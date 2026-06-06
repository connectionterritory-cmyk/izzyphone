-- ============================================================
-- 0044_ventas_productos_assignments_rls.sql
-- RLS hardening for ventas, productos, tele_vendedor_assignments
-- ============================================================

begin;
-- -----------------------------
-- Ventas policies
-- -----------------------------
alter table public.ventas enable row level security;
drop policy if exists ventas_admin_all on public.ventas;
drop policy if exists ventas_distribuidor_all on public.ventas;
drop policy if exists ventas_vendedor_all on public.ventas;
drop policy if exists ventas_supervisor_tele_read on public.ventas;
drop policy if exists ventas_tele_read on public.ventas;
create policy ventas_admin_all on public.ventas
  for all to authenticated
  using (public.is_admin() and public.is_org_member(org_id))
  with check (public.is_admin() and public.is_org_member(org_id));
create policy ventas_distribuidor_all on public.ventas
  for all to authenticated
  using (public.is_distribuidor() and public.is_org_member(org_id))
  with check (public.is_distribuidor() and public.is_org_member(org_id));
create policy ventas_vendedor_all on public.ventas
  for all to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
    and public.is_org_member(org_id)
  )
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
    and public.is_org_member(org_id)
  );
create policy ventas_supervisor_tele_read on public.ventas
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'supervisor_telemercadeo'
    )
    and public.is_org_member(org_id)
  );
create policy ventas_tele_read on public.ventas
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    and exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = ventas.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
    and public.is_org_member(org_id)
  );
-- -----------------------------
-- Productos policies
-- -----------------------------
alter table public.productos enable row level security;
drop policy if exists productos_admin_distribuidor_select on public.productos;
drop policy if exists productos_admin_distribuidor_insert on public.productos;
drop policy if exists productos_admin_distribuidor_update on public.productos;
drop policy if exists productos_admin_distribuidor_delete on public.productos;
create policy productos_admin_distribuidor_select on public.productos
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
create policy productos_admin_distribuidor_insert on public.productos
  for insert to authenticated
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
create policy productos_admin_distribuidor_update on public.productos
  for update to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  )
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
create policy productos_admin_distribuidor_delete on public.productos
  for delete to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
-- Public view without cost columns for non-admin roles
create or replace view public.v_productos_publicos as
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
grant select on public.v_productos_publicos to authenticated;
-- -----------------------------
-- Tele vendedor assignments policies
-- -----------------------------
alter table public.tele_vendedor_assignments enable row level security;
drop policy if exists tele_assignments_read on public.tele_vendedor_assignments;
drop policy if exists tele_assignments_insert on public.tele_vendedor_assignments;
drop policy if exists tele_assignments_update on public.tele_vendedor_assignments;
drop policy if exists tele_assignments_delete on public.tele_vendedor_assignments;
create policy tele_assignments_read on public.tele_vendedor_assignments
  for select to authenticated
  using (
    public.is_admin()
    or public.is_distribuidor()
    or exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'supervisor_telemercadeo'
    )
    or tele_id = auth.uid()
  );
create policy tele_assignments_insert on public.tele_vendedor_assignments
  for insert to authenticated
  with check (public.is_admin() or public.is_distribuidor());
create policy tele_assignments_update on public.tele_vendedor_assignments
  for update to authenticated
  using (public.is_admin() or public.is_distribuidor())
  with check (public.is_admin() or public.is_distribuidor());
create policy tele_assignments_delete on public.tele_vendedor_assignments
  for delete to authenticated
  using (public.is_admin() or public.is_distribuidor());
commit;
