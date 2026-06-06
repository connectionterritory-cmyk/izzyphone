-- ============================================================
-- 0092: Deduplicación de leads por teléfono + columnas de
--       trazabilidad OCR para el pipeline n8n
--
-- La tabla leads no tiene org_id (usa owner_id). El índice
-- único se crea sobre telefono solamente (instalación
-- single-org) y excluye nulos y soft-deleted.
--
-- Columnas nuevas:
--   run_id          — ID de ejecución n8n para trazabilidad
--   file_id_origen  — Drive file_id del archivo fuente
--   file_name_origen — Nombre del archivo fuente
--   confianza_ocr   — Nivel de confianza dado por Claude
--
-- ROLLBACK:
--   drop index if exists public.leads_telefono_uidx;
--   alter table public.leads
--     drop column if exists run_id,
--     drop column if exists file_id_origen,
--     drop column if exists file_name_origen,
--     drop column if exists confianza_ocr;
-- ============================================================

begin;
-- Columnas de trazabilidad para importaciones OCR
alter table public.leads
  add column if not exists run_id           text,
  add column if not exists file_id_origen   text,
  add column if not exists file_name_origen text,
  add column if not exists confianza_ocr    text;
-- Índice único parcial en telefono para PostgREST
-- resolution=merge-duplicates
create unique index if not exists leads_telefono_uidx
  on public.leads (telefono)
  where telefono is not null
    and deleted_at is null;
comment on index public.leads_telefono_uidx is
  'Permite PostgREST upsert con resolution=merge-duplicates '
  'usando telefono como clave de deduplicación OCR.';
commit;
