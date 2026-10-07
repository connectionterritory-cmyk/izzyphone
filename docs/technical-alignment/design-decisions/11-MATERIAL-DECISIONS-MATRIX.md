# 11 — Material Decisions Matrix

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-11`  
**Phase:** Material Design Decisions / Governance Matrix  
**Status:** PROPOSED — PENDING OWNER DECISIONS  
**Target Authority:** Moisés Caicedo  

---

## 1. Overview

This matrix consolidates all material architecture, data model, and governance decisions required to align IZZY Communications with the frozen V1 Compensation Plan (`IZZY-COMM-2026-10-V1`).

In accordance with the mandate: a decision is marked approved **only** when formally authorized by Moisés Caicedo; all others remain `PENDING OWNER DECISION`.

**Approval log**

| Date | Decision | Result | Reference |
|---|---|---|---|
| 2026-10-06 | D-04 | APPROVED — `validation_date` anchor | `06-IZZY-COMM-V1-CLARIFICATIONS.md` §5 |
| 2026-10-06 | D-06 | APPROVED — Option 1 (AT&T Air = internet; leadership eligible) | `06-IZZY-COMM-V1-CLARIFICATIONS.md` §4 |
| 2026-10-06 | D-16 | APPROVED — Option 1 (150 maintenance does not condition leadership) | `06-IZZY-COMM-V1-CLARIFICATIONS.md` §6 |
| 2026-10-07 | D-02 | APPROVED — `V1_EFFECTIVE_AT = 2026-11-01 00:00:00 America/Los_Angeles = 2026-11-01 07:00:00 UTC` | `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md` §2 |
| 2026-10-07 | D-03 | APPROVED — `sale_date = izzy_orders.created_at` (server-generated) is the sole LEGACY/V1 discriminator | `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md` §2A |
| 2026-10-07 | D-01 | APPROVED (conceptual design) — additive `izzy_v1_rank_events`; initial rank mapping; Director → Supervisor V1; legacy untouched. Implementation not authorized | `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md` §3–§7 |

---

## 2. Material Decisions Table

| DECISION_ID | TOPIC | CURRENT STATE | V1 REQUIREMENT | RECOMMENDED DESIGN | ALTERNATIVE | RISK | MIGRATION IMPACT | MOISÉS DECISION |
|---|---|---|---|---|---|---|---|---|
| **D-01** | Legacy Ranks Isolation | Five ranks (`novato`, `agente`, `supervisor`, `director`, `embajador`) in `izzy_portal_users`. | Exactly three ranks (`training`, `associate`, `supervisor`). No economic standing for Director/Ambassador. | Additive `izzy_v1_rank_events`. Legacy roles kept untouched. V1 engine queries only V1 events. | Mutate legacy roles or map via database view. | Downgrading historical titles causes contractor disputes and corrupts audit. | Zero modification to legacy users; additive onboarding table. | **APPROVED 2026-10-07 (conceptual design)** — additive dual-track `izzy_v1_rank_events`; legacy ranks untouched; mapping `novato`→`training`, `agente`→`associate`, `supervisor`→`supervisor`, `director`→`supervisor`, `embajador` outside V1. Implementation not authorized. See `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md`. |
| **D-02** | Adoption Boundary Timestamp | No system-wide cutoff timestamp exists. | Explicit boundary date separating legacy from V1 accounting. | Establish `V1_EFFECTIVE_AT` in Pacific Time, stored as UTC (e.g., `2026-11-01 07:00:00 UTC`). | Soft rollout without a hard timestamp. | Ambiguous cutover leads to retroactive bonus calculation errors. | Required to discriminate `LEGACY` vs `IZZY-COMM-V1` orders. | **APPROVED 2026-10-07** — `V1_EFFECTIVE_AT = 2026-11-01 00:00:00 America/Los_Angeles = 2026-11-01 07:00:00 UTC`. See `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md` §2. |
| **D-03** | Grandfathering Adoption Rule | Undefined; legacy orders could theoretically trigger V1 logic. | Orders prior to V1 must NEVER be recalculated under V1 rules. | Single deterministic rule: `sale_date < V1_EFFECTIVE_AT` $\implies$ `LEGACY`. Stamped as `program_code = 'LEGACY'`. | Use `validation_date` as the boundary discriminator. | Using validation allows gaming by delaying order submissions. | Guarantees legacy orders remain under legacy compensation. | **APPROVED 2026-10-07** — `sale_date = izzy_orders.created_at` (server-generated); `created_at < V1_EFFECTIVE_AT` = `LEGACY`, `>=` = `IZZY-COMM-V1`; no other date determines classification. See `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md` §2A. |
| **D-04** | Economic Snapshot Anchor Event | Rates resolved dynamically from current user role. | Economic snapshot frozen per connection. | Freeze snapshot at `validation_date` using rank/hierarchy active at validation. | Freeze snapshot at `sale_date` or `activation_date`. | Freezing at sale creates unearned bonus liabilities for uninstalled sales. | Defines when rows in `izzy_connection_compensation_snapshots` lock. | **APPROVED 2026-10-06** — `validation_date` anchor; rank, recipient and hierarchy frozen at validation except documented administrative correction; no historical recalculation. |
| **D-05** | Exact Product Model | Rates based on 3 coarse categories (`basic`, `standard`, `premium`). | Exactly 10 canonical products with exact rates. Categories = metadata only. | Canonical table `izzy_v1_products` with 10 exact product codes. Rate lookup by `product_id`. | Continue category-based pricing with sub-tags. | Wrong payouts; inability to audit carrier-specific products. | Additive product master; orders link to exact `v1_product_id`. | **PENDING OWNER DECISION** (Recommended: Approve 10-product catalog) |
| **D-06** | AT&T Air Leadership Eligibility | Category-based logic does not distinguish fixed wireless. | Leadership: "Internet only; no wireless; no BYOD." | **Option 1:** Internet eligible ($5.00). **Option 2:** Wireless excluded ($0.00). | Infer eligibility dynamically from carrier marketing text. | Inadvertently paying unauthorized $5 bonuses or denying valid earnings. | Sets `leadership_eligible` flag on `ATT-AIR` product row. | **APPROVED — Option 1** (2026-10-06, Moisés Caicedo): AT&T Air is classified as INTERNET for V1; eligible for the $5 leadership bonus when all other V1 conditions are met. |
| **D-07** | Commission Plan Versioning | Single mutable `izzy_commission_rates` table. | Immutable versions formatted `IZZY-COMM-YYYY-MM-V#`. | Header `izzy_commission_plan_versions` + line items `izzy_commission_product_rates`. | Overwrite rate rows in-place when carriers adjust payouts. | Overwriting rates recalculates historical order values retroactively. | Additive version master; orders freeze their `version_id`. | **PENDING OWNER DECISION** (Recommended: Approve versioned architecture) |
| **D-08** | 25/50 Production Bonus Engine | Absent. No tranches, ordinals, or supervisor pools exist. | Supervisor pool (personal + direct non-sup); sorted by date/ID; 1-24: $0, 25-49: T1, 50+: T2. Non-retroactive. | Deterministic sorting algorithm writing `production_ordinal`, `production_tier`, and bonus to snapshot. | Calculate lump-sum team bonuses at end of month. | Lump-sum bonuses obscure individual line-item auditability. | Materializes bonus per connection; no retroactive changes. | **PENDING OWNER DECISION** (Recommended: Approve algorithm) |
| **D-09** | Leadership Bonus Engine ($5) | Director bonus pays multi-tier recursive percentages. | Flat $5, internet only, strictly single depth (1 level). | Deterministic traversal stopping at depth 1; freezes `leadership_recipient_id` and `$5.00`. | Allow multi-generational leadership overrides. | Financial insolvency; margin collapse on multi-tier overrides. | Materializes recipient and bonus on connection snapshot. | **PENDING OWNER DECISION** (Recommended: Approve single-depth engine) |
| **D-10** | Append-Only Compensation Ledger | Ad-hoc updates to `izzy_orders.commission_amount`. | Inviolable financial ledger for credits, debits, reversals, offsets. | `izzy_compensation_ledger_entries` with strict component types and foreign keys. | Edit order commission rows directly. | Complete audit failure; loss of historical financial ledger. | All new payouts written as append-only ledger entries. | **PENDING OWNER DECISION** (Recommended: Approve ledger design) |
| **D-11** | Negative Balance & Clawback Recovery | 120-day reserve holdback; no post-payout recovery mechanism. | 3-month churn window; 100% clawback of base, production, leadership; offset future pay. | Append `REVERSAL` entries; accumulate in `izzy_negative_balance_accounts`; auto-offset future pay. | Waive negative balances upon contractor deactivation. | Corporate absorption of bad debt; unrecovered contractor debt. | Introduces balance account table and automated offset pipeline. | **PENDING OWNER DECISION** (Recommended: Approve offset pipeline) |
| **D-12** | Period Close State Machine | No accounting cutoffs or period states. | Monthly Pacific Time close: `OPEN`, `PRELIMINARY` (1-5), `CLOSED` (day 6), `ADJUSTED`. | `izzy_compensation_periods` table; scheduled Day 6 automated close job; permanent immutability. | Ad-hoc calculation anytime an admin requests reports. | Shifting monthly balances; unstable financial statements. | Introduces period master table and immutable close triggers. | **PENDING OWNER DECISION** (Recommended: Approve period model) |
| **D-13** | Confidentiality & RLS Enforcement | Sensitive carrier payouts and internal margins stored in plain view. | Strict non-exposure: wholesale payouts, margins, reserves, peer debt protected. | RLS intent matrix; DTO sanitization on Edge Functions; dedicated SQL views for agents vs admin. | Expose full tables and rely on client-side JS filtering. | Wholesale contract leaks; agent disputes over company profit. | Additive RLS policies and separated view models. | **PENDING OWNER DECISION** (Recommended: Approve RLS intent matrix) |
| **D-14** | Migration Strategy & Zero Data Loss | Ad-hoc database migrations modifying live tables. | Zero data loss; additive schema first; no initial drops; no retroactive inference. | Purely additive deployment sequence; legacy data kept read-only; no inferring unrecorded data. | Destructive schema refactor dropping legacy tables immediately. | Irrecoverable loss of historical customer and order data. | Zero disruption to live operations during migration. | **PENDING OWNER DECISION** (Recommended: Approve additive migration) |
| **D-15** | Circuit Breaker & Rollback Protocol | No formal rollback procedure exists. | Instant operational shutdown with complete ledger preservation. | Multi-tier feature flags (`V1_CALCULATION_ENGINE_ENABLED`); instant reversion to legacy read paths. | Database rollback restoring snapshot from backup. | Data loss of all orders created between snapshot and restore. | Non-destructive rollback preserves all evidence and ledger rows. | **PENDING OWNER DECISION** (Recommended: Approve rollback plan) |
| **D-16** | Maintenance vs. Leadership Bonus | Unspecified: V1 does not state whether the 150-connection quarterly maintenance conditions the $5 leadership bonus. | Leadership paid when the connection meets leadership rules. | Maintenance does NOT, by itself, condition the $5 leadership bonus. | Condition leadership on prior-quarter maintenance. | Unintended forfeiture or retention without an approved rule. | None (rule-level; consequence of failing maintenance remains a separate undefined owner decision — no rank loss, grace period, retention or retroactivity). | **APPROVED 2026-10-06 — Option 1** |

---

## 3. Critical Path Owner Decisions Requiring Immediate Action

While all 15 design specifications are fully formulated, implementation authorization specifically depends on **three core owner decisions**:

1. **Decision D-02 (APPROVED 2026-10-07):** `V1_EFFECTIVE_AT = 2026-11-01 07:00:00 UTC`.
2. **Decision D-04 (APPROVED 2026-10-06):** Economic snapshot anchor confirmed: `validation_date`.
3. **Decision D-06 (APPROVED 2026-10-06 — Option 1):** AT&T Air classified as internet; eligible for the $5 leadership bonus.
