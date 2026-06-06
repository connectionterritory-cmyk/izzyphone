begin;

-- 0147_cob_pagos_operational_table
-- Evoluciona/normaliza public.cob_pagos como tabla operativa de pagos
-- para cartera / cargo de vuelta / DFP, sin tocar cob_financial_ledger.

create table if not exists public.cob_pagos (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid not null,
  cliente_id            uuid not null references public.clientes(id),
  cargo_vuelta_case_id  uuid references public.cargo_vuelta_cases(id) on delete set null,
  revolving_account_id  uuid,
  ptp_id                uuid references public.cob_ptps(id) on delete set null,
  monto                 numeric(12,2) not null check (monto > 0),
  moneda                text not null default 'USD',
  fecha_pago            date not null default current_date,
  metodo_pago           text not null default 'otro',
  referencia_externa    text,
  comprobante_url       text,
  notas                 text,
  estado                text not null default 'registrado',
  source                text not null default 'manual',
  external_id           text,
  created_by            uuid default auth.uid(),
  updated_by            uuid,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- Compatibilidad con esquema legacy 0107.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'cob_pagos'
      and column_name = 'case_id'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'cob_pagos'
      and column_name = 'cargo_vuelta_case_id'
  ) then
    execute 'alter table public.cob_pagos rename column case_id to cargo_vuelta_case_id';
  end if;
end $$;

alter table public.cob_pagos add column if not exists revolving_account_id uuid;
alter table public.cob_pagos add column if not exists moneda text;
alter table public.cob_pagos add column if not exists referencia_externa text;
alter table public.cob_pagos add column if not exists comprobante_url text;
alter table public.cob_pagos add column if not exists estado text;
alter table public.cob_pagos add column if not exists source text;
alter table public.cob_pagos add column if not exists external_id text;
alter table public.cob_pagos add column if not exists created_by uuid;
alter table public.cob_pagos add column if not exists updated_by uuid;

-- Si existe naming legacy, lo migramos al naming operativo.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_pagos' and column_name = 'referencia'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_pagos' and column_name = 'referencia_externa'
  ) then
    execute 'alter table public.cob_pagos rename column referencia to referencia_externa';
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_pagos' and column_name = 'creado_por'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_pagos' and column_name = 'created_by'
  ) then
    execute 'alter table public.cob_pagos rename column creado_por to created_by';
  end if;
end $$;

update public.cob_pagos
set created_by = coalesce(created_by, auth.uid())
where created_by is null;

update public.cob_pagos
set moneda = coalesce(moneda, 'USD')
where moneda is null;

update public.cob_pagos
set estado = coalesce(estado, 'registrado')
where estado is null;

update public.cob_pagos
set source = coalesce(source, 'manual')
where source is null;

-- Drop constraint legacy antes de normalizar valores (el constraint original solo permite valores en español).
alter table public.cob_pagos drop constraint if exists cob_pagos_metodo_pago_check;

-- Normalización de método de pago legacy -> catálogo operativo.
update public.cob_pagos set metodo_pago = 'cash' where metodo_pago = 'efectivo';
update public.cob_pagos set metodo_pago = 'ach' where metodo_pago = 'transferencia';
update public.cob_pagos set metodo_pago = 'check' where metodo_pago = 'cheque';
update public.cob_pagos set metodo_pago = 'card' where metodo_pago = 'tarjeta';
update public.cob_pagos set metodo_pago = 'otro' where metodo_pago is null;

-- FKs defensivas para relaciones opcionales.
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'cob_revolving_accounts'
  ) then
    alter table public.cob_pagos
      drop constraint if exists cob_pagos_revolving_account_id_fkey;
    alter table public.cob_pagos
      add constraint cob_pagos_revolving_account_id_fkey
      foreign key (revolving_account_id)
      references public.cob_revolving_accounts(id)
      on delete set null;
  end if;
end $$;

alter table public.cob_pagos
  drop constraint if exists cob_pagos_cliente_id_fkey;
alter table public.cob_pagos
  add constraint cob_pagos_cliente_id_fkey
  foreign key (cliente_id)
  references public.clientes(id);

alter table public.cob_pagos
  drop constraint if exists cob_pagos_cargo_vuelta_case_id_fkey;
alter table public.cob_pagos
  add constraint cob_pagos_cargo_vuelta_case_id_fkey
  foreign key (cargo_vuelta_case_id)
  references public.cargo_vuelta_cases(id)
  on delete set null;

do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'cob_ptps'
  ) then
    alter table public.cob_pagos
      drop constraint if exists cob_pagos_ptp_id_fkey;
    alter table public.cob_pagos
      add constraint cob_pagos_ptp_id_fkey
      foreign key (ptp_id)
      references public.cob_ptps(id)
      on delete set null;
  end if;
end $$;

-- Constraints operativas.
alter table public.cob_pagos
  alter column metodo_pago set default 'otro',
  alter column metodo_pago set not null,
  alter column fecha_pago set default current_date,
  alter column fecha_pago set not null,
  alter column moneda set default 'USD',
  alter column moneda set not null,
  alter column estado set default 'registrado',
  alter column estado set not null,
  alter column source set default 'manual',
  alter column source set not null,
  alter column created_by set default auth.uid();

alter table public.cob_pagos
  drop constraint if exists cob_pagos_monto_check;
alter table public.cob_pagos
  add constraint cob_pagos_monto_check
  check (monto > 0);

alter table public.cob_pagos
  drop constraint if exists cob_pagos_estado_check;
alter table public.cob_pagos
  add constraint cob_pagos_estado_check
  check (estado in ('registrado', 'validado', 'rechazado', 'reversado'));

alter table public.cob_pagos
  drop constraint if exists cob_pagos_metodo_pago_check;
alter table public.cob_pagos
  add constraint cob_pagos_metodo_pago_check
  check (metodo_pago in ('cash', 'check', 'zelle', 'ach', 'card', 'hycite', 'wire', 'otro'));

alter table public.cob_pagos
  drop constraint if exists cob_pagos_source_check;
alter table public.cob_pagos
  add constraint cob_pagos_source_check
  check (source in ('manual', 'import', 'hycite', 'n8n', 'api'));

create index if not exists idx_cob_pagos_org_cliente_fecha
  on public.cob_pagos (org_id, cliente_id, fecha_pago desc);

create index if not exists idx_cob_pagos_case_fecha
  on public.cob_pagos (cargo_vuelta_case_id, fecha_pago desc);

create index if not exists idx_cob_pagos_ptp_id
  on public.cob_pagos (ptp_id);

create index if not exists idx_cob_pagos_estado
  on public.cob_pagos (org_id, estado);

create unique index if not exists uq_cob_pagos_source_external_id
  on public.cob_pagos (org_id, source, external_id)
  where external_id is not null;

-- Trigger updated_at reusable.
create or replace function public.fn_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_cob_pagos_updated_at on public.cob_pagos;
create trigger trg_cob_pagos_updated_at
  before update on public.cob_pagos
  for each row execute function public.fn_set_updated_at();

-- RLS: patrón cartera por org_id + roles existentes.
alter table public.cob_pagos enable row level security;

drop policy if exists cob_pagos_cartera_role on public.cob_pagos;
drop policy if exists cob_pagos_select_cartera on public.cob_pagos;
drop policy if exists cob_pagos_insert_cartera on public.cob_pagos;
drop policy if exists cob_pagos_update_cartera on public.cob_pagos;
drop policy if exists cob_pagos_delete_cartera on public.cob_pagos;

create policy cob_pagos_select_cartera
  on public.cob_pagos
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );

create policy cob_pagos_insert_cartera
  on public.cob_pagos
  for insert to authenticated
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (created_by is null or created_by = auth.uid())
      )
    )
  );

create policy cob_pagos_update_cartera
  on public.cob_pagos
  for update to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  )
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (created_by is null or created_by = auth.uid())
      )
    )
  );

-- Sin policy de delete: anulación operativa vía estado='reversado'.

commit;;
