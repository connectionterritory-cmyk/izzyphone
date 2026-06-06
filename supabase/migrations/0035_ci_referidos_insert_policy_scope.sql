begin;
-- Expand ci_referidos INSERT policy to allow admin and distribuidor (same scope as SELECT).
-- No trigger: frontend always sends gestionado_por_usuario_id and modo_gestion explicitly.

drop policy if exists ci_referidos_insert on public.ci_referidos;
create policy ci_referidos_insert on public.ci_referidos
for insert to authenticated
with check (
  exists (
    select 1
    from public.ci_activaciones a
    where a.id = activacion_id
      and (
        a.owner_id = auth.uid()
        or a.representante_id = auth.uid()
        or exists (
          select 1 from public.usuarios u
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
