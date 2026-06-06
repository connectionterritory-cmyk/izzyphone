-- ============================================================
-- 0119: cob_financial_ledger — Libro mayor financiero interno
--
-- Objetivo:
--   Registro inmutable de toda mutación monetaria en una cuenta
--   revolving DFP. Es la fuente de verdad financiera.
--
-- Principios:
--   - Append-only: nunca borrar líneas
--   - Reversos: crear línea de tipo 'reversal' con reverses_ledger_id
--   - El ledger reconstruye cualquier estado pasado de la cuenta
--   - saldo_*_after refleja el balance acumulado después del entry
--
-- Tipos de entrada (entry_type):
--   principal_initial       → creación de la cuenta, carga el principal
--   finance_charge_accrual → devengo de interés diario
--   late_fee_assessed      → cargo de mora
--   payment_applied        → pago recibido (waterfall: fee→interest→principal)
--   adjustment             → ajuste manual auditado
--   writeoff               → castigo contable de saldo residual
--   reversal               → anulación de otra entrada
--
-- Componentes (component_type):
--   principal | interest | fee
--
-- Convención debit/credit:
--   debit  → aumenta el saldo del componente (cargo al cliente)
--   credit → reduce el saldo del componente (pago o reverso)
--
-- Prevención de doble devengo:
--   unique parcial en (revolving_account_id, accrual_from, accrual_to)
--   para entry_type = 'finance_charge_accrual'
--
-- Escritura:
--   En producción, solo via funciones SECURITY DEFINER.
--   La policy WITH CHECK limita inserts directos a admin/distribuidor
--   hasta que las funciones estén implementadas.
--
-- ROLLBACK:
--   DROP TABLE IF EXISTS public.cob_financial_ledger;
-- ============================================================

begin;
-- ── 1. Tabla ──────────────────────────────────────────────────

create table if not exists public.cob_financial_ledger (
  id                      uuid          primary key default gen_random_uuid(),
  org_id                  uuid          not null,

  -- Cuenta fuente
  revolving_account_id    uuid          not null
                                        references public.cob_revolving_accounts(id)
                                        on delete restrict,

  -- Entidades contextuales (desnormalizadas para auditoría independiente)
  case_id                 uuid          not null
                                        references public.cargo_vuelta_cases(id)
                                        on delete restrict,
  cliente_id              uuid          not null
                                        references public.clientes(id)
                                        on delete restrict,

  -- Referencias opcionales a otras entidades
  plan_id                 uuid          references public.cob_plan_pagos(id)   on delete set null,
  cuota_id                uuid          references public.cob_plan_cuotas(id)  on delete set null,
  pago_id                 uuid          references public.cob_pagos(id)         on delete set null,

  -- Fechas
  entry_date              date          not null default current_date,  -- fecha de registro
  effective_date          date          not null,                       -- fecha financiera del evento

  -- Tipo de movimiento
  entry_type              text          not null
                                        check (entry_type in (
                                          'principal_initial',
                                          'finance_charge_accrual',
                                          'late_fee_assessed',
                                          'payment_applied',
                                          'adjustment',
                                          'writeoff',
                                          'reversal'
                                        )),

  -- Componente financiero afectado
  component_type          text          not null
                                        check (component_type in (
                                          'principal',
                                          'interest',
                                          'fee'
                                        )),

  -- Dirección del movimiento
  debit_credit            text          not null
                                        check (debit_credit in ('debit', 'credit')),

  -- Monto (siempre positivo; la dirección la da debit_credit)
  amount                  numeric(12,2) not null
                                        check (amount > 0),

  -- Descripción libre para auditoría
  description             text,

  -- Rango de devengo (solo para finance_charge_accrual)
  accrual_from            date,
  accrual_to              date,

  -- Saldos de la cuenta después de este entry (snapshot del momento)
  balance_principal_after numeric(12,2),
  balance_interest_after  numeric(12,2),
  balance_fees_after      numeric(12,2),
  balance_total_after     numeric(12,2),

  -- Reverso: referencia a la entrada que este entry anula
  reverses_ledger_id      uuid          references public.cob_financial_ledger(id)
                                        on delete restrict,

  -- Metadata libre para contexto adicional
  metadata                jsonb         not null default '{}'::jsonb,

  -- Auditoría
  created_by              uuid          references public.usuarios(id) on delete set null,
  created_at              timestamptz   not null default now()
  -- Sin updated_at: el ledger es inmutable. No se actualiza, solo se reversa.
);
-- ── 2. Constraints de integridad ──────────────────────────────

-- finance_charge_accrual requiere rango de fechas
alter table public.cob_financial_ledger
  add constraint cob_financial_ledger_accrual_fechas_chk
  check (
    entry_type != 'finance_charge_accrual'
    or (accrual_from is not null and accrual_to is not null and accrual_to > accrual_from)
  );
-- reversal debe referenciar la entrada que anula
alter table public.cob_financial_ledger
  add constraint cob_financial_ledger_reversal_ref_chk
  check (
    entry_type != 'reversal'
    or reverses_ledger_id is not null
  );
-- Los saldos after deben ser no negativos cuando se registren
alter table public.cob_financial_ledger
  add constraint cob_financial_ledger_balance_principal_chk
  check (balance_principal_after is null or balance_principal_after >= 0);
alter table public.cob_financial_ledger
  add constraint cob_financial_ledger_balance_interest_chk
  check (balance_interest_after is null or balance_interest_after >= 0);
alter table public.cob_financial_ledger
  add constraint cob_financial_ledger_balance_fees_chk
  check (balance_fees_after is null or balance_fees_after >= 0);
alter table public.cob_financial_ledger
  add constraint cob_financial_ledger_balance_total_after_chk
  check (balance_total_after is null or balance_total_after >= 0);
-- ── 3. Comentarios ────────────────────────────────────────────

comment on table public.cob_financial_ledger is
  'Libro mayor financiero interno. Registro inmutable de toda mutación monetaria '
  'en cuentas revolving DFP. Fuente de verdad para reconstruir saldos históricos. '
  'Nunca borrar filas: usar entry_type=reversal para anular. '
  'INSERT solo permitido mediante funciones SECURITY DEFINER (0120+). '
  'INSERT directo de usuarios autenticados está explícitamente bloqueado por RLS.';
comment on column public.cob_financial_ledger.entry_date is
  'Fecha en que se registró el entry en el sistema (puede diferir de effective_date).';
comment on column public.cob_financial_ledger.effective_date is
  'Fecha financiera del evento. Para devengos: último día del rango. '
  'Para pagos: fecha real del pago recibido.';
comment on column public.cob_financial_ledger.debit_credit is
  'debit: aumenta el saldo del componente (cargo al cliente). '
  'credit: reduce el saldo del componente (pago o reverso).';
comment on column public.cob_financial_ledger.amount is
  'Monto siempre positivo. La dirección la determina debit_credit.';
comment on column public.cob_financial_ledger.accrual_from is
  'Inicio del rango de devengo. Solo para finance_charge_accrual.';
comment on column public.cob_financial_ledger.accrual_to is
  'Fin del rango de devengo (exclusivo del rango). Solo para finance_charge_accrual.';
comment on column public.cob_financial_ledger.balance_principal_after is
  'Saldo de principal de la cuenta revolving inmediatamente después de este entry.';
comment on column public.cob_financial_ledger.reverses_ledger_id is
  'FK al entry que este reverso anula. Obligatorio cuando entry_type=reversal.';
comment on column public.cob_financial_ledger.metadata is
  'Contexto adicional libre: APR usado en el cálculo, días devengados, '
  'ID externo de referencia, usuario que aprobó, etc.';
-- ── 4. Índices ────────────────────────────────────────────────

-- Historial completo de una cuenta (query principal del estado de cuenta)
create index if not exists cob_financial_ledger_account_date_idx
  on public.cob_financial_ledger (revolving_account_id, effective_date, created_at);
-- Historial de un caso
create index if not exists cob_financial_ledger_case_date_idx
  on public.cob_financial_ledger (org_id, case_id, effective_date desc);
-- Buscar entries vinculados a un pago
create index if not exists cob_financial_ledger_pago_id_idx
  on public.cob_financial_ledger (pago_id)
  where pago_id is not null;
-- Buscar entries vinculados a un plan
create index if not exists cob_financial_ledger_plan_id_idx
  on public.cob_financial_ledger (plan_id)
  where plan_id is not null;
-- Dashboard por tipo de entrada
create index if not exists cob_financial_ledger_org_type_date_idx
  on public.cob_financial_ledger (org_id, entry_type, effective_date desc);
-- Prevención de doble devengo:
-- No puede existir dos finance_charge_accrual con el mismo rango para la misma cuenta
create unique index if not exists cob_financial_ledger_accrual_uidx
  on public.cob_financial_ledger (revolving_account_id, accrual_from, accrual_to)
  where entry_type = 'finance_charge_accrual';
-- Búsqueda de reversos ya emitidos para una entrada
create unique index if not exists cob_financial_ledger_reversal_uidx
  on public.cob_financial_ledger (reverses_ledger_id)
  where entry_type = 'reversal';
-- ── 5. Vista de saldo reconstruido desde ledger ───────────────
-- Útil para auditoría y para fn_recalcular_saldos_revolving.
-- No reemplaza los saldos materializados en cob_revolving_accounts.

create or replace view public.v_ledger_saldos_reconstruidos as
select
  revolving_account_id,
  org_id,
  sum(
    case when component_type = 'principal' and debit_credit = 'debit'  then  amount else 0 end
    - case when component_type = 'principal' and debit_credit = 'credit' then amount else 0 end
  )::numeric(12,2)  as saldo_principal_reconstruido,
  sum(
    case when component_type = 'interest' and debit_credit = 'debit'   then  amount else 0 end
    - case when component_type = 'interest' and debit_credit = 'credit' then amount else 0 end
  )::numeric(12,2)  as saldo_interes_reconstruido,
  sum(
    case when component_type = 'fee'      and debit_credit = 'debit'   then  amount else 0 end
    - case when component_type = 'fee'    and debit_credit = 'credit'   then amount else 0 end
  )::numeric(12,2)  as saldo_fees_reconstruido,
  sum(
    case when debit_credit = 'debit'  then  amount else 0 end
    - case when debit_credit = 'credit' then amount else 0 end
  )::numeric(12,2)  as saldo_total_reconstruido,
  count(*)::int      as total_entries,
  max(effective_date) as ultimo_effective_date
from public.cob_financial_ledger
group by revolving_account_id, org_id;
comment on view public.v_ledger_saldos_reconstruidos is
  'Saldos reconstruidos desde el ledger desde cero (sin usar saldos materializados). '
  'Usar para auditoría o para detectar drift entre ledger y cob_revolving_accounts. '
  'Sin auth.uid(): filtrar por org_id desde el llamador.';
-- ── 6. RLS ────────────────────────────────────────────────────
-- Ledger es append-only e inmutable desde el punto de vista de usuarios.
-- INSERT solo permitido mediante funciones SECURITY DEFINER (0120+).
-- Sin UPDATE ni DELETE policies.

alter table public.cob_financial_ledger enable row level security;
-- Lectura: mismo patrón de cartera
create policy cob_financial_ledger_read
  on public.cob_financial_ledger
  for select to authenticated
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
  );
-- Escritura directa bloqueada para todo usuario autenticado.
-- Las funciones fn_* de 0120+ usan SECURITY DEFINER y bypassean RLS.
create policy cob_financial_ledger_no_direct_write
  on public.cob_financial_ledger
  for insert to authenticated
  with check (false);
commit;
