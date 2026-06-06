-- ============================================================
-- 0125: fn_registrar_pago_revolving — pago waterfall DFP Revolving
-- ============================================================

begin;

create or replace function public.fn_registrar_pago_revolving(
  p_account_id  uuid,
  p_monto       numeric,
  p_fecha       date    default current_date,
  p_referencia  text    default null,
  p_notas       text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_account      public.cob_revolving_accounts%rowtype;
  v_caller_org   uuid;
  v_batch_id     uuid    := gen_random_uuid();
  v_monto        numeric(14,2);

  v_aplicado_fees      numeric(14,2) := 0;
  v_aplicado_interes   numeric(14,2) := 0;
  v_aplicado_principal numeric(14,2) := 0;
  v_excedente          numeric(14,2) := 0;
  v_restante           numeric(14,2);

  v_bal_fees_post      numeric(14,2);
  v_bal_interes_post   numeric(14,2);
  v_bal_principal_post numeric(14,2);

  v_desc_suffix  text;
  v_estado_final text;
begin

  if p_monto is null or p_monto <= 0 then
    raise exception 'INVALID_AMOUNT: p_monto debe ser mayor a 0';
  end if;
  v_monto := round(p_monto, 2);

  select u.org_id into v_caller_org
  from public.usuarios u
  where u.id = auth.uid()
  limit 1;

  if v_caller_org is null then
    raise exception 'UNAUTHORIZED: usuario sin org_id';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_account_id::text));

  select * into v_account
  from public.cob_revolving_accounts
  where id      = p_account_id
    and org_id  = v_caller_org
  for update;

  if not found then
    raise exception 'ACCOUNT_NOT_FOUND: cuenta revolving no existe o pertenece a otra organización';
  end if;

  if v_account.estado in ('completado', 'cancelado', 'writeoff') then
    raise exception 'ACCOUNT_CLOSED: la cuenta está en estado "%" y no acepta pagos',
      v_account.estado;
  end if;

  if v_account.saldo_principal_actual = 0
     and v_account.saldo_interes_actual = 0
     and v_account.saldo_fees_actual    = 0
  then
    raise exception 'ZERO_BALANCE: la cuenta ya tiene saldo total en cero';
  end if;

  -- Waterfall estricto: fees → interest → principal
  v_restante := v_monto;

  v_aplicado_fees      := least(v_restante, v_account.saldo_fees_actual);
  v_restante           := v_restante - v_aplicado_fees;

  v_aplicado_interes   := least(v_restante, v_account.saldo_interes_actual);
  v_restante           := v_restante - v_aplicado_interes;

  v_aplicado_principal := least(v_restante, v_account.saldo_principal_actual);
  v_restante           := v_restante - v_aplicado_principal;

  v_excedente := v_restante;

  v_bal_fees_post      := v_account.saldo_fees_actual      - v_aplicado_fees;
  v_bal_interes_post   := v_account.saldo_interes_actual   - v_aplicado_interes;
  v_bal_principal_post := v_account.saldo_principal_actual - v_aplicado_principal;

  v_desc_suffix := case
    when p_referencia is not null then ' | ref: ' || p_referencia
    else ''
  end;

  -- Ledger: una fila por componente con monto > 0
  if v_aplicado_fees > 0 then
    insert into public.cob_financial_ledger (
      org_id, revolving_account_id, case_id, cliente_id,
      entry_date, effective_date,
      entry_type, component_type, debit_credit, amount,
      description,
      balance_principal_after, balance_interest_after,
      balance_fees_after,      balance_total_after,
      metadata, created_by
    ) values (
      v_account.org_id, v_account.id, v_account.case_id, v_account.cliente_id,
      current_date, p_fecha,
      'payment_applied', 'fee', 'credit', v_aplicado_fees,
      coalesce(p_notas, 'Pago — fee') || v_desc_suffix,
      v_account.saldo_principal_actual,
      v_account.saldo_interes_actual,
      v_bal_fees_post,
      v_account.saldo_principal_actual + v_account.saldo_interes_actual + v_bal_fees_post,
      jsonb_build_object('batch_id', v_batch_id, 'referencia', p_referencia, 'waterfall_step', 1, 'pago_id', null),
      auth.uid()
    );
  end if;

  if v_aplicado_interes > 0 then
    insert into public.cob_financial_ledger (
      org_id, revolving_account_id, case_id, cliente_id,
      entry_date, effective_date,
      entry_type, component_type, debit_credit, amount,
      description,
      balance_principal_after, balance_interest_after,
      balance_fees_after,      balance_total_after,
      metadata, created_by
    ) values (
      v_account.org_id, v_account.id, v_account.case_id, v_account.cliente_id,
      current_date, p_fecha,
      'payment_applied', 'interest', 'credit', v_aplicado_interes,
      coalesce(p_notas, 'Pago — interés') || v_desc_suffix,
      v_account.saldo_principal_actual,
      v_bal_interes_post,
      v_bal_fees_post,
      v_account.saldo_principal_actual + v_bal_interes_post + v_bal_fees_post,
      jsonb_build_object('batch_id', v_batch_id, 'referencia', p_referencia, 'waterfall_step', 2, 'pago_id', null),
      auth.uid()
    );
  end if;

  if v_aplicado_principal > 0 then
    insert into public.cob_financial_ledger (
      org_id, revolving_account_id, case_id, cliente_id,
      entry_date, effective_date,
      entry_type, component_type, debit_credit, amount,
      description,
      balance_principal_after, balance_interest_after,
      balance_fees_after,      balance_total_after,
      metadata, created_by
    ) values (
      v_account.org_id, v_account.id, v_account.case_id, v_account.cliente_id,
      current_date, p_fecha,
      'payment_applied', 'principal', 'credit', v_aplicado_principal,
      coalesce(p_notas, 'Pago — principal') || v_desc_suffix,
      v_bal_principal_post,
      v_bal_interes_post,
      v_bal_fees_post,
      v_bal_principal_post + v_bal_interes_post + v_bal_fees_post,
      jsonb_build_object('batch_id', v_batch_id, 'referencia', p_referencia, 'waterfall_step', 3, 'pago_id', null),
      auth.uid()
    );
  end if;

  -- Actualizar saldos — saldo_total_actual es GENERATED, no se toca
  v_estado_final := case
    when v_bal_principal_post = 0
     and v_bal_interes_post   = 0
     and v_bal_fees_post      = 0
    then 'completado'
    else v_account.estado
  end;

  update public.cob_revolving_accounts
  set
    saldo_principal_actual = v_bal_principal_post,
    saldo_interes_actual   = v_bal_interes_post,
    saldo_fees_actual      = v_bal_fees_post,
    estado                 = v_estado_final,
    updated_at             = now()
  where id = p_account_id;

  return jsonb_build_object(
    'account_id',            p_account_id,
    'batch_id',              v_batch_id,
    'fecha',                 p_fecha,
    'monto_recibido',        v_monto,
    'aplicado_fees',         v_aplicado_fees,
    'aplicado_interes',      v_aplicado_interes,
    'aplicado_principal',    v_aplicado_principal,
    'excedente',             v_excedente,
    'nuevo_saldo_fees',      v_bal_fees_post,
    'nuevo_saldo_interes',   v_bal_interes_post,
    'nuevo_saldo_principal', v_bal_principal_post,
    'nuevo_saldo_total',     v_bal_principal_post + v_bal_interes_post + v_bal_fees_post,
    'estado_cuenta',         v_estado_final
  );
end;
$$;

revoke all    on function public.fn_registrar_pago_revolving(uuid, numeric, date, text, text) from public, anon;
grant execute on function public.fn_registrar_pago_revolving(uuid, numeric, date, text, text) to authenticated;

comment on function public.fn_registrar_pago_revolving(uuid, numeric, date, text, text) is
  'Registra un pago sobre una cuenta DFP Revolving con waterfall estricto fees→interest→principal. '
  'SECURITY DEFINER: valida org_id del llamador, lock de cuenta, inserta en ledger (payment_applied), '
  'actualiza saldos en cob_revolving_accounts, y transiciona a completado si saldo total = 0. '
  'Excedente: si p_monto > saldo_total, la diferencia se devuelve en JSONB sin aplicar. '
  'pago_id = null — tabla de pagos pendiente (hueco conocido, documentado). '
  'Sin excepciones al waterfall en esta versión (0125). '
  'Flujos especiales (ajuste manual, reasignación) van en funciones separadas (0126+).';

commit;
;
