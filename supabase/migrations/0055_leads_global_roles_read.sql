-- ============================================================
-- 0055_leads_global_roles_read.sql
-- Allow admin, distribuidor, and supervisor_telemercadeo to
-- SELECT all leads.
--
-- Context: leads_vendedor_all (0004) only covers owner_id = auth.uid().
-- Global roles (admin, distribuidor, supervisor_telemercadeo) had
-- no SELECT policy, so CitaModal lead search returned empty for them.
-- ============================================================

begin;
-- admin: all leads
drop policy if exists leads_admin_read on public.leads;
create policy leads_admin_read on public.leads
  for select to authenticated
  using (public.is_admin());
-- distribuidor: all leads
drop policy if exists leads_distribuidor_read on public.leads;
create policy leads_distribuidor_read on public.leads
  for select to authenticated
  using (public.is_distribuidor());
-- supervisor_telemercadeo: all leads
drop policy if exists leads_supervisor_tele_read on public.leads;
create policy leads_supervisor_tele_read on public.leads
  for select to authenticated
  using (public.is_supervisor_tele());
commit;
