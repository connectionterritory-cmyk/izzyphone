-- ============================================================
-- 0069_leads_referidor_polymorphic.sql
--
-- Objetivo:
--   Agregar referidor_tipo + referidor_id a leads como modelo
--   polimórfico canónico para el referidor. Reemplaza a largo
--   plazo los campos tipados embajador_id y referido_por_cliente_id.
--
-- Fase: ADITIVA — no elimina columnas, no rompe escrituras actuales.
--
-- Contiene:
--   1.  ADD COLUMN referidor_tipo, referidor_id
--   2a. CHECK CONSTRAINT — valores permitidos para referidor_tipo
--   2b. CHECK CONSTRAINT — nullidad consistente (ambos NULL o ambos NOT NULL)
--   3.  Backfill desde embajador_id y referido_por_cliente_id
--   4.  Índice por (referidor_tipo, referidor_id)
--   5.  Trigger BIDIRECCIONAL en INSERT
--       - si new code escribió referidor_id → sincroniza → legacy
--       - si legacy code escribió embajador_id/referido_por_cliente_id → sincroniza → nuevo
--   6.  Trigger BIDIRECCIONAL en UPDATE
--       - detecta qué lado cambió; si ambos cambiaron → nuevo gana
--       - al sincronizar legacy→nuevo, limpia el otro campo legacy
--         para evitar dualidad futura
--
-- AUDIT QUERY al final del archivo (antes del rollback).
-- ROLLBACK al final del archivo.
-- ============================================================

begin;
-- ── 1. Nuevas columnas ────────────────────────────────────────

alter table public.leads
  add column if not exists referidor_tipo text,
  add column if not exists referidor_id   uuid;
-- ── 2a. Check constraint — valores permitidos ─────────────────
-- DO block para idempotencia (ADD CONSTRAINT falla si ya existe).

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where  conrelid = 'public.leads'::regclass
      and  conname  = 'leads_referidor_tipo_values'
  ) then
    alter table public.leads
      add constraint leads_referidor_tipo_values
      check (
        referidor_tipo is null
        or referidor_tipo in ('cliente', 'lead', 'embajador')
      );
  end if;
end $$;
-- ── 2b. Check constraint — nullidad consistente ───────────────
-- referidor_tipo y referidor_id deben ser ambos NULL o ambos NOT NULL.
-- Expresión: (a IS NULL) = (b IS NULL) equivale a "ambos iguales en nulidad".

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where  conrelid = 'public.leads'::regclass
      and  conname  = 'leads_referidor_nullity'
  ) then
    alter table public.leads
      add constraint leads_referidor_nullity
      check (
        (referidor_tipo is null) = (referidor_id is null)
      );
  end if;
end $$;
-- ── 3. Backfill de datos existentes ──────────────────────────
--
-- Prioridad documentada: embajador_id > referido_por_cliente_id.
-- El campo legacy de menor prioridad NO se limpia aquí — los datos
-- históricos se conservan tal cual. El trigger lo limpiará en
-- escrituras futuras.
--
-- Para ver filas con ambos campos poblados (anomalías):
-- → ver AUDIT QUERY al final del archivo.

update public.leads
set
  referidor_tipo = case
    when embajador_id            is not null then 'embajador'
    when referido_por_cliente_id is not null then 'cliente'
  end,
  referidor_id = coalesce(embajador_id, referido_por_cliente_id)
where
  (embajador_id is not null or referido_por_cliente_id is not null)
  and referidor_id is null;
-- idempotente: no sobreescribe si ya fue migrado

-- ── 4. Índice ─────────────────────────────────────────────────

create index if not exists idx_leads_referidor
  on public.leads (referidor_tipo, referidor_id)
  where referidor_id is not null;
-- ── 5. Función para trigger INSERT — bidireccional ────────────
--
-- Lógica de prioridad:
--   Si referidor_id IS NOT NULL al llegar al trigger
--     → código nuevo escribió el lado canónico
--     → sincronizar canónico → legacy
--   Si referidor_id IS NULL
--     → código legacy escribió embajador_id / referido_por_cliente_id
--     → sincronizar legacy → canónico
--     → limpiar el otro campo legacy para evitar dualidad
--
-- Mapa nuevo → legacy:
--   'embajador' → embajador_id = referidor_id, referido_por_cliente_id = NULL
--   'cliente'   → referido_por_cliente_id = referidor_id, embajador_id = NULL
--   'lead'      → sin equivalente legacy; ambos campos legacy = NULL
--
-- Mapa legacy → nuevo:
--   embajador_id NOT NULL  → tipo = 'embajador', id = embajador_id
--                            limpiar referido_por_cliente_id
--   referido_por_cliente_id NOT NULL → tipo = 'cliente', id = referido_por_cliente_id
--                                      limpiar embajador_id

create or replace function public.fn_leads_sync_referidor_insert()
returns trigger
language plpgsql
as $$
begin
  if NEW.referidor_id is not null then
    -- ── Código nuevo → sincronizar hacia legacy ──────────────
    if NEW.referidor_tipo = 'embajador' then
      NEW.embajador_id            := NEW.referidor_id;
      NEW.referido_por_cliente_id := null;
    elsif NEW.referidor_tipo = 'cliente' then
      NEW.referido_por_cliente_id := NEW.referidor_id;
      NEW.embajador_id            := null;
    elsif NEW.referidor_tipo = 'lead' then
      -- Sin campo legacy para leads: limpiar ambos para consistencia
      NEW.embajador_id            := null;
      NEW.referido_por_cliente_id := null;
    end if;

  else
    -- ── Código legacy → sincronizar hacia canónico ───────────
    if NEW.embajador_id is not null then
      NEW.referidor_tipo          := 'embajador';
      NEW.referidor_id            := NEW.embajador_id;
      NEW.referido_por_cliente_id := null;   -- prevenir dualidad
    elsif NEW.referido_por_cliente_id is not null then
      NEW.referidor_tipo          := 'cliente';
      NEW.referidor_id            := NEW.referido_por_cliente_id;
      NEW.embajador_id            := null;   -- prevenir dualidad
    end if;
    -- Si ambos legacy son null: dejar canónico null (ya lo es)
  end if;

  return NEW;
end;
$$;
-- Recrear trigger INSERT (drop+create para que CREATE OR REPLACE de la
-- función siempre quede ligado a la versión más reciente del trigger).
drop trigger if exists trg_leads_sync_referidor_insert on public.leads;
create trigger trg_leads_sync_referidor_insert
  before insert on public.leads
  for each row
  execute function public.fn_leads_sync_referidor_insert();
-- ── 6. Función para trigger UPDATE — bidireccional ────────────
--
-- Detección de qué lado cambió:
--   new_side_changed    = referidor_tipo o referidor_id cambió
--   legacy_side_changed = embajador_id o referido_por_cliente_id cambió
--
-- Reglas de resolución:
--   Ninguno cambió     → no-op (return NEW sin tocar nada)
--   Solo nuevo cambió  → sincronizar canónico → legacy
--   Solo legacy cambió → sincronizar legacy → canónico
--                        + limpiar el otro campo legacy
--   Ambos cambiaron    → canónico gana (intent explícito del código nuevo)
--                        → sincronizar canónico → legacy
--
-- El "limpiar el otro campo legacy" en legacy→canónico evita que una
-- fila quede con embajador_id=X y referido_por_cliente_id=Y simultáneamente.

create or replace function public.fn_leads_sync_referidor_update()
returns trigger
language plpgsql
as $$
declare
  v_new_changed    boolean;
  v_legacy_changed boolean;
begin
  v_new_changed := (
    NEW.referidor_tipo is distinct from OLD.referidor_tipo or
    NEW.referidor_id   is distinct from OLD.referidor_id
  );
  v_legacy_changed := (
    NEW.embajador_id            is distinct from OLD.embajador_id or
    NEW.referido_por_cliente_id is distinct from OLD.referido_por_cliente_id
  );

  -- Nada cambió en ninguno de los dos lados → no-op
  if not v_new_changed and not v_legacy_changed then
    return NEW;
  end if;

  if v_new_changed then
    -- ── Canónico → legacy (nuevo gana, incluso si ambos cambiaron) ──
    if NEW.referidor_tipo = 'embajador' and NEW.referidor_id is not null then
      NEW.embajador_id            := NEW.referidor_id;
      NEW.referido_por_cliente_id := null;
    elsif NEW.referidor_tipo = 'cliente' and NEW.referidor_id is not null then
      NEW.referido_por_cliente_id := NEW.referidor_id;
      NEW.embajador_id            := null;
    elsif NEW.referidor_tipo = 'lead' and NEW.referidor_id is not null then
      -- Sin campo legacy para lead
      NEW.embajador_id            := null;
      NEW.referido_por_cliente_id := null;
    elsif NEW.referidor_tipo is null or NEW.referidor_id is null then
      -- Se limpió el lado canónico → limpiar legacy también
      NEW.embajador_id            := null;
      NEW.referido_por_cliente_id := null;
    end if;

  else
    -- ── Legacy → canónico (solo legacy cambió) ──────────────────
    if NEW.embajador_id is not null then
      NEW.referidor_tipo          := 'embajador';
      NEW.referidor_id            := NEW.embajador_id;
      NEW.referido_por_cliente_id := null;   -- limpiar otro campo legacy
    elsif NEW.referido_por_cliente_id is not null then
      NEW.referidor_tipo          := 'cliente';
      NEW.referidor_id            := NEW.referido_por_cliente_id;
      NEW.embajador_id            := null;   -- limpiar otro campo legacy
    else
      -- Ambos campos legacy vaciados → limpiar canónico
      NEW.referidor_tipo := null;
      NEW.referidor_id   := null;
    end if;
  end if;

  return NEW;
end;
$$;
-- Recrear trigger UPDATE
drop trigger if exists trg_leads_sync_referidor_update on public.leads;
create trigger trg_leads_sync_referidor_update
  before update on public.leads
  for each row
  execute function public.fn_leads_sync_referidor_update();
commit;
-- ============================================================
-- AUDIT QUERY — anomalías legacy (correr ANTES de aplicar migración)
-- Detecta filas donde embajador_id y referido_por_cliente_id están
-- poblados simultáneamente. El backfill resolverá con embajador_id
-- ganando. Si hay filas, revisar manualmente cuál es el dato correcto.
-- ============================================================
--
-- select
--   id,
--   nombre,
--   apellido,
--   telefono,
--   embajador_id,
--   referido_por_cliente_id,
--   referidor_tipo,
--   referidor_id,
--   created_at
-- from public.leads
-- where embajador_id is not null
--   and referido_por_cliente_id is not null
-- order by created_at desc;
--
-- Si el resultado está vacío: backfill sin ambigüedad.
-- Si hay filas: resolver manualmente antes de aplicar migración.
-- ============================================================

-- ============================================================
-- ROLLBACK
-- ============================================================
-- begin;
--
-- drop trigger if exists trg_leads_sync_referidor_update on public.leads;
-- drop trigger if exists trg_leads_sync_referidor_insert on public.leads;
-- drop function if exists public.fn_leads_sync_referidor_update();
-- drop function if exists public.fn_leads_sync_referidor_insert();
--
-- alter table public.leads
--   drop constraint if exists leads_referidor_tipo_values,
--   drop constraint if exists leads_referidor_nullity,
--   drop column    if exists referidor_tipo,
--   drop column    if exists referidor_id;
--
-- drop index if exists public.idx_leads_referidor;
--
-- commit;
-- ============================================================;
