-- ============================================================
-- 0043_clientes_usuarios_rls_roles.sql
-- RLS hardening for clientes and usuarios based on roles
--
-- Requirements:
--   - admin: all clients in org
--   - distribuidor: all clients in org
--   - vendedor: only own clients
--   - supervisor_telemercadeo: all clients in org
--   - telemercadeo: only assigned clients
--   - telemercadeo/supervisor_telemercadeo: no org-wide usuarios access
-- ============================================================

begin;
-- -----------------------------
-- Clientes policies
-- -----------------------------
drop policy if exists clientes_org_member on public.clientes;
drop policy if exists clientes_telemercadeo_read on public.clientes;
drop policy if exists clientes_admin on public.clientes;
drop policy if exists clientes_distribuidor on public.clientes;
drop policy if exists clientes_vendedor on public.clientes;
drop policy if exists clientes_admin_all on public.clientes;
drop policy if exists clientes_distribuidor_all on public.clientes;
drop policy if exists clientes_vendedor_read on public.clientes;
drop policy if exists clientes_supervisor_telemercadeo_read on public.clientes;
create policy clientes_admin_all on public.clientes
  for all to authenticated
  using (public.is_admin() and public.is_org_member(org_id))
  with check (public.is_admin() and public.is_org_member(org_id));
create policy clientes_distribuidor_all on public.clientes
  for all to authenticated
  using (public.is_distribuidor() and public.is_org_member(org_id))
  with check (public.is_distribuidor() and public.is_org_member(org_id));
create policy clientes_vendedor_read on public.clientes
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
    and public.is_org_member(org_id)
  );
create policy clientes_supervisor_telemercadeo_read on public.clientes
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'supervisor_telemercadeo'
    )
    and public.is_org_member(org_id)
  );
create policy clientes_telemercadeo_read on public.clientes
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    and exists (
      select 1 from public.tele_vendedor_assignments t
      where t.tele_id = auth.uid()
        and (t.vendedor_id = clientes.vendedor_id or t.vendedor_id = clientes.distribuidor_id)
    )
    and public.is_org_member(org_id)
  );
-- -----------------------------
-- Usuarios policies
-- -----------------------------
drop policy if exists usuarios_read_all on public.usuarios;
drop policy if exists usuarios_self_read on public.usuarios;
drop policy if exists usuarios_org_read on public.usuarios;
create policy usuarios_self_read on public.usuarios
  for select to authenticated
  using (id = auth.uid());
create policy usuarios_org_read on public.usuarios
  for select to authenticated
  using (
    public.is_org_member(org_id)
    and exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol not in ('telemercadeo', 'supervisor_telemercadeo')
    )
  );
commit;
