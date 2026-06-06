-- ============================================================
-- 0089: Agregar campos faltantes a clientes para importación
--       de imágenes vía n8n + Claude Vision
--
-- Campos nuevos:
--   email              — correo electrónico del cliente
--   credito_disponible — límite de crédito disponible (Hy-Cite)
--   metodo_pago        — método de pago registrado (Cheque, etc.)
--   fecha_orden        — fecha de la orden original (Hy-Cite)
--   fecha_cierre       — fecha de cierre de cuenta (Hy-Cite)
--
-- ROLLBACK:
--   alter table public.clientes
--     drop column if exists email,
--     drop column if exists credito_disponible,
--     drop column if exists metodo_pago,
--     drop column if exists fecha_orden,
--     drop column if exists fecha_cierre;
-- ============================================================

begin;
alter table public.clientes
  add column if not exists email              text,
  add column if not exists credito_disponible numeric(12,2),
  add column if not exists metodo_pago        text,
  add column if not exists fecha_orden        date,
  add column if not exists fecha_cierre       date;
commit;
