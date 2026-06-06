-- ============================================================
-- 0124: RLS hardening — módulo DFP Revolving
--
-- Objetivo:
--   Hardening quirúrgico. Un solo hueco crítico resuelto y
--   limpieza defensiva de permisos. Sin tocar lógica financiera.
--
-- Cambios:
--   1. Revocar grants de anon en tablas y vista DFP
--   2. Reemplazar cargo_vuelta_cases_cartera_role (sin org_id)
--      por 3 policies separadas por comando con org_id en USING
--   3. Comentarios de seguridad actualizados
--
-- Conservado sin cambios:
--   - cob_financial_ledger_no_direct_write
--   - cob_financial_ledger_read
--   - cob_revolving_accounts_cartera_role
--
-- Sin FORCE RLS. Sin cambios a lógica financiera. Sin nuevas tablas.
--
-- ROLLBACK:
--   drop policy if exists cargo_vuelta_cases_cartera_select on public.cargo_vuelta_cases;
--   drop policy if exists cargo_vuelta_cases_cartera_insert on public.cargo_vuelta_cases;
--   drop policy if exists cargo_vuelta_cases_cartera_update on public.cargo_vuelta_cases;
--   create policy cargo_vuelta_cases_cartera_role on public.cargo_vuelta_cases
--     for all to authenticated
--     using (public.is_admin_or_distribuidor() or public.is_supervisor_tele()
--            or security.current_user_role() = 'telemercadeo')
--     with check (public.is_admin_or_distribuidor() or public.is_supervisor_tele()
--                 or security.current_user_role() = 'telemercadeo');
-- ============================================================

begin;

-- ── 1. Claridad defensiva: revocar grants directos de anon ────────
-- anon está bloqueado por RLS al no tener policies permisivas.
-- Revocar explícitamente elimina la apariencia de acceso y sigue
-- el mismo patrón aplicado a las RPCs en 0122.

revoke all on table public.cargo_vuelta_cases    from anon;
revoke all on table public.cob_revolving_accounts from anon;
revoke all on table public.cob_financial_ledger   from anon;
revoke all on table public.v_dfp_caso_resumen     from anon;

-- ── 2. Reemplazar policy vulnerable de cargo_vuelta_cases ─────────
-- Hueco crítico: la policy anterior usaba solo comprobación de rol
-- sin filtrar por org_id. Un usuario de org A con rol correcto
-- podía leer y escribir casos de org B.

drop policy if exists cargo_vuelta_cases_cartera_role on public.cargo_vuelta_cases;

-- Lectura: roles de cartera de la misma organización
create policy cargo_vuelta_cases_cartera_select
  on public.cargo_vuelta_cases
  for select to authenticated
  using (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or exists (
        select 1 from public.usuarios u
        where u.id = auth.uid() and u.rol = 'telemercadeo'
      )
    )
  );

-- INSERT: solo admin/distribuidor/supervisor de la misma org
create policy cargo_vuelta_cases_cartera_insert
  on public.cargo_vuelta_cases
  for insert to authenticated
  with check (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
    )
  );

-- UPDATE: solo admin/distribuidor/supervisor de la misma org
create policy cargo_vuelta_cases_cartera_update
  on public.cargo_vuelta_cases
  for update to authenticated
  using (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
    )
  )
  with check (
    org_id = (
      select u.org_id from public.usuarios u
      where u.id = auth.uid() limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
    )
  );

-- Sin DELETE policy: ningún usuario autenticado puede borrar casos.

-- ── 3. Comentarios de seguridad ───────────────────────────────────

comment on table public.cargo_vuelta_cases is
  'Caso operativo Cargo de Vuelta / DFP. '
  'RLS restringido por org_id. '
  'Lectura: roles de cartera de la misma organización. '
  'INSERT/UPDATE: solo admin/distribuidor/supervisor_tele de la misma organización. '
  'DELETE no permitido por policy (sin policy = denegado). '
  'telemercadeo puede leer casos de su org pero no crear ni modificar.';

comment on table public.cob_revolving_accounts is
  'Cuenta financiera interna DFP Revolving. '
  'RLS restringido por org_id (0118). '
  'Lectura: roles de cartera de la misma organización. '
  'Mutaciones financieras deben pasar por RPCs SECURITY DEFINER (0122+). '
  'anon sin grant directo desde 0124.';

comment on table public.cob_financial_ledger is
  'Ledger financiero DFP Revolving — append-only e inmutable. '
  'RLS restringido por org_id (0119/0120). '
  'Lectura: roles de cartera de la misma organización. '
  'INSERT directo bloqueado por policy WITH CHECK (false). '
  'UPDATE/DELETE denegados (sin policy permisiva). '
  'Movimientos financieros exclusivamente vía RPCs SECURITY DEFINER (0122+). '
  'anon sin grant directo desde 0124.';

commit;
;
