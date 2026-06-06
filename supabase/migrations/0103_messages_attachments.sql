-- 0103: inbox base schema + attachment support
--
-- conversations and messages were used by InboxPage and process-outbox
-- but were never documented as migrations. This migration creates them
-- with IF NOT EXISTS so it is safe to run whether or not they pre-exist.
--
-- ROLLBACK:
--   DROP TABLE public.messages;
--   DROP TABLE public.conversations;

-- ─── 1. conversations ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversations (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id               UUID,
  canal                TEXT        NOT NULL DEFAULT 'whatsapp'
                                   CHECK (canal IN ('whatsapp','sms','email')),
  contact_tipo         TEXT        CHECK (contact_tipo IN ('cliente','lead','embajador')),
  contact_id           UUID,
  phone_e164           TEXT,
  wa_id                TEXT,
  status               TEXT        NOT NULL DEFAULT 'open'
                                   CHECK (status IN ('open','closed','archived')),
  last_message_at      TIMESTAMPTZ,
  last_message_preview TEXT,
  unread_count         INT         NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS conversations_org_id_idx
  ON public.conversations (org_id);
CREATE INDEX IF NOT EXISTS conversations_wa_id_idx
  ON public.conversations (wa_id)
  WHERE wa_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS conversations_phone_e164_idx
  ON public.conversations (phone_e164)
  WHERE phone_e164 IS NOT NULL;
CREATE INDEX IF NOT EXISTS conversations_last_message_at_idx
  ON public.conversations (last_message_at DESC);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY conversations_org ON public.conversations
  FOR ALL TO authenticated
  USING (org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1))
  WITH CHECK (org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1));
-- ─── 2. messages ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id     UUID        REFERENCES public.conversations(id) ON DELETE CASCADE,
  direction           TEXT        NOT NULL CHECK (direction IN ('inbound','outbound')),
  message             TEXT,
  provider_message_id TEXT,
  status              TEXT        NOT NULL DEFAULT 'sent'
                                  CHECK (status IN ('pending','sent','delivered','read','failed')),
  error_message       TEXT,
  delivered_at        TIMESTAMPTZ,
  read_at             TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx
  ON public.messages (conversation_id);
CREATE INDEX IF NOT EXISTS messages_created_at_idx
  ON public.messages (created_at DESC);
CREATE INDEX IF NOT EXISTS messages_direction_idx
  ON public.messages (conversation_id, direction);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY messages_via_conversation ON public.messages
  FOR ALL TO authenticated
  USING (
    conversation_id IN (
      SELECT id FROM public.conversations
      WHERE org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1)
    )
  );
-- ─── 3. attachment_urls column ───────────────────────────────────────────────
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS attachment_urls TEXT[] NOT NULL DEFAULT '{}'::TEXT[];
COMMENT ON COLUMN public.messages.attachment_urls IS
  'Public URLs of media/doc attachments associated to this message.';
