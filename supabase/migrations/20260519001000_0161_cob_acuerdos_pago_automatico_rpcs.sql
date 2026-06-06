begin;
-- 0161: RPCs base para motor de acuerdos automáticos DFP
-- Alcance: lifecycle del acuerdo + generación idempotente de cobros programados.
-- Fuera de alcance en esta migración:
--   - marcar cobros pagados/fallidos con impacto financiero
--   - escrituras en cob_pagos
--   - escrituras en cob_financial_ledger
--   - generación automática de statements

-- ============================================================
-- 1) Helpers puros de fechas
-- ============================================================

create or replace function public.fn_cob_acuerdo_calcular_fecha_mensual(
  p_anio int,
  p_mes int,
  p_dia int
)
returns date
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
  v_first_day date;
  v_last_day  date;
  v_day       int;
begin
  if p_mes < 1 or p_mes > 12 then
    raise exception 'INVALID_PARAM: p_mes (%) debe estar entre 1 y 12', p_mes;
  end if;

  if p_dia < 1 or p_dia > 31 then
    raise exception 'INVALID_PARAM: p_dia (%) debe estar entre 1 y 31', p_dia;
  end if;

  v_first_day := make_date(p_anio, p_mes, 1);
  v_last_day  := (date_trunc('month', v_first_day::timestamp) + interval '1 month - 1 day')::date;
  v_day       := least(p_dia, extract(day from v_last_day)::int);

  return make_date(p_anio, p_mes, v_day);
end;
$$;
comment on function public.fn_cob_acuerdo_calcular_fecha_mensual(int, int, int) is
  'Devuelve fecha ajustada al último día del mes si p_dia no existe en ese mes.';
create or replace function public.fn_cob_acuerdo_calcular_proximo_cobro(
  p_fecha_base date,
  p_dia int
)
returns date
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
  v_anio int;
  v_mes int;
  v_candidate date;
  v_next_month date;
begin
  if p_dia < 1 or p_dia > 31 then
    raise exception 'INVALID_PARAM: p_dia (%) debe estar entre 1 y 31', p_dia;
  end if;

  v_anio := extract(year from p_fecha_base)::int;
  v_mes  := extract(month from p_fecha_base)::int;

  v_candidate := public.fn_cob_acuerdo_calcular_fecha_mensual(v_anio, v_mes, p_dia);

  if v_candidate > p_fecha_base then
    return v_candidate;
  end if;

  v_next_month := (date_trunc('month', p_fecha_base::timestamp) + interval '1 month')::date;
  return public.fn_cob_acuerdo_calcular_fecha_mensual(
    extract(year from v_next_month)::int,
    extract(month from v_next_month)::int,
    p_dia
  );
end;
$$;
comment on function public.fn_cob_acuerdo_calcular_proximo_cobro(date, int) is
  'Calcula próximo cobro mensual ajustando días 29/30/31 al último día del mes.';
-- ============================================================
-- 2) Generación idempotente de cobros programados
-- ============================================================

create or replace function public.fn_cob_acuerdo_generar_cobros(
  p_acuerdo_id uuid,
  p_meses_a_generar int default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid;
  v_actor_org_id uuid;
  v_actor_can_operate boolean;

  v_acuerdo public.cob_acuerdos_pago_automatico%rowtype;

  v_created_count int := 0;
  v_skipped_count int := 0;
  v_i int;
  v_month_anchor date;
  v_base_month date;
  v_fecha_programada date;
  v_inserted_id uuid;
  v_fechas date[] := '{}';
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  v_actor_can_operate := (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  );

  if not v_actor_can_operate then
    raise exception 'FORBIDDEN: rol sin permiso para generar cobros de acuerdos';
  end if;

  if p_acuerdo_id is null then
    raise exception 'INVALID_PARAM: p_acuerdo_id es requerido';
  end if;

  if p_meses_a_generar is null or p_meses_a_generar < 1 or p_meses_a_generar > 24 then
    raise exception 'INVALID_PARAM: p_meses_a_generar (%) debe estar entre 1 y 24', p_meses_a_generar;
  end if;

  select * into v_acuerdo
  from public.cob_acuerdos_pago_automatico a
  where a.id = p_acuerdo_id
    and a.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'ACUERDO_NOT_FOUND_OR_FORBIDDEN: acuerdo no existe o no pertenece a la org del usuario';
  end if;

  if v_acuerdo.estado <> 'activo' then
    raise exception 'INVALID_STATE: acuerdo % debe estar en estado activo para generar cobros', p_acuerdo_id;
  end if;

  v_month_anchor := coalesce(v_acuerdo.fecha_proximo_cobro, v_acuerdo.fecha_primer_cobro);
  v_base_month := date_trunc('month', v_month_anchor::timestamp)::date;

  for v_i in 0..(p_meses_a_generar - 1) loop
    v_month_anchor := (v_base_month + make_interval(months => v_i))::date;

    v_fecha_programada := public.fn_cob_acuerdo_calcular_fecha_mensual(
      extract(year from v_month_anchor)::int,
      extract(month from v_month_anchor)::int,
      v_acuerdo.dia_cobro_preferido
    );

    insert into public.cob_cobros_programados (
      org_id,
      acuerdo_id,
      cliente_id,
      cargo_vuelta_case_id,
      metodo_pago_id,
      fecha_programada,
      monto_programado,
      estado,
      intento_numero
    )
    values (
      v_acuerdo.org_id,
      v_acuerdo.id,
      v_acuerdo.cliente_id,
      v_acuerdo.cargo_vuelta_case_id,
      v_acuerdo.metodo_pago_id,
      v_fecha_programada,
      v_acuerdo.monto_total_cobro,
      'programado',
      0
    )
    on conflict (acuerdo_id, fecha_programada) do nothing
    returning id into v_inserted_id;

    if v_inserted_id is not null then
      v_created_count := v_created_count + 1;
      v_fechas := array_append(v_fechas, v_fecha_programada);

      insert into public.cob_acuerdo_eventos (
        org_id,
        acuerdo_id,
        cobro_programado_id,
        tipo_evento,
        actor_user_id,
        payload_after,
        metadata
      )
      values (
        v_acuerdo.org_id,
        v_acuerdo.id,
        v_inserted_id,
        'cobro_programado_creado',
        v_actor_id,
        jsonb_build_object(
          'fecha_programada', v_fecha_programada,
          'monto_programado', v_acuerdo.monto_total_cobro,
          'metodo_pago_id', v_acuerdo.metodo_pago_id
        ),
        jsonb_build_object('source', 'fn_cob_acuerdo_generar_cobros')
      );
    else
      v_skipped_count := v_skipped_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'acuerdo_id', v_acuerdo.id,
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'fechas_generadas', coalesce(to_jsonb(v_fechas), '[]'::jsonb)
  );
end;
$$;
comment on function public.fn_cob_acuerdo_generar_cobros(uuid, int) is
  'Genera cobros programados futuros de forma idempotente para acuerdos activos.';
-- ============================================================
-- 3) Crear acuerdo automático
-- ============================================================

create or replace function public.fn_cob_acuerdo_crear(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid;
  v_actor_org_id uuid;
  v_actor_can_operate boolean;

  v_case record;
  v_metodo record;
  v_existing uuid;

  v_cliente_id uuid;
  v_case_id uuid;
  v_revolving_id uuid;
  v_metodo_id uuid;

  v_monto_base numeric(12,2);
  v_pct numeric(5,2);
  v_monto_total numeric(12,2);
  v_frecuencia text;
  v_dia int;
  v_fecha_primer date;
  v_autorizado boolean;
  v_fecha_aut timestamptz;
  v_canal text;
  v_notas text;
  v_metadata jsonb;
  v_estado text;

  v_acuerdo_id uuid;
  v_gen_result jsonb := '{}'::jsonb;
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  v_actor_can_operate := (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  );

  if not v_actor_can_operate then
    raise exception 'FORBIDDEN: rol sin permiso para crear acuerdos';
  end if;

  if p_payload is null then
    raise exception 'INVALID_PARAM: p_payload es requerido';
  end if;

  v_cliente_id   := (p_payload->>'cliente_id')::uuid;
  v_case_id      := (p_payload->>'cargo_vuelta_case_id')::uuid;
  v_revolving_id := nullif(p_payload->>'revolving_account_id', '')::uuid;
  v_metodo_id    := nullif(p_payload->>'metodo_pago_id', '')::uuid;

  v_monto_base   := (p_payload->>'monto_base_mensual')::numeric(12,2);
  v_pct          := coalesce((p_payload->>'porcentaje_cargo_autorizado')::numeric(5,2), 0);
  v_monto_total  := (p_payload->>'monto_total_cobro')::numeric(12,2);

  v_frecuencia   := coalesce(p_payload->>'frecuencia', 'mensual');
  v_dia          := (p_payload->>'dia_cobro_preferido')::int;
  v_fecha_primer := (p_payload->>'fecha_primer_cobro')::date;

  v_autorizado   := coalesce((p_payload->>'autorizado_por_cliente')::boolean, false);
  v_fecha_aut    := nullif(p_payload->>'fecha_autorizacion', '')::timestamptz;
  v_canal        := nullif(p_payload->>'canal_autorizacion', '');
  v_notas        := nullif(p_payload->>'notas', '');
  v_metadata     := coalesce(p_payload->'metadata', '{}'::jsonb);

  if v_cliente_id is null or v_case_id is null then
    raise exception 'INVALID_PARAM: cliente_id y cargo_vuelta_case_id son requeridos';
  end if;

  if v_monto_base is null or v_monto_base <= 0 then
    raise exception 'INVALID_PARAM: monto_base_mensual debe ser > 0';
  end if;

  if v_pct < 0 or v_pct > 100 then
    raise exception 'INVALID_PARAM: porcentaje_cargo_autorizado debe estar entre 0 y 100';
  end if;

  if v_monto_total is null or v_monto_total <= 0 then
    raise exception 'INVALID_PARAM: monto_total_cobro debe ser > 0';
  end if;

  if v_frecuencia <> 'mensual' then
    raise exception 'INVALID_PARAM: frecuencia debe ser mensual';
  end if;

  if v_dia is null or v_dia < 1 or v_dia > 31 then
    raise exception 'INVALID_PARAM: dia_cobro_preferido debe estar entre 1 y 31';
  end if;

  if v_fecha_primer is null then
    raise exception 'INVALID_PARAM: fecha_primer_cobro es requerida';
  end if;

  if v_autorizado and v_fecha_aut is null then
    raise exception 'INVALID_PARAM: fecha_autorizacion es requerida cuando autorizado_por_cliente = true';
  end if;

  select c.id, c.org_id, c.cliente_id
  into v_case
  from public.cargo_vuelta_cases c
  where c.id = v_case_id
    and c.org_id = v_actor_org_id
  limit 1;

  if not found then
    raise exception 'CASE_NOT_FOUND_OR_FORBIDDEN: el caso no existe o no pertenece a la organización';
  end if;

  if v_case.cliente_id is distinct from v_cliente_id then
    raise exception 'INVALID_RELATION: cliente_id no corresponde al cliente del caso';
  end if;

  if v_metodo_id is not null then
    select m.id, m.org_id, m.cliente_id, m.cargo_vuelta_case_id
    into v_metodo
    from public.cob_metodos_pago m
    where m.id = v_metodo_id
      and m.org_id = v_actor_org_id
    limit 1;

    if not found then
      raise exception 'METODO_PAGO_NOT_FOUND_OR_FORBIDDEN: método de pago no existe o no pertenece a la organización';
    end if;

    if v_metodo.cliente_id is not null and v_metodo.cliente_id is distinct from v_cliente_id then
      raise exception 'INVALID_RELATION: metodo_pago_id no corresponde al cliente del acuerdo';
    end if;

    if v_metodo.cargo_vuelta_case_id is not null and v_metodo.cargo_vuelta_case_id is distinct from v_case_id then
      raise exception 'INVALID_RELATION: metodo_pago_id no corresponde al caso del acuerdo';
    end if;
  end if;

  if v_revolving_id is not null then
    perform 1
    from public.cob_revolving_accounts a
    where a.id = v_revolving_id
      and a.org_id = v_actor_org_id
      and a.cargo_vuelta_case_id = v_case_id;

    if not found then
      raise exception 'REVOLVING_NOT_FOUND_OR_FORBIDDEN: revolving_account_id inválido para org/caso';
    end if;
  end if;

  select a.id into v_existing
  from public.cob_acuerdos_pago_automatico a
  where a.org_id = v_actor_org_id
    and a.cargo_vuelta_case_id = v_case_id
    and a.estado in ('activo', 'pausado')
  limit 1;

  if v_existing is not null then
    raise exception 'DUPLICATE_ACTIVE_AGREEMENT: ya existe acuerdo activo/pausado para este caso (%)', v_existing;
  end if;

  v_estado := case
    when v_autorizado then 'activo'
    else 'borrador'
  end;

  insert into public.cob_acuerdos_pago_automatico (
    org_id,
    cliente_id,
    cargo_vuelta_case_id,
    revolving_account_id,
    metodo_pago_id,
    monto_base_mensual,
    porcentaje_cargo_autorizado,
    monto_total_cobro,
    frecuencia,
    dia_cobro_preferido,
    fecha_primer_cobro,
    fecha_proximo_cobro,
    statement_automatico,
    recordatorio_automatico,
    estado,
    autorizado_por_cliente,
    fecha_autorizacion,
    canal_autorizacion,
    notas,
    metadata,
    created_by,
    updated_by
  )
  values (
    v_actor_org_id,
    v_cliente_id,
    v_case_id,
    v_revolving_id,
    v_metodo_id,
    v_monto_base,
    v_pct,
    v_monto_total,
    'mensual',
    v_dia,
    v_fecha_primer,
    v_fecha_primer,
    coalesce((p_payload->>'statement_automatico')::boolean, true),
    coalesce((p_payload->>'recordatorio_automatico')::boolean, true),
    v_estado,
    v_autorizado,
    v_fecha_aut,
    v_canal,
    v_notas,
    v_metadata,
    v_actor_id,
    v_actor_id
  )
  returning id into v_acuerdo_id;

  insert into public.cob_acuerdo_eventos (
    org_id,
    acuerdo_id,
    tipo_evento,
    actor_user_id,
    payload_after,
    metadata
  )
  values (
    v_actor_org_id,
    v_acuerdo_id,
    'acuerdo_creado',
    v_actor_id,
    jsonb_build_object(
      'estado', v_estado,
      'fecha_primer_cobro', v_fecha_primer,
      'monto_total_cobro', v_monto_total,
      'dia_cobro_preferido', v_dia
    ),
    jsonb_build_object('source', 'fn_cob_acuerdo_crear')
  );

  if v_estado = 'activo' then
    v_gen_result := public.fn_cob_acuerdo_generar_cobros(v_acuerdo_id, 3);
  end if;

  return jsonb_build_object(
    'acuerdo_id', v_acuerdo_id,
    'estado', v_estado,
    'fecha_proximo_cobro', v_fecha_primer,
    'cobros_generados', v_gen_result
  );
end;
$$;
comment on function public.fn_cob_acuerdo_crear(jsonb) is
  'Crea acuerdo automático DFP, audita evento y genera cobros iniciales si queda activo.';
-- ============================================================
-- 4) Pausar / Cancelar / Reactivar
-- ============================================================

create or replace function public.fn_cob_acuerdo_pausar(
  p_acuerdo_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid;
  v_actor_org_id uuid;
  v_actor_can_operate boolean;
  v_acuerdo public.cob_acuerdos_pago_automatico%rowtype;
  v_cancelados int := 0;
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  v_actor_can_operate := (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  );

  if not v_actor_can_operate then
    raise exception 'FORBIDDEN: rol sin permiso para pausar acuerdos';
  end if;

  if p_acuerdo_id is null then
    raise exception 'INVALID_PARAM: p_acuerdo_id es requerido';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'INVALID_PARAM: p_motivo es obligatorio';
  end if;

  select * into v_acuerdo
  from public.cob_acuerdos_pago_automatico a
  where a.id = p_acuerdo_id
    and a.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'ACUERDO_NOT_FOUND_OR_FORBIDDEN: acuerdo no existe o no pertenece a la organización';
  end if;

  if v_acuerdo.estado <> 'activo' then
    raise exception 'INVALID_STATE: solo se puede pausar un acuerdo activo';
  end if;

  update public.cob_acuerdos_pago_automatico
  set estado = 'pausado',
      updated_by = v_actor_id,
      updated_at = now()
  where id = v_acuerdo.id;

  with cte as (
    update public.cob_cobros_programados cp
    set estado = 'cancelado',
        notas = concat_ws(' | ', cp.notas, 'cancelado_por_pausa: ' || p_motivo),
        updated_at = now()
    where cp.acuerdo_id = v_acuerdo.id
      and cp.org_id = v_actor_org_id
      and cp.estado in ('programado', 'recordatorio_enviado')
      and cp.fecha_programada >= current_date
    returning cp.id
  ), ins as (
    insert into public.cob_acuerdo_eventos (
      org_id,
      acuerdo_id,
      cobro_programado_id,
      tipo_evento,
      actor_user_id,
      motivo,
      metadata
    )
    select
      v_actor_org_id,
      v_acuerdo.id,
      cte.id,
      'cobro_cancelado',
      v_actor_id,
      p_motivo,
      jsonb_build_object('source', 'fn_cob_acuerdo_pausar')
    from cte
    returning 1
  )
  select count(*)::int into v_cancelados from cte;

  insert into public.cob_acuerdo_eventos (
    org_id,
    acuerdo_id,
    tipo_evento,
    actor_user_id,
    motivo,
    metadata
  )
  values (
    v_actor_org_id,
    v_acuerdo.id,
    'acuerdo_pausado',
    v_actor_id,
    p_motivo,
    jsonb_build_object('source', 'fn_cob_acuerdo_pausar', 'cobros_cancelados', v_cancelados)
  );

  return jsonb_build_object(
    'acuerdo_id', v_acuerdo.id,
    'estado', 'pausado',
    'cobros_cancelados', v_cancelados
  );
end;
$$;
comment on function public.fn_cob_acuerdo_pausar(uuid, text) is
  'Pausa acuerdo activo y cancela cobros futuros programados/recordatorio_enviado.';
create or replace function public.fn_cob_acuerdo_cancelar(
  p_acuerdo_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid;
  v_actor_org_id uuid;
  v_actor_can_operate boolean;
  v_acuerdo public.cob_acuerdos_pago_automatico%rowtype;
  v_cancelados int := 0;
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  v_actor_can_operate := (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  );

  if not v_actor_can_operate then
    raise exception 'FORBIDDEN: rol sin permiso para cancelar acuerdos';
  end if;

  if p_acuerdo_id is null then
    raise exception 'INVALID_PARAM: p_acuerdo_id es requerido';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'INVALID_PARAM: p_motivo es obligatorio';
  end if;

  select * into v_acuerdo
  from public.cob_acuerdos_pago_automatico a
  where a.id = p_acuerdo_id
    and a.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'ACUERDO_NOT_FOUND_OR_FORBIDDEN: acuerdo no existe o no pertenece a la organización';
  end if;

  if v_acuerdo.estado not in ('borrador', 'activo', 'pausado') then
    raise exception 'INVALID_STATE: solo se puede cancelar acuerdo en borrador, activo o pausado';
  end if;

  update public.cob_acuerdos_pago_automatico
  set estado = 'cancelado',
      updated_by = v_actor_id,
      updated_at = now()
  where id = v_acuerdo.id;

  with cte as (
    update public.cob_cobros_programados cp
    set estado = 'cancelado',
        notas = concat_ws(' | ', cp.notas, 'cancelado_por_acuerdo: ' || p_motivo),
        updated_at = now()
    where cp.acuerdo_id = v_acuerdo.id
      and cp.org_id = v_actor_org_id
      and cp.estado in ('programado', 'recordatorio_enviado')
      and cp.fecha_programada >= current_date
    returning cp.id
  ), ins as (
    insert into public.cob_acuerdo_eventos (
      org_id,
      acuerdo_id,
      cobro_programado_id,
      tipo_evento,
      actor_user_id,
      motivo,
      metadata
    )
    select
      v_actor_org_id,
      v_acuerdo.id,
      cte.id,
      'cobro_cancelado',
      v_actor_id,
      p_motivo,
      jsonb_build_object('source', 'fn_cob_acuerdo_cancelar')
    from cte
    returning 1
  )
  select count(*)::int into v_cancelados from cte;

  insert into public.cob_acuerdo_eventos (
    org_id,
    acuerdo_id,
    tipo_evento,
    actor_user_id,
    motivo,
    metadata
  )
  values (
    v_actor_org_id,
    v_acuerdo.id,
    'acuerdo_cancelado',
    v_actor_id,
    p_motivo,
    jsonb_build_object('source', 'fn_cob_acuerdo_cancelar', 'cobros_cancelados', v_cancelados)
  );

  return jsonb_build_object(
    'acuerdo_id', v_acuerdo.id,
    'estado', 'cancelado',
    'cobros_cancelados', v_cancelados
  );
end;
$$;
comment on function public.fn_cob_acuerdo_cancelar(uuid, text) is
  'Cancela acuerdo y cobros futuros; no cierra caso automáticamente.';
create or replace function public.fn_cob_acuerdo_reactivar(
  p_acuerdo_id uuid,
  p_fecha_reactivacion date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid;
  v_actor_org_id uuid;
  v_actor_can_operate boolean;
  v_acuerdo public.cob_acuerdos_pago_automatico%rowtype;
  v_fecha_proximo date;
  v_gen_result jsonb;
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    raise exception 'AUTH_REQUIRED: usuario no autenticado';
  end if;

  select u.org_id into v_actor_org_id
  from public.usuarios u
  where u.id = v_actor_id
  limit 1;

  if v_actor_org_id is null then
    raise exception 'ORG_REQUIRED: no se encontró org_id para el usuario autenticado';
  end if;

  v_actor_can_operate := (
    public.is_admin_or_distribuidor()
    or public.is_supervisor_tele()
    or security.current_user_role() = 'telemercadeo'
  );

  if not v_actor_can_operate then
    raise exception 'FORBIDDEN: rol sin permiso para reactivar acuerdos';
  end if;

  if p_acuerdo_id is null then
    raise exception 'INVALID_PARAM: p_acuerdo_id es requerido';
  end if;

  if p_fecha_reactivacion is null then
    raise exception 'INVALID_PARAM: p_fecha_reactivacion es requerida';
  end if;

  select * into v_acuerdo
  from public.cob_acuerdos_pago_automatico a
  where a.id = p_acuerdo_id
    and a.org_id = v_actor_org_id
  for update;

  if not found then
    raise exception 'ACUERDO_NOT_FOUND_OR_FORBIDDEN: acuerdo no existe o no pertenece a la organización';
  end if;

  if v_acuerdo.estado <> 'pausado' then
    raise exception 'INVALID_STATE: solo se puede reactivar un acuerdo en estado pausado';
  end if;

  v_fecha_proximo := public.fn_cob_acuerdo_calcular_proximo_cobro(
    p_fecha_reactivacion,
    v_acuerdo.dia_cobro_preferido
  );

  update public.cob_acuerdos_pago_automatico
  set estado = 'activo',
      fecha_proximo_cobro = v_fecha_proximo,
      updated_by = v_actor_id,
      updated_at = now()
  where id = v_acuerdo.id;

  insert into public.cob_acuerdo_eventos (
    org_id,
    acuerdo_id,
    tipo_evento,
    actor_user_id,
    payload_after,
    metadata
  )
  values (
    v_actor_org_id,
    v_acuerdo.id,
    'acuerdo_editado',
    v_actor_id,
    jsonb_build_object('estado', 'activo', 'fecha_proximo_cobro', v_fecha_proximo),
    jsonb_build_object('accion', 'reactivado', 'source', 'fn_cob_acuerdo_reactivar')
  );

  v_gen_result := public.fn_cob_acuerdo_generar_cobros(v_acuerdo.id, 3);

  return jsonb_build_object(
    'acuerdo_id', v_acuerdo.id,
    'estado', 'activo',
    'fecha_proximo_cobro', v_fecha_proximo,
    'cobros_generados', v_gen_result
  );
end;
$$;
comment on function public.fn_cob_acuerdo_reactivar(uuid, date) is
  'Reactiva acuerdo pausado, recalcula próximo cobro y genera agenda inicial.';
-- ============================================================
-- Grants (patrón de RPCs del proyecto)
-- ============================================================

revoke all on function public.fn_cob_acuerdo_calcular_fecha_mensual(int, int, int) from public;
revoke all on function public.fn_cob_acuerdo_calcular_proximo_cobro(date, int) from public;
revoke all on function public.fn_cob_acuerdo_generar_cobros(uuid, int) from public;
revoke all on function public.fn_cob_acuerdo_crear(jsonb) from public;
revoke all on function public.fn_cob_acuerdo_pausar(uuid, text) from public;
revoke all on function public.fn_cob_acuerdo_cancelar(uuid, text) from public;
revoke all on function public.fn_cob_acuerdo_reactivar(uuid, date) from public;
grant execute on function public.fn_cob_acuerdo_calcular_fecha_mensual(int, int, int) to authenticated, service_role;
grant execute on function public.fn_cob_acuerdo_calcular_proximo_cobro(date, int) to authenticated, service_role;
grant execute on function public.fn_cob_acuerdo_generar_cobros(uuid, int) to authenticated;
grant execute on function public.fn_cob_acuerdo_crear(jsonb) to authenticated;
grant execute on function public.fn_cob_acuerdo_pausar(uuid, text) to authenticated;
grant execute on function public.fn_cob_acuerdo_cancelar(uuid, text) to authenticated;
grant execute on function public.fn_cob_acuerdo_reactivar(uuid, date) to authenticated;
commit;
