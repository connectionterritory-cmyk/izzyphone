insert into public.cob_gestiones (
  org_id,
  cliente_id,
  tipo_gestion,
  resultado,
  monto_comprometido,
  fecha_compromiso,
  notas,
  gestionado_por,
  created_at
)
select
  lt.org_id,
  lt.cliente_id,
  'Llamada'                                                                           as tipo_gestion,
  lt.resultado,
  lt.monto_prometido                                                                  as monto_comprometido,
  coalesce(lt.followup_at, lt.followup_fecha)                                         as fecha_compromiso,
  coalesce(lt.notas, '') || ' [migrado desde llamadas_telemercadeo ' || lt.id::text || ']' as notas,
  lt.telemercadista_id                                                                as gestionado_por,
  lt.created_at
from public.llamadas_telemercadeo lt
where lt.resultado = 'pago_prometido'
  and lt.org_id is not null
  and not exists (
    select 1
    from public.cob_gestiones cg
    where cg.notas like '%[migrado desde llamadas_telemercadeo ' || lt.id::text || '%'
  );;
