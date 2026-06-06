-- ============================================================
-- 0132_whatsapp_campaign_consent.sql
-- Consentimiento minimo para campanas WhatsApp + trazabilidad ultimo envio.
--
-- No depende de las migraciones 0126-0129.
-- ============================================================

begin;

alter table if exists public.clientes
  add column if not exists whatsapp_opt_in boolean not null default false,
  add column if not exists whatsapp_no_molestar boolean not null default false,
  add column if not exists whatsapp_ultimo_envio_at timestamptz,
  add column if not exists whatsapp_consent_source text,
  add column if not exists whatsapp_consented_at timestamptz;

alter table if exists public.leads
  add column if not exists whatsapp_opt_in boolean not null default false,
  add column if not exists whatsapp_no_molestar boolean not null default false,
  add column if not exists whatsapp_ultimo_envio_at timestamptz,
  add column if not exists whatsapp_consent_source text,
  add column if not exists whatsapp_consented_at timestamptz;

alter table if exists public.contactos
  add column if not exists whatsapp_opt_in boolean not null default false,
  add column if not exists whatsapp_no_molestar boolean not null default false,
  add column if not exists whatsapp_ultimo_envio_at timestamptz,
  add column if not exists whatsapp_consent_source text,
  add column if not exists whatsapp_consented_at timestamptz;

comment on column public.clientes.whatsapp_opt_in is
  'Consentimiento explicito para recibir campanas WhatsApp.';
comment on column public.clientes.whatsapp_no_molestar is
  'Bloquea campanas WhatsApp aunque exista opt-in.';
comment on column public.clientes.whatsapp_ultimo_envio_at is
  'Ultimo envio WhatsApp registrado desde outbox_messages.';
comment on column public.clientes.whatsapp_consent_source is
  'Fuente del consentimiento WhatsApp: formulario, manual, importacion, contrato, etc.';
comment on column public.clientes.whatsapp_consented_at is
  'Fecha/hora en que se registro el consentimiento WhatsApp.';

comment on column public.leads.whatsapp_opt_in is
  'Consentimiento explicito para recibir campanas WhatsApp.';
comment on column public.leads.whatsapp_no_molestar is
  'Bloquea campanas WhatsApp aunque exista opt-in.';
comment on column public.leads.whatsapp_ultimo_envio_at is
  'Ultimo envio WhatsApp registrado desde outbox_messages.';
comment on column public.leads.whatsapp_consent_source is
  'Fuente del consentimiento WhatsApp: formulario, manual, importacion, contrato, etc.';
comment on column public.leads.whatsapp_consented_at is
  'Fecha/hora en que se registro el consentimiento WhatsApp.';

create index if not exists clientes_whatsapp_campaign_eligible_idx
  on public.clientes (whatsapp_opt_in, whatsapp_no_molestar, whatsapp_ultimo_envio_at)
  where telefono is not null;

create index if not exists leads_whatsapp_campaign_eligible_idx
  on public.leads (whatsapp_opt_in, whatsapp_no_molestar, whatsapp_ultimo_envio_at)
  where telefono is not null;

create or replace function public.sync_whatsapp_ultimo_envio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.canal = 'whatsapp'
     and new.status = 'enviado'
     and coalesce(old.status, '') is distinct from 'enviado'
     and new.contact_id is not null then
    if new.contact_tipo = 'cliente' then
      update public.clientes
         set whatsapp_ultimo_envio_at = coalesce(new.sent_at, now())
       where id = new.contact_id;
    elsif new.contact_tipo = 'lead' then
      update public.leads
         set whatsapp_ultimo_envio_at = coalesce(new.sent_at, now())
       where id = new.contact_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_whatsapp_ultimo_envio on public.outbox_messages;
create trigger trg_sync_whatsapp_ultimo_envio
  after update of status on public.outbox_messages
  for each row
  execute function public.sync_whatsapp_ultimo_envio();

create or replace function public.fn_dispatch_campaign(
  p_campaign_id uuid,
  p_interval_ms integer default 1100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_msg record;
  v_outbox_id uuid;
  v_count integer := 0;
begin
  perform 1 from public.mk_campaigns where id = p_campaign_id;
  if not found then
    return jsonb_build_object('error', 'campaign_not_found');
  end if;

  for v_msg in
    select id, canal, telefono, mensaje_texto, owner_id, contacto_tipo, contacto_id
    from public.mk_messages
    where campaign_id = p_campaign_id
      and status = 'pendiente'
      and outbox_message_id is null
      and telefono is not null
      and mensaje_texto is not null
    order by orden nulls last, created_at
  loop
    insert into public.outbox_messages (
      canal, destinatario, mensaje,
      scheduled_for, status, contexto_tipo,
      owner_id, contact_tipo, contact_id,
      dispatch_provider
    )
    values (
      v_msg.canal,
      v_msg.telefono,
      v_msg.mensaje_texto,
      now() + (v_count * p_interval_ms * interval '1 millisecond'),
      'programado',
      'campaign',
      v_msg.owner_id,
      v_msg.contacto_tipo,
      v_msg.contacto_id,
      'n8n'
    )
    returning id into v_outbox_id;

    update public.mk_messages
       set outbox_message_id = v_outbox_id,
           status = 'programado'
     where id = v_msg.id;

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    update public.mk_campaigns
       set estado = 'activa',
           dispatched_at = now()
     where id = p_campaign_id;
  end if;

  return jsonb_build_object('dispatched', v_count, 'campaign_id', p_campaign_id);
end;
$$;

comment on function public.fn_dispatch_campaign(uuid, integer) is
  'Despacha mk_messages pendientes de una campaña hacia outbox_messages con dispatch_provider=n8n.';

create or replace function public.fn_claim_outbox_messages_for_n8n(
  batch_size integer default 50
)
returns setof public.outbox_messages
language sql
security definer
set search_path = public
as $$
  with candidates as (
    select om.id
    from public.outbox_messages om
    where om.dispatch_provider = 'n8n'
      and om.canal = 'whatsapp'
      and om.status in ('programado', 'retry_pending')
      and coalesce(om.retry_after, om.scheduled_for, now()) <= now()
    order by coalesce(om.retry_after, om.scheduled_for, om.created_at) asc
    for update skip locked
    limit greatest(1, least(coalesce(batch_size, 50), 200))
  ),
  claimed as (
    update public.outbox_messages om
       set status = 'en_proceso',
           locked_at = now(),
           locked_by = 'n8n',
           attempt_count = coalesce(om.attempt_count, 0) + 1
      from candidates c
     where om.id = c.id
     returning om.*
  )
  select *
  from claimed;
$$;

comment on function public.fn_claim_outbox_messages_for_n8n(integer) is
  'Reclama de forma atomica mensajes WhatsApp programados para n8n usando FOR UPDATE SKIP LOCKED.';
;
