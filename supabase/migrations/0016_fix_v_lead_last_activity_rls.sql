-- Migration 0014: Fix v_lead_last_activity — add security_invoker
-- Problem: the view in 0012 runs with the view owner's permissions (postgres role),
--          which bypasses RLS on leads and lead_notas.
-- Fix:     WITH (security_invoker = true) makes the view execute as the calling
--          user, so RLS policies on leads and lead_notas are enforced.
-- Requires: PostgreSQL 15+ (Supabase uses PG 15). ✅
--
-- Behavior change:
--   Before: authenticated user → postgres permissions → no RLS → all leads visible
--   After:  authenticated user → caller permissions → RLS applies → only own leads visible

begin;
create or replace view public.v_lead_last_activity
  with (security_invoker = true)    -- caller's permissions; RLS on leads + lead_notas enforced
as
select
  l.id                                              as lead_id,
  greatest(
    coalesce(max(n.created_at), l.updated_at),
    l.updated_at
  )                                                 as last_activity_at
from public.leads l
left join public.lead_notas n on n.lead_id = l.id
where l.deleted_at is null
group by l.id, l.updated_at;
-- Explicit grant as defense-in-depth.
-- Supabase's default privileges already cover this, but migrations do NOT inherit them
-- automatically for views, so we make it explicit and idempotent.
grant select on public.v_lead_last_activity to authenticated;
grant select on public.v_lead_last_activity to anon;
commit;
