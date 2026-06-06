begin;
alter table public.clientes
  add column if not exists ultima_fecha_pago date;
commit;
