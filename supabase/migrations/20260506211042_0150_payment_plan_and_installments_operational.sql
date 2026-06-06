begin;
-- 0150_payment_plan_and_installments_operational
-- Extiende estructura operativa de planes de pago y cuotas sin contabilidad real.
-- No toca cob_financial_ledger.

-- ============================================================================
-- A) HARDENING / EXTENSIÓN DE cob_plan_pagos
-- ============================================================================

alter table public.cob_plan_pagos
  add column if not exists cargo_vuelta_case_id uuid,
  add column if not exists metodo_pago_id uuid,
  add column if not exists tipo_plan text,
  add column if not exists principal_original numeric(12,2),
  add column if not exists balance_inicial numeric(12,2),
  add column if not exists tasa_anual_pct numeric(6,3),
  add column if not exists tasa_mensual_pct numeric(6,3),
  add column if not exists monto_cuota numeric(12,2),
  add column if not exists dia_debito integer,
  add column if not exists fecha_inicio date,
  add column if not exists fecha_primer_pago date,
  add column if not exists fecha_fin_estimada date,
  add column if not exists fee_setup numeric(12,2),
  add column if not exists fee_late numeric(12,2),
  add column if not exists moneda text,
  add column if not exists acuerdo_generado_at timestamptz,
  add column if not exists acuerdo_firmado_at timestamptz,
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid;
-- Compatibilidad con naming legacy.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'cob_plan_pagos'
      and column_name = 'case_id'
  ) then
    execute '
      update public.cob_plan_pagos
         set cargo_vuelta_case_id = coalesce(cargo_vuelta_case_id, case_id)
       where case_id is not null
         and cargo_vuelta_case_id is null
    ';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'cob_plan_pagos'
      and column_name = 'creado_por'
  ) then
    execute '
      update public.cob_plan_pagos
         set created_by = coalesce(created_by, creado_por)
       where created_by is null
         and creado_por is not null
    ';
  end if;
end $$;
update public.cob_plan_pagos
set tipo_plan = coalesce(tipo_plan, 'refinanciamiento'),
    fee_setup = coalesce(fee_setup, 0),
    fee_late = coalesce(fee_late, 0),
    moneda = coalesce(moneda, 'USD'),
    created_by = coalesce(created_by, auth.uid())
where tipo_plan is null
   or fee_setup is null
   or fee_late is null
   or moneda is null
   or created_by is null;
alter table public.cob_plan_pagos
  alter column tipo_plan set default 'refinanciamiento',
  alter column tipo_plan set not null,
  alter column estado set default 'borrador',
  alter column estado set not null,
  alter column fee_setup set default 0,
  alter column fee_setup set not null,
  alter column fee_late set default 0,
  alter column fee_late set not null,
  alter column moneda set default 'USD',
  alter column moneda set not null,
  alter column created_by set default auth.uid(),
  alter column created_at set default now(),
  alter column updated_at set default now();
alter table public.cob_plan_pagos
  drop constraint if exists cob_plan_pagos_cargo_vuelta_case_id_fkey;
alter table public.cob_plan_pagos
  add constraint cob_plan_pagos_cargo_vuelta_case_id_fkey
  foreign key (cargo_vuelta_case_id) references public.cargo_vuelta_cases(id) on delete set null;
alter table public.cob_plan_pagos
  drop constraint if exists cob_plan_pagos_metodo_pago_id_fkey;
alter table public.cob_plan_pagos
  add constraint cob_plan_pagos_metodo_pago_id_fkey
  foreign key (metodo_pago_id) references public.cob_metodos_pago(id) on delete set null;
alter table public.cob_plan_pagos
  drop constraint if exists cob_plan_pagos_created_by_fkey;
alter table public.cob_plan_pagos
  add constraint cob_plan_pagos_created_by_fkey
  foreign key (created_by) references public.usuarios(id) on delete set null;
alter table public.cob_plan_pagos
  drop constraint if exists cob_plan_pagos_updated_by_fkey;
alter table public.cob_plan_pagos
  add constraint cob_plan_pagos_updated_by_fkey
  foreign key (updated_by) references public.usuarios(id) on delete set null;
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_tipo_plan;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_tipo_plan
  check (tipo_plan in ('refinanciamiento', 'promesa_pago', 'settlement', 'manual'));
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_estado;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_estado
  check (estado in ('borrador', 'activo', 'pausado', 'cumplido', 'incumplido', 'cancelado'));
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_tasa_anual_pct;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_tasa_anual_pct
  check (tasa_anual_pct is null or (tasa_anual_pct >= 0 and tasa_anual_pct <= 36));
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_tasa_mensual_pct;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_tasa_mensual_pct
  check (tasa_mensual_pct is null or (tasa_mensual_pct >= 0 and tasa_mensual_pct <= 3));
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_numero_cuotas;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_numero_cuotas
  check (numero_cuotas is null or (numero_cuotas > 0 and numero_cuotas <= 120));
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_dia_debito;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_dia_debito
  check (dia_debito is null or (dia_debito between 1 and 31));
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_montos_non_negative;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_montos_non_negative
  check (
    (principal_original is null or principal_original >= 0)
    and (balance_inicial is null or balance_inicial >= 0)
    and (monto_cuota is null or monto_cuota >= 0)
    and fee_setup >= 0
    and fee_late >= 0
  );
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_moneda;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_moneda
  check (moneda = 'USD');
create index if not exists idx_cob_plan_pagos_org_id
  on public.cob_plan_pagos (org_id);
create index if not exists idx_cob_plan_pagos_cliente_id
  on public.cob_plan_pagos (cliente_id);
create index if not exists idx_cob_plan_pagos_case_id
  on public.cob_plan_pagos (cargo_vuelta_case_id);
create index if not exists idx_cob_plan_pagos_estado
  on public.cob_plan_pagos (org_id, estado);
create index if not exists idx_cob_plan_pagos_metodo_pago_id
  on public.cob_plan_pagos (metodo_pago_id);
drop trigger if exists trg_cob_plan_pagos_updated_at on public.cob_plan_pagos;
create trigger trg_cob_plan_pagos_updated_at
  before update on public.cob_plan_pagos
  for each row execute function public.fn_set_updated_at();
-- ============================================================================
-- B) HARDENING / EXTENSIÓN DE cob_plan_cuotas
-- ============================================================================

create table if not exists public.cob_plan_cuotas (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null,
  plan_pago_id         uuid not null references public.cob_plan_pagos(id) on delete cascade,
  cargo_vuelta_case_id uuid not null references public.cargo_vuelta_cases(id) on delete cascade,
  cliente_id           uuid not null references public.clientes(id) on delete cascade,
  numero_cuota         integer not null,
  fecha_vencimiento    date not null,
  monto_programado     numeric(12,2) not null,
  principal_programado numeric(12,2) not null default 0,
  interes_programado   numeric(12,2) not null default 0,
  fees_programados     numeric(12,2) not null default 0,
  monto_pagado         numeric(12,2) not null default 0,
  saldo_cuota          numeric(12,2) not null default 0,
  estado               text not null default 'pendiente',
  cob_pago_id          uuid references public.cob_pagos(id) on delete set null,
  paid_at              timestamptz,
  notas                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
alter table public.cob_plan_cuotas
  add column if not exists plan_pago_id uuid,
  add column if not exists cargo_vuelta_case_id uuid,
  add column if not exists cliente_id uuid,
  add column if not exists monto_programado numeric(12,2),
  add column if not exists principal_programado numeric(12,2),
  add column if not exists interes_programado numeric(12,2),
  add column if not exists fees_programados numeric(12,2),
  add column if not exists monto_pagado numeric(12,2),
  add column if not exists saldo_cuota numeric(12,2),
  add column if not exists cob_pago_id uuid,
  add column if not exists paid_at timestamptz;
-- Compatibilidad con naming legacy y backfill.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_plan_cuotas' and column_name = 'plan_id'
  ) then
    execute '
      update public.cob_plan_cuotas
         set plan_pago_id = coalesce(plan_pago_id, plan_id)
       where plan_id is not null
         and plan_pago_id is null
    ';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_plan_cuotas' and column_name = 'pago_id'
  ) then
    execute '
      update public.cob_plan_cuotas
         set cob_pago_id = coalesce(cob_pago_id, pago_id)
       where pago_id is not null
         and cob_pago_id is null
    ';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cob_plan_cuotas' and column_name = 'monto'
  ) then
    execute '
      update public.cob_plan_cuotas
         set monto_programado = coalesce(monto_programado, monto)
       where monto_programado is null
    ';
  end if;
end $$;
update public.cob_plan_cuotas c
set cargo_vuelta_case_id = coalesce(c.cargo_vuelta_case_id, p.cargo_vuelta_case_id, p.case_id),
    cliente_id = coalesce(c.cliente_id, p.cliente_id)
from public.cob_plan_pagos p
where c.plan_pago_id = p.id
  and (c.cargo_vuelta_case_id is null or c.cliente_id is null);
update public.cob_plan_cuotas
set principal_programado = coalesce(principal_programado, 0),
    interes_programado = coalesce(interes_programado, 0),
    fees_programados = coalesce(fees_programados, 0),
    monto_pagado = coalesce(monto_pagado, 0),
    monto_programado = coalesce(monto_programado, 0),
    saldo_cuota = coalesce(saldo_cuota, greatest(coalesce(monto_programado, 0) - coalesce(monto_pagado, 0), 0))
where principal_programado is null
   or interes_programado is null
   or fees_programados is null
   or monto_pagado is null
   or monto_programado is null
   or saldo_cuota is null;
alter table public.cob_plan_cuotas
  alter column plan_pago_id set not null,
  alter column cargo_vuelta_case_id set not null,
  alter column cliente_id set not null,
  alter column monto_programado set not null,
  alter column principal_programado set default 0,
  alter column principal_programado set not null,
  alter column interes_programado set default 0,
  alter column interes_programado set not null,
  alter column fees_programados set default 0,
  alter column fees_programados set not null,
  alter column monto_pagado set default 0,
  alter column monto_pagado set not null,
  alter column saldo_cuota set default 0,
  alter column saldo_cuota set not null,
  alter column estado set default 'pendiente',
  alter column estado set not null,
  alter column created_at set default now(),
  alter column updated_at set default now();
alter table public.cob_plan_cuotas
  drop constraint if exists cob_plan_cuotas_plan_pago_id_fkey;
alter table public.cob_plan_cuotas
  add constraint cob_plan_cuotas_plan_pago_id_fkey
  foreign key (plan_pago_id) references public.cob_plan_pagos(id) on delete cascade;
alter table public.cob_plan_cuotas
  drop constraint if exists cob_plan_cuotas_cargo_vuelta_case_id_fkey;
alter table public.cob_plan_cuotas
  add constraint cob_plan_cuotas_cargo_vuelta_case_id_fkey
  foreign key (cargo_vuelta_case_id) references public.cargo_vuelta_cases(id) on delete cascade;
alter table public.cob_plan_cuotas
  drop constraint if exists cob_plan_cuotas_cliente_id_fkey;
alter table public.cob_plan_cuotas
  add constraint cob_plan_cuotas_cliente_id_fkey
  foreign key (cliente_id) references public.clientes(id) on delete cascade;
alter table public.cob_plan_cuotas
  drop constraint if exists cob_plan_cuotas_cob_pago_id_fkey;
alter table public.cob_plan_cuotas
  add constraint cob_plan_cuotas_cob_pago_id_fkey
  foreign key (cob_pago_id) references public.cob_pagos(id) on delete set null;
alter table public.cob_plan_cuotas
  drop constraint if exists chk_cob_plan_cuotas_numero_cuota;
alter table public.cob_plan_cuotas
  add constraint chk_cob_plan_cuotas_numero_cuota
  check (numero_cuota > 0);
alter table public.cob_plan_cuotas
  drop constraint if exists chk_cob_plan_cuotas_montos_non_negative;
alter table public.cob_plan_cuotas
  add constraint chk_cob_plan_cuotas_montos_non_negative
  check (
    monto_programado >= 0
    and principal_programado >= 0
    and interes_programado >= 0
    and fees_programados >= 0
    and monto_pagado >= 0
    and saldo_cuota >= 0
  );
alter table public.cob_plan_cuotas
  drop constraint if exists chk_cob_plan_cuotas_estado;
alter table public.cob_plan_cuotas
  add constraint chk_cob_plan_cuotas_estado
  check (estado in ('pendiente', 'programada', 'pagada', 'parcial', 'vencida', 'omitida', 'cancelada'));
create index if not exists idx_cob_plan_cuotas_org_id
  on public.cob_plan_cuotas (org_id);
create index if not exists idx_cob_plan_cuotas_plan_pago_id
  on public.cob_plan_cuotas (plan_pago_id);
create index if not exists idx_cob_plan_cuotas_cliente_id
  on public.cob_plan_cuotas (cliente_id);
create index if not exists idx_cob_plan_cuotas_case_id
  on public.cob_plan_cuotas (cargo_vuelta_case_id);
create index if not exists idx_cob_plan_cuotas_fecha_vencimiento
  on public.cob_plan_cuotas (org_id, fecha_vencimiento);
create index if not exists idx_cob_plan_cuotas_estado
  on public.cob_plan_cuotas (org_id, estado);
create unique index if not exists uq_cob_plan_cuotas_plan_numero
  on public.cob_plan_cuotas (plan_pago_id, numero_cuota);
drop trigger if exists trg_cob_plan_cuotas_updated_at on public.cob_plan_cuotas;
create trigger trg_cob_plan_cuotas_updated_at
  before update on public.cob_plan_cuotas
  for each row execute function public.fn_set_updated_at();
-- ============================================================================
-- C) RLS GRANULAR (sin DELETE)
-- ============================================================================

alter table public.cob_plan_pagos enable row level security;
alter table public.cob_plan_cuotas enable row level security;
drop policy if exists cob_plan_pagos_cartera_role on public.cob_plan_pagos;
drop policy if exists cob_plan_pagos_select_cartera on public.cob_plan_pagos;
drop policy if exists cob_plan_pagos_insert_cartera on public.cob_plan_pagos;
drop policy if exists cob_plan_pagos_update_cartera on public.cob_plan_pagos;
create policy cob_plan_pagos_select_cartera
  on public.cob_plan_pagos
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_plan_pagos_insert_cartera
  on public.cob_plan_pagos
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
create policy cob_plan_pagos_update_cartera
  on public.cob_plan_pagos
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
drop policy if exists cob_plan_cuotas_cartera_role on public.cob_plan_cuotas;
drop policy if exists cob_plan_cuotas_select_cartera on public.cob_plan_cuotas;
drop policy if exists cob_plan_cuotas_insert_cartera on public.cob_plan_cuotas;
drop policy if exists cob_plan_cuotas_update_cartera on public.cob_plan_cuotas;
create policy cob_plan_cuotas_select_cartera
  on public.cob_plan_cuotas
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_plan_cuotas_insert_cartera
  on public.cob_plan_cuotas
  for insert to authenticated
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_plan_cuotas_update_cartera
  on public.cob_plan_cuotas
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
      or security.current_user_role() = 'telemercadeo'
    )
  );
-- Sin policy DELETE: cancelación operativa vía estado.

commit;
