-- ============================================================
-- 0091: Tabla import_processed_files
--       Registro de archivos ya procesados por el workflow
--       n8n "IMPORT - OCR Prospectos". Evita reprocesar en
--       cada ejecución del trigger manual.
--
-- ROLLBACK:
--   drop table if exists public.import_processed_files;
-- ============================================================

begin;
create table if not exists public.import_processed_files (
  file_id      text        primary key,
  run_id       text,
  destino      text        check (destino in ('cliente','lead','revision')),
  processed_at timestamptz not null default now()
);
-- Solo service_role puede leer/escribir; no se expone a usuarios de app
alter table public.import_processed_files enable row level security;
comment on table public.import_processed_files is
  'Registro de Drive file_ids ya procesados por el pipeline OCR de n8n. '
  'Permite skip de archivos ya procesados sin reprocesar en cada ejecución.';
commit;
