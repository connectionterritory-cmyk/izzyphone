// Phase 1 guard: GET ?resource=dashboard on izzy-compensation must perform ZERO writes.
// Runs the REAL handler (supabase/functions/izzy-compensation/index.ts) against a recording in-memory DB
// seeded so the old code WOULD have written (due reserve + promotable user).
import { register } from "node:module";
import crypto from "node:crypto";
import assert from "node:assert/strict";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
register(pathToFileURL(path.join(here, "hooks.mjs")));

const past = "2020-01-01T00:00:00.000Z";
const now = new Date();
const thisMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 5)).toISOString();

function seed() {
  return {
    izzy_portal_users: [
      { id: 1, nombre: "Admin", rol: "admin", compensation_role: "director", sponsor_user_id: null, manager_user_id: null, active: true, pin_code: "0001" },
      { id: 2, nombre: "Ana", rol: "agente", compensation_role: "novato", sponsor_user_id: 1, manager_user_id: 1, active: true, pin_code: "0002" },
    ],
    izzy_orders: [
      { id: 10, agente: "Ana", portal_user_id: 2, service_category_code: "basic", sale_type: "residential", carrier_name: "X", compensation_status: "reserve", compensation_rank_code: "novato", compensation_estimated_amount: 50, actual_install_date: "2020-01-02", installation_status: "confirmed_satisfied", satisfaction_status: "satisfied", reserve_release_at: past, ambassador_id: null, created_at: thisMonth },
      ...[11, 12, 13].map((id) => ({ id, agente: "Ana", portal_user_id: 2, service_category_code: "basic", sale_type: "residential", carrier_name: "X", compensation_status: "approved", compensation_rank_code: "novato", compensation_estimated_amount: 50, actual_install_date: thisMonth.slice(0, 10), installation_status: "confirmed_satisfied", satisfaction_status: "satisfied", reserve_release_at: null, ambassador_id: null, created_at: thisMonth })),
    ],
    izzy_commission_reserves: [{ id: 1, order_id: 10, carrier_name: "X", reserve_days: 120, status: "reserved", reserve_started_at: past, release_at: past, released_at: null, notes: null }],
    izzy_agent_rank_history: [],
    izzy_rank_levels: [{ code: "novato", name: "Novato", sort_order: 1, is_career: true, active: true }, { code: "agente", name: "Agente", sort_order: 2, is_career: true, active: true }],
    izzy_service_categories: [{ code: "basic", name: "Basic", sort_order: 1, active: true, visible_examples: [] }],
    izzy_carriers: [], izzy_compensation_plans: [], izzy_compensation_promotions: [],
    izzy_commission_rates: [{ id: 1, rank_code: "novato", service_category_code: "basic", sale_type: "residential", amount: 50, active: true }],
    izzy_director_bonus_rates: [], izzy_activity_rules: [],
    izzy_rank_requirements: [{ from_rank_code: "novato", to_rank_code: "agente", min_lifetime_personal_installs: 1, min_active_agents: 0, min_active_supervisors: 0, min_org_installs_month: 0, active: true }],
    izzy_compensation_settings: [], izzy_ambassadors: [], izzy_compensation_audit_log: [],
  };
}

class FakeDb {
  constructor() { this.tables = seed(); this.mutations = []; this.reads = 0; }
  hash() { return crypto.createHash("sha256").update(JSON.stringify(this.tables)).digest("hex"); }
  client() {
    const db = this;
    return {
      from(table) {
        const rows = () => db.tables[table] ?? (db.tables[table] = []);
        const q = { filters: [], op: "select", payload: null };
        const run = () => {
          let out = rows().filter((r) => q.filters.every((f) => f(r)));
          if (q.op === "select") { db.reads++; return { data: out.map((r) => ({ ...r })), error: null }; }
          db.mutations.push({ table, op: q.op, count: q.op === "insert" ? 1 : out.length });
          if (q.op === "update") out.forEach((r) => Object.assign(r, q.payload));
          if (q.op === "insert") rows().push({ id: rows().length + 1, ...q.payload });
          if (q.op === "delete") db.tables[table] = rows().filter((r) => !out.includes(r));
          if (q.op === "upsert") rows().push(q.payload);
          return { data: null, error: null };
        };
        const b = new Proxy({}, {
          get(_, prop) {
            if (prop === "then") return (res, rej) => Promise.resolve(run()).then(res, rej);
            if (["update", "insert", "upsert", "delete"].includes(prop)) return (p) => { q.op = prop; q.payload = p; return b; };
            if (prop === "eq") return (c, v) => (q.filters.push((r) => r[c] === v), b);
            if (prop === "in") return (c, vs) => (q.filters.push((r) => vs.includes(r[c])), b);
            if (prop === "lte") return (c, v) => (q.filters.push((r) => r[c] != null && r[c] <= v), b);
            if (prop === "maybeSingle" || prop === "single") return () => Promise.resolve(run()).then((r) => ({ data: r.data?.[0] ?? null, error: null }));
            return () => b; // select/order/limit/gte/etc.
          },
        });
        return b;
      },
    };
  }
}

let handler;
globalThis.Deno = { serve: (h) => { handler = h; }, env: { get: () => undefined } };
await import(pathToFileURL(path.resolve(here, process.env.TARGET_INDEX || "../../supabase/functions/izzy-compensation/index.ts")).href);
assert.equal(typeof handler, "function", "handler not registered");

async function get(db, url = "http://x/izzy-compensation") {
  globalThis.__DB = db;
  globalThis.__SESSION = { nombre: "Ana", rol: "agente", pin_code: "0002" };
  const res = await handler(new Request(url, { method: "GET" }));
  return { status: res.status, body: await res.json() };
}

let failures = 0;
const test = async (name, fn) => { try { await fn(); console.log("PASS", name); } catch (e) { failures++; console.log("FAIL", name, "\n ", e.message); } };

await test("GET dashboard: 0 inserts/updates/deletes and state unchanged", async () => {
  const db = new FakeDb(); const before = db.hash();
  const { status } = await get(db);
  assert.equal(status, 200);
  const c = (op) => db.mutations.filter((m) => m.op === op).length;
  assert.deepEqual({ insert: c("insert"), update: c("update"), delete: c("delete"), upsert: c("upsert") }, { insert: 0, update: 0, delete: 0, upsert: 0 }, JSON.stringify(db.mutations));
  assert.equal(db.hash(), before);
});

await test("GET dashboard x10: state hash identical, no promotion, no reserve release", async () => {
  const db = new FakeDb(); const before = db.hash();
  for (let i = 0; i < 10; i++) assert.equal((await get(db)).status, 200);
  assert.equal(db.mutations.length, 0, JSON.stringify(db.mutations));
  assert.equal(db.hash(), before);
  assert.equal(db.tables.izzy_portal_users[1].compensation_role, "novato");
  assert.equal(db.tables.izzy_agent_rank_history.length, 0);
  assert.equal(db.tables.izzy_orders[0].compensation_status, "reserve");
  assert.equal(db.tables.izzy_commission_reserves[0].status, "reserved");
  assert.equal(db.tables.izzy_commission_reserves[0].released_at, null);
});

await test("GET resource=config and resource=admin: 0 writes", async () => {
  const db = new FakeDb(); const before = db.hash();
  await get(db, "http://x/izzy-compensation?resource=config");
  globalThis.__SESSION = { nombre: "Admin", rol: "admin", pin_code: "0001" };
  const res = await handler(new Request("http://x/izzy-compensation?resource=admin"));
  assert.equal(res.status, 200);
  assert.equal(db.mutations.length, 0);
  assert.equal(db.hash(), before);
});

await test("Regression: response shape still carries legacy dashboard data", async () => {
  const { status, body } = await get(new FakeDb());
  assert.equal(status, 200);
  assert.ok(body && typeof body === "object" && !body.error, JSON.stringify(body).slice(0, 200));
  console.log("  response keys:", Object.keys(body).join(","));
  assert.ok(Object.keys(body).length >= 5);
});

await test("Self-check: the harness detects a mutation (proves the guard can fail)", async () => {
  const db = new FakeDb();
  await db.client().from("izzy_orders").update({ compensation_status: "released" }).in("id", [10]);
  assert.equal(db.mutations.length, 1);
});

process.exit(failures ? 1 : 0);
