-- ============================================================
-- 0097: Agrega run_id a import_revisiones
--
-- Necesario para que Marcar R pueda usar return=representation
-- en Supabase - Rev Manual y leer $json.run_id directamente,
-- eliminando toda dependencia de cross-node item pairing.
--
-- ROLLBACK:
--   alter table public.import_revisiones drop column if exists run_id;
-- ============================================================

begin;
alter table public.import_revisiones
  add column if not exists run_id text;
comment on column public.import_revisiones.run_id
  is 'ID de ejecución n8n que generó este registro (trazabilidad).';
commit;
