-- ============================================================
-- 0120: cob_financial_ledger — lockdown de escritura directa
--
-- Contexto:
--   0119 fue aplicada con una policy INSERT que permitía escritura
--   directa a admin/distribuidor. Ese comportamiento es incorrecto:
--   el ledger financiero debe ser append-only exclusivamente via
--   funciones SECURITY DEFINER (0121+).
--
-- Este archivo documenta el hotfix ya aplicado en producción
--   para que sea reproducible en cualquier entorno nuevo.
--
-- Hotfix aplicado:
--   - drop policy cob_financial_ledger_write (permisiva)
--   - create policy cob_financial_ledger_no_direct_write (bloqueo total)
--   - constraint balance_total_after >= 0 (idempotente)
--   - comment actualizado en la tabla
--
-- ROLLBACK (solo si se sabe lo que se hace):
--   drop policy if exists cob_financial_ledger_no_direct_write on public.cob_financial_ledger;
--   create policy cob_financial_ledger_write
--     on public.cob_financial_ledger for insert to authenticated
--     with check (
--       org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
--       and public.is_admin_or_distribuidor()
--     );
-- ============================================================

begin;
-- ── 1. Eliminar policy permisiva ──────────────────────────────

drop policy if exists cob_financial_ledger_write on public.cob_financial_ledger;
-- ── 2. Bloqueo explícito de INSERT directo ────────────────────
-- with check (false) = ningún usuario autenticado puede insertar.
-- Las funciones fn_* de 0121+ usan SECURITY DEFINER y bypassean RLS.

drop policy if exists cob_financial_ledger_no_direct_write on public.cob_financial_ledger;
create policy cob_financial_ledger_no_direct_write
  on public.cob_financial_ledger
  for insert to authenticated
  with check (false);
-- ── 3. Constraint idempotente: balance_total_after >= 0 ───────

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'cob_financial_ledger_balance_total_after_chk'
      and conrelid = 'public.cob_financial_ledger'::regclass
  ) then
    alter table public.cob_financial_ledger
      add constraint cob_financial_ledger_balance_total_after_chk
      check (balance_total_after is null or balance_total_after >= 0);
  end if;
end $$;
-- ── 4. Comment actualizado ────────────────────────────────────

comment on table public.cob_financial_ledger is
  'Libro mayor financiero interno. Registro inmutable de toda mutación monetaria '
  'en cuentas revolving DFP. Fuente de verdad para reconstruir saldos históricos. '
  'Nunca borrar filas: usar entry_type=reversal para anular. '
  'INSERT solo permitido mediante funciones SECURITY DEFINER (0121+). '
  'INSERT directo de usuarios autenticados está explícitamente bloqueado por RLS.';
commit;
