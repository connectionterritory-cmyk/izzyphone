import "@supabase/functions-js/edge-runtime.d.ts";

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireSession } from "../_shared/auth.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type LeadPayload = {
  cliente?: string;
  telefono?: string;
  direccion?: string;
  proveedor_internet?: string;
  pago_internet?: number | null;
  proveedor_telefono?: string;
  pago_telefono?: number | null;
  velocidad?: string;
  lineas?: string;
  nota?: string;
};

function cleanString(value: unknown): string {
  return String(value || "").trim();
}

function cleanNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function buildLeadPayload(raw: LeadPayload, agentName: string) {
  return {
    fecha: new Intl.DateTimeFormat("en-US", { timeZone: "America/Los_Angeles" }).format(new Date()),
    agente: agentName,
    cliente: cleanString(raw.cliente),
    telefono: cleanString(raw.telefono),
    direccion: cleanString(raw.direccion),
    proveedor_internet: cleanString(raw.proveedor_internet),
    pago_internet: cleanNumber(raw.pago_internet),
    proveedor_telefono: cleanString(raw.proveedor_telefono),
    pago_telefono: cleanNumber(raw.pago_telefono),
    velocidad: cleanString(raw.velocidad),
    lineas: cleanString(raw.lineas),
    nota: cleanString(raw.nota),
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
    const payload = buildLeadPayload(await req.json(), user.nombre);

    if (!payload.cliente) {
      return jsonResponse({ error: "Client name is required" }, { status: 400 });
    }

    const supabase = createAdminClient();
    const { data, error } = await supabase
      .from("izzy_leads")
      .insert(payload)
      .select("*")
      .single();

    if (error) {
      console.error("[izzy-create-lead] insert failed", error);
      return jsonResponse({ error: "Could not create lead" }, { status: 500 });
    }

    return jsonResponse({ lead: data }, { status: 201 });
  } catch (error) {
    if (error instanceof Response) {
      const body = await error.text();
      return new Response(body, {
        status: error.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.error("[izzy-create-lead] unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, { status: 500 });
  }
});
