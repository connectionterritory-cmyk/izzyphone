-- ============================================================
-- 0086: Documentacion de tabla legacy llamadas_telemercadeo
-- ============================================================
-- Nota: esta migracion solo crea la tabla si no existe para
-- entornos nuevos. No altera datos en produccion.

begin;
create table if not exists public.llamadas_telemercadeo (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null,
  telemercadista_id uuid,
  resultado text not null,
  notas text,
  followup_at date,
  monto_prometido numeric,
  created_at timestamptz not null default now()
);
create index if not exists llamadas_telemercadeo_cliente_idx
  on public.llamadas_telemercadeo (cliente_id);
create index if not exists llamadas_telemercadeo_created_at_idx
  on public.llamadas_telemercadeo (created_at desc);
create index if not exists llamadas_telemercadeo_followup_idx
  on public.llamadas_telemercadeo (followup_at)
  where followup_at is not null;
commit;
