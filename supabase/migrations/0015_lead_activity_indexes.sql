-- Migration 0015: Indexes for lead activity view and app queries
-- These indexes support:
--   1. v_lead_last_activity — the LEFT JOIN + max(created_at) aggregation
--   2. HoyPage + LeadsPage — .eq('vendedor_id', ...) queries with deleted_at filter

begin;
-- 1. Covering index for the view's JOIN and max(created_at) aggregation.
--    When LeadsPage calls loadLastActivity with .in('lead_id', ids), Postgres can
--    satisfy max(created_at) per lead_id with an index-only scan.
create index if not exists lead_notas_lead_id_created_at_idx
  on public.lead_notas (lead_id, created_at desc);
-- 2. Partial covering index for the view's WHERE + GROUP BY.
--    Only indexes non-deleted leads — significantly reduces index size and
--    allows an index-only scan for (id, updated_at) on active leads.
--    The lead PK covers id over ALL rows; this covers id+updated_at for active rows only.
create index if not exists leads_active_idx
  on public.leads (id, updated_at)
  where deleted_at is null;
-- 3. Composite index for vendedor-scoped queries (.eq('vendedor_id', x) + deleted_at filter).
--    Note: deleted_at in the column list is redundant given the partial condition
--    (all entries will have deleted_at = null), but retained per spec and harmless.
create index if not exists leads_vendedor_deleted_idx
  on public.leads (vendedor_id, deleted_at)
  where deleted_at is null;
commit;
