-- =================================================================
-- 0084: fn_dispatch_campaign — bulk dispatch plpgsql function
-- =================================================================
-- Dispatches all pendiente mk_messages for a campaign that don't yet
-- have an outbox_message_id into outbox_messages, with staggered
-- scheduled_for timestamps (default 1100ms apart for rate limiting).
--
-- Idempotent: filters on status='pendiente' AND outbox_message_id IS NULL,
-- so re-running after a partial dispatch only picks up remaining rows.

CREATE OR REPLACE FUNCTION public.fn_dispatch_campaign(
  p_campaign_id uuid,
  p_interval_ms integer DEFAULT 1100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_msg        record;
  v_outbox_id  uuid;
  v_count      integer := 0;
BEGIN
  -- Validate campaign exists
  PERFORM 1 FROM public.mk_campaigns WHERE id = p_campaign_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'campaign_not_found');
  END IF;

  -- Dispatch all pendiente messages not yet linked to outbox
  FOR v_msg IN
    SELECT id, canal, telefono, mensaje_texto, owner_id, contacto_tipo, contacto_id
    FROM public.mk_messages
    WHERE campaign_id = p_campaign_id
      AND status = 'pendiente'
      AND outbox_message_id IS NULL
      AND telefono IS NOT NULL
      AND mensaje_texto IS NOT NULL
    ORDER BY orden NULLS LAST, created_at
  LOOP
    INSERT INTO public.outbox_messages (
      canal, destinatario, mensaje,
      scheduled_for, status, contexto_tipo,
      owner_id, contact_tipo, contact_id
    )
    VALUES (
      v_msg.canal,
      v_msg.telefono,
      v_msg.mensaje_texto,
      now() + (v_count * p_interval_ms * interval '1 millisecond'),
      'programado',
      'campaign',
      v_msg.owner_id,
      v_msg.contacto_tipo,
      v_msg.contacto_id
    )
    RETURNING id INTO v_outbox_id;

    UPDATE public.mk_messages
    SET outbox_message_id = v_outbox_id,
        status = 'programado'
    WHERE id = v_msg.id;

    v_count := v_count + 1;
  END LOOP;

  -- Mark campaign active + record dispatched_at if any messages were queued
  IF v_count > 0 THEN
    UPDATE public.mk_campaigns
    SET estado = 'activa',
        dispatched_at = now()
    WHERE id = p_campaign_id;
  END IF;

  RETURN jsonb_build_object('dispatched', v_count, 'campaign_id', p_campaign_id);
END;
$$;
COMMENT ON FUNCTION public.fn_dispatch_campaign(uuid, integer) IS
  'Bulk-dispatches pendiente mk_messages (without outbox_message_id) for a campaign. '
  'Stagger: p_interval_ms between scheduled_for timestamps (default 1100ms). '
  'Updates mk_messages.outbox_message_id + status=programado. '
  'Sets mk_campaigns.estado=activa, dispatched_at=now() when messages are queued.';
