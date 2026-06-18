import "@supabase/functions-js/edge-runtime.d.ts";

import { requireSession, type Role } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type PortalUser = {
  id: number;
  nombre: string;
  rol: Role;
  active: boolean;
};

type LeadRow = {
  id: number;
  created_at: string;
  agente: string | null;
  cliente: string | null;
  telefono: string | null;
  direccion: string | null;
  estado: string | null;
  cotizacion_enviada: string | null;
  cotizacion_at: string | null;
  assigned_user_id: number | null;
  lead_status_code: string | null;
  priority: string | null;
  last_contact_at: string | null;
  last_contact_result: string | null;
  next_action: string | null;
  next_followup_at: string | null;
  next_followup_status: string | null;
  do_not_call: boolean | null;
};

type LeadCallRow = {
  id: number;
  lead_id: number;
  agent_user_id: number;
  direction: string;
  call_status: string;
  disposition: string;
  notes: string | null;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  next_action: string | null;
  next_followup_at: string | null;
  created_at: string;
};

type FollowupRow = {
  id: number;
  lead_id: number;
  agent_user_id: number;
  source_call_id: number | null;
  status: string;
  scheduled_for: string;
  completed_at: string | null;
  subject: string | null;
  notes: string | null;
  outcome: string | null;
  created_at: string;
  updated_at: string;
};

type ActivityRow = {
  id: number;
  lead_id: number;
  agent_user_id: number | null;
  activity_type: string;
  activity_source: string;
  title: string | null;
  body: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
};

type SessionUser = {
  nombre: string;
  rol: Role;
  pin_code?: string;
};

const CALL_RESULTS = new Set([
  "answered",
  "no_answer",
  "voicemail",
  "wrong_number",
  "call_back",
  "interested",
  "not_interested",
  "quote_requested",
]);

const LEAD_STATUS_CODES = new Set([
  "new",
  "not_contacted",
  "contacted",
  "follow_up",
  "qualified",
  "quote_requested",
  "quote_pending",
  "quoted_ready",
  "not_interested",
  "wrong_number",
  "sold",
]);

const PRIORITIES = new Set(["low", "normal", "high", "urgent"]);
const FOLLOWUP_STATUSES = new Set(["scheduled", "completed", "missed", "cancelled"]);
const PENDING_FOLLOWUP_STATUS = "scheduled";

function cleanString(value: unknown): string {
  return String(value || "").trim();
}

function cleanNullableString(value: unknown): string | null {
  const cleaned = cleanString(value);
  return cleaned || null;
}

function cleanInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

function cleanBoolean(value: unknown): boolean {
  return value === true || value === "true" || value === 1 || value === "1";
}

function cleanIsoDateTime(value: unknown): string | null {
  const raw = cleanString(value);
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function nowIso() {
  return new Date().toISOString();
}

function losAngelesDateKey(value: string | Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(typeof value === "string" ? new Date(value) : value);
}

function deriveFollowupStatus(nextFollowupAt: string | null) {
  if (!nextFollowupAt) return "none";
  const targetKey = losAngelesDateKey(nextFollowupAt);
  const todayKey = losAngelesDateKey(new Date());
  if (targetKey < todayKey) return "overdue";
  if (targetKey === todayKey) return "due_today";
  return "scheduled";
}

function deriveLeadStatusFromCall(callStatus: string, currentStatus: string | null) {
  if (callStatus === "wrong_number") return "wrong_number";
  if (callStatus === "not_interested") return "not_interested";
  if (callStatus === "quote_requested") return "quote_requested";
  if (callStatus === "interested") return "qualified";
  if (callStatus === "call_back") return "follow_up";
  if (callStatus === "answered" || callStatus === "voicemail") return "contacted";
  if (callStatus === "no_answer") return currentStatus === "new" ? "not_contacted" : currentStatus || "not_contacted";
  return currentStatus || "new";
}

async function getPortalUser(supabase: ReturnType<typeof createAdminClient>, sessionUser: SessionUser) {
  let query = supabase
    .from("izzy_portal_users")
    .select("id, nombre, rol, active")
    .limit(1);

  if (sessionUser.pin_code) {
    query = query.eq("pin_code", sessionUser.pin_code);
  } else {
    query = query.eq("nombre", sessionUser.nombre);
  }

  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  if (!data) {
    throw new Response(JSON.stringify({ error: "Portal user not found" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }
  return data as PortalUser;
}

function leadIsVisibleToUser(lead: LeadRow, sessionUser: SessionUser, portalUser: PortalUser) {
  if (sessionUser.rol === "admin") return true;
  return lead.assigned_user_id === portalUser.id || cleanString(lead.agente) === cleanString(sessionUser.nombre);
}

async function requireVisibleLead(
  supabase: ReturnType<typeof createAdminClient>,
  leadId: number,
  sessionUser: SessionUser,
  portalUser: PortalUser,
) {
  const { data, error } = await supabase
    .from("izzy_leads")
    .select("*")
    .eq("id", leadId)
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw new Response(JSON.stringify({ error: "Lead not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const lead = data as LeadRow;
  if (!leadIsVisibleToUser(lead, sessionUser, portalUser)) {
    throw new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  return lead;
}

async function insertActivity(
  supabase: ReturnType<typeof createAdminClient>,
  payload: {
    lead_id: number;
    agent_user_id?: number | null;
    activity_type: string;
    title?: string | null;
    body?: string | null;
    metadata?: Record<string, unknown>;
  },
) {
  const { error } = await supabase
    .from("izzy_lead_activities")
    .insert({
      lead_id: payload.lead_id,
      agent_user_id: payload.agent_user_id ?? null,
      activity_type: payload.activity_type,
      title: payload.title ?? null,
      body: payload.body ?? null,
      metadata: payload.metadata ?? {},
    });

  if (error) throw error;
}

async function syncLeadNextFollowup(
  supabase: ReturnType<typeof createAdminClient>,
  leadId: number,
) {
  const { data: nextFollowupData, error: nextFollowupError } = await supabase
    .from("izzy_followups")
    .select("id, scheduled_for, subject")
    .eq("lead_id", leadId)
    .eq("status", PENDING_FOLLOWUP_STATUS)
    .order("scheduled_for", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (nextFollowupError) throw nextFollowupError;

  const nextFollowup = nextFollowupData as Pick<FollowupRow, "id" | "scheduled_for" | "subject"> | null;
  const nextFollowupAt = nextFollowup?.scheduled_for || null;
  const nextAction = cleanNullableString(nextFollowup?.subject);

  const { data: updatedLeadData, error: updateLeadError } = await supabase
    .from("izzy_leads")
    .update({
      next_followup_at: nextFollowupAt,
      next_followup_status: deriveFollowupStatus(nextFollowupAt),
      next_action: nextAction,
    })
    .eq("id", leadId)
    .select("*")
    .single();

  if (updateLeadError) throw updateLeadError;

  return {
    lead: updatedLeadData as LeadRow,
    next_followup: nextFollowup,
  };
}

async function upsertPendingFollowup(
  supabase: ReturnType<typeof createAdminClient>,
  payload: {
    lead_id: number;
    agent_user_id: number;
    scheduled_for: string;
    subject?: string | null;
    notes?: string | null;
    source_call_id?: number | null;
  },
) {
  const subject = cleanNullableString(payload.subject);
  const notes = cleanNullableString(payload.notes);
  const sourceCallId = payload.source_call_id ?? null;

  const { data: existingData, error: existingError } = await supabase
    .from("izzy_followups")
    .select("*")
    .eq("lead_id", payload.lead_id)
    .eq("status", PENDING_FOLLOWUP_STATUS)
    .eq("scheduled_for", payload.scheduled_for)
    .limit(1);

  if (existingError) throw existingError;

  const existingFollowups = (existingData || []) as FollowupRow[];
  const existing = existingFollowups.find((followup) =>
    cleanNullableString(followup.subject) === subject
  ) || existingFollowups[0] || null;

  if (existing) {
    const updates: Record<string, unknown> = {
      agent_user_id: payload.agent_user_id,
      subject,
      notes,
      source_call_id: sourceCallId,
      status: PENDING_FOLLOWUP_STATUS,
    };

    const { data: updatedData, error: updateError } = await supabase
      .from("izzy_followups")
      .update(updates)
      .eq("id", existing.id)
      .select("*")
      .single();

    if (updateError) throw updateError;

    return {
      followup: updatedData as FollowupRow,
      created: false,
    };
  }

  const { data: createdData, error: createError } = await supabase
    .from("izzy_followups")
    .insert({
      lead_id: payload.lead_id,
      agent_user_id: payload.agent_user_id,
      source_call_id: sourceCallId,
      status: PENDING_FOLLOWUP_STATUS,
      scheduled_for: payload.scheduled_for,
      subject,
      notes,
    })
    .select("*")
    .single();

  if (createError) throw createError;

  return {
    followup: createdData as FollowupRow,
    created: true,
  };
}

async function handleWorkspace(sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const [{ data: leadsData, error: leadsError }, { data: callsData, error: callsError }, { data: followupsData, error: followupsError }] =
    await Promise.all([
      supabase.from("izzy_leads").select("*").order("created_at", { ascending: false }),
      supabase.from("izzy_lead_calls").select("*").order("started_at", { ascending: false }).limit(500),
      supabase.from("izzy_followups").select("*").order("scheduled_for", { ascending: true }).limit(500),
    ]);

  if (leadsError || callsError || followupsError) {
    console.error("[izzy-call-center] workspace fetch failed", { leadsError, callsError, followupsError });
    return jsonResponse({ error: "Could not load workspace" }, { status: 500 });
  }

  const scopedLeads = ((leadsData || []) as LeadRow[]).filter((lead) => leadIsVisibleToUser(lead, sessionUser, portalUser));
  const scopedLeadIds = new Set(scopedLeads.map((lead) => lead.id));
  const scopedCalls = ((callsData || []) as LeadCallRow[]).filter((call) =>
    sessionUser.rol === "admin" ? scopedLeadIds.has(call.lead_id) : call.agent_user_id === portalUser.id || scopedLeadIds.has(call.lead_id)
  );
  const scopedFollowups = ((followupsData || []) as FollowupRow[]).filter((followup) =>
    sessionUser.rol === "admin" ? scopedLeadIds.has(followup.lead_id) : followup.agent_user_id === portalUser.id || scopedLeadIds.has(followup.lead_id)
  );

  const todayKey = losAngelesDateKey(new Date());
  const callsToday = scopedCalls.filter((call) => losAngelesDateKey(call.started_at) === todayKey);
  const followupsToday = scopedFollowups.filter((followup) => followup.status === "scheduled" && losAngelesDateKey(followup.scheduled_for) === todayKey);
  const followupsOverdue = scopedFollowups.filter((followup) => followup.status === "scheduled" && losAngelesDateKey(followup.scheduled_for) < todayKey);

  const enrichedLeads = scopedLeads.map((lead) => {
    const derivedFollowupStatus = deriveFollowupStatus(lead.next_followup_at);
    return {
      ...lead,
      computed_followup_status: derivedFollowupStatus,
      is_due_today: derivedFollowupStatus === "due_today",
      is_overdue: derivedFollowupStatus === "overdue",
      sent_to_quote: Boolean(cleanString(lead.cotizacion_enviada)),
    };
  });

  const kpis = {
    assigned_leads: enrichedLeads.length,
    calls_today: callsToday.length,
    contacted_today: callsToday.filter((call) => ["answered", "interested", "quote_requested", "call_back"].includes(call.call_status)).length,
    no_answer_today: callsToday.filter((call) => call.call_status === "no_answer").length,
    followups_today: followupsToday.length,
    overdue_followups: followupsOverdue.length,
    interested_leads: enrichedLeads.filter((lead) =>
      ["qualified", "quote_requested", "quote_pending", "quoted_ready"].includes(lead.lead_status_code || "") ||
      lead.last_contact_result === "interested"
    ).length,
    sent_to_quote: enrichedLeads.filter((lead) =>
      ["quote_requested", "quote_pending", "quoted_ready"].includes(lead.lead_status_code || "") || Boolean(cleanString(lead.cotizacion_enviada))
    ).length,
  };

  return jsonResponse({
    user: {
      id: portalUser.id,
      nombre: portalUser.nombre,
      rol: portalUser.rol,
    },
    kpis,
    leads: enrichedLeads,
    calls_today: callsToday,
    followups_today: followupsToday,
    followups_overdue: followupsOverdue,
    status_options: Array.from(LEAD_STATUS_CODES),
    call_result_options: Array.from(CALL_RESULTS),
  });
}

async function handleLeadTimeline(leadId: number, sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const lead = await requireVisibleLead(supabase, leadId, sessionUser, portalUser);
  const [{ data: callsData, error: callsError }, { data: activitiesData, error: activitiesError }, { data: followupsData, error: followupsError }] =
    await Promise.all([
      supabase.from("izzy_lead_calls").select("*").eq("lead_id", leadId).order("started_at", { ascending: false }),
      supabase.from("izzy_lead_activities").select("*").eq("lead_id", leadId).order("created_at", { ascending: false }),
      supabase.from("izzy_followups").select("*").eq("lead_id", leadId).order("scheduled_for", { ascending: false }),
    ]);

  if (callsError || activitiesError || followupsError) {
    console.error("[izzy-call-center] timeline fetch failed", { callsError, activitiesError, followupsError });
    return jsonResponse({ error: "Could not load timeline" }, { status: 500 });
  }

  const calls = (callsData || []) as LeadCallRow[];
  const activities = (activitiesData || []) as ActivityRow[];
  const followups = (followupsData || []) as FollowupRow[];

  const timeline = [
    ...calls.map((call) => ({
      kind: "call",
      sort_at: call.started_at,
      item: call,
    })),
    ...activities.map((activity) => ({
      kind: "activity",
      sort_at: activity.created_at,
      item: activity,
    })),
    ...followups.map((followup) => ({
      kind: "followup",
      sort_at: followup.completed_at || followup.scheduled_for,
      item: followup,
    })),
  ].sort((a, b) => String(b.sort_at).localeCompare(String(a.sort_at)));

  return jsonResponse({ lead, calls, activities, followups, timeline });
}

async function handleCreateCall(req: Request, sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const body = await req.json().catch(() => ({}));
  const leadId = cleanInteger(body?.lead_id);
  if (!leadId) return jsonResponse({ error: "lead_id is required" }, { status: 400 });

  const lead = await requireVisibleLead(supabase, leadId, sessionUser, portalUser);
  const callStatus = cleanString(body?.call_status);
  const disposition = cleanString(body?.disposition || body?.call_status);
  const direction = cleanString(body?.direction || "outbound") || "outbound";
  const startedAt = cleanIsoDateTime(body?.started_at) || nowIso();
  const endedAt = cleanIsoDateTime(body?.ended_at);
  const durationSeconds = cleanInteger(body?.duration_seconds);
  const notes = cleanNullableString(body?.notes);
  const nextAction = cleanNullableString(body?.next_action);
  const nextFollowupAt = cleanIsoDateTime(body?.next_followup_at);

  if (!CALL_RESULTS.has(callStatus) || !CALL_RESULTS.has(disposition)) {
    return jsonResponse({ error: "Invalid call status or disposition" }, { status: 400 });
  }

  const { data: call, error: callError } = await supabase
    .from("izzy_lead_calls")
    .insert({
      lead_id: leadId,
      agent_user_id: portalUser.id,
      direction,
      call_status: callStatus,
      disposition,
      notes,
      started_at: startedAt,
      ended_at: endedAt,
      duration_seconds: durationSeconds,
      next_action: nextAction,
      next_followup_at: nextFollowupAt,
    })
    .select("*")
    .single();

  if (callError) {
    console.error("[izzy-call-center] create call failed", callError);
    return jsonResponse({ error: "Could not save call" }, { status: 500 });
  }

  const nextLeadStatus = deriveLeadStatusFromCall(callStatus, lead.lead_status_code);
  const leadPatch: Record<string, unknown> = {
    last_contact_at: startedAt,
    last_contact_result: callStatus,
    lead_status_code: nextLeadStatus,
  };

  if (callStatus === "quote_requested" && cleanString(lead.estado) === "Nuevo") {
    leadPatch.estado = "Contactado";
  }

  const { error: leadError } = await supabase
    .from("izzy_leads")
    .update(leadPatch)
    .eq("id", leadId)
    .select("id")
    .single();

  if (leadError) {
    console.error("[izzy-call-center] update lead after call failed", leadError);
    return jsonResponse({ error: "Call saved but lead update failed" }, { status: 500 });
  }

  await insertActivity(supabase, {
    lead_id: leadId,
    agent_user_id: portalUser.id,
    activity_type: "call_logged",
    title: `Llamada ${callStatus}`,
    body: notes,
    metadata: {
      call_id: (call as LeadCallRow).id,
      call_status: callStatus,
      disposition,
      next_action: nextAction,
      next_followup_at: nextFollowupAt,
    },
  });

  let createdFollowup: FollowupRow | null = null;
  if (nextFollowupAt) {
    try {
      const followupResult = await upsertPendingFollowup(supabase, {
        lead_id: leadId,
        agent_user_id: portalUser.id,
        source_call_id: (call as LeadCallRow).id,
        scheduled_for: nextFollowupAt,
        subject: nextAction || "Follow-up",
        notes,
      });
      createdFollowup = followupResult.followup;
      await insertActivity(supabase, {
        lead_id: leadId,
        agent_user_id: portalUser.id,
        activity_type: "followup_created",
        title: followupResult.created ? "Seguimiento programado" : "Seguimiento actualizado",
        body: nextAction || notes,
        metadata: {
          followup_id: createdFollowup.id,
          scheduled_for: nextFollowupAt,
          source: "call_logged",
          deduplicated: !followupResult.created,
        },
      });
    } catch (followupError) {
      console.error("[izzy-call-center] create followup from call failed", followupError);
      return jsonResponse({ error: "Call saved but follow-up creation failed" }, { status: 500 });
    }
  }

  if (lead.lead_status_code !== nextLeadStatus) {
    await insertActivity(supabase, {
      lead_id: leadId,
      agent_user_id: portalUser.id,
      activity_type: "status_changed",
      title: `Estado actualizado a ${nextLeadStatus}`,
      metadata: {
        previous_status: lead.lead_status_code,
        next_status: nextLeadStatus,
      },
    });
  }

  try {
    const syncResult = await syncLeadNextFollowup(supabase, leadId);
    return jsonResponse({ call, lead: syncResult.lead, followup: createdFollowup, next_followup: syncResult.next_followup });
  } catch (syncError) {
    console.error("[izzy-call-center] sync lead after call failed", syncError);
    return jsonResponse({ error: "Call saved but next follow-up sync failed" }, { status: 500 });
  }
}

async function handleCreateNote(req: Request, sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const body = await req.json().catch(() => ({}));
  const leadId = cleanInteger(body?.lead_id);
  const note = cleanNullableString(body?.note);
  if (!leadId || !note) return jsonResponse({ error: "lead_id and note are required" }, { status: 400 });

  await requireVisibleLead(supabase, leadId, sessionUser, portalUser);
  await insertActivity(supabase, {
    lead_id: leadId,
    agent_user_id: portalUser.id,
    activity_type: "note_added",
    title: "Nota agregada",
    body: note,
  });

  return jsonResponse({ ok: true });
}

async function handleCreateFollowup(req: Request, sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const body = await req.json().catch(() => ({}));
  const leadId = cleanInteger(body?.lead_id);
  const scheduledFor = cleanIsoDateTime(body?.scheduled_for);
  const subject = cleanNullableString(body?.subject);
  const notes = cleanNullableString(body?.notes);

  if (!leadId || !scheduledFor) {
    return jsonResponse({ error: "lead_id and scheduled_for are required" }, { status: 400 });
  }

  const lead = await requireVisibleLead(supabase, leadId, sessionUser, portalUser);

  let followupResult: { followup: FollowupRow; created: boolean };
  try {
    followupResult = await upsertPendingFollowup(supabase, {
      lead_id: leadId,
      agent_user_id: portalUser.id,
      scheduled_for: scheduledFor,
      subject,
      notes,
    });
  } catch (followupError) {
    console.error("[izzy-call-center] create followup failed", followupError);
    return jsonResponse({ error: "Could not create follow-up" }, { status: 500 });
  }

  const nextLeadStatus = lead.lead_status_code === "new" ? "follow_up" : lead.lead_status_code;
  const { error: leadError } = await supabase
    .from("izzy_leads")
    .update({
      lead_status_code: nextLeadStatus,
    })
    .eq("id", leadId)
    .select("id")
    .single();

  if (leadError) {
    console.error("[izzy-call-center] update lead from followup failed", leadError);
    return jsonResponse({ error: "Follow-up created but lead update failed" }, { status: 500 });
  }

  await insertActivity(supabase, {
    lead_id: leadId,
    agent_user_id: portalUser.id,
    activity_type: "followup_created",
    title: followupResult.created ? "Seguimiento programado" : "Seguimiento actualizado",
    body: subject || notes,
    metadata: {
      followup_id: followupResult.followup.id,
      scheduled_for: scheduledFor,
      deduplicated: !followupResult.created,
    },
  });

  if (lead.lead_status_code !== nextLeadStatus) {
    await insertActivity(supabase, {
      lead_id: leadId,
      agent_user_id: portalUser.id,
      activity_type: "status_changed",
      title: `Estado actualizado a ${nextLeadStatus}`,
      metadata: {
        previous_status: lead.lead_status_code,
        next_status: nextLeadStatus,
      },
    });
  }

  try {
    const syncResult = await syncLeadNextFollowup(supabase, leadId);
    return jsonResponse({ followup: followupResult.followup, lead: syncResult.lead, next_followup: syncResult.next_followup });
  } catch (syncError) {
    console.error("[izzy-call-center] sync lead after followup create failed", syncError);
    return jsonResponse({ error: "Follow-up saved but next follow-up sync failed" }, { status: 500 });
  }
}

async function handlePatchLead(req: Request, sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const url = new URL(req.url);
  const leadId = cleanInteger(url.searchParams.get("id"));
  const body = await req.json().catch(() => ({}));

  if (!leadId) return jsonResponse({ error: "Lead id is required" }, { status: 400 });

  const lead = await requireVisibleLead(supabase, leadId, sessionUser, portalUser);
  const updates: Record<string, unknown> = {};

  if ("lead_status_code" in body) {
    const value = cleanString(body.lead_status_code);
    if (!LEAD_STATUS_CODES.has(value)) return jsonResponse({ error: "Invalid lead_status_code" }, { status: 400 });
    updates.lead_status_code = value;
  }

  if ("priority" in body) {
    const value = cleanString(body.priority);
    if (!PRIORITIES.has(value)) return jsonResponse({ error: "Invalid priority" }, { status: 400 });
    updates.priority = value;
  }

  if ("next_action" in body) updates.next_action = cleanNullableString(body.next_action);
  if ("last_contact_result" in body) updates.last_contact_result = cleanNullableString(body.last_contact_result);
  if ("do_not_call" in body) updates.do_not_call = cleanBoolean(body.do_not_call);
  const requestedNextAction = "next_action" in body ? cleanNullableString(body.next_action) : lead.next_action;
  const requestedNextFollowupAt = "next_followup_at" in body ? cleanIsoDateTime(body.next_followup_at) : null;
  if ("next_followup_at" in body) {
    updates.next_followup_at = requestedNextFollowupAt;
    updates.next_followup_status = deriveFollowupStatus(requestedNextFollowupAt);
  }

  if (Object.keys(updates).length === 0) {
    return jsonResponse({ error: "No valid lead updates provided" }, { status: 400 });
  }

  const { data: updatedLead, error } = await supabase
    .from("izzy_leads")
    .update(updates)
    .eq("id", leadId)
    .select("*")
    .single();

  if (error) {
    console.error("[izzy-call-center] patch lead failed", error);
    return jsonResponse({ error: "Could not update lead" }, { status: 500 });
  }

  if (updates.lead_status_code && updates.lead_status_code !== lead.lead_status_code) {
    await insertActivity(supabase, {
      lead_id: leadId,
      agent_user_id: portalUser.id,
      activity_type: "status_changed",
      title: `Estado actualizado a ${String(updates.lead_status_code)}`,
      metadata: {
        previous_status: lead.lead_status_code,
        next_status: updates.lead_status_code,
      },
    });
  }

  if ("next_followup_at" in body && requestedNextFollowupAt) {
    try {
      const followupResult = await upsertPendingFollowup(supabase, {
        lead_id: leadId,
        agent_user_id: portalUser.id,
        scheduled_for: requestedNextFollowupAt,
        subject: requestedNextAction,
      });
      await insertActivity(supabase, {
        lead_id: leadId,
        agent_user_id: portalUser.id,
        activity_type: "followup_created",
        title: followupResult.created ? "Seguimiento programado desde estado" : "Seguimiento actualizado desde estado",
        body: requestedNextAction,
        metadata: {
          followup_id: followupResult.followup.id,
          scheduled_for: requestedNextFollowupAt,
          source: "lead_patch",
          deduplicated: !followupResult.created,
        },
      });
    } catch (followupError) {
      console.error("[izzy-call-center] patch lead followup sync failed", followupError);
      return jsonResponse({ error: "Lead updated but follow-up sync failed" }, { status: 500 });
    }
  }

  if ("next_followup_at" in body) {
    try {
      const syncResult = await syncLeadNextFollowup(supabase, leadId);
      return jsonResponse({ lead: syncResult.lead, updated_lead: updatedLead, next_followup: syncResult.next_followup });
    } catch (syncError) {
      console.error("[izzy-call-center] patch lead next followup recalculation failed", syncError);
      return jsonResponse({ error: "Lead updated but next follow-up recalculation failed" }, { status: 500 });
    }
  }

  return jsonResponse({ lead: updatedLead });
}

async function handlePatchFollowup(req: Request, sessionUser: SessionUser, portalUser: PortalUser) {
  const supabase = createAdminClient();
  const url = new URL(req.url);
  const followupId = cleanInteger(url.searchParams.get("id"));
  const body = await req.json().catch(() => ({}));
  if (!followupId) return jsonResponse({ error: "Follow-up id is required" }, { status: 400 });

  const { data: followupData, error: followupLookupError } = await supabase
    .from("izzy_followups")
    .select("*")
    .eq("id", followupId)
    .maybeSingle();

  if (followupLookupError) {
    console.error("[izzy-call-center] followup lookup failed", followupLookupError);
    return jsonResponse({ error: "Could not load follow-up" }, { status: 500 });
  }

  if (!followupData) return jsonResponse({ error: "Follow-up not found" }, { status: 404 });
  const followup = followupData as FollowupRow;
  const lead = await requireVisibleLead(supabase, followup.lead_id, sessionUser, portalUser);

  const updates: Record<string, unknown> = {};
  if ("status" in body) {
    const status = cleanString(body.status);
    if (!FOLLOWUP_STATUSES.has(status)) return jsonResponse({ error: "Invalid follow-up status" }, { status: 400 });
    updates.status = status;
    if (status === "completed") updates.completed_at = nowIso();
  }
  if ("scheduled_for" in body) updates.scheduled_for = cleanIsoDateTime(body.scheduled_for);
  if ("subject" in body) updates.subject = cleanNullableString(body.subject);
  if ("notes" in body) updates.notes = cleanNullableString(body.notes);
  if ("outcome" in body) updates.outcome = cleanNullableString(body.outcome);

  if (Object.keys(updates).length === 0) {
    return jsonResponse({ error: "No valid follow-up updates provided" }, { status: 400 });
  }

  const { data: updatedFollowup, error: updateError } = await supabase
    .from("izzy_followups")
    .update(updates)
    .eq("id", followupId)
    .select("*")
    .single();

  if (updateError) {
    console.error("[izzy-call-center] patch followup failed", updateError);
    return jsonResponse({ error: "Could not update follow-up" }, { status: 500 });
  }

  const latestScheduledFor = cleanIsoDateTime((updatedFollowup as FollowupRow).scheduled_for);

  const status = String((updates.status || followup.status));
  await insertActivity(supabase, {
    lead_id: followup.lead_id,
    agent_user_id: portalUser.id,
    activity_type: status === "completed" ? "followup_completed" : "followup_rescheduled",
    title: status === "completed" ? "Seguimiento completado" : "Seguimiento actualizado",
    body: cleanNullableString(body?.outcome) || cleanNullableString(body?.notes),
    metadata: {
      followup_id: followupId,
      status,
      scheduled_for: latestScheduledFor,
    },
  });

  try {
    const syncResult = await syncLeadNextFollowup(supabase, lead.id);
    return jsonResponse({ followup: updatedFollowup, lead: syncResult.lead, next_followup: syncResult.next_followup });
  } catch (syncError) {
    console.error("[izzy-call-center] sync lead after followup patch failed", syncError);
    return jsonResponse({ error: "Follow-up updated but next follow-up recalculation failed" }, { status: 500 });
  }
}

async function handleGet(req: Request) {
  const sessionUser = await requireSession(req);
  const portalUser = await getPortalUser(createAdminClient(), sessionUser);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "workspace";

  if (resource === "workspace") {
    return await handleWorkspace(sessionUser, portalUser);
  }

  if (resource === "lead-timeline") {
    const leadId = cleanInteger(url.searchParams.get("id"));
    if (!leadId) return jsonResponse({ error: "Lead id is required" }, { status: 400 });
    return await handleLeadTimeline(leadId, sessionUser, portalUser);
  }

  return jsonResponse({ error: "Unknown resource" }, { status: 400 });
}

async function handlePost(req: Request) {
  const sessionUser = await requireSession(req);
  const portalUser = await getPortalUser(createAdminClient(), sessionUser);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "";

  if (resource === "lead-call") return await handleCreateCall(req, sessionUser, portalUser);
  if (resource === "followup") return await handleCreateFollowup(req, sessionUser, portalUser);
  if (resource === "note") return await handleCreateNote(req, sessionUser, portalUser);

  return jsonResponse({ error: "Unknown resource" }, { status: 400 });
}

async function handlePatch(req: Request) {
  const sessionUser = await requireSession(req);
  const portalUser = await getPortalUser(createAdminClient(), sessionUser);
  const url = new URL(req.url);
  const resource = url.searchParams.get("resource") || "";

  if (resource === "lead") return await handlePatchLead(req, sessionUser, portalUser);
  if (resource === "followup") return await handlePatchFollowup(req, sessionUser, portalUser);

  return jsonResponse({ error: "Unknown resource" }, { status: 400 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "GET") return await handleGet(req);
    if (req.method === "POST") return await handlePost(req);
    if (req.method === "PATCH") return await handlePatch(req);
    return jsonResponse({ error: "Method not allowed" }, { status: 405 });
  } catch (error) {
    if (error instanceof Response) {
      const body = await error.text();
      return new Response(body, {
        status: Number.isInteger(error.status) && error.status >= 200 && error.status <= 599 ? error.status : 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.error("[izzy-call-center] unexpected error", error);
    return jsonResponse({ error: "Internal server error" }, { status: 500 });
  }
});
