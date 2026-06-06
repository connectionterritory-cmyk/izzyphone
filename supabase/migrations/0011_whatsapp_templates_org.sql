begin;
create table if not exists public.whatsapp_templates_org (
  id uuid primary key default gen_random_uuid(),
  organizacion text not null,
  template_key text not null,
  label text not null,
  message text not null,
  category text not null default 'system',
  is_system boolean not null default true,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists whatsapp_templates_org_org_key_idx
  on public.whatsapp_templates_org (organizacion, template_key);
create index if not exists whatsapp_templates_org_organizacion_idx
  on public.whatsapp_templates_org (organizacion);
drop trigger if exists set_updated_at_whatsapp_templates_org on public.whatsapp_templates_org;
create trigger set_updated_at_whatsapp_templates_org
  before update on public.whatsapp_templates_org
  for each row execute function public.set_updated_at();
alter table public.whatsapp_templates_org enable row level security;
drop policy if exists whatsapp_templates_org_select on public.whatsapp_templates_org;
create policy whatsapp_templates_org_select on public.whatsapp_templates_org
  for select to authenticated
  using (
    exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.organizacion is not distinct from whatsapp_templates_org.organizacion
    )
  );
drop policy if exists whatsapp_templates_org_insert on public.whatsapp_templates_org;
create policy whatsapp_templates_org_insert on public.whatsapp_templates_org
  for insert to authenticated
  with check (
    (public.is_admin() or public.is_distribuidor())
    and exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.organizacion is not distinct from whatsapp_templates_org.organizacion
    )
  );
drop policy if exists whatsapp_templates_org_update on public.whatsapp_templates_org;
create policy whatsapp_templates_org_update on public.whatsapp_templates_org
  for update to authenticated
  using (
    (public.is_admin() or public.is_distribuidor())
    and exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.organizacion is not distinct from whatsapp_templates_org.organizacion
    )
  )
  with check (
    (public.is_admin() or public.is_distribuidor())
    and exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.organizacion is not distinct from whatsapp_templates_org.organizacion
    )
  );
drop policy if exists whatsapp_templates_org_delete on public.whatsapp_templates_org;
create policy whatsapp_templates_org_delete on public.whatsapp_templates_org
  for delete to authenticated
  using (
    (public.is_admin() or public.is_distribuidor())
    and exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.organizacion is not distinct from whatsapp_templates_org.organizacion
    )
  );
create or replace function public.get_distributor_phone()
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  _rol public.usuario_rol;
  _telefono text;
  _distribuidor_id uuid;
begin
  select rol, telefono, distribuidor_padre_id
    into _rol, _telefono, _distribuidor_id
  from public.usuarios
  where id = auth.uid();

  if _rol in ('admin', 'distribuidor') then
    return coalesce(_telefono, '');
  end if;

  if _distribuidor_id is not null then
    select telefono into _telefono
    from public.usuarios
    where id = _distribuidor_id;
    return coalesce(_telefono, '');
  end if;

  return coalesce(_telefono, '');
end;
$$;
grant execute on function public.get_distributor_phone() to authenticated;
commit;
