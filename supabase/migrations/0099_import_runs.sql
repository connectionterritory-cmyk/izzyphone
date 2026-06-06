-- ============================================================
-- 0099: Tabla import_runs — tracking de ejecuciones n8n
--
-- Problema que resuelve:
--   n8n marca execution=error si cualquier nodo falla, pero los
--   inserts en Supabase ya se hicieron. Sin esta tabla no hay forma
--   de distinguir "falló sin insertar nada" de "insertó pero Marcar
--   C/L tiró Bad Request". Ver ejecuciones 9273, 9279, 9284, 9289.
--
-- Contexto:
--   import_processed_files → tracking por archivo (file_id)
--   import_revisiones      → datos sin clasificar para revisión manual
--   import_runs            → resumen por ejecución n8n (este archivo)
--
-- El workflow n8n escribe aquí al inicio (status='running') y al
-- final actualiza con conteos y status final.
--
-- ROLLBACK:
--   drop table if exists public.import_runs;
-- ============================================================

begin;
create table if not exists public.import_runs (
  run_id        text        primary key,   -- execution ID de n8n
  org_id        uuid,   -- UUID del tenant; sin FK (igual que import_processed_files y import_revisiones)

  status        text        not null default 'running'
                              check (status in ('running', 'ok', 'partial', 'error')),

  -- Conteos finales (el workflow los escribe al terminar)
  total         int         not null default 0,   -- archivos procesados en el run
  ok            int         not null default 0,   -- insertados cliente+lead sin error
  parcial       int         not null default 0,   -- insertado pero Marcar C/L falló
  en_revision   int         not null default 0,   -- enviados a import_revisiones

  started_at    timestamptz,
  finished_at   timestamptz,

  created_at    timestamptz not null default now()
);
comment on table public.import_runs is
  'Resumen por ejecución del workflow n8n OCR (run_id = n8n execution ID). '
  'status=partial significa que hubo inserts en clientes/leads pero Marcar C/L '
  'falló (Bad Request por file_id ya existente). '
  'Diferente de import_processed_files (por archivo) e import_revisiones (por dato).';
comment on column public.import_runs.parcial is
  'Registros donde el insert a clientes/leads fue OK pero el upsert a '
  'import_processed_files falló. Indica re-procesamiento parcial.';
-- RLS: service_role escribe desde n8n sin restricción.
--      admin puede leer para auditoría.
alter table public.import_runs enable row level security;
create policy "admin_all_import_runs"
  on public.import_runs
  for all
  to authenticated
  using     (public.is_admin())
  with check (public.is_admin());
-- Índice para consultas por org + fecha
create index if not exists import_runs_org_created_idx
  on public.import_runs (org_id, created_at desc);
-- Índice para filtrar runs con errores parciales
create index if not exists import_runs_status_idx
  on public.import_runs (status)
  where status in ('partial', 'error');
commit;
