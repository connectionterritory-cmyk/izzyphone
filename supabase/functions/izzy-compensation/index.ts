import "@supabase/functions-js/edge-runtime.d.ts";

import { requireSession, type Role } from "../_shared/auth.ts";
import {
  getAllCompUsers,
  getCompOrders,
  getDirectorBonusAmount,
  getPortalUserBySession,
  getRateAmount,
  loadCompensationConfig,
  normalizeCompensationRole,
  normalizeSaleType,
  syncRankPromotions,
  syncReserveStatuses,
  type CompensationConfig,
  type CompensationOrder,
  type PortalCompUser,
} from "../_shared/compensation.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/supabase.ts";

function ensureAdmin(role: Role) {
  if (role !== "admin") {
    throw new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }
}

function safeResponseStatus(status: number) {
  return Number.isInteger(status) && status >= 200 && status <= 599 ? status : 500;
}

function currentMonthKey(dateValue: string | null) {
  if (!dateValue) return "";
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return "";
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

function isCurrentMonth(dateValue: string | null, anchor = new Date()) {
  return currentMonthKey(dateValue) === `${anchor.getUTCFullYear()}-${String(anchor.getUTCMonth() + 1).padStart(2, "0")}`;
}

function daysSince(dateValue: string | null, anchor = new Date()) {
  if (!dateValue) return Number.POSITIVE_INFINITY;
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return Number.POSITIVE_INFINITY;
  return Math.floor((anchor.getTime() - date.getTime()) / 86400000);
}

function getDirectReports(users: PortalCompUser[], managerId: number) {
  return users.filter((user) => user.manager_user_id === managerId && user.active);
}

function collectDescendants(users: PortalCompUser[], rootId: number) {
  const descendants = new Set<number>();
  const queue = [rootId];
  while (queue.length) {
    const current = queue.shift()!;
    for (const user of users) {
      if (user.manager_user_id === current && !descendants.has(user.id)) {
        descendants.add(user.id);
        queue.push(user.id);
      }
    }
  }
  descendants.delete(rootId);
  return descendants;
}

function getSponsoredRecruits(users: PortalCompUser[], sponsorId: number) {
  return users.filter((user) => user.sponsor_user_id === sponsorId && user.active);
}

function collectSponsoredDescendants(users: PortalCompUser[], rootId: number) {
  const descendants = new Set<number>();
  const queue = [rootId];
  while (queue.length) {
    const current = queue.shift()!;
    for (const user of users) {
      if (user.sponsor_user_id === current && !descendants.has(user.id)) {
        descendants.add(user.id);
        queue.push(user.id);
      }
    }
  }
  descendants.delete(rootId);
  return descendants;
}

function buildRecruitTree(users: PortalCompUser[], rootId: number): Array<Record<string, unknown>> {
  const children = getSponsoredRecruits(users, rootId);
  return children.map((user) => ({
    id: user.id,
    nombre: user.nombre,
    compensation_role: user.compensation_role,
    manager_user_id: user.manager_user_id,
    sponsor_user_id: user.sponsor_user_id,
    recruits: buildRecruitTree(users, user.id),
  }));
}

function getActivityRule(config: CompensationConfig, role: string) {
  return config.activityRules.find((rule) => rule.rank_code === role);
}

function getRequirement(config: CompensationConfig, role: string) {
  return config.rankRequirements.find((rule) => rule.from_rank_code === role);
}

function orderIsInstalled(order: CompensationOrder) {
  return order.installation_status === "confirmed_satisfied" && order.satisfaction_status === "satisfied";
}

function buildUserActivity(
  user: PortalCompUser,
  users: PortalCompUser[],
  orders: CompensationOrder[],
  config: CompensationConfig,
) {
  const personalOrders = orders.filter((order) => order.portal_user_id === user.id && orderIsInstalled(order));
  const personalMonthOrders = personalOrders.filter((order) => isCurrentMonth(order.actual_install_date));
  const directReports = getDirectReports(users, user.id);
  const descendants = collectDescendants(users, user.id);
  const descendantOrdersMonth = orders.filter((order) =>
    order.portal_user_id &&
    descendants.has(order.portal_user_id) &&
    orderIsInstalled(order) &&
    isCurrentMonth(order.actual_install_date)
  );

  const activeAgents = directReports.filter((candidate) => {
    if (!["novato", "agente"].includes(candidate.compensation_role)) return false;
    const candidateOrdersMonth = orders.filter((order) => order.portal_user_id === candidate.id && orderIsInstalled(order) && isCurrentMonth(order.actual_install_date)).length;
    const rule = getActivityRule(config, candidate.compensation_role);
    return Boolean(rule && candidateOrdersMonth >= rule.min_personal_installs_month);
  });

  const activeSupervisors = directReports.filter((candidate) => {
    if (candidate.compensation_role !== "supervisor") return false;
    const candidateOrdersMonth = orders.filter((order) => order.portal_user_id === candidate.id && orderIsInstalled(order) && isCurrentMonth(order.actual_install_date)).length;
    const rule = getActivityRule(config, candidate.compensation_role);
    return Boolean(rule && candidateOrdersMonth >= rule.min_personal_installs_month);
  });

  const rule = getActivityRule(config, user.compensation_role);
  const isActive = rule
    ? personalMonthOrders.length >= rule.min_personal_installs_month &&
      activeAgents.length >= rule.min_active_agents &&
      activeSupervisors.length >= rule.min_active_supervisors &&
      descendantOrdersMonth.length >= rule.min_org_installs_month
    : false;

  return {
    personalOrders,
    personalMonthOrders,
    descendantOrdersMonth,
    directReports,
    activeAgents,
    inactiveAgents: directReports.filter((candidate) => ["novato", "agente"].includes(candidate.compensation_role) && !activeAgents.some((row) => row.id === candidate.id)),
    activeSupervisors,
    isActive,
  };
}

function sumOrderAmounts(orders: CompensationOrder[], statuses: string[]) {
  return orders
    .filter((order) => statuses.includes(order.compensation_status || "estimated"))
    .reduce((sum, order) => sum + Number(order.compensation_estimated_amount || 0), 0);
}

async function buildDashboard(user: PortalCompUser, supabase: ReturnType<typeof createAdminClient>) {
  await syncReserveStatuses(supabase);
  const config = await loadCompensationConfig(supabase);
  let users = await getAllCompUsers(supabase);
  let orders = await getCompOrders(supabase);
  await syncRankPromotions(supabase, config, users, orders);
  users = await getAllCompUsers(supabase);
  orders = await getCompOrders(supabase);

  const freshUser = users.find((row) => row.id === user.id) || user;
  const activity = buildUserActivity(freshUser, users, orders, config);
  const personalAllOrders = orders.filter((order) => order.portal_user_id === freshUser.id);
  const personalCommissionOrders = personalAllOrders.filter((order) => orderIsInstalled(order) || order.compensation_status === "estimated");
  const commissionTable = config.categories
    .filter((category) => category.active)
    .map((category) => ({
      category_code: category.code,
      category_name: category.name,
      examples: category.visible_examples,
      residential_amount: getRateAmount(config, freshUser.compensation_role, category.code, "residential"),
      commercial_amount: getRateAmount(config, freshUser.compensation_role, category.code, "commercial"),
    }));

  const eliteThreshold = Number((config.settings.producer_elite_threshold as { monthly_installs?: number } | undefined)?.monthly_installs || 10);
  const ambassadorSettings = config.settings.ambassador_program as {
    payout_per_install?: number;
    active_window_days?: number;
    minimum_installs_to_stay_active?: number;
  } | undefined;

  const progressRequirement = getRequirement(config, freshUser.compensation_role);
  const nextRank = progressRequirement?.to_rank_code || null;
  const lifetimeInstalled = personalAllOrders.filter(orderIsInstalled).length;
  const personalMonthInstalled = activity.personalMonthOrders.length;
  const descendants = collectDescendants(users, freshUser.id);
  const descendantOrdersInstalled = orders.filter((order) => order.portal_user_id && descendants.has(order.portal_user_id) && orderIsInstalled(order));
  const directorBonusAccumulated = freshUser.compensation_role === "director"
    ? descendantOrdersInstalled
        .filter((order) => isCurrentMonth(order.actual_install_date))
        .reduce((sum, order) => sum + getDirectorBonusAmount(config, order.service_category_code, normalizeSaleType(order.sale_type)), 0)
    : 0;

  return {
    generated_at: new Date().toISOString(),
    user: freshUser,
    current_level: config.ranks.find((rank) => rank.code === freshUser.compensation_role) || { code: freshUser.compensation_role, name: freshUser.compensation_role },
    installs_month: personalMonthInstalled,
    active_status: activity.isActive ? "active" : "inactive",
    producer_elite: {
      threshold: eliteThreshold,
      achieved: personalMonthInstalled >= eliteThreshold,
      installs_month: personalMonthInstalled,
    },
    commissions: {
      estimated: sumOrderAmounts(personalCommissionOrders, ["estimated", "reserve", "released"]),
      approved: sumOrderAmounts(personalCommissionOrders, ["approved"]),
      paid: sumOrderAmounts(personalCommissionOrders, ["paid"]),
      reserve: sumOrderAmounts(personalCommissionOrders, ["reserve"]),
      released: sumOrderAmounts(personalCommissionOrders, ["released"]),
      chargeback: sumOrderAmounts(personalCommissionOrders, ["chargeback"]),
    },
    commission_table: commissionTable,
    progress: {
      next_rank: nextRank,
      lifetime_personal_installs: lifetimeInstalled,
      active_agents: activity.activeAgents.length,
      active_supervisors: activity.activeSupervisors.length,
      org_installs_month: activity.descendantOrdersMonth.length,
      requirements: progressRequirement,
      initial_rank_assigned_by_admin: true,
    },
    recruit_tree: {
      direct_recruits: getSponsoredRecruits(users, freshUser.id).length,
      indirect_recruits: Math.max(0, collectSponsoredDescendants(users, freshUser.id).size - getSponsoredRecruits(users, freshUser.id).length),
      network_size: collectSponsoredDescendants(users, freshUser.id).size,
      recruits: buildRecruitTree(users, freshUser.id),
    },
    supervisor_view: ["supervisor", "director"].includes(freshUser.compensation_role)
      ? {
          personal_production: personalMonthInstalled,
          team_production: activity.descendantOrdersMonth.length,
          active_agents: activity.activeAgents.length,
          inactive_agents: activity.inactiveAgents.length,
          progress_to_director: freshUser.compensation_role === "supervisor" ? getRequirement(config, "supervisor") : null,
        }
      : null,
    director_view: freshUser.compensation_role === "director"
      ? {
          organizational_production: activity.descendantOrdersMonth.length,
          active_supervisors: activity.activeSupervisors.length,
          director_bonus_accumulated: directorBonusAccumulated,
          residential_production: activity.descendantOrdersMonth.filter((order) => normalizeSaleType(order.sale_type) === "residential").length,
          commercial_production: activity.descendantOrdersMonth.filter((order) => normalizeSaleType(order.sale_type) === "commercial").length,
        }
      : null,
    ambassador_program: {
      payout_per_install: Number(ambassadorSettings?.payout_per_install || 15),
      active_window_days: Number(ambassadorSettings?.active_window_days || 90),
      minimum_installs_to_stay_active: Number(ambassadorSettings?.minimum_installs_to_stay_active || 1),
      installs_last_window: orders.filter((order) => order.ambassador_id && orderIsInstalled(order) && daysSince(order.actual_install_date) <= Number(ambassadorSettings?.active_window_days || 90)).length,
      active_ambassadors: config.ambassadors.filter((ambassador) => ambassador.active).length,
    },
    visible_categories: config.categories.filter((category) => category.active),
    recent_orders: personalAllOrders.slice(0, 12),
  };
}

async function logAudit(
  supabase: ReturnType<typeof createAdminClient>,
  actor: { nombre: string; rol: Role },
  entityType: string,
  entityKey: string,
  action: string,
  beforeValue: unknown,
  afterValue: unknown,
  reason: string | null,
) {
  await supabase.from("izzy_compensation_audit_log").insert({
    actor_name: actor.nombre,
    actor_role: actor.rol,
    entity_type: entityType,
    entity_key: entityKey,
    action,
    before_value: beforeValue,
    after_value: afterValue,
    reason,
  });
}

async function handleGet(req: Request) {
  const user = await requireSession(req);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "dashboard";
  const supabase = createAdminClient();

  if (resource === "config") {
    const config = await loadCompensationConfig(supabase);
    return jsonResponse({
      ranks: config.ranks,
      categories: config.categories.filter((category) => category.active),
      ambassadors: config.ambassadors.filter((ambassador) => ambassador.active),
    });
  }

  if (resource === "admin") {
    ensureAdmin(user.rol);
    const [config, usersRes, auditRes] = await Promise.all([
      loadCompensationConfig(supabase),
      getAllCompUsers(supabase),
      supabase.from("izzy_compensation_audit_log").select("*").order("created_at", { ascending: false }).limit(50),
    ]);
    return jsonResponse({
      config,
      users: usersRes,
      audit_log: auditRes.data || [],
    });
  }

  const portalUser = await getPortalUserBySession(supabase, user);
  if (!portalUser) {
    return jsonResponse({ error: "Portal user not found" }, { status: 404 });
  }

  const dashboard = await buildDashboard(portalUser, supabase);
  return jsonResponse(dashboard);
}

async function handlePost(req: Request) {
  const user = await requireSession(req);
  ensureAdmin(user.rol);
  const supabase = createAdminClient();
  const body = await req.json();
  const section = String(body?.section || "");
  const rows = Array.isArray(body?.rows) ? body.rows : [];
  const reason = String(body?.reason || "").trim() || null;

  if (!section || !rows.length) {
    return jsonResponse({ error: "section and rows are required" }, { status: 400 });
  }

  if (section === "settings") {
    for (const row of rows) {
      const key = String(row.key || "");
      if (!key) continue;
      const { data: existing } = await supabase.from("izzy_compensation_settings").select("key, value").eq("key", key).maybeSingle();
      await supabase.from("izzy_compensation_settings").upsert({
        key,
        value: row.value || {},
        description: row.description || null,
      });
      await logAudit(supabase, user, "setting", key, "upsert", existing?.value || null, row.value || {}, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "categories") {
    for (const row of rows) {
      const { data: existing } = await supabase.from("izzy_service_categories").select("*").eq("code", row.code).maybeSingle();
      await supabase.from("izzy_service_categories").upsert({
        code: row.code,
        name: row.name,
        sort_order: Number(row.sort_order || 0),
        active: row.active !== false,
        visible_examples: Array.isArray(row.visible_examples) ? row.visible_examples : [],
      });
      await logAudit(supabase, user, "category", String(row.code || ""), "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "carriers") {
    for (const row of rows) {
      const key = row.id ? String(row.id) : String(row.name || "");
      const { data: existing } = row.id
        ? await supabase.from("izzy_carriers").select("*").eq("id", row.id).maybeSingle()
        : { data: null };
      await supabase.from("izzy_carriers").upsert({
        id: row.id || undefined,
        name: row.name,
        service_type: row.service_type || "other",
        active: row.active !== false,
        internal_notes: row.internal_notes || null,
      });
      await logAudit(supabase, user, "carrier", key, "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "plans") {
    for (const row of rows) {
      const key = row.id ? String(row.id) : `${row.carrier_id}:${row.plan_name}:${row.sale_type}`;
      const { data: existing } = row.id
        ? await supabase.from("izzy_compensation_plans").select("*").eq("id", row.id).maybeSingle()
        : { data: null };
      await supabase.from("izzy_compensation_plans").upsert({
        id: row.id || undefined,
        carrier_id: Number(row.carrier_id),
        plan_name: row.plan_name,
        service_category_code: row.service_category_code,
        sale_type: normalizeSaleType(row.sale_type),
        novice_commission: Number(row.novice_commission || 0),
        agent_commission: Number(row.agent_commission || 0),
        supervisor_commission: Number(row.supervisor_commission || 0),
        director_commission: Number(row.director_commission || 0),
        director_bonus: Number(row.director_bonus || 0),
        commercial_multiplier: Number(row.commercial_multiplier || 1),
        chargeback_days: Number(row.chargeback_days || 120),
        special_bonuses: Array.isArray(row.special_bonuses) ? row.special_bonuses : [],
        temporary_promo_notes: row.temporary_promo_notes || null,
        active: row.active !== false,
      });
      await logAudit(supabase, user, "plan", key, "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "rates") {
    for (const row of rows) {
      const key = `${row.rank_code}:${row.service_category_code}:${row.sale_type}`;
      const { data: existing } = await supabase
        .from("izzy_commission_rates")
        .select("*")
        .eq("rank_code", row.rank_code)
        .eq("service_category_code", row.service_category_code)
        .eq("sale_type", normalizeSaleType(row.sale_type))
        .maybeSingle();
      await supabase.from("izzy_commission_rates").upsert({
        id: row.id || undefined,
        rank_code: row.rank_code,
        service_category_code: row.service_category_code,
        sale_type: normalizeSaleType(row.sale_type),
        amount: Number(row.amount || 0),
        active: row.active !== false,
      }, { onConflict: "rank_code,service_category_code,sale_type" });
      await logAudit(supabase, user, "rate", key, "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "director_bonuses") {
    for (const row of rows) {
      const key = `${row.service_category_code}:${row.sale_type}`;
      const { data: existing } = await supabase
        .from("izzy_director_bonus_rates")
        .select("*")
        .eq("service_category_code", row.service_category_code)
        .eq("sale_type", normalizeSaleType(row.sale_type))
        .maybeSingle();
      await supabase.from("izzy_director_bonus_rates").upsert({
        id: row.id || undefined,
        service_category_code: row.service_category_code,
        sale_type: normalizeSaleType(row.sale_type),
        amount: Number(row.amount || 0),
        active: row.active !== false,
      }, { onConflict: "service_category_code,sale_type" });
      await logAudit(supabase, user, "director_bonus", key, "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "activity_rules") {
    for (const row of rows) {
      const { data: existing } = await supabase.from("izzy_activity_rules").select("*").eq("rank_code", row.rank_code).maybeSingle();
      await supabase.from("izzy_activity_rules").upsert({
        rank_code: row.rank_code,
        min_personal_installs_month: Number(row.min_personal_installs_month || 0),
        min_active_agents: Number(row.min_active_agents || 0),
        min_active_supervisors: Number(row.min_active_supervisors || 0),
        min_org_installs_month: Number(row.min_org_installs_month || 0),
        active: row.active !== false,
      });
      await logAudit(supabase, user, "activity_rule", String(row.rank_code || ""), "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "rank_requirements") {
    for (const row of rows) {
      const { data: existing } = await supabase.from("izzy_rank_requirements").select("*").eq("from_rank_code", row.from_rank_code).maybeSingle();
      await supabase.from("izzy_rank_requirements").upsert({
        from_rank_code: row.from_rank_code,
        to_rank_code: row.to_rank_code,
        min_lifetime_personal_installs: Number(row.min_lifetime_personal_installs || 0),
        min_active_agents: Number(row.min_active_agents || 0),
        min_active_supervisors: Number(row.min_active_supervisors || 0),
        min_org_installs_month: Number(row.min_org_installs_month || 0),
        active: row.active !== false,
      });
      await logAudit(supabase, user, "rank_requirement", String(row.from_rank_code || ""), "upsert", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "users") {
    for (const row of rows) {
      const { data: existing } = await supabase.from("izzy_portal_users").select("id, compensation_role, sponsor_user_id, manager_user_id").eq("id", row.id).maybeSingle();
      await supabase.from("izzy_portal_users").update({
        compensation_role: normalizeCompensationRole(row.compensation_role),
        sponsor_user_id: row.sponsor_user_id || null,
        manager_user_id: row.manager_user_id || null,
      }).eq("id", row.id);
      await logAudit(supabase, user, "user_comp", String(row.id || ""), "update", existing || null, row, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "ambassadors") {
    for (const row of rows) {
      const { data: existing } = row.id
        ? await supabase.from("izzy_ambassadors").select("*").eq("id", row.id).maybeSingle()
        : { data: null };
      const payload = {
        id: row.id || undefined,
        code: row.code,
        nombre: row.nombre,
        telefono: row.telefono || null,
        email: row.email || null,
        active: row.active !== false,
        notes: row.notes || null,
      };
      if (payload.id) {
        await supabase.from("izzy_ambassadors").upsert(payload);
      } else {
        await supabase.from("izzy_ambassadors").insert(payload);
      }
      await logAudit(supabase, user, "ambassador", String(row.id || row.code || ""), "upsert", existing || null, payload, reason);
    }
    return jsonResponse({ ok: true });
  }

  if (section === "promotions") {
    for (const row of rows) {
      const { data: existing } = row.id
        ? await supabase.from("izzy_compensation_promotions").select("*").eq("id", row.id).maybeSingle()
        : { data: null };
      const payload = {
        id: row.id || undefined,
        name: row.name,
        start_date: row.start_date,
        end_date: row.end_date || null,
        rules: row.rules && typeof row.rules === "object" ? row.rules : {},
        amount: Number(row.amount || 0),
        active: row.active !== false,
        promotion_type: row.promotion_type || "special_bonus",
        carrier_id: row.carrier_id || null,
        notes: row.notes || null,
      };
      await supabase.from("izzy_compensation_promotions").upsert(payload);
      await logAudit(supabase, user, "promotion", String(row.id || row.name || ""), "upsert", existing || null, payload, reason);
    }
    return jsonResponse({ ok: true });
  }

  return jsonResponse({ error: "Unknown section" }, { status: 400 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "GET") return await handleGet(req);
    if (req.method === "POST") return await handlePost(req);
    return jsonResponse({ error: "Method not allowed" }, { status: 405 });
  } catch (error) {
    if (error instanceof Response) {
      const body = await error.text();
      return new Response(body, {
        status: safeResponseStatus(error.status),
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.error("[izzy-compensation] unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, { status: 500 });
  }
});
