-- Migration 0002: MVP Tables (Servicio, Agua, Cartera, Team Hub)
-- Idempotent: safe to re-run

begin;
-- ============================================================================
-- C) SERVICIO / POSTVENTA (multi-producto)
-- ============================================================================

create table if not exists public.cliente_productos (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  cliente_id uuid not null,
  producto_tipo text not null, -- 'FrescaFlow', 'FrescaPure 3000', 'FrescaPure 5500', 'Ducha', etc.
  numero_serie text,
  fecha_instalacion date,
  notas text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists cliente_productos_org_id_idx on public.cliente_productos (org_id);
create index if not exists cliente_productos_cliente_id_idx on public.cliente_productos (cliente_id);
create table if not exists public.servicios (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  cliente_id uuid not null,
  ticket_number text unique,
  titulo text not null,
  descripcion text,
  estado text not null default 'Abierto', -- 'Abierto', 'En Proceso', 'Resuelto', 'Cerrado'
  prioridad text not null default 'Media', -- 'Baja', 'Media', 'Alta', 'Urgente'
  asignado_a uuid, -- references auth.users(id)
  fecha_apertura timestamptz not null default now(),
  fecha_cierre timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists servicios_org_id_idx on public.servicios (org_id);
create index if not exists servicios_cliente_id_idx on public.servicios (cliente_id);
create index if not exists servicios_estado_idx on public.servicios (estado);
create table if not exists public.servicio_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  servicio_id uuid not null references public.servicios(id) on delete cascade,
  cliente_producto_id uuid references public.cliente_productos(id),
  descripcion text not null,
  componente text, -- e.g., 'Carbón', 'Prefiltro', 'RO', etc.
  accion text, -- 'Cambio', 'Reparación', 'Inspección', etc.
  completado boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists servicio_items_org_id_idx on public.servicio_items (org_id);
create index if not exists servicio_items_servicio_id_idx on public.servicio_items (servicio_id);
-- ============================================================================
-- D) AGUA SCHEDULER (componentes + reglas)
-- ============================================================================

-- agua_reglas already created via seed 0001_water_rules.sql
-- We need the supporting tables

create table if not exists public.agua_sistemas (
  id uuid primary key default gen_random_uuid(),
  nombre text unique not null, -- 'FrescaFlow', 'FrescaPure 3000', etc.
  descripcion text,
  created_at timestamptz not null default now()
);
insert into public.agua_sistemas (nombre, descripcion)
values
  ('FrescaFlow', 'Sistema de filtración completo con RO y mineralización'),
  ('FrescaPure 3000', 'Sistema básico con filtro de carbón'),
  ('FrescaPure 5500', 'Sistema intermedio con carbón y prefiltro opcional'),
  ('Ducha', 'Sistema de filtración para ducha')
on conflict (nombre) do nothing;
create table if not exists public.agua_componentes (
  id uuid primary key default gen_random_uuid(),
  nombre text unique not null, -- 'Prefiltro', 'Carbon', 'Mineralizador', 'RO'
  descripcion text,
  created_at timestamptz not null default now()
);
insert into public.agua_componentes (nombre, descripcion)
values
  ('Prefiltro', 'Filtro preliminar de sedimentos'),
  ('Carbon', 'Filtro de carbón activado'),
  ('Mineralizador', 'Filtro mineralizador'),
  ('RO', 'Membrana de ósmosis inversa')
on conflict (nombre) do nothing;
create table if not exists public.agua_reglas (
  id uuid primary key default gen_random_uuid(),
  sistema text not null,
  componente text not null,
  intervalo_meses integer not null,
  aplica_si text, -- null or 'si_aplica' for conditional components
  created_at timestamptz not null default now(),
  unique (sistema, componente, intervalo_meses, aplica_si)
);
create index if not exists agua_reglas_sistema_idx on public.agua_reglas (sistema);
create table if not exists public.cliente_sistemas (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  cliente_id uuid not null,
  sistema text not null, -- references agua_sistemas(nombre)
  fecha_instalacion date not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists cliente_sistemas_org_id_idx on public.cliente_sistemas (org_id);
create index if not exists cliente_sistemas_cliente_id_idx on public.cliente_sistemas (cliente_id);
create table if not exists public.cliente_componentes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  cliente_sistema_id uuid not null references public.cliente_sistemas(id) on delete cascade,
  componente text not null,
  last_change_at date not null,
  next_change_at date not null, -- calculated based on agua_reglas
  intervalo_meses integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists cliente_componentes_org_id_idx on public.cliente_componentes (org_id);
create index if not exists cliente_componentes_next_change_idx on public.cliente_componentes (next_change_at);
-- ============================================================================
-- E) CARTERA (Aging + Cargo de vuelta)
-- ============================================================================

create table if not exists public.cob_gestiones (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  cliente_id uuid not null,
  factura_id uuid, -- optional reference to specific invoice/transaction
  tipo_gestion text not null, -- 'Llamada', 'Email', 'WhatsApp', 'Visita', 'PTP'
  resultado text, -- 'Contactado', 'No Contactado', 'Promesa de Pago', 'Disputa', etc.
  monto_comprometido numeric(12,2),
  fecha_compromiso date, -- for PTP (Promise to Pay)
  notas text,
  gestionado_por uuid, -- references auth.users(id)
  created_at timestamptz not null default now()
);
create index if not exists cob_gestiones_org_id_idx on public.cob_gestiones (org_id);
create index if not exists cob_gestiones_cliente_id_idx on public.cob_gestiones (cliente_id);
create index if not exists cob_gestiones_created_at_idx on public.cob_gestiones (created_at);
create table if not exists public.cargo_vuelta_cases (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  cliente_id uuid not null,
  factura_id uuid, -- optional reference
  monto_total numeric(12,2) not null,
  dias_vencido integer not null,
  estado text not null default 'Abierto', -- 'Abierto', 'En Negociación', 'Acuerdo', 'Cerrado'
  acuerdo_tipo text, -- 'PTP', 'Plan de Pagos', 'Descuento', etc.
  acuerdo_detalles jsonb,
  fecha_apertura timestamptz not null default now(),
  fecha_cierre timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists cargo_vuelta_cases_org_id_idx on public.cargo_vuelta_cases (org_id);
create index if not exists cargo_vuelta_cases_cliente_id_idx on public.cargo_vuelta_cases (cliente_id);
create index if not exists cargo_vuelta_cases_estado_idx on public.cargo_vuelta_cases (estado);
-- ============================================================================
-- F) TEAM HUB (canales + anuncios)
-- ============================================================================

create table if not exists public.canales (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  nombre text not null,
  descripcion text,
  tipo text not null default 'general', -- 'general', 'departamento', 'proyecto', etc.
  is_private boolean not null default false,
  created_by uuid, -- references auth.users(id)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists canales_org_id_idx on public.canales (org_id);
create table if not exists public.anuncios (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  canal_id uuid references public.canales(id) on delete cascade,
  titulo text not null,
  contenido text not null,
  autor_id uuid, -- references auth.users(id)
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists anuncios_org_id_idx on public.anuncios (org_id);
create index if not exists anuncios_canal_id_idx on public.anuncios (canal_id);
create index if not exists anuncios_created_at_idx on public.anuncios (created_at desc);
-- ============================================================================
-- RLS POLICIES
-- ============================================================================

alter table public.cliente_productos enable row level security;
alter table public.servicios enable row level security;
alter table public.servicio_items enable row level security;
alter table public.agua_sistemas enable row level security;
alter table public.agua_componentes enable row level security;
alter table public.agua_reglas enable row level security;
alter table public.cliente_sistemas enable row level security;
alter table public.cliente_componentes enable row level security;
alter table public.cob_gestiones enable row level security;
alter table public.cargo_vuelta_cases enable row level security;
alter table public.canales enable row level security;
alter table public.anuncios enable row level security;
-- Servicio policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cliente_productos' and policyname = 'cliente_productos_org_member'
  ) then
    create policy cliente_productos_org_member on public.cliente_productos
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'servicios' and policyname = 'servicios_org_member'
  ) then
    create policy servicios_org_member on public.servicios
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'servicio_items' and policyname = 'servicio_items_org_member'
  ) then
    create policy servicio_items_org_member on public.servicio_items
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  -- Agua policies (sistemas and componentes are reference data, readable by all authenticated users)
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'agua_sistemas' and policyname = 'agua_sistemas_read'
  ) then
    create policy agua_sistemas_read on public.agua_sistemas
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'agua_componentes' and policyname = 'agua_componentes_read'
  ) then
    create policy agua_componentes_read on public.agua_componentes
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'agua_reglas' and policyname = 'agua_reglas_read'
  ) then
    create policy agua_reglas_read on public.agua_reglas
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cliente_sistemas' and policyname = 'cliente_sistemas_org_member'
  ) then
    create policy cliente_sistemas_org_member on public.cliente_sistemas
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cliente_componentes' and policyname = 'cliente_componentes_org_member'
  ) then
    create policy cliente_componentes_org_member on public.cliente_componentes
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  -- Cartera policies
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cob_gestiones' and policyname = 'cob_gestiones_org_member'
  ) then
    create policy cob_gestiones_org_member on public.cob_gestiones
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cargo_vuelta_cases' and policyname = 'cargo_vuelta_cases_org_member'
  ) then
    create policy cargo_vuelta_cases_org_member on public.cargo_vuelta_cases
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  -- Team Hub policies
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'canales' and policyname = 'canales_org_member'
  ) then
    create policy canales_org_member on public.canales
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'anuncios' and policyname = 'anuncios_org_member'
  ) then
    create policy anuncios_org_member on public.anuncios
      for all
      using (public.is_org_member(org_id))
      with check (public.is_org_member(org_id));
  end if;
end $$;
commit;
