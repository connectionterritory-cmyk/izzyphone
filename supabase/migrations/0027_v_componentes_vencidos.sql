-- Migration 0027: Vista v_componentes_vencidos para segmento MarketingFlow.
-- Una fila por componente vencido (fecha_proximo_cambio <= hoy, activo = true).
-- El frontend agrupa por cliente_id para consolidar en un mensaje por cliente.
-- security_invoker = true → RLS de clientes/equipos/componentes se aplica al caller.
begin;
create or replace view public.v_componentes_vencidos
  with (security_invoker = true)
as
select
  c.id                            as cliente_id,
  c.nombre,
  c.apellido,
  c.telefono,
  c.vendedor_id,
  c.distribuidor_id,
  e.id                            as equipo_id,
  e.numero_serie,
  comp.id                         as componente_id,
  comp.nombre_componente,
  comp.tipo_componente,
  comp.ciclo_meses,
  comp.fecha_ultimo_cambio,
  comp.fecha_proximo_cambio
from public.componentes_equipo comp
join public.equipos_instalados e  on e.id    = comp.equipo_instalado_id
join public.clientes           c  on c.id    = e.cliente_id
where comp.activo                = true
  and comp.fecha_proximo_cambio  is not null
  and comp.fecha_proximo_cambio  <= current_date;
commit;
-- ROLLBACK:
-- begin;
-- drop view if exists public.v_componentes_vencidos;
-- commit;;
