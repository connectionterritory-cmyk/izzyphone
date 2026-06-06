-- ============================================================
-- 0048_supervisor_tele_reassign.sql
-- Allow supervisor_telemercadeo to update vendedor_id on
-- leads and clientes (for cita reassignment flow).
-- owner_id is never changed by this policy.
-- ============================================================

begin;
-- Helper: is current user a supervisor_telemercadeo?
create or replace function public.is_supervisor_tele()
returns boolean
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid()
      and rol = 'supervisor_telemercadeo'
  );
$$;
-- Leads: supervisor can update (reassign vendedor_id)
drop policy if exists leads_supervisor_tele_update on public.leads;
create policy leads_supervisor_tele_update on public.leads
  for update to authenticated
  using (public.is_supervisor_tele() and deleted_at is null)
  with check (public.is_supervisor_tele());
-- Clientes: supervisor can update (reassign vendedor_id)
drop policy if exists clientes_supervisor_tele_update on public.clientes;
create policy clientes_supervisor_tele_update on public.clientes
  for update to authenticated
  using (public.is_supervisor_tele())
  with check (public.is_supervisor_tele());
commit;
