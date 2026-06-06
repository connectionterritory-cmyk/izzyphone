-- ============================================================
-- 0111_ventas_multitenancy_reproducibility.sql
-- Reproducibility + multitenancy hardening for ventas legacy
--
-- Goals:
--   1. Add org_id to public.ventas without breaking legacy rows.
--   2. Backfill ventas.org_id from vendedor_id -> usuarios.org_id,
--      then cliente_id -> clientes.org_id, then default org only
--      for unresolved legacy data where the repo already defines a
--      clear canonical org constant.
--   3. Align venta_items.org_id and venta_transacciones.org_id
--      with ventas.org_id and keep them in sync.
--   4. Rebuild RLS so access is tenant-aware and child tables
--      inherit security from ventas.
--   5. Document the legacy naming of venta_transacciones.cantidad.
-- ============================================================

begin;
-- ------------------------------------------------------------------
-- 0. Canonical default org documented in existing migrations:
--    00000000-0000-0000-0000-000000000001
--    Used only for unresolved legacy rows during backfill.
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- 1. ventas.org_id
-- ------------------------------------------------------------------
alter table public.ventas
  add column if not exists org_id uuid;
comment on column public.ventas.org_id is
  'Tenant owner organization. Backfilled from vendedor_id -> usuarios.org_id, then cliente_id -> clientes.org_id, with default org fallback only for unresolved legacy data.';
create index if not exists ventas_org_id_idx
  on public.ventas (org_id);
create index if not exists ventas_org_id_vendedor_id_idx
  on public.ventas (org_id, vendedor_id);
-- ------------------------------------------------------------------
-- 2. Helper functions + triggers to derive/sync org_id
--    Keep inserts working while legacy frontend still omits org_id.
-- ------------------------------------------------------------------
create or replace function public.resolve_venta_org_id(
  p_vendedor_id uuid,
  p_cliente_id uuid
)
returns uuid
language plpgsql
stable
set search_path = 'public', 'extensions'
as $$
declare
  v_org_id uuid;
begin
  if p_vendedor_id is not null then
    select u.org_id
      into v_org_id
    from public.usuarios u
    where u.id = p_vendedor_id
    limit 1;
  end if;

  if v_org_id is null and p_cliente_id is not null then
    select c.org_id
      into v_org_id
    from public.clientes c
    where c.id = p_cliente_id
    limit 1;
  end if;

  return v_org_id;
end;
$$;
create or replace function public.trg_set_ventas_org_id()
returns trigger
language plpgsql
set search_path = 'public', 'extensions'
as $$
begin
  if new.org_id is null then
    new.org_id := public.resolve_venta_org_id(new.vendedor_id, new.cliente_id);
  end if;

  return new;
end;
$$;
create or replace function public.trg_set_venta_child_org_id()
returns trigger
language plpgsql
set search_path = 'public', 'extensions'
as $$
declare
  v_parent_org_id uuid;
begin
  select v.org_id
    into v_parent_org_id
  from public.ventas v
  where v.id = new.venta_id;

  if v_parent_org_id is not null
     and new.org_id is not null
     and new.org_id is distinct from v_parent_org_id then
    raise exception 'org_id mismatch for venta_id %', new.venta_id;
  end if;

  new.org_id := coalesce(v_parent_org_id, new.org_id);
  return new;
end;
$$;
create or replace function public.trg_sync_ventas_children_org_id()
returns trigger
language plpgsql
set search_path = 'public', 'extensions'
as $$
begin
  if tg_op = 'INSERT' or new.org_id is distinct from old.org_id then
    update public.venta_items
       set org_id = new.org_id
     where venta_id = new.id
       and org_id is distinct from new.org_id;

    update public.venta_transacciones
       set org_id = new.org_id
     where venta_id = new.id
       and org_id is distinct from new.org_id;
  end if;

  return new;
end;
$$;
drop trigger if exists set_ventas_org_id on public.ventas;
create trigger set_ventas_org_id
before insert or update of org_id, vendedor_id, cliente_id
on public.ventas
for each row
execute function public.trg_set_ventas_org_id();
drop trigger if exists sync_ventas_children_org_id on public.ventas;
create trigger sync_ventas_children_org_id
after insert or update of org_id
on public.ventas
for each row
execute function public.trg_sync_ventas_children_org_id();
drop trigger if exists set_venta_items_org_id on public.venta_items;
create trigger set_venta_items_org_id
before insert or update of org_id, venta_id
on public.venta_items
for each row
execute function public.trg_set_venta_child_org_id();
drop trigger if exists set_venta_transacciones_org_id on public.venta_transacciones;
create trigger set_venta_transacciones_org_id
before insert or update of org_id, venta_id
on public.venta_transacciones
for each row
execute function public.trg_set_venta_child_org_id();
-- ------------------------------------------------------------------
-- 3. Backfill org_id on ventas and align child tables
-- ------------------------------------------------------------------
do $$
declare
  default_org uuid := '00000000-0000-0000-0000-000000000001';
begin
  update public.ventas v
     set org_id = coalesce(
       public.resolve_venta_org_id(v.vendedor_id, v.cliente_id),
       default_org
     )
   where v.org_id is null;
end $$;
update public.venta_items vi
   set org_id = v.org_id
  from public.ventas v
 where vi.venta_id = v.id
   and vi.org_id is distinct from v.org_id;
update public.venta_transacciones vt
   set org_id = v.org_id
  from public.ventas v
 where vt.venta_id = v.id
   and vt.org_id is distinct from v.org_id;
create index if not exists venta_items_org_id_idx
  on public.venta_items (org_id);
create index if not exists venta_items_org_id_venta_id_idx
  on public.venta_items (org_id, venta_id);
create index if not exists venta_transacciones_org_id_idx
  on public.venta_transacciones (org_id);
create index if not exists venta_transacciones_org_id_venta_id_idx
  on public.venta_transacciones (org_id, venta_id);
comment on column public.venta_transacciones.cantidad is
  'Legacy name. Monetary amount of the transaction line, stored as numeric(12,2); not a unit quantity.';
-- ------------------------------------------------------------------
-- 4. RLS for ventas (tenant-aware)
--    Distributor scope is restricted to same-org rows plus direct
--    ownership/team relationships when derivable from vendedor/cliente.
-- ------------------------------------------------------------------
alter table public.ventas enable row level security;
alter table public.venta_items enable row level security;
alter table public.venta_transacciones enable row level security;
drop policy if exists ventas_admin_all on public.ventas;
drop policy if exists ventas_distribuidor_all on public.ventas;
drop policy if exists ventas_distribuidor_read on public.ventas;
drop policy if exists ventas_vendedor_all on public.ventas;
drop policy if exists ventas_supervisor_tele_read on public.ventas;
drop policy if exists ventas_tele_read on public.ventas;
create policy ventas_admin_all
  on public.ventas
  for all
  to authenticated
  using (
    public.is_admin()
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
  )
  with check (
    public.is_admin()
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
  );
create policy ventas_distribuidor_all
  on public.ventas
  for all
  to authenticated
  using (
    public.is_distribuidor()
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and (
      vendedor_id = auth.uid()
      or public.is_distribuidor_of(vendedor_id)
      or exists (
        select 1
        from public.clientes c
        where c.id = ventas.cliente_id
          and c.org_id = ventas.org_id
          and (
            c.distribuidor_id = auth.uid()
            or c.vendedor_id = auth.uid()
            or public.is_distribuidor_of(c.vendedor_id)
          )
      )
    )
  )
  with check (
    public.is_distribuidor()
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and (
      vendedor_id = auth.uid()
      or public.is_distribuidor_of(vendedor_id)
      or exists (
        select 1
        from public.clientes c
        where c.id = ventas.cliente_id
          and c.org_id = ventas.org_id
          and (
            c.distribuidor_id = auth.uid()
            or c.vendedor_id = auth.uid()
            or public.is_distribuidor_of(c.vendedor_id)
          )
      )
    )
  );
create policy ventas_vendedor_all
  on public.ventas
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.rol = 'vendedor'
    )
    and vendedor_id = auth.uid()
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
  );
create policy ventas_supervisor_tele_read
  on public.ventas
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.rol = 'supervisor_telemercadeo'
    )
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
  );
create policy ventas_tele_read
  on public.ventas
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.usuarios u
      where u.id = auth.uid()
        and u.rol = 'telemercadeo'
    )
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and exists (
      select 1
      from public.clientes c
      join public.tele_vendedor_assignments t
        on t.tele_id = auth.uid()
      where c.id = ventas.cliente_id
        and c.org_id = ventas.org_id
        and (
          t.vendedor_id = c.vendedor_id
          or t.vendedor_id = c.distribuidor_id
        )
    )
  );
-- ------------------------------------------------------------------
-- 5. Child table RLS inherits from ventas
--    The parent ventas row must be visible and org_id must match.
-- ------------------------------------------------------------------
drop policy if exists venta_items_admin_all on public.venta_items;
drop policy if exists venta_items_distribuidor_all on public.venta_items;
drop policy if exists venta_items_supervisor_tele_read on public.venta_items;
drop policy if exists venta_items_tele_read on public.venta_items;
drop policy if exists venta_items_vendedor_all on public.venta_items;
drop policy if exists venta_items_inherit_ventas on public.venta_items;
create policy venta_items_inherit_ventas
  on public.venta_items
  for all
  to authenticated
  using (
    org_id is not null
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and exists (
      select 1
      from public.ventas v
      where v.id = venta_items.venta_id
        and v.org_id = venta_items.org_id
    )
  )
  with check (
    org_id is not null
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and exists (
      select 1
      from public.ventas v
      where v.id = venta_items.venta_id
        and v.org_id = venta_items.org_id
    )
  );
drop policy if exists venta_transacciones_admin_all on public.venta_transacciones;
drop policy if exists venta_transacciones_distribuidor_all on public.venta_transacciones;
drop policy if exists venta_transacciones_supervisor_tele_read on public.venta_transacciones;
drop policy if exists venta_transacciones_tele_read on public.venta_transacciones;
drop policy if exists venta_transacciones_vendedor_all on public.venta_transacciones;
drop policy if exists venta_transacciones_inherit_ventas on public.venta_transacciones;
create policy venta_transacciones_inherit_ventas
  on public.venta_transacciones
  for all
  to authenticated
  using (
    org_id is not null
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and exists (
      select 1
      from public.ventas v
      where v.id = venta_transacciones.venta_id
        and v.org_id = venta_transacciones.org_id
    )
  )
  with check (
    org_id is not null
    and org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
    )
    and exists (
      select 1
      from public.ventas v
      where v.id = venta_transacciones.venta_id
        and v.org_id = venta_transacciones.org_id
    )
  );
commit;
