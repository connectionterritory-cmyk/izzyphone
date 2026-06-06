-- Migration 0034: segment_params en mk_campaigns + fix mk_messages INSERT policy
-- 1. segment_params jsonb para guardar {month} del segmento cumpleanos_clientes
-- 2. DROP mk_messages_owner_insert (0028) y reemplazar con mk_messages_insert_own_campaign
--    que verifica campaign ownership. Sin este drop, la nueva policy es inefectiva
--    porque las policies PERMISSIVE hacen OR: la anterior siempre pasa primero.

begin;
-- ── 1. segment_params en mk_campaigns ────────────────────────────────────────
alter table public.mk_campaigns
  add column if not exists segment_params jsonb not null default '{}'::jsonb;
-- ── 2. Reemplazar mk_messages_owner_insert con policy que verifica campaign ──
-- IMPORTANTE: hay que hacer DROP primero. Si ambas coexisten (PERMISSIVE),
-- la original (solo owner_id = auth.uid()) deja pasar inserts sin campaign check.
drop policy if exists mk_messages_owner_insert          on public.mk_messages;
drop policy if exists mk_messages_insert_own_campaign   on public.mk_messages;
create policy mk_messages_insert_own_campaign on public.mk_messages
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1
      from public.mk_campaigns c
      where c.id = campaign_id
        and c.owner_id = auth.uid()
    )
  );
-- Nota: mk_messages_admin_all (for all, using is_admin()) cubre inserts para admin
-- sin restriccion de campaign ownership — comportamiento intencional.

commit;
-- ROLLBACK:
-- begin;
-- drop policy if exists mk_messages_insert_own_campaign on public.mk_messages;
-- create policy mk_messages_owner_insert on public.mk_messages
--   for insert to authenticated
--   with check (owner_id = auth.uid());
-- alter table public.mk_campaigns drop column if exists segment_params;
-- commit;;
