
alter table public.cargo_vuelta_cases
  add column if not exists en_proceso_legal boolean not null default false;

create index if not exists cargo_vuelta_cases_proceso_legal_idx
  on public.cargo_vuelta_cases (org_id, en_proceso_legal)
  where en_proceso_legal = true;

comment on column public.cargo_vuelta_cases.en_proceso_legal is
  'Indica que el caso escaló a proceso legal / demanda. Muestra ⚖️ al lado del nombre en Cartera.';
;
