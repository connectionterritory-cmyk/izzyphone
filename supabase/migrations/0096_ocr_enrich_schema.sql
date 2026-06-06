-- ============================================================
-- 0095: Enriquecimiento OCR — campos extendidos leads/clientes
--       y corrección del CHECK constraint en import_revisiones
--
-- Cambios:
--   1. import_revisiones.motivo: ampliar CHECK para incluir los
--      motivos que el workflow emite en producción pero que la
--      constraint original no contemplaba.
--   2. leads: agregar campos extraídos por OCR extendido.
--   3. clientes: agregar campos Hy-Cite extraídos por OCR.
--
-- ROLLBACK:
--   alter table public.import_revisiones
--     drop constraint if exists import_revisiones_motivo_check;
--   alter table public.import_revisiones
--     add constraint import_revisiones_motivo_check
--     check (motivo in ('parse_error','baja_confianza','fileid_vacio'));
--   alter table public.leads
--     drop column if exists lugar_trabajo,
--     drop column if exists telefono_trabajo,
--     drop column if exists mejor_hora_llamar,
--     drop column if exists notas_extraidas;
--   alter table public.clientes
--     drop column if exists apartamento,
--     drop column if exists tipo_cuenta_hycite,
--     drop column if exists pago_minimo_mensual,
--     drop column if exists factor_ingresos,
--     drop column if exists estado_cuenta_raw,
--     drop column if exists vendedor_hycite_nombre;
-- ============================================================

begin;
-- ----------------------------------------------------------------
-- 1. Ampliar CHECK constraint de motivo en import_revisiones
--    La constraint original (0093) solo tenía 3 valores. El
--    workflow emite 7 motivos distintos; los 4 faltantes causaban
--    violaciones de constraint silenciosas en n8n.
-- ----------------------------------------------------------------
alter table public.import_revisiones
  drop constraint if exists import_revisiones_motivo_check;
alter table public.import_revisiones
  add constraint import_revisiones_motivo_check
  check (motivo in (
    'parse_error',           -- OCR no devolvió JSON válido
    'baja_confianza',        -- confianza='baja' o tipo='revision'
    'fileid_vacio',          -- archivo sin fileId asignable
    'error_leyendo_imagen',  -- fallo al leer binario en n8n
    'sin_datos_binarios',    -- nodo Drive no adjuntó binario
    'openai_api_error',      -- error HTTP desde OpenAI
    'sin_personas'           -- JSON válido pero personas=[]
  ));
-- ----------------------------------------------------------------
-- 2. leads: campos adicionales extraídos por OCR extendido
-- ----------------------------------------------------------------
alter table public.leads
  add column if not exists lugar_trabajo      text,
  add column if not exists telefono_trabajo   text,
  add column if not exists mejor_hora_llamar  text,
  add column if not exists notas_extraidas    text;
comment on column public.leads.lugar_trabajo     is 'Empresa o lugar de trabajo del prospecto (extraído por OCR).';
comment on column public.leads.telefono_trabajo  is 'Teléfono del trabajo (extraído por OCR).';
comment on column public.leads.mejor_hora_llamar is 'Hora preferida para ser contactado (extraído por OCR).';
comment on column public.leads.notas_extraidas   is 'Notas adicionales del OCR que no caben en otros campos.';
-- ----------------------------------------------------------------
-- 3. clientes: campos Hy-Cite extraídos por OCR
-- ----------------------------------------------------------------
alter table public.clientes
  add column if not exists apartamento            text,
  add column if not exists tipo_cuenta_hycite     text,
  add column if not exists pago_minimo_mensual    numeric(12,2),
  add column if not exists factor_ingresos        numeric(12,2),
  add column if not exists estado_cuenta_raw      text,
  add column if not exists vendedor_hycite_nombre text;
comment on column public.clientes.apartamento            is 'Apartamento o unidad de la dirección (extraído por OCR).';
comment on column public.clientes.tipo_cuenta_hycite     is 'Tipo de cuenta Hy-Cite (Quality of Life, etc.).';
comment on column public.clientes.pago_minimo_mensual    is 'Pago mínimo mensual Hy-Cite (extraído por OCR).';
comment on column public.clientes.factor_ingresos        is 'Factor de ingresos declarado (extraído por OCR).';
comment on column public.clientes.estado_cuenta_raw      is 'Estado de la cuenta Hy-Cite tal como aparece en el documento.';
comment on column public.clientes.vendedor_hycite_nombre is 'Nombre del vendedor Hy-Cite en el documento.';
commit;
