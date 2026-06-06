-- ============================================================
-- 0118: cob_revolving_accounts — Cuenta revolving interna DFP
--
-- Objetivo:
--   Modelar la obligación financiera de un caso Cargo de Vuelta /
--   Recomprada / DFP como cuenta revolving interna con APR entre
--   10% y 24%, late fees y saldos por componente.
--
-- Relación con otras tablas:
--   - 1 caso (cargo_vuelta_cases) → 1 cuenta activa como máximo
--   - La cuenta guarda saldos materializados (resumen rápido)
--   - cob_financial_ledger (0119) será la verdad financiera
--   - cob_plan_pagos / cob_pagos siguen funcionando como antes
--
-- Reglas de negocio:
--   - APR real de negocio: 10% a 24% anual
--   - Método de interés: daily_simple_365 (APR/365 × días × principal)
--   - Interés se calcula solo sobre principal (no sobre interés ni fees)
--   - saldo_total_actual es columna generada: no puede divergir de componentes
--   - Solo un estado activo por caso (unique parcial)
--
-- ROLLBACK:
--   DROP TABLE IF EXISTS public.cob_revolving_accounts;
-- ============================================================

begin;
-- ── 1. Tabla principal ────────────────────────────────────────

create table if not exists public.cob_revolving_accounts (
  id                        uuid          primary key default gen_random_uuid(),
  org_id                    uuid          not null,

  -- Entidades relacionadas
  case_id                   uuid          not null
                                          references public.cargo_vuelta_cases(id)
                                          on delete restrict,
  cliente_id                uuid          not null
                                          references public.clientes(id)
                                          on delete restrict,

  -- Configuración financiera
  apr_anual                 numeric(6,5)  not null
                                          check (apr_anual between 0.10 and 0.24),
  metodo_calculo_interes    text          not null default 'daily_simple_365'
                                          check (metodo_calculo_interes in ('daily_simple_365')),

  -- Línea de tiempo
  fecha_inicio              date          not null,
  fecha_ultimo_devengo      date          not null,

  -- Saldo inicial (base del caso devuelto)
  saldo_principal_inicial   numeric(12,2) not null
                                          check (saldo_principal_inicial >= 0),

  -- Saldos actuales por componente (materializados para consulta rápida)
  -- saldo_total_actual es generado: imposible divergir de sus componentes
  saldo_principal_actual    numeric(12,2) not null default 0
                                          check (saldo_principal_actual >= 0),
  saldo_interes_actual      numeric(12,2) not null default 0
                                          check (saldo_interes_actual >= 0),
  saldo_fees_actual         numeric(12,2) not null default 0
                                          check (saldo_fees_actual >= 0),
  saldo_total_actual        numeric(12,2) generated always as (
                                            saldo_principal_actual
                                            + saldo_interes_actual
                                            + saldo_fees_actual
                                          ) stored,

  -- Configuración de late fees (uno de los dos o ninguno)
  late_fee_fijo             numeric(12,2)
                                          check (late_fee_fijo is null or late_fee_fijo >= 0),
  late_fee_porcentaje       numeric(6,5)
                                          check (late_fee_porcentaje is null or late_fee_porcentaje between 0 and 1),
  dias_gracia_late_fee      integer       not null default 0
                                          check (dias_gracia_late_fee >= 0),

  -- Política de capitalización (false por defecto — no capitalizar)
  capitaliza_interes        boolean       not null default false,
  capitaliza_fees           boolean       not null default false,

  -- Estado del ciclo de vida de la cuenta
  estado                    text          not null default 'activo'
                                          check (estado in (
                                            'activo',
                                            'moroso',
                                            'en_plan',
                                            'reestructurado',
                                            'completado',
                                            'cancelado',
                                            'writeoff'
                                          )),

  -- Auditoría
  created_by                uuid          references public.usuarios(id) on delete set null,
  created_at                timestamptz   not null default now(),
  updated_at                timestamptz   not null default now()
);
-- ── 2. Constraints de negocio ─────────────────────────────────

-- Solo un late fee activo a la vez (fijo o porcentaje, no ambos)
alter table public.cob_revolving_accounts
  add constraint cob_revolving_accounts_late_fee_exclusivo_chk
  check (
    late_fee_fijo is null
    or late_fee_porcentaje is null
  );
-- saldo_principal_actual no puede exceder el inicial
-- (nota: puede reducirse a cero pero nunca ser negativo — cubierto por check individual)

-- ── 3. Comentarios ────────────────────────────────────────────

comment on table public.cob_revolving_accounts is
  'Cuenta revolving interna para casos DFP/Cargo de Vuelta. '
  'Guarda la configuración financiera (APR, fees) y saldos materializados '
  'por componente (principal, interés, fees). '
  'La verdad financiera auditable vive en cob_financial_ledger (0119).';
comment on column public.cob_revolving_accounts.apr_anual is
  'Tasa de interés anual en decimal. Rango operativo: 0.10 (10%) a 0.24 (24%).';
comment on column public.cob_revolving_accounts.metodo_calculo_interes is
  'Método de cálculo. daily_simple_365: APR/365 × días × saldo_principal_actual. '
  'Interés no capitaliza sobre sí mismo ni sobre fees salvo política explícita.';
comment on column public.cob_revolving_accounts.fecha_ultimo_devengo is
  'Última fecha hasta la que se devengó interés. '
  'fn_devengar_interes_revolving avanza este campo. '
  'Nunca modificar manualmente: usar la función para evitar doble devengo.';
comment on column public.cob_revolving_accounts.saldo_principal_inicial is
  'Monto devuelto por Hy-Cite. Fuente: cargo_vuelta_cases.monto_devuelto al crear la cuenta. '
  'No cambia una vez creada la cuenta (los pagos reducen saldo_principal_actual).';
comment on column public.cob_revolving_accounts.saldo_total_actual is
  'Columna generada: saldo_principal_actual + saldo_interes_actual + saldo_fees_actual. '
  'No actualizar directamente. Actualizar los tres componentes.';
comment on column public.cob_revolving_accounts.late_fee_fijo is
  'Monto fijo de late fee en dólares. Excluyente con late_fee_porcentaje.';
comment on column public.cob_revolving_accounts.late_fee_porcentaje is
  'Porcentaje del saldo vencido como late fee (ej: 0.05 = 5%). Excluyente con late_fee_fijo.';
comment on column public.cob_revolving_accounts.capitaliza_interes is
  'Si true, el interés devengado se suma al principal (compound). '
  'Por política actual: false. Solo cambiar con aprobación explícita.';
comment on column public.cob_revolving_accounts.estado is
  'activo: cuenta viva sin acuerdo formal. '
  'moroso: mora activa o fee pendiente. '
  'en_plan: existe cob_plan_pagos activo. '
  'reestructurado: reemplazada por otra cuenta/acuerdo. '
  'completado: todos los saldos en cero. '
  'cancelado: anulada administrativamente. '
  'writeoff: castigo contable interno.';
-- ── 4. Índices ────────────────────────────────────────────────

-- Acceso principal
create index if not exists cob_revolving_accounts_org_id_idx
  on public.cob_revolving_accounts (org_id);
create index if not exists cob_revolving_accounts_case_id_idx
  on public.cob_revolving_accounts (case_id);
create index if not exists cob_revolving_accounts_cliente_id_idx
  on public.cob_revolving_accounts (cliente_id);
-- Garantía de negocio: un solo estado activo por caso
-- Estados activos = aquellos que representan obligación viva
create unique index if not exists cob_revolving_accounts_case_activa_uidx
  on public.cob_revolving_accounts (case_id)
  where estado in ('activo', 'moroso', 'en_plan', 'reestructurado');
-- Dashboard por estado
create index if not exists cob_revolving_accounts_org_estado_idx
  on public.cob_revolving_accounts (org_id, estado);
-- Job de devengo: cuentas pendientes de accrual
create index if not exists cob_revolving_accounts_org_devengo_idx
  on public.cob_revolving_accounts (org_id, fecha_ultimo_devengo)
  where estado in ('activo', 'moroso', 'en_plan');
-- ── 5. Trigger updated_at ─────────────────────────────────────

create or replace function public.fn_set_revolving_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_cob_revolving_accounts_updated_at
  on public.cob_revolving_accounts;
create trigger trg_cob_revolving_accounts_updated_at
  before update on public.cob_revolving_accounts
  for each row execute function public.fn_set_revolving_updated_at();
-- ── 6. RLS ────────────────────────────────────────────────────

alter table public.cob_revolving_accounts enable row level security;
-- Patrón canónico de cartera:
-- admin/distribuidor/supervisor_tele: acceso completo (lectura + escritura)
-- telemercadeo: lectura de su org; escritura solo vía funciones en fases futuras
-- Las mutaciones financieras críticas (devengo, waterfall) serán SECURITY DEFINER

create policy cob_revolving_accounts_cartera_role
  on public.cob_revolving_accounts
  for all to authenticated
  using (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  )
  with check (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
    )
  );
commit;
