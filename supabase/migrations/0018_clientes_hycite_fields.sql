begin;
-- 1. Add missing columns to clientes (safe — skips if already exists)
alter table public.clientes
  add column if not exists hycite_id              text,
  add column if not exists tipo_cliente           text,
  add column if not exists telefono_casa          text,
  add column if not exists ciudad                 text,
  add column if not exists estado_region          text,
  add column if not exists codigo_postal          text,
  add column if not exists monto_moroso           numeric(12,2) default 0,
  add column if not exists dias_atraso            integer       default 0,
  add column if not exists estado_cuenta          text,
  add column if not exists elegible_addon         boolean       default true,
  add column if not exists fecha_ultimo_pedido    date,
  add column if not exists origen                 text,
  add column if not exists codigo_vendedor_hycite text,
  add column if not exists codigo_dist_hycite     text,
  add column if not exists nivel                  integer       default 1;
-- 2. Partial unique index on hycite_id (NULL-safe — avoids constraint failures
--    on existing rows that have no hycite_id yet)
create unique index if not exists clientes_hycite_id_uidx
  on public.clientes (hycite_id)
  where hycite_id is not null;
-- 3. Create import history table
create table if not exists public.importaciones_hycite (
  id                      uuid        primary key default gen_random_uuid(),
  org_id                  uuid,
  importado_por           uuid references public.usuarios(id) on delete set null,
  tipo_cuenta             text,
  archivo_nombre          text,
  total_registros         integer not null default 0,
  registros_nuevos        integer not null default 0,
  registros_actualizados  integer not null default 0,
  registros_error         integer not null default 0,
  created_at              timestamptz not null default now()
);
alter table public.importaciones_hycite enable row level security;
drop policy if exists importaciones_hycite_select on public.importaciones_hycite;
drop policy if exists importaciones_hycite_insert on public.importaciones_hycite;
-- Only admin/distribuidor can read import history
create policy importaciones_hycite_select on public.importaciones_hycite
  for select to authenticated
  using (
    exists (
      select 1 from public.usuarios u
      where u.id = auth.uid()
        and u.rol in ('admin', 'distribuidor')
    )
  );
-- Any authenticated user can insert their own import run
create policy importaciones_hycite_insert on public.importaciones_hycite
  for insert to authenticated
  with check (importado_por = auth.uid());
commit;
