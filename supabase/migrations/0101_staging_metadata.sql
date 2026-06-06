-- ============================================================
-- 0101: Metadatos de trazabilidad en clientes_rp
--
-- Añade org_id, source_id, file_id, run_id para vincular cada
-- registro de staging con su organización, carpeta Drive,
-- archivo individual y ejecución n8n.
--
-- ROLLBACK:
--   alter table public.clientes_rp
--     drop column if exists org_id,
--     drop column if exists source_id,
--     drop column if exists file_id,
--     drop column if exists run_id,
--     drop column if exists apellido;
-- ============================================================

begin;
alter table public.clientes_rp
  add column if not exists org_id    uuid,
  add column if not exists source_id text,
  add column if not exists file_id   text,
  add column if not exists run_id    text,
  add column if not exists apellido  text;
comment on column public.clientes_rp.org_id    is 'Organización propietaria (de import_configs.org_id).';
comment on column public.clientes_rp.source_id is 'Carpeta Drive de origen (import_configs.source_id).';
comment on column public.clientes_rp.file_id   is 'ID del archivo en Google Drive.';
comment on column public.clientes_rp.run_id    is 'ID de ejecución n8n (trazabilidad).';
comment on column public.clientes_rp.apellido  is 'Apellido(s) del cliente. Puede ser heurístico si el OCR entregó nombre completo en el campo nombre.';
commit;
