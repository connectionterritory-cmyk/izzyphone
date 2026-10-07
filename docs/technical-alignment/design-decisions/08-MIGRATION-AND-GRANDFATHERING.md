# 08 — Migration, Backfill, and Grandfathering Strategy Specification

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-08`  
**Phase:** Migration Planning & Data Transition Strategy  
**Status:** PROPOSED — PENDING OWNER DECISION  
**Target Authority:** Moisés Caicedo  

---

## 1. Context and Problem Statement

Migrating an active telecom compensation system with hundreds of agents and thousands of historical orders requires mathematical precision. A flawed migration risks:
1. Retroactive financial distortion (recomputing past payouts under new rules).
2. Data loss or corruption of historical order and commission tables.
3. Churn disputes caused by applying modern 100% clawback rules to historical orders that were contracted under 120-day reserve rules.

---

## 2. Zero-Data-Loss Migration Philosophy

The migration adheres to three architectural guarantees:

1. **Purely Additive Schema First:**
   - Existing tables (`izzy_orders`, `izzy_portal_users`, `izzy_commission_rates`, `izzy_commission_reserves`) remain intact.
   - New V1 tables (`izzy_v1_products`, `izzy_commission_plan_versions`, `izzy_connection_compensation_snapshots`, `izzy_compensation_ledger_entries`, etc.) are created alongside existing structures.
   - **Zero initial drops, zero table renames, and zero destructive column alterations.**
2. **Dual-Pipeline Execution:**
   - Legacy orders continue executing through the legacy read paths.
   - V1 orders execute through the new V1 snapshot, engine, and ledger pipelines.
3. **Discriminator Flag on Ingestion:**
   - Every order entity is stamped with an immutable discriminator:
     $$\text{program\_code} \in \{\text{'LEGACY'}, \text{'IZZY-COMM-V1'}\}$$

---

## 3. Backfill Assessment: Deterministic vs. Non-Reconstructable Data

A critical hazard in data migrations is attempting to "guess" or infer past data. We strictly partition existing data fields into what can be safely backfilled versus what must be declared **NOT RECONSTRUCTABLE**.

### 3.1 Deterministic Fields (Safe for Backfill)

These fields represent objective historical facts that can be mapped 1:1 without inference:

| Field | Source in Legacy Database | Backfill Rule / Logic |
|---|---|---|
| `connection_id` | `izzy_orders.id` | Direct 1:1 foreign key assignment. |
| `seller_id` | `izzy_orders.portal_user_id` | Direct 1:1 assignment. |
| `carrier` | `izzy_orders.carrier_name` | Direct string normalization. |
| `sale_date` | `izzy_orders.created_at` | Direct timestamp mapping. |
| `activation_date` | `izzy_orders.actual_install_date` | Direct mapping where not null. |
| `validation_date` | `izzy_orders.satisfaction_verified_at` | Direct mapping where verified. |
| `legacy_commission_paid` | `izzy_orders.commission_amount` | Recorded as legacy historical paid amount. |

### 3.2 Non-Reconstructable Fields (Strictly Prohibited from Backfill)

Attempting to backfill the following V1 concepts onto legacy orders would fabricate financial history and is **strictly prohibited**:

| Concept | Why It Is Marked `NOT RECONSTRUCTABLE` | Enforcement Action |
|---|---|---|
| **V1 25/50 Ordinal & Tier** | The legacy system had no Pacific-time validation ordering or 25/50 tranches. Inferring ordinals would randomly award bonuses to some legacy orders while denying them to others. | Set to `NULL` / `Tier = 0` for all legacy records. |
| **V1 Leadership Recipient ($5)** | The legacy system had Director overrides, not $5 single-depth internet leadership. Hierarchy snapshots at historical validation moments were not frozen. | Set to `NULL` / `$0.00` for all legacy records. |
| **V1 Component Breakdown** | Legacy records store a single lumped `commission_amount`. They cannot be separated into Base vs. Production vs. Leadership. | Recorded solely as a legacy lump sum; do not synthesize ledger entries. |
| **Historical Closed Periods** | Legacy accounting had no `OPEN`/`PRELIMINARY`/`CLOSED` state machine. | Legacy periods are marked `LEGACY_SETTLED`. |

---

## 4. Chargeback Migration Boundary Contract

The legacy system and V1 implement conflicting chargeback policies:
- **Legacy Policy:** 120-day reserve holdback in `izzy_commission_reserves`, release upon expiration, partial carrier-specific clawbacks.
- **V1 Policy (`IZZY-COMM-2026-10-V1`):** Strict 3-month active requirement; 100% reversal across base commission, production bonus, and leadership bonus; negative balance offset against future earnings.

### 4.1 Deterministic Policy Routing by `program_code`

To prevent legal and operational chaos, the chargeback engine routes churn events based on the connection's immutable program classification:

```
                                 [ CHURN / CHARGEBACK EVENT ]
                                              |
                                              v
                              Check connection.program_code
                                              |
                     +------------------------+------------------------+
                     |                                                 |
                     v                                                 v
        [ program_code == 'LEGACY' ]                    [ program_code == 'IZZY-COMM-V1' ]
                     |                                                 |
                     v                                                 v
        Apply Legacy 120-Day Reserve Policy             Apply V1 3-Month / 100% Reversal Policy
        - Inspect izzy_commission_reserves              - Claw back 100% Base Commission
        - Debit legacy escrow funds                     - Claw back 100% Production Bonus
        - Zero impact on V1 negative balances           - Claw back 100% Leadership Bonus
                                                        - Debit izzy_negative_balance_accounts
```

### 4.2 Chargeback Policy Summary Table

| Attribute | Legacy Chargeback Path | V1 Chargeback Path |
|---|---|---|
| **Applicability** | Orders with `sale_date < V1_EFFECTIVE_AT` | Orders with `sale_date >= V1_EFFECTIVE_AT` |
| **Qualifying Window** | 120 days from installation date | 3 months (90 days) from installation date |
| **Clawback Scope** | Escrowed reserve amount in `izzy_commission_reserves` | 100% full reversal of Base, Production, and Leadership |
| **Recovery Mechanism** | Forfeit unreleased reserve balance | Automated offset via `izzy_negative_balance_accounts` |
| **Impact on Other Orders** | Zero impact on other orders | Zero impact on other orders (tiers never shift) |

---

## 5. Transition Deployment Sequence (Phase 2 Roadmap)

When implementation is formally authorized by Moisés Caicedo, the technical deployment will proceed in five non-disruptive stages:

1. **Stage 1 (DDL Additions):** Deploy all new V1 tables and indexes without altering existing tables.
2. **Stage 2 (Catalog Seed):** Seed `izzy_v1_products` with the 10 canonical products and `izzy_commission_plan_versions` with `IZZY-COMM-2026-10-V1`.
3. **Stage 3 (Initial Rank Onboarding):** Populate `izzy_v1_rank_events` and `izzy_v1_hierarchy_events` for **active** users only, per the approved mapping (`novato`→`training`, `agente`→`associate`, `supervisor`→`supervisor`, `director`→`supervisor`; `embajador` outside V1), with `effective_at = 2026-11-01 07:00:00 UTC` and reason `initial_v1_onboarding`. Inactive users receive no automatic event; their rank is assigned explicitly on reactivation. Users without `manager_user_id` / `sponsor_user_id` keep `supervisor_id = NULL` until an explicit owner decision. See `13-D02-AND-RANK-MAPPING-DECISION-RECORD.md`.
4. **Stage 4 (Engine Activation & Ingestion Gate):** Deploy the V1 calculation engine behind a feature flag, stamping new orders as `IZZY-COMM-V1` once `sale_date >= V1_EFFECTIVE_AT`.
5. **Stage 5 (Verification & Dual Reporting):** Run parallel verification for the first monthly cycle before deprecating legacy UI views.
