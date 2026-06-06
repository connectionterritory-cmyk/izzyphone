-- 0078: provider_message_id en outbox_messages para tracking de Resend
alter table public.outbox_messages
  add column if not exists provider_message_id text;
comment on column public.outbox_messages.provider_message_id is
  'ID devuelto por el proveedor (Resend email ID, etc.) para tracking de entrega/bounce';
