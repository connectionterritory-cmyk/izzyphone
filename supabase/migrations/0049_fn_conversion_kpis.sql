-- ============================================================
-- 0045_fn_conversion_kpis.sql
-- RPC helper for conversion KPIs + supporting indexes
-- ============================================================

begin;
create or replace function public.get_conversion_kpis(
  p_user_ids uuid[] default null,
  p_range text default 'semana'
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  range_key text := lower(coalesce(p_range, 'semana'));
  start_ts timestamptz;
  end_ts timestamptz;
  prev_start timestamptz;
  prev_end timestamptz;
  span interval;

  citas_programadas integer := 0;
  citas_completadas integer := 0;
  citas_no_show integer := 0;
  citas_venta integer := 0;
  citas_realizada integer := 0;
  citas_demo_venta integer := 0;

  prev_citas_programadas integer := 0;
  prev_citas_completadas integer := 0;
  prev_citas_no_show integer := 0;
  prev_citas_venta integer := 0;
  prev_citas_realizada integer := 0;
  prev_citas_demo_venta integer := 0;

  ventas_monto numeric := 0;
  ventas_count integer := 0;
  prev_ventas_monto numeric := 0;
  prev_ventas_count integer := 0;
begin
  if range_key = 'hoy' then
    start_ts := date_trunc('day', now());
    end_ts := start_ts + interval '1 day';
  elsif range_key = 'mes' then
    start_ts := date_trunc('month', now());
    end_ts := start_ts + interval '1 month';
  else
    start_ts := date_trunc('week', now());
    end_ts := start_ts + interval '1 week';
  end if;

  span := end_ts - start_ts;
  prev_start := start_ts - span;
  prev_end := start_ts;

  select count(*) into citas_programadas
  from public.citas c
  where c.start_at >= start_ts
    and c.start_at < end_ts
    and c.estado in ('programada', 'confirmada', 'en_camino')
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into citas_completadas
  from public.citas c
  where c.start_at >= start_ts
    and c.start_at < end_ts
    and c.estado = 'completada'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into citas_no_show
  from public.citas c
  where c.start_at >= start_ts
    and c.start_at < end_ts
    and c.estado = 'no_show'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into citas_venta
  from public.citas c
  where c.start_at >= start_ts
    and c.start_at < end_ts
    and c.resultado = 'venta'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into citas_realizada
  from public.citas c
  where c.start_at >= start_ts
    and c.start_at < end_ts
    and c.resultado = 'realizada'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into citas_demo_venta
  from public.citas c
  where c.start_at >= start_ts
    and c.start_at < end_ts
    and c.tipo = 'demo'
    and c.resultado = 'venta'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into prev_citas_programadas
  from public.citas c
  where c.start_at >= prev_start
    and c.start_at < prev_end
    and c.estado in ('programada', 'confirmada', 'en_camino')
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into prev_citas_completadas
  from public.citas c
  where c.start_at >= prev_start
    and c.start_at < prev_end
    and c.estado = 'completada'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into prev_citas_no_show
  from public.citas c
  where c.start_at >= prev_start
    and c.start_at < prev_end
    and c.estado = 'no_show'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into prev_citas_venta
  from public.citas c
  where c.start_at >= prev_start
    and c.start_at < prev_end
    and c.resultado = 'venta'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into prev_citas_realizada
  from public.citas c
  where c.start_at >= prev_start
    and c.start_at < prev_end
    and c.resultado = 'realizada'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select count(*) into prev_citas_demo_venta
  from public.citas c
  where c.start_at >= prev_start
    and c.start_at < prev_end
    and c.tipo = 'demo'
    and c.resultado = 'venta'
    and (
      p_user_ids is null
      or c.owner_id = any(p_user_ids)
      or c.assigned_to = any(p_user_ids)
    );

  select coalesce(sum(v.monto), 0), count(*) into ventas_monto, ventas_count
  from public.ventas v
  where v.fecha_venta >= start_ts::date
    and v.fecha_venta < end_ts::date
    and (
      p_user_ids is null
      or v.vendedor_id = any(p_user_ids)
    );

  select coalesce(sum(v.monto), 0), count(*) into prev_ventas_monto, prev_ventas_count
  from public.ventas v
  where v.fecha_venta >= prev_start::date
    and v.fecha_venta < prev_end::date
    and (
      p_user_ids is null
      or v.vendedor_id = any(p_user_ids)
    );

  return jsonb_build_object(
    'period', jsonb_build_object(
      'start', start_ts,
      'end', end_ts
    ),
    'previous', jsonb_build_object(
      'start', prev_start,
      'end', prev_end
    ),
    'citas', jsonb_build_object(
      'programadas', citas_programadas,
      'completadas', citas_completadas,
      'no_show', citas_no_show,
      'tasa_asistencia', case when (citas_completadas + citas_no_show) = 0 then 0
        else round((citas_completadas::numeric / (citas_completadas + citas_no_show)) * 100, 2) end
    ),
    'conversion', jsonb_build_object(
      'ventas', citas_venta,
      'realizadas', citas_realizada,
      'tasa_conversion', case when citas_completadas = 0 then 0
        else round((citas_venta::numeric / citas_completadas) * 100, 2) end,
      'demo_venta', citas_demo_venta
    ),
    'ventas', jsonb_build_object(
      'monto', ventas_monto,
      'count', ventas_count,
      'ticket_promedio', case when ventas_count = 0 then 0
        else round((ventas_monto / ventas_count), 2) end
    ),
    'prev', jsonb_build_object(
      'citas_programadas', prev_citas_programadas,
      'citas_completadas', prev_citas_completadas,
      'citas_no_show', prev_citas_no_show,
      'conversion_ventas', prev_citas_venta,
      'conversion_realizadas', prev_citas_realizada,
      'conversion_demo_venta', prev_citas_demo_venta,
      'ventas_monto', prev_ventas_monto,
      'ventas_count', prev_ventas_count
    )
  );
end;
$$;
grant execute on function public.get_conversion_kpis(uuid[], text) to authenticated;
create index if not exists citas_start_estado_idx
  on public.citas (start_at, estado)
  where estado in ('completada', 'no_show', 'cancelada');
create index if not exists citas_start_resultado_idx
  on public.citas (start_at, resultado)
  where resultado is not null;
create index if not exists leads_vendedor_idx
  on public.leads (vendedor_id)
  where deleted_at is null;
create index if not exists ventas_vendedor_fecha_idx
  on public.ventas (vendedor_id, fecha_venta);
commit;
