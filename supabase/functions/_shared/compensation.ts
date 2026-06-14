import type { SessionUser } from "./auth.ts";
import type { createAdminClient } from "./supabase.ts";

export type CompensationRole = "novato" | "agente" | "supervisor" | "director" | "embajador";
export type SaleType = "residential" | "commercial";
export type CompensationStatus = "estimated" | "approved" | "reserve" | "released" | "paid" | "chargeback";

export type PortalCompUser = {
  id: number;
  nombre: string;
  rol: "admin" | "agente";
  compensation_role: CompensationRole;
  sponsor_user_id: number | null;
  manager_user_id: number | null;
  active: boolean;
};

export type CompensationConfig = {
  ranks: Array<{ code: string; name: string; sort_order: number; is_career: boolean; active: boolean }>;
  categories: Array<{ code: string; name: string; sort_order: number; active: boolean; visible_examples: string[] }>;
  carriers: Array<{ id: number; name: string; service_type: string; active: boolean; internal_notes: string | null }>;
  plans: Array<{
    id: number;
    carrier_id: number;
    plan_name: string;
    service_category_code: string;
    sale_type: SaleType;
    novice_commission: number;
    agent_commission: number;
    supervisor_commission: number;
    director_commission: number;
    director_bonus: number;
    commercial_multiplier: number;
    chargeback_days: number;
    special_bonuses: unknown[];
    temporary_promo_notes: string | null;
    active: boolean;
  }>;
  promotions: Array<{
    id: number;
    name: string;
    start_date: string;
    end_date: string | null;
    rules: Record<string, unknown>;
    amount: number;
    active: boolean;
    promotion_type: string;
    carrier_id: number | null;
    notes: string | null;
  }>;
  rates: Array<{ id: number; rank_code: string; service_category_code: string; sale_type: SaleType; amount: number; active: boolean }>;
  directorBonuses: Array<{ id: number; service_category_code: string; sale_type: SaleType; amount: number; active: boolean }>;
  activityRules: Array<{ rank_code: string; min_personal_installs_month: number; min_active_agents: number; min_active_supervisors: number; min_org_installs_month: number; active: boolean }>;
  rankRequirements: Array<{ from_rank_code: string; to_rank_code: string; min_lifetime_personal_installs: number; min_active_agents: number; min_active_supervisors: number; min_org_installs_month: number; active: boolean }>;
  settings: Record<string, unknown>;
  ambassadors: Array<{ id: number; code: string; nombre: string; telefono: string | null; email: string | null; active: boolean; notes: string | null }>;
};

export type CompensationOrder = {
  id: number;
  agente: string;
  portal_user_id: number | null;
  service_category_code: string | null;
  sale_type: SaleType | null;
  carrier_name: string | null;
  compensation_status: CompensationStatus | null;
  compensation_rank_code: string | null;
  compensation_estimated_amount: number | null;
  actual_install_date: string | null;
  installation_status: string | null;
  satisfaction_status: string | null;
  reserve_release_at: string | null;
  ambassador_id: number | null;
  created_at: string;
};

function asNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function asString(value: unknown) {
  return String(value || "").trim();
}

function monthKey(date: Date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

function sameMonth(dateValue: string | null, compareTo = new Date()) {
  if (!dateValue) return false;
  const parsed = new Date(dateValue);
  if (Number.isNaN(parsed.getTime())) return false;
  return monthKey(parsed) === monthKey(compareTo);
}

function inferCategoryByText(input: string) {
  const text = input.toLowerCase();
  if (!text) return "standard";
  if (text.includes("2 gig") || text.includes("1 gig") || text.includes("fiber")) return "premium";
  if (text.includes("500") || text.includes("300") || text.includes("home internet")) return "standard";
  if (text.includes("promo") || text.includes("special")) return "basic";
  return "standard";
}

export function normalizeCompensationRole(value: unknown): CompensationRole {
  const raw = asString(value).toLowerCase();
  if (raw === "agente" || raw === "supervisor" || raw === "director" || raw === "embajador") return raw;
  return "novato";
}

export function normalizeSaleType(value: unknown): SaleType {
  return asString(value).toLowerCase() === "commercial" ? "commercial" : "residential";
}

export function normalizeCompensationStatus(value: unknown): CompensationStatus {
  const raw = asString(value).toLowerCase();
  if (raw === "approved" || raw === "reserve" || raw === "released" || raw === "paid" || raw === "chargeback") return raw;
  return "estimated";
}

export function getCarrierReserveDays(settings: Record<string, unknown>, carrierName: string | null | undefined) {
  const carrierPolicies = settings.carrier_policies as Record<string, { chargeback_days?: number }> | undefined;
  const defaultDays = asNumber((settings.default_chargeback_days as { days?: number } | undefined)?.days, 120);
  const cleanCarrier = asString(carrierName);
  if (!carrierPolicies) return defaultDays;
  if (cleanCarrier && carrierPolicies[cleanCarrier]?.chargeback_days) {
    return asNumber(carrierPolicies[cleanCarrier].chargeback_days, defaultDays);
  }
  return asNumber(carrierPolicies.default?.chargeback_days, defaultDays);
}

export function getRateAmount(
  config: CompensationConfig,
  rankCode: string | null | undefined,
  categoryCode: string | null | undefined,
  saleType: SaleType,
) {
  const match = config.rates.find((rate) =>
    rate.active &&
    rate.rank_code === (rankCode || "novato") &&
    rate.service_category_code === (categoryCode || "standard") &&
    rate.sale_type === saleType
  );
  return match ? asNumber(match.amount, 0) : 0;
}

export function getDirectorBonusAmount(
  config: CompensationConfig,
  categoryCode: string | null | undefined,
  saleType: SaleType,
) {
  const match = config.directorBonuses.find((rate) =>
    rate.active &&
    rate.service_category_code === (categoryCode || "standard") &&
    rate.sale_type === saleType
  );
  return match ? asNumber(match.amount, 0) : 0;
}

export async function loadCompensationConfig(supabase: ReturnType<typeof createAdminClient>): Promise<CompensationConfig> {
  const [
    rankLevelsRes,
    categoriesRes,
    carriersRes,
    plansRes,
    promotionsRes,
    ratesRes,
    bonusRes,
    activityRes,
    requirementsRes,
    settingsRes,
    ambassadorsRes,
  ] = await Promise.all([
    supabase.from("izzy_rank_levels").select("code, name, sort_order, is_career, active").order("sort_order", { ascending: true }),
    supabase.from("izzy_service_categories").select("code, name, sort_order, active, visible_examples").order("sort_order", { ascending: true }),
    supabase.from("izzy_carriers").select("id, name, service_type, active, internal_notes").order("name", { ascending: true }),
    supabase.from("izzy_compensation_plans").select("id, carrier_id, plan_name, service_category_code, sale_type, novice_commission, agent_commission, supervisor_commission, director_commission, director_bonus, commercial_multiplier, chargeback_days, special_bonuses, temporary_promo_notes, active").order("plan_name", { ascending: true }),
    supabase.from("izzy_compensation_promotions").select("id, name, start_date, end_date, rules, amount, active, promotion_type, carrier_id, notes").order("start_date", { ascending: false }),
    supabase.from("izzy_commission_rates").select("id, rank_code, service_category_code, sale_type, amount, active").order("id", { ascending: true }),
    supabase.from("izzy_director_bonus_rates").select("id, service_category_code, sale_type, amount, active").order("id", { ascending: true }),
    supabase.from("izzy_activity_rules").select("rank_code, min_personal_installs_month, min_active_agents, min_active_supervisors, min_org_installs_month, active"),
    supabase.from("izzy_rank_requirements").select("from_rank_code, to_rank_code, min_lifetime_personal_installs, min_active_agents, min_active_supervisors, min_org_installs_month, active"),
    supabase.from("izzy_compensation_settings").select("key, value"),
    supabase.from("izzy_ambassadors").select("id, code, nombre, telefono, email, active, notes").order("nombre", { ascending: true }),
  ]);

  const settings: Record<string, unknown> = {};
  for (const row of settingsRes.data || []) {
    settings[row.key] = row.value;
  }

  return {
    ranks: (rankLevelsRes.data || []) as CompensationConfig["ranks"],
    categories: (categoriesRes.data || []).map((row) => ({
      ...row,
      visible_examples: Array.isArray(row.visible_examples) ? row.visible_examples.map((item) => String(item)) : [],
    })),
    carriers: (carriersRes.data || []) as CompensationConfig["carriers"],
    plans: (plansRes.data || []).map((row) => ({
      ...row,
      novice_commission: asNumber(row.novice_commission, 0),
      agent_commission: asNumber(row.agent_commission, 0),
      supervisor_commission: asNumber(row.supervisor_commission, 0),
      director_commission: asNumber(row.director_commission, 0),
      director_bonus: asNumber(row.director_bonus, 0),
      commercial_multiplier: asNumber(row.commercial_multiplier, 1),
      chargeback_days: asNumber(row.chargeback_days, 120),
      special_bonuses: Array.isArray(row.special_bonuses) ? row.special_bonuses : [],
    })),
    promotions: (promotionsRes.data || []).map((row) => ({
      ...row,
      amount: asNumber(row.amount, 0),
      rules: typeof row.rules === "object" && row.rules ? row.rules as Record<string, unknown> : {},
    })),
    rates: (ratesRes.data || []).map((row) => ({ ...row, amount: asNumber(row.amount, 0) })),
    directorBonuses: (bonusRes.data || []).map((row) => ({ ...row, amount: asNumber(row.amount, 0) })),
    activityRules: (activityRes.data || []).map((row) => ({
      ...row,
      min_personal_installs_month: asNumber(row.min_personal_installs_month, 0),
      min_active_agents: asNumber(row.min_active_agents, 0),
      min_active_supervisors: asNumber(row.min_active_supervisors, 0),
      min_org_installs_month: asNumber(row.min_org_installs_month, 0),
    })),
    rankRequirements: (requirementsRes.data || []).map((row) => ({
      ...row,
      min_lifetime_personal_installs: asNumber(row.min_lifetime_personal_installs, 0),
      min_active_agents: asNumber(row.min_active_agents, 0),
      min_active_supervisors: asNumber(row.min_active_supervisors, 0),
      min_org_installs_month: asNumber(row.min_org_installs_month, 0),
    })),
    settings,
    ambassadors: (ambassadorsRes.data || []) as CompensationConfig["ambassadors"],
  };
}

export async function syncReserveStatuses(supabase: ReturnType<typeof createAdminClient>) {
  const now = new Date().toISOString();
  const { data } = await supabase
    .from("izzy_orders")
    .select("id, compensation_status")
    .eq("compensation_status", "reserve")
    .lte("reserve_release_at", now);

  if (!data?.length) return;

  const ids = data.map((row) => row.id);
  await supabase
    .from("izzy_orders")
    .update({ compensation_status: "released" })
    .in("id", ids);

  await supabase
    .from("izzy_commission_reserves")
    .update({ status: "released", released_at: now })
    .in("order_id", ids);
}

export async function getPortalUserBySession(
  supabase: ReturnType<typeof createAdminClient>,
  sessionUser: SessionUser,
) {
  if (sessionUser.pin_code) {
    const { data } = await supabase
      .from("izzy_portal_users")
      .select("id, nombre, rol, compensation_role, sponsor_user_id, manager_user_id, active")
      .eq("pin_code", sessionUser.pin_code)
      .maybeSingle();
    if (data) return data as PortalCompUser;
  }

  const { data } = await supabase
    .from("izzy_portal_users")
    .select("id, nombre, rol, compensation_role, sponsor_user_id, manager_user_id, active")
    .eq("nombre", sessionUser.nombre)
    .maybeSingle();
  return (data || null) as PortalCompUser | null;
}

export async function getAllCompUsers(supabase: ReturnType<typeof createAdminClient>) {
  const { data } = await supabase
    .from("izzy_portal_users")
    .select("id, nombre, rol, compensation_role, sponsor_user_id, manager_user_id, active")
    .order("nombre", { ascending: true });
  return (data || []) as PortalCompUser[];
}

export async function getCompOrders(supabase: ReturnType<typeof createAdminClient>) {
  const { data } = await supabase
    .from("izzy_orders")
    .select("id, agente, portal_user_id, service_category_code, sale_type, carrier_name, compensation_status, compensation_rank_code, compensation_estimated_amount, actual_install_date, installation_status, satisfaction_status, reserve_release_at, ambassador_id, created_at")
    .order("created_at", { ascending: false });
  return (data || []) as CompensationOrder[];
}

function collectDescendants(rootUserId: number, users: PortalCompUser[]) {
  const descendants = new Set<number>();
  const queue = [rootUserId];

  while (queue.length) {
    const current = queue.shift()!;
    for (const user of users) {
      if (user.manager_user_id === current && !descendants.has(user.id)) {
        descendants.add(user.id);
        queue.push(user.id);
      }
    }
  }

  descendants.delete(rootUserId);
  return descendants;
}

export async function syncRankPromotions(
  supabase: ReturnType<typeof createAdminClient>,
  config: CompensationConfig,
  users: PortalCompUser[],
  orders: CompensationOrder[],
) {
  const month = new Date();
  const activityByUser = new Map<number, { personalMonth: number; personalLifetime: number; activeAgents: number; activeSupervisors: number; orgMonth: number; isActive: boolean }>();
  const usersById = new Map(users.map((user) => [user.id, user]));

  const personalInstalledOrders = orders.filter((order) =>
    order.portal_user_id &&
    order.installation_status === "confirmed_satisfied" &&
    order.satisfaction_status === "satisfied"
  );

  for (const user of users) {
    const personalOrders = personalInstalledOrders.filter((order) => order.portal_user_id === user.id);
    const personalMonth = personalOrders.filter((order) => sameMonth(order.actual_install_date, month)).length;
    const personalLifetime = personalOrders.length;
    activityByUser.set(user.id, {
      personalMonth,
      personalLifetime,
      activeAgents: 0,
      activeSupervisors: 0,
      orgMonth: 0,
      isActive: false,
    });
  }

  for (const user of users) {
    const descendants = collectDescendants(user.id, users);
    const directReports = users.filter((candidate) => candidate.manager_user_id === user.id && candidate.active);
    const activeAgents = directReports.filter((candidate) => {
      const candidateActivity = activityByUser.get(candidate.id);
      const rule = config.activityRules.find((row) => row.rank_code === candidate.compensation_role);
      if (!candidateActivity || !rule) return false;
      if (candidate.compensation_role === "supervisor" || candidate.compensation_role === "director" || candidate.compensation_role === "embajador") return false;
      return candidateActivity.personalMonth >= rule.min_personal_installs_month;
    }).length;
    const activeSupervisors = directReports.filter((candidate) => {
      const candidateActivity = activityByUser.get(candidate.id);
      const rule = config.activityRules.find((row) => row.rank_code === candidate.compensation_role);
      if (!candidateActivity || !rule) return false;
      if (candidate.compensation_role !== "supervisor") return false;
      return candidateActivity.personalMonth >= rule.min_personal_installs_month;
    }).length;
    const orgMonth = personalInstalledOrders.filter((order) =>
      order.portal_user_id &&
      descendants.has(order.portal_user_id) &&
      sameMonth(order.actual_install_date, month)
    ).length;

    const currentActivity = activityByUser.get(user.id);
    if (currentActivity) {
      currentActivity.activeAgents = activeAgents;
      currentActivity.activeSupervisors = activeSupervisors;
      currentActivity.orgMonth = orgMonth;
      const rule = config.activityRules.find((row) => row.rank_code === user.compensation_role);
      currentActivity.isActive = rule
        ? currentActivity.personalMonth >= rule.min_personal_installs_month &&
          currentActivity.activeAgents >= rule.min_active_agents &&
          currentActivity.activeSupervisors >= rule.min_active_supervisors &&
          currentActivity.orgMonth >= rule.min_org_installs_month
        : false;
    }
  }

  for (const user of users) {
    const current = activityByUser.get(user.id);
    const requirement = config.rankRequirements.find((row) => row.from_rank_code === user.compensation_role && row.active);
    if (!current || !requirement) continue;
    const canPromote =
      current.personalLifetime >= requirement.min_lifetime_personal_installs &&
      current.activeAgents >= requirement.min_active_agents &&
      current.activeSupervisors >= requirement.min_active_supervisors &&
      current.orgMonth >= requirement.min_org_installs_month;

    if (!canPromote || requirement.to_rank_code === user.compensation_role) continue;

    await supabase
      .from("izzy_portal_users")
      .update({ compensation_role: requirement.to_rank_code })
      .eq("id", user.id);

    await supabase
      .from("izzy_agent_rank_history")
      .insert({
        user_id: user.id,
        previous_rank_code: user.compensation_role,
        new_rank_code: requirement.to_rank_code,
        reason: "Auto promotion by compensation rules",
        metadata: {
          personal_lifetime_installs: current.personalLifetime,
          active_agents: current.activeAgents,
          active_supervisors: current.activeSupervisors,
          org_installs_month: current.orgMonth,
        },
      });

    const mutable = usersById.get(user.id);
    if (mutable) mutable.compensation_role = requirement.to_rank_code as CompensationRole;
  }
}

export function buildOrderCompensationSnapshot(
  config: CompensationConfig,
  user: PortalCompUser | null,
  raw: {
    service_provider?: string;
    service_provider_other?: string;
    desired_speed?: string;
    sale_type?: string;
    service_category_code?: string;
  },
) {
  const saleType = normalizeSaleType(raw.sale_type);
  const carrierName = asString(raw.service_provider_other) || asString(raw.service_provider);
  const serviceCategoryCode = asString(raw.service_category_code) || inferCategoryByText(`${raw.service_provider || ""} ${raw.desired_speed || ""}`);
  const rankCode = user?.compensation_role || "novato";
  const estimatedAmount = getRateAmount(config, rankCode, serviceCategoryCode, saleType);

  return {
    portal_user_id: user?.id || null,
    sale_type: saleType,
    carrier_name: carrierName,
    service_category_code: serviceCategoryCode,
    compensation_rank_code: rankCode,
    compensation_estimated_amount: estimatedAmount,
    compensation_status: "estimated" as CompensationStatus,
  };
}
