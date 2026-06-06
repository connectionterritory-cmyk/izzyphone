begin;
alter table public.tele_vendedor_assignments enable row level security;
drop policy if exists tele_assignments_read on public.tele_vendedor_assignments;
create policy tele_assignments_read on public.tele_vendedor_assignments
  for select to authenticated
  using (public.is_admin() or public.is_distribuidor() or tele_id = auth.uid());
drop policy if exists tele_assignments_insert on public.tele_vendedor_assignments;
create policy tele_assignments_insert on public.tele_vendedor_assignments
  for insert to authenticated
  with check (public.is_admin() or public.is_distribuidor());
drop policy if exists tele_assignments_delete on public.tele_vendedor_assignments;
create policy tele_assignments_delete on public.tele_vendedor_assignments
  for delete to authenticated
  using (public.is_admin() or public.is_distribuidor());
commit;
