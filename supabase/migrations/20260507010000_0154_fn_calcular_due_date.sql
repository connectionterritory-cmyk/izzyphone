begin;
-- 0154: fn_calcular_due_date
--
-- Calcula la fecha de vencimiento (due date) de un estado de cuenta DFP
-- a partir de la fecha de corte, el mínimo de días requeridos y el día
-- preferido del cliente para pagar.
--
-- Lógica:
--   1. Fecha mínima = fecha_corte + min_days (default 21, CARD Act).
--   2. Si no hay preferred_day → devuelve fecha mínima.
--   3. Si hay preferred_day → busca la próxima ocurrencia de ese día
--      en el mes de la fecha mínima. Si ya pasó ese día en ese mes,
--      avanza al mes siguiente.
--
-- Invariantes:
--   - Siempre retorna un día >= fecha_corte + min_days.
--   - preferred_day se trata como número de día 1–28 (schema limita a 28).
--   - Inmutable: sin acceso a tablas; determinista con los mismos args.
--
-- Rollback:
--   drop function if exists public.fn_calcular_due_date(date, smallint, smallint);

create or replace function public.fn_calcular_due_date(
  p_fecha_corte    date,
  p_min_days       smallint  default 21,
  p_preferred_day  smallint  default null
)
returns date
language plpgsql
immutable
as $$
declare
  v_min_due    date;
  v_year       integer;
  v_month      integer;
  v_day        integer;
  v_candidate  date;
begin
  if p_fecha_corte is null then
    return null;
  end if;

  v_min_due := p_fecha_corte + coalesce(p_min_days, 21)::integer;

  if p_preferred_day is null then
    return v_min_due;
  end if;

  -- Usar el menor entre preferred_day y 28 (schema garantiza ≤28, pero defensivo)
  v_day   := least(p_preferred_day::integer, 28);
  v_year  := extract(year  from v_min_due)::integer;
  v_month := extract(month from v_min_due)::integer;

  v_candidate := make_date(v_year, v_month, v_day);

  -- Si el candidato cae antes de la fecha mínima, avanzar un mes
  if v_candidate < v_min_due then
    if v_month = 12 then
      v_candidate := make_date(v_year + 1, 1, v_day);
    else
      v_candidate := make_date(v_year, v_month + 1, v_day);
    end if;
  end if;

  return v_candidate;
end;
$$;
comment on function public.fn_calcular_due_date(date, smallint, smallint) is
  'Calcula fecha_vencimiento de un statement DFP. '
  'Garantiza >= fecha_corte + min_days (CARD Act default 21). '
  'Con preferred_day: busca la próxima ocurrencia del día en el mes correcto. '
  'Inmutable y sin acceso a tablas; úsarla desde fn_cob_statement_generar.';
-- Permisos: función pura, sin datos sensibles; accesible a autenticados
revoke all on function public.fn_calcular_due_date(date, smallint, smallint)
  from public, anon;
grant execute on function public.fn_calcular_due_date(date, smallint, smallint)
  to authenticated;
commit;
