begin;
alter table public.ci_activaciones enable row level security;
alter table public.ci_referidos enable row level security;
drop policy if exists ci_activaciones_select on public.ci_activaciones;
create policy ci_activaciones_select on public.ci_activaciones
for select to authenticated
using (
  owner_id = auth.uid() or representante_id = auth.uid()
);
drop policy if exists ci_activaciones_insert on public.ci_activaciones;
create policy ci_activaciones_insert on public.ci_activaciones
for insert to authenticated
with check (
  owner_id = auth.uid() or representante_id = auth.uid()
);
drop policy if exists ci_referidos_select on public.ci_referidos;
create policy ci_referidos_select on public.ci_referidos
for select to authenticated
using (
  exists (
    select 1
    from public.ci_activaciones a
    where a.id = activacion_id
      and (a.owner_id = auth.uid() or a.representante_id = auth.uid())
  )
);
drop policy if exists ci_referidos_insert on public.ci_referidos;
create policy ci_referidos_insert on public.ci_referidos
for insert to authenticated
with check (
  exists (
    select 1
    from public.ci_activaciones a
    where a.id = activacion_id
      and (a.owner_id = auth.uid() or a.representante_id = auth.uid())
  )
);
commit;
