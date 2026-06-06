begin;
-- 0159_dfp_daily_cuota_notifications
-- Tracking minimo para recordatorios diarios DFP.
-- No toca cob_financial_ledger, no registra pagos y no procesa tarjetas.

alter table public.cob_metodos_pago
  add column if not exists display text;
comment on column public.cob_metodos_pago.display is
  'Texto seguro de presentacion del metodo de pago. No debe contener PAN completo ni CVV.';
alter table public.outbox_messages
  add column if not exists dfp_notification_key text,
  add column if not exists dfp_notification_date date;
comment on column public.outbox_messages.dfp_notification_key is
  'Llave logica idempotente para recordatorios DFP, ej. dfp_cuota_reminder:{cuota_id}:{fecha}:{canal}.';
comment on column public.outbox_messages.dfp_notification_date is
  'Fecha America/New_York en la que se genero el recordatorio DFP.';
create unique index if not exists uq_outbox_messages_dfp_notification_key
  on public.outbox_messages (dfp_notification_key)
  where dfp_notification_key is not null;
create index if not exists idx_outbox_messages_dfp_notification_date
  on public.outbox_messages (dfp_notification_date)
  where dfp_notification_date is not null;
create table if not exists public.dfp_notification_events (
  notification_key text primary key,
  org_id uuid,
  cuota_id uuid references public.cob_plan_cuotas(id) on delete cascade,
  notification_date date not null,
  target_date date,
  channel text not null check (channel in ('email', 'telegram', 'whatsapp', 'sms')),
  scope text not null check (scope in ('internal_summary', 'client_reminder')),
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'queued', 'skipped')),
  payload jsonb not null default '{}'::jsonb,
  error_message text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.dfp_notification_events is
  'Eventos idempotentes de notificacion DFP diaria. No contiene PAN, CVV ni pagos reales.';
create index if not exists idx_dfp_notification_events_date_channel
  on public.dfp_notification_events (notification_date, channel, scope);
create index if not exists idx_dfp_notification_events_cuota
  on public.dfp_notification_events (cuota_id)
  where cuota_id is not null;
drop trigger if exists trg_dfp_notification_events_updated_at on public.dfp_notification_events;
create trigger trg_dfp_notification_events_updated_at
  before update on public.dfp_notification_events
  for each row execute function public.fn_set_updated_at();
alter table public.dfp_notification_events enable row level security;
drop policy if exists dfp_notification_events_read_cartera on public.dfp_notification_events;
create policy dfp_notification_events_read_cartera
  on public.dfp_notification_events
  for select to authenticated
  using (
    org_id is null
    or org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
  );
commit;
