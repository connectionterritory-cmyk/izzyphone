begin;
create extension if not exists "pgcrypto";
create table if not exists public.plan_limits (
  plan text primary key,
  max_users integer not null default 3,
  max_storage_mb integer not null default 1024,
  max_records integer not null default 5000,
  features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique,
  plan text not null default 'Free' references public.plan_limits(plan),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.org_branding (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  org_name text,
  logo_url text,
  primary_color text,
  secondary_color text,
  updated_at timestamptz not null default now()
);
create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member',
  created_at timestamptz not null default now()
);
create unique index if not exists memberships_org_user_idx on public.memberships (org_id, user_id);
create index if not exists memberships_user_idx on public.memberships (user_id);
insert into public.plan_limits (plan, max_users, max_storage_mb, max_records, features)
values
  ('Free', 3, 1024, 5000, '{"branding": true, "reports": false, "dfp": false}'),
  ('Basico', 10, 5120, 25000, '{"branding": true, "reports": true, "dfp": false}'),
  ('Pro', 30, 20480, 100000, '{"branding": true, "reports": true, "dfp": true}'),
  ('Elite', 100, 102400, 500000, '{"branding": true, "reports": true, "dfp": true}')
on conflict (plan) do nothing;
alter table if exists public.clientes add column if not exists org_id uuid;
alter table if exists public.contactos add column if not exists org_id uuid;
alter table if exists public.oportunidades add column if not exists org_id uuid;
alter table if exists public.ordenesrp add column if not exists org_id uuid;
alter table if exists public.ordenitemsrp add column if not exists org_id uuid;
alter table if exists public.enviosrp add column if not exists org_id uuid;
alter table if exists public.cuentarp add column if not exists org_id uuid;
alter table if exists public.transaccionesrp add column if not exists org_id uuid;
alter table if exists public.mensajescrm add column if not exists org_id uuid;
alter table if exists public.notasrp add column if not exists org_id uuid;
alter table if exists public.auditoriaacciones add column if not exists org_id uuid;
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'clientes') then
    execute 'create index if not exists clientes_org_id_idx on public.clientes (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'contactos') then
    execute 'create index if not exists contactos_org_id_idx on public.contactos (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'oportunidades') then
    execute 'create index if not exists oportunidades_org_id_idx on public.oportunidades (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'ordenesrp') then
    execute 'create index if not exists ordenesrp_org_id_idx on public.ordenesrp (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'ordenitemsrp') then
    execute 'create index if not exists ordenitemsrp_org_id_idx on public.ordenitemsrp (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'enviosrp') then
    execute 'create index if not exists enviosrp_org_id_idx on public.enviosrp (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'cuentarp') then
    execute 'create index if not exists cuentarp_org_id_idx on public.cuentarp (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'transaccionesrp') then
    execute 'create index if not exists transaccionesrp_org_id_idx on public.transaccionesrp (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'mensajescrm') then
    execute 'create index if not exists mensajescrm_org_id_idx on public.mensajescrm (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'notasrp') then
    execute 'create index if not exists notasrp_org_id_idx on public.notasrp (org_id)';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'auditoriaacciones') then
    execute 'create index if not exists auditoriaacciones_org_id_idx on public.auditoriaacciones (org_id)';
  end if;
end $$;
create or replace function public.is_org_member(check_org uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.memberships m
    where m.org_id = check_org
      and m.user_id = auth.uid()
  );
$$;
create or replace function public.is_org_admin(check_org uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.memberships m
    where m.org_id = check_org
      and m.user_id = auth.uid()
      and m.role in ('owner', 'admin')
  );
$$;
do $$
declare
  default_org uuid := '00000000-0000-0000-0000-000000000001';
begin
  insert into public.organizations (id, name, slug, plan)
  values (default_org, 'FlowSuiteCRM Default', 'flowsuitecrm-default', 'Free')
  on conflict (id) do nothing;

  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'profiles'
  ) then
    insert into public.memberships (org_id, user_id, role)
    select default_org, p.id, 'owner'
    from public.profiles p
    where not exists (
      select 1 from public.memberships m
      where m.user_id = p.id
    )
    on conflict (org_id, user_id) do nothing;
  end if;

  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'clientes') then
    update public.clientes set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'contactos') then
    update public.contactos set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'oportunidades') then
    update public.oportunidades set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'ordenesrp') then
    update public.ordenesrp set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'ordenitemsrp') then
    update public.ordenitemsrp set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'enviosrp') then
    update public.enviosrp set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'cuentarp') then
    update public.cuentarp set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'transaccionesrp') then
    update public.transaccionesrp set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'mensajescrm') then
    update public.mensajescrm set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'notasrp') then
    update public.notasrp set org_id = default_org where org_id is null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'auditoriaacciones') then
    update public.auditoriaacciones set org_id = default_org where org_id is null;
  end if;
end $$;
alter table if exists public.organizations enable row level security;
alter table if exists public.memberships enable row level security;
alter table if exists public.org_branding enable row level security;
alter table if exists public.plan_limits enable row level security;
alter table if exists public.clientes enable row level security;
alter table if exists public.contactos enable row level security;
alter table if exists public.oportunidades enable row level security;
alter table if exists public.ordenesrp enable row level security;
alter table if exists public.ordenitemsrp enable row level security;
alter table if exists public.enviosrp enable row level security;
alter table if exists public.cuentarp enable row level security;
alter table if exists public.transaccionesrp enable row level security;
alter table if exists public.mensajescrm enable row level security;
alter table if exists public.notasrp enable row level security;
alter table if exists public.auditoriaacciones enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'memberships' and policyname = 'memberships_read_own'
  ) then
    create policy memberships_read_own on public.memberships
      for select
      using (user_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'organizations' and policyname = 'organizations_read'
  ) then
    create policy organizations_read on public.organizations
      for select
      using (public.is_org_member(id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'organizations' and policyname = 'organizations_update_admin'
  ) then
    create policy organizations_update_admin on public.organizations
      for update
      using (public.is_org_admin(id))
      with check (public.is_org_admin(id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'org_branding' and policyname = 'org_branding_read'
  ) then
    create policy org_branding_read on public.org_branding
      for select
      using (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'org_branding' and policyname = 'org_branding_write_admin'
  ) then
    create policy org_branding_write_admin on public.org_branding
      for insert
      with check (public.is_org_admin(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'org_branding' and policyname = 'org_branding_update_admin'
  ) then
    create policy org_branding_update_admin on public.org_branding
      for update
      using (public.is_org_admin(org_id))
      with check (public.is_org_admin(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'plan_limits' and policyname = 'plan_limits_read'
  ) then
    create policy plan_limits_read on public.plan_limits
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'clientes' and policyname = 'clientes_org_member'
  ) then
    create policy clientes_org_member on public.clientes
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'contactos' and policyname = 'contactos_org_member'
  ) then
    create policy contactos_org_member on public.contactos
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'oportunidades' and policyname = 'oportunidades_org_member'
  ) then
    create policy oportunidades_org_member on public.oportunidades
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'ordenesrp' and policyname = 'ordenesrp_org_member'
  ) then
    create policy ordenesrp_org_member on public.ordenesrp
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'ordenitemsrp' and policyname = 'ordenitemsrp_org_member'
  ) then
    create policy ordenitemsrp_org_member on public.ordenitemsrp
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'enviosrp' and policyname = 'enviosrp_org_member'
  ) then
    create policy enviosrp_org_member on public.enviosrp
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cuentarp' and policyname = 'cuentarp_org_member'
  ) then
    create policy cuentarp_org_member on public.cuentarp
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'transaccionesrp' and policyname = 'transaccionesrp_org_member'
  ) then
    create policy transaccionesrp_org_member on public.transaccionesrp
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'mensajescrm' and policyname = 'mensajescrm_org_member'
  ) then
    create policy mensajescrm_org_member on public.mensajescrm
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'notasrp' and policyname = 'notasrp_org_member'
  ) then
    create policy notasrp_org_member on public.notasrp
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'auditoriaacciones' and policyname = 'auditoriaacciones_org_member'
  ) then
    create policy auditoriaacciones_org_member on public.auditoriaacciones
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;
end $$;
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'contactos') then
    execute 'create or replace view public.contactos_canonical as select * from public.contactos';
  end if;
end $$;
commit;
