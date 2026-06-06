-- ============================================================
-- 0117: v_cartera_operativa — Vista unificada de cartera
--
-- Objetivo:
--   Unificar los dos momentos del ciclo de deuda en una sola vista:
--
--   Momento 1 — Cartera Hy-Cite activa (preventiva):
--     Hy-Cite todavía maneja la cuenta.
--     FlowSuite gestiona llamadas, recordatorios y PTPs.
--     Fuente de saldo: snapshot en clientes (monto_moroso, dias_atraso).
--
--   Momento 2 — Cargo de Vuelta / Recomprada / DFP:
--     Hy-Cite devolvió la cuenta al distribuidor.
--     FlowSuite maneja el caso interno.
--     Fuente de saldo: cargo_vuelta_cases.monto_total − cob_pagos.
--     (monto_devuelto estará disponible tras migración 0116.)
--
-- Decisiones de diseño:
--   - Sin auth.uid() en la vista. Seguridad = RLS en tablas base.
--     Filtrar siempre por org_id desde el frontend o RPC.
--   - Solo CREATE OR REPLACE VIEW: no toca tablas, triggers ni RLS.
--   - Un cliente puede tener a lo sumo un caso activo (estado != Cerrado).
--   - PTPs con case_id IS NULL = cartera preventiva Hy-Cite.
--   - PTPs con case_id IS NOT NULL = Cargo de Vuelta / DFP.
--   - cob_pagos alimenta saldo_operativo solo cuando hay case_id.
--   - Columnas de 0116 (tipo_caso, alias_operativo, fecha_cargo_vuelta)
--     expuestas como NULL hasta que esa migración sea aplicada.
--
-- Clasificacion_cartera (prioridad descendente):
--   cargo_vuelta       → caso activo (estado != 'Cerrado')
--   ptp_vencida_hycite → sin caso activo + PTP vencida (case_id NULL)
--   ptp_activa_hycite  → sin caso activo + PTP activa (case_id NULL)
--   moroso_hycite      → sin caso activo + dias_atraso > 0
--   caso_cerrado       → sin caso activo + tiene caso cerrado + sin atraso ni PTP
--   al_dia             → sin caso, sin atraso, sin PTP
--
-- ROLLBACK:
--   DROP VIEW IF EXISTS public.v_cartera_operativa;
-- ============================================================

begin;
create or replace view public.v_cartera_operativa as

with

-- ── Caso activo por cliente ────────────────────────────────────
-- Un cliente puede tener a lo sumo un caso abierto. Si tuviera
-- varios (datos incorrectos), se toma el más reciente por created_at.
-- monto_devuelto con fallback a monto_total para casos legacy sin backfill.
caso_activo as (
  select distinct on (cliente_id)
    id                                        as case_id,
    org_id,
    cliente_id,
    estado                                    as estado_caso,
    tipo_caso,
    alias_operativo,
    fecha_cargo_vuelta,
    coalesce(monto_devuelto, monto_total)     as monto_devuelto,
    fecha_apertura,
    fecha_cierre
  from public.cargo_vuelta_cases
  where estado != 'Cerrado'
  order by cliente_id, created_at desc
),

-- ── Flag: cliente con al menos un caso cerrado ─────────────────
-- Solo relevante cuando no hay caso activo. Identifica clientes
-- que ya pasaron por DFP y cerraron su caso.
caso_cerrado_flag as (
  select distinct on (cliente_id)
    cliente_id,
    true as tiene_caso_cerrado
  from public.cargo_vuelta_cases
  where estado = 'Cerrado'
  order by cliente_id, updated_at desc
),

-- ── Pagos internos acumulados por caso ─────────────────────────
-- Solo cuenta pagos vinculados a un caso (Cargo de Vuelta / DFP).
-- Pagos de cartera preventiva no tienen case_id.
pagos_por_caso as (
  select
    case_id,
    sum(monto)::numeric(12,2) as monto_recuperado
  from public.cob_pagos
  where case_id is not null
  group by case_id
),

-- ── Último contacto por cliente ────────────────────────────────
-- Cubre gestiones vinculadas a un caso Y gestiones preventivas
-- (case_id NULL). Complementa clientes.ultimo_contacto_at.
ultimo_contacto_por_cliente as (
  select
    cliente_id,
    max(created_at) as ultimo_contacto_gestion
  from public.cob_gestiones
  group by cliente_id
),

-- ── PTPs preventivas Hy-Cite (case_id IS NULL) ─────────────────
-- Promesas registradas fuera de un caso de cargo de vuelta.
ptps_hycite as (
  select
    cliente_id,
    count(*) filter (
      where estado = 'pendiente'
        and fecha_compromiso >= current_date
    )::int as ptps_activas,
    count(*) filter (
      where estado in ('pendiente', 'vencido')
        and fecha_compromiso < current_date
    )::int as ptps_vencidas
  from public.cob_ptps
  where case_id is null
  group by cliente_id
),

-- ── PTPs de Cargo de Vuelta / DFP (case_id IS NOT NULL) ────────
ptps_dfp as (
  select
    case_id,
    count(*) filter (
      where estado = 'pendiente'
        and fecha_compromiso >= current_date
    )::int as ptps_activas,
    count(*) filter (
      where estado in ('pendiente', 'vencido')
        and fecha_compromiso < current_date
    )::int as ptps_vencidas
  from public.cob_ptps
  where case_id is not null
  group by case_id
),

-- ── Plan activo por caso ───────────────────────────────────────
plan_activo_por_caso as (
  select
    case_id,
    count(*)::int as planes_activos
  from public.cob_plan_pagos
  where estado = 'activo'
    and case_id is not null
  group by case_id
)

select
  -- ── Identificadores ────────────────────────────────────────
  c.id                                          as cliente_id,
  c.org_id,

  -- ── Datos del cliente ──────────────────────────────────────
  c.nombre,
  c.apellido,
  c.telefono,
  c.telefono_casa,
  c.email,
  c.hycite_id,
  c.numero_cuenta_financiera,

  -- ── Snapshot Hy-Cite ───────────────────────────────────────
  -- fuente de verdad: importaciones manuales desde Hy-Cite
  c.saldo_actual                                as saldo_hycite_snapshot,
  c.monto_moroso,
  c.dias_atraso,
  c.estado_cuenta,
  c.estado_cuenta_raw,

  -- ── Caso DFP / Cargo de Vuelta ─────────────────────────────
  ca.case_id,
  ca.estado_caso,
  ca.tipo_caso,
  ca.alias_operativo,
  ca.fecha_cargo_vuelta,
  ca.monto_devuelto,
  coalesce(pc.monto_recuperado, 0)::numeric(12,2) as monto_recuperado,
  greatest(
    coalesce(ca.monto_devuelto, 0) - coalesce(pc.monto_recuperado, 0),
    0
  )::numeric(12,2)                              as saldo_operativo,

  -- ── Contadores operativos ──────────────────────────────────
  -- PTPs según contexto: DFP si hay caso, Hy-Cite si no hay caso
  case
    when ca.case_id is not null
    then coalesce(pd.ptps_activas, 0)
    else coalesce(ph.ptps_activas, 0)
  end::int                                      as ptps_activas_count,

  case
    when ca.case_id is not null
    then coalesce(pd.ptps_vencidas, 0)
    else coalesce(ph.ptps_vencidas, 0)
  end::int                                      as ptps_vencidas_count,

  coalesce(pp.planes_activos, 0)::int           as plan_activo_count,

  -- ── Seguimiento ────────────────────────────────────────────
  -- prefiere la gestión más reciente; cae en el campo legacy si no hay gestiones
  coalesce(
    uc.ultimo_contacto_gestion,
    c.ultimo_contacto_at
  )                                             as ultimo_contacto,
  c.next_action                                 as proxima_accion,
  c.next_action_date                            as proxima_accion_fecha,

  -- ── Clasificación de cartera ──────────────────────────────
  -- Prioridad descendente: el primer WHEN que aplica gana.
  case
    when ca.case_id is not null
      then 'cargo_vuelta'                      -- tiene caso activo (Momento 2)

    when ca.case_id is null
      and coalesce(ph.ptps_vencidas, 0) > 0
      then 'ptp_vencida_hycite'               -- PTP preventiva sin cumplir

    when ca.case_id is null
      and coalesce(ph.ptps_activas, 0) > 0
      then 'ptp_activa_hycite'                -- PTP preventiva vigente

    when c.dias_atraso > 0
      then 'moroso_hycite'                    -- atraso Hy-Cite sin caso abierto

    when cf.tiene_caso_cerrado is true
      and coalesce(c.dias_atraso, 0) = 0
      then 'caso_cerrado'                     -- DFP cerrado, sin atraso activo

    else
      'al_dia'                                -- sin atraso, sin caso, sin PTPs
  end                                           as clasificacion_cartera

from public.clientes c
left join caso_activo                ca  on ca.cliente_id  = c.id
left join pagos_por_caso             pc  on pc.case_id     = ca.case_id
left join ultimo_contacto_por_cliente uc on uc.cliente_id  = c.id
left join ptps_hycite                ph  on ph.cliente_id  = c.id
left join ptps_dfp                   pd  on pd.case_id     = ca.case_id
left join plan_activo_por_caso       pp  on pp.case_id     = ca.case_id
left join caso_cerrado_flag          cf  on cf.cliente_id  = c.id
where c.activo = true;
comment on view public.v_cartera_operativa is
  'Vista unificada de cartera operativa. '
  'Cubre Momento 1 (moroso Hy-Cite activo) y Momento 2 (Cargo de Vuelta/DFP). '
  'Sin auth.uid(): siempre filtrar por org_id desde el frontend o un RPC. '
  'Actualizada en 0117 (post 0116): tipo_caso, alias_operativo, fecha_cargo_vuelta '
  'y monto_devuelto provienen de cargo_vuelta_cases directamente.';
commit;
