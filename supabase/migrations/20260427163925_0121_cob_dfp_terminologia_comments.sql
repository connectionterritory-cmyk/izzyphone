-- ============================================================
-- 0121: Alineación terminológica DFP / Cargo de Vuelta
--
-- Objetivo:
--   Documentar con COMMENT ON todas las tablas, vistas y columnas
--   clave del módulo DFP/Cartera usando la terminología oficial
--   aprobada en v1 (2026-04-27).
--
-- Sin cambios de lógica, sin DDL, sin triggers, sin RLS.
-- Solo semántica: evitar que el frontend, las funciones y los
-- comentarios mezclen saldo/balance/monto/recompra/cargo sin
--   una regla clara.
--
-- Terminología oficial (resumen):
--   BD/técnico:    cargo_vuelta, cargo_vuelta_cases, ledger
--   UI/operativo:  "Cuenta Recomprada / DFP"
--   Saldo externo: Saldo Hy-Cite (snapshot, no editable)
--   Saldo interno: Saldo Operativo Interno (calculado desde ledger)
--   Principal:     Monto Devuelto (cargo_vuelta_cases.monto_devuelto)
--
-- ROLLBACK: no aplica — COMMENT ON es idempotente y no destructivo.
-- ============================================================

begin;

-- ══════════════════════════════════════════════════════════════
-- 1. cargo_vuelta_cases — Caso central de cobranza DFP
-- ══════════════════════════════════════════════════════════════

comment on table public.cargo_vuelta_cases is
  'Caso central de cobranza para cuentas devueltas por Hy-Cite al distribuidor. '
  'En BD: "Cargo de Vuelta". En UI y comunicación operativa: "Cuenta Recomprada / DFP". '
  'Un cliente puede tener múltiples casos, pero solo uno activo (estado != Cerrado) a la vez. '
  'El Monto Devuelto (monto_devuelto) es el principal operativo inicial; nunca confundir con saldo_actual de clientes.';

comment on column public.cargo_vuelta_cases.monto_total is
  'Campo legacy mantenido por compatibilidad con código anterior a 0116. '
  'Para tipo_caso=cargo_vuelta la fuente correcta del principal operativo es monto_devuelto. '
  'UI label: no exponer directamente. Usar monto_devuelto.';

comment on column public.cargo_vuelta_cases.dias_vencido is
  'Días vencidos informados por Hy-Cite al momento del cargo de vuelta. '
  'Snapshot histórico. No recalcular; la morosidad activa se gestiona desde cob_revolving_accounts.';

comment on column public.cargo_vuelta_cases.estado is
  'Estado operativo del caso. Valores: Abierto | En negociación | En acuerdo | En seguimiento | Cerrado | Cancelado. '
  'Describe la situación operativa, no el saldo financiero. '
  'El saldo vive en cob_revolving_accounts y cob_financial_ledger.';

comment on column public.cargo_vuelta_cases.acuerdo_tipo is
  'Tipo de acuerdo alcanzado con el cliente: PTP, Plan de Pagos, Descuento, etc. '
  'Campo libre. El acuerdo formal vive en cob_plan_pagos.';

comment on column public.cargo_vuelta_cases.acuerdo_detalles is
  'JSONB libre con detalles del acuerdo. Complementario a cob_plan_pagos. '
  'No usar para saldos financieros.';

comment on column public.cargo_vuelta_cases.fecha_apertura is
  'Fecha en que se registró el caso en FlowSuite. '
  'Puede diferir de fecha_cargo_vuelta (que es la fecha en que Hy-Cite devolvió la cuenta).';

comment on column public.cargo_vuelta_cases.fecha_cierre is
  'Fecha de cierre operativo del caso. Nulo mientras el caso está activo.';

comment on column public.cargo_vuelta_cases.tipo_caso is
  'Tipo formal del caso. Valor único por ahora: cargo_vuelta. '
  'BD/técnico: cargo_vuelta. UI label: "Cuenta Recomprada / DFP".';

comment on column public.cargo_vuelta_cases.alias_operativo is
  'Alias libre usado por el equipo: Cargo de Vuelta, Cuenta Devuelta, '
  'Cuenta Recomprada, Recomprada, DFP, Distributor Finance Program u otro equivalente. '
  'No normalizar; es un campo operativo de referencia interna.';

comment on column public.cargo_vuelta_cases.fecha_cargo_vuelta is
  'Fecha en que Hy-Cite devolvió la cuenta al distribuidor. '
  'UI label: "Fecha de Devolución" o "Fecha Cargo de Vuelta". '
  'Distinta de fecha_apertura (cuando se registró en FlowSuite).';

comment on column public.cargo_vuelta_cases.monto_devuelto is
  'Principal operativo inicial del caso DFP. '
  'UI label: "Monto Devuelto". '
  'Fuente: Hy-Cite al momento del cargo de vuelta. '
  'Este valor abre la cuenta revolving (cob_revolving_accounts.saldo_principal_inicial). '
  'No confundir con Saldo Hy-Cite (clientes.saldo_actual) ni con el Saldo Operativo Interno '
  '(calculado desde cob_financial_ledger). '
  'No editar una vez que la cuenta revolving está creada.';

comment on column public.cargo_vuelta_cases.numero_cuenta_hycite is
  'Número de cuenta Hy-Cite asociado al caso devuelto. '
  'Usado para reconciliación y rastreo. No es el ID interno del cliente.';

comment on column public.cargo_vuelta_cases.numero_orden_hycite is
  'Número de orden Hy-Cite relacionado al cargo de vuelta, cuando aplique.';

comment on column public.cargo_vuelta_cases.orden_hycite_id is
  'UUID de referencia futura a tabla formal de órdenes Hy-Cite. Nulo hasta que esa tabla exista.';

comment on column public.cargo_vuelta_cases.documento_hycite_id is
  'UUID de referencia futura a documento/importación/OCR que respalda el cargo de vuelta. '
  'Nulo si el caso fue creado manualmente.';

comment on column public.cargo_vuelta_cases.origen_cargo_vuelta is
  'Origen del cargo de vuelta. Valor esperado: hycite. '
  'Extensible en el futuro para otros orígenes si se incorporan.';

comment on column public.cargo_vuelta_cases.requiere_reconciliacion is
  'Bandera operativa: true cuando el monto devuelto, los pagos o el soporte documental '
  'requieren revisión antes de considerar el caso confiable. '
  'UI label: "Pendiente de reconciliación".';


-- ══════════════════════════════════════════════════════════════
-- 2. clientes — Campos snapshot Hy-Cite
-- ══════════════════════════════════════════════════════════════

comment on column public.clientes.saldo_actual is
  'Saldo Hy-Cite Snapshot. Importado desde Hy-Cite; no refleja pagos internos registrados en FlowSuite. '
  'UI label: "Saldo Hy-Cite". '
  'No editable manualmente. No usar para calcular saldo operativo de casos DFP. '
  'Puede quedar en 0.00 incluso cuando hay saldo interno pendiente en cob_revolving_accounts.';

comment on column public.clientes.monto_moroso is
  'Monto moroso según Hy-Cite al último corte de importación. '
  'UI label: "Monto Moroso Hy-Cite". '
  'Snapshot externo — puede diferir del Saldo Operativo Interno del caso DFP.';

comment on column public.clientes.dias_atraso is
  'Días de atraso según Hy-Cite al último corte de importación. '
  'UI label: "Días de Atraso Hy-Cite". '
  'Snapshot externo — no lo usa el motor DFP Revolving para calcular intereses o late fees.';

comment on column public.clientes.estado_cuenta is
  'Estado de cuenta normalizado desde Hy-Cite. '
  'Valores típicos derivados de estado_cuenta_raw. '
  'Snapshot externo; el estado operativo interno del caso DFP vive en cargo_vuelta_cases.estado.';

comment on column public.clientes.estado_cuenta_raw is
  'Estado de cuenta tal como llega en el archivo Hy-Cite, sin normalizar. '
  'Preservado para auditoría y reconciliación.';


-- ══════════════════════════════════════════════════════════════
-- 3. cob_revolving_accounts — Cuenta revolving interna DFP
-- ══════════════════════════════════════════════════════════════

comment on table public.cob_revolving_accounts is
  'Cuenta revolving interna del módulo DFP Revolving. '
  'Modela la obligación financiera de un caso Cargo de Vuelta como cuenta con interés (APR 10–24%) y late fees. '
  'Guarda saldos materializados por componente (principal, interés, fees) para consulta rápida. '
  'La verdad financiera auditable vive en cob_financial_ledger. '
  'Un caso activo tiene como máximo una cuenta activa (unique parcial por estado).';

comment on column public.cob_revolving_accounts.case_id is
  'FK al caso de Cargo de Vuelta (cargo_vuelta_cases). '
  'Uno a uno con el caso mientras la cuenta está en estado activo/moroso/en_plan/reestructurado.';

comment on column public.cob_revolving_accounts.apr_anual is
  'Tasa de interés anual en decimal. Rango operativo aprobado: 0.10 (10%) a 0.24 (24%). '
  'Usada por fn_devengar_interes_revolving con método daily_simple_365.';

comment on column public.cob_revolving_accounts.metodo_calculo_interes is
  'Método de cálculo de interés. daily_simple_365: APR/365 × días × saldo_principal_actual. '
  'Interés no capitaliza sobre sí mismo ni sobre fees salvo política explícita (capitaliza_interes).';

comment on column public.cob_revolving_accounts.fecha_inicio is
  'Fecha de apertura de la cuenta revolving. Típicamente igual a fecha_cargo_vuelta del caso.';

comment on column public.cob_revolving_accounts.fecha_ultimo_devengo is
  'Última fecha hasta la que se devengó interés. '
  'fn_devengar_interes_revolving avanza este campo tras cada accrual. '
  'No modificar manualmente: riesgo de doble devengo o devengo saltado.';

comment on column public.cob_revolving_accounts.saldo_principal_inicial is
  'Monto Devuelto al abrir la cuenta. Fuente: cargo_vuelta_cases.monto_devuelto. '
  'Inmutable una vez creada la cuenta. Los pagos reducen saldo_principal_actual, no este campo.';

comment on column public.cob_revolving_accounts.saldo_principal_actual is
  'Saldo de principal pendiente. Reducido por pagos (waterfall: fee→interés→principal). '
  'UI label: parte del "Saldo Interno".';

comment on column public.cob_revolving_accounts.saldo_interes_actual is
  'Saldo de interés devengado pendiente de pago. '
  'Incrementado por fn_devengar_interes_revolving. Reducido por pagos (waterfall).';

comment on column public.cob_revolving_accounts.saldo_fees_actual is
  'Saldo de late fees pendientes de pago. '
  'Incrementado por fn_aplicar_late_fee_revolving. Reducido por pagos (waterfall, primer componente).';

comment on column public.cob_revolving_accounts.saldo_total_actual is
  'Saldo Operativo Interno total. Columna generada (STORED): suma de principal + interés + fees. '
  'UI label: "Saldo Interno". '
  'No actualizar directamente — actualizar los tres componentes por separado vía funciones. '
  'No confundir con Saldo Hy-Cite (clientes.saldo_actual).';

comment on column public.cob_revolving_accounts.late_fee_fijo is
  'Monto fijo de late fee en dólares, aplicado cuando se detecta mora. '
  'Excluyente con late_fee_porcentaje.';

comment on column public.cob_revolving_accounts.late_fee_porcentaje is
  'Late fee como porcentaje del saldo vencido (ej: 0.05 = 5%). '
  'Excluyente con late_fee_fijo.';

comment on column public.cob_revolving_accounts.dias_gracia_late_fee is
  'Días de gracia antes de aplicar late fee tras vencimiento. 0 = sin gracia.';

comment on column public.cob_revolving_accounts.capitaliza_interes is
  'Si true, el interés devengado se capitaliza al principal (interés compuesto). '
  'Política actual: false. Cambiar solo con aprobación explícita.';

comment on column public.cob_revolving_accounts.capitaliza_fees is
  'Si true, los fees se capitalizan al principal. Política actual: false.';

comment on column public.cob_revolving_accounts.estado is
  'Estado del ciclo de vida de la cuenta revolving. '
  'activo: cuenta viva sin acuerdo formal. '
  'moroso: mora activa o fee pendiente. '
  'en_plan: existe cob_plan_pagos activo vinculado. '
  'reestructurado: reemplazada por otra cuenta o acuerdo. '
  'completado: todos los saldos en cero — caso recuperado. '
  'cancelado: anulada administrativamente. '
  'writeoff: castigo contable interno — saldo irrecuperable.';


-- ══════════════════════════════════════════════════════════════
-- 4. cob_financial_ledger — Ledger financiero inmutable
-- ══════════════════════════════════════════════════════════════

comment on table public.cob_financial_ledger is
  'Ledger Financiero Inmutable del módulo DFP Revolving. '
  'Registro append-only de toda mutación monetaria en cuentas revolving DFP. '
  'Fuente de verdad para reconstruir saldos históricos. '
  'NUNCA borrar filas: usar entry_type=reversal para anular. '
  'INSERT solo permitido mediante funciones SECURITY DEFINER (0122+). '
  'INSERT directo de usuarios autenticados está explícitamente bloqueado por RLS.';

comment on column public.cob_financial_ledger.revolving_account_id is
  'FK a la cuenta revolving DFP (cob_revolving_accounts). '
  'Todos los entries de un caso se agrupan bajo la misma cuenta revolving.';

comment on column public.cob_financial_ledger.case_id is
  'FK desnormalizada al caso de Cargo de Vuelta. '
  'Preservada para auditoría independiente: permite reconstruir el historial del caso '
  'incluso si la cuenta revolving fuera eliminada (no debería ocurrir por ON DELETE RESTRICT).';

comment on column public.cob_financial_ledger.cliente_id is
  'FK desnormalizada al cliente. Preservada para auditoría independiente.';

comment on column public.cob_financial_ledger.plan_id is
  'FK opcional al plan de pagos (cob_plan_pagos). Presente cuando el pago responde a un plan.';

comment on column public.cob_financial_ledger.cuota_id is
  'FK opcional a la cuota específica del plan (cob_plan_cuotas).';

comment on column public.cob_financial_ledger.pago_id is
  'FK opcional al registro de pago (cob_pagos) que originó este entry.';

comment on column public.cob_financial_ledger.entry_date is
  'Fecha en que se registró el entry en FlowSuite (puede diferir de effective_date).';

comment on column public.cob_financial_ledger.effective_date is
  'Fecha financiera del evento. '
  'Para devengos: último día del rango de accrual. '
  'Para pagos: fecha real del pago recibido.';

comment on column public.cob_financial_ledger.entry_type is
  'Tipo de movimiento financiero. Valores: '
  'principal_initial (apertura de cuenta), '
  'finance_charge_accrual (devengo de interés diario), '
  'late_fee_assessed (cargo de mora), '
  'payment_applied (pago recibido con waterfall fee→interés→principal), '
  'adjustment (ajuste manual auditado), '
  'writeoff (castigo contable de saldo residual), '
  'reversal (anulación de otro entry — requiere reverses_ledger_id).';

comment on column public.cob_financial_ledger.component_type is
  'Componente financiero afectado por este entry. '
  'principal: afecta saldo_principal. '
  'interest: afecta saldo_interes. '
  'fee: afecta saldo_fees.';

comment on column public.cob_financial_ledger.debit_credit is
  'Dirección del movimiento. '
  'debit: aumenta el saldo del componente (cargo al cliente). '
  'credit: reduce el saldo del componente (pago o reverso a favor del cliente).';

comment on column public.cob_financial_ledger.amount is
  'Monto siempre positivo. La dirección la determina debit_credit.';

comment on column public.cob_financial_ledger.description is
  'Descripción libre del entry para auditoría. '
  'Ejemplo: "Pago recibido en efectivo 2026-04-20", "Devengo interés 2026-04-01/2026-04-30".';

comment on column public.cob_financial_ledger.accrual_from is
  'Inicio del rango de devengo (inclusivo). Solo para entry_type=finance_charge_accrual.';

comment on column public.cob_financial_ledger.accrual_to is
  'Fin del rango de devengo (exclusivo del día final). Solo para finance_charge_accrual. '
  'Unique parcial con accrual_from y revolving_account_id previene doble devengo.';

comment on column public.cob_financial_ledger.balance_principal_after is
  'Saldo de principal de la cuenta revolving inmediatamente después de este entry. '
  'Snapshot del momento — permite reconstruir el estado exacto en cualquier punto del tiempo.';

comment on column public.cob_financial_ledger.balance_interest_after is
  'Saldo de interés de la cuenta revolving inmediatamente después de este entry.';

comment on column public.cob_financial_ledger.balance_fees_after is
  'Saldo de fees de la cuenta revolving inmediatamente después de este entry.';

comment on column public.cob_financial_ledger.balance_total_after is
  'Saldo total (principal + interés + fees) inmediatamente después de este entry. '
  'Constraint: >= 0.';

comment on column public.cob_financial_ledger.reverses_ledger_id is
  'FK al entry que este reverso anula. Obligatorio cuando entry_type=reversal. '
  'Unique parcial garantiza que cada entry solo puede ser revertido una vez.';

comment on column public.cob_financial_ledger.metadata is
  'JSONB libre para contexto adicional: APR usado en el cálculo, días devengados, '
  'ID externo de referencia, usuario aprobador, canal de pago, etc.';

comment on column public.cob_financial_ledger.created_by is
  'Usuario de FlowSuite que originó este entry (via función SECURITY DEFINER). '
  'NULL si fue generado por un job automático sin sesión de usuario.';


-- ══════════════════════════════════════════════════════════════
-- 5. Vistas — Terminología y propósito declarado
-- ══════════════════════════════════════════════════════════════

comment on view public.v_cartera_operativa is
  'Vista unificada de cartera operativa. '
  'Momento 1 — Moroso Hy-Cite activo: saldo desde clientes (Saldo Hy-Cite Snapshot). '
  'Momento 2 — Cargo de Vuelta / DFP: saldo operativo desde cargo_vuelta_cases (Monto Devuelto - pagos internos). '
  'Clasificación: cargo_vuelta | ptp_vencida_hycite | ptp_activa_hycite | moroso_hycite | caso_cerrado | al_dia. '
  'Sin auth.uid(): siempre filtrar por org_id desde el frontend o un RPC. '
  'Fuente: clientes WHERE activo=true.';

comment on view public.v_cargo_vuelta_resumen is
  'Resumen operativo de casos Cargo de Vuelta / Cuenta Recomprada / DFP. '
  'Expone Monto Devuelto (principal inicial), pagos internos acumulados, '
  'Saldo Operativo (monto_devuelto - pagos), y Saldo Hy-Cite como referencia externa. '
  'Solo muestra tipo_caso=cargo_vuelta. '
  'Sin auth.uid(): filtrar por org_id desde el llamador.';

comment on view public.v_ledger_saldos_reconstruidos is
  'Saldos reconstruidos desde el Ledger Financiero Inmutable (cob_financial_ledger) desde cero. '
  'No usa saldos materializados de cob_revolving_accounts. '
  'Usar para auditoría o para detectar drift entre ledger y cob_revolving_accounts. '
  'Sin auth.uid(): filtrar por org_id desde el llamador.';

commit;;
