begin;

revoke all privileges on table public.izzy_leads from anon;
revoke all privileges on table public.izzy_leads from authenticated;

drop policy if exists allow_anon_select on public.izzy_leads;
drop policy if exists allow_anon_insert on public.izzy_leads;
drop policy if exists allow_anon_update on public.izzy_leads;

alter table public.izzy_leads enable row level security;
alter table public.izzy_leads force row level security;

commit;
