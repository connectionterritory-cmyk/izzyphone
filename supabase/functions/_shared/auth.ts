export type Role = "admin" | "agente";

export type SessionUser = {
  nombre: string;
  rol: Role;
};

type UserRecord = SessionUser & {
  pin: string;
};

type SessionPayload = SessionUser & {
  exp: number;
  iat: number;
};

const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const encoder = new TextEncoder();

function toBase64Url(bytes: Uint8Array): string {
  const bin = Array.from(bytes, (b) => String.fromCharCode(b)).join("");
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4);
  const bin = atob(padded);
  return Uint8Array.from(bin, (char) => char.charCodeAt(0));
}

async function hmacSign(input: string): Promise<string> {
  const secret = Deno.env.get("IZZY_SESSION_SECRET");
  if (!secret) {
    throw new Error("Missing IZZY_SESSION_SECRET");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(input));
  return toBase64Url(new Uint8Array(signature));
}

function normalizePin(pin: string): string {
  return pin.trim().toUpperCase();
}

function getUsers(): UserRecord[] {
  const raw = Deno.env.get("IZZY_USERS_JSON");
  if (!raw) {
    throw new Error("Missing IZZY_USERS_JSON");
  }

  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) {
    throw new Error("IZZY_USERS_JSON must be an array");
  }

  return parsed.map((item) => ({
    pin: normalizePin(String(item.pin || "")),
    nombre: String(item.nombre || "").trim(),
    rol: item.rol === "admin" ? "admin" : "agente",
  })).filter((item) => item.pin && item.nombre);
}

export function authenticatePin(pin: string): SessionUser | null {
  const normalized = normalizePin(pin);
  const match = getUsers().find((user) => user.pin === normalized);
  return match ? { nombre: match.nombre, rol: match.rol } : null;
}

export async function createSessionToken(user: SessionUser): Promise<string> {
  const now = Date.now();
  const payload: SessionPayload = {
    ...user,
    iat: now,
    exp: now + SESSION_TTL_MS,
  };
  const encoded = toBase64Url(encoder.encode(JSON.stringify(payload)));
  const signature = await hmacSign(encoded);
  return `${encoded}.${signature}`;
}

export async function verifySessionToken(token: string): Promise<SessionUser | null> {
  const [encoded, signature] = token.split(".");
  if (!encoded || !signature) return null;

  const expected = await hmacSign(encoded);
  if (signature !== expected) return null;

  try {
    const payload = JSON.parse(new TextDecoder().decode(fromBase64Url(encoded))) as SessionPayload;
    if (!payload?.nombre || !payload?.rol || !payload?.exp) return null;
    if (Date.now() > payload.exp) return null;
    return {
      nombre: payload.nombre,
      rol: payload.rol === "admin" ? "admin" : "agente",
    };
  } catch {
    return null;
  }
}

export async function requireSession(req: Request): Promise<SessionUser> {
  const auth = req.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const user = token ? await verifySessionToken(token) : null;
  if (!user) {
    throw new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  return user;
}
