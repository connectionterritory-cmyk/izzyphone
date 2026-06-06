-- 0077_contacto_actividades_lead_state_trigger.sql
-- Purpose: mantener estado_pipeline consistente cuando se registra una actividad de contacto.
-- Alcance: SOLO leads (contacto_tipo = 'lead'). Clientes no aplican (usan estado_cuenta).
-- Regla mínima: si el lead estaba en 'nuevo', pasar a 'contactado' al insertar actividad.
-- Nota: este trigger es extensible con más transiciones en el futuro.

begin;
create or replace function public.sync_lead_estado_from_contacto_actividades()
returns trigger
language plpgsql
as $$
begin
  if new.contacto_tipo = 'lead' then
    update public.leads
      set estado_pipeline = 'contactado'
      where id = new.contacto_id
        and estado_pipeline = 'nuevo';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_sync_lead_estado_from_contacto_actividades
  on public.contacto_actividades;
create trigger trg_sync_lead_estado_from_contacto_actividades
after insert on public.contacto_actividades
for each row
execute function public.sync_lead_estado_from_contacto_actividades();
commit;
