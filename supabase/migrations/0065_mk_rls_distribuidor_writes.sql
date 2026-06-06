-- Migration 0065: MarketingFlow RLS distribuidor writes
-- Allows distributors to update mk_messages and insert mk_responses
-- for campaigns owned by agents under their scope.
begin;
drop policy if exists mk_messages_distribuidor_update on public.mk_messages;
create policy mk_messages_distribuidor_update on public.mk_messages
  for update to authenticated
  using (
    is_distribuidor() and is_distribuidor_of(owner_id)
  )
  with check (
    is_distribuidor() and is_distribuidor_of(owner_id)
  );
drop policy if exists mk_responses_distribuidor_insert on public.mk_responses;
create policy mk_responses_distribuidor_insert on public.mk_responses
  for insert to authenticated
  with check (
    is_distribuidor() and exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id and is_distribuidor_of(m.owner_id)
    )
  );
commit;
-- ROLLBACK:
-- begin;
-- drop policy if exists mk_messages_distribuidor_update on public.mk_messages;
-- drop policy if exists mk_responses_distribuidor_insert on public.mk_responses;
-- commit;;
