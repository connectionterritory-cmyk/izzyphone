-- ============================================================
-- 0054_leads_address_fields.sql
-- Add address columns to leads table.
--
-- Context: leads had no address fields in the live DB. CitaModal
-- already stores direccion/ciudad/estado_region/zip on citas, and
-- CalificacionPanel has UI for address fields but they were silently
-- failing because the columns didn't exist.
-- ============================================================

begin;
alter table public.leads
  add column if not exists direccion     text,
  add column if not exists ciudad        text,
  add column if not exists estado_region text,
  add column if not exists codigo_postal text;
commit;
