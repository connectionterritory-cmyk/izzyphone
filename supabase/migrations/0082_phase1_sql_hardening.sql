-- =================================================================
-- 0082: Phase 1 SQL Hardening
-- =================================================================
-- Forward-only. Migration 0081 (phase1_outbox_mk_link) was applied
-- as version 20260412162331. This migration does NOT touch 0081.
--
-- Root cause discovered during first apply attempt:
--   mk_messages_sync_status() trigger used legacy vocabulary
--   ('sent', 'responded') and had no awareness of outbox-managed
--   states, causing the CHECK constraint to fail and the worker
--   sync to be silently overridden on every UPDATE.
--
-- Changes (must run in this order):
--   1) Fix trigger function (new vocab + respect outbox statuses)
--   2) Normalize legacy data  (works correctly with fixed trigger)
--   3) Add CHECK constraint on mk_messages.status
--   4) Add retry_after / locked_at / locked_by to outbox_messages
--   5) Add indexes for retry scheduling and orphan recovery
--   6) Drop superseded outbox scheduled index
-- =================================================================


-- =================================================================
-- 1. Fix mk_messages_sync_status() trigger function
-- =================================================================
-- Old problem: function used 'sent' / 'responded' and had no guard
-- for outbox-managed statuses. Two concrete bugs:
--
--   a) Worker sync: status='enviado' + sent_at=now() → trigger
--      overrode to 'sent' (old vocab) → CHECK constraint violated.
--   b) Worker sync: status='en_proceso' on rows with old sent_at
--      → trigger overrode to 'sent' silently.
--
-- Fix: whitelist outbox-managed states (trigger skips them entirely)
-- and update derived values to canonical vocabulary.

CREATE OR REPLACE FUNCTION public.mk_messages_sync_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
begin
  -- States managed by the outbox worker: never override these.
  -- They are set explicitly by syncMkMessage() in process-outbox.
  if new.status in ('programado', 'en_proceso', 'fallido', 'cancelado') then
    return new;
  end if;

  -- For all other cases, derive status from timestamp columns.
  -- Canonical vocabulary: respondido / enviado / pendiente.
  if new.responded_at is not null then
    new.status := 'respondido';   -- previously: 'responded'
  elsif new.sent_at is not null then
    new.status := 'enviado';      -- previously: 'sent'
  else
    new.status := coalesce(new.status, 'pendiente');
  end if;

  return new;
end;
$$;
COMMENT ON FUNCTION public.mk_messages_sync_status() IS
  'BEFORE INSERT/UPDATE trigger on mk_messages. '
  'Respects outbox-managed statuses (programado, en_proceso, fallido, cancelado). '
  'For other rows, derives status from timestamp columns: '
  'respondido (responded_at IS NOT NULL), enviado (sent_at IS NOT NULL), pendiente (else).';
-- =================================================================
-- 2. Normalize legacy mk_messages status values
-- =================================================================
-- With the trigger now fixed, these UPDATEs complete correctly:
--   procesando rows: no timestamps → trigger preserves 'pendiente'
--   sent rows:       sent_at IS NOT NULL → trigger outputs 'enviado'
--   responded rows:  responded_at IS NOT NULL → trigger → 'respondido'
--
-- Data confirmed before migration (SELECT GROUP BY):
--   procesando : 1913 rows
--   sent       :   75 rows
--   responded  :    3 rows

UPDATE public.mk_messages SET status = 'pendiente'  WHERE status = 'procesando';
UPDATE public.mk_messages SET status = 'enviado'    WHERE status = 'sent';
UPDATE public.mk_messages SET status = 'respondido' WHERE status = 'responded';
-- =================================================================
-- 3. CHECK constraint on mk_messages.status
-- =================================================================
-- Uses NOT VALID to skip table scan (avoids race condition window),
-- then validates immediately. Safe because the fixed trigger already
-- prevents any new row from carrying an invalid status value.

ALTER TABLE public.mk_messages
  DROP CONSTRAINT IF EXISTS mk_messages_status_check;
ALTER TABLE public.mk_messages
  ADD CONSTRAINT mk_messages_status_check
  CHECK (status IN (
    'pendiente',    -- awaiting send (default)
    'programado',   -- linked to outbox queue, not yet processed
    'en_proceso',   -- outbox worker has locked the paired row
    'enviado',      -- delivery confirmed by worker
    'fallido',      -- delivery failed (worker reported error)
    'respondido',   -- response registered by user
    'cancelado'     -- cancelled before send
  ))
  NOT VALID;
-- Validate existing rows (ShareUpdateExclusiveLock — non-blocking).
ALTER TABLE public.mk_messages
  VALIDATE CONSTRAINT mk_messages_status_check;
-- =================================================================
-- 4. Add retry and orphan-recovery columns to outbox_messages
-- =================================================================
-- All NULL-default: zero impact on existing rows.
-- Worker can populate these in a future sprint without schema changes.

ALTER TABLE public.outbox_messages
  ADD COLUMN IF NOT EXISTS retry_after timestamptz NULL;
ALTER TABLE public.outbox_messages
  ADD COLUMN IF NOT EXISTS locked_at   timestamptz NULL;
ALTER TABLE public.outbox_messages
  ADD COLUMN IF NOT EXISTS locked_by   text        NULL;
COMMENT ON COLUMN public.outbox_messages.retry_after IS
  'Earliest timestamp for next retry attempt. NULL = no delay. '
  'Set by worker when transitioning to retry_pending. '
  'Worker query: status = ''retry_pending'' AND (retry_after IS NULL OR retry_after <= now()).';
COMMENT ON COLUMN public.outbox_messages.locked_at IS
  'Timestamp when the worker claimed this row (set status = en_proceso). '
  'Orphan recovery: status = en_proceso AND locked_at < now() - interval ''10 minutes'' '
  'can be safely reset to programado.';
COMMENT ON COLUMN public.outbox_messages.locked_by IS
  'Identifier of the worker invocation that locked this row. '
  'For debugging stale locks and concurrent processing issues.';
-- =================================================================
-- 5. Indexes for retry scheduling and orphan recovery
-- =================================================================

-- Retry scheduling: status='retry_pending' AND retry_after <= now()
CREATE INDEX IF NOT EXISTS outbox_messages_retry_idx
  ON public.outbox_messages (retry_after)
  WHERE status = 'retry_pending';
-- Orphan recovery: status='en_proceso' AND locked_at < now() - interval 'X'
-- Near-zero cardinality in steady state.
CREATE INDEX IF NOT EXISTS outbox_messages_orphan_idx
  ON public.outbox_messages (locked_at)
  WHERE status = 'en_proceso';
-- =================================================================
-- 6. Drop superseded index
-- =================================================================
-- outbox_messages_scheduled_idx: WHERE status = 'programado'
-- Superseded by outbox_messages_scheduled_pending_v2:
--   WHERE status IN ('programado', 'retry_pending')
-- Removing reduces write amplification on every INSERT/UPDATE.

DROP INDEX IF EXISTS public.outbox_messages_scheduled_idx;
