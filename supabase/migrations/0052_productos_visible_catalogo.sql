-- ============================================================
-- 0052_productos_visible_catalogo.sql
-- Add visible_catalogo boolean to productos.
-- Rebuild v_productos_publicos to filter by visible_catalogo.
-- ============================================================

begin;
-- 1. Add column (DEFAULT true → all existing products remain visible)
alter table public.productos
  add column if not exists visible_catalogo boolean not null default true;
-- 2. Partial index for fast public-catalog queries
create index if not exists idx_productos_visible_catalogo
  on public.productos(id)
  where visible_catalogo = true;
-- 3. Recreate v_productos_publicos — same columns as original (0044)
--    plus visible_catalogo, filtered to active + visible only.
drop view if exists public.v_productos_publicos;
create view public.v_productos_publicos
  with (security_invoker = true)
as
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
    visible_catalogo,
    created_at
  from public.productos
  where activo = true
    and visible_catalogo = true;
grant select on public.v_productos_publicos to authenticated;
commit;
