begin;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'leads'
      and policyname = 'leads_admin_all'
  ) then
    create policy leads_admin_all on public.leads
      to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'leads'
      and policyname = 'leads_distribuidor_update'
  ) then
    create policy leads_distribuidor_update on public.leads
      for update to authenticated
      using (public.is_distribuidor() and public.is_distribuidor_of(owner_id))
      with check (public.is_distribuidor() and public.is_distribuidor_of(owner_id));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'leads'
      and policyname = 'leads_vendedor_update_soft_delete'
  ) then
    create policy leads_vendedor_update_soft_delete on public.leads
      for update to authenticated
      using (owner_id = auth.uid())
      with check (owner_id = auth.uid());
  end if;
end $$;
commit;
