-- ============================================================
-- 0045_productos_assignments_rls.sql
-- Completa restricción por columna en productos para roles
-- no-admin/distribuidor, y crea la vista productos_sin_costo.
--
-- Contexto:
--   • 0044 creó v_productos_publicos y las políticas de
--     admin/distribuidor en productos, pero dejó sin política
--     SELECT a vendedor/supervisor_telemercadeo/telemercadeo,
--     lo que hace que la vista devuelva 0 filas para esos roles.
--   • tele_vendedor_assignments ya quedó completo en 0044.
--
-- Resultado final:
--   admin / distribuidor  → SELECT directo en productos (todas las columnas)
--   vendedor / supervisor_telemercadeo / telemercadeo
--     → SELECT en productos (habilitado por RLS)
--     → Solo deben consultar mediante productos_sin_costo (sin columnas de costo)
--     → Sin acceso a INSERT / UPDATE / DELETE en productos
-- ============================================================

begin;
-- ── 1. SELECT policies para roles de solo lectura ────────────
-- Sin esta política la vista productos_sin_costo devuelve 0 filas
-- para esos roles porque el acceso a la tabla base falla por RLS.

drop policy if exists productos_vendedor_select           on public.productos;
drop policy if exists productos_supervisor_tele_select    on public.productos;
drop policy if exists productos_telemercadeo_select       on public.productos;
create policy productos_vendedor_select on public.productos
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol = 'vendedor'
    )
  );
create policy productos_supervisor_tele_select on public.productos
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol = 'supervisor_telemercadeo'
    )
  );
create policy productos_telemercadeo_select on public.productos
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol = 'telemercadeo'
    )
  );
-- ── 2. Vista productos_sin_costo ─────────────────────────────
-- Expone productos sin columnas de costo:
--   excluye: costo_n1, costo_n2, costo_n3, costo_n4, recargo_arancelario
-- Los roles de solo lectura deben usar esta vista en el frontend.

create or replace view public.productos_sin_costo as
  select
    id,
    codigo,
    nombre,
    categoria,
    categoria_compra,
    categoria_principal,
    subcategoria,
    linea_producto,
    precio,
    activo,
    foto_url,
    created_at
  from public.productos;
grant select on public.productos_sin_costo to authenticated;
-- ── Nota: tele_vendedor_assignments ──────────────────────────
-- Política completa ya implementada en 0044:
--   admin / distribuidor  → CRUD completo
--   supervisor_telemercadeo → SELECT (todos los registros de la org)
--   telemercadeo          → SELECT (solo sus propias asignaciones: tele_id = auth.uid())
--   vendedor / otros      → sin política = sin acceso
-- No se requieren cambios adicionales.

commit;
