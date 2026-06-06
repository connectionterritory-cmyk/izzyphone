-- ============================================================
-- 0095: Canonical org_id en usuarios + leads, corrección de
--       RLS en import_revisiones, y fix del índice de teléfono
--
-- Problema de fondo:
--   usuarios.organizacion es texto ("Connection Worldwide Group"),
--   no un UUID. La migración 0094 creó políticas RLS que hacían
--   org_id::text = organizacion (texto≠UUID) y un índice de
--   teléfono sin org_id porque leads no tenía esa columna.
--
-- Solución:
--   1. Agregar org_id uuid a usuarios y backfill por nombre.
--   2. Agregar org_id uuid a leads y backfill desde usuarios.
--   3. Recrear el índice de teléfono normalizado con org_id.
--   4. Corregir RLS en import_revisiones a comparación UUID pura.
-- ============================================================

begin;
-- ── 1. usuarios.org_id ──────────────────────────────────────

alter table public.usuarios
  add column if not exists org_id uuid;
-- Único valor activo en producción: "Connection Worldwide Group"
-- → 00000000-0000-0000-0000-000000000001
update public.usuarios
set org_id = '00000000-0000-0000-0000-000000000001'
where organizacion is not null
  and org_id is null;
create index if not exists usuarios_org_id_idx
  on public.usuarios (org_id);
-- ── 2. leads.org_id ─────────────────────────────────────────

alter table public.leads
  add column if not exists org_id uuid;
-- Backfill a través de owner_id → usuarios.org_id
update public.leads l
set org_id = u.org_id
from public.usuarios u
where l.owner_id = u.id
  and u.org_id is not null
  and l.org_id is null;
create index if not exists leads_org_id_idx
  on public.leads (org_id);
-- ── 3. Índice de teléfono normalizado (fix 0094) ────────────
-- 0094 lo creó sin org_id porque la columna no existía aún.
-- Ahora la recreamos con org_id como primer componente.

drop index if exists public.leads_normalized_phone_org_idx;
create unique index if not exists leads_normalized_phone_org_idx
  on public.leads (org_id, regexp_replace(telefono, '\D', '', 'g'))
  where (
    org_id  is not null
    and telefono is not null
    and length(regexp_replace(telefono, '\D', '', 'g')) >= 7
  );
comment on index public.leads_normalized_phone_org_idx is
  'Idempotencia OCR: un teléfono normalizado por organización, ignorando formato.';
-- ── 4. Corregir RLS en import_revisiones ────────────────────
-- 0094 usaba org_id::text = organizacion (tipos incompatibles).
-- Ahora comparamos UUID con UUID a través de usuarios.org_id.

drop policy if exists "dist_select_revisiones_scoped" on public.import_revisiones;
drop policy if exists "dist_update_revisiones_scoped" on public.import_revisiones;
create policy "dist_select_revisiones_scoped"
  on public.import_revisiones
  for select
  to authenticated
  using (
    public.is_distribuidor()
    and org_id = (
      select org_id from public.usuarios
      where id = auth.uid()
      limit 1
    )
  );
create policy "dist_update_revisiones_scoped"
  on public.import_revisiones
  for update
  to authenticated
  using (
    public.is_distribuidor()
    and org_id = (
      select org_id from public.usuarios
      where id = auth.uid()
      limit 1
    )
  )
  with check (
    public.is_distribuidor()
    and org_id = (
      select org_id from public.usuarios
      where id = auth.uid()
      limit 1
    )
  );
commit;
