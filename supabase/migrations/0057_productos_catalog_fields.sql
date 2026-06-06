-- ============================================================
-- 0057_productos_catalog_fields.sql
-- Add catalog/detail columns to productos that were missing
-- from the base table (only existed in v_catalogo_vendedor view).
-- All use IF NOT EXISTS — safe to run even if some already exist.
-- ============================================================

begin;
alter table public.productos
  add column if not exists estado text
    check (estado in ('activo', 'borrador', 'descontinuado', 'reemplazado'))
    default 'activo',
  add column if not exists descripcion_corta text,
  add column if not exists descripcion_larga text,
  add column if not exists beneficios text[],
  add column if not exists cuota_minima numeric,
  add column if not exists con_financiamiento boolean not null default false;
commit;
