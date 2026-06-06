ALTER TABLE public.programa_4en14_referidos
  ADD COLUMN IF NOT EXISTS cita_id uuid REFERENCES public.citas(id) ON DELETE SET NULL;
