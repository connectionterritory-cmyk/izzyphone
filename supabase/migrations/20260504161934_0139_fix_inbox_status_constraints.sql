-- ============================================================
-- 0139: Fix messages.status CHECK — add 'received' for inbound
-- ============================================================

begin;

-- Drop existing CHECK constraint on messages.status, whatever Postgres named it
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.messages'::regclass
      AND contype = 'c'
      AND conname LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS %I', r.conname);
    RAISE NOTICE 'Dropped constraint: %', r.conname;
  END LOOP;
END;
$$;

-- Recreate with 'received' added for inbound messages
ALTER TABLE public.messages
  ADD CONSTRAINT messages_status_check
  CHECK (status IN ('pending', 'sent', 'delivered', 'read', 'failed', 'received'));

comment on column public.messages.status is
  'Message delivery status. Outbound: pending→sent→delivered→read|failed. Inbound: received.';

commit;;
