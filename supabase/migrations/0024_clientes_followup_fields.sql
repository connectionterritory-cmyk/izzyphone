-- Migration 0024: Add follow-up fields to clientes.
-- Aligns clientes with leads (next_action_date / next_action)
-- for consistent appointment management across both entity types.
begin;
alter table public.clientes
  add column if not exists next_action_date date,
  add column if not exists next_action      text;
commit;
