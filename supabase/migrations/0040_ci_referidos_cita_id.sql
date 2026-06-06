-- ============================================================
-- 0040_ci_referidos_cita_id.sql
-- Fase 3A: FK de ci_referidos → citas para vincular la visita
-- de presentación al referido que la originó
-- ============================================================

begin;
alter table public.ci_referidos
  add column if not exists cita_id uuid
    references public.citas(id) on delete set null;
create index if not exists ci_referidos_cita_id_idx
  on public.ci_referidos (cita_id)
  where cita_id is not null;
commit;
