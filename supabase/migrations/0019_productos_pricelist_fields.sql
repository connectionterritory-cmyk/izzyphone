alter table public.productos
  add column if not exists categoria_compra text,
  add column if not exists categoria_principal text,
  add column if not exists subcategoria text,
  add column if not exists linea_producto text,
  add column if not exists recargo_arancelario numeric default 0;
