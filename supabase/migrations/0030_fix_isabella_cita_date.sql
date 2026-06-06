-- Fix: Isabella Caicedo appointment was saved as 2026-04-03 (April 3)
-- Correct date is 2026-03-04 (March 4)
update public.servicios
set fecha_servicio = '2026-03-04'
where fecha_servicio = '2026-04-03'
  and cliente_id in (
    select id from public.clientes
    where nombre ilike '%isabella%'
      and apellido ilike '%caicedo%'
  );
