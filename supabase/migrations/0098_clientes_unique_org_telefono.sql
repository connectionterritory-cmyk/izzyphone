-- ============================================================
-- 0098: Deduplicación de clientes + unique constraint por
--       (org_id, telefono) para idempotencia de importaciones OCR
--
-- Problema:
--   Pipeline OCR generó 90 filas duplicadas (Rosa Ugalde, telefono=NULL).
--   Pre-existing duplicates con telefono≠NULL tienen FK en llamadas_telemercadeo.
--
-- Estrategia:
--   1. Identificar survivor por (org_id, telefono): prioriza el que tiene
--      actividad (llamadas), luego el más antiguo (registro original).
--   2. Redirigir FK en llamadas_telemercadeo al survivor antes de eliminar.
--   3. Eliminar duplicados con telefono≠NULL.
--   4. Eliminar duplicados OCR con telefono=NULL (no tienen FKs activos).
--   5. Agregar UNIQUE(org_id, telefono).
--
-- ROLLBACK:
--   ALTER TABLE public.clientes
--     DROP CONSTRAINT IF EXISTS clientes_org_telefono_uidx;
-- ============================================================

begin;
-- ── 1 + 2. Redirigir llamadas_telemercadeo al survivor antes de eliminar duplicados

WITH activity_ranked AS (
  SELECT
    c.id,
    c.org_id,
    c.telefono,
    c.created_at,
    EXISTS (
      SELECT 1 FROM public.llamadas_telemercadeo lt WHERE lt.cliente_id = c.id
    ) AS has_activity
  FROM public.clientes c
  WHERE c.telefono IS NOT NULL
),
survivors AS (
  SELECT DISTINCT ON (org_id, telefono)
    id   AS survivor_id,
    org_id,
    telefono
  FROM activity_ranked
  ORDER BY org_id, telefono,
    has_activity DESC,      -- registros con actividad primero
    created_at  ASC NULLS LAST  -- luego el más antiguo (registro original)
),
dup_to_survivor AS (
  SELECT c.id AS dup_id, s.survivor_id
  FROM public.clientes c
  JOIN survivors s
    ON  c.org_id   = s.org_id
    AND c.telefono = s.telefono
  WHERE c.id != s.survivor_id
)
UPDATE public.llamadas_telemercadeo lt
SET    cliente_id = dts.survivor_id
FROM   dup_to_survivor dts
WHERE  lt.cliente_id = dts.dup_id;
-- ── 3. Eliminar duplicados con telefono≠NULL (FKs ya redirigidas)

WITH activity_ranked AS (
  SELECT
    c.id,
    c.org_id,
    c.telefono,
    c.created_at,
    EXISTS (
      SELECT 1 FROM public.llamadas_telemercadeo lt WHERE lt.cliente_id = c.id
    ) AS has_activity
  FROM public.clientes c
  WHERE c.telefono IS NOT NULL
),
survivors AS (
  SELECT DISTINCT ON (org_id, telefono) id AS survivor_id
  FROM activity_ranked
  ORDER BY org_id, telefono, has_activity DESC, created_at ASC NULLS LAST
)
DELETE FROM public.clientes
WHERE  telefono IS NOT NULL
  AND  id NOT IN (SELECT survivor_id FROM survivors);
-- ── 4. Eliminar duplicados OCR con telefono=NULL por (org_id, nombre, apellido)
-- Conserva el más antiguo (primer registro real); los OCR duplicados no tienen FKs

WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY org_id,
                        lower(trim(coalesce(nombre, ''))),
                        lower(trim(coalesce(apellido, '')))
           ORDER BY created_at ASC NULLS LAST
         ) AS rn
  FROM public.clientes
  WHERE telefono IS NULL
)
DELETE FROM public.clientes
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);
-- ── 5. Unique constraint en (org_id, telefono)
ALTER TABLE public.clientes
  ADD CONSTRAINT clientes_org_telefono_uidx
  UNIQUE (org_id, telefono);
comment on constraint clientes_org_telefono_uidx on public.clientes is
  'Idempotencia OCR: un teléfono por organización. NULL excluido de unicidad.';
commit;
