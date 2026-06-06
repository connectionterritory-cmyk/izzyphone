-- ============================================================
-- 0093: Trazabilidad para importación de imágenes vía n8n
--       workflow RFN0rJZlo86HNgRj (Claude Vision → CRM)
--
-- Agrega:
--   1. clientes: fuente_import, import_file_name, import_drive_url
--   2. leads:    fuente_import, import_file_name, import_drive_url
--   3. tabla import_revisiones — registros que requieren revisión
--      manual (baja confianza, errores de parseo, fileId vacío)
--
-- Contexto de columnas existentes (no duplicar):
--   leads.run_id, file_id_origen, file_name_origen, confianza_ocr
--     → ya en 0092 (para el pipeline OCR de documentos)
--   clientes.email, credito_disponible, metodo_pago, fecha_orden,
--             fecha_cierre → ya en 0089
--   import_processed_files → ya en 0091 (tracking de archivos ya
--     procesados; diferente de import_revisiones)
--
-- Las nuevas columnas de fuente_import / import_file_name /
-- import_drive_url permiten trazabilidad de origen y filtrado
-- por canal de importación desde la UI del CRM.
--
-- ROLLBACK:
--   alter table public.clientes
--     drop column if exists fuente_import,
--     drop column if exists import_file_name,
--     drop column if exists import_drive_url;
--   alter table public.leads
--     drop column if exists fuente_import,
--     drop column if exists import_file_name,
--     drop column if exists import_drive_url;
--   drop table if exists public.import_revisiones;
-- ============================================================

begin;
-- ----------------------------------------------------------------
-- 1. clientes: columnas de trazabilidad de importación
-- ----------------------------------------------------------------
alter table public.clientes
  add column if not exists fuente_import    text,
  add column if not exists import_file_name text,
  add column if not exists import_drive_url text;
comment on column public.clientes.fuente_import    is 'Canal de importación que creó el registro (e.g. import_imagen_gdrive, csv, manual).';
comment on column public.clientes.import_file_name is 'Nombre del archivo de Drive del que proviene este registro.';
comment on column public.clientes.import_drive_url is 'URL de Google Drive del archivo fuente (webViewLink).';
-- ----------------------------------------------------------------
-- 2. leads: columnas de trazabilidad de importación
--    (no duplicar run_id/file_id_origen/file_name_origen/confianza_ocr de 0092)
-- ----------------------------------------------------------------
alter table public.leads
  add column if not exists fuente_import    text,
  add column if not exists import_file_name text,
  add column if not exists import_drive_url text;
comment on column public.leads.fuente_import    is 'Canal de importación que creó el registro (e.g. import_imagen_gdrive, csv, manual).';
comment on column public.leads.import_file_name is 'Nombre del archivo de Drive del que proviene este registro.';
comment on column public.leads.import_drive_url is 'URL de Google Drive del archivo fuente (webViewLink).';
-- ----------------------------------------------------------------
-- 3. tabla import_revisiones
--    Registros del workflow de imágenes que no pudieron clasificarse
--    automáticamente (error de parseo, baja confianza, fileId vacío).
--    Solo service_role puede escribir. La UI puede consultarla
--    con rol de admin/distribuidor para revisión manual.
-- ----------------------------------------------------------------
create table if not exists public.import_revisiones (
  id             uuid        primary key default gen_random_uuid(),

  -- Referencia al archivo fuente
  file_name      text,
  file_id        text,                          -- Drive file_id si estaba disponible
  drive_url      text,

  -- Datos crudos del ítem que falló
  raw_data       jsonb       not null default '{}',

  -- Clasificación de por qué está en revisión
  motivo         text        not null
                   check (motivo in (
                     'parse_error',      -- Claude no devolvió JSON válido
                     'baja_confianza',   -- confianza='baja' declarado por Claude
                     'fileid_vacio'      -- el archivo no tenía fileId asignable
                   )),

  -- Lo que Claude pensaba antes de mandarlo a revisión
  tipo_tentativo text
                   check (tipo_tentativo in ('lead', 'cliente')),
  confianza_ia   text
                   check (confianza_ia in ('alta', 'media', 'baja')),

  -- Estado de revisión manual
  revisado       boolean     not null default false,
  revisado_por   uuid        references public.usuarios(id) on delete set null,
  revisado_at    timestamptz,
  accion_tomada  text
                   check (accion_tomada in (
                     'creado_lead',
                     'creado_cliente',
                     'descartado',
                     'pendiente'
                   )) default 'pendiente',
  notas_revisor  text,

  created_at     timestamptz not null default now()
);
comment on table public.import_revisiones is
  'Registros del workflow n8n de importación de imágenes (RFN0rJZlo86HNgRj) '
  'que requieren revisión manual: errores de parseo, baja confianza de Claude, '
  'o fileId vacío. Diferente de import_processed_files (que rastrea archivos ya procesados).';
-- ----------------------------------------------------------------
-- RLS: service_role escribe sin restricción (desde n8n)
--       admin y distribuidor pueden leer y actualizar para revisión
-- ----------------------------------------------------------------
alter table public.import_revisiones enable row level security;
-- Admins pueden todo
create policy "admin_all_revisiones"
  on public.import_revisiones
  for all
  to authenticated
  using     (public.is_admin())
  with check (public.is_admin());
-- Distribuidores pueden ver y actualizar (para revisar manualmente)
create policy "dist_select_revisiones"
  on public.import_revisiones
  for select
  to authenticated
  using (public.is_distribuidor());
create policy "dist_update_revisiones"
  on public.import_revisiones
  for update
  to authenticated
  using     (public.is_distribuidor())
  with check (public.is_distribuidor());
-- ----------------------------------------------------------------
-- Índices para consultas frecuentes desde la UI de revisión
-- ----------------------------------------------------------------
create index if not exists import_revisiones_motivo_idx
  on public.import_revisiones (motivo);
create index if not exists import_revisiones_revisado_idx
  on public.import_revisiones (revisado)
  where revisado = false;
-- índice parcial: solo los pendientes

create index if not exists import_revisiones_created_idx
  on public.import_revisiones (created_at desc);
commit;
