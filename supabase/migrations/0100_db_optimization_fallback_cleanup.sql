-- 1. LIMPIEZA DE DIRECCIONES (ONE-OFF)
UPDATE clientes
SET direccion = NULL
WHERE direccion IN ('Cargo de Vuelta', 'Cancelación total', 'Actual');
-- 2. BACKFILL DE TELÉFONOS
UPDATE clientes c
SET telefono = c.telefono_casa
WHERE (c.telefono IS NULL OR c.telefono = '')
  AND (c.telefono_casa IS NOT NULL AND c.telefono_casa != '')
  AND NOT EXISTS (
    SELECT 1 FROM clientes other
    WHERE other.org_id = c.org_id
      AND other.telefono = c.telefono_casa
      AND other.id <> c.id
  );
-- 3. TRIGGER PARA FALLBACK AUTOMÁTICO
CREATE OR REPLACE FUNCTION fn_clientes_phone_fallback()
RETURNS TRIGGER AS $$
BEGIN
  -- Solo aplica fallback si telefono_casa no colisiona con otro cliente de la misma org
  IF (NEW.telefono IS NULL OR NEW.telefono = '')
     AND (NEW.telefono_casa IS NOT NULL AND NEW.telefono_casa != '')
     AND NOT EXISTS (
       SELECT 1 FROM clientes other
       WHERE other.org_id = NEW.org_id
         AND other.telefono = NEW.telefono_casa
         AND other.id <> NEW.id
     )
  THEN
    NEW.telefono := NEW.telefono_casa;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tr_clientes_phone_fallback ON clientes;
CREATE TRIGGER tr_clientes_phone_fallback
  BEFORE INSERT OR UPDATE ON clientes
  FOR EACH ROW
  EXECUTE FUNCTION fn_clientes_phone_fallback();
