-- 0109: backfill cob_gestiones desde llamadas_telemercadeo para clientes huérfanos
--
-- Contexto:
--   TelemercadeoCallModal hacía dual-write hasta 2026-04-25 (commit 9daef48).
--   16 clientes tienen historial SOLO en llamadas_telemercadeo porque sus registros
--   se crearon antes del dual-write. Esta migración los copia a cob_gestiones para
--   que el historial sea visible desde la vista canónica.
--
-- Criterio de huérfano:
--   cliente_id presente en llamadas_telemercadeo pero ausente en cob_gestiones.
--
-- Idempotencia:
--   Usa NOT EXISTS para no duplicar si ya existe alguna gestión para ese cliente.
--   Seguro correrla más de una vez.
--
-- Rollback:
--   delete from public.cob_gestiones
--   where notas like '%[migrado desde llamadas_telemercadeo%';

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
  'Llamada'                                                         as tipo_gestion,
  lt.resultado,
  lt.monto_prometido                                                as monto_comprometido,
  lt.followup_at                                                    as fecha_compromiso,
  coalesce(lt.notas, '') || ' [migrado desde llamadas_telemercadeo ' || lt.id::text || ']' as notas,
  lt.telemercadista_id                                              as gestionado_por,
  lt.created_at
from public.llamadas_telemercadeo lt
where lt.org_id is not null
  and not exists (
    select 1
    from public.cob_gestiones cg
    where cg.cliente_id = lt.cliente_id
  );
