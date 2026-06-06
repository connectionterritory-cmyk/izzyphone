begin;
-- 0156: fix statement generator to include principal_initial in header totals
--
-- Contexto:
-- 0155 generaba statement_lines correctamente, pero el header podía quedar
-- desalineado cuando el único movimiento del período era principal_initial.
--
-- Corrección:
-- - compras_periodo incluye TODO debit de component_type='principal'
--   (incluyendo entry_type='principal_initial').
-- - nuevo_balance queda alineado con la suma neta de líneas + balance_previo.
--
-- No cambia:
-- - idempotencia (STATEMENT_EXISTS)
-- - due date (fn_calcular_due_date)
-- - no genera pagos, no genera late fees, no toca cron.

create or replace function public.fn_cob_statement_generar(
  p_revolving_account_id  uuid,
  p_periodo_inicio        date,
  p_periodo_fin           date,
  p_fecha_corte           date    default null,
  p_notas                 text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id               uuid;
  v_actor_org_id           uuid;
  v_account                record;
  v_fecha_corte            date;
  v_fecha_vencimiento      date;
  v_ytd_inicio             date;
  v_dias_ciclo             integer;

  v_balance_previo         numeric(12,2);
  v_balance_sujeto_int     numeric(12,2);
  v_pagos_periodo          numeric(12,2);
  v_otros_creditos         numeric(12,2);
  v_compras_periodo        numeric(12,2);
  v_cargos_interes         numeric(12,2);
  v_cargos_fees            numeric(12,2);
  v_nuevo_balance          numeric(12,2);
  v_ytd_fees               numeric(12,2);
  v_ytd_interes            numeric(12,2);
  v_tasa_diaria            numeric(12,10);

  v_existing_id            uuid;
  v_statement_id           uuid;
  v_now                    timestamptz := now();
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  if p_revolving_account_id is null then
    raise exception 'INVALID_PARAM: p_revolving_account_id es requerido';
  end if;
  if p_periodo_inicio is null or p_periodo_fin is null then
    raise exception 'INVALID_PARAM: p_periodo_inicio y p_periodo_fin son requeridos';
  end if;
  if p_periodo_inicio > p_periodo_fin then
    raise exception 'INVALID_PARAM: p_periodo_inicio (%) no puede ser posterior a p_periodo_fin (%)',
      p_periodo_inicio, p_periodo_fin;
  end if;

  v_fecha_corte := coalesce(p_fecha_corte, p_periodo_fin);

  if v_fecha_corte < p_periodo_inicio or v_fecha_corte > p_periodo_fin then
    raise exception 'INVALID_FECHA_CORTE: fecha_corte (%) debe estar entre % y %',
      v_fecha_corte, p_periodo_inicio, p_periodo_fin;
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      p_revolving_account_id::text
      || '|' || p_periodo_inicio::text
      || '|' || p_periodo_fin::text
    )
  );

  select a.* into v_account
  from public.cob_revolving_accounts a
  where a.id     = p_revolving_account_id
    and a.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'ACCOUNT_NOT_FOUND_OR_FORBIDDEN: cuenta % no existe o no pertenece a la organización',
      p_revolving_account_id;
  end if;

  select s.id into v_existing_id
  from public.cob_statements s
  where s.revolving_account_id = p_revolving_account_id
    and s.org_id               = v_actor_org_id
    and s.periodo_inicio       = p_periodo_inicio
    and s.periodo_fin          = p_periodo_fin
  limit 1;

  if v_existing_id is not null then
    raise exception 'STATEMENT_EXISTS: ya existe statement % para el período % → %',
      v_existing_id, p_periodo_inicio, p_periodo_fin;
  end if;

  v_dias_ciclo  := (p_periodo_fin - p_periodo_inicio + 1)::integer;
  v_ytd_inicio  := make_date(extract(year from p_periodo_fin)::integer, 1, 1);
  v_tasa_diaria := round(v_account.apr_anual / 365.0, 10);

  v_fecha_vencimiento := public.fn_calcular_due_date(
    v_fecha_corte,
    v_account.min_days_statement_to_due,
    v_account.customer_preferred_payment_day
  );

  select coalesce(sum(
    case when debit_credit = 'debit' then amount else -amount end
  ), 0)::numeric(12,2)
  into v_balance_previo
  from public.cob_financial_ledger l
  where l.revolving_account_id = p_revolving_account_id
    and l.effective_date < p_periodo_inicio;

  v_balance_previo := greatest(v_balance_previo, 0);

  select coalesce(sum(
    case
      when component_type = 'principal' and debit_credit = 'debit'  then  amount
      when component_type = 'principal' and debit_credit = 'credit' then -amount
      else 0
    end
  ), 0)::numeric(12,2)
  into v_balance_sujeto_int
  from public.cob_financial_ledger l
  where l.revolving_account_id = p_revolving_account_id
    and l.effective_date < p_periodo_inicio;

  v_balance_sujeto_int := greatest(v_balance_sujeto_int, 0);

  select
    coalesce(sum(case
      when entry_type = 'payment_applied' and debit_credit = 'credit'
      then amount else 0 end), 0)::numeric(12,2),

    coalesce(sum(case
      when entry_type in ('adjustment', 'reversal') and debit_credit = 'credit'
      then amount else 0 end), 0)::numeric(12,2),

    -- FIX 0156: incluir principal_initial dentro de compras_periodo
    coalesce(sum(case
      when component_type = 'principal'
        and debit_credit = 'debit'
      then amount else 0 end), 0)::numeric(12,2),

    coalesce(sum(case
      when component_type = 'interest' and debit_credit = 'debit'
      then amount else 0 end), 0)::numeric(12,2),

    coalesce(sum(case
      when component_type = 'fee' and debit_credit = 'debit'
      then amount else 0 end), 0)::numeric(12,2)

  into
    v_pagos_periodo,
    v_otros_creditos,
    v_compras_periodo,
    v_cargos_interes,
    v_cargos_fees

  from public.cob_financial_ledger l
  where l.revolving_account_id = p_revolving_account_id
    and l.effective_date >= p_periodo_inicio
    and l.effective_date <= p_periodo_fin;

  select
    coalesce(sum(case
      when component_type = 'fee'      and debit_credit = 'debit' then amount else 0 end), 0)::numeric(12,2),
    coalesce(sum(case
      when component_type = 'interest' and debit_credit = 'debit' then amount else 0 end), 0)::numeric(12,2)
  into
    v_ytd_fees,
    v_ytd_interes
  from public.cob_financial_ledger l
  where l.revolving_account_id = p_revolving_account_id
    and l.effective_date >= v_ytd_inicio
    and l.effective_date <= p_periodo_fin;

  v_nuevo_balance := round(
    v_balance_previo
    + v_compras_periodo
    + v_cargos_interes
    + v_cargos_fees
    - v_pagos_periodo
    - v_otros_creditos,
    2
  );
  v_nuevo_balance := greatest(v_nuevo_balance, 0);

  insert into public.cob_statements (
    org_id,
    cliente_id,
    case_id,
    revolving_account_id,
    periodo_inicio,
    periodo_fin,
    fecha_corte,
    fecha_vencimiento,
    dias_ciclo_facturacion,
    balance_previo,
    pagos_periodo,
    otros_creditos,
    compras_periodo,
    balance_atrasado,
    cargos_totales_periodo,
    apr_tae,
    tasa_diaria,
    balance_sujeto_interes,
    cargos_interes_periodo,
    nuevo_balance,
    pago_minimo,
    ytd_cargos_atraso,
    ytd_cargos_interes,
    mensaje_pago,
    status,
    generated_by,
    metadata,
    created_at,
    updated_at
  )
  values (
    v_actor_org_id,
    v_account.cliente_id,
    v_account.case_id,
    p_revolving_account_id,
    p_periodo_inicio,
    p_periodo_fin,
    v_fecha_corte,
    v_fecha_vencimiento,
    v_dias_ciclo,
    v_balance_previo,
    v_pagos_periodo,
    v_otros_creditos,
    v_compras_periodo,
    v_balance_previo,
    v_cargos_fees,
    v_account.apr_anual,
    v_tasa_diaria,
    v_balance_sujeto_int,
    v_cargos_interes,
    v_nuevo_balance,
    v_nuevo_balance,
    v_ytd_fees,
    v_ytd_interes,
    coalesce(
      p_notas,
      'Por favor realice su pago antes del '
        || to_char(v_fecha_vencimiento, 'DD/MM/YYYY')
        || ' para evitar cargos adicionales.'
    ),
    'draft',
    v_actor_id,
    jsonb_build_object(
      'account_apr',               v_account.apr_anual,
      'account_estado',            v_account.estado,
      'dias_ciclo',                v_dias_ciclo,
      'closing_day',               v_account.statement_closing_day,
      'preferred_payment_day',     v_account.customer_preferred_payment_day,
      'min_days_statement_to_due', v_account.min_days_statement_to_due,
      'fix_version',               '0156_principal_initial_in_header'
    ),
    v_now,
    v_now
  )
  returning id into v_statement_id;

  insert into public.cob_statement_lines (
    org_id,
    statement_id,
    revolving_account_id,
    ledger_entry_id,
    line_order,
    transaction_date,
    posting_date,
    entry_type,
    component_type,
    description,
    amount,
    metadata
  )
  select
    v_actor_org_id,
    v_statement_id,
    p_revolving_account_id,
    l.id,
    row_number() over (order by l.effective_date asc, l.created_at asc)::integer,
    l.effective_date,
    l.entry_date,
    l.entry_type,
    l.component_type,
    coalesce(l.description, l.entry_type),
    case when l.debit_credit = 'debit' then l.amount else -l.amount end,
    jsonb_build_object(
      'debit_credit',    l.debit_credit,
      'original_amount', l.amount
    )
  from public.cob_financial_ledger l
  where l.revolving_account_id = p_revolving_account_id
    and l.effective_date >= p_periodo_inicio
    and l.effective_date <= p_periodo_fin
  order by l.effective_date asc, l.created_at asc;

  return v_statement_id;
end;
$$;
comment on function public.fn_cob_statement_generar(uuid, date, date, date, text) is
  '0156 fix: incluye principal_initial en compras_periodo para cuadrar header con líneas. '
  'Genera snapshot en cob_statements + cob_statement_lines sin mutar ledger.';
revoke all on function public.fn_cob_statement_generar(uuid, date, date, date, text)
  from public, anon;
grant execute on function public.fn_cob_statement_generar(uuid, date, date, date, text)
  to authenticated;
commit;
