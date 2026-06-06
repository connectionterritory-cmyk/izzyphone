alter table public.ci_referidos
  add column if not exists email text,
  add column if not exists calificacion integer;
