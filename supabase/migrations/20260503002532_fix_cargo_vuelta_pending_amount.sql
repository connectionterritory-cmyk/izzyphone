
create or replace function public.fn_abrir_o_actualizar_cargo_vuelta_case(
  p_cliente_id           uuid,
  p_monto_cargo_vuelta   numeric          default null,
  p_fecha_cargo_vuelta   date             default null,
  p_dias_vencido         integer          default null,
  p_numero_cuenta_hycite text             default null,
  p_numero_orden_hycite  text             default null,
  p_notas                text             default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id         uuid;
  v_org_id          uuid;
  v_user_role       text;
  v_case_id         uuid;
  v_has_ledger      boolean;
  v_existing_monto  numeric(12,2);
  v_monto           numeric(12,2);
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select u.org_id, u.rol
    into v_org_id, v_user_role
  from public.usuarios u
  where u.id = v_user_id
  limit 1;

  if v_org_id is null then
    raise exception 'Usuario sin org_id';
  end if;

  if not (
    v_user_role in ('admin', 'distribuidor', 'supervisor_tele')
    or public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
  ) then
    raise exception 'Sin permisos para gestionar casos de cargo de vuelta. Rol requerido: admin, distribuidor o supervisor_tele';
  end if;

  if not exists (
    select 1
    from public.clientes
    where id = p_cliente_id
      and org_id = v_org_id
  ) then
    raise exception 'Cliente no encontrado o no pertenece a su organización';
  end if;

  select cv.id, cv.monto_devuelto
    into v_case_id, v_existing_monto
  from public.cargo_vuelta_cases cv
  where cv.org_id = v_org_id
    and cv.cliente_id = p_cliente_id
    and cv.estado is distinct from 'Cerrado'
  order by cv.updated_at desc, cv.created_at desc
  limit 1;

  v_monto := case
    when p_monto_cargo_vuelta is not null and p_monto_cargo_vuelta > 0
    then p_monto_cargo_vuelta::numeric(12,2)
    else null
  end;

  if v_case_id is not null and v_monto is not null and v_existing_monto is not null
     and abs(v_monto - v_existing_monto) > 0.01
  then
    select exists(
      select 1
      from public.cob_revolving_accounts ra
      join public.cob_financial_ledger fl on fl.revolving_account_id = ra.id
      where ra.case_id = v_case_id
        and ra.org_id = v_org_id
      limit 1
    ) into v_has_ledger;

    if v_has_ledger then
      raise exception
        'El caso tiene una cuenta revolving con movimientos de ledger. No se puede cambiar el monto cargo de vuelta de % a % automáticamente. Realiza el ajuste manualmente desde el detalle del caso.',
        v_existing_monto, v_monto;
    end if;
  end if;

  if v_case_id is null then
    insert into public.cargo_vuelta_cases (
      org_id,
      cliente_id,
      tipo_caso,
      origen_cargo_vuelta,
      estado,
      fecha_apertura,
      fecha_cargo_vuelta,
      monto_devuelto,
      monto_total,
      dias_vencido,
      numero_cuenta_hycite,
      numero_orden_hycite,
      requiere_reconciliacion,
      updated_by
    ) values (
      v_org_id,
      p_cliente_id,
      'cargo_vuelta',
      'hycite',
      'Abierto',
      now(),
      p_fecha_cargo_vuelta,
      v_monto,
      coalesce(v_monto, 0),
      coalesce(p_dias_vencido, 0),
      p_numero_cuenta_hycite,
      p_numero_orden_hycite,
      case when v_monto is null or v_monto = 0 then true else false end,
      v_user_id
    )
    returning id into v_case_id;

    if p_notas is not null and trim(p_notas) <> '' then
      insert into public.cob_gestiones (
        org_id, cliente_id, case_id,
        tipo_gestion, resultado, notas,
        gestionado_por
      ) values (
        v_org_id, p_cliente_id, v_case_id,
        'Nota', 'cargo_vuelta_apertura', p_notas,
        v_user_id
      );
    end if;
  else
    update public.cargo_vuelta_cases
    set
      fecha_cargo_vuelta = coalesce(p_fecha_cargo_vuelta, fecha_cargo_vuelta),
      dias_vencido = coalesce(p_dias_vencido, dias_vencido),
      numero_cuenta_hycite = coalesce(p_numero_cuenta_hycite, numero_cuenta_hycite),
      numero_orden_hycite = coalesce(p_numero_orden_hycite, numero_orden_hycite),
      monto_devuelto = case when v_monto is not null then v_monto else monto_devuelto end,
      monto_total = case when v_monto is not null then v_monto else monto_total end,
      requiere_reconciliacion = case
        when v_monto is not null and v_monto > 0 then false
        else requiere_reconciliacion
      end,
      updated_by = v_user_id,
      updated_at = now()
    where id = v_case_id;

    if p_notas is not null and trim(p_notas) <> '' then
      insert into public.cob_gestiones (
        org_id, cliente_id, case_id,
        tipo_gestion, resultado, notas,
        gestionado_por
      ) values (
        v_org_id, p_cliente_id, v_case_id,
        'Nota', 'cargo_vuelta_actualizacion', p_notas,
        v_user_id
      );
    end if;
  end if;

  return v_case_id;
end;
$$;

revoke all on function public.fn_abrir_o_actualizar_cargo_vuelta_case(uuid, numeric, date, integer, text, text, text) from public;
revoke execute on function public.fn_abrir_o_actualizar_cargo_vuelta_case(uuid, numeric, date, integer, text, text, text) from anon;
grant execute on function public.fn_abrir_o_actualizar_cargo_vuelta_case(uuid, numeric, date, integer, text, text, text) to authenticated;

comment on function public.fn_abrir_o_actualizar_cargo_vuelta_case(uuid, numeric, date, integer, text, text, text) is
  'Abre o actualiza un caso de cargo de vuelta para un cliente. '
  'El monto_cargo_vuelta se guarda en monto_devuelto; si falta monto, crea caso pendiente con monto_total=0 por compatibilidad legacy. '
  'Si hay cuenta revolving con ledger no cambia el monto. '
  'Roles permitidos: admin, distribuidor, supervisor_tele.';
;
