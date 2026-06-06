-- 0079: Campos de remitente por campaña en outbox_messages
alter table public.outbox_messages
  add column if not exists from_email text,
  add column if not exists from_name  text,
  add column if not exists reply_to   text;
comment on column public.outbox_messages.from_email is 'Dirección FROM del remitente (ej: ventas@flowiadigital.com)';
comment on column public.outbox_messages.from_name  is 'Nombre visible del remitente (ej: Royal Prestige Ventas)';
comment on column public.outbox_messages.reply_to   is 'Reply-To real (ej: oportunidad@connectionworldwidegroup.com)';
