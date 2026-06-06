-- ============================================================
-- 0149 · cob_metodos_pago
-- Tabla operativa de métodos de pago por cliente/caso.
-- Almacena tokens/referencias seguras — nunca PAN, CVV.
-- ============================================================

begin;

-- ── 1. TABLA ────────────────────────────────────────────────

create table if not exists public.cob_metodos_pago (
  id                    uuid        primary key default gen_random_uuid(),
  org_id                uuid        not null,
  cliente_id            uuid        not null
                          references public.clientes(id) on delete cascade,
  cargo_vuelta_case_id  uuid        null
                          references public.cargo_vuelta_cases(id) on delete set null,

  -- proveedor de procesamiento
  provider              text        null,

  -- token seguro — NUNCA guardar PAN completo ni CVV
  token_ref             text        not null,

  -- datos de presentación (no sensibles)
  brand                 text        null,
  last4                 text        null,
  exp_month             int         null,
  exp_year              int         null,
  nombre_tarjeta        text        null,
  billing_zip           text        null,

  -- estado operativo
  is_default            boolean     not null default false,
  estado                text        not null default 'activo',
  source                text        not null default 'manual',

  -- trazabilidad
  notas                 text        null,
  created_by            uuid        null
                          references public.usuarios(id) on delete set null,
  updated_by            uuid        null
                          references public.usuarios(id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  -- ── CHECK CONSTRAINTS ──────────────────────────────────────

  constraint chk_cob_metodos_pago_last4
    check (last4 is null or (length(last4) <= 4 and last4 ~ '^[0-9]{1,4}$')),

  constraint chk_cob_metodos_pago_exp_month
    check (exp_month is null or (exp_month >= 1 and exp_month <= 12)),

  constraint chk_cob_metodos_pago_exp_year
    check (exp_year is null or (exp_year >= 2020 and exp_year <= 2099)),

  constraint chk_cob_metodos_pago_estado
    check (estado in ('activo', 'inactivo', 'expirado', 'reemplazado', 'fallido')),

  constraint chk_cob_metodos_pago_source
    check (source in ('manual', 'import', 'portal', 'n8n'))
);

-- ── 2. COMENTARIOS ──────────────────────────────────────────

comment on table  public.cob_metodos_pago                 is 'Métodos de pago por cliente/caso. Solo tokens/referencias — nunca PAN ni CVV.';
comment on column public.cob_metodos_pago.token_ref       is 'Token o referencia del procesador. Nunca guardar número completo de tarjeta.';
comment on column public.cob_metodos_pago.last4           is 'Últimos 4 dígitos, solo para presentación.';
comment on column public.cob_metodos_pago.is_default      is 'Método de pago activo preferido del cliente en este org.';
comment on column public.cob_metodos_pago.estado          is 'activo | inactivo | expirado | reemplazado | fallido';
comment on column public.cob_metodos_pago.source          is 'manual | import | portal | n8n';

-- ── 3. ÍNDICES ───────────────────────────────────────────────

create index if not exists idx_cob_metodos_pago_org_id
  on public.cob_metodos_pago (org_id);

create index if not exists idx_cob_metodos_pago_cliente_id
  on public.cob_metodos_pago (org_id, cliente_id);

create index if not exists idx_cob_metodos_pago_case_id
  on public.cob_metodos_pago (cargo_vuelta_case_id)
  where cargo_vuelta_case_id is not null;

create index if not exists idx_cob_metodos_pago_estado
  on public.cob_metodos_pago (org_id, estado);

create unique index if not exists uq_cob_metodos_pago_default_activo
  on public.cob_metodos_pago (org_id, cliente_id)
  where is_default = true and estado = 'activo';

-- ── 4. TRIGGER updated_at ───────────────────────────────────

drop trigger if exists trg_cob_metodos_pago_updated_at on public.cob_metodos_pago;
create trigger trg_cob_metodos_pago_updated_at
  before update on public.cob_metodos_pago
  for each row execute function public.fn_set_updated_at();

-- ── 5. RLS ──────────────────────────────────────────────────

alter table public.cob_metodos_pago enable row level security;

drop policy if exists cob_metodos_pago_select_cartera on public.cob_metodos_pago;
drop policy if exists cob_metodos_pago_insert_cartera on public.cob_metodos_pago;
drop policy if exists cob_metodos_pago_update_cartera on public.cob_metodos_pago;

create policy cob_metodos_pago_select_cartera
  on public.cob_metodos_pago
  for select to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  );

create policy cob_metodos_pago_insert_cartera
  on public.cob_metodos_pago
  for insert to authenticated
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (created_by is null or created_by = auth.uid())
      )
    )
  );

create policy cob_metodos_pago_update_cartera
  on public.cob_metodos_pago
  for update to authenticated
  using (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or security.current_user_role() = 'telemercadeo'
    )
  )
  with check (
    org_id = (select u.org_id from public.usuarios u where u.id = auth.uid() limit 1)
    and (
      public.is_admin_or_distribuidor()
      or public.is_supervisor_tele()
      or (
        security.current_user_role() = 'telemercadeo'
        and (created_by is null or created_by = auth.uid())
      )
    )
  );

commit;;
