-- ============================================================
-- 0114: abrir o recuperar caso de cartera desde cliente
--
-- Objetivo:
--   Formalizar un punto backend para recuperar un caso activo de
--   cartera o abrir uno nuevo desde un cliente del mismo tenant.
--
-- Alcance:
--   - NO modifica clientes.saldo_actual
--   - NO toca pagos, PTPs ni planes
--   - NO toca llamadas_telemercadeo
--   - NO abre casos automaticamente por trigger
-- ============================================================

begin;
create index if not exists cargo_vuelta_cases_org_cliente_estado_updated_idx
  on public.cargo_vuelta_cases (org_id, cliente_id, estado, updated_at desc);
create index if not exists cob_gestiones_org_case_created_at_idx
  on public.cob_gestiones (org_id, case_id, created_at desc)
  where case_id is not null;
drop function if exists public.fn_abrir_o_recuperar_caso_cartera(uuid, numeric, integer);
create or replace function public.fn_abrir_o_recuperar_caso_cartera(
  p_cliente_id uuid,
  p_monto_total numeric default null,
  p_dias_vencido integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_user_org_id uuid;
  v_user_role text;
  v_case_id uuid;
  v_cliente_monto_moroso numeric(12,2);
  v_cliente_dias_atraso integer;
  v_monto_total numeric(12,2);
  v_dias_vencido integer;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select u.org_id, u.rol
    into v_user_org_id, v_user_role
  from public.usuarios u
  where u.id = v_user_id
  limit 1;

  if v_user_org_id is null then
    raise exception 'Usuario sin org_id en public.usuarios';
  end if;

  if not (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or v_user_role = 'telemercadeo'
  ) then
    raise exception 'Usuario sin permisos para abrir casos de cartera';
  end if;

  select c.monto_moroso, c.dias_atraso
    into v_cliente_monto_moroso, v_cliente_dias_atraso
  from public.clientes c
  where c.id = p_cliente_id
    and c.org_id = v_user_org_id
  for update;

  if not found then
    raise exception 'Cliente no encontrado o no pertenece a su organización';
  end if;

  select cv.id
    into v_case_id
  from public.cargo_vuelta_cases cv
  where cv.org_id = v_user_org_id
    and cv.cliente_id = p_cliente_id
    and cv.estado is distinct from 'Cerrado'
  order by cv.updated_at desc, cv.created_at desc
  limit 1;

  if v_case_id is not null then
    return v_case_id;
  end if;

  v_monto_total := coalesce(p_monto_total, v_cliente_monto_moroso, 0)::numeric(12,2);
  v_dias_vencido := coalesce(p_dias_vencido, v_cliente_dias_atraso, 0);

  insert into public.cargo_vuelta_cases (
    org_id,
    cliente_id,
    monto_total,
    dias_vencido,
    estado,
    fecha_apertura,
    updated_by
  ) values (
    v_user_org_id,
    p_cliente_id,
    v_monto_total,
    v_dias_vencido,
    'Abierto',
    now(),
    v_user_id
  )
  returning id into v_case_id;

  return v_case_id;
end;
$$;
revoke all on function public.fn_abrir_o_recuperar_caso_cartera(uuid, numeric, integer) from public;
revoke execute on function public.fn_abrir_o_recuperar_caso_cartera(uuid, numeric, integer) from anon;
grant execute on function public.fn_abrir_o_recuperar_caso_cartera(uuid, numeric, integer) to authenticated;
comment on function public.fn_abrir_o_recuperar_caso_cartera(uuid, numeric, integer) is
  'Recupera un caso activo de cartera para un cliente o crea uno nuevo dentro del org_id del usuario autenticado.';
commit;
