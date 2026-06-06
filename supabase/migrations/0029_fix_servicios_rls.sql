-- Migración para corregir las políticas RLS de la tabla servicios
begin;
-- 1. Eliminar políticas antiguas si existen para evitar conflictos (Lista exhaustiva)
drop policy if exists servicios_admin_all on public.servicios;
drop policy if exists servicios_distribuidor_read on public.servicios;
drop policy if exists servicios_distribuidor_all on public.servicios;
drop policy if exists servicios_vendedor_all on public.servicios;
drop policy if exists servicios_telemercadeo_read on public.servicios;
drop policy if exists servicios_telemercadeo_insert on public.servicios;
drop policy if exists servicios_org_member on public.servicios;
drop policy if exists "Enable all for admins" on public.servicios;
drop policy if exists "Enable read access for all users" on public.servicios;
-- 2. Política de Admin (Acceso total)
create policy servicios_admin_all on public.servicios
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
-- 3. Política de Distribuidor (Acceso total a su equipo y clientes)
create policy servicios_distribuidor_all on public.servicios
  for all to authenticated
  using (
    public.is_distribuidor() 
    and (
      -- Es el vendedor asignado al servicio
      vendedor_id = auth.uid()
      -- O el vendedor pertenece a su equipo
      or public.is_distribuidor_of(vendedor_id)
      -- O el cliente pertenece a su organización (o está sin asignar)
      or exists (
        select 1 from public.clientes c
        where c.id = servicios.cliente_id
          and (c.distribuidor_id = auth.uid() or c.distribuidor_id is null or public.is_distribuidor_of(c.vendedor_id))
      )
    )
  )
  with check (
    public.is_distribuidor()
    and (
      -- Solo puede asignar el servicio a sí mismo o a alguien de su equipo
      vendedor_id = auth.uid() 
      or public.is_distribuidor_of(vendedor_id)
      -- Y el cliente debe ser suyo, estar sin asignar, o ser de su equipo
      or exists (
        select 1 from public.clientes c
        where c.id = servicios.cliente_id
          and (c.distribuidor_id = auth.uid() or c.distribuidor_id is null or public.is_distribuidor_of(c.vendedor_id))
      )
    )
  );
-- 4. Política de Vendedor (Acceso a sus propios servicios o a los de sus clientes)
create policy servicios_vendedor_all on public.servicios
  for all to authenticated
  using (
    vendedor_id = auth.uid()
    or exists (
      select 1 from public.clientes c
      where c.id = servicios.cliente_id and (c.vendedor_id = auth.uid() or c.vendedor_id is null)
    )
  )
  with check (
    vendedor_id = auth.uid()
  );
-- 5. Limpieza de datos corruptos ("Actual" en dirección)
update public.clientes
set direccion = null, estado_region = null
where direccion = 'Actual' or estado_region = 'Actual';
commit;
