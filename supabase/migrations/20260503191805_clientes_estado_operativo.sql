-- 0078_clientes_estado_operativo.sql
-- Propósito: agregar estado_operativo a clientes (retención/ciclo de vida).
-- Estados: activo | en_riesgo | recuperacion | inactivo | cancelado
-- Backfill:
--   - estado_cuenta = 'cancelacion_total' => cancelado
--   - estado_cuenta = 'inactivo'          => inactivo
--   - estado_cuenta = 'actual' or null    => activo

begin;
alter table public.clientes
  add column if not exists estado_operativo text;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.clientes'::regclass
      and conname = 'clientes_estado_operativo_values'
  ) then
    alter table public.clientes
      add constraint clientes_estado_operativo_values
      check (
        estado_operativo is null
        or estado_operativo in ('activo', 'en_riesgo', 'recuperacion', 'inactivo', 'cancelado')
      );
  end if;
end $$;
update public.clientes
set estado_operativo = case
  when estado_cuenta = 'cancelacion_total' then 'cancelado'
  when estado_cuenta = 'inactivo' then 'inactivo'
  else 'activo'
end
where estado_operativo is null;
create index if not exists clientes_estado_operativo_idx
  on public.clientes (estado_operativo);
commit;
