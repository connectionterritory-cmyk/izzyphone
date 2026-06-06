-- ============================================================
-- 0087: RLS minimo para cartera (cob_gestiones, cargo_vuelta_cases)
-- ============================================================
-- Restringe acceso por rol sin abrir a toda la org.
-- usuario_rol enum actual: admin | distribuidor | vendedor | telemercadeo | embajador
-- 'cobrador' y 'supervisor_telemercadeo' no existen aún en el enum.
-- Se usa u.rol::text para comparación segura — valores futuros no rompen en runtime,
-- simplemente no hacen match hasta que se agreguen al enum (ALTER TYPE ... ADD VALUE).

-- NOTA: helpers disponibles en producción:
--   public.is_admin_or_distribuidor()
--   public.is_supervisor_tele()
--   security.current_user_role() → text
-- is_org_member() NO existe en producción.

begin;
drop policy if exists cob_gestiones_org_member on public.cob_gestiones;
drop policy if exists cargo_vuelta_cases_org_member on public.cargo_vuelta_cases;
drop policy if exists cob_gestiones_cartera_role on public.cob_gestiones;
drop policy if exists cargo_vuelta_cases_cartera_role on public.cargo_vuelta_cases;
-- cob_gestiones: admin/distribuidor/supervisor_tele ven todo
-- telemercadeo: lee todo, escribe solo sus propias gestiones (gestionado_por)
create policy cob_gestiones_cartera_role
  on public.cob_gestiones
  for all to authenticated
  using (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  )
  with check (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or (
      security.current_user_role() = 'telemercadeo'
      and (gestionado_por is null or gestionado_por = auth.uid())
    )
  );
-- cargo_vuelta_cases: mismo patrón de acceso
create policy cargo_vuelta_cases_cartera_role
  on public.cargo_vuelta_cases
  for all to authenticated
  using (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  )
  with check (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  );
commit;
