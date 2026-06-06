BEGIN;
ALTER TABLE public.embajadores
    ADD COLUMN IF NOT EXISTS estado text NOT NULL DEFAULT 'pendiente',
    ADD COLUMN IF NOT EXISTS fecha_aceptacion timestamptz,
    ADD COLUMN IF NOT EXISTS aceptado_por uuid,
    ADD COLUMN IF NOT EXISTS notas_inscripcion text;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'embajadores_estado_check'
    ) THEN
        ALTER TABLE public.embajadores
            ADD CONSTRAINT embajadores_estado_check CHECK (estado IN ('pendiente', 'activo', 'inactivo', 'rechazado'));
    END IF;
END
$$;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'embajadores_aceptado_por_fkey'
    ) THEN
        ALTER TABLE public.embajadores
            ADD CONSTRAINT embajadores_aceptado_por_fkey FOREIGN KEY (aceptado_por)
                REFERENCES public.usuarios(id) ON DELETE SET NULL;
    END IF;
END
$$;
CREATE INDEX IF NOT EXISTS embajadores_estado_idx ON public.embajadores USING btree (estado);
COMMENT ON COLUMN public.embajadores.estado IS 'Estado de activación del embajador en el programa Conexiones Infinitas';
COMMENT ON COLUMN public.embajadores.fecha_aceptacion IS 'Marca cuándo el embajador fue aceptado en el programa';
COMMENT ON COLUMN public.embajadores.aceptado_por IS 'Usuario que validó la inscripción del embajador';
COMMENT ON COLUMN public.embajadores.notas_inscripcion IS 'Notas libres capturadas durante la inscripción';
COMMIT;
