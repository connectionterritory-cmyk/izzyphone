begin;
-- 0153_dfp_calendar_fields
--
-- Agrega campos de configuración de ciclo de facturación DFP a
-- cob_revolving_accounts y tasa_diaria a cob_statements.
--
-- Estos campos son necesarios para que fn_cob_statement_generar (Fase 2)
-- pueda calcular due dates y documentar la tasa diaria usada en cada ciclo.
--
-- Rollback manual:
--   alter table public.cob_revolving_accounts
--     drop column if exists statement_closing_day,
--     drop column if exists customer_preferred_payment_day,
--     drop column if exists min_days_statement_to_due,
--     drop column if exists agreement_date;
--   alter table public.cob_statements
--     drop column if exists tasa_diaria;
--   drop index if exists idx_cob_revolving_accounts_closing_day;
--   drop index if exists idx_cob_revolving_accounts_preferred_day;

-- ── cob_revolving_accounts: campos de calendario ──────────────────────────────

-- Día del mes en que cierra el ciclo de facturación (1–28).
-- NULL = sin ciclo configurado todavía (operación manual).
-- Limitado a 28 para evitar problemas con febrero.
-- Ejemplo: 6 → el ciclo cierra cada día 6 del mes.
alter table public.cob_revolving_accounts
  add column if not exists statement_closing_day smallint
    check (statement_closing_day between 1 and 28);
-- Día del mes preferido del cliente para pagar (1–28).
-- NULL = sin preferencia registrada.
-- fn_calcular_due_date usa este campo como target para la due date,
-- sujeto a min_days_statement_to_due.
alter table public.cob_revolving_accounts
  add column if not exists customer_preferred_payment_day smallint
    check (customer_preferred_payment_day between 1 and 28);
-- Mínimo de días que deben pasar entre fecha_corte y fecha_vencimiento.
-- DEFAULT 21 (estándar CARD Act como referencia para ciclos de crédito).
-- Protege al cliente: el statement siempre da al menos N días para pagar.
alter table public.cob_revolving_accounts
  add column if not exists min_days_statement_to_due smallint
    not null default 21
    check (min_days_statement_to_due >= 7);
-- Fecha del acuerdo/contrato original con el distribuidor.
-- Puede diferir de fecha_inicio (cuando se abrió la cuenta en el sistema).
-- NULL = no capturado todavía.
alter table public.cob_revolving_accounts
  add column if not exists agreement_date date;
-- Constraint: si statement_closing_day está seteado, min_days_statement_to_due
-- debe existir (ya tiene default 21, así que este check es defensivo).
alter table public.cob_revolving_accounts
  drop constraint if exists chk_cob_rev_closing_day_requires_min_days;
alter table public.cob_revolving_accounts
  add constraint chk_cob_rev_closing_day_requires_min_days
  check (
    statement_closing_day is null
    or min_days_statement_to_due is not null
  );
-- Constraint: agreement_date no puede ser posterior a hoy (validación defensiva).
-- Se omite aquí para no bloquear backfill de datos históricos.
-- La validación queda en la RPC de apertura.

-- ── Índices para future cron/n8n ──────────────────────────────────────────────

-- Buscar cuentas que deben generar statement hoy:
--   WHERE statement_closing_day = extract(day from current_date)
--   AND estado IN ('activo', 'moroso', 'en_plan')
create index if not exists idx_cob_revolving_accounts_closing_day
  on public.cob_revolving_accounts (statement_closing_day, estado)
  where statement_closing_day is not null
    and estado in ('activo', 'moroso', 'en_plan');
-- Lookup por día preferido del cliente (útil para reporting de cobranza):
create index if not exists idx_cob_revolving_accounts_preferred_day
  on public.cob_revolving_accounts (customer_preferred_payment_day)
  where customer_preferred_payment_day is not null;
-- ── cob_statements: tasa diaria auditada ─────────────────────────────────────

-- Tasa diaria efectiva usada en el cálculo del ciclo:
--   tasa_diaria = apr_tae / 365
-- Se guarda explícitamente para que el statement sea un snapshot completo
-- y auditable sin recalcular. NULL si el statement no tiene finance charge.
alter table public.cob_statements
  add column if not exists tasa_diaria numeric(12, 10)
    check (tasa_diaria is null or tasa_diaria > 0);
-- Constraint: si hay cargos_interes_periodo > 0, tasa_diaria debe estar presente.
alter table public.cob_statements
  drop constraint if exists chk_cob_statements_tasa_diaria_required;
alter table public.cob_statements
  add constraint chk_cob_statements_tasa_diaria_required
  check (
    cargos_interes_periodo = 0
    or tasa_diaria is not null
  );
commit;
