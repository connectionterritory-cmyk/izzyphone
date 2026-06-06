-- Migration 0023: Allow all authenticated users to read basic user info.
-- Needed so roles like telemercadeo and vendedor can resolve user names
-- (vendedor_id, distribuidor_id) throughout the app.
-- The existing policies (admin_all, dist_team_select, usuarios_self_read)
-- remain in place; this adds a broader SELECT for the authenticated role.
begin;
drop policy if exists usuarios_read_all on public.usuarios;
create policy usuarios_read_all on public.usuarios
  for select to authenticated
  using (true);
commit;
