-- ============================================================
-- 0060_remove_foto_galeria_url.sql
-- Removes the ghost field foto_galeria_url from v_catalogo_vendedor view.
-- ============================================================

begin;
-- Redefine the view without the redundant field
drop view if exists public.v_catalogo_vendedor;
create view public.v_catalogo_vendedor
  with (security_invoker = true)
as
  select
    p.id,
    p.codigo,
    p.nombre,
    p.categoria,
    p.categoria_principal,
    p.subcategoria,
    p.linea_producto,
    p.precio        as precio_publico,
    p.foto_url      as foto_principal_url,
    p.activo,
    p.estado,
    p.descripcion_corta,
    p.descripcion_larga,
    p.beneficios,
    p.reemplazado_por_id,
    r.codigo        as reemplazado_por_codigo,
    r.nombre        as reemplazado_por_nombre,
    p.cuota_minima,
    p.con_financiamiento,
    p.visible_catalogo
  from public.productos p
  left join public.productos r on r.id = p.reemplazado_por_id
  where p.activo = true;
grant select on public.v_catalogo_vendedor to authenticated;
commit;
