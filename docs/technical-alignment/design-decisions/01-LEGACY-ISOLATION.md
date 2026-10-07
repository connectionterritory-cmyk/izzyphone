# 01 — Legacy Isolation Specification

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-01`  
**Phase:** Material Design Decisions / Schema Contract  
**Status:** APPROVED (conceptual design) — 2026-10-07; rank mapping per `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md`; implementation not authorized  
**Target Authority:** Moisés Caicedo  

---

## 1. Context and Problem Statement

The existing IZZY Communications platform contains historical and operational compensation structures that directly conflict with the frozen V1 compensation model (`IZZY-COMM-2026-10-V1`). Specifically:

1. **Legacy Rank Hierarchy:** The existing database (`izzy_portal_users`, `izzy_agent_rank_history`, and `izzy_commission_rates`) implements five ranks:
   - `novato` (Agente en Entrenamiento)
   - `agente` (Asociado)
   - `supervisor` (Supervisor)
   - `director` (Legacy — Director)
   - `embajador` (Legacy — Embajador)
2. **Legacy Economic Programs:** The current codebase implements multi-generational overrides (`izzy_director_bonus_rates`), ambassador commercial incentives, promotional multipliers, and category-based compensation tiers.
3. **V1 Compensation Standard:** The frozen V1 compensation plan recognizes **strictly three compensation ranks**:
   - `Agente en Entrenamiento` (code: `training`)
   - `Asociado` (code: `associate`)
   - `Supervisor` (code: `supervisor`)

Under V1 governance, `Director` and `Embajador` have zero economic standing. However, historical records cannot be discarded, modified, or forcibly mapped, as doing so would corrupt past financial statements, disrupt existing user accounts, and violate auditability.

---

## 2. Core Architectural Principles

To resolve this conflict deterministically, the design enforces four inviolable principles:

1. **Zero Data Loss:** No historical database rows in `izzy_orders`, `izzy_portal_users`, `izzy_agent_rank_history`, or legacy rate tables will be deleted or overwritten.
2. **No Automatic Rank Conversion:** Users holding legacy ranks (e.g., `director` or `embajador`) will **not** be automatically converted or downgraded to V1 ranks in legacy tables. Automatic conversion would distort historical organizational records.
3. **Complete Economic Isolation:** Legacy ranks and legacy bonus rules must be completely prevented from producing ledger entries, pool entries, or overrides within the V1 economic engine.
4. **Historical Reporting Continuity:** Legacy reports, historical statements, and audit dashboards for pre-V1 periods must remain 100% readable and consistent against legacy data models.

---

## 3. Recommended Design: Dual-Track Rank Architecture

The recommended solution is a strict **Dual-Track Isolation Model** separating historical portal roles from V1 effective compensation ranks:

```
+---------------------------------------------------------------------------------+
|                                 PORTAL USER                                      |
|                                                                                 |
|  Legacy Profile (Untouched)                     V1 Effective Rank History        |
|  izzy_portal_users.compensation_role            izzy_v1_rank_events             |
|  [ 'director', 'embajador', etc. ]              [ 'training', 'associate',      |
|                                                   'supervisor' ]                |
+-------------------------------------------------------+-------------------------+
                         |                              |
                         v                              v
             +-----------------------+      +-----------------------+
             |   LEGACY PIPELINE     |      |      V1 PIPELINE      |
             |  (Orders < Boundary)  |      | (Orders >= Boundary)  |
             |   izzy_orders         |      | izzy_connection_      |
             |   izzy_commission_    |      |   compensation_       |
             |     rates             |      |   snapshots           |
             |   Director Overrides  |      | izzy_compensation_    |
             |   Ambassador Perks    |      |   ledger_entries      |
             +-----------------------+      +-----------------------+
```

### 3.1 Schema Isolation (`izzy_v1_rank_events`)

Rather than mutating `izzy_portal_users.compensation_role`, a new dedicated event-sourced table is introduced:

```sql
-- CONCEPTUAL SCHEMA CONTRACT (NOT MIGRATION SQL)
CREATE TABLE izzy_v1_rank_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id BIGINT NOT NULL REFERENCES izzy_portal_users(id),
    rank_code VARCHAR(20) NOT NULL CHECK (rank_code IN ('training', 'associate', 'supervisor')),
    effective_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NULL,
    reason VARCHAR(50) NOT NULL CHECK (reason IN ('initial_v1_onboarding', 'promoted_to_associate', 'promoted_to_supervisor', 'demotion_maintenance_failed', 'manual_adjustment')),
    approved_by BIGINT NOT NULL REFERENCES izzy_portal_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
```

### 3.2 Cutover Mapping for V1 Compensation Calculations

When the V1 engine resolves the compensation rank for an agent on a V1 connection, it **only** queries `izzy_v1_rank_events` active at the connection's snapshot anchor timestamp:

1. **Active V1 Rank Resolution:**
   ```sql
   SELECT rank_code 
   FROM izzy_v1_rank_events 
   WHERE user_id = :seller_id 
     AND effective_at <= :snapshot_anchor_timestamp 
     AND (ended_at IS NULL OR ended_at > :snapshot_anchor_timestamp)
   ORDER BY effective_at DESC 
   LIMIT 1;
   ```
2. **Circuit Breaker:** If an agent has no entry in `izzy_v1_rank_events`, the V1 engine defaults to `training` (Agente en Entrenamiento) or blocks economic snapshot creation with a fatal audit error (`ERR_V1_RANK_NOT_FOUND`). Under no circumstances does the engine fall back to `izzy_portal_users.compensation_role`.

### 3.3 Disabling Automatic Legacy Promotions

The legacy function `syncRankPromotions` in `izzy-compensation` dynamically alters user ranks based on order counts and category points. 
- For V1, automatic rank elevation is **strictly prohibited**.
- V1 rank promotions require an explicit `izzy_v1_rank_events` record with an authorized `effective_at` timestamp.
- Legacy `syncRankPromotions` is modified or scoped to ignore any user once onboarded to V1, preventing legacy cron jobs from mutating V1 compensation state.

---

## 4. Alternative Considered and Rationale for Rejection

| Alternative Option | Description | Reason for Rejection |
|---|---|---|
| **Direct Schema Mutation / Drop** | Update `izzy_portal_users.compensation_role` replacing all `director` and `embajador` with `supervisor`. | **REJECTED:** Violates auditability. Modifies historical records. Causes legal and commercial confusion regarding past agreements. Destroys historical reporting accuracy. |
| **View-Based Alias Mapping** | Use a database view that maps `director` -> `supervisor` and `embajador` -> `supervisor` dynamically. | **REJECTED:** Flawed because it allows legacy users to automatically claim Supervisor production bonuses (25/50 tranches) without fulfilling V1 Supervisor qualifications or structure. |

---

## 5. Historical Report Continuity

- Legacy compensation dashboards and queries continue to reference `izzy_orders`, `izzy_commission_rates`, and `izzy_director_bonus_rates`.
- V1 compensation dashboards query exclusively `izzy_connection_compensation_snapshots` and `izzy_compensation_ledger_entries`.
- Historical statements generated prior to the V1 adoption boundary remain 100% reproducible byte-for-byte.

---

## 6. Decision Recommendation

**Recommendation:** Adopt the additive `izzy_v1_rank_events` table and strict dual-track isolation. Do not modify or delete historical legacy roles. Require explicit V1 rank assignment for all active agents prior to processing V1 connections.

---

## 7. Owner Decision — 2026-10-07 (APPROVED)

Full record: `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md`.

| Legacy | V1 |
|---|---|
| `novato` | Agente en Entrenamiento (`training`) |
| `agente` | Asociado (`associate`) |
| `supervisor` | Supervisor (`supervisor`) |
| `director` | Supervisor (`supervisor`) — no fourth economic rank, no Director payments, no Director Bonus in V1 |
| `embajador` | outside V1 economics |
| Productor Elite | outside V1 economics |

- Active users receive an initial V1 event (`effective_at = 2026-11-01 07:00:00 UTC`, reason `initial_v1_onboarding`).
- Inactive users receive no automatic initial event; their rank is assigned explicitly when reactivated.
- Users without `manager_user_id` / `sponsor_user_id` keep V1 supervisor `NULL` until an explicit owner decision.
- No fallback to `compensation_role`. Legacy tables, `izzy_rank_levels`, CHECKs, FKs and legacy orders are not modified.
- "Director" may later be evaluated as a separate display-only organizational title; not implemented, not a V1 rank, no economic effect.
- The DDL in §3.1 uses `BIGINT` identifiers to match `izzy_portal_users.id`.
