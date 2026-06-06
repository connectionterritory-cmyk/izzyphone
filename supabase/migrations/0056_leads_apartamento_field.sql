-- ============================================================
-- 0056_leads_apartamento_field.sql
-- Add apartamento column to leads table.
--
-- Context: CalificacionPanel already exposes an Apt / Suite field
-- for leads. Without this column, the lead detail query falls back
-- to a reduced select and address edits cannot round-trip.
-- ============================================================

begin;
alter table public.leads
  add column if not exists apartamento text;
commit;
