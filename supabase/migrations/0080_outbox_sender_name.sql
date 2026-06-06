-- 0080: sender_name en outbox_messages para firma real del vendedor en email
alter table public.outbox_messages
  add column if not exists sender_name text;
comment on column public.outbox_messages.sender_name is
  'Nombre real del vendedor que envía (para firma en email)';
