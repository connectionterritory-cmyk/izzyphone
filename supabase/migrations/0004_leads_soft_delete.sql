begin;
alter table public.leads
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid,
  add column if not exists deleted_reason text;
alter table public.leads
  add constraint leads_deleted_reason_required
  check (
    deleted_at is null
    or (deleted_reason is not null and length(trim(deleted_reason)) > 0)
  );
create index if not exists leads_deleted_at_idx on public.leads (deleted_at);
drop policy if exists leads_vendedor_all on public.leads;
create policy leads_vendedor_all on public.leads
  to authenticated
  using (owner_id = auth.uid() and deleted_at is null)
  with check (owner_id = auth.uid() and deleted_at is null);
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
commit;
