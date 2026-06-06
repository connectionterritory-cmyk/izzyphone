-- Migration 0067: Allow owner/distribuidor to update mk_responses
-- Ensures campaign owner and distribuidor can update responses within scope.
begin;
drop policy if exists mk_responses_owner_update on public.mk_responses;
create policy mk_responses_owner_update on public.mk_responses
  for update to authenticated
  using (
    exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id
        and m.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id
        and m.owner_id = auth.uid()
    )
  );
drop policy if exists mk_responses_distribuidor_update on public.mk_responses;
create policy mk_responses_distribuidor_update on public.mk_responses
  for update to authenticated
  using (
    is_distribuidor() and exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id
        and is_distribuidor_of(m.owner_id)
    )
  )
  with check (
    is_distribuidor() and exists (
      select 1 from public.mk_messages m
      where m.id = mk_responses.message_id
        and is_distribuidor_of(m.owner_id)
    )
  );
commit;
-- ROLLBACK:
-- begin;
-- drop policy if exists mk_responses_owner_update on public.mk_responses;
-- drop policy if exists mk_responses_distribuidor_update on public.mk_responses;
-- commit;;
