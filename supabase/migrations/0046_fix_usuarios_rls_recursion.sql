-- ============================================================
-- 0046_fix_usuarios_rls_recursion.sql
-- La policy usuarios_org_read en 0043 tenía una subquery
-- recursiva sobre la misma tabla usuarios, lo que puede
-- causar que la query falle y currentUser sea null en el UI.
-- Fix: usar una función security definer que bypasses RLS.
-- ============================================================

begin;
create or replace function public.current_user_is_not_tele()
returns boolean
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid()
      and rol not in ('telemercadeo', 'supervisor_telemercadeo')
  );
$$;
drop policy if exists usuarios_org_read on public.usuarios;
create policy usuarios_org_read on public.usuarios
  for select to authenticated
  using (public.current_user_is_not_tele());
commit;
