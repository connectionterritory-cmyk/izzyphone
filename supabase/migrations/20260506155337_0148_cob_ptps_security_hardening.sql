begin;

-- 0148_cob_ptps_security_hardening
-- Hardening de seguridad en cob_ptps:
-- 1. FK defensiva cob_gestiones.ptp_id → cob_ptps(id) (ya existe; no-op si está presente)
-- 2. Check constraint en canal
-- 3. Reemplaza policy FOR ALL por SELECT/INSERT/UPDATE separadas
-- Sin renombres, sin tocar datos, sin tocar cob_financial_ledger.

-- 1. FK defensiva cob_gestiones.ptp_id → cob_ptps(id)
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'cob_gestiones'
      and constraint_name = 'cob_gestiones_ptp_id_fkey'
  ) then
    alter table public.cob_gestiones
      add constraint cob_gestiones_ptp_id_fkey
      foreign key (ptp_id)
      references public.cob_ptps(id)
      on delete set null;
  end if;
end $$;

-- 2. Check constraint canal (null permitido; si existe, limitar a catálogo)
alter table public.cob_ptps
  drop constraint if exists cob_ptps_canal_check;

alter table public.cob_ptps
  add constraint cob_ptps_canal_check
  check (
    canal is null
    or canal in ('telefono', 'whatsapp', 'email', 'sms', 'presencial', 'otro')
  );

-- 3. RLS: reemplazar policy FOR ALL por tres policies granulares
alter table public.cob_ptps enable row level security;

drop policy if exists cob_ptps_cartera_role       on public.cob_ptps;
drop policy if exists cob_ptps_select_cartera_role on public.cob_ptps;
drop policy if exists cob_ptps_insert_cartera_role on public.cob_ptps;
drop policy if exists cob_ptps_update_cartera_role on public.cob_ptps;

create policy cob_ptps_select_cartera_role
  on public.cob_ptps
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );

create policy cob_ptps_insert_cartera_role
  on public.cob_ptps
  for insert to authenticated
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (creado_por is null or creado_por = auth.uid())
      )
    )
  );

create policy cob_ptps_update_cartera_role
  on public.cob_ptps
  for update to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  )
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (creado_por is null or creado_por = auth.uid())
      )
    )
  );

-- Sin policy DELETE: cancelación operativa vía estado='cancelado'.

commit;;
