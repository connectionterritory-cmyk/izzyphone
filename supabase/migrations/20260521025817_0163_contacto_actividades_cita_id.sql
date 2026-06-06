
alter table public.contacto_actividades
  add column if not exists cita_id uuid
    references public.citas(id) on delete set null;

create index if not exists contacto_actividades_cita_id_idx
  on public.contacto_actividades (cita_id)
  where cita_id is not null;

comment on column public.contacto_actividades.cita_id is
  'FK opcional a citas. Usado por CitaModal para vincular la actividad de cierre a la cita completada y releer el estado al reabrir.';
;
