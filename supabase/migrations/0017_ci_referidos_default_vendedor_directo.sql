begin;
-- Set default mode for new referidos to vendedor_directo.
-- Existing rows with NULL keep their current value; we back-fill to vendedor_directo
-- so the UI shows consistent behaviour regardless of when the row was created.

alter table public.ci_referidos
  alter column modo_gestion set default 'vendedor_directo';
update public.ci_referidos
  set modo_gestion = 'vendedor_directo'
  where modo_gestion is null;
commit;
