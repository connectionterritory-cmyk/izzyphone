-- ============================================================
-- 0047_leads_distribuidor_select.sql
-- La tabla leads no tenía política SELECT para distribuidores
-- (solo UPDATE via leads_distribuidor_update).
-- Esto hacía que Oportunidades mostrara 0 datos en modo distribuidor.
-- ============================================================

begin;
create policy leads_distribuidor_select on public.leads
  for select to authenticated
  using (
    public.is_distribuidor()
    and deleted_at is null
  );
commit;
