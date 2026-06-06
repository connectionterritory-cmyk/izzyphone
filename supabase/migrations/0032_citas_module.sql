-- ============================================================
-- 0032_citas_module.sql
-- MVP: tabla de citas (appointments) con RLS completo
-- ============================================================

begin;
-- ── Helper: is_admin_or_distribuidor() ──────────────────────
-- Reutilizable por otras tablas; idempotente.
create or replace function public.is_admin_or_distribuidor()
returns boolean
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid()
      and rol in ('admin', 'distribuidor')
  );
$$;
-- ── Tabla: citas ─────────────────────────────────────────────
create table if not exists public.citas (
  id              uuid        primary key default gen_random_uuid(),

  -- Propietario y asignado
  owner_id        uuid        not null references public.usuarios(id) on delete restrict,
  assigned_to     uuid        references public.usuarios(id) on delete set null,

  -- Contacto (cliente o lead)
  contacto_tipo   text        not null check (contacto_tipo in ('cliente', 'lead')),
  contacto_id     uuid        not null,

  -- Datos de contacto denormalizados (para offline / historial)
  telefono        text,
  nombre          text,
  direccion       text,
  ciudad          text,
  estado_region   text,
  zip             text,

  -- Tiempo
  start_at        timestamptz not null,
  end_at          timestamptz not null default now() + interval '60 minutes',

  -- Clasificación y estado
  tipo            text        not null default 'servicio'
                              check (tipo in ('servicio', 'demo', 'cobranza', 'reclutamiento', 'otro')),
  estado          text        not null default 'programada'
                              check (estado in ('programada', 'confirmada', 'en_camino', 'completada', 'cancelada', 'no_show')),

  notas           text,

  -- Vínculos opcionales a MarketingFlow
  campaign_id     uuid        references public.mk_campaigns(id)  on delete set null,
  message_id      uuid        references public.mk_messages(id)   on delete set null,
  response_id     uuid        references public.mk_responses(id)  on delete set null,

  -- Auditoría
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- Garantizar que end_at > start_at
  constraint citas_time_order check (end_at > start_at)
);
-- ── Índices ──────────────────────────────────────────────────
create index if not exists citas_assigned_to_start_idx
  on public.citas (assigned_to, start_at);
create index if not exists citas_contacto_idx
  on public.citas (contacto_tipo, contacto_id);
create index if not exists citas_campaign_idx
  on public.citas (campaign_id)
  where campaign_id is not null;
create index if not exists citas_owner_idx
  on public.citas (owner_id);
-- ── Trigger updated_at ───────────────────────────────────────
-- set_updated_at() ya existe (migration 0001 / schema.sql)
create trigger citas_set_updated_at
  before update on public.citas
  for each row execute function public.set_updated_at();
-- ── RLS ──────────────────────────────────────────────────────
alter table public.citas enable row level security;
-- SELECT: propio o asignado o admin/distribuidor
create policy citas_select on public.citas
  for select to authenticated
  using (
    owner_id    = auth.uid()
    or assigned_to = auth.uid()
    or public.is_admin_or_distribuidor()
  );
-- INSERT: solo el propio usuario como owner
create policy citas_insert on public.citas
  for insert to authenticated
  with check (owner_id = auth.uid());
-- UPDATE: owner, asignado, o admin/distribuidor
create policy citas_update on public.citas
  for update to authenticated
  using (
    owner_id    = auth.uid()
    or assigned_to = auth.uid()
    or public.is_admin_or_distribuidor()
  )
  with check (
    owner_id    = auth.uid()
    or assigned_to = auth.uid()
    or public.is_admin_or_distribuidor()
  );
-- DELETE: solo admin o distribuidor
create policy citas_delete on public.citas
  for delete to authenticated
  using (public.is_admin_or_distribuidor());
commit;
