begin;

create or replace function public.fn_crear_revolving_account_cargo_vuelta(
  p_case_id  uuid,
  p_apr      numeric,
  p_notes    text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id        uuid;
  v_actor_org_id    uuid;
  v_case            record;
  v_existing_id     uuid;
  v_account_id      uuid;
  v_apr             numeric(6,5);
  v_principal       numeric(12,2);
  v_now             timestamptz := now();
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id
    into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  if p_apr is null then
    raise exception 'INVALID_APR: apr_anual es obligatorio y debe estar entre 0.10 y 0.24';
  end if;

  v_apr := round(p_apr::numeric, 5);

  if v_apr < 0.10 or v_apr > 0.24 then
    raise exception 'INVALID_APR: apr_anual debe estar entre 0.10 y 0.24 (0.10 = 10%%, 0.24 = 24%%). Recibido: %', v_apr;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_case_id::text));

  select c.*
    into v_case
  from public.cargo_vuelta_cases c
  where c.id = p_case_id
    and c.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'CASE_NOT_FOUND_OR_FORBIDDEN: caso % no existe o no pertenece a la organización', p_case_id;
  end if;

  if coalesce(v_case.monto_devuelto, 0) <= 0 then
    raise exception 'INVALID_MONTO_DEVUELTO: monto_devuelto debe ser mayor a 0 (caso: %)', p_case_id;
  end if;

  v_principal := round(v_case.monto_devuelto::numeric, 2);

  select a.id
    into v_existing_id
  from public.cob_revolving_accounts a
  where a.case_id = p_case_id
    and a.org_id  = v_actor_org_id
  limit 1;

  if v_existing_id is not null then
    raise exception 'REVOLVING_ACCOUNT_EXISTS: ya existe cuenta revolving % para el caso %',
      v_existing_id, p_case_id;
  end if;

  insert into public.cob_revolving_accounts (
    org_id,
    case_id,
    cliente_id,
    apr_anual,
    metodo_calculo_interes,
    fecha_inicio,
    fecha_ultimo_devengo,
    saldo_principal_inicial,
    saldo_principal_actual,
    saldo_interes_actual,
    saldo_fees_actual,
    estado,
    created_by,
    created_at,
    updated_at
  )
  values (
    v_actor_org_id,
    p_case_id,
    v_case.cliente_id,
    v_apr,
    'daily_simple_365',
    current_date,
    current_date,
    v_principal,
    v_principal,
    0,
    0,
    'activo',
    v_actor_id,
    v_now,
    v_now
  )
  returning id into v_account_id;

  insert into public.cob_financial_ledger (
    org_id,
    revolving_account_id,
    case_id,
    cliente_id,
    entry_date,
    effective_date,
    entry_type,
    component_type,
    debit_credit,
    amount,
    description,
    balance_principal_after,
    balance_interest_after,
    balance_fees_after,
    balance_total_after,
    metadata,
    created_by,
    created_at
  )
  values (
    v_actor_org_id,
    v_account_id,
    p_case_id,
    v_case.cliente_id,
    current_date,
    current_date,
    'principal_initial',
    'principal',
    'debit',
    v_principal,
    coalesce(p_notes, 'Cuenta DFP Revolving abierta desde Cargo de Vuelta'),
    v_principal,
    0,
    0,
    v_principal,
    jsonb_build_object(
      'case_id',        p_case_id,
      'apr_anual',      v_apr,
      'monto_devuelto', v_principal
    ),
    v_actor_id,
    v_now
  );

  return v_account_id;
end;
$$;

comment on function public.fn_crear_revolving_account_cargo_vuelta(uuid, numeric, text) is
  'Abre una cuenta revolving DFP desde un caso Cargo de Vuelta. '
  'Usa monto_devuelto como principal inicial. Crea ledger principal_initial. '
  'Valida org_id dentro de la función. '
  'apr_anual es obligatorio: decimal entre 0.10 (10%%) y 0.24 (24%%), alineado con constraint de 0118. '
  'Null, 0 y valores fuera de rango se rechazan.';


create or replace function public.fn_devengar_interes_revolving(
  p_account_id   uuid,
  p_accrual_date date    default current_date,
  p_notes        text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id              uuid;
  v_actor_org_id          uuid;
  v_account               record;
  v_accrual_from          date;
  v_days                  integer;
  v_interest              numeric(12,2);
  v_new_saldo_interes     numeric(12,2);
  v_new_saldo_total       numeric(12,2);
  v_ledger_id             uuid;
  v_now                   timestamptz := now();
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id
    into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  if p_accrual_date is null then
    raise exception 'INVALID_ACCRUAL_DATE: p_accrual_date no puede ser null';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_account_id::text));

  select a.*
    into v_account
  from public.cob_revolving_accounts a
  where a.id     = p_account_id
    and a.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'ACCOUNT_NOT_FOUND_OR_FORBIDDEN: cuenta % no existe o no pertenece a la organización', p_account_id;
  end if;

  if coalesce(v_account.saldo_principal_actual, 0) <= 0 then
    return null;
  end if;

  if coalesce(v_account.apr_anual, 0) <= 0 then
    return null;
  end if;

  if v_account.fecha_ultimo_devengo >= p_accrual_date then
    return null;
  end if;

  v_accrual_from := v_account.fecha_ultimo_devengo;
  v_days         := p_accrual_date - v_accrual_from;

  if v_days <= 0 then
    return null;
  end if;

  v_interest := round(
    (v_account.saldo_principal_actual::numeric
     * v_account.apr_anual::numeric
     / 365
     * v_days)::numeric,
    2
  );

  if v_interest <= 0 then
    update public.cob_revolving_accounts
       set fecha_ultimo_devengo = p_accrual_date,
           updated_at           = v_now
     where id     = p_account_id
       and org_id = v_actor_org_id;
    return null;
  end if;

  v_new_saldo_interes := round(v_account.saldo_interes_actual::numeric + v_interest, 2);

  v_new_saldo_total := round(
    v_account.saldo_principal_actual::numeric
    + v_new_saldo_interes
    + v_account.saldo_fees_actual::numeric,
    2
  );

  insert into public.cob_financial_ledger (
    org_id,
    revolving_account_id,
    case_id,
    cliente_id,
    entry_date,
    effective_date,
    entry_type,
    component_type,
    debit_credit,
    amount,
    description,
    accrual_from,
    accrual_to,
    balance_principal_after,
    balance_interest_after,
    balance_fees_after,
    balance_total_after,
    metadata,
    created_by,
    created_at
  )
  values (
    v_actor_org_id,
    p_account_id,
    v_account.case_id,
    v_account.cliente_id,
    current_date,
    p_accrual_date,
    'finance_charge_accrual',
    'interest',
    'debit',
    v_interest,
    coalesce(
      p_notes,
      'Devengo de interés DFP Revolving: '
        || v_accrual_from::text || ' → ' || p_accrual_date::text
        || ' (' || v_days::text || ' día(s))'
        || ' @ APR ' || (v_account.apr_anual * 100)::numeric(5,2)::text || '%'
    ),
    v_accrual_from,
    p_accrual_date,
    round(v_account.saldo_principal_actual::numeric, 2),
    v_new_saldo_interes,
    round(v_account.saldo_fees_actual::numeric, 2),
    v_new_saldo_total,
    jsonb_build_object(
      'apr_anual',       v_account.apr_anual,
      'dias_devengados', v_days,
      'accrual_from',    v_accrual_from,
      'accrual_to',      p_accrual_date,
      'principal_base',  v_account.saldo_principal_actual
    ),
    v_actor_id,
    v_now
  )
  returning id into v_ledger_id;

  update public.cob_revolving_accounts
     set saldo_interes_actual  = v_new_saldo_interes,
         fecha_ultimo_devengo  = p_accrual_date,
         updated_at            = v_now
   where id     = p_account_id
     and org_id = v_actor_org_id;

  return v_ledger_id;
end;
$$;

comment on function public.fn_devengar_interes_revolving(uuid, date, text) is
  'Devenga interés interno de una cuenta revolving DFP. '
  'Calcula días desde fecha_ultimo_devengo hasta p_accrual_date. '
  'Fórmula: principal × apr_anual / 365 × días (APR en decimal, 0.18 = 18%). '
  'Persiste interés redondeado a 2 decimales en ledger finance_charge_accrual. '
  'Actualiza saldo_interes_actual y fecha_ultimo_devengo. '
  'Retorna null cuando no hay devengo aplicable (principal=0, APR=0, ya devengado, resultado=0).';


revoke all on function public.fn_crear_revolving_account_cargo_vuelta(uuid, numeric, text)
  from public;

revoke all on function public.fn_devengar_interes_revolving(uuid, date, text)
  from public;

grant execute on function public.fn_crear_revolving_account_cargo_vuelta(uuid, numeric, text)
  to authenticated;

grant execute on function public.fn_devengar_interes_revolving(uuid, date, text)
  to authenticated;

commit;;
