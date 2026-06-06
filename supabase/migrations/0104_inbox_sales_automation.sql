-- 0104: inbox sales automation
-- Adds pipeline tracking, tags, direction sync, follow-up control to conversations.
-- Creates auto_reply_rules (keyword → template/text, configurable without code).
-- Creates inbox_tasks (manual follow-up reminders for sales reps).
--
-- Rollback:
--   DROP TABLE public.inbox_tasks;
--   DROP TABLE public.auto_reply_rules;
--   DROP TRIGGER trg_sync_conversation_direction ON public.messages;
--   DROP FUNCTION public.fn_sync_conversation_direction();
--   ALTER TABLE public.conversations
--     DROP COLUMN pipeline_stage,
--     DROP COLUMN tags,
--     DROP COLUMN assigned_to,
--     DROP COLUMN last_message_direction,
--     DROP COLUMN follow_up_sent_at,
--     DROP COLUMN follow_up_count,
--     DROP COLUMN auto_reply_sent_at;

-- ─── 1. Extend conversations ────────────────────────────────────────────────
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS pipeline_stage TEXT NOT NULL DEFAULT 'nuevo'
    CONSTRAINT conversations_pipeline_stage_check
    CHECK (pipeline_stage IN ('nuevo','contacto','demo_agendada','cerrado_ganado','cerrado_perdido')),

  ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT '{}',

  ADD COLUMN IF NOT EXISTS assigned_to UUID
    REFERENCES public.usuarios(id) ON DELETE SET NULL,

  -- tracks direction of the last message so n8n can query "last was inbound/outbound"
  ADD COLUMN IF NOT EXISTS last_message_direction TEXT
    CONSTRAINT conversations_last_direction_check
    CHECK (last_message_direction IN ('inbound','outbound')),

  -- follow-up automation controls
  ADD COLUMN IF NOT EXISTS follow_up_sent_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS follow_up_count    INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS auto_reply_sent_at TIMESTAMPTZ;
-- ─── 2. Trigger: keep last_message_direction in sync on every INSERT ─────────
CREATE OR REPLACE FUNCTION public.fn_sync_conversation_direction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.direction = 'inbound' THEN
    -- client replied → reset follow-up counter so the cron doesn't re-send
    UPDATE public.conversations
    SET
      last_message_direction = 'inbound',
      follow_up_count        = 0,
      follow_up_sent_at      = NULL,
      updated_at             = NOW()
    WHERE id = NEW.conversation_id;
  ELSE
    UPDATE public.conversations
    SET
      last_message_direction = 'outbound',
      updated_at             = NOW()
    WHERE id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_conversation_direction ON public.messages;
CREATE TRIGGER trg_sync_conversation_direction
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_sync_conversation_direction();
-- ─── 3. auto_reply_rules ─────────────────────────────────────────────────────
-- Stores keyword → response mappings. n8n reads this table to decide what to
-- reply to an inbound message, so rules can be edited without redeploying.
-- Either reply_text or template_id must be set (CHECK enforces this).
CREATE TABLE IF NOT EXISTS public.auto_reply_rules (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID    NOT NULL,
  keyword     TEXT    NOT NULL,
  reply_text  TEXT,
  template_id UUID    REFERENCES public.message_templates(id) ON DELETE SET NULL,
  priority    INT     NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT auto_reply_rules_reply_check
    CHECK (reply_text IS NOT NULL OR template_id IS NOT NULL)
);
-- partial index: only active rules are queried by n8n
CREATE UNIQUE INDEX IF NOT EXISTS auto_reply_rules_org_keyword_uidx
  ON public.auto_reply_rules(org_id, lower(keyword));
CREATE INDEX IF NOT EXISTS auto_reply_rules_org_active_idx
  ON public.auto_reply_rules(org_id, priority DESC)
  WHERE active = true;
ALTER TABLE public.auto_reply_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY auto_reply_rules_org ON public.auto_reply_rules
  USING (org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1))
  WITH CHECK (org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1));
-- ─── 4. inbox_tasks ──────────────────────────────────────────────────────────
-- Manual follow-up reminders assigned to a sales rep for a conversation.
CREATE TABLE IF NOT EXISTS public.inbox_tasks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  contact_id      UUID,
  contact_tipo    TEXT CHECK (contact_tipo IN ('cliente','lead','embajador')),
  assigned_to     UUID REFERENCES public.usuarios(id) ON DELETE SET NULL,
  titulo          TEXT NOT NULL,
  notas           TEXT,
  due_at          TIMESTAMPTZ,
  status          TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','done','cancelled')),
  completado_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS inbox_tasks_org_status_idx
  ON public.inbox_tasks(org_id, status);
CREATE INDEX IF NOT EXISTS inbox_tasks_conversation_id_idx
  ON public.inbox_tasks(conversation_id);
CREATE INDEX IF NOT EXISTS inbox_tasks_assigned_due_idx
  ON public.inbox_tasks(assigned_to, due_at)
  WHERE status = 'open';
ALTER TABLE public.inbox_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY inbox_tasks_org ON public.inbox_tasks
  USING (org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1))
  WITH CHECK (org_id = (SELECT u.org_id FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1));
-- ─── 5. Seed auto_reply_rules sample rows (replace org_id before running) ───
-- INSERT INTO public.auto_reply_rules (org_id, keyword, reply_text, priority) VALUES
--   ('YOUR_ORG_ID', 'precio',      'Hola! Te comparto información sobre nuestros precios. Un asesor te contactará pronto.', 10),
--   ('YOUR_ORG_ID', 'información', 'Hola! Con gusto te enviamos más información. ¿Cuál es tu ciudad?', 9),
--   ('YOUR_ORG_ID', 'filtro',      'Nuestros sistemas de filtración tienen garantía de por vida. ¿Te interesa una demo?', 8),
--   ('YOUR_ORG_ID', 'olla',        'Las ollas Royal Prestige son de acero quirúrgico 316L. ¿Quieres conocer el set completo?', 8);;
