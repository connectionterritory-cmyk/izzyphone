-- ============================================================
-- 0106: cob_ptps — Promesa de Pago como entidad formal
--
-- Objetivo:
--   Reemplazar el PTP embebido en cob_gestiones.tipo_gestion='PTP'
--   con una entidad propia que tenga ciclo de vida, estado, y
--   trazabilidad completa. cob_gestiones sigue existiendo para el
--   registro de la gestión; cob_ptps modela el compromiso financiero
--   formal derivado de esa gestión.
--
-- Alcance:
--   - CREATE TABLE cob_ptps
--   - FK a cargo_vuelta_cases (case_id, nullable)
--   - FK a clientes (cliente_id, required)
--   - FK a cob_gestiones (gestion_id, nullable)
--   - FK a usuarios (creado_por, updated_by)
--   - Estados: pendiente | cumplido | incumplido | vencido | cancelado
--   - Trigger: auto-marcar vencido en UPDATE si fecha pasó
--   - Índices para queries operativas y cron de seguimiento
--   - RLS con patrón canónico usuarios.org_id (igual que 0095/0105)
--
-- No incluye todavía:
--   - cob_pagos (pago real registrado)
--   - cob_plan_pagos / cob_plan_cuotas
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_cob_ptps_auto_vencido ON public.cob_ptps;
--   DROP FUNCTION IF EXISTS public.fn_cob_ptps_auto_vencido();
--   DROP TABLE IF EXISTS public.cob_ptps;
-- ============================================================

begin;
-- ── 1. Tabla cob_ptps ────────────────────────────────────────

create table if not exists public.cob_ptps (
  id                uuid        primary key default gen_random_uuid(),
  org_id            uuid        not null,

  -- Entidades relacionadas
  cliente_id        uuid        not null
                                references public.clientes(id) on delete cascade,
  case_id           uuid
                                references public.cargo_vuelta_cases(id) on delete set null,
  gestion_id        uuid
                                references public.cob_gestiones(id) on delete set null,
  creado_por        uuid
                                references public.usuarios(id) on delete set null,
  updated_by        uuid
                                references public.usuarios(id) on delete set null,

  -- Datos del compromiso
  monto             numeric(12,2) not null
                                check (monto > 0),
  fecha_compromiso  date        not null,
  fecha_cumplimiento date,

  -- Estado del ciclo de vida
  estado            text        not null default 'pendiente'
                                check (estado in (
                                  'pendiente',
                                  'cumplido',
                                  'incumplido',
                                  'vencido',
                                  'cancelado'
                                )),

  notas             text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- Una gestión solo puede originar un PTP activo a la vez
  constraint cob_ptps_gestion_activo_uidx
    unique (gestion_id)
    deferrable initially deferred
);
comment on table public.cob_ptps is
  'Promesas de Pago formales. Un PTP nace de una gestión de cobranza y tiene '
  'ciclo de vida propio: pendiente → cumplido | incumplido | vencido | cancelado.';
comment on column public.cob_ptps.gestion_id is
  'Gestión de cobranza que originó este PTP. UNIQUE: una gestión genera un PTP a la vez.';
comment on column public.cob_ptps.fecha_cumplimiento is
  'Fecha en que el cliente efectivamente pagó. NULL si no cumplió.';
-- ── 2. Índices operativos ────────────────────────────────────

create index if not exists cob_ptps_org_id_idx
  on public.cob_ptps (org_id);
create index if not exists cob_ptps_cliente_id_idx
  on public.cob_ptps (cliente_id);
create index if not exists cob_ptps_case_id_idx
  on public.cob_ptps (case_id)
  where case_id is not null;
create index if not exists cob_ptps_gestion_id_idx
  on public.cob_ptps (gestion_id)
  where gestion_id is not null;
-- Cron de seguimiento: PTPs pendientes con fecha pasada
create index if not exists cob_ptps_pendientes_vencimiento_idx
  on public.cob_ptps (org_id, fecha_compromiso)
  where estado = 'pendiente';
-- Dashboard: PTPs por estado en la org
create index if not exists cob_ptps_org_estado_idx
  on public.cob_ptps (org_id, estado);
-- Cobrador: mis PTPs abiertos ordenados por urgencia
create index if not exists cob_ptps_creado_por_pendientes_idx
  on public.cob_ptps (creado_por, fecha_compromiso)
  where estado = 'pendiente';
-- ── 3. Trigger: auto-vencido en UPDATE ───────────────────────
-- Cuando se actualiza un PTP y la fecha_compromiso ya pasó
-- y el estado sigue como 'pendiente', lo marca 'vencido'.
-- No cambia estados ya cerrados (cumplido/incumplido/cancelado).

create or replace function public.fn_cob_ptps_auto_vencido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'pendiente'
     and new.fecha_compromiso < current_date then
    new.estado := 'vencido';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_cob_ptps_auto_vencido on public.cob_ptps;
create trigger trg_cob_ptps_auto_vencido
  before insert or update on public.cob_ptps
  for each row
  execute function public.fn_cob_ptps_auto_vencido();
-- ── 4. RLS ───────────────────────────────────────────────────

alter table public.cob_ptps enable row level security;
-- admin / distribuidor / supervisor_tele → acceso completo
-- telemercadeo → lee todo en su org; escribe solo sus propios PTPs

create policy cob_ptps_cartera_role
  on public.cob_ptps
  for all to authenticated
  using (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  )
  with check (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (creado_por is null or creado_por = auth.uid())
      )
    )
  );
commit;
