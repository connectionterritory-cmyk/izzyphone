-- Migration 0152: drop stale inline check constraint on cob_plan_pagos.estado
--
-- Migration 0107 created cob_plan_pagos with an inline CHECK:
--   estado in ('activo', 'completado', 'cancelado')
-- Postgres auto-named it cob_plan_pagos_estado_check.
--
-- Migration 0150 dropped chk_cob_plan_pagos_estado (a different name) and added
-- a new constraint with the full value set. The old auto-named constraint was
-- never removed, causing inserts with estado='borrador' to fail.

alter table public.cob_plan_pagos
  drop constraint if exists cob_plan_pagos_estado_check;
-- Ensure the correct constraint is in place (idempotent)
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_estado;
alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_estado
  check (estado in ('borrador', 'activo', 'pausado', 'cumplido', 'incumplido', 'cancelado'));
