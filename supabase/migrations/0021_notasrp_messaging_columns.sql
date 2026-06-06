-- Migration 0021: Create notasrp (if missing) + add messaging columns
-- notasrp is a legacy table that may or may not exist.
-- lead_notas exists — only add new columns.
begin;
-- ── 1. notasrp ────────────────────────────────────────────────────────────
-- Create with all columns if the table doesn't exist yet.
create table if not exists public.notasrp (
  id           uuid        primary key default gen_random_uuid(),
  org_id       uuid,
  cliente_id   uuid        references public.clientes(id) on delete cascade,
  contenido    text,
  canal        text,
  tipo_mensaje text,
  enviado_por  uuid        references public.usuarios(id) on delete set null,
  enviado_en   timestamptz,
  mensaje      text,
  created_at   timestamptz not null default now()
);
-- If the table already existed, add only the missing columns.
alter table public.notasrp
  add column if not exists org_id       uuid,
  add column if not exists canal        text,
  add column if not exists tipo_mensaje text,
  add column if not exists enviado_por  uuid references public.usuarios(id) on delete set null,
  add column if not exists enviado_en   timestamptz,
  add column if not exists mensaje      text;
alter table public.notasrp enable row level security;
create index if not exists notasrp_org_id_idx
  on public.notasrp (org_id);
create index if not exists notasrp_cliente_id_enviado_en_idx
  on public.notasrp (cliente_id, enviado_en desc nulls last);
-- RLS — mirrors clientes policies
drop policy if exists notasrp_org_member   on public.notasrp;
drop policy if exists notasrp_admin_all    on public.notasrp;
drop policy if exists notasrp_vendedor     on public.notasrp;
drop policy if exists notasrp_distribuidor on public.notasrp;
create policy notasrp_admin_all on public.notasrp
  for all to authenticated
  using (is_admin());
create policy notasrp_vendedor on public.notasrp
  for all to authenticated
  using (
    exists (
      select 1 from public.clientes c
      where c.id = notasrp.cliente_id
        and c.vendedor_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.clientes c
      where c.id = notasrp.cliente_id
        and c.vendedor_id = auth.uid()
    )
  );
create policy notasrp_distribuidor on public.notasrp
  for select to authenticated
  using (
    is_distribuidor() and exists (
      select 1 from public.clientes c
      where c.id = notasrp.cliente_id
        and (c.distribuidor_id = auth.uid() or is_distribuidor_of(c.vendedor_id))
    )
  );
-- ── 2. lead_notas ─────────────────────────────────────────────────────────
alter table public.lead_notas
  add column if not exists canal        text,
  add column if not exists tipo_mensaje text,
  add column if not exists mensaje      text;
commit;
