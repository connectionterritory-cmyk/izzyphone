CREATE OR REPLACE VIEW public.v_lead_fuentes AS
SELECT DISTINCT
  fuente AS fuente_raw,
  lower(trim(fuente)) AS fuente_norm
FROM public.leads
WHERE fuente IS NOT NULL
  AND trim(fuente) <> '';
GRANT SELECT ON public.v_lead_fuentes TO authenticated;
GRANT SELECT ON public.v_lead_fuentes TO anon;
