begin;
drop policy if exists ci_activaciones_select on public.ci_activaciones;
create policy ci_activaciones_select on public.ci_activaciones
for select to authenticated
using (
  owner_id = auth.uid()
  or representante_id = auth.uid()
  or exists (
    select 1
    from public.usuarios u
    where u.id = auth.uid()
      and u.rol = 'admin'
  )
  or exists (
    select 1
    from public.usuarios u
    join public.usuarios r on r.id = representante_id
    where u.id = auth.uid()
      and u.rol = 'distribuidor'
      and (
        (u.codigo_distribuidor is not null and r.codigo_distribuidor = u.codigo_distribuidor)
        or r.distribuidor_padre_id = u.id
      )
  )
);
drop policy if exists ci_referidos_select on public.ci_referidos;
create policy ci_referidos_select on public.ci_referidos
for select to authenticated
using (
  exists (
    select 1
    from public.ci_activaciones a
    where a.id = activacion_id
      and (
        a.owner_id = auth.uid()
        or a.representante_id = auth.uid()
        or exists (
          select 1
          from public.usuarios u
          where u.id = auth.uid()
            and u.rol = 'admin'
        )
        or exists (
          select 1
          from public.usuarios u
          join public.usuarios r on r.id = a.representante_id
          where u.id = auth.uid()
            and u.rol = 'distribuidor'
            and (
              (u.codigo_distribuidor is not null and r.codigo_distribuidor = u.codigo_distribuidor)
              or r.distribuidor_padre_id = u.id
            )
        )
      )
  )
);
commit;
