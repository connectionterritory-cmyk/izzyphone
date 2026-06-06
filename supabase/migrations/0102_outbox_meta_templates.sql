-- 0102: outbox_messages Meta template support and provider tracing

alter table public.outbox_messages
  add column if not exists tipo_envio text not null default 'text',
  add column if not exists template_name text,
  add column if not exists template_params jsonb not null default '[]'::jsonb,
  add column if not exists provider text;
alter table public.outbox_messages
  drop constraint if exists outbox_messages_tipo_envio_check;
alter table public.outbox_messages
  add constraint outbox_messages_tipo_envio_check
  check (tipo_envio in ('text', 'template'));
comment on column public.outbox_messages.tipo_envio is
  'Tipo de envio para proveedor de mensajeria: text o template (Meta WhatsApp Cloud API).';
comment on column public.outbox_messages.template_name is
  'Nombre del template aprobado en Meta, usado cuando tipo_envio=template.';
comment on column public.outbox_messages.template_params is
  'Parametros del template en orden (array JSON) para componentes body de WhatsApp.';
comment on column public.outbox_messages.provider is
  'Proveedor usado para envio (meta, resend, telegram, etc.).';
