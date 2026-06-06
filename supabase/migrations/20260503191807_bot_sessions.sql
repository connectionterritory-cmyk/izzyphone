-- ============================================================
-- 0080_bot_sessions.sql
-- Tabla de sesiones de conversación para el bot de citas
-- Canal: Telegram (extensible a WhatsApp/webchat)
-- ============================================================

begin;
create table if not exists public.bot_sessions (
  id            uuid        primary key default gen_random_uuid(),

  -- Identificador del chat externo (Telegram chat_id, WA phone, etc.)
  chat_id       text        not null,
  canal         text        not null default 'telegram'
                            check (canal in ('telegram','whatsapp','webchat')),

  -- Estado conversacional
  intent        text        check (intent in ('citas','servicio_cliente','cartera','cumpleanos','otro')),
  step          text        not null default 'inicio',
                            -- inicio | ask_nombre | ask_telefono | ask_motivo | ask_fecha | ask_hora | confirmar | done

  -- Slots recolectados
  slots         jsonb       not null default '{}'::jsonb,
  -- Ejemplo: {"nombre":"Ana","telefono":"7861234567","motivo":"servicio","fecha":"2026-04-10","hora":"10:00"}

  -- Resultado final
  cita_id       uuid        references public.citas(id) on delete set null,
  lead_id       uuid        references public.leads(id) on delete set null,

  -- Control
  intentos      integer     not null default 0,
  activa        boolean     not null default true,
  expires_at    timestamptz not null default (now() + interval '2 hours'),

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
-- Un chat activo por canal (upsert por chat_id+canal)
create unique index if not exists bot_sessions_active_chat_idx
  on public.bot_sessions (chat_id, canal)
  where activa = true;
create index if not exists bot_sessions_expires_idx
  on public.bot_sessions (expires_at)
  where activa = true;
drop trigger if exists bot_sessions_set_updated_at on public.bot_sessions;
create trigger bot_sessions_set_updated_at
  before update on public.bot_sessions
  for each row execute function public.set_updated_at();
-- RLS: solo service_role accede (el bot corre con service key)
alter table public.bot_sessions enable row level security;
drop policy if exists bot_sessions_service_all on public.bot_sessions;
create policy bot_sessions_service_all on public.bot_sessions
  for all
  using (true)
  with check (true);
-- Limpiar sesiones expiradas automáticamente (llamar con cron/n8n)
create or replace function public.cleanup_bot_sessions()
returns integer
language plpgsql
security definer
as $$
declare v_count integer;
begin
  update public.bot_sessions
  set activa = false
  where activa = true and expires_at < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
commit;
