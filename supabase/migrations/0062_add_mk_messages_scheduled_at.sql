-- ============================================================
-- 0062_add_mk_messages_scheduled_at.sql
-- Descripción: Agrega scheduled_at a mk_messages y un índice parcial para pendientes
-- Tipo: add_column + create_index
-- Prerequisito: ninguno
-- Reversible: parcial (DROP COLUMN/INDEX manual si se aprueba)
-- ============================================================

begin;
alter table public.mk_messages
  add column if not exists scheduled_at timestamptz;
create index if not exists mk_messages_scheduled_pending_idx
  on public.mk_messages (scheduled_at)
  where status = 'pendiente';
commit;
