-- ============================================================
-- 0108: fn_registrar_pago() - registro atomico de pagos
--
-- Objetivo:
--   Hacer atomico el flujo operativo de registrar un pago:
--   1. INSERT en cob_pagos
--   2. UPDATE opcional de cob_ptps a cumplido
--   3. UPDATE opcional de cob_plan_cuotas a pagada
--
-- Beneficio:
--   Evita estados inconsistentes donde el pago existe pero el PTP
--   o las cuotas seleccionadas no quedaron actualizadas.
--
-- No incluye:
--   - cambio automatico de estado del caso
--   - cambio automatico de estado del plan a completado
-- ============================================================

begin;
drop function if exists public.fn_registrar_pago(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  uuid,
  uuid[]
);
create or replace function public.fn_registrar_pago(
  p_org_id uuid,
  p_cliente_id uuid,
  p_case_id uuid,
  p_monto numeric,
  p_fecha_pago date,
  p_metodo_pago text default null,
  p_referencia text default null,
  p_notas text default null,
  p_ptp_id uuid default null,
  p_cuota_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_user_org_id uuid;
  v_pago_id uuid;
  v_cuota_count integer := 0;
  v_updated_cuotas integer := 0;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select u.org_id
  into v_user_org_id
  from public.usuarios u
  where u.id = v_user_id
  limit 1;

  if v_user_org_id is null then
    raise exception 'Usuario sin org_id en public.usuarios';
  end if;

  if p_org_id is distinct from v_user_org_id then
    raise exception 'org_id invalido para el usuario actual';
  end if;

  if not (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  ) then
    raise exception 'Usuario sin permisos para registrar pagos';
  end if;

  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a 0';
  end if;

  if p_fecha_pago is null then
    raise exception 'La fecha de pago es obligatoria';
  end if;

  if not exists (
    select 1
    from public.clientes c
    where c.id = p_cliente_id
      and c.org_id = p_org_id
  ) then
    raise exception 'Cliente invalido para la organizacion';
  end if;

  if p_case_id is not null and not exists (
    select 1
    from public.cargo_vuelta_cases cv
    where cv.id = p_case_id
      and cv.org_id = p_org_id
      and cv.cliente_id = p_cliente_id
  ) then
    raise exception 'Caso invalido para el cliente y organizacion';
  end if;

  if p_ptp_id is not null and not exists (
    select 1
    from public.cob_ptps ptp
    where ptp.id = p_ptp_id
      and ptp.org_id = p_org_id
      and ptp.cliente_id = p_cliente_id
      and (p_case_id is null or ptp.case_id = p_case_id)
  ) then
    raise exception 'PTP invalido para el pago actual';
  end if;

  if p_cuota_ids is not null then
    select coalesce(array_length(p_cuota_ids, 1), 0)
    into v_cuota_count;

    if exists (
      select 1
      from public.cob_plan_cuotas cpc
      join public.cob_plan_pagos cpp on cpp.id = cpc.plan_id
      where cpc.id = any(p_cuota_ids)
        and (
          cpc.org_id <> p_org_id
          or cpp.cliente_id <> p_cliente_id
          or (p_case_id is not null and cpp.case_id is distinct from p_case_id)
          or cpc.estado not in ('pendiente', 'vencida')
          or cpc.pago_id is not null
        )
    ) then
      raise exception 'Una o mas cuotas no son validas para este pago';
    end if;

    if v_cuota_count > 0 and (
      select count(*)
      from public.cob_plan_cuotas cpc
      where cpc.id = any(p_cuota_ids)
    ) <> v_cuota_count then
      raise exception 'Una o mas cuotas seleccionadas no existen';
    end if;
  end if;

  insert into public.cob_pagos (
    org_id,
    cliente_id,
    case_id,
    ptp_id,
    monto,
    fecha_pago,
    metodo_pago,
    referencia,
    notas,
    creado_por
  ) values (
    p_org_id,
    p_cliente_id,
    p_case_id,
    p_ptp_id,
    p_monto,
    p_fecha_pago,
    p_metodo_pago,
    p_referencia,
    p_notas,
    v_user_id
  )
  returning id into v_pago_id;

  if p_ptp_id is not null then
    update public.cob_ptps
    set
      estado = 'cumplido',
      fecha_cumplimiento = p_fecha_pago,
      updated_by = v_user_id,
      updated_at = now()
    where id = p_ptp_id;
  end if;

  if p_cuota_ids is not null and v_cuota_count > 0 then
    update public.cob_plan_cuotas
    set
      pago_id = v_pago_id,
      estado = 'pagada',
      fecha_pago = p_fecha_pago,
      updated_at = now()
    where id = any(p_cuota_ids);

    get diagnostics v_updated_cuotas = row_count;

    if v_updated_cuotas <> v_cuota_count then
      raise exception 'No se pudieron actualizar todas las cuotas seleccionadas';
    end if;
  end if;

  return v_pago_id;
end;
$$;
grant execute on function public.fn_registrar_pago(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  uuid,
  uuid[]
) to authenticated;
revoke execute on function public.fn_registrar_pago(
  uuid,
  uuid,
  uuid,
  numeric,
  date,
  text,
  text,
  text,
  uuid,
  uuid[]
) from public, anon;
comment on function public.fn_registrar_pago(uuid, uuid, uuid, numeric, date, text, text, text, uuid, uuid[]) is
  'Registra un pago de forma atomica: crea cob_pagos y actualiza opcionalmente PTP y cuotas asociadas en la misma transaccion.';
commit;
