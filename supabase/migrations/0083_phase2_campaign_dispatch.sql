-- =================================================================
-- 0083: Phase 2B - mk_campaigns dispatch tracking
-- =================================================================
-- Adds timestamps for first dispatch and completion.
-- Safe, nullable columns for existing rows.

ALTER TABLE public.mk_campaigns
  ADD COLUMN IF NOT EXISTS dispatched_at timestamptz NULL;
ALTER TABLE public.mk_campaigns
  ADD COLUMN IF NOT EXISTS completed_at  timestamptz NULL;
COMMENT ON COLUMN public.mk_campaigns.dispatched_at IS
  'Timestamp when campaign dispatch was triggered (first batch).';
COMMENT ON COLUMN public.mk_campaigns.completed_at IS
  'Timestamp when campaign dispatch finished (no pending rows left).';
