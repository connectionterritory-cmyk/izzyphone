begin;

-- ── 1. Nuevas columnas en cob_ptps ──────────────────────────

alter table public.cob_ptps
  add column if not exists canal         text,
  add column if not exists cumplido_at   timestamptz,
  add column if not exists incumplido_at timestamptz;

comment on column public.cob_ptps.canal is
  'Canal por el que se recibió el compromiso de pago: llamada, whatsapp, email, presencial.';

comment on column public.cob_ptps.cumplido_at is
  'Timestamp exacto en que se registró el cumplimiento. '
  'Complementa fecha_cumplimiento (date legacy) con precisión de hora.';

comment on column public.cob_ptps.incumplido_at is
  'Timestamp exacto en que se registró el incumplimiento o vencimiento del PTP.';

-- ── 2. Expandir estado: agregar renegociada ──────────────────

alter table public.cob_ptps
  drop constraint if exists cob_ptps_estado_check;

alter table public.cob_ptps
  add constraint cob_ptps_estado_check
  check (estado in (
    'pendiente',
    'cumplido',
    'incumplido',
    'vencido',
    'cancelado',
    'renegociada'
  ));

-- ── 3. Actualizar función del trigger para auto-poblar timestamps ──

create or replace function public.fn_cob_ptps_auto_vencido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Auto-vencido: pendiente cuya fecha de compromiso ya pasó
  if new.estado = 'pendiente'
     and new.fecha_compromiso < current_date then
    new.estado := 'vencido';
  end if;

  -- Auto-timestamp de cumplimiento
  if new.estado = 'cumplido'
     and new.cumplido_at is null then
    new.cumplido_at := now();
    if new.fecha_cumplimiento is null then
      new.fecha_cumplimiento := current_date;
    end if;
  end if;

  -- Auto-timestamp de incumplimiento (incumplido o vencido)
  if new.estado in ('incumplido', 'vencido')
     and new.incumplido_at is null then
    new.incumplido_at := now();
  end if;

  new.updated_at := now();
  return new;
end;
$$;

-- ── 4. ptp_id en cob_gestiones ──────────────────────────────

alter table public.cob_gestiones
  add column if not exists ptp_id uuid
    references public.cob_ptps(id) on delete set null;

create index if not exists cob_gestiones_ptp_id_idx
  on public.cob_gestiones (ptp_id)
  where ptp_id is not null;

comment on column public.cob_gestiones.ptp_id is
  'PTP formal originado por esta gestión. FK inversa a cob_ptps(id). '
  'La relación canónica es cob_ptps.gestion_id; este campo es conveniencia de lectura.';

commit;;
