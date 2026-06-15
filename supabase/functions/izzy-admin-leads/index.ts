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
  email?: string | null;
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

type PasswordResetRequest = {
  id: number;
  user_id: number | null;
  pin_code: string | null;
  email: string | null;
  status: "pending" | "resolved";
  requested_at: string;
  resolved_at: string | null;
  user?: { nombre?: string | null } | null;
};

type UpdatePayload = {
  id?: number;
  updates?: Record<string, unknown>;
};

type InstallationStatus =
  | "submitted"
  | "scheduled"
  | "installed_pending_confirmation"
  | "confirmed_satisfied"
  | "cancelled"
  | "failed_install";

type SatisfactionStatus = "pending" | "satisfied" | "issue" | "cancelled";

type CommissionStatus = "not_earned" | "earned" | "paid" | "cancelled";

type OrderRow = {
  id: number;
  agente: string;
  carrier_name: string | null;
  install_date: string | null;
  installation_status: InstallationStatus | null;
  scheduled_install_date: string | null;
  actual_install_date: string | null;
  satisfaction_status: SatisfactionStatus | null;
  satisfaction_confirmed_at: string | null;
  commission_status: CommissionStatus | null;
  commission_earned_at: string | null;
  commission_amount: number | null;
  commission_paid_at: string | null;
  compensation_status: string | null;
  reserve_release_at: string | null;
};

const DEFAULT_QUOTERS = [
  { code: "PCAI", nombre: "PATRICIA CAICEDO", telefono: "7862913042", active: true },
];
const PASSWORD_RESET_TTL_HOURS = 2;

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
  "estado",
  "cotizacion_enviada",
  "cotizacion_at",
] as const;

const ORDER_INSTALLATION_STATUSES = new Set<InstallationStatus>([
  "submitted",
  "scheduled",
  "installed_pending_confirmation",
  "confirmed_satisfied",
  "cancelled",
  "failed_install",
]);

const ORDER_SATISFACTION_STATUSES = new Set<SatisfactionStatus>([
  "pending",
  "satisfied",
  "issue",
  "cancelled",
]);

const ORDER_COMMISSION_STATUSES = new Set<CommissionStatus>([
  "not_earned",
  "earned",
  "paid",
  "cancelled",
]);

function cleanString(value: unknown): string {
  return String(value || "").trim();
}

function cleanNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function cleanDate(value: unknown): string | null {
  const raw = cleanString(value);
  return raw || null;
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

function normalizeEmail(email: unknown): string {
  return cleanString(email).toLowerCase();
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

function sanitizeOrderUpdates(raw: Record<string, unknown>, isAdmin: boolean) {
  const updates: Record<string, string | number | null> = {};

  if ("scheduled_install_date" in raw) {
    updates.scheduled_install_date = cleanDate(raw.scheduled_install_date);
    updates.install_date = updates.scheduled_install_date;
  }

  if ("actual_install_date" in raw) {
    updates.actual_install_date = cleanDate(raw.actual_install_date);
  }

  if ("installation_status" in raw) {
    const value = cleanString(raw.installation_status) as InstallationStatus;
    if (ORDER_INSTALLATION_STATUSES.has(value)) {
      updates.installation_status = value;
    }
  }

  if ("satisfaction_status" in raw) {
    const value = cleanString(raw.satisfaction_status) as SatisfactionStatus;
    if (ORDER_SATISFACTION_STATUSES.has(value)) {
      updates.satisfaction_status = value;
    }
  }

  if (isAdmin && "commission_status" in raw) {
    const value = cleanString(raw.commission_status) as CommissionStatus;
    if (ORDER_COMMISSION_STATUSES.has(value)) {
      updates.commission_status = value;
    }
  }

  if (isAdmin && "commission_amount" in raw) {
    updates.commission_amount = cleanNumber(raw.commission_amount);
  }

  if ("satisfaction_notes" in raw) {
    updates.satisfaction_notes = cleanString(raw.satisfaction_notes) || null;
  }

  return updates;
}

function nowIso() {
  return new Date().toISOString();
}

function addReserveDays(dateValue: string, days: number) {
  const date = new Date(`${dateValue}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return null;
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString();
}

function deriveOrderUpdates(
  existing: OrderRow,
  incoming: Record<string, string | number | null>,
  agentName: string,
): Record<string, string | number | null> {
  const next: Record<string, string | number | null> = { ...incoming };

  const installationStatus = (next.installation_status ?? existing.installation_status ?? "submitted") as InstallationStatus;
  const actualInstallDate = cleanDate(next.actual_install_date ?? existing.actual_install_date);
  const currentCommissionStatus = (next.commission_status ?? existing.commission_status ?? "not_earned") as CommissionStatus;

  if (installationStatus === "scheduled" && !("scheduled_install_date" in next)) {
    next.scheduled_install_date = existing.scheduled_install_date ?? existing.install_date;
    next.install_date = next.scheduled_install_date;
  }

  if (installationStatus === "confirmed_satisfied") {
    if (!actualInstallDate) {
      throw new Response(JSON.stringify({ error: "actual_install_date is required before confirming satisfaction" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    next.satisfaction_status = "satisfied";
    // Record who confirmed and when (only set once, never overwrite)
    if (!existing.satisfaction_confirmed_at) {
      next.satisfaction_confirmed_at = nowIso();
      next.satisfaction_confirmed_by = agentName;
    }
  }

  if ((next.satisfaction_status ?? existing.satisfaction_status) === "satisfied" && !actualInstallDate) {
    throw new Response(JSON.stringify({ error: "actual_install_date is required when satisfaction_status is satisfied" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const resolvedSatisfactionStatus = (next.satisfaction_status ?? existing.satisfaction_status ?? "pending") as SatisfactionStatus;

  if (installationStatus === "cancelled") {
    next.satisfaction_status = "cancelled";
    if (currentCommissionStatus !== "paid") {
      next.commission_status = "cancelled";
      next.commission_earned_at = null;
    }
    next.compensation_status = "chargeback";
  } else if (installationStatus === "failed_install") {
    if (resolvedSatisfactionStatus === "pending") {
      next.satisfaction_status = "issue";
    }
    if (currentCommissionStatus !== "paid") {
      next.commission_status = "cancelled";
      next.commission_earned_at = null;
    }
    next.compensation_status = "chargeback";
  }

  const finalSatisfactionStatus = (next.satisfaction_status ?? existing.satisfaction_status ?? "pending") as SatisfactionStatus;

  if (actualInstallDate && finalSatisfactionStatus === "satisfied") {
    next.installation_status = "confirmed_satisfied";
    if (currentCommissionStatus !== "paid") {
      next.commission_status = "earned";
      next.commission_earned_at = existing.commission_status === "earned" && existing.commission_earned_at
        ? existing.commission_earned_at
        : nowIso();
    }
    if (existing.compensation_status !== "paid") {
      next.compensation_status = "reserve";
      next.reserve_release_at = existing.reserve_release_at || addReserveDays(actualInstallDate, 120);
    }
  } else {
    // FIX: use next.commission_status (which may have been set to "cancelled" by the blocks
    // above) rather than currentCommissionStatus (the stale value from before those mutations).
    const latestCommissionStatus = (
      next.commission_status != null ? next.commission_status as CommissionStatus : currentCommissionStatus
    );
    if (latestCommissionStatus !== "paid" && latestCommissionStatus !== "cancelled") {
      next.commission_status = "not_earned";
      next.commission_earned_at = null;
    }
  }

  // When admin marks commission as paid, stamp who paid and when (only once)
  if (next.commission_status === "paid" && existing.commission_status !== "paid") {
    if (!next.commission_paid_at) next.commission_paid_at = nowIso();
    if (!next.commission_paid_by) next.commission_paid_by = agentName;
    next.compensation_status = "paid";
  }

  return next;
}

function getAppUrl() {
  return cleanString(Deno.env.get("IZZY_APP_URL")) || "https://izzyphone.vercel.app";
}

function getResendConfig() {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL");
  const fromName = Deno.env.get("RESEND_FROM_NAME") || "Izzy Communications";
  if (!apiKey || !fromEmail) return null;
  return { apiKey, fromEmail, fromName };
}

async function sha256(input: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function createPasswordResetToken(supabase: ReturnType<typeof createAdminClient>, userId: number) {
  const token = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
  const tokenHash = await sha256(token);
  const expiresAt = new Date(Date.now() + PASSWORD_RESET_TTL_HOURS * 60 * 60 * 1000).toISOString();

  await supabase
    .from("izzy_password_reset_tokens")
    .update({ used_at: new Date().toISOString() })
    .eq("user_id", userId)
    .is("used_at", null);

  const { error } = await supabase
    .from("izzy_password_reset_tokens")
    .insert({
      user_id: userId,
      token_hash: tokenHash,
      expires_at: expiresAt,
    });

  if (error) {
    throw error;
  }

  return { token, expiresAt };
}

async function sendPasswordResetEmail(email: string, nombre: string, token: string) {
  const resend = getResendConfig();
  if (!resend) {
    throw new Error("Missing Resend configuration");
  }

  const resetUrl = `${getAppUrl().replace(/\/$/, "")}/?reset_token=${encodeURIComponent(token)}`;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resend.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `${resend.fromName} <${resend.fromEmail}>`,
      to: [email],
      subject: "Recupera tu acceso a Izzy Communications",
      html: `
        <div style="font-family:Arial,sans-serif;line-height:1.6;color:#111827">
          <h2 style="margin-bottom:12px;color:#1a3a6b">Izzy Communications</h2>
          <p>Hola ${nombre || "equipo"},</p>
          <p>Recibimos una solicitud para restablecer tu password del portal.</p>
          <p>
            <a href="${resetUrl}" style="display:inline-block;padding:12px 18px;background:#1a3a6b;color:#ffffff;text-decoration:none;border-radius:10px;font-weight:700">
              Crear nueva password
            </a>
          </p>
          <p>Este enlace vence en ${PASSWORD_RESET_TTL_HOURS} horas y solo se puede usar una vez.</p>
          <p>Si no pediste este cambio, puedes ignorar este correo.</p>
        </div>
      `,
    }),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Resend error: ${details}`);
  }

  return resetUrl;
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

async function handleOrderList(user: { nombre: string; rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  let query = supabase.from("izzy_orders").select("*").order("created_at", { ascending: false });
  if (user.rol !== "admin") {
    query = query.eq("agente", user.nombre);
  }

  const { data, error } = await query;
  if (error) {
    console.error("[izzy-admin-leads] fetch orders failed", error);
    return jsonResponse({ error: "Could not fetch orders" }, { status: 500 });
  }

  return jsonResponse({ orders: data ?? [] });
}

async function updateOrderById(
  id: number,
  user: { nombre: string; rol: Role },
  supabase: ReturnType<typeof createAdminClient>,
  updates: Record<string, string | number | null>,
) {
  const { data: existing, error: existingError } = await supabase
    .from("izzy_orders")
    .select("id, agente, carrier_name, install_date, installation_status, scheduled_install_date, actual_install_date, satisfaction_status, satisfaction_confirmed_at, commission_status, commission_earned_at, commission_amount, commission_paid_at, compensation_status, reserve_release_at")
    .eq("id", id)
    .maybeSingle();

  if (existingError) {
    console.error("[izzy-admin-leads] order ownership check failed", existingError);
    return jsonResponse({ error: "Could not verify order ownership" }, { status: 500 });
  }

  if (!existing) {
    return jsonResponse({ error: "Order not found" }, { status: 404 });
  }

  if (user.rol !== "admin" && existing.agente !== user.nombre) {
    return jsonResponse({ error: "Forbidden" }, { status: 403 });
  }

  const derivedUpdates = deriveOrderUpdates(existing as OrderRow, updates, user.nombre);

  const { data, error } = await supabase
    .from("izzy_orders")
    .update(derivedUpdates)
    .eq("id", id)
    .select("*")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] update order failed", error);
    return jsonResponse({ error: "Could not update order" }, { status: 500 });
  }

  return jsonResponse({ order: data });
}

async function handleAdminConfig(user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);

  const [{ data: users, error: usersError }, { data: quoters, error: quotersError }, { data: resetRequests, error: resetError }] = await Promise.all([
    supabase.from("izzy_portal_users").select("id, pin_code, nombre, email, rol, compensation_role, active, created_at, updated_at, password_hash").order("nombre", { ascending: true }),
    supabase.from("izzy_quoters").select("*").order("nombre", { ascending: true }),
    supabase.from("izzy_password_reset_requests").select("id, user_id, pin_code, email, status, requested_at, resolved_at, user:izzy_portal_users(nombre)").order("requested_at", { ascending: false }).limit(20),
  ]);

  if (usersError || quotersError || resetError) {
    console.error("[izzy-admin-leads] fetch admin config failed", { usersError, quotersError, resetError });
    return jsonResponse({ error: "Could not load admin config" }, { status: 500 });
  }

  return jsonResponse({
    users: (users ?? []).map((row) => ({ ...row, password_set: Boolean(row.password_hash) })),
    quoters: quoters ?? [],
    reset_requests: resetRequests ?? [],
  });
}

async function handleCreateUser(req: Request, user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);
  const body = await req.json();
  const password = normalizePassword(body?.password);

  const payload = {
    pin_code: normalizePin(body?.pin_code || body?.pin || ""),
    nombre: cleanString(body?.nombre),
    email: normalizeEmail(body?.email),
    rol: normalizeRole(body?.rol),
    compensation_role: normalizeCompensationRole(body?.compensation_role),
    active: body?.active === false ? false : true,
  };

  if (!payload.pin_code || !payload.nombre || !payload.email || !password) {
    return jsonResponse({ error: "pin_code, nombre, email and password are required" }, { status: 400 });
  }

  const passwordData = await hashPassword(password);

  const { data, error } = await supabase
    .from("izzy_portal_users")
    .insert({ ...payload, password_hash: passwordData.hash, password_salt: passwordData.salt })
    .select("id, pin_code, nombre, email, rol, compensation_role, active, created_at, updated_at")
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
    .select("id, pin_code, nombre, email, rol, compensation_role, active, created_at, updated_at")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] reset password failed", error);
    return jsonResponse({ error: "Could not reset password" }, { status: 500 });
  }

  await supabase
    .from("izzy_password_reset_requests")
    .update({ status: "resolved", resolved_at: new Date().toISOString() })
    .eq("status", "pending")
    .eq("user_id", userId);

  return jsonResponse({ user: data });
}

async function handleUpdateUserEmail(req: Request, user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);
  const body = await req.json();
  const userId = Number(body?.user_id);
  const rawEmail = cleanString(body?.email);
  const email = rawEmail ? normalizeEmail(rawEmail) : null;

  if (!Number.isInteger(userId) || userId <= 0) {
    return jsonResponse({ error: "user_id is required" }, { status: 400 });
  }

  const { data, error } = await supabase
    .from("izzy_portal_users")
    .update({ email })
    .eq("id", userId)
    .select("id, pin_code, nombre, email, rol, compensation_role, active, created_at, updated_at")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] update email failed", error);
    return jsonResponse({ error: "Could not update email" }, { status: 500 });
  }

  return jsonResponse({ user: data });
}

async function handleResolveResetRequest(req: Request, user: { rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  ensureAdmin(user);
  const body = await req.json();
  const requestId = Number(body?.request_id);

  if (!Number.isInteger(requestId) || requestId <= 0) {
    return jsonResponse({ error: "request_id is required" }, { status: 400 });
  }

  const { data, error } = await supabase
    .from("izzy_password_reset_requests")
    .update({ status: "resolved", resolved_at: new Date().toISOString() })
    .eq("id", requestId)
    .select("id, user_id, pin_code, email, status, requested_at, resolved_at, user:izzy_portal_users(nombre)")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] resolve reset request failed", error);
    return jsonResponse({ error: "Could not resolve request" }, { status: 500 });
  }

  return jsonResponse({ request: data });
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
    .select("id, pin_code, nombre, email, rol, active, created_at, updated_at")
    .single();

  if (error) {
    console.error("[izzy-admin-leads] self password failed", error);
    return jsonResponse({ error: "Could not save password" }, { status: 500 });
  }

  return jsonResponse({ user: data, password_set: true });
}

async function handleForgotPassword(req: Request) {
  const body = await req.json();
  const pin = normalizePin(body?.pin || "");
  const email = normalizeEmail(body?.email);
  const supabase = createAdminClient();

  if (!pin && !email) {
    return jsonResponse({ error: "pin or email is required" }, { status: 400 });
  }

  let query = supabase
    .from("izzy_portal_users")
    .select("id, pin_code, nombre, email, active")
    .eq("active", true)
    .limit(1);

  query = pin ? query.eq("pin_code", pin) : query.eq("email", email);
  const { data: portalUser, error } = await query.maybeSingle();

  if (error) {
    console.error("[izzy-admin-leads] forgot password lookup failed", error);
    return jsonResponse({ error: "Could not create request" }, { status: 500 });
  }

  if (!portalUser?.email) {
    return jsonResponse({
      ok: true,
      created: false,
      message: "No encontramos un email registrado para este usuario. Contacta al administrador.",
    });
  }

  const { data: existingRequest } = await supabase
    .from("izzy_password_reset_requests")
    .select("id")
    .eq("user_id", portalUser.id)
    .eq("status", "pending")
    .limit(1)
    .maybeSingle();

  if (!existingRequest) {
    const { error: insertError } = await supabase
      .from("izzy_password_reset_requests")
      .insert({
        user_id: portalUser.id,
        pin_code: portalUser.pin_code,
        email: portalUser.email,
        status: "pending",
      });

    if (insertError) {
      console.error("[izzy-admin-leads] forgot password insert failed", insertError);
      return jsonResponse({ error: "Could not create request" }, { status: 500 });
    }
  }

  try {
    const { token } = await createPasswordResetToken(supabase, portalUser.id);
    await sendPasswordResetEmail(portalUser.email, portalUser.nombre, token);
  } catch (sendError) {
    console.error("[izzy-admin-leads] forgot password email failed", sendError);
    return jsonResponse({
      ok: false,
      error: "No se pudo enviar el correo de recuperacion.",
    }, { status: 500 });
  }

  return jsonResponse({
    ok: true,
    created: true,
    message: `Te enviamos un enlace de recuperacion a ${portalUser.email}.`,
  });
}

async function handleResetPasswordWithToken(req: Request) {
  const body = await req.json();
  const token = cleanString(body?.token);
  const password = normalizePassword(body?.password);
  const supabase = createAdminClient();

  if (!token || !password) {
    return jsonResponse({ error: "token and password are required" }, { status: 400 });
  }

  const tokenHash = await sha256(token);
  const now = new Date().toISOString();
  const { data: resetRow, error } = await supabase
    .from("izzy_password_reset_tokens")
    .select("id, user_id, expires_at, used_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (error || !resetRow || resetRow.used_at || resetRow.expires_at < now) {
    return jsonResponse({ error: "Reset link is invalid or expired" }, { status: 400 });
  }

  const passwordData = await hashPassword(password);
  const { error: updateError } = await supabase
    .from("izzy_portal_users")
    .update({ password_hash: passwordData.hash, password_salt: passwordData.salt })
    .eq("id", resetRow.user_id);

  if (updateError) {
    console.error("[izzy-admin-leads] token password update failed", updateError);
    return jsonResponse({ error: "Could not update password" }, { status: 500 });
  }

  await supabase
    .from("izzy_password_reset_tokens")
    .update({ used_at: now })
    .eq("id", resetRow.id);

  await supabase
    .from("izzy_password_reset_requests")
    .update({ status: "resolved", resolved_at: now })
    .eq("status", "pending")
    .eq("user_id", resetRow.user_id);

  return jsonResponse({ ok: true });
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
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "leads";
  const supabase = createAdminClient();

  if (resource === "quoters") {
    const quoters = await getQuoters(supabase);
    return jsonResponse({ quoters });
  }

  const user = await requireSession(req);

  if (resource === "admin-config") {
    return await handleAdminConfig(user, supabase);
  }

  if (resource === "orders") {
    return await handleOrderList(user, supabase);
  }

  return await handleLeadList(user, supabase);
}

async function handleUpdate(req: Request) {
  const user = await requireSession(req);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "leads";
  const body = await req.json() as UpdatePayload;
  const id = Number(body?.id);

  if (!Number.isInteger(id) || id <= 0) {
    return jsonResponse({ error: `${resource === "orders" ? "Order" : "Lead"} id is required` }, { status: 400 });
  }

  const supabase = createAdminClient();

  if (resource === "orders") {
    const updates = sanitizeOrderUpdates(body?.updates || {}, user.rol === "admin");
    if (Object.keys(updates).length === 0) {
      return jsonResponse({ error: "No valid order updates provided" }, { status: 400 });
    }
    return await updateOrderById(id, user, supabase, updates);
  }

  const updates = sanitizeUpdates(body?.updates || {}, user.rol === "admin");
  if (Object.keys(updates).length === 0) {
    return jsonResponse({ error: "No valid updates provided" }, { status: 400 });
  }

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

async function handleDelete(req: Request) {
  const user = await requireSession(req);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "lead";
  const id = Number(url.searchParams.get("id"));

  if (resource !== "lead") {
    return jsonResponse({ error: "Unknown resource" }, { status: 400 });
  }
  const supabase = createAdminClient();
  return await deleteLeadById(id, user, supabase);
}

async function deleteLeadById(id: number, user: { nombre: string; rol: Role }, supabase: ReturnType<typeof createAdminClient>) {
  if (!Number.isInteger(id) || id <= 0) {
    return jsonResponse({ error: "Lead id is required" }, { status: 400 });
  }

  if (user.rol !== "admin") {
    const { data: existing, error: existingError } = await supabase
      .from("izzy_leads")
      .select("id, agente")
      .eq("id", id)
      .maybeSingle();

    if (existingError) {
      console.error("[izzy-admin-leads] ownership delete check failed", existingError);
      return jsonResponse({ error: "Could not verify lead ownership" }, { status: 500 });
    }

    if (!existing || existing.agente !== user.nombre) {
      return jsonResponse({ error: "Forbidden" }, { status: 403 });
    }
  }

  const { error } = await supabase
    .from("izzy_leads")
    .delete()
    .eq("id", id);

  if (error) {
    console.error("[izzy-admin-leads] delete lead failed", error);
    return jsonResponse({ error: "Could not delete lead" }, { status: 500 });
  }

  return jsonResponse({ ok: true, id });
}

async function handlePost(req: Request) {
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource");

  if (!resource) {
    return await handleLogin(req);
  }

  if (resource === "forgot-password") {
    return await handleForgotPassword(req);
  }

  if (resource === "reset-password") {
    return await handleResetPasswordWithToken(req);
  }

  const user = await requireSession(req);
  const supabase = createAdminClient();

  if (resource === "users") {
    return await handleCreateUser(req, user, supabase);
  }

  if (resource === "user-password") {
    return await handleResetUserPassword(req, user, supabase);
  }

  if (resource === "user-email") {
    return await handleUpdateUserEmail(req, user, supabase);
  }

  if (resource === "resolve-reset-request") {
    return await handleResolveResetRequest(req, user, supabase);
  }

  if (resource === "self-password") {
    return await handleSelfPassword(req, user, supabase);
  }

  if (resource === "quoters") {
    return await handleCreateQuoter(req, user, supabase);
  }

  if (resource === "delete-lead") {
    const body = await req.json().catch(() => ({}));
    return await deleteLeadById(Number(body?.id), user, supabase);
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
    if (req.method === "DELETE") {
      return await handleDelete(req);
    }
    return jsonResponse({ error: "Method not allowed" }, { status: 405 });
  } catch (error) {
    if (error instanceof Response) {
      const body = await error.text();
      return new Response(body, {
        status: Number.isInteger(error.status) && error.status >= 200 && error.status <= 599 ? error.status : 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.error("[izzy-admin-leads] unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, { status: 500 });
  }
});
