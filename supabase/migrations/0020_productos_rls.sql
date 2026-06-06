alter table public.productos enable row level security;
drop policy if exists productos_admin_distribuidor_select on public.productos;
drop policy if exists productos_admin_distribuidor_insert on public.productos;
drop policy if exists productos_admin_distribuidor_update on public.productos;
drop policy if exists productos_admin_distribuidor_delete on public.productos;
create policy productos_admin_distribuidor_select on public.productos
  for select
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
create policy productos_admin_distribuidor_insert on public.productos
  for insert
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
create policy productos_admin_distribuidor_update on public.productos
  for update
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
  for delete
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
