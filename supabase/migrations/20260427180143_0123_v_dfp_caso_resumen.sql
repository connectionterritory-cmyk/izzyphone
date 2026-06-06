begin;

create or replace view public.v_dfp_caso_resumen
  with (security_invoker = true)
as

with

ultimo_ledger as (
  select distinct on (revolving_account_id)
    revolving_account_id,
    id             as ultimo_ledger_id,
    entry_type     as ultimo_entry_type,
    component_type as ultimo_component_type,
    amount         as ultimo_amount,
    effective_date as ultimo_ledger_fecha
  from public.cob_financial_ledger
  order by revolving_account_id, effective_date desc, created_at desc
),

ledger_tiene_inicial as (
  select
    revolving_account_id,
    true as tiene_principal_initial
  from public.cob_financial_ledger
  where entry_type = 'principal_initial'
  group by revolving_account_id
)

select

  c.id            as case_id,
  c.org_id,
  c.cliente_id,

  c.tipo_caso,
  c.alias_operativo,
  c.estado                                as estado_caso,
  c.fecha_apertura,
  c.fecha_cierre,
  c.fecha_cargo_vuelta,
  c.monto_devuelto,
  c.requiere_reconciliacion,
  c.numero_cuenta_hycite,
  c.numero_orden_hycite,
  c.origen_cargo_vuelta,

  a.id                                    as account_id,
  a.apr_anual,
  a.metodo_calculo_interes,
  a.fecha_inicio,
  a.fecha_ultimo_devengo,
  a.saldo_principal_inicial,
  a.saldo_principal_actual,
  a.saldo_interes_actual,
  a.saldo_fees_actual,
  a.saldo_total_actual                    as saldo_operativo_interno,
  a.estado                                as estado_cuenta,

  ul.ultimo_entry_type,
  ul.ultimo_component_type,
  ul.ultimo_ledger_fecha,
  ul.ultimo_amount                        as ultimo_ledger_monto,

  lr.saldo_principal_reconstruido,
  lr.saldo_interes_reconstruido,
  lr.saldo_fees_reconstruido,
  lr.saldo_total_reconstruido,
  lr.total_entries                        as ledger_total_entries,

  case
    when a.id is not null and lr.revolving_account_id is not null
    then round(
      coalesce(a.saldo_total_actual, 0) - coalesce(lr.saldo_total_reconstruido, 0),
      2
    )
    else null
  end                                     as drift_saldo_total,

  case
    when a.id is not null
     and coalesce(li.tiene_principal_initial, false) = false
    then true
    else false
  end                                     as requiere_configuracion,

  case
    when a.id is not null
     and lr.revolving_account_id is not null
     and abs(
       coalesce(a.saldo_total_actual, 0) - coalesce(lr.saldo_total_reconstruido, 0)
     ) > 0.01
    then true
    else false
  end                                     as requiere_revision_saldos,

  case
    when a.id is null
     and coalesce(c.monto_devuelto, 0) > 0
     and c.tipo_caso = 'cargo_vuelta'
     and c.estado not in ('Cerrado', 'Cancelado')
    then true
    else false
  end                                     as puede_crear_cuenta_revolving,

  case
    when a.id is not null
     and a.apr_anual between 0.10 and 0.24
     and coalesce(a.saldo_principal_actual, 0) > 0
     and a.fecha_ultimo_devengo < current_date
     and a.estado in ('activo', 'moroso', 'en_plan')
    then true
    else false
  end                                     as puede_devengar_interes

from public.cargo_vuelta_cases c

left join public.cob_revolving_accounts a
  on  a.case_id = c.id
  and a.org_id  = c.org_id

left join ultimo_ledger ul
  on ul.revolving_account_id = a.id

left join public.v_ledger_saldos_reconstruidos lr
  on  lr.revolving_account_id = a.id
  and lr.org_id               = a.org_id

left join ledger_tiene_inicial li
  on li.revolving_account_id = a.id

where c.tipo_caso = 'cargo_vuelta';


comment on view public.v_dfp_caso_resumen is
  'Vista read-only de soporte UI para casos Cargo de Vuelta / DFP. '
  'Unifica cargo_vuelta_cases, cob_revolving_accounts, cob_financial_ledger '
  'y v_ledger_saldos_reconstruidos. '
  'SECURITY INVOKER: RLS de las tablas base se aplica al llamador. '
  'Sin auth.uid(): siempre filtrar por org_id desde el frontend o un RPC. '
  'Solo muestra tipo_caso=cargo_vuelta. '
  'Las banderas puede_* son informativas para UI; la autorización real vive en las RPCs.';

commit;;
