-- Migration 0026: MarketingFlow hardening — corrige 4 problemas antes de escalar.
-- 1. owner_id ON DELETE CASCADE → RESTRICT (evita borrado en cascada de campañas)
-- 2. org_id nullable en mk_campaigns (multi-tenant futuro, non-breaking)
-- 3. Índice mk_messages(owner_id) (rendimiento RLS)
-- 4. Índice mk_campaigns(segmento_key) (dashboard filters)
begin;
-- ── 1. owner_id FK: CASCADE → RESTRICT en mk_campaigns ───────────────────────
-- PostgreSQL no permite ALTER de una FK; hay que drop + recrear.
alter table public.mk_campaigns
  drop constraint if exists mk_campaigns_owner_id_fkey;
alter table public.mk_campaigns
  add constraint mk_campaigns_owner_id_fkey
  foreign key (owner_id)
  references public.usuarios(id)
  on delete restrict;
-- ── 1b. owner_id FK: CASCADE → RESTRICT en mk_messages ───────────────────────
alter table public.mk_messages
  drop constraint if exists mk_messages_owner_id_fkey;
alter table public.mk_messages
  add constraint mk_messages_owner_id_fkey
  foreign key (owner_id)
  references public.usuarios(id)
  on delete restrict;
-- ── 2. org_id en mk_campaigns (nullable — no rompe app actual) ────────────────
alter table public.mk_campaigns
  add column if not exists org_id uuid;
-- ── 3. Índice owner_id en mk_messages (requerido para RLS performance) ────────
create index if not exists mk_messages_owner_idx
  on public.mk_messages (owner_id);
-- ── 4. Índice segmento_key en mk_campaigns (dashboard filters) ────────────────
create index if not exists mk_campaigns_segmento_idx
  on public.mk_campaigns (segmento_key);
commit;
-- ROLLBACK:
-- begin;
-- alter table public.mk_messages   drop constraint if exists mk_messages_owner_id_fkey;
-- alter table public.mk_messages   add constraint mk_messages_owner_id_fkey
--   foreign key (owner_id) references public.usuarios(id) on delete cascade;
-- alter table public.mk_campaigns  drop constraint if exists mk_campaigns_owner_id_fkey;
-- alter table public.mk_campaigns  add constraint mk_campaigns_owner_id_fkey
--   foreign key (owner_id) references public.usuarios(id) on delete cascade;
-- alter table public.mk_campaigns  drop column if exists org_id;
-- drop index if exists mk_messages_owner_idx;
-- drop index if exists mk_campaigns_segmento_idx;
-- commit;;
