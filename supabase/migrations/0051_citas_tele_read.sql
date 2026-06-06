-- ============================================================
-- 0051_citas_tele_read.sql
-- Allow telemercadeo and supervisor_telemercadeo to SELECT
-- citas of their assigned vendors (via tele_vendedor_assignments).
-- This enables the reconfirmation workflow.
-- ============================================================

begin;
-- telemercadeo: ve citas donde el owner o asignado es uno de sus vendedores
drop policy if exists citas_tele_read on public.citas;
create policy citas_tele_read on public.citas
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol = 'telemercadeo'
    )
    and exists (
      select 1 from public.tele_vendedor_assignments tva
      where tva.tele_id = auth.uid()
        and (
          tva.vendedor_id = citas.owner_id
          or tva.vendedor_id = citas.assigned_to
        )
    )
  );
-- supervisor_telemercadeo: ve todas las citas (mismo scope que admin/distribuidor)
drop policy if exists citas_supervisor_tele_read on public.citas;
create policy citas_supervisor_tele_read on public.citas
  for select to authenticated
  using (public.is_supervisor_tele());
commit;
