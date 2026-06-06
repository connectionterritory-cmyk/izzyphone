-- Migration 0068: Distribuidor scope for MarketingFlow
--
-- NOTA: La rama is_org_member fue removida de todas las policies porque
-- public.memberships no existe en este entorno de producción (divergencia
-- con migration 0001). Las policies quedan con is_distribuidor_of como
-- único criterio de acceso distribuidor hasta que se corrija el estado
-- de la tabla memberships en una migración separada.
begin;
-- ── mk_campaigns ─────────────────────────────────────────────────────────────
drop policy if exists mk_campaigns_distribuidor_read on public.mk_campaigns;
drop policy if exists mk_campaigns_distribuidor_update on public.mk_campaigns;
create policy mk_campaigns_distribuidor_read on public.mk_campaigns
  for select to authenticated
  using (
    is_distribuidor()
    and is_distribuidor_of(owner_id)
  );
create policy mk_campaigns_distribuidor_update on public.mk_campaigns
  for update to authenticated
  using (
    is_distribuidor()
    and is_distribuidor_of(owner_id)
  )
  with check (
    is_distribuidor()
    and is_distribuidor_of(owner_id)
  );
-- ── mk_messages ──────────────────────────────────────────────────────────────
drop policy if exists mk_messages_distribuidor_read on public.mk_messages;
drop policy if exists mk_messages_distribuidor_update on public.mk_messages;
create policy mk_messages_distribuidor_read on public.mk_messages
  for select to authenticated
  using (
    is_distribuidor()
    and is_distribuidor_of(owner_id)
  );
create policy mk_messages_distribuidor_update on public.mk_messages
  for update to authenticated
  using (
    is_distribuidor()
    and is_distribuidor_of(owner_id)
  )
  with check (
    is_distribuidor()
    and is_distribuidor_of(owner_id)
  );
-- ── mk_responses ─────────────────────────────────────────────────────────────
drop policy if exists mk_responses_distribuidor_read on public.mk_responses;
drop policy if exists mk_responses_distribuidor_insert on public.mk_responses;
drop policy if exists mk_responses_distribuidor_update on public.mk_responses;
create policy mk_responses_distribuidor_read on public.mk_responses
  for select to authenticated
  using (
    is_distribuidor() and exists (
      select 1
      from public.mk_messages m
      where m.id = mk_responses.message_id
        and is_distribuidor_of(m.owner_id)
    )
  );
create policy mk_responses_distribuidor_insert on public.mk_responses
  for insert to authenticated
  with check (
    is_distribuidor() and exists (
      select 1
      from public.mk_messages m
      where m.id = mk_responses.message_id
        and is_distribuidor_of(m.owner_id)
    )
  );
create policy mk_responses_distribuidor_update on public.mk_responses
  for update to authenticated
  using (
    is_distribuidor() and exists (
      select 1
      from public.mk_messages m
      where m.id = mk_responses.message_id
        and is_distribuidor_of(m.owner_id)
    )
  )
  with check (
    is_distribuidor() and exists (
      select 1
      from public.mk_messages m
      where m.id = mk_responses.message_id
        and is_distribuidor_of(m.owner_id)
    )
  );
commit;
-- ROLLBACK:
-- begin;
-- drop policy if exists mk_campaigns_distribuidor_read on public.mk_campaigns;
-- drop policy if exists mk_campaigns_distribuidor_update on public.mk_campaigns;
-- drop policy if exists mk_messages_distribuidor_read on public.mk_messages;
-- drop policy if exists mk_messages_distribuidor_update on public.mk_messages;
-- drop policy if exists mk_responses_distribuidor_read on public.mk_responses;
-- drop policy if exists mk_responses_distribuidor_insert on public.mk_responses;
-- drop policy if exists mk_responses_distribuidor_update on public.mk_responses;
-- commit;;
