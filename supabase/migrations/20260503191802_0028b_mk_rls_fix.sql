-- Migration 0028: Rebuild RLS policies for mk_campaigns and mk_messages.
-- Root cause: mk_messages SELECT returns 0 rows even when rows exist.
-- Probable cause: migration 0025 used "for all" combined policies; splitting
-- into explicit per-operation policies eliminates ambiguity and ensures SELECT
-- is independently covered for owner_id = auth.uid(), admin, and distribuidor.
--
-- Safe to rerun: all DROP IF EXISTS before CREATE.

begin;
-- ── mk_campaigns ─────────────────────────────────────────────────────────────

drop policy if exists mk_campaigns_admin_all          on public.mk_campaigns;
drop policy if exists mk_campaigns_owner_all          on public.mk_campaigns;
drop policy if exists mk_campaigns_owner_select       on public.mk_campaigns;
drop policy if exists mk_campaigns_owner_insert       on public.mk_campaigns;
drop policy if exists mk_campaigns_owner_update       on public.mk_campaigns;
drop policy if exists mk_campaigns_owner_delete       on public.mk_campaigns;
drop policy if exists mk_campaigns_distribuidor_read  on public.mk_campaigns;
-- Admin: full access to all campaigns
create policy mk_campaigns_admin_all on public.mk_campaigns
  for all to authenticated
  using (is_admin())
  with check (is_admin());
-- Owner: explicit per-operation policies
create policy mk_campaigns_owner_select on public.mk_campaigns
  for select to authenticated
  using (owner_id = auth.uid());
create policy mk_campaigns_owner_insert on public.mk_campaigns
  for insert to authenticated
  with check (owner_id = auth.uid());
create policy mk_campaigns_owner_update on public.mk_campaigns
  for update to authenticated
  using  (owner_id = auth.uid())
  with check (owner_id = auth.uid());
create policy mk_campaigns_owner_delete on public.mk_campaigns
  for delete to authenticated
  using (owner_id = auth.uid());
-- Distribuidor: read-only for campaigns owned by their team
create policy mk_campaigns_distribuidor_read on public.mk_campaigns
  for select to authenticated
  using (is_distribuidor() and is_distribuidor_of(owner_id));
-- ── mk_messages ───────────────────────────────────────────────────────────────

drop policy if exists mk_messages_admin_all           on public.mk_messages;
drop policy if exists mk_messages_owner_all           on public.mk_messages;
drop policy if exists mk_messages_owner_select        on public.mk_messages;
drop policy if exists mk_messages_owner_insert        on public.mk_messages;
drop policy if exists mk_messages_owner_update        on public.mk_messages;
drop policy if exists mk_messages_owner_delete        on public.mk_messages;
drop policy if exists mk_messages_distribuidor_read   on public.mk_messages;
-- Admin: full access to all messages
create policy mk_messages_admin_all on public.mk_messages
  for all to authenticated
  using (is_admin())
  with check (is_admin());
-- Owner: SELECT own messages
create policy mk_messages_owner_select on public.mk_messages
  for select to authenticated
  using (owner_id = auth.uid());
-- Owner: INSERT own messages
create policy mk_messages_owner_insert on public.mk_messages
  for insert to authenticated
  with check (owner_id = auth.uid());
-- Owner: UPDATE own messages (optional, included for completeness)
create policy mk_messages_owner_update on public.mk_messages
  for update to authenticated
  using  (owner_id = auth.uid())
  with check (owner_id = auth.uid());
-- Owner: DELETE own messages
create policy mk_messages_owner_delete on public.mk_messages
  for delete to authenticated
  using (owner_id = auth.uid());
-- Distribuidor: read-only for messages owned by their team
create policy mk_messages_distribuidor_read on public.mk_messages
  for select to authenticated
  using (is_distribuidor() and is_distribuidor_of(owner_id));
commit;
-- ROLLBACK (restore migration 0025 policies):
-- begin;
-- -- mk_campaigns
-- drop policy if exists mk_campaigns_admin_all         on public.mk_campaigns;
-- drop policy if exists mk_campaigns_owner_select      on public.mk_campaigns;
-- drop policy if exists mk_campaigns_owner_insert      on public.mk_campaigns;
-- drop policy if exists mk_campaigns_owner_update      on public.mk_campaigns;
-- drop policy if exists mk_campaigns_owner_delete      on public.mk_campaigns;
-- drop policy if exists mk_campaigns_distribuidor_read on public.mk_campaigns;
-- create policy mk_campaigns_admin_all on public.mk_campaigns for all to authenticated using (is_admin());
-- create policy mk_campaigns_owner_all on public.mk_campaigns for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- create policy mk_campaigns_distribuidor_read on public.mk_campaigns for select to authenticated using (is_distribuidor() and is_distribuidor_of(owner_id));
-- -- mk_messages
-- drop policy if exists mk_messages_admin_all          on public.mk_messages;
-- drop policy if exists mk_messages_owner_select       on public.mk_messages;
-- drop policy if exists mk_messages_owner_insert       on public.mk_messages;
-- drop policy if exists mk_messages_owner_update       on public.mk_messages;
-- drop policy if exists mk_messages_owner_delete       on public.mk_messages;
-- drop policy if exists mk_messages_distribuidor_read  on public.mk_messages;
-- create policy mk_messages_admin_all on public.mk_messages for all to authenticated using (is_admin());
-- create policy mk_messages_owner_all on public.mk_messages for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- create policy mk_messages_distribuidor_read on public.mk_messages for select to authenticated using (is_distribuidor() and is_distribuidor_of(owner_id));
-- commit;;
