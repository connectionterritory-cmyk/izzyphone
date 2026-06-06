begin;

alter table public.outbox_messages
  add column if not exists cc_emails text[] default null;

comment on column public.outbox_messages.cc_emails is
  'Destinatarios en copia (CC) del email. Solo aplica cuando canal = email.';

commit;;
