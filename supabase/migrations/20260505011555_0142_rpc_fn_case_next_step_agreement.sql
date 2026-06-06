-- Migration: 0142_rpc_fn_case_next_step_agreement
-- Description: RPC de solo lectura para recomendar el próximo paso de cobranza basado en el estado del caso.

CREATE OR REPLACE FUNCTION public.fn_case_next_step_agreement(p_case_id uuid)
RETURNS TABLE (
  case_id uuid,
  cliente_id uuid,
  recommended_action text,
  recommended_agreement_type text,
  reason text,
  risk_level text,
  has_active_ptp boolean,
  has_overdue_ptp boolean,
  last_gestion_at timestamptz,
  suggested_followup_date date,
  missing_data text[],
  warnings text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_org_id uuid;
  v_case record;
  v_cliente record;
  v_revolving record;
  v_ptp record;
  v_last_gestion_at timestamptz;
  v_missing_data text[] := '{}';
  v_warnings text[] := '{}';
  v_recommended_action text;
  v_recommended_agreement_type text;
  v_reason text;
  v_risk_level text := 'medium';
  v_has_active_ptp boolean := false;
  v_has_overdue_ptp boolean := false;
  v_suggested_followup_date date;
BEGIN
  -- 1. Seguridad e Identificación del Tenant
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT org_id INTO v_org_id FROM usuarios WHERE id = v_user_id;
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'User organization context not found';
  END IF;

  -- 2. Cargar datos del caso con aislamiento de Tenant (org_id)
  SELECT * INTO v_case 
  FROM cargo_vuelta_cases 
  WHERE id = p_case_id AND org_id = v_org_id;
  
  -- Si el caso no existe o es de otra org, devolvemos fila con acción de bloqueo
  IF NOT FOUND THEN
    RETURN QUERY SELECT 
      p_case_id, 
      NULL::uuid, 
      'case_not_available'::text, 
      NULL::text, 
      'El caso no está disponible o no pertenece a su organización.'::text, 
      'unknown'::text, 
      false, 
      false, 
      NULL::timestamptz, 
      NULL::date, 
      '{}'::text[], 
      '{}'::text[];
    RETURN;
  END IF;

  -- 3. Cargar datos relacionados
  SELECT * INTO v_cliente FROM clientes WHERE id = v_case.cliente_id;
  SELECT * INTO v_revolving FROM cob_revolving_accounts WHERE case_id = p_case_id;
  
  -- PTP pendiente más próximo
  SELECT * INTO v_ptp FROM cob_ptps 
  WHERE case_id = p_case_id AND estado = 'pendiente' 
  ORDER BY fecha_compromiso ASC LIMIT 1;

  -- Última gestión realizada
  SELECT created_at INTO v_last_gestion_at FROM cob_gestiones 
  WHERE case_id = p_case_id 
  ORDER BY created_at DESC LIMIT 1;

  -- 4. Diagnóstico de Datos Faltantes
  IF v_cliente.nombre IS NULL OR v_cliente.nombre = '' THEN v_missing_data := array_append(v_missing_data, 'cliente.nombre'); END IF;
  IF v_cliente.telefono IS NULL OR v_cliente.telefono = '' THEN v_missing_data := array_append(v_missing_data, 'cliente.telefono'); END IF;
  IF v_case.monto_devuelto IS NULL OR v_case.monto_devuelto <= 0 THEN v_missing_data := array_append(v_missing_data, 'case.monto_devuelto'); END IF;

  -- 5. Lógica de Decisión Operativa (Basada en Prioridades solicitadas)

  -- Prioridad 1: Caso Cerrado o Sin Saldo
  IF v_case.estado IN ('Cerrado', 'Cancelado') OR (v_revolving.saldo_total_actual IS NOT NULL AND v_revolving.saldo_total_actual <= 0) THEN
    v_recommended_action := 'sin_accion';
    v_reason := 'El caso está resuelto, cerrado o no presenta saldo pendiente.';
    v_risk_level := 'low';
  
  -- Prioridad 2 & 3: Faltan datos críticos para operar
  ELSIF array_length(v_missing_data, 1) > 0 THEN
    v_recommended_action := 'completar_datos';
    v_reason := 'Faltan datos clave del cliente o del caso para proceder con la gestión.';
    v_risk_level := 'medium';

  -- Prioridad 4: PTP Pendiente Vencido (Incumplido)
  ELSIF v_ptp.id IS NOT NULL AND v_ptp.fecha_compromiso < CURRENT_DATE THEN
    v_recommended_action := 'gestionar_incumplimiento';
    v_recommended_agreement_type := 'renegotiated_ptp';
    v_reason := 'El cliente tiene una promesa de pago vencida desde el ' || v_ptp.fecha_compromiso || '. Requiere contacto inmediato.';
    v_risk_level := 'high';
    v_has_overdue_ptp := true;
    v_has_active_ptp := true;
    v_suggested_followup_date := CURRENT_DATE;

  -- Prioridad 5: PTP Pendiente Vigente (Esperando fecha)
  ELSIF v_ptp.id IS NOT NULL THEN
    v_recommended_action := 'seguimiento_ptp';
    v_recommended_agreement_type := 'promise_to_pay';
    v_reason := 'Existe una promesa de pago activa programada para el ' || v_ptp.fecha_compromiso || '.';
    v_risk_level := 'medium';
    v_has_active_ptp := true;
    v_suggested_followup_date := v_ptp.fecha_compromiso;

  -- Prioridad 6: Sin acuerdo activo y con saldo pendiente
  ELSE
    v_recommended_action := 'ofrecer_acuerdo';
    v_recommended_agreement_type := 'payment_plan';
    v_reason := 'El caso tiene saldo operativo pero no cuenta con un acuerdo o promesa de pago activa.';
    v_risk_level := CASE 
      WHEN (v_revolving.saldo_total_actual IS NOT NULL AND v_revolving.saldo_total_actual > 1000) THEN 'high'
      ELSE 'medium'
    END;
    v_suggested_followup_date := CURRENT_DATE;
  END IF;

  -- 6. Alertas / Advertencias Adicionales
  IF v_case.en_proceso_legal THEN
    v_warnings := array_append(v_warnings, 'en_proceso_legal');
  END IF;
  IF v_case.requiere_reconciliacion THEN
    v_warnings := array_append(v_warnings, 'requiere_reconciliacion');
  END IF;
  IF v_last_gestion_at IS NULL OR v_last_gestion_at < (now() - interval '30 days') THEN
    v_warnings := array_append(v_warnings, 'sin_gestion_reciente');
  END IF;

  RETURN QUERY SELECT 
    v_case.id,
    v_case.cliente_id,
    v_recommended_action,
    v_recommended_agreement_type,
    v_reason,
    v_risk_level,
    v_has_active_ptp,
    v_has_overdue_ptp,
    v_last_gestion_at,
    v_suggested_followup_date,
    v_missing_data,
    v_warnings;
END;
$$;

-- Comentario de seguridad
COMMENT ON FUNCTION public.fn_case_next_step_agreement(uuid) IS 
'Recomienda el próximo paso de cobranza para un caso DFP/Cargo Vuelta analizando PTPs, saldos y gestiones. SECURITY DEFINER con filtrado por org_id.';
;
