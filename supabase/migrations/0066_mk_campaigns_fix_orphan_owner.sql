-- Migration 0066: Fix orphaned owner_id in mk_campaigns and enforce FK integrity.
--
-- Root cause: owner_id can reference a user that exists in auth.users but was
-- never synced to public.usuarios (missing handle_new_user trigger or manual
-- auth creation). The FK to public.usuarios then has nothing to enforce against
-- if it was never applied, or the row was written before the constraint existed.
--
-- This migration:
--   1. Identifies orphaned campaigns (verification query — see bottom).
--   2. Reassigns orphaned campaigns to the fallback admin (first active admin).
--   3. Drops and recreates the FK constraint with ON DELETE RESTRICT to prevent
--      future orphans via the DB layer.
--   4. Adds a trigger that blocks INSERT/UPDATE if owner_id is not in usuarios.

begin;
-- ── Step 1: Reassign orphaned campaigns to fallback admin ─────────────────────
-- Finds campaigns whose owner_id has no matching row in public.usuarios,
-- then sets owner_id to the first active admin user as a safe fallback.

do $$
declare
  v_fallback_id uuid;
begin
  -- Pick the first active admin as fallback owner
  select id into v_fallback_id
  from public.usuarios
  where rol = 'admin' and activo = true
  order by created_at asc
  limit 1;

  if v_fallback_id is null then
    raise exception 'No active admin found in usuarios — cannot reassign orphaned campaigns.';
  end if;

  update public.mk_campaigns
  set owner_id = v_fallback_id
  where owner_id not in (select id from public.usuarios);

  raise notice 'Orphaned campaigns reassigned to %', v_fallback_id;
end;
$$;
-- ── Step 2: Also fix mk_messages orphans (same root cause) ────────────────────
do $$
declare
  v_fallback_id uuid;
begin
  select id into v_fallback_id
  from public.usuarios
  where rol = 'admin' and activo = true
  order by created_at asc
  limit 1;

  if v_fallback_id is null then
    raise exception 'No active admin found — cannot reassign orphaned messages.';
  end if;

  update public.mk_messages
  set owner_id = v_fallback_id
  where owner_id not in (select id from public.usuarios);

  raise notice 'Orphaned messages reassigned to %', v_fallback_id;
end;
$$;
-- ── Step 3: Enforce FK with ON DELETE RESTRICT (idempotent) ──────────────────
-- mk_campaigns
alter table public.mk_campaigns
  drop constraint if exists mk_campaigns_owner_id_fkey;
alter table public.mk_campaigns
  add constraint mk_campaigns_owner_id_fkey
  foreign key (owner_id)
  references public.usuarios(id)
  on delete restrict;
-- mk_messages
alter table public.mk_messages
  drop constraint if exists mk_messages_owner_id_fkey;
alter table public.mk_messages
  add constraint mk_messages_owner_id_fkey
  foreign key (owner_id)
  references public.usuarios(id)
  on delete restrict;
-- ── Step 4: Trigger to block orphan owner_id at INSERT/UPDATE ─────────────────
-- Belt-and-suspenders: catches writes that bypass FK (e.g. service_role with
-- session_replication_role = replica).

create or replace function public.fn_check_mk_owner_exists()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.usuarios where id = NEW.owner_id) then
    raise exception 'owner_id % does not exist in public.usuarios', NEW.owner_id;
  end if;
  return NEW;
end;
$$;
drop trigger if exists trg_mk_campaigns_owner_check on public.mk_campaigns;
create trigger trg_mk_campaigns_owner_check
  before insert or update of owner_id on public.mk_campaigns
  for each row execute function public.fn_check_mk_owner_exists();
drop trigger if exists trg_mk_messages_owner_check on public.mk_messages;
create trigger trg_mk_messages_owner_check
  before insert or update of owner_id on public.mk_messages
  for each row execute function public.fn_check_mk_owner_exists();
commit;
-- ── Verification query (run separately to inspect before/after) ───────────────
-- Find any remaining orphaned campaigns:
--
-- select c.id, c.nombre, c.owner_id, c.estado
-- from public.mk_campaigns c
-- where not exists (select 1 from public.usuarios u where u.id = c.owner_id);
--
-- Find any remaining orphaned messages:
--
-- select m.id, m.nombre, m.owner_id
-- from public.mk_messages m
-- where not exists (select 1 from public.usuarios u where u.id = m.owner_id)
-- limit 20;

-- ROLLBACK:
-- begin;
-- drop trigger if exists trg_mk_campaigns_owner_check on public.mk_campaigns;
-- drop trigger if exists trg_mk_messages_owner_check on public.mk_messages;
-- drop function if exists public.fn_check_mk_owner_exists();
-- alter table public.mk_campaigns drop constraint if exists mk_campaigns_owner_id_fkey;
-- alter table public.mk_campaigns add constraint mk_campaigns_owner_id_fkey
--   foreign key (owner_id) references public.usuarios(id) on delete restrict;
-- alter table public.mk_messages drop constraint if exists mk_messages_owner_id_fkey;
-- alter table public.mk_messages add constraint mk_messages_owner_id_fkey
--   foreign key (owner_id) references public.usuarios(id) on delete restrict;
-- commit;;
