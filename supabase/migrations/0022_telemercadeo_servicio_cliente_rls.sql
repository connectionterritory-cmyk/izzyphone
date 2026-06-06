begin;
-- Clientes: permitir lectura a telemercadeo segun asignacion de vendedor/distribuidor
drop policy if exists clientes_telemercadeo_read on public.clientes;
create policy clientes_telemercadeo_read on public.clientes
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.tele_vendedor_assignments t
      where t.tele_id = auth.uid()
        and (t.vendedor_id = clientes.vendedor_id or t.vendedor_id = clientes.distribuidor_id)
    )
  );
-- Equipos instalados: lectura para telemercadeo
drop policy if exists equipos_instalados_telemercadeo_read on public.equipos_instalados;
create policy equipos_instalados_telemercadeo_read on public.equipos_instalados
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = equipos_instalados.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
-- Componentes de equipo: lectura para telemercadeo
drop policy if exists componentes_equipo_telemercadeo_read on public.componentes_equipo;
create policy componentes_equipo_telemercadeo_read on public.componentes_equipo
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.equipos_instalados e
      join public.clientes c on c.id = e.cliente_id
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where e.id = componentes_equipo.equipo_instalado_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
-- Servicios: lectura para telemercadeo
drop policy if exists servicios_telemercadeo_read on public.servicios;
create policy servicios_telemercadeo_read on public.servicios
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = servicios.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
-- Servicios: permitir insertar citas/servicios a telemercadeo
drop policy if exists servicios_telemercadeo_insert on public.servicios;
create policy servicios_telemercadeo_insert on public.servicios
  for insert to authenticated
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = servicios.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
        and (
          servicios.vendedor_id is null
          or servicios.vendedor_id = c.vendedor_id
          or servicios.vendedor_id = c.distribuidor_id
          or servicios.vendedor_id = t.vendedor_id
        )
    )
  );
-- Notas RP: lectura e insercion para telemercadeo
drop policy if exists notasrp_telemercadeo_read on public.notasrp;
create policy notasrp_telemercadeo_read on public.notasrp
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = notasrp.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
drop policy if exists notasrp_telemercadeo_insert on public.notasrp;
create policy notasrp_telemercadeo_insert on public.notasrp
  for insert to authenticated
  with check (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid() and u.rol = 'telemercadeo'
    )
    or
    exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t on t.tele_id = auth.uid()
      where c.id = notasrp.cliente_id
        and (t.vendedor_id = c.vendedor_id or t.vendedor_id = c.distribuidor_id)
    )
  );
commit;
