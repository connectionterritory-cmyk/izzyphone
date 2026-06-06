alter table public.usuarios
  add column if not exists foto_url text,
  add column if not exists reclutador_codigo text;
alter table public.productos
  add column if not exists foto_url text;
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;
insert into storage.buckets (id, name, public)
values ('productos', 'productos', true)
on conflict (id) do update set public = excluded.public;
do $$
begin
  create policy "Public read avatars"
    on storage.objects for select
    using (bucket_id = 'avatars');
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Authenticated upload avatars"
    on storage.objects for insert
    with check (
      bucket_id = 'avatars'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
    );
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Authenticated update avatars"
    on storage.objects for update
    using (
      bucket_id = 'avatars'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
    )
    with check (
      bucket_id = 'avatars'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
    );
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Authenticated delete avatars"
    on storage.objects for delete
    using (
      bucket_id = 'avatars'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
    );
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Public read productos"
    on storage.objects for select
    using (bucket_id = 'productos');
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Admin distribuidor upload productos"
    on storage.objects for insert
    with check (
      bucket_id = 'productos'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
      and exists (
        select 1
        from public.usuarios u
        where u.id = auth.uid()
          and u.rol in ('admin', 'distribuidor')
      )
    );
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Admin distribuidor update productos"
    on storage.objects for update
    using (
      bucket_id = 'productos'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
      and exists (
        select 1
        from public.usuarios u
        where u.id = auth.uid()
          and u.rol in ('admin', 'distribuidor')
      )
    )
    with check (
      bucket_id = 'productos'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
      and exists (
        select 1
        from public.usuarios u
        where u.id = auth.uid()
          and u.rol in ('admin', 'distribuidor')
      )
    );
exception when duplicate_object then
  null;
end $$;
do $$
begin
  create policy "Admin distribuidor delete productos"
    on storage.objects for delete
    using (
      bucket_id = 'productos'
      and auth.role() = 'authenticated'
      and auth.uid() = owner
      and exists (
        select 1
        from public.usuarios u
        where u.id = auth.uid()
          and u.rol in ('admin', 'distribuidor')
      )
    );
exception when duplicate_object then
  null;
end $$;
