-- ============================================================
-- 0058_catalogo_vendedor_view.sql
-- Creates v_catalogo_vendedor view, product_images table,
-- and adds reemplazado_por_id to productos.
-- ============================================================

begin;
-- ── 1. Add reemplazado_por_id column ───────────────────────
alter table public.productos
  add column if not exists reemplazado_por_id uuid references public.productos(id);
-- ── 2. Create v_catalogo_vendedor view ─────────────────────
-- Maps existing column names to what the frontend expects.
-- Includes a self-join for replacement product info.
drop view if exists public.v_catalogo_vendedor;
create view public.v_catalogo_vendedor
  with (security_invoker = true)
as
  select
    p.id,
    p.codigo,
    p.nombre,
    p.categoria,
    p.categoria_principal,
    p.subcategoria,
    p.linea_producto,
    p.precio        as precio_publico,
    p.foto_url      as foto_principal_url,
    p.activo,
    p.estado,
    p.descripcion_corta,
    p.descripcion_larga,
    p.beneficios,
    p.reemplazado_por_id,
    r.codigo        as reemplazado_por_codigo,
    r.nombre        as reemplazado_por_nombre,
    p.cuota_minima,
    p.con_financiamiento,
    p.visible_catalogo,
    cast(null as text) as foto_galeria_url
  from public.productos p
  left join public.productos r on r.id = p.reemplazado_por_id
  where p.activo = true;
grant select on public.v_catalogo_vendedor to authenticated;
-- ── 3. Create product_images table ─────────────────────────
create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.productos(id) on delete cascade,
  url text not null,
  orden int not null default 0,
  alt_text text,
  created_at timestamptz not null default now()
);
create index if not exists idx_product_images_product_id
  on public.product_images(product_id);
-- RLS: same as productos — admin/distribuidor full, others read
alter table public.product_images enable row level security;
create policy product_images_select on public.product_images
  for select to authenticated
  using (true);
create policy product_images_admin_insert on public.product_images
  for insert to authenticated
  with check (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol in ('admin', 'distribuidor')
    )
  );
create policy product_images_admin_update on public.product_images
  for update to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol in ('admin', 'distribuidor')
    )
  );
create policy product_images_admin_delete on public.product_images
  for delete to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol in ('admin', 'distribuidor')
    )
  );
commit;
