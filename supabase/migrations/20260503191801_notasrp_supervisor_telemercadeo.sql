-- Migration 0023: Allow supervisor_telemercadeo to read/insert notasrp
begin;
drop policy if exists notasrp_telemercadeo_read on public.notasrp;
create policy notasrp_telemercadeo_read on public.notasrp
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol in ('telemercadeo', 'supervisor_telemercadeo')
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = notasrp.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
drop policy if exists notasrp_telemercadeo_insert on public.notasrp;
create policy notasrp_telemercadeo_insert on public.notasrp
  for insert to authenticated
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol in ('telemercadeo', 'supervisor_telemercadeo')
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = notasrp.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
commit;
