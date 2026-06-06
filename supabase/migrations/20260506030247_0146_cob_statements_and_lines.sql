
create table if not exists public.cob_statements (
  id uuid primary key default gen_random_uuid(),

  org_id uuid not null,
  cliente_id uuid not null references public.clientes(id) on delete restrict,
  case_id uuid not null references public.cargo_vuelta_cases(id) on delete restrict,
  revolving_account_id uuid not null references public.cob_revolving_accounts(id) on delete restrict,

  periodo_inicio date not null,
  periodo_fin date not null,
  fecha_corte date not null,
  fecha_vencimiento date,
  dias_ciclo_facturacion integer,

  balance_previo numeric(12,2) not null default 0,
  pagos_periodo numeric(12,2) not null default 0,
  otros_creditos numeric(12,2) not null default 0,
  compras_periodo numeric(12,2) not null default 0,
  balance_atrasado numeric(12,2) not null default 0,
  cargos_totales_periodo numeric(12,2) not null default 0,

  apr_tae numeric(8,6),
  balance_sujeto_interes numeric(12,2) not null default 0,
  cargos_interes_periodo numeric(12,2) not null default 0,

  nuevo_balance numeric(12,2) not null default 0,
  pago_minimo numeric(12,2) not null default 0,
  credito_disponible numeric(12,2),

  ytd_cargos_atraso numeric(12,2) not null default 0,
  ytd_cargos_interes numeric(12,2) not null default 0,

  mensaje_pago text,
  metodos_pago text,

  status text not null default 'draft'
    check (status in ('draft', 'final', 'enviado', 'anulado')),
  pdf_url text,
  enviado_at timestamptz,
  outbox_message_id uuid references public.outbox_messages(id) on delete set null,

  generated_by uuid references public.usuarios(id) on delete set null,
  metadata jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint cob_statements_period_check
    check (periodo_inicio <= periodo_fin and fecha_corte >= periodo_inicio and fecha_corte <= periodo_fin),

  constraint cob_statements_unique_period
    unique (org_id, revolving_account_id, periodo_inicio, periodo_fin)
);

comment on table public.cob_statements is
  'Snapshot documental del estado de cuenta. Generar mediante RPC (ej: fn_cob_statement_generar) desde ledger. '
  'Enviar mediante outbox_messages (ej: fn_cob_statement_enviar). NO muta saldos oficiales. '
  'Pagos, fees, intereses y ajustes se registran solo por RPC/ledger.';

comment on column public.cob_statements.apr_tae is
  'APR/TAE mostrado en statement para comunicación al cliente.';

comment on column public.cob_statements.balance_sujeto_interes is
  'Base de cálculo de interés para visualización del período.';

comment on column public.cob_statements.outbox_message_id is
  'Relación al envío generado en outbox_messages (si fue enviado).';

create table if not exists public.cob_statement_lines (
  id uuid primary key default gen_random_uuid(),

  org_id uuid not null,
  statement_id uuid not null references public.cob_statements(id) on delete cascade,
  revolving_account_id uuid not null references public.cob_revolving_accounts(id) on delete restrict,
  ledger_entry_id uuid references public.cob_financial_ledger(id) on delete set null,

  line_order integer not null default 1,
  transaction_date date,
  posting_date date,

  entry_type text,
  component_type text,
  description text not null,

  amount numeric(12,2) not null,

  metadata jsonb,
  created_at timestamptz not null default now(),

  constraint cob_statement_lines_line_order_positive check (line_order > 0)
);

comment on table public.cob_statement_lines is
  'Líneas del statement mensual (snapshot documental). '
  'No representan contabilidad oficial; solo visualización derivada del ledger. '
  'La verdad monetaria está en cob_financial_ledger y el saldo operativo en cob_revolving_accounts.';

comment on column public.cob_statement_lines.ledger_entry_id is
  'Referencia opcional al asiento fuente en cob_financial_ledger.';

create unique index if not exists cob_statements_id_org_uidx
  on public.cob_statements (id, org_id);

alter table public.cob_statement_lines
  drop constraint if exists cob_statement_lines_statement_org_fk;

alter table public.cob_statement_lines
  add constraint cob_statement_lines_statement_org_fk
  foreign key (statement_id, org_id)
  references public.cob_statements (id, org_id)
  on delete cascade;

create index if not exists cob_statements_org_id_idx
  on public.cob_statements (org_id);

create index if not exists cob_statements_case_id_idx
  on public.cob_statements (case_id);

create index if not exists cob_statements_revolving_period_idx
  on public.cob_statements (revolving_account_id, periodo_inicio desc, periodo_fin desc);

create index if not exists cob_statements_status_idx
  on public.cob_statements (org_id, status);

create index if not exists cob_statements_due_date_idx
  on public.cob_statements (org_id, fecha_vencimiento)
  where fecha_vencimiento is not null;

create index if not exists cob_statement_lines_statement_order_idx
  on public.cob_statement_lines (statement_id, line_order);

create index if not exists cob_statement_lines_ledger_entry_idx
  on public.cob_statement_lines (ledger_entry_id)
  where ledger_entry_id is not null;

create index if not exists cob_statement_lines_org_date_idx
  on public.cob_statement_lines (org_id, transaction_date desc);

drop trigger if exists trg_cob_statements_updated_at on public.cob_statements;

create trigger trg_cob_statements_updated_at
  before update on public.cob_statements
  for each row execute function public.fn_set_updated_at();

alter table public.cob_statements enable row level security;
alter table public.cob_statement_lines enable row level security;

drop policy if exists cob_statements_org_member on public.cob_statements;
drop policy if exists cob_statement_lines_org_member on public.cob_statement_lines;

create policy cob_statements_org_member_select
  on public.cob_statements
  for select to authenticated
  using (
    org_id = (
      select u.org_id from public.usuarios u where u.id = auth.uid() limit 1
    )
  );

create policy cob_statement_lines_org_member_select
  on public.cob_statement_lines
  for select to authenticated
  using (
    org_id = (
      select u.org_id from public.usuarios u where u.id = auth.uid() limit 1
    )
  );

revoke all on table public.cob_statements from anon;
revoke all on table public.cob_statement_lines from anon;

revoke all on table public.cob_statements from public;
revoke all on table public.cob_statement_lines from public;

grant select on table public.cob_statements to authenticated;
grant select on table public.cob_statement_lines to authenticated;
;
