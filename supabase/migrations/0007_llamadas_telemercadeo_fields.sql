begin;
alter table public.llamadas_telemercadeo
  add column if not exists followup_at date,
  add column if not exists monto_prometido numeric;
commit;
