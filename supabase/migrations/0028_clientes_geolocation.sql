-- Migration 0028: Clientes Geolocation & Unified Agenda View
begin;
-- 1. Add geolocation columns to clientes
alter table public.clientes
  add column if not exists lat numeric,
  add column if not exists lng numeric;
-- 2. Add time columns for agenda sorting
alter table public.servicios
  add column if not exists hora_cita time without time zone;
alter table public.programa_4en14_referidos
  add column if not exists hora_demo time without time zone;
-- 3. Create Unified Agenda View
-- Unifies 'servicios' and 'programa_4en14_referidos'
create or replace view public.v_agenda_hoy as
select 
  s.id as agenda_id,
  s.vendedor_id,
  s.fecha_servicio as fecha,
  s.hora_cita as hora,
  'servicio' as tipo,
  s.tipo_servicio as subtipo,
  c.nombre || ' ' || c.apellido as cliente_nombre,
  c.telefono as cliente_telefono,
  c.direccion,
  c.ciudad,
  c.estado_region,
  s.observaciones as notas,
  exists (
    select 1 
    from public.servicio_componentes sc 
    where sc.servicio_id = s.id
  ) as completado
from public.servicios s
join public.clientes c on s.cliente_id = c.id

union all

select 
  r.id as agenda_id,
  p.vendedor_id,
  r.fecha_demo as fecha,
  r.hora_demo as hora,
  'demo' as tipo,
  r.estado_presentacion::text as subtipo,
  r.nombre as cliente_nombre,
  r.telefono as cliente_telefono,
  null as direccion, 
  null as ciudad,
  null as estado_region,
  r.notas as notas,
  (r.estado_presentacion in ('show', 'demo_calificada', 'venta')) as completado
from public.programa_4en14_referidos r
join public.programa_4en14 p on r.programa_id = p.id;
-- Grant access to the view
grant select on public.v_agenda_hoy to authenticated;
commit;
