-- Drop stale inline check constraint auto-named by Postgres from migration 0107
alter table public.cob_plan_pagos
  drop constraint if exists cob_plan_pagos_estado_check;

-- Ensure correct constraint is in place (idempotent)
alter table public.cob_plan_pagos
  drop constraint if exists chk_cob_plan_pagos_estado;

alter table public.cob_plan_pagos
  add constraint chk_cob_plan_pagos_estado
  check (estado in ('borrador', 'activo', 'pausado', 'cumplido', 'incumplido', 'cancelado'));;
