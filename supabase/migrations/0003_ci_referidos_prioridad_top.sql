begin;
alter table public.ci_referidos
  add column if not exists prioridad_top boolean default false,
  add column if not exists asignado_a uuid;
create or replace function public.ci_referidos_enforce_prioridad_top()
returns trigger
language plpgsql
as $$
declare
  _top_count integer;
  _rep_id uuid;
begin
  if new.prioridad_top is true then
    select count(*) into _top_count
    from public.ci_referidos
    where activacion_id = new.activacion_id
      and prioridad_top is true
      and (tg_op = 'INSERT' or id <> new.id);

    if _top_count >= 4 then
      raise exception 'Maximo 4 referidos con prioridad_top por activacion.';
    end if;

    if tg_op = 'INSERT' or (old.prioridad_top is distinct from true) then
      select representante_id
      into _rep_id
      from public.ci_activaciones
      where id = new.activacion_id;

      new.asignado_a := _rep_id;
    end if;
  end if;

  return new;
end;
$$;
drop trigger if exists ci_referidos_prioridad_top_guard on public.ci_referidos;
create trigger ci_referidos_prioridad_top_guard
before insert or update on public.ci_referidos
for each row
execute function public.ci_referidos_enforce_prioridad_top();
commit;
