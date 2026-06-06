-- Migration 0064: Fix unique index en mk_messages
-- Reemplaza el índice campaign_phone por uno basado en cita_id + telefono + ventana temporal
-- Prerequisito: 0063 (cita_id column en mk_messages)

begin;
-- Eliminar índice antiguo que bloqueaba mensajes futuros al mismo cliente
DROP INDEX IF EXISTS mk_messages_campaign_phone_unique;
-- Nuevo índice: un mensaje por tipo de recordatorio (24H, 1H, otro) por cita por teléfono
-- Permite recordatorios de distintas citas al mismo teléfono ✅
-- Bloquea duplicados del mismo recordatorio ✅
CREATE UNIQUE INDEX IF NOT EXISTS mk_messages_cita_telefono_ventana_unique
  ON public.mk_messages (
    cita_id,
    telefono,
    (CASE
      WHEN mensaje_texto LIKE '%[24H]%' THEN '24h'
      WHEN mensaje_texto LIKE '%[1H]%'  THEN '1h'
      ELSE 'other'
    END)
  )
  WHERE cita_id IS NOT NULL;
commit;
-- ROLLBACK:
-- begin;
-- DROP INDEX IF EXISTS mk_messages_cita_telefono_ventana_unique;
-- CREATE UNIQUE INDEX mk_messages_campaign_phone_unique
--   ON public.mk_messages (campaign_id, telefono);
-- commit;;
