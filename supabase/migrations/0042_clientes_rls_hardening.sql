-- ============================================================
-- 0042_clientes_rls_hardening.sql
-- Hardening RLS en clientes: de org-level a role-level
--
-- Antes: clientes_org_member (FOR ALL, USING is_org_member(org_id))
--        → cualquier miembro de la org podía leer clientes de otros vendedores
--
-- Después:
--   • admin        → todo
--   • distribuidor → sus clientes directos + los de su equipo
--   • vendedor     → solo sus propios clientes
--   • telemercadeo → solo clientes del vendedor asignado (SELECT)
-- ============================================================

begin;
-- 1. Eliminar políticas antiguas
drop policy if exists clientes_org_member        on public.clientes;
drop policy if exists clientes_telemercadeo_read on public.clientes;
-- 2. Admin: acceso total
create policy clientes_admin on public.clientes
  for all to authenticated
  using      (public.is_admin())
  with check (public.is_admin());
-- 3. Distribuidor: clientes propios + clientes del equipo
--    distribuidor_id = auth.uid()  → cliente asignado directamente al distribuidor
--    is_distribuidor_of(vendedor_id) → el vendedor pertenece a este distribuidor
create policy clientes_distribuidor on public.clientes
  for all to authenticated
  using (
    public.is_distribuidor()
    and (
      distribuidor_id = auth.uid()
      or public.is_distribuidor_of(vendedor_id)
    )
  )
  with check (
    public.is_distribuidor()
    and (
      distribuidor_id = auth.uid()
      or public.is_distribuidor_of(vendedor_id)
    )
  );
-- 4. Vendedor: solo sus propios clientes
create policy clientes_vendedor on public.clientes
  for all to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
  )
  with check (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
  );
-- 5. Telemercadeo: SELECT solo de clientes del vendedor asignado
create policy clientes_telemercadeo_read on public.clientes
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios
      where id = auth.uid() and rol = 'telemercadeo'
    )
    and exists (
      select 1 from public.tele_vendedor_assignments t
      where t.tele_id = auth.uid()
        and t.vendedor_id = clientes.vendedor_id
    )
  );
commit;
