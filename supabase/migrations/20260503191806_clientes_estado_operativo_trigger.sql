-- 0079_clientes_estado_operativo_trigger.sql
-- Propósito: actualizar estado_operativo de clientes en base a contacto_actividades.
-- Reglas V1:
--   - resultado = 'promesa_pago'   y estado_operativo = 'en_riesgo' => 'recuperacion'
--   - resultado = 'pago_realizado' => 'activo' (desde cualquier estado)
-- Alcance: SOLO clientes (contacto_tipo = 'cliente').

begin;
create or replace function public.sync_cliente_estado_operativo_from_contacto_actividades()
returns trigger
language plpgsql
as $$
begin
  if new.contacto_tipo = 'cliente' then
    if new.resultado = 'promesa_pago' then
      update public.clientes
        set estado_operativo = 'recuperacion'
        where id = new.contacto_id
          and estado_operativo = 'en_riesgo';
    elsif new.resultado = 'pago_realizado' then
      update public.clientes
        set estado_operativo = 'activo'
        where id = new.contacto_id;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_sync_cliente_estado_operativo_from_contacto_actividades
  on public.contacto_actividades;
create trigger trg_sync_cliente_estado_operativo_from_contacto_actividades
after insert on public.contacto_actividades
for each row
execute function public.sync_cliente_estado_operativo_from_contacto_actividades();
commit;
