-- Migration 0025: MarketingFlow Sprint 1 — mk_campaigns, mk_messages, mk_responses
-- Tablas nuevas. No modifica ninguna tabla existente.
-- Reversible: ver ROLLBACK al final.
begin;
-- ── mk_campaigns ─────────────────────────────────────────────────────────────
create table if not exists public.mk_campaigns (
  id               uuid        primary key default gen_random_uuid(),
  nombre           text        not null,
  descripcion      text,
  segmento_key     text        not null,
  canal            text        not null default 'whatsapp'
                               check (canal in ('whatsapp', 'sms')),
  template_key     text,
  owner_id         uuid        not null
                               references public.usuarios(id) on delete cascade,
  estado           text        not null default 'borrador'
                               check (estado in (
                                 'borrador', 'activa', 'pausada',
                                 'completada', 'archivada'
                               )),
  total_contactos  integer     not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
drop trigger if exists mk_campaigns_updated_at on public.mk_campaigns;
create trigger mk_campaigns_updated_at
  before update on public.mk_campaigns
  for each row execute function public.set_updated_at();
-- ── mk_messages ──────────────────────────────────────────────────────────────
create table if not exists public.mk_messages (
  id              uuid        primary key default gen_random_uuid(),
  campaign_id     uuid        not null
                              references public.mk_campaigns(id) on delete cascade,
  owner_id        uuid        not null
                              references public.usuarios(id) on delete cascade,
  contacto_tipo   text        not null
                              check (contacto_tipo in (
                                'cliente', 'lead', 'ci_referido', '4en14_referido'
                              )),
  contacto_id     uuid        not null,
  telefono        text,
  nombre          text,
  mensaje_texto   text,
  canal           text        not null default 'whatsapp',
  orden           integer,
  abierto_at      timestamptz,
  created_at      timestamptz not null default now()
);
-- UNIQUE CONSTRAINT (no índice parcial) — requerido para onConflict en PostgREST.
-- NULL es seguro: NULL != NULL en SQL, múltiples contactos sin teléfono permitidos.
alter table public.mk_messages
  drop constraint if exists mk_messages_campaign_telefono_key;
alter table public.mk_messages
  add constraint mk_messages_campaign_telefono_key
  unique (campaign_id, telefono);
-- ── mk_responses ─────────────────────────────────────────────────────────────
create table if not exists public.mk_responses (
  id                uuid        primary key default gen_random_uuid(),
  message_id        uuid        not null
                                references public.mk_messages(id) on delete cascade,
  resultado         text        not null
                                check (resultado in (
                                  'sin_respuesta', 'buzon',
                                  'cita_agendada', 'cita_servicio',
                                  'pago_prometido', 'pago_realizado', 'ya_pago',
                                  'reagendar', 'solicita_info',
                                  'no_interesado', 'numero_incorrecto', 'disputa',
                                  'demo_calificada', 'venta_cerrada'
                                )),
  notas             text,
  followup_at       date,
  monto_prometido   numeric(12, 2),
  registrado_por    uuid
                    references public.usuarios(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (message_id)
);
drop trigger if exists mk_responses_updated_at on public.mk_responses;
create trigger mk_responses_updated_at
  before update on public.mk_responses
  for each row execute function public.set_updated_at();
-- ── Índices ───────────────────────────────────────────────────────────────────
create index if not exists mk_campaigns_owner_estado_idx
  on public.mk_campaigns (owner_id, estado);
create index if not exists mk_messages_campaign_orden_idx
  on public.mk_messages (campaign_id, orden asc nulls last);
create index if not exists mk_messages_campaign_abierto_idx
  on public.mk_messages (campaign_id, abierto_at);
create index if not exists mk_messages_contacto_idx
  on public.mk_messages (contacto_tipo, contacto_id);
create index if not exists mk_responses_resultado_idx
  on public.mk_responses (resultado);
create index if not exists mk_responses_followup_idx
  on public.mk_responses (followup_at)
  where followup_at is not null;
-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table public.mk_campaigns  enable row level security;
alter table public.mk_messages   enable row level security;
alter table public.mk_responses  enable row level security;
-- mk_campaigns
drop policy if exists mk_campaigns_admin_all          on public.mk_campaigns;
drop policy if exists mk_campaigns_owner_all          on public.mk_campaigns;
drop policy if exists mk_campaigns_distribuidor_read  on public.mk_campaigns;
create policy mk_campaigns_admin_all on public.mk_campaigns
  for all to authenticated using (is_admin());
create policy mk_campaigns_owner_all on public.mk_campaigns
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
create policy mk_campaigns_distribuidor_read on public.mk_campaigns
  for select to authenticated
  using (is_distribuidor() and is_distribuidor_of(owner_id));
-- mk_messages
drop policy if exists mk_messages_admin_all           on public.mk_messages;
drop policy if exists mk_messages_owner_all           on public.mk_messages;
drop policy if exists mk_messages_distribuidor_read   on public.mk_messages;
create policy mk_messages_admin_all on public.mk_messages
  for all to authenticated using (is_admin());
create policy mk_messages_owner_all on public.mk_messages
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
create policy mk_messages_distribuidor_read on public.mk_messages
  for select to authenticated
  using (is_distribuidor() and is_distribuidor_of(owner_id));
-- mk_responses
drop policy if exists mk_responses_admin_all                on public.mk_responses;
drop policy if exists mk_responses_registrado_por           on public.mk_responses;
drop policy if exists mk_responses_message_owner_read       on public.mk_responses;
drop policy if exists mk_responses_message_owner_insert     on public.mk_responses;
drop policy if exists mk_responses_distribuidor_read        on public.mk_responses;
create policy mk_responses_admin_all on public.mk_responses
  for all to authenticated using (is_admin());
create policy mk_responses_registrado_por on public.mk_responses
  for all to authenticated
  using (registrado_por = auth.uid())
  with check (registrado_por = auth.uid());
create policy mk_responses_message_owner_read on public.mk_responses
  for select to authenticated
  using (
    exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id and m.owner_id = auth.uid()
    )
  );
create policy mk_responses_message_owner_insert on public.mk_responses
  for insert to authenticated
  with check (
    exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id and m.owner_id = auth.uid()
    )
  );
create policy mk_responses_distribuidor_read on public.mk_responses
  for select to authenticated
  using (
    is_distribuidor() and exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id and is_distribuidor_of(m.owner_id)
    )
  );
-- ── Vista KPI (security_invoker = RLS aplicado al caller) ────────────────────
create or replace view public.v_mk_campaign_stats
  with (security_invoker = true)
as
select
  c.id                                                              as campaign_id,
  c.nombre, c.segmento_key, c.canal, c.estado, c.total_contactos, c.owner_id,
  count(m.id)                                                       as total_mensajes,
  count(m.id) filter (where m.abierto_at is not null)              as total_abiertos,
  count(r.id)                                                       as total_respondidos,
  count(m.id) filter (where r.id is null)                          as total_pendientes,
  count(r.id) filter (where r.resultado = 'cita_agendada')         as citas,
  count(r.id) filter (where r.resultado = 'pago_prometido')        as pagos_prometidos,
  count(r.id) filter (where r.resultado = 'no_interesado')         as no_interesados,
  count(r.id) filter (where r.resultado = 'sin_respuesta')         as sin_respuesta,
  coalesce(sum(r.monto_prometido), 0)                              as monto_comprometido,
  case when count(m.id) > 0
    then round(count(r.id)::numeric / count(m.id) * 100, 1) else 0
  end                                                               as tasa_respuesta_pct,
  case when count(m.id) > 0
    then round(count(r.id) filter (where r.resultado = 'cita_agendada')::numeric / count(m.id) * 100, 1) else 0
  end                                                               as tasa_citas_pct
from public.mk_campaigns c
left join public.mk_messages  m on m.campaign_id = c.id
left join public.mk_responses r on r.message_id  = m.id
group by c.id;
commit;
-- ROLLBACK:
-- begin;
-- drop view  if exists public.v_mk_campaign_stats;
-- drop table if exists public.mk_responses cascade;
-- drop table if exists public.mk_messages  cascade;
-- drop table if exists public.mk_campaigns cascade;
-- commit;;
