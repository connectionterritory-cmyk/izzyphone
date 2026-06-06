-- ============================================================
-- 0107: cob_pagos + cob_plan_pagos + cob_plan_cuotas
--
-- Objetivo:
--   Cerrar el ciclo operativo de cartera/cobranza:
--   - cob_pagos: pago real recibido, linkeable a PTP y/o cuota
--   - cob_plan_pagos: cabecera del plan de pagos por caso
--   - cob_plan_cuotas: cuotas rastreables con estado propio
--
-- Relaciones clave:
--   cob_pagos       → clientes, cargo_vuelta_cases, cob_ptps (opt), cob_plan_cuotas (opt)
--   cob_plan_pagos  → cargo_vuelta_cases (opt), clientes
--   cob_plan_cuotas → cob_plan_pagos, cob_pagos (opt)
--
-- No incluye todavía:
--   - consolidación de llamadas_telemercadeo con cob_gestiones
--   - rol cobrador en RLS
--   - automatización n8n de cuotas
--
-- ROLLBACK:
--   DROP TABLE public.cob_plan_cuotas;
--   DROP TABLE public.cob_plan_pagos;
--   DROP TABLE public.cob_pagos;
--   DROP FUNCTION public.fn_cob_cuotas_auto_vencido();
-- ============================================================

begin;
-- ── 1. cob_pagos ─────────────────────────────────────────────
-- Registro de cada pago real recibido del cliente.
-- Puede estar asociado a un PTP, a una cuota de plan, o ser libre.

create table if not exists public.cob_pagos (
  id              uuid          primary key default gen_random_uuid(),
  org_id          uuid          not null,

  cliente_id      uuid          not null
                                references public.clientes(id) on delete cascade,
  case_id         uuid
                                references public.cargo_vuelta_cases(id) on delete set null,
  ptp_id          uuid
                                references public.cob_ptps(id) on delete set null,

  monto           numeric(12,2) not null
                                check (monto > 0),
  fecha_pago      date          not null,
  metodo_pago     text
                                check (metodo_pago in (
                                  'efectivo',
                                  'transferencia',
                                  'cheque',
                                  'tarjeta',
                                  'otro'
                                )),
  referencia      text,
  notas           text,
  creado_por      uuid
                                references public.usuarios(id) on delete set null,

  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now()
);
comment on table public.cob_pagos is
  'Pagos reales recibidos de clientes. Linkeable a PTP (cob_ptps) '
  'y/o cuota de plan (cob_plan_cuotas). Fuente de verdad operativa.';
create index if not exists cob_pagos_org_id_idx
  on public.cob_pagos (org_id);
create index if not exists cob_pagos_cliente_id_idx
  on public.cob_pagos (cliente_id);
create index if not exists cob_pagos_case_id_idx
  on public.cob_pagos (case_id)
  where case_id is not null;
create index if not exists cob_pagos_ptp_id_idx
  on public.cob_pagos (ptp_id)
  where ptp_id is not null;
create index if not exists cob_pagos_fecha_pago_idx
  on public.cob_pagos (org_id, fecha_pago desc);
-- ── 2. cob_plan_pagos ────────────────────────────────────────
-- Cabecera del plan de pagos acordado con el cliente.
-- Un caso puede tener a lo sumo un plan activo a la vez.

create table if not exists public.cob_plan_pagos (
  id              uuid          primary key default gen_random_uuid(),
  org_id          uuid          not null,

  cliente_id      uuid          not null
                                references public.clientes(id) on delete cascade,
  case_id         uuid
                                references public.cargo_vuelta_cases(id) on delete set null,

  monto_total     numeric(12,2) not null
                                check (monto_total > 0),
  numero_cuotas   integer       not null
                                check (numero_cuotas > 0),
  estado          text          not null default 'activo'
                                check (estado in ('activo', 'completado', 'cancelado')),

  notas           text,
  creado_por      uuid
                                references public.usuarios(id) on delete set null,

  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now()
);
comment on table public.cob_plan_pagos is
  'Plan de pagos acordado con el cliente, compuesto por cuotas '
  'rastreadas en cob_plan_cuotas.';
create index if not exists cob_plan_pagos_org_id_idx
  on public.cob_plan_pagos (org_id);
create index if not exists cob_plan_pagos_cliente_id_idx
  on public.cob_plan_pagos (cliente_id);
create index if not exists cob_plan_pagos_case_id_idx
  on public.cob_plan_pagos (case_id)
  where case_id is not null;
create index if not exists cob_plan_pagos_org_estado_idx
  on public.cob_plan_pagos (org_id, estado);
-- ── 3. cob_plan_cuotas ───────────────────────────────────────
-- Cuota individual de un plan de pagos.
-- Cuando se registra un pago (cob_pagos), se vincula via pago_id.
-- Múltiples cuotas pueden referenciar el mismo pago (un pago cubre N cuotas).

create table if not exists public.cob_plan_cuotas (
  id                uuid          primary key default gen_random_uuid(),
  org_id            uuid          not null,

  plan_id           uuid          not null
                                  references public.cob_plan_pagos(id) on delete cascade,
  pago_id           uuid
                                  references public.cob_pagos(id) on delete set null,

  numero_cuota      integer       not null
                                  check (numero_cuota > 0),
  monto             numeric(12,2) not null
                                  check (monto > 0),
  fecha_vencimiento date          not null,
  fecha_pago        date,

  estado            text          not null default 'pendiente'
                                  check (estado in (
                                    'pendiente',
                                    'pagada',
                                    'vencida',
                                    'cancelada'
                                  )),

  created_at        timestamptz   not null default now(),
  updated_at        timestamptz   not null default now(),

  -- Unicidad: no puede haber dos cuotas con el mismo número dentro del plan
  constraint cob_plan_cuotas_plan_numero_uidx
    unique (plan_id, numero_cuota)
);
comment on table public.cob_plan_cuotas is
  'Cuotas individuales del plan de pagos. Una cuota pasa de pendiente '
  'a pagada cuando se registra un cob_pagos y se vincula via pago_id.';
comment on column public.cob_plan_cuotas.pago_id is
  'FK al pago que cubrió esta cuota. Un mismo pago puede cubrir varias cuotas.';
create index if not exists cob_plan_cuotas_plan_id_idx
  on public.cob_plan_cuotas (plan_id);
create index if not exists cob_plan_cuotas_pago_id_idx
  on public.cob_plan_cuotas (pago_id)
  where pago_id is not null;
-- Cron de vencimiento: cuotas pendientes con fecha pasada
create index if not exists cob_plan_cuotas_pendientes_vencimiento_idx
  on public.cob_plan_cuotas (org_id, fecha_vencimiento)
  where estado = 'pendiente';
-- Dashboard de cuotas próximas a vencer por cobrador
create index if not exists cob_plan_cuotas_org_estado_idx
  on public.cob_plan_cuotas (org_id, estado, fecha_vencimiento);
-- ── 4. Trigger: auto-vencido en cob_plan_cuotas ──────────────
-- Mismo patrón que cob_ptps: si fecha_vencimiento pasó y estado
-- sigue como 'pendiente', la marca 'vencida' automáticamente.

create or replace function public.fn_cob_cuotas_auto_vencido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'pendiente'
     and new.fecha_vencimiento < current_date then
    new.estado := 'vencida';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_cob_cuotas_auto_vencido on public.cob_plan_cuotas;
create trigger trg_cob_cuotas_auto_vencido
  before insert or update on public.cob_plan_cuotas
  for each row
  execute function public.fn_cob_cuotas_auto_vencido();
-- ── 5. updated_at triggers ───────────────────────────────────
-- Mantiene updated_at fresco en cob_pagos y cob_plan_pagos.
-- cob_plan_cuotas ya lo actualiza fn_cob_cuotas_auto_vencido.

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
drop trigger if exists trg_cob_plan_pagos_updated_at on public.cob_plan_pagos;
create trigger trg_cob_plan_pagos_updated_at
  before update on public.cob_plan_pagos
  for each row execute function public.fn_set_updated_at();
-- ── 6. RLS ───────────────────────────────────────────────────

alter table public.cob_pagos       enable row level security;
alter table public.cob_plan_pagos  enable row level security;
alter table public.cob_plan_cuotas enable row level security;
-- cob_pagos: admin/distribuidor/supervisor_tele full;
-- telemercadeo lee todo en su org, escribe solo sus propios registros

create policy cob_pagos_cartera_role
  on public.cob_pagos
  for all to authenticated
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
        and (creado_por is null or creado_por = auth.uid())
      )
    )
  );
-- cob_plan_pagos: mismo patrón

create policy cob_plan_pagos_cartera_role
  on public.cob_plan_pagos
  for all to authenticated
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
        and (creado_por is null or creado_por = auth.uid())
      )
    )
  );
-- cob_plan_cuotas: acceso via plan (org_id propio)

create policy cob_plan_cuotas_cartera_role
  on public.cob_plan_cuotas
  for all to authenticated
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
commit;
