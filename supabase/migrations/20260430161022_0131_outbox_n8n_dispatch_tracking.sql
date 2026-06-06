-- ============================================================
-- 0131_outbox_n8n_dispatch_tracking.sql
-- Tracking para dispatcher n8n de outbox_messages
--
-- Fase 1:
--   Solo procesa filas marcadas explicitamente con dispatch_provider = 'n8n'.
--   process-outbox conserva el flujo directo existente.
-- ============================================================

begin;

alter table public.outbox_messages
  add column if not exists dispatch_provider text,
  add column if not exists n8n_execution_id text,
  add column if not exists dispatched_to_n8n_at timestamptz,
  add column if not exists provider_message_id text,
  add column if not exists provider_response jsonb,
  add column if not exists attempt_count integer not null default 0;

comment on column public.outbox_messages.dispatch_provider is
  'Dispatcher/proveedor responsable del envio. Fase 1 n8n solo procesa filas con valor n8n.';

comment on column public.outbox_messages.n8n_execution_id is
  'Execution id devuelto por n8n para trazabilidad del workflow.';

comment on column public.outbox_messages.dispatched_to_n8n_at is
  'Timestamp cuando el mensaje fue entregado al webhook de n8n.';

comment on column public.outbox_messages.provider_response is
  'Respuesta cruda del dispatcher/proveedor final.';

comment on column public.outbox_messages.attempt_count is
  'Cantidad acumulada de intentos de despacho.';

create table if not exists public.outbox_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  outbox_message_id uuid not null references public.outbox_messages(id) on delete cascade,
  org_id text,
  attempt_number integer not null,
  dispatcher text not null,
  status text not null check (status in ('started', 'accepted', 'sent', 'retry_pending', 'failed')),
  request_payload jsonb,
  response_payload jsonb,
  error_message text,
  created_at timestamptz not null default now()
);

comment on table public.outbox_delivery_attempts is
  'Auditoria por intento de despacho de outbox_messages hacia workers/proveedores externos como n8n.';

comment on column public.outbox_delivery_attempts.outbox_message_id is
  'Mensaje de outbox asociado al intento.';

comment on column public.outbox_delivery_attempts.org_id is
  'Organizacion del mensaje. Text por compatibilidad con outbox_messages.org_id actual.';

comment on column public.outbox_delivery_attempts.attempt_number is
  'Numero de intento tomado desde outbox_messages.attempt_count.';

comment on column public.outbox_delivery_attempts.dispatcher is
  'Worker/dispatcher que intento procesar el mensaje.';

comment on column public.outbox_delivery_attempts.status is
  'Estado del intento individual: started, accepted, sent, retry_pending o failed.';

comment on column public.outbox_delivery_attempts.request_payload is
  'Payload enviado al dispatcher externo.';

comment on column public.outbox_delivery_attempts.response_payload is
  'Respuesta cruda recibida del dispatcher externo.';

comment on column public.outbox_delivery_attempts.error_message is
  'Mensaje de error asociado al intento, si aplica.';

create index if not exists outbox_delivery_attempts_message_idx
  on public.outbox_delivery_attempts (outbox_message_id, attempt_number desc);

create index if not exists outbox_delivery_attempts_org_created_idx
  on public.outbox_delivery_attempts (org_id, created_at desc);

create index if not exists outbox_messages_n8n_dispatch_idx
  on public.outbox_messages (scheduled_for)
  where status in ('programado', 'retry_pending')
    and dispatch_provider = 'n8n';

alter table public.outbox_delivery_attempts enable row level security;

drop policy if exists outbox_delivery_attempts_owner_read on public.outbox_delivery_attempts;
create policy outbox_delivery_attempts_owner_read
  on public.outbox_delivery_attempts
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.outbox_messages om
      where om.id = outbox_delivery_attempts.outbox_message_id
        and om.owner_id = auth.uid()
    )
  );
;
