ALTER TABLE public.citas
  ADD COLUMN IF NOT EXISTS resultado text CHECK (resultado IN (
    'realizada', 'venta', 'no_contacto', 'reagendar', 'no_interes', 'otro'
  )),
  ADD COLUMN IF NOT EXISTS resultado_notas text;
