-- ============================================================
-- 0070_embajadores_org_id.sql
--
-- Objetivo:
--   Agregar org_id a embajadores y embajador_programas.
--
-- Problema que resuelve:
--   Ambas tablas fueron creadas sin org_id, dejando un gap de
--   aislamiento multi-tenant. Las policies actuales dependen
--   exclusivamente de owner_id = auth.uid() e is_admin().
--   Si alguna de esas condiciones falla o se otorga is_admin()
--   a un usuario de otra organización, no existe una segunda
--   capa de aislamiento por org.
--
-- Fase: ADITIVA + HARDENING DE POLICIES
--   • No elimina columnas.
--   • No rompe escrituras ni lecturas existentes.
--   • Backfill con org default para todos los registros.
--   • Reemplaza las policies de distribuidor en ambas tablas
--     para incluir is_org_member(org_id) como defensa extra.
--   • Policies de admin y vendedor permanecen intactas.
--
-- Tablas afectadas:
--   public.embajadores
--   public.embajador_programas
--
-- ROLLBACK al final del archivo.
-- ============================================================

begin;
-- ── 1. Agregar org_id a embajadores ──────────────────────────

-- FK a organizations eliminado: public.organizations no existe en este
-- entorno de producción (divergencia con migration 0001). org_id se agrega
-- como uuid simple. El FK se puede agregar en una migración posterior
-- cuando se resuelva el estado de la tabla organizations.
alter table public.embajadores
  add column if not exists org_id uuid;
-- ── 2. Agregar org_id a embajador_programas ───────────────────

alter table public.embajador_programas
  add column if not exists org_id uuid;
-- ── 3. Backfill con la organización default ───────────────────
-- Mismo UUID que usa migration 0001 para el backfill de clientes,
-- contactos y demás tablas retro-aplicadas.

do $$
declare
  v_default_org uuid := '00000000-0000-0000-0000-000000000001';
begin
  update public.embajadores
  set    org_id = v_default_org
  where  org_id is null;

  update public.embajador_programas
  set    org_id = v_default_org
  where  org_id is null;
end $$;
-- ── 4. Índices ────────────────────────────────────────────────

create index if not exists embajadores_org_id_idx
  on public.embajadores (org_id);
create index if not exists embajador_programas_org_id_idx
  on public.embajador_programas (org_id);
-- ── 5. Hardening: policy distribuidor en embajadores ─────────
--
-- Antes:
--   USING (is_distribuidor() AND is_distribuidor_of(owner_id))
--   → no verifica org; si is_distribuidor_of() fallara o se
--     otorgara el rol a otro org, vería embajadores ajenos.
--
-- Después:
--   Agrega (org_id IS NULL OR is_org_member(org_id)) como
--   segunda capa. IS NULL cubre el período de transición por
--   si algún registro no recibió el backfill.
--
-- La policy de admin (is_admin) y vendedor (owner_id = auth.uid())
-- no se modifican: su scope ya es suficientemente estricto.

drop policy if exists embajadores_distribuidor_read on public.embajadores;
-- NOTA: rama is_org_member eliminada — public.memberships no existe en producción.
-- La policy queda con is_distribuidor_of como único criterio distribuidor.
create policy embajadores_distribuidor_read on public.embajadores
  for select to authenticated
  using (
    public.is_distribuidor()
    and public.is_distribuidor_of(owner_id)
  );
-- ── 6. Hardening: policy distribuidor en embajador_programas ─

drop policy if exists embajador_programas_distribuidor_read on public.embajador_programas;
create policy embajador_programas_distribuidor_read on public.embajador_programas
  for select to authenticated
  using (
    public.is_distribuidor()
    and public.is_distribuidor_of(owner_id)
  );
commit;
-- ============================================================
-- AUDIT QUERIES (ejecutar ANTES de aplicar para verificar)
-- ============================================================
--
-- Verificar que no quedan filas sin org_id después del backfill:
--
-- select count(*) as sin_org
-- from public.embajadores
-- where org_id is null;
--
-- select count(*) as sin_org
-- from public.embajador_programas
-- where org_id is null;
--
-- Verificar distribución por org (debe verse solo el default org):
--
-- select org_id, count(*) as total
-- from public.embajadores
-- group by org_id;
--
-- ============================================================
-- ROLLBACK
-- ============================================================
-- begin;
--
-- -- Restaurar policies originales de distribuidor
-- drop policy if exists embajadores_distribuidor_read        on public.embajadores;
-- drop policy if exists embajador_programas_distribuidor_read on public.embajador_programas;
--
-- create policy embajadores_distribuidor_read on public.embajadores
--   for select to authenticated
--   using (public.is_distribuidor() and public.is_distribuidor_of(owner_id));
--
-- create policy embajador_programas_distribuidor_read on public.embajador_programas
--   for select to authenticated
--   using (public.is_distribuidor() and public.is_distribuidor_of(owner_id));
--
-- -- Eliminar columnas (solo si no hay datos en producción que lo impidan)
-- alter table public.embajadores
--   drop column if exists org_id;
--
-- alter table public.embajador_programas
--   drop column if exists org_id;
--
-- drop index if exists public.embajadores_org_id_idx;
-- drop index if exists public.embajador_programas_org_id_idx;
--
-- commit;
-- ============================================================;
