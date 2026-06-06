import "@supabase/functions-js/edge-runtime.d.ts";

import {
  authenticatePin,
  createSessionToken,
  hashPassword,
  normalizePassword,
  requireSession,
  type Role,
  verifyPassword,
} from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type PortalUser = {
  id: number;
  pin_code: string;
  nombre: string;
  rol: Role;
  active: boolean;
  password_hash?: string | null;
  password_salt?: string | null;
  created_at: string;
  updated_at: string;
};

type Quoter = {
  id: number;
  code: string;
  nombre: string;
  telefono: string;
  active: boolean;
  created_at: string;
  updated_at: string;
};

type UpdatePayload = {
  id?: number;
  updates?: Record<string, unknown>;
};

const DEFAULT_QUOTERS = [
  { code: "PCAI", nombre: "PATRICIA CAICEDO", telefono: "7862913042", active: true },
];

const ALLOWED_UPDATE_FIELDS = [
  "cliente",
  "telefono",
  "agente",
  "direccion",
  "proveedor_internet",
  "pago_internet",
  "velocidad",
  "proveedor_telefono",
  "pago_telefono",
  "lineas",
  "nota",
] as const;

function cleanString(value: unknown): string {
  return String(value || "").trim();
}

function cleanNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizePin(pin: string): string {
  return cleanString(pin).toUpperCase();
}

function normalizeCode(code: string): string {
  return cleanString(code).toUpperCase();
}

function normalizeRole(role: unknown): Role {
  return role === "admin" ? "admin" : "agente";
}

function sanitizeUpdates(raw: Record<string, unknown>, isAdmin: boolean) {
  const updates: Record<string, string | number | null> = {};

  for (const field of ALLOWED_UPDATE_FIELDS) {
    if (!(field in raw)) continue;
    if (!isAdmin && field === "agente") continue;

    if (field === "pago_internet" || field === "pago_telefono") {
      updates[field] = cleanNumber(raw[field]);
      continue;
    }

    updates[field] = cleanString(raw[field]);
  }

  return updates;
}

async function getQuoters(supabase: ReturnType<typeof createAdminClient>) {
  const { data, error } = await supabase
    .from("izzy_quoters")
    .select("*")
    .eq("active", true)
    .order("nombre", { ascending: true });

  if (!error && data?.length) {
    return data as Quoter[];
  }

  return DEFAULT_QUOTERS as Quoter[];
}

async function authenticatePortalUser(pin: string, password: string, supabase: ReturnType<typeof createAdminClient>) {
  const normalized = normalizePin(pin);
  if (!normalized) return null;

  const { data, error } = await supabase
    .from("izzy_portal_users")
    .select("nombre, rol, active, password_hash, password_salt")
    .eq("pin_code", normalized)
    .maybeSingle();

  if (error) {
    console.error("[izzy-admin-leads] login lookup failed", error);
    return null;
  }

  if (data?.active) {
    const mustSetPassword = !(data.password_hash && data.password_salt);
    if (data.password_hash && data.password_salt) {
      const validPassword = await verifyPassword(password, data.password_salt, data.password_hash);
      if (!validPassword) return null;
    }
    return { user: { nombre: data.nombre, rol: normalizeRole(data.rol), pin_code: normalized }, mustSetPassword };
  }

  const legacyUser = authenticatePin(normalized);
  return legacyUser ? { user: legacyUser, mustSetPassword: false } : null;
}

function ensureAdmin(user: { rol: Role }) {
  if (user.rol !== "admin") {
    throw new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }
}

async function handleLogin(req: Request) {
  const body = await req.json();
  const supabase = createAdminClient();
  const user = await authenticatePortalUser(String(body?.pin || ""), normalizePassword(body?.password), supabase);

  if (!user) {
    return jsonResponse({ error: "Invalid access code" }, { status: 401 });
  }

  const token = await createSessionToken(user.user);
  return jsonResponse({ token, user: user.user, must_set_password: user.mustSetPassword });
}

async function handleLeadList(user: { nombre: string; rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  let query = supabase.from("izzy_leads").select("*").order("created_at", { ascending: false });
  if (user.rol !== "admin") {
    query = query.eq("agente", user.nombre);
  }

  const { data, error } = await query;
  if (error) {
    console.error("[izzy-admin-leads] fetch leads failed", error);
    return jsonResponse({ error: "Could not fetch leads" }, { status: 500 });
  }

  return jsonResponse({ leads: data ?? [] });
}

async function handleAdminConfig(user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);

  const [{ data: users, error: usersError }, { data: quoters, error: quotersError }] = await Promise.all([
    supabase.from("izzy_portal_users").select("id, pin_code, nombre, rol, active, created_at, updated_at, password_hash").order("nombre", { ascending: true }),
    supabase.from("izzy_quoters").select("*").order("nombre", { ascending: true }),
  ]);

  if (usersError || quotersError) {
    console.error("[izzy-admin-leads] fetch admin config failed", { usersError, quotersError });
    return jsonResponse({ error: "Could not load admin config" }, { status: 500 });
  }

  return jsonResponse({
    users: (users ?? []).map((row) => ({ ...row, password_set: Boolean(row.password_hash) })),
    quoters: quoters ?? [],
  });
}

async function handleCreateUser(req: Request, user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);
  const body = await req.json();
  const password = normalizePassword(body?.password);

  const payload = {
    pin_code: normalizePin(body?.pin_code || body?.pin || ""),
    nombre: cleanString(body?.nombre),
    rol: normalizeRole(body?.rol),
    active: body?.active === false ? false : true,
  };

  if (!payload.pin_code || !payload.nombre || !password) {
    return jsonResponse({ error: "pin_code, nombre and password are required" }, { status: 400 });
  }

  const passwordData = await hashPassword(password);

  const { data, error } = await supabase
    .from("izzy_portal_users")
    .insert({ ...payload, password_hash: passwordData.hash, password_salt: passwordData.salt })
    .select("id, pin_code, nombre, rol, active, created_at, updated_at")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] create user failed", error);
    return jsonResponse({ error: "Could not create user" }, { status: 500 });
  }

  return jsonResponse({ user: data }, { status: 201 });
}

async function handleResetUserPassword(req: Request, user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);
  const body = await req.json();
  const userId = Number(body?.user_id);
  const password = normalizePassword(body?.password);

  if (!Number.isInteger(userId) || userId <= 0 || !password) {
    return jsonResponse({ error: "user_id and password are required" }, { status: 400 });
  }

  const passwordData = await hashPassword(password);
  const { data, error } = await supabase
    .from("izzy_portal_users")
    .update({ password_hash: passwordData.hash, password_salt: passwordData.salt })
    .eq("id", userId)
    .select("id, pin_code, nombre, rol, active, created_at, updated_at")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] reset password failed", error);
    return jsonResponse({ error: "Could not reset password" }, { status: 500 });
  }

  return jsonResponse({ user: data });
}

async function handleSelfPassword(req: Request, user: { nombre: string; rol: Role; pin_code?: string }, supabase: ReturnType<typeof createAdminClient>) {
  const body = await req.json();
  const password = normalizePassword(body?.password);

  if (!user.pin_code || !password) {
    return jsonResponse({ error: "password is required" }, { status: 400 });
  }

  const passwordData = await hashPassword(password);
  const { data, error } = await supabase
    .from("izzy_portal_users")
    .update({ password_hash: passwordData.hash, password_salt: passwordData.salt })
    .eq("pin_code", user.pin_code)
    .select("id, pin_code, nombre, rol, active, created_at, updated_at")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] self password failed", error);
    return jsonResponse({ error: "Could not save password" }, { status: 500 });
  }

  return jsonResponse({ user: data, password_set: true });
}

async function handleCreateQuoter(req: Request, user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);
  const body = await req.json();

  const payload = {
    code: normalizeCode(body?.code),
    nombre: cleanString(body?.nombre),
    telefono: cleanString(body?.telefono),
    active: body?.active === false ? false : true,
  };

  if (!payload.code || !payload.nombre || !payload.telefono) {
    return jsonResponse({ error: "code, nombre and telefono are required" }, { status: 400 });
  }

  const { data, error } = await supabase
    .from("izzy_quoters")
    .insert(payload)
    .select("*")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] create quoter failed", error);
    return jsonResponse({ error: "Could not create quoter" }, { status: 500 });
  }

  return jsonResponse({ quoter: data }, { status: 201 });
}

async function handleGet(req: Request) {
  const user = await requireSession(req);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "leads";
  const supabase = createAdminClient();

  if (resource === "quoters") {
    const quoters = await getQuoters(supabase);
    return jsonResponse({ quoters });
  }

  if (resource === "admin-config") {
    return await handleAdminConfig(user, supabase);
  }

  return await handleLeadList(user, supabase);
}

async function handleUpdate(req: Request) {
  const user = await requireSession(req);
  const body = await req.json() as UpdatePayload;
  const id = Number(body?.id);

  if (!Number.isInteger(id) || id <= 0) {
    return jsonResponse({ error: "Lead id is required" }, { status: 400 });
  }

  const updates = sanitizeUpdates(body?.updates || {}, user.rol === "admin");
  if (Object.keys(updates).length === 0) {
    return jsonResponse({ error: "No valid updates provided" }, { status: 400 });
  }

  const supabase = createAdminClient();

  if (user.rol !== "admin") {
    const { data: existing, error: existingError } = await supabase
      .from("izzy_leads")
      .select("id, agente")
      .eq("id", id)
      .maybeSingle();

    if (existingError) {
      console.error("[izzy-admin-leads] ownership check failed", existingError);
      return jsonResponse({ error: "Could not verify lead ownership" }, { status: 500 });
    }

    if (!existing || existing.agente !== user.nombre) {
      return jsonResponse({ error: "Forbidden" }, { status: 403 });
    }
  }

  const { data, error } = await supabase
    .from("izzy_leads")
    .update(updates)
    .eq("id", id)
    .select("*")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] update lead failed", error);
    return jsonResponse({ error: "Could not update lead" }, { status: 500 });
  }

  return jsonResponse({ lead: data });
}

async function handlePost(req: Request) {
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource");

  if (!resource) {
    return await handleLogin(req);
  }

  const user = await requireSession(req);
  const supabase = createAdminClient();

  if (resource === "users") {
    return await handleCreateUser(req, user, supabase);
  }

  if (resource === "user-password") {
    return await handleResetUserPassword(req, user, supabase);
  }

  if (resource === "self-password") {
    return await handleSelfPassword(req, user, supabase);
  }

  if (resource === "quoters") {
    return await handleCreateQuoter(req, user, supabase);
  }

  return jsonResponse({ error: "Unknown resource" }, { status: 400 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "POST") {
      return await handlePost(req);
    }
    if (req.method === "GET") {
      return await handleGet(req);
    }
    if (req.method === "PATCH") {
      return await handleUpdate(req);
    }
    return jsonResponse({ error: "Method not allowed" }, { status: 405 });
  } catch (error) {
    if (error instanceof Response) {
      const body = await error.text();
      return new Response(body, {
        status: error.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.error("[izzy-admin-leads] unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, { status: 500 });
  }
});
