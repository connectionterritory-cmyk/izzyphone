-- ============================================================
-- 0105: Formalizacion minima de cartera/cobranza
--
-- Objetivo:
--   - Formalizar el CASO como entidad central de cartera sin crear tablas nuevas.
--   - Documentar columnas criticas de clientes que ya existen en produccion.
--   - Volver multi-tenant la tabla legacy llamadas_telemercadeo.
--
-- Alcance intencional:
--   - clientes.saldo_actual
--   - clientes.estado_operativo
--   - cob_gestiones.case_id
--   - cargo_vuelta_cases.updated_by
--   - llamadas_telemercadeo.org_id + backfill + RLS minima
--
-- No incluye todavia:
--   - cob_ptps
--   - cob_pagos
--   - cob_plan_pagos / cob_plan_cuotas
--   - consolidacion de llamadas_telemercadeo con cob_gestiones
--   - documentacion masiva de otras columnas legacy de clientes
-- ============================================================

begin;
-- ── 1. Documentar columnas criticas en clientes ──────────────

alter table public.clientes
  add column if not exists saldo_actual numeric(12,2) default 0,
  add column if not exists estado_operativo text;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.clientes'::regclass
      and conname = 'clientes_estado_operativo_check'
  ) then
    alter table public.clientes
      add constraint clientes_estado_operativo_check
      check (
        estado_operativo is null
        or estado_operativo in ('activo', 'inactivo', 'cancelado')
      ) not valid;
  end if;
end $$;
comment on column public.clientes.saldo_actual is
  'Saldo actual sincronizado desde fuente externa (Hy-Cite). Columna ya usada en UI y bots; documentada en migracion para reproducibilidad.';
comment on column public.clientes.estado_operativo is
  'Estado operativo derivado/importado para filtros operativos del CRM. Valores permitidos: activo, inactivo, cancelado.';
-- ── 2. Relacionar gestiones con casos de cartera ─────────────

alter table public.cob_gestiones
  add column if not exists case_id uuid
    references public.cargo_vuelta_cases(id) on delete set null;
create index if not exists cob_gestiones_case_id_idx
  on public.cob_gestiones (case_id);
comment on column public.cob_gestiones.case_id is
  'FK opcional al caso central de cartera/cobranza (cargo_vuelta_cases).';
-- ── 3. Auditar cambios de estado del caso ────────────────────

alter table public.cargo_vuelta_cases
  add column if not exists updated_by uuid
    references public.usuarios(id) on delete set null;
create index if not exists cargo_vuelta_cases_updated_by_idx
  on public.cargo_vuelta_cases (updated_by);
comment on column public.cargo_vuelta_cases.updated_by is
  'Ultimo usuario que actualizo el caso de cartera.';
-- ── 4. Legacy llamadas_telemercadeo: org_id + backfill ──────

alter table public.llamadas_telemercadeo
  add column if not exists org_id uuid;
update public.llamadas_telemercadeo l
set org_id = c.org_id
from public.clientes c
where l.cliente_id = c.id
  and l.org_id is null
  and c.org_id is not null;
create index if not exists llamadas_telemercadeo_org_id_idx
  on public.llamadas_telemercadeo (org_id);
create index if not exists llamadas_telemercadeo_org_cliente_idx
  on public.llamadas_telemercadeo (org_id, cliente_id);
create index if not exists llamadas_telemercadeo_telemercadista_idx
  on public.llamadas_telemercadeo (telemercadista_id);
create index if not exists llamadas_telemercadeo_org_followup_idx
  on public.llamadas_telemercadeo (org_id, followup_at)
  where followup_at is not null;
comment on column public.llamadas_telemercadeo.org_id is
  'Organizacion canonica del registro legacy, backfilled desde clientes.org_id.';
create or replace function public.set_llamadas_telemercadeo_org_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.org_id is null and new.cliente_id is not null then
    select c.org_id
    into new.org_id
    from public.clientes c
    where c.id = new.cliente_id;
  end if;

  return new;
end;
$$;
drop trigger if exists trg_set_llamadas_telemercadeo_org_id
on public.llamadas_telemercadeo;
create trigger trg_set_llamadas_telemercadeo_org_id
before insert or update of cliente_id, org_id
on public.llamadas_telemercadeo
for each row
execute function public.set_llamadas_telemercadeo_org_id();
-- ── 5. RLS minima para tabla legacy ─────────────────────────

alter table public.llamadas_telemercadeo enable row level security;
drop policy if exists llamadas_telemercadeo_cartera_role on public.llamadas_telemercadeo;
drop policy if exists llamadas_telemercadeo_org_member on public.llamadas_telemercadeo;
drop policy if exists llamadas_telemercadeo_org_select on public.llamadas_telemercadeo;
drop policy if exists llamadas_telemercadeo_org_insert on public.llamadas_telemercadeo;
drop policy if exists llamadas_telemercadeo_org_update on public.llamadas_telemercadeo;
drop policy if exists llamadas_telemercadeo_org_delete on public.llamadas_telemercadeo;
create policy llamadas_telemercadeo_org_select
  on public.llamadas_telemercadeo
  for select to authenticated
  using (
    org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
      limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
create policy llamadas_telemercadeo_org_insert
  on public.llamadas_telemercadeo
  for insert to authenticated
  with check (
    org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
      limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (telemercadista_id is null or telemercadista_id = auth.uid())
      )
    )
  );
create policy llamadas_telemercadeo_org_update
  on public.llamadas_telemercadeo
  for update to authenticated
  using (
    org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
      limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  )
  with check (
    org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
      limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (telemercadista_id is null or telemercadista_id = auth.uid())
      )
    )
  );
create policy llamadas_telemercadeo_org_delete
  on public.llamadas_telemercadeo
  for delete to authenticated
  using (
    org_id = (
      select u.org_id
      from public.usuarios u
      where u.id = auth.uid()
      limit 1
    )
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );
commit;
