-- Migration 0063: Schema para workflow MK - Recordatorio de Citas
-- 1. segmento_key nullable en mk_campaigns (para upserts automáticos sin segmento)
-- 2. UNIQUE(nombre) en mk_campaigns (para ON CONFLICT en workflow n8n)
-- 3. cita_id en mk_messages (FK a citas)
-- 4. Agrega 'usuario' al check de contacto_tipo en mk_messages (para mensajes a vendedores)
-- Tipo: alter_table (non-breaking, aditivo)
-- Prerequisito: 0062

begin;
-- 1. segmento_key: NOT NULL → nullable
ALTER TABLE public.mk_campaigns
  ALTER COLUMN segmento_key DROP NOT NULL;
-- 2. UNIQUE constraint en nombre (requerido para ON CONFLICT en workflow n8n)
ALTER TABLE public.mk_campaigns
  DROP CONSTRAINT IF EXISTS mk_campaigns_nombre_key;
ALTER TABLE public.mk_campaigns
  ADD CONSTRAINT mk_campaigns_nombre_key UNIQUE (nombre);
-- 3. cita_id en mk_messages → FK a citas (nullable, SET NULL al borrar)
ALTER TABLE public.mk_messages
  ADD COLUMN IF NOT EXISTS cita_id uuid
  REFERENCES public.citas(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS mk_messages_cita_id_idx
  ON public.mk_messages (cita_id)
  WHERE cita_id IS NOT NULL;
-- 4. Ampliar check de contacto_tipo para incluir 'usuario' (vendedor/asignado)
ALTER TABLE public.mk_messages
  DROP CONSTRAINT IF EXISTS mk_messages_contacto_tipo_check;
ALTER TABLE public.mk_messages
  ADD CONSTRAINT mk_messages_contacto_tipo_check
  CHECK (contacto_tipo IN ('cliente', 'lead', 'ci_referido', '4en14_referido', 'usuario'));
commit;
-- ROLLBACK:
-- begin;
-- ALTER TABLE public.mk_messages DROP CONSTRAINT IF EXISTS mk_messages_contacto_tipo_check;
-- ALTER TABLE public.mk_messages ADD CONSTRAINT mk_messages_contacto_tipo_check CHECK (contacto_tipo IN ('cliente', 'lead', 'ci_referido', '4en14_referido'));
-- ALTER TABLE public.mk_messages DROP COLUMN IF EXISTS cita_id;
-- ALTER TABLE public.mk_campaigns DROP CONSTRAINT IF EXISTS mk_campaigns_nombre_key;
-- ALTER TABLE public.mk_campaigns ALTER COLUMN segmento_key SET NOT NULL;
-- commit;;
