
ALTER TABLE equipos_instalados
  ADD COLUMN IF NOT EXISTS intervalo_cambio_meses INT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS proxima_cambio DATE DEFAULT NULL;

COMMENT ON COLUMN equipos_instalados.intervalo_meses IS 'Intervalo de revisión en meses (default 6)';
COMMENT ON COLUMN equipos_instalados.intervalo_cambio_meses IS 'Intervalo de cambio de filtro en meses. NULL = mismo que intervalo_meses';
COMMENT ON COLUMN equipos_instalados.proxima_cambio IS 'Próxima fecha de cambio de filtro/repuesto';
;
