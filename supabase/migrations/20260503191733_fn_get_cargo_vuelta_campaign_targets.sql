
create or replace function public.fn_get_cargo_vuelta_campaign_targets(
  p_org_id uuid,
  p_today date default current_date,
  p_max_auto_attempts int default 7,
  p_recent_payment_days int default 7,
  p_daily_cooldown_hours int default 20,
  p_mock boolean default true
)
returns table (
  case_id uuid,
  org_id uuid,
  cliente_id uuid,
  owner_id uuid,
  nombre text,
  apellido text,
  email text,
  telefono text,
  telefono_casa text,
  fecha_cargo_vuelta date,
  monto_cargo_vuelta numeric,
  dias_vencido int,
  estado text,
  cuenta_hycite text,
  auto_attempt_count int,
  last_message_at timestamptz,
  days_since_case_opened int,
  cadence_step text,
  should_send_email boolean,
  should_send_whatsapp boolean,
  mock boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with case_base as (
    select
      cv.id as case_id,
      cv.org_id,
      cv.cliente_id,
      cv.fecha_apertura,
      cv.fecha_cargo_vuelta,
      cv.monto_devuelto,
      cv.dias_vencido,
      cv.estado,
      cv.acuerdo_tipo,
      cv.numero_cuenta_hycite,
      cv.numero_orden_hycite,
      c.nombre,
      c.apellido,
      c.email,
      c.telefono,
      c.telefono_casa,
      c.hycite_id,
      c.whatsapp_no_molestar,
      c.whatsapp_opt_in,
      c.whatsapp_ultimo_envio_at
    from public.cargo_vuelta_cases cv
    join public.clientes c
      on c.id = cv.cliente_id
     and c.org_id = cv.org_id
    where cv.org_id = p_org_id
      and cv.estado is distinct from 'Cerrado'
      and coalesce(cv.monto_devuelto, 0) > 0
      and (
        nullif(trim(coalesce(c.email, '')), '') is not null
        or nullif(trim(coalesce(c.telefono, c.telefono_casa, '')), '') is not null
      )
      and (
        cv.acuerdo_tipo is null
        or trim(cv.acuerdo_tipo) = ''
        or lower(trim(cv.acuerdo_tipo)) in ('ninguno', 'none', 'cancelado', 'cerrado')
      )
      and coalesce(c.whatsapp_no_molestar, false) = false
  ),
  message_stats as (
    select
      cb.case_id,
      count(om.id)::int as auto_attempt_count,
      max(coalesce(om.sent_at, om.created_at)) as last_message_at
    from case_base cb
    left join public.outbox_messages om
      on om.contact_tipo = 'cliente'
     and om.contact_id = cb.cliente_id
     and om.org_id = cb.org_id::text
     and om.contexto_tipo = 'cobranza'
     and om.canal in ('email', 'whatsapp', 'sms')
     and om.status in ('programado', 'en_proceso', 'enviado', 'retry_pending')
     and (
       om.dispatch_provider in ('n8n', 'n8n_mock')
       or om.provider in ('resend_mock', 'evolution_mock', 'whatsapp_cloud_mock')
       or coalesce(om.asunto, '') ilike '%revision de cuenta royal prestige%'
       or coalesce(om.mensaje_resuelto, om.mensaje, '') ilike '%royal prestige / hy-cite%'
       or coalesce(om.mensaje_resuelto, om.mensaje, '') ilike '%cargo de vuelta%'
       or coalesce(om.mensaje_resuelto, om.mensaje, '') ilike '%dfp%'
     )
    group by cb.case_id
  ),
  eligible as (
    select
      cb.*,
      coalesce(ms.auto_attempt_count, 0) as auto_attempt_count,
      ms.last_message_at,
      greatest((p_today - cb.fecha_apertura::date), 0)::int as days_since_case_opened,
      case
        when coalesce(ms.auto_attempt_count, 0) = 0 then 'formal_amable'
        when coalesce(ms.auto_attempt_count, 0) = 1 then 'recordatorio_corto'
        when coalesce(ms.auto_attempt_count, 0) = 2 then 'revision_interna'
        when coalesce(ms.auto_attempt_count, 0) = 3
          and greatest((p_today - cb.fecha_apertura::date), 0) >= 5
          then 'ultimo_intento'
        when coalesce(ms.auto_attempt_count, 0) >= 4
          and greatest((p_today - coalesce(ms.last_message_at::date, cb.fecha_apertura::date)), 0) >= 3
          then 'seguimiento_3_dias'
        else null
      end as cadence_step
    from case_base cb
    left join message_stats ms
      on ms.case_id = cb.case_id
    where coalesce(ms.auto_attempt_count, 0) < p_max_auto_attempts
      and (
        ms.last_message_at is null
        or ms.last_message_at <= (
          ((p_today::timestamp + localtime) at time zone current_setting('timezone'))
          - make_interval(hours => p_daily_cooldown_hours)
        )
      )
      and not exists (
        select 1
        from public.cob_ptps ptp
        where ptp.org_id = cb.org_id
          and ptp.cliente_id = cb.cliente_id
          and (ptp.case_id = cb.case_id or ptp.case_id is null)
          and ptp.estado in ('pendiente')
      )
      and not exists (
        select 1
        from public.cob_plan_pagos plan
        where plan.org_id = cb.org_id
          and plan.cliente_id = cb.cliente_id
          and (plan.case_id = cb.case_id or plan.case_id is null)
          and plan.estado = 'activo'
      )
      and not exists (
        select 1
        from public.cob_pagos pago
        where pago.org_id = cb.org_id
          and pago.cliente_id = cb.cliente_id
          and (pago.case_id = cb.case_id or pago.case_id is null)
          and pago.fecha_pago >= (p_today - p_recent_payment_days)
      )
  )
  select
    e.case_id,
    e.org_id,
    e.cliente_id,
    null::uuid as owner_id,
    e.nombre,
    e.apellido,
    nullif(trim(coalesce(e.email, '')), '') as email,
    nullif(trim(coalesce(e.telefono, e.telefono_casa, '')), '') as telefono,
    e.telefono_casa,
    e.fecha_cargo_vuelta,
    e.monto_devuelto as monto_cargo_vuelta,
    e.dias_vencido,
    e.estado,
    coalesce(
      nullif(trim(coalesce(e.numero_cuenta_hycite, '')), ''),
      nullif(trim(coalesce(e.hycite_id, '')), ''),
      nullif(trim(coalesce(e.numero_orden_hycite, '')), '')
    ) as cuenta_hycite,
    e.auto_attempt_count,
    e.last_message_at,
    e.days_since_case_opened,
    e.cadence_step,
    nullif(trim(coalesce(e.email, '')), '') is not null as should_send_email,
    (
      nullif(trim(coalesce(e.telefono, e.telefono_casa, '')), '') is not null
      and coalesce(e.whatsapp_no_molestar, false) = false
    ) as should_send_whatsapp,
    p_mock as mock
  from eligible e
  where e.cadence_step is not null
    and (
      nullif(trim(coalesce(e.email, '')), '') is not null
      or (
        nullif(trim(coalesce(e.telefono, e.telefono_casa, '')), '') is not null
        and coalesce(e.whatsapp_no_molestar, false) = false
      )
    )
  order by e.days_since_case_opened desc, e.monto_devuelto desc, e.case_id;
$$;

revoke all on function public.fn_get_cargo_vuelta_campaign_targets(uuid, date, int, int, int, boolean) from public;
revoke execute on function public.fn_get_cargo_vuelta_campaign_targets(uuid, date, int, int, int, boolean) from anon;
grant execute on function public.fn_get_cargo_vuelta_campaign_targets(uuid, date, int, int, int, boolean) to authenticated;
grant execute on function public.fn_get_cargo_vuelta_campaign_targets(uuid, date, int, int, int, boolean) to service_role;

comment on function public.fn_get_cargo_vuelta_campaign_targets(uuid, date, int, int, int, boolean) is
  'Selecciona casos Cargo de Vuelta / DFP elegibles para campana automatica n8n. Read-only: no inserta, no toca ledger, no registra pagos.';
;
