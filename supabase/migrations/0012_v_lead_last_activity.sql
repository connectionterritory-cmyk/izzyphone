begin;
create or replace view public.v_lead_last_activity as
select
  l.id as lead_id,
  greatest(coalesce(max(n.created_at), l.updated_at), l.updated_at) as last_activity_at
from public.leads l
left join public.lead_notas n on n.lead_id = l.id
where l.deleted_at is null
group by l.id, l.updated_at;
commit;
