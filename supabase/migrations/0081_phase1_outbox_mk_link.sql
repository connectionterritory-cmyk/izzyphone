-- 0081: Phase 1 - link mk_messages to outbox and expand outbox lifecycle

-- 1) Link mk_messages -> outbox_messages
alter table public.mk_messages
  add column if not exists outbox_message_id uuid references public.outbox_messages(id) on delete set null;
create index if not exists mk_messages_outbox_message_id_idx
  on public.mk_messages (outbox_message_id);
-- 2) Add business context to outbox
alter table public.outbox_messages
  add column if not exists contexto_tipo text default 'ad_hoc';
alter table public.outbox_messages
  drop constraint if exists outbox_messages_contexto_tipo_check;
alter table public.outbox_messages
  add constraint outbox_messages_contexto_tipo_check
  check (contexto_tipo in ('campaign', 'cobranza', 'servicio', 'cumpleanos', 'seguimiento', 'ad_hoc'));
-- 3) Expand status lifecycle for worker locking and retries
-- Normalize any legacy status values before tightening the check constraint.
update public.outbox_messages
  set status = 'enviado'
  where status = 'sent';
update public.outbox_messages
  set status = 'programado'
  where status = 'procesando';
alter table public.outbox_messages
  drop constraint if exists outbox_messages_status_check;
alter table public.outbox_messages
  add constraint outbox_messages_status_check
  check (status in ('borrador', 'programado', 'en_proceso', 'enviado', 'fallido', 'retry_pending', 'cancelado'));
-- 4) Update scheduled index to include retry_pending
create index if not exists outbox_messages_scheduled_idx_v2
  on public.outbox_messages (scheduled_for)
  where status in ('programado', 'retry_pending');
-- (Optional cleanup) keep old index if it exists; safe to leave during rollout;
