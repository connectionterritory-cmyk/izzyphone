-- ============================================================
-- 0116: formalizacion de Cargo de Vuelta / Recomprada / DFP
--
-- Objetivo:
--   Formalizar el caso de cobranza devuelto por Hy-Cite sin tocar
--   clientes.saldo_actual ni la logica de pagos/PTPs/planes.
--
-- Regla de negocio:
--   - clientes.saldo_actual puede quedar en 0.00
--   - el saldo operativo se basa en cargo_vuelta_cases.monto_devuelto
--   - monto_recuperado = suma de cob_pagos.monto del caso
--   - saldo_operativo = monto_devuelto - monto_recuperado
--
-- Compatibilidad:
--   - monto_total se mantiene por compatibilidad legacy
--   - para casos tipo_caso='cargo_vuelta', monto_devuelto es la
--     fuente correcta del saldo operativo
-- ============================================================

begin;
alter table public.cargo_vuelta_cases
  add column if not exists tipo_caso text not null default 'cargo_vuelta',
  add column if not exists alias_operativo text,
  add column if not exists fecha_cargo_vuelta date,
  add column if not exists monto_devuelto numeric(12,2),
  add column if not exists numero_cuenta_hycite text,
  add column if not exists numero_orden_hycite text,
  add column if not exists orden_hycite_id uuid,
  add column if not exists documento_hycite_id uuid,
  add column if not exists origen_cargo_vuelta text not null default 'hycite',
  add column if not exists requiere_reconciliacion boolean not null default false;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'cargo_vuelta_cases_tipo_caso_chk'
      and conrelid = 'public.cargo_vuelta_cases'::regclass
  ) then
    alter table public.cargo_vuelta_cases
      add constraint cargo_vuelta_cases_tipo_caso_chk
      check (tipo_caso in ('cargo_vuelta'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'cargo_vuelta_cases_origen_cargo_vuelta_chk'
      and conrelid = 'public.cargo_vuelta_cases'::regclass
  ) then
    alter table public.cargo_vuelta_cases
      add constraint cargo_vuelta_cases_origen_cargo_vuelta_chk
      check (origen_cargo_vuelta in ('hycite'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'cargo_vuelta_cases_monto_devuelto_chk'
      and conrelid = 'public.cargo_vuelta_cases'::regclass
  ) then
    alter table public.cargo_vuelta_cases
      add constraint cargo_vuelta_cases_monto_devuelto_chk
      check (monto_devuelto is null or monto_devuelto >= 0);
  end if;
end $$;
comment on column public.cargo_vuelta_cases.tipo_caso is
  'Tipo formal del caso de cobranza. En esta fase solo cargo_vuelta.';
comment on column public.cargo_vuelta_cases.alias_operativo is
  'Alias operativo libre para el equipo: Cargo de Vuelta, Cuenta Devuelta, Cuenta Recomprada, Recomprada, DFP, Distributor Finance, Distributor Financing, Distributor Finance Program u otro equivalente.';
comment on column public.cargo_vuelta_cases.fecha_cargo_vuelta is
  'Fecha en que Hy-Cite devolvio la cuenta al distribuidor para cobranza directa.';
comment on column public.cargo_vuelta_cases.monto_devuelto is
  'Monto devuelto por Hy-Cite para cobranza directa. Para tipo_caso=cargo_vuelta esta es la fuente correcta del saldo operativo, no clientes.saldo_actual.';
comment on column public.cargo_vuelta_cases.monto_total is
  'Campo legacy mantenido por compatibilidad. Para tipo_caso=cargo_vuelta puede espejar monto_devuelto, pero la fuente correcta del saldo operativo es monto_devuelto.';
comment on column public.cargo_vuelta_cases.numero_cuenta_hycite is
  'Numero de cuenta Hy-Cite asociado al caso devuelto.';
comment on column public.cargo_vuelta_cases.numero_orden_hycite is
  'Numero de orden Hy-Cite relacionado al caso, cuando aplique.';
comment on column public.cargo_vuelta_cases.orden_hycite_id is
  'Referencia futura a una tabla formal de ordenes Hy-Cite, si se implementa.';
comment on column public.cargo_vuelta_cases.documento_hycite_id is
  'Referencia futura a documento/importacion/OCR origen que respalda el cargo de vuelta.';
comment on column public.cargo_vuelta_cases.origen_cargo_vuelta is
  'Origen reportado del cargo de vuelta. En esta fase se espera hycite.';
comment on column public.cargo_vuelta_cases.requiere_reconciliacion is
  'Bandera operativa para casos cuyo monto devuelto, pagos o soporte documental requieren revision.';
update public.cargo_vuelta_cases
set monto_devuelto = monto_total
where tipo_caso = 'cargo_vuelta'
  and monto_devuelto is null
  and monto_total is not null;
create index if not exists cargo_vuelta_cases_tipo_caso_idx
  on public.cargo_vuelta_cases (org_id, tipo_caso);
create index if not exists cargo_vuelta_cases_fecha_cargo_vuelta_idx
  on public.cargo_vuelta_cases (org_id, fecha_cargo_vuelta desc)
  where fecha_cargo_vuelta is not null;
create index if not exists cargo_vuelta_cases_numero_cuenta_hycite_idx
  on public.cargo_vuelta_cases (org_id, numero_cuenta_hycite)
  where numero_cuenta_hycite is not null;
create index if not exists cargo_vuelta_cases_numero_orden_hycite_idx
  on public.cargo_vuelta_cases (org_id, numero_orden_hycite)
  where numero_orden_hycite is not null;
create index if not exists cargo_vuelta_cases_requiere_reconciliacion_idx
  on public.cargo_vuelta_cases (org_id, requiere_reconciliacion)
  where requiere_reconciliacion = true;
create or replace view public.v_cargo_vuelta_resumen as
with pagos as (
  select
    p.case_id,
    sum(p.monto)::numeric(12,2) as monto_recuperado,
    max(p.fecha_pago) as ultimo_pago_fecha
  from public.cob_pagos p
  where p.case_id is not null
  group by p.case_id
),
gestiones as (
  select
    g.case_id,
    max(g.created_at) as ultimo_contacto
  from public.cob_gestiones g
  where g.case_id is not null
  group by g.case_id
)
select
  cvc.id as case_id,
  cvc.org_id,
  cvc.cliente_id,
  cvc.tipo_caso,
  cvc.alias_operativo,
  cvc.estado,
  cvc.fecha_apertura,
  cvc.fecha_cierre,
  cvc.fecha_cargo_vuelta,
  cvc.monto_total,
  cvc.monto_devuelto,
  coalesce(p.monto_recuperado, 0)::numeric(12,2) as monto_recuperado,
  greatest(
    coalesce(cvc.monto_devuelto, cvc.monto_total, 0) - coalesce(p.monto_recuperado, 0),
    0
  )::numeric(12,2) as saldo_operativo,
  cvc.numero_cuenta_hycite,
  cvc.numero_orden_hycite,
  cvc.orden_hycite_id,
  cvc.documento_hycite_id,
  cvc.origen_cargo_vuelta,
  cvc.requiere_reconciliacion,
  cl.nombre,
  cl.apellido,
  cl.hycite_id,
  cl.estado_cuenta,
  cl.estado_cuenta_raw,
  cl.saldo_actual as saldo_hycite_snapshot,
  cl.telefono,
  cl.telefono_casa,
  cl.next_action as proxima_accion,
  cl.next_action_date as proxima_accion_fecha,
  g.ultimo_contacto,
  p.ultimo_pago_fecha
from public.cargo_vuelta_cases cvc
join public.clientes cl
  on cl.id = cvc.cliente_id
left join pagos p
  on p.case_id = cvc.id
left join gestiones g
  on g.case_id = cvc.id
where cvc.tipo_caso = 'cargo_vuelta';
comment on view public.v_cargo_vuelta_resumen is
  'Resumen operativo de casos devueltos por Hy-Cite con monto devuelto, pagos internos acumulados, saldo operativo calculado y snapshot financiero externo solo de referencia.';
commit;
