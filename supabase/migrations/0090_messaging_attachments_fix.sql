-- ============================================================
-- 0076: messaging_attachments — Soporte para archivos adjuntos
-- ============================================================

-- 1. Agregar columnas para URLs de adjuntos (Array de texto)
alter table public.message_templates
  add column if not exists attachment_urls text[] default '{}';
alter table public.outbox_messages
  add column if not exists attachment_urls text[] default '{}';
-- 2. Crear bucket de storage para adjuntos
insert into storage.buckets (id, name, public)
values ('messaging_attachments', 'messaging_attachments', true)
on conflict (id) do nothing;
-- 3. Políticas RLS para el bucket 'messaging_attachments'
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Adjuntos de mensajeria son publicos para lectura'
  ) then
    create policy "Adjuntos de mensajeria son publicos para lectura"
    on storage.objects for select to public
    using (bucket_id = 'messaging_attachments');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Usuarios pueden subir adjuntos de mensajeria'
  ) then
    create policy "Usuarios pueden subir adjuntos de mensajeria"
    on storage.objects for insert to authenticated
    with check (bucket_id = 'messaging_attachments');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Usuarios pueden eliminar sus propios adjuntos'
  ) then
    create policy "Usuarios pueden eliminar sus propios adjuntos"
    on storage.objects for delete to authenticated
    using (bucket_id = 'messaging_attachments' and owner = auth.uid());
  end if;
end $$;
-- 4. Notas adicionales:
-- El limite de tamaño sugerido de 10MB se controlará preferiblemente en el Frontend antes de la subida,
-- aunque se puede configurar en el dashboard de Supabase posteriormente.;
