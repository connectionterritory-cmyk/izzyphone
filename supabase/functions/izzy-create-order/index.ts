import "@supabase/functions-js/edge-runtime.d.ts";

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireSession } from "../_shared/auth.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type OrderPayload = {
  first_name?: string;
  last_name?: string;
  phone1?: string;
  phone2?: string;
  email?: string;
  dob?: string;
  street?: string;
  apt?: string;
  city?: string;
  state?: string;
  zip?: string;
  service_provider?: string;
  service_provider_other?: string;
  desired_speed?: string;
  voice_service?: boolean;
  install_notes?: string;
  autopay?: boolean;
  monthly_price?: number | string | null;
  special_notes?: string;
  order_number?: string;
  btn?: string;
  order_date?: string;
  install_date?: string;
  card_last4?: string;
  signature_data?: string;
};

function cleanString(value: unknown): string {
  return String(value || "").trim();
}

function cleanNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function cleanBoolean(value: unknown): boolean {
  return value === true || value === "true" || value === "yes" || value === 1 || value === "1";
}

function cleanDate(value: unknown): string | null {
  const raw = cleanString(value);
  return raw || null;
}

function buildOrderPayload(raw: OrderPayload, agentName: string) {
  return {
    fecha: new Intl.DateTimeFormat("en-US", { timeZone: "America/Los_Angeles" }).format(new Date()),
    agente: agentName,
    cliente_nombre: cleanString(raw.first_name),
    cliente_apellido: cleanString(raw.last_name),
    telefono_primario: cleanString(raw.phone1),
    telefono_secundario: cleanString(raw.phone2),
    email: cleanString(raw.email),
    fecha_nacimiento: cleanString(raw.dob),
    direccion: cleanString(raw.street),
    apartamento: cleanString(raw.apt),
    ciudad: cleanString(raw.city),
    estado: cleanString(raw.state),
    zip: cleanString(raw.zip),
    proveedor_servicio: cleanString(raw.service_provider),
    proveedor_otro: cleanString(raw.service_provider_other),
    velocidad_deseada: cleanString(raw.desired_speed),
    voice_service: cleanBoolean(raw.voice_service),
    notas_instalacion: cleanString(raw.install_notes),
    autopay: cleanBoolean(raw.autopay),
    monthly_price: cleanNumber(raw.monthly_price),
    special_notes: cleanString(raw.special_notes),
    order_number: cleanString(raw.order_number),
    btn: cleanString(raw.btn),
    order_date: cleanString(raw.order_date),
    install_date: cleanDate(raw.install_date),
    card_last4: cleanString(raw.card_last4),
    signature_data: cleanString(raw.signature_data),
    payload: raw,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, { status: 405 });
  }

  try {
    const user = await requireSession(req);
    const payload = buildOrderPayload(await req.json(), user.nombre);

    if (!payload.cliente_nombre || !payload.cliente_apellido) {
      return jsonResponse({ error: "Client full name is required" }, { status: 400 });
    }

    if (!payload.telefono_primario) {
      return jsonResponse({ error: "Primary phone is required" }, { status: 400 });
    }

    if (!payload.direccion) {
      return jsonResponse({ error: "Street address is required" }, { status: 400 });
    }

    const supabase = createAdminClient();
    const { data, error } = await supabase
      .from("izzy_orders")
      .insert(payload)
      .select("*")
      .single();

    if (error) {
      console.error("[izzy-create-order] insert failed", error);
      return jsonResponse({ error: "Could not create order" }, { status: 500 });
    }

    return jsonResponse({ order: data }, { status: 201 });
  } catch (error) {
    if (error instanceof Response) {
      const body = await error.text();
      return new Response(body, {
        status: error.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.error("[izzy-create-order] unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, { status: 500 });
  }
});
