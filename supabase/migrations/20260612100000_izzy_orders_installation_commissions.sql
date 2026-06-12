alter table public.izzy_orders
  add column if not exists installation_status text not null default 'submitted',
  add column if not exists scheduled_install_date date,
  add column if not exists actual_install_date date,
  add column if not exists satisfaction_status text not null default 'pending',
  add column if not exists commission_status text not null default 'not_earned',
  add column if not exists commission_earned_at timestamptz,
  add column if not exists commission_amount numeric,
  -- Audit trail
  add column if not exists satisfaction_confirmed_at timestamptz,
  add column if not exists satisfaction_confirmed_by text,
  add column if not exists satisfaction_notes text,
  add column if not exists commission_paid_at timestamptz,
  add column if not exists commission_paid_by text;

-- Backfill: copy install_date → scheduled_install_date for existing orders
update public.izzy_orders
set scheduled_install_date = install_date
where install_date is not null
  and scheduled_install_date is null;

-- Backfill: existing orders with an install_date were already scheduled
-- Note: columns have NOT NULL defaults so we check for the default value,
-- not null — the old "is null or = ''" check would never fire.
update public.izzy_orders
set installation_status = 'scheduled'
where install_date is not null
  and installation_status = 'submitted';

alter table public.izzy_orders
  drop constraint if exists izzy_orders_installation_status_check;

alter table public.izzy_orders
  add constraint izzy_orders_installation_status_check
  check (installation_status in (
    'submitted',
    'scheduled',
    'installed_pending_confirmation',
    'confirmed_satisfied',
    'cancelled',
    'failed_install'
  ));

alter table public.izzy_orders
  drop constraint if exists izzy_orders_satisfaction_status_check;

alter table public.izzy_orders
  add constraint izzy_orders_satisfaction_status_check
  check (satisfaction_status in (
    'pending',
    'satisfied',
    'issue',
    'cancelled'
  ));

alter table public.izzy_orders
  drop constraint if exists izzy_orders_commission_status_check;

alter table public.izzy_orders
  add constraint izzy_orders_commission_status_check
  check (commission_status in (
    'not_earned',
    'earned',
    'paid',
    'cancelled'
  ));
