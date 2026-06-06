-- 0160_cob_acuerdos_pago_automatico.sql
-- Motor de Acuerdos de Pago Automático (DFP/Cartera)
-- Draft de schema únicamente. No ejecuta cobros ni mutaciones de ledger.

begin;
-- ============================================================
-- 1) Tabla: cob_acuerdos_pago_automatico
-- ============================================================

create table if not exists public.cob_acuerdos_pago_automatico (
  id                         uuid primary key default gen_random_uuid(),
  org_id                     uuid not null,
  cliente_id                 uuid not null references public.clientes(id),
  cargo_vuelta_case_id       uuid not null references public.cargo_vuelta_cases(id),
  revolving_account_id       uuid null references public.cob_revolving_accounts(id),
  metodo_pago_id             uuid null references public.cob_metodos_pago(id),

  monto_base_mensual         numeric(12,2) not null,
  porcentaje_cargo_autorizado numeric(5,2) not null default 0,
  monto_total_cobro          numeric(12,2) not null,

  frecuencia                 text not null default 'mensual',
  dia_cobro_preferido        int not null,
  fecha_primer_cobro         date not null,
  fecha_proximo_cobro        date null,
  fecha_ultimo_cobro         date null,

  statement_automatico       boolean not null default true,
  recordatorio_automatico    boolean not null default true,

  estado                     text not null default 'borrador',

  autorizado_por_cliente     boolean not null default false,
  fecha_autorizacion         timestamptz null,
  canal_autorizacion         text null,

  notas                      text null,
  metadata                   jsonb not null default '{}'::jsonb,

  created_by                 uuid null references auth.users(id),
  updated_by                 uuid null references auth.users(id),
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),

  constraint chk_cob_acuerdo_estado
    check (estado in ('borrador','activo','pausado','cancelado','completado')),

  constraint chk_cob_acuerdo_monto_base
    check (monto_base_mensual > 0),

  constraint chk_cob_acuerdo_porcentaje
    check (porcentaje_cargo_autorizado >= 0 and porcentaje_cargo_autorizado <= 100),

  constraint chk_cob_acuerdo_monto_total
    check (monto_total_cobro > 0),

  constraint chk_cob_acuerdo_dia_cobro
    check (dia_cobro_preferido between 1 and 31),

  constraint chk_cob_acuerdo_frecuencia
    check (frecuencia = 'mensual'),

  constraint chk_cob_acuerdo_autorizacion
    check (
      autorizado_por_cliente = false
      or (autorizado_por_cliente = true and fecha_autorizacion is not null)
    )
);
comment on table public.cob_acuerdos_pago_automatico is
  'Acuerdo de pago automático DFP: regla operativa recurrente por caso/cliente.';
comment on column public.cob_acuerdos_pago_automatico.metadata is
  'Metadatos operativos del acuerdo (no financieros).';
create index if not exists idx_cob_acuerdos_org
  on public.cob_acuerdos_pago_automatico (org_id);
create index if not exists idx_cob_acuerdos_cliente
  on public.cob_acuerdos_pago_automatico (org_id, cliente_id);
create index if not exists idx_cob_acuerdos_case
  on public.cob_acuerdos_pago_automatico (org_id, cargo_vuelta_case_id);
create index if not exists idx_cob_acuerdos_estado
  on public.cob_acuerdos_pago_automatico (org_id, estado);
create index if not exists idx_cob_acuerdos_proximo_cobro
  on public.cob_acuerdos_pago_automatico (org_id, fecha_proximo_cobro)
  where fecha_proximo_cobro is not null;
-- Regla: un solo acuerdo activo o pausado por caso dentro del org.
create unique index if not exists uq_cob_acuerdo_activo_pausado_por_caso
  on public.cob_acuerdos_pago_automatico (org_id, cargo_vuelta_case_id)
  where estado in ('activo', 'pausado');
-- updated_at trigger (patrón existente del proyecto)
drop trigger if exists trg_cob_acuerdos_pago_automatico_updated_at on public.cob_acuerdos_pago_automatico;
create trigger trg_cob_acuerdos_pago_automatico_updated_at
  before update on public.cob_acuerdos_pago_automatico
  for each row execute function public.fn_set_updated_at();
-- ============================================================
-- 2) Tabla: cob_cobros_programados
-- ============================================================

create table if not exists public.cob_cobros_programados (
  id                         uuid primary key default gen_random_uuid(),
  org_id                     uuid not null,

  acuerdo_id                 uuid not null references public.cob_acuerdos_pago_automatico(id),
  cliente_id                 uuid not null references public.clientes(id),
  cargo_vuelta_case_id       uuid not null references public.cargo_vuelta_cases(id),

  statement_id               uuid null references public.cob_statements(id),
  pago_id                    uuid null references public.cob_pagos(id),
  metodo_pago_id             uuid null references public.cob_metodos_pago(id),

  fecha_programada           date not null,
  monto_programado           numeric(12,2) not null,

  estado                     text not null default 'programado',
  intento_numero             int not null default 0,

  provider                   text null,
  provider_reference         text null,
  error_code                 text null,
  error_message              text null,
  notas                      text null,

  metadata                   jsonb not null default '{}'::jsonb,

  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),

  constraint chk_cob_cobro_prog_estado
    check (estado in (
      'programado',
      'recordatorio_enviado',
      'procesando',
      'pagado',
      'fallido',
      'vencido',
      'cancelado'
    )),

  constraint chk_cob_cobro_prog_monto
    check (monto_programado > 0),

  constraint chk_cob_cobro_prog_intento
    check (intento_numero >= 0)
);
comment on table public.cob_cobros_programados is
  'Cobro programado DFP: intento futuro de cobro; no impacta ledger por sí solo.';
comment on column public.cob_cobros_programados.metadata is
  'Metadatos operativos del intento de cobro (provider, orquestación, etc.).';
create index if not exists idx_cob_cobros_prog_org
  on public.cob_cobros_programados (org_id);
create index if not exists idx_cob_cobros_prog_acuerdo
  on public.cob_cobros_programados (acuerdo_id);
create index if not exists idx_cob_cobros_prog_case
  on public.cob_cobros_programados (org_id, cargo_vuelta_case_id);
create index if not exists idx_cob_cobros_prog_estado_fecha
  on public.cob_cobros_programados (org_id, estado, fecha_programada);
create unique index if not exists uq_cob_cobro_prog_acuerdo_fecha
  on public.cob_cobros_programados (acuerdo_id, fecha_programada);
-- updated_at trigger
drop trigger if exists trg_cob_cobros_programados_updated_at on public.cob_cobros_programados;
create trigger trg_cob_cobros_programados_updated_at
  before update on public.cob_cobros_programados
  for each row execute function public.fn_set_updated_at();
-- ============================================================
-- 3) Tabla: cob_acuerdo_eventos
-- ============================================================

create table if not exists public.cob_acuerdo_eventos (
  id                         uuid primary key default gen_random_uuid(),
  org_id                     uuid not null,

  acuerdo_id                 uuid not null references public.cob_acuerdos_pago_automatico(id),
  cobro_programado_id        uuid null references public.cob_cobros_programados(id),

  tipo_evento                text not null,
  actor_user_id              uuid null references auth.users(id),

  payload_before             jsonb null,
  payload_after              jsonb null,
  motivo                     text null,
  metadata                   jsonb not null default '{}'::jsonb,

  created_at                 timestamptz not null default now(),

  constraint chk_cob_acuerdo_evento_tipo
    check (tipo_evento in (
      'acuerdo_creado',
      'acuerdo_editado',
      'acuerdo_pausado',
      'acuerdo_cancelado',
      'acuerdo_completado',
      'acuerdo_renegociado',
      'monto_cambiado',
      'metodo_cambiado',
      'cobro_programado_creado',
      'cobro_recordatorio_enviado',
      'cobro_procesando',
      'cobro_exitoso',
      'cobro_fallido',
      'cobro_vencido',
      'cobro_cancelado'
    ))
);
comment on table public.cob_acuerdo_eventos is
  'Auditoría técnica del ciclo de vida de acuerdos y cobros programados DFP.';
create index if not exists idx_cob_acuerdo_eventos_org
  on public.cob_acuerdo_eventos (org_id);
create index if not exists idx_cob_acuerdo_eventos_acuerdo
  on public.cob_acuerdo_eventos (acuerdo_id, created_at desc);
create index if not exists idx_cob_acuerdo_eventos_cobro
  on public.cob_acuerdo_eventos (cobro_programado_id)
  where cobro_programado_id is not null;
create index if not exists idx_cob_acuerdo_eventos_tipo
  on public.cob_acuerdo_eventos (org_id, tipo_evento, created_at desc);
-- ============================================================
-- 4) RLS (patrón cartera por org_id y rol)
-- ============================================================

alter table public.cob_acuerdos_pago_automatico enable row level security;
alter table public.cob_cobros_programados enable row level security;
alter table public.cob_acuerdo_eventos enable row level security;
-- cob_acuerdos_pago_automatico

drop policy if exists cob_acuerdos_pago_automatico_select_cartera on public.cob_acuerdos_pago_automatico;
drop policy if exists cob_acuerdos_pago_automatico_insert_cartera on public.cob_acuerdos_pago_automatico;
drop policy if exists cob_acuerdos_pago_automatico_update_cartera on public.cob_acuerdos_pago_automatico;
create policy cob_acuerdos_pago_automatico_select_cartera
  on public.cob_acuerdos_pago_automatico
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_acuerdos_pago_automatico_insert_cartera
  on public.cob_acuerdos_pago_automatico
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
create policy cob_acuerdos_pago_automatico_update_cartera
  on public.cob_acuerdos_pago_automatico
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
-- cob_cobros_programados

drop policy if exists cob_cobros_programados_select_cartera on public.cob_cobros_programados;
drop policy if exists cob_cobros_programados_insert_cartera on public.cob_cobros_programados;
drop policy if exists cob_cobros_programados_update_cartera on public.cob_cobros_programados;
create policy cob_cobros_programados_select_cartera
  on public.cob_cobros_programados
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_cobros_programados_insert_cartera
  on public.cob_cobros_programados
  for insert to authenticated
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_cobros_programados_update_cartera
  on public.cob_cobros_programados
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
-- cob_acuerdo_eventos

drop policy if exists cob_acuerdo_eventos_select_cartera on public.cob_acuerdo_eventos;
drop policy if exists cob_acuerdo_eventos_insert_cartera on public.cob_acuerdo_eventos;
drop policy if exists cob_acuerdo_eventos_update_cartera on public.cob_acuerdo_eventos;
create policy cob_acuerdo_eventos_select_cartera
  on public.cob_acuerdo_eventos
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy cob_acuerdo_eventos_insert_cartera
  on public.cob_acuerdo_eventos
  for insert to authenticated
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
-- cob_acuerdo_eventos es append-only por diseño: sin UPDATE/DELETE policies.
-- Cualquier corrección debe registrarse como evento compensatorio nuevo.

-- Sin policy DELETE: historial y auditoría no se elimina por RLS.

commit;
