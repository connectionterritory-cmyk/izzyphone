begin;

alter table public.izzy_portal_users
  add column if not exists password_hash text,
  add column if not exists password_salt text;

commit;
