
CREATE TABLE izzy_leads (
  id              BIGSERIAL PRIMARY KEY,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  fecha           TEXT,
  agente          TEXT,
  cliente         TEXT NOT NULL,
  telefono        TEXT,
  direccion       TEXT,
  proveedor_internet  TEXT,
  pago_internet       NUMERIC,
  proveedor_telefono  TEXT,
  pago_telefono       NUMERIC,
  velocidad       TEXT,
  lineas          TEXT,
  nota            TEXT
);
;
