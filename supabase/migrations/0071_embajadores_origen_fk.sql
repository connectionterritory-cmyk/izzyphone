-- ============================================================
-- 0071_embajadores_origen_fk.sql
--
-- Objetivo:
--   Vincular embajadores con su entidad de origen (lead o
--   cliente) mediante FKs reales, corrigiendo el bug de
--   integridad de negocio donde la tabla duplicaba datos de
--   identidad sin apuntar al registro de origen.
--
-- Contexto de negocio:
--   Un embajador no es una entidad independiente: es un rol
--   que toma un lead o cliente ya existente en el sistema.
--   El origen es siempre lead O cliente — nunca ambos, y el
--   conjunto es cerrado.
--
-- Fase: ADITIVA
--   • Agrega lead_id y cliente_id como columnas nullable.
--   • Agrega FKs reales con ON DELETE SET NULL.
--   • Agrega constraint de exclusión mutua.
--   • Agrega índices parciales para JOINs por origen.
--   • Marca campos de identidad históricos como LEGACY CACHE
--     via COMMENT ON COLUMN (no los elimina).
--   • No hace backfill — registros históricos sin origen
--     vinculado son válidos y permanecen con NULLs en ambas
--     FKs. El backfill es responsabilidad del operador cuando
--     el origen sea identificable.
--
-- Tablas afectadas:
--   public.embajadores
--
-- AUDIT QUERIES y ROLLBACK al final del archivo.
-- ============================================================

begin;
-- ── 1. Agregar lead_id ────────────────────────────────────────
--
-- ON DELETE SET NULL: si el lead es eliminado (o borrado lógico
-- y luego purgado), el embajador no se pierde — queda con
-- lead_id = NULL como registro histórico.

alter table public.embajadores
  add column if not exists lead_id uuid
    references public.leads(id) on delete set null;
-- ── 2. Agregar cliente_id ─────────────────────────────────────
--
-- Mismo criterio que lead_id.

alter table public.embajadores
  add column if not exists cliente_id uuid
    references public.clientes(id) on delete set null;
-- ── 3. Constraint de exclusión mutua ─────────────────────────
--
-- El origen es lead O cliente, nunca ambos.
-- El conjunto es cerrado: no se añadirán nuevos tipos de origen.
-- Ambos pueden ser NULL (registros históricos sin origen vinculado).
--
-- Nombre semántico: embajador_origen_unico

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where  conrelid = 'public.embajadores'::regclass
      and  conname  = 'embajador_origen_unico'
  ) then
    alter table public.embajadores
      add constraint embajador_origen_unico
      check (
        not (lead_id is not null and cliente_id is not null)
      );
  end if;
end $$;
-- ── 4. Índices parciales por origen ──────────────────────────
--
-- Parciales (WHERE IS NOT NULL): la mayoría de filas en la
-- transición tendrán NULLs, no tiene sentido indexar esas.
-- Cuando el backfill operacional avance, los índices cubrirán
-- la porción de datos que realmente se consulta por origen.

create index if not exists embajadores_lead_id_idx
  on public.embajadores (lead_id)
  where lead_id is not null;
create index if not exists embajadores_cliente_id_idx
  on public.embajadores (cliente_id)
  where cliente_id is not null;
-- ── 5. Documentar campos de identidad legacy ──────────────────
--
-- Los campos nombre, apellido, email, telefono, fecha_nacimiento
-- pasan a ser LEGACY CACHE. La fuente canónica de identidad es el
-- lead o cliente al que apunta lead_id / cliente_id.
--
-- Se conservan para:
--   a) Registros históricos sin origen vinculado.
--   b) Denormalización de acceso rápido mientras dure la transición.
--
-- No se eliminan en esta migración.

comment on column public.embajadores.nombre is
  'LEGACY CACHE: fuente canónica es leads o clientes via lead_id/cliente_id. '
  'Se mantiene para registros históricos sin origen vinculado.';
comment on column public.embajadores.apellido is
  'LEGACY CACHE: fuente canónica es leads o clientes via lead_id/cliente_id. '
  'Se mantiene para registros históricos sin origen vinculado.';
comment on column public.embajadores.email is
  'LEGACY CACHE: fuente canónica es leads o clientes via lead_id/cliente_id. '
  'Se mantiene para registros históricos sin origen vinculado.';
comment on column public.embajadores.telefono is
  'LEGACY CACHE: fuente canónica es leads o clientes via lead_id/cliente_id. '
  'Se mantiene para registros históricos sin origen vinculado.';
comment on column public.embajadores.fecha_nacimiento is
  'LEGACY CACHE: fuente canónica es leads o clientes via lead_id/cliente_id. '
  'Se mantiene para registros históricos sin origen vinculado.';
-- ── 6. Documentar las nuevas columnas de origen ───────────────

comment on column public.embajadores.lead_id is
  'FK al lead de origen. Exclusivo con cliente_id (constraint embajador_origen_unico). '
  'NULL en registros históricos sin origen vinculado.';
comment on column public.embajadores.cliente_id is
  'FK al cliente de origen. Exclusivo con lead_id (constraint embajador_origen_unico). '
  'NULL en registros históricos sin origen vinculado.';
commit;
-- ============================================================
-- AUDIT QUERIES
-- Ejecutar después de aplicar para verificar el estado de la BD.
-- ============================================================
--
-- 1. Cuántos embajadores tienen origen vinculado vs. sin vincular:
--
-- select
--   count(*) filter (where lead_id    is not null) as con_lead,
--   count(*) filter (where cliente_id is not null) as con_cliente,
--   count(*) filter (where lead_id is null and cliente_id is null) as sin_origen,
--   count(*) as total
-- from public.embajadores;
--
-- 2. Verificar que el constraint funciona (debe fallar con error):
--
-- insert into public.embajadores (nombre, lead_id, cliente_id)
-- values ('Test', gen_random_uuid(), gen_random_uuid());
-- → debe lanzar: ERROR: new row for relation "embajadores" violates
--   check constraint "embajador_origen_unico"
--
-- 3. Detectar duplicidad potencial para backfill futuro
-- (leads con mismo teléfono que embajadores sin lead_id):
--
-- select
--   e.id          as embajador_id,
--   e.nombre      as emb_nombre,
--   e.telefono    as emb_telefono,
--   l.id          as lead_candidato_id,
--   l.nombre      as lead_nombre
-- from public.embajadores e
-- join public.leads l
--   on regexp_replace(l.telefono, '[^0-9]', '', 'g')
--    = regexp_replace(e.telefono, '[^0-9]', '', 'g')
--  and l.deleted_at is null
-- where e.lead_id    is null
--   and e.cliente_id is null
--   and e.telefono   is not null
-- order by e.created_at desc;
--
-- ============================================================
-- ROLLBACK
-- ============================================================
-- begin;
--
-- alter table public.embajadores
--   drop constraint if exists embajador_origen_unico,
--   drop column    if exists lead_id,
--   drop column    if exists cliente_id;
--
-- drop index if exists public.embajadores_lead_id_idx;
-- drop index if exists public.embajadores_cliente_id_idx;
--
-- -- Los COMMENT ON COLUMN no tienen rollback necesario
-- -- (vuelven a NULL al dropear las columnas o se pueden limpiar así):
-- -- comment on column public.embajadores.nombre           is null;
-- -- comment on column public.embajadores.apellido         is null;
-- -- comment on column public.embajadores.email            is null;
-- -- comment on column public.embajadores.telefono         is null;
-- -- comment on column public.embajadores.fecha_nacimiento is null;
--
-- commit;
-- ============================================================;
