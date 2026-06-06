-- 0143: add resultado to contacto_actividades
--
-- Bug:
-- trg_sync_cliente_estado_operativo_from_contacto_actividades references
-- NEW.resultado, but contacto_actividades did not have that column.
-- This crashed INSERTs into contacto_actividades, including activity logs
-- created from outbox_messages.
--
-- Fix:
-- Add resultado as nullable text.
-- Existing inserts that do not set resultado will store null, so trigger
-- conditions should not match and will behave as no-op.
--
-- Rollback:
-- alter table public.contacto_actividades drop column if exists resultado;

alter table public.contacto_actividades
  add column if not exists resultado text;

comment on column public.contacto_actividades.resultado is
  'Resultado de la actividad: promesa_pago, pago_realizado, no_contesto, etc. Usado por triggers de sincronización de estado operativo del cliente.';
;
