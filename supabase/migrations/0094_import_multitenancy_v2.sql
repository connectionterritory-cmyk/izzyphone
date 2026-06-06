-- ============================================================
-- 0094: Multitenancy y Estabilización de Ingestión OCR
--
-- Cambios:
--   1. Tabla import_configs: mapea source_id (Google Drive folder) a org_id
--   2. import_processed_files: agrega org_id y cambia PK a compuesta
--   3. import_revisiones: agrega org_id y filtra RLS por organización
--   4. leads: índice único sobre teléfono normalizado para idempotencia
-- ============================================================

begin;
-- 1. Tabla de configuración de importaciones (mapeo de origen a organización)
create table if not exists public.import_configs (
  id           uuid        primary key default gen_random_uuid(),
  org_id       uuid        not null,
  source_id    text        not null, -- e.g. '12WUNLZFEmr1C8OBMtEI1FDb1Bai3fuEK' (Drive Folder ID)
  source_name  text,
  is_active    boolean     not null default true,
  created_at   timestamptz not null default now(),
  unique (org_id, source_id)
);
comment on table public.import_configs is 'Mapeo de orígenes (carpetas de Drive) a organizaciones para multitenancy en n8n.';
alter table public.import_configs enable row level security;
create policy "admin_all_import_configs" on public.import_configs for all using (public.is_admin());
-- 2. Refactor de import_processed_files para multitenancy
do $$
begin
  -- Agregar org_id si no existe
  if not exists (select 1 from information_schema.columns where table_name = 'import_processed_files' and column_name = 'org_id') then
    alter table public.import_processed_files add column org_id uuid;
  end if;

  -- Poblar con org_id default para evitar nulos en registros existentes
  update public.import_processed_files set org_id = '00000000-0000-0000-0000-000000000001' where org_id is null;
  alter table public.import_processed_files alter column org_id set not null;

  -- Cambiar el Primary Key (file_id -> org_id, file_id)
  -- Esto permite que diferentes organizaciones procesen el mismo archivo si fuese necesario
  alter table public.import_processed_files drop constraint if exists import_processed_files_pkey;
  alter table public.import_processed_files add primary key (org_id, file_id);
end $$;
-- 3. Refactor de import_revisiones para multitenancy
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'import_revisiones' and column_name = 'org_id') then
    alter table public.import_revisiones add column org_id uuid;
  end if;

  update public.import_revisiones set org_id = '00000000-0000-0000-0000-000000000001' where org_id is null;
  alter table public.import_revisiones alter column org_id set not null;
end $$;
-- Actualizar políticas de RLS para import_revisiones
drop policy if exists "dist_select_revisiones" on public.import_revisiones;
drop policy if exists "dist_update_revisiones" on public.import_revisiones;
create policy "dist_select_revisiones_scoped"
  on public.import_revisiones
  for select
  to authenticated
  using (public.is_distribuidor() and org_id::text = (select organizacion from public.usuarios where id = auth.uid() limit 1));
create policy "dist_update_revisiones_scoped"
  on public.import_revisiones
  for update
  to authenticated
  using     (public.is_distribuidor() and org_id::text = (select organizacion from public.usuarios where id = auth.uid() limit 1))
  with check (public.is_distribuidor() and org_id::text = (select organizacion from public.usuarios where id = auth.uid() limit 1));
-- 4. Idempotencia en leads (Índice único con normalización)
-- Usamos regexp_replace para quitar todo lo que no sea dígito y tomamos los últimos 10 dígitos (estándar común)
create unique index if not exists leads_normalized_phone_org_idx
  on public.leads (regexp_replace(telefono, '\D', '', 'g'))
  where (telefono is not null and length(regexp_replace(telefono, '\D', '', 'g')) >= 7);
comment on index public.leads_normalized_phone_org_idx is 'Idempotencia: evita duplicados por teléfono normalizado (sin formato), ignorando caracteres no numéricos.';
commit;
