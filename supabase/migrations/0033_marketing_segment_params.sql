-- Agrega soporte para parámetros de segmento en campañas (ej. mes de cumpleaños)
alter table public.mk_campaigns
  add column if not exists segment_params jsonb default '{}'::jsonb;
-- Refuerza la política de mk_messages para asegurar que el usuario es dueño de la campaña
drop policy if exists "mk_messages_owner_all" on public.mk_messages;
create policy "mk_messages_owner_all"
  on public.mk_messages
  for all
  to authenticated
  using (
    owner_id = auth.uid()
  )
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.mk_campaigns c
      where c.id = mk_messages.campaign_id
        and c.owner_id = auth.uid()
    )
  );
