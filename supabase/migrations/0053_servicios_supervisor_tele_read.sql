-- ============================================================
-- 0053_servicios_supervisor_tele_read.sql
-- Allow supervisor_telemercadeo to read all servicios.
--
-- Context: the live DB has no org_id on public.servicios, so the
-- supervisor scope must follow the same role-based pattern already
-- used by citas_supervisor_tele_read.
-- ============================================================

begin;
drop policy if exists servicios_supervisor_tele_read on public.servicios;
create policy servicios_supervisor_tele_read on public.servicios
  for select to authenticated
  using (public.is_supervisor_tele());
commit;
