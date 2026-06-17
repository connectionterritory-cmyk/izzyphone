begin;

alter table public.izzy_leads
  add column if not exists assigned_user_id bigint references public.izzy_portal_users(id) on delete set null,
  add column if not exists lead_status_code text not null default 'new',
  add column if not exists priority text not null default 'normal',
  add column if not exists last_contact_at timestamptz,
  add column if not exists last_contact_result text,
  add column if not exists next_action text,
  add column if not exists next_followup_at timestamptz,
  add column if not exists next_followup_status text not null default 'none',
  add column if not exists do_not_call boolean not null default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'izzy_leads_priority_check'
      and conrelid = 'public.izzy_leads'::regclass
  ) then
    alter table public.izzy_leads
      add constraint izzy_leads_priority_check
      check (priority in ('low', 'normal', 'high', 'urgent'));
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'izzy_leads_status_check'
      and conrelid = 'public.izzy_leads'::regclass
  ) then
    alter table public.izzy_leads
      add constraint izzy_leads_status_check
      check (
        lead_status_code in (
          'new',
          'not_contacted',
          'contacted',
          'follow_up',
          'qualified',
          'quote_requested',
          'quote_pending',
          'quoted_ready',
          'not_interested',
          'wrong_number',
          'sold'
        )
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'izzy_leads_followup_status_check'
      and conrelid = 'public.izzy_leads'::regclass
  ) then
    alter table public.izzy_leads
      add constraint izzy_leads_followup_status_check
      check (next_followup_status in ('none', 'scheduled', 'due_today', 'overdue', 'completed'));
  end if;
end
$$;

create index if not exists izzy_leads_assigned_user_id_idx
  on public.izzy_leads (assigned_user_id);

create index if not exists izzy_leads_status_code_idx
  on public.izzy_leads (lead_status_code);

create index if not exists izzy_leads_next_followup_at_idx
  on public.izzy_leads (next_followup_at)
  where next_followup_at is not null;

create index if not exists izzy_leads_do_not_call_idx
  on public.izzy_leads (do_not_call);

update public.izzy_leads l
set assigned_user_id = u.id
from public.izzy_portal_users u
where l.assigned_user_id is null
  and upper(trim(coalesce(l.agente, ''))) = upper(trim(coalesce(u.nombre, '')));

update public.izzy_leads
set lead_status_code = case coalesce(estado, 'Nuevo')
  when 'Vendido' then 'sold'
  when 'Contactado' then 'contacted'
  when 'No interesó' then 'not_interested'
  when 'Volver a Contactar' then 'follow_up'
  else 'new'
end
where lead_status_code is null
   or lead_status_code = 'new';

update public.izzy_leads
set lead_status_code = 'quote_pending'
where cotizacion_enviada is not null
  and trim(cotizacion_enviada) <> ''
  and lead_status_code in ('new', 'not_contacted', 'contacted', 'follow_up');

commit;
