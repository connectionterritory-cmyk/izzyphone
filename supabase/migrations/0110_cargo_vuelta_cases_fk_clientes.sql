-- ============================================================
-- 0110: FK cargo_vuelta_cases → clientes
--
-- Objetivo:
--   PostgREST requiere una FK real para resolver el embed
--   clientes(...) desde cargo_vuelta_cases.
--   Sin esta FK, cualquier select con embed devuelve 400.
--
-- NOT VALID: no valida filas existentes, solo nuevas inserciones.
-- Rollback: drop constraint cargo_vuelta_cases_cliente_id_fk
-- ============================================================

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.cargo_vuelta_cases'::regclass
      and conname = 'cargo_vuelta_cases_cliente_id_fk'
  ) then
    alter table public.cargo_vuelta_cases
      add constraint cargo_vuelta_cases_cliente_id_fk
      foreign key (cliente_id)
      references public.clientes(id)
      on delete restrict
      not valid;
  end if;
end $$;
