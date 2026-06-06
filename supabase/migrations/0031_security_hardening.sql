-- ============================================================
-- 0031_security_hardening.sql
-- Fixes flagged by Supabase security linter:
--   1. Add SET search_path to all helper functions
--   2. Restrict programas INSERT policy to admin only
-- ============================================================

begin;
-- ── 1. is_admin() ───────────────────────────────────────────
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and rol = 'admin'
  );
$$;
-- ── 2. is_distribuidor() ────────────────────────────────────
create or replace function public.is_distribuidor()
returns boolean
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and rol = 'distribuidor'
  );
$$;
-- ── 3. is_distribuidor_of(uuid) ─────────────────────────────
-- Was missing search_path
create or replace function public.is_distribuidor_of(vendor_id uuid)
returns boolean
language sql
stable
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios u
    where u.id = vendor_id
      and u.distribuidor_padre_id = auth.uid()
  );
$$;
-- ── 4. is_vendedor() ────────────────────────────────────────
-- Was missing search_path
create or replace function public.is_vendedor()
returns boolean
language sql
stable
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid()
      and rol in ('vendedor', 'telemercadeo')
  );
$$;
-- ── 5. get_distributor_phone() ──────────────────────────────
-- Already had search_path = 'public' — add 'extensions'
create or replace function public.get_distributor_phone()
returns text
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  _rol    public.usuario_rol;
  _tel    text;
  _dist   uuid;
begin
  select rol, telefono, distribuidor_padre_id
    into _rol, _tel, _dist
  from public.usuarios
  where id = auth.uid();

  if _rol in ('admin', 'distribuidor') then
    return coalesce(_tel, '');
  end if;

  if _dist is not null then
    select telefono into _tel
    from public.usuarios
    where id = _dist;
    return coalesce(_tel, '');
  end if;

  return coalesce(_tel, '');
end;
$$;
grant execute on function public.get_distributor_phone() to authenticated;
-- ── 8. Programas INSERT policy ──────────────────────────────
-- The linter flagged "programas_insert_auth" with WITH CHECK (true).
-- Drop the overly permissive policy and rely on programas_admin_all
-- for inserts (which already restricts to admin).
drop policy if exists programas_insert_auth on public.programas;
-- Ensure the admin-only insert path is clean:
-- programas_admin_all covers INSERT for admins already.
-- If it doesn't exist, create it narrowly:
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'programas'
      and policyname = 'programas_admin_all'
  ) then
    execute $p$
      create policy programas_admin_all on public.programas
        for all to authenticated
        using (
          exists (
            select 1 from public.usuarios
            where id = auth.uid() and rol = 'admin'
          )
        )
        with check (
          exists (
            select 1 from public.usuarios
            where id = auth.uid() and rol = 'admin'
          )
        );
    $p$;
  end if;
end;
$$;
commit;
