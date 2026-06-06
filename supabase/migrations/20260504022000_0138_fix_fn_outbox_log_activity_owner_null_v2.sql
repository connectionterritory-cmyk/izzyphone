
CREATE OR REPLACE FUNCTION public.fn_outbox_log_activity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (new.status IN ('enviado', 'programado')
      AND new.contact_tipo IS NOT NULL
      AND new.contact_id IS NOT NULL
      AND new.owner_id IS NOT NULL) THEN
    INSERT INTO public.contacto_actividades (
      contacto_tipo, contacto_id, tipo, resumen, contenido, metadata, autor_id, fecha_actividad
    ) VALUES (
      new.contact_tipo,
      new.contact_id,
      new.canal,
      CASE
        WHEN new.canal = 'email'    THEN 'Email enviado: ' || COALESCE(new.asunto, '(sin asunto)')
        WHEN new.canal = 'whatsapp' THEN 'WhatsApp enviado'
        ELSE initcap(new.canal) || ' enviado'
      END,
      new.mensaje_resuelto,
      jsonb_build_object(
        'outbox_id',        new.id,
        'canal',            new.canal,
        'destinatario',     new.destinatario,
        'attachment_count', array_length(new.attachment_urls, 1)
      ),
      new.owner_id,
      COALESCE(new.sent_at, new.created_at, now())
    );
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_outbox_log_activity() IS
  'Logs outbox sends to contacto_actividades timeline. Skipped when owner_id is null (automated/n8n sends).';
;
