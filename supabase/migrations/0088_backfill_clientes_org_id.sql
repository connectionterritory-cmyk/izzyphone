-- ============================================================
-- 0088: Backfill org_id en clientes
-- ============================================================
-- Todos los clientes importados desde Hy-Cite quedaron con org_id NULL
-- porque la columna se agregó en 0001 sin backfill para registros legacy.
-- El módulo de cartera depende de cliente.org_id para RLS y para
-- guardar gestiones (cob_gestiones.cliente_id → clientes.org_id).
--
-- Este backfill es seguro en proyectos single-tenant donde el org
-- operativo es el singleton 00000000-0000-0000-0000-000000000001.
--
-- ROLLBACK:
--   UPDATE public.clientes
--   SET org_id = NULL
--   WHERE org_id = '00000000-0000-0000-0000-000000000001';
--   (Solo seguro si no existe otra fuente de org_id en esta tabla)
-- ============================================================

UPDATE public.clientes
SET org_id = '00000000-0000-0000-0000-000000000001'
WHERE org_id IS NULL;
