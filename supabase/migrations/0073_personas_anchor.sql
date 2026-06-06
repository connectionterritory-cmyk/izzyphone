-- ============================================================
-- 0073_personas_anchor.sql
--
-- Objetivo:
--   Crear la tabla personas como ancla de identidad que unifica
--   leads, clientes y embajadores bajo un mismo registro de
--   persona física. Un lead puede convertirse en cliente, y un
--   cliente en embajador — los tres apuntan al mismo persona_id.
--
-- Contexto de negocio:
--   Una persona es un ROL tomado por un lead, cliente o embajador,
--   no una entidad independiente. La tabla personas es infraestructura
--   interna de deduplicación; el frontend accede a la identidad
--   siempre vía leads/clientes/embajadores, no directamente.
--
-- Decisiones de diseño:
--   • org_id: uuid sin FK (public.organizations no existe en prod).
--     FK se puede agregar en migración posterior si se crea la tabla.
--   • persona_id en leads/clientes/embajadores: nullable.
--     Registros históricos sin persona_id son válidos.
--   • ON DELETE SET NULL: si una persona es eliminada, los registros
--     que apuntaban a ella quedan con persona_id = NULL, no se pierden.
--   • RLS Opción C: solo is_admin() puede leer/escribir personas
--     directamente. El frontend siempre accede vía JOIN desde
--     leads/clientes/embajadores que ya tienen sus propias policies.
--   • Sin backfill: la migración es solo estructura. El backfill es
--     responsabilidad del operador cuando identifique registros de la
--     misma persona física en distintas tablas.
--   • Sin trigger de updated_at: consistente con el patrón de otras
--     tablas del proyecto que no usan set_updated_at trigger.
--
-- Tablas afectadas:
--   public.personas (nueva)
--   public.leads (add persona_id)
--   public.clientes (add persona_id)
--   public.embajadores (add persona_id)
--
-- ROLLBACK al final del archivo.
-- ============================================================

begin;
-- ── 1. Tabla personas ─────────────────────────────────────────

create table if not exists public.personas (
  id               uuid primary key default gen_random_uuid(),
  nombre           text,
  apellido         text,
  email            text,
  telefono         text,
  fecha_nacimiento date,
  org_id           uuid,
  -- FK a organizations omitida: public.organizations no existe en prod.
  -- Se puede agregar en migración posterior cuando se resuelva ese estado.
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on table public.personas is
  'Ancla de identidad que unifica leads, clientes y embajadores bajo un mismo registro de persona física. '
  'Tabla de infraestructura interna: el frontend accede a identidad siempre vía JOIN desde las entidades.';
comment on column public.personas.org_id is
  'Organización propietaria del registro. uuid sin FK (public.organizations no existe en prod). '
  'FK se puede agregar en migración posterior.';
-- ── 2. Índices en personas ────────────────────────────────────

create index if not exists personas_org_id_idx
  on public.personas (org_id);
create index if not exists personas_email_idx
  on public.personas (email)
  where email is not null;
create index if not exists personas_telefono_idx
  on public.personas (telefono)
  where telefono is not null;
-- ── 3. persona_id en leads ────────────────────────────────────

alter table public.leads
  add column if not exists persona_id uuid;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where  conrelid = 'public.leads'::regclass
      and  conname  = 'leads_persona_id_fkey'
  ) then
    alter table public.leads
      add constraint leads_persona_id_fkey
      foreign key (persona_id) references public.personas(id)
      on delete set null;
  end if;
end $$;
create index if not exists leads_persona_id_idx
  on public.leads (persona_id)
  where persona_id is not null;
comment on column public.leads.persona_id is
  'FK al registro de persona física en public.personas. '
  'NULL en registros históricos sin persona vinculada. '
  'Exclusivo de uso con clientes.persona_id y embajadores.persona_id para el mismo individuo.';
-- ── 4. persona_id en clientes ─────────────────────────────────

alter table public.clientes
  add column if not exists persona_id uuid;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where  conrelid = 'public.clientes'::regclass
      and  conname  = 'clientes_persona_id_fkey'
  ) then
    alter table public.clientes
      add constraint clientes_persona_id_fkey
      foreign key (persona_id) references public.personas(id)
      on delete set null;
  end if;
end $$;
create index if not exists clientes_persona_id_idx
  on public.clientes (persona_id)
  where persona_id is not null;
comment on column public.clientes.persona_id is
  'FK al registro de persona física en public.personas. '
  'NULL en registros históricos sin persona vinculada.';
-- ── 5. persona_id en embajadores ──────────────────────────────

alter table public.embajadores
  add column if not exists persona_id uuid;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where  conrelid = 'public.embajadores'::regclass
      and  conname  = 'embajadores_persona_id_fkey'
  ) then
    alter table public.embajadores
      add constraint embajadores_persona_id_fkey
      foreign key (persona_id) references public.personas(id)
      on delete set null;
  end if;
end $$;
create index if not exists embajadores_persona_id_idx
  on public.embajadores (persona_id)
  where persona_id is not null;
comment on column public.embajadores.persona_id is
  'FK al registro de persona física en public.personas. '
  'NULL en registros históricos sin persona vinculada.';
-- ── 6. RLS en personas (Opción C: solo admin) ─────────────────
--
-- personas es tabla de infraestructura interna.
-- El frontend accede a identidad siempre vía lead/cliente/embajador
-- que ya tienen sus propias RLS policies.
-- No se exponen personas directamente a vendedores ni distribuidores.

alter table public.personas enable row level security;
drop policy if exists personas_admin_all on public.personas;
create policy personas_admin_all on public.personas
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
commit;
-- ============================================================
-- AUDIT QUERIES (ejecutar DESPUÉS de aplicar)
-- ============================================================
--
-- Verificar tabla creada con RLS habilitado:
--
-- select tablename, rowsecurity
-- from pg_tables
-- where schemaname = 'public' and tablename = 'personas';
--
-- Verificar FKs en las tres tablas:
--
-- select
--   tc.table_name,
--   kcu.column_name,
--   ccu.table_name as ref_table
-- from information_schema.table_constraints tc
-- join information_schema.key_column_usage kcu
--   on tc.constraint_name = kcu.constraint_name
-- join information_schema.constraint_column_usage ccu
--   on tc.constraint_name = ccu.constraint_name
-- where tc.constraint_type = 'FOREIGN KEY'
--   and ccu.table_name = 'personas';
--
-- Verificar policy RLS:
--
-- select policyname, cmd, qual
-- from pg_policies
-- where schemaname = 'public' and tablename = 'personas';
--
-- ============================================================
-- ROLLBACK
-- ============================================================
-- begin;
--
-- -- Eliminar FKs y columnas en orden inverso
-- alter table public.embajadores
--   drop constraint if exists embajadores_persona_id_fkey,
--   drop column    if exists persona_id;
--
-- alter table public.clientes
--   drop constraint if exists clientes_persona_id_fkey,
--   drop column    if exists persona_id;
--
-- alter table public.leads
--   drop constraint if exists leads_persona_id_fkey,
--   drop column    if exists persona_id;
--
-- drop index if exists public.personas_org_id_idx;
-- drop index if exists public.personas_email_idx;
-- drop index if exists public.personas_telefono_idx;
-- drop index if exists public.leads_persona_id_idx;
-- drop index if exists public.clientes_persona_id_idx;
-- drop index if exists public.embajadores_persona_id_idx;
--
-- drop policy if exists personas_admin_all on public.personas;
-- drop table if exists public.personas;
--
-- commit;
-- ============================================================;
