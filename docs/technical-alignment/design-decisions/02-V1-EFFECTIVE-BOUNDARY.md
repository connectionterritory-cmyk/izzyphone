# 02 — V1 Effective Boundary and Grandfathering Specification

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-02`  
**Phase:** Migration Boundary & Grandfathering Rules  
**Status:** PROPOSED — PENDING OWNER DECISION  
**Target Authority:** Moisés Caicedo  

---

## 1. Context and Problem Statement

The introduction of the V1 Compensation Plan (`IZZY-COMM-2026-10-V1`) creates a fundamental economic transition. The system contains thousands of legacy orders processed under legacy rates, categories, and 120-day reserve rules.

Without an unambiguous, mathematically deterministic adoption boundary:
1. Historical orders could be re-evaluated under V1 production bonus tranches (25/50) or $5 leadership bonuses, causing massive unintended cash liabilities.
2. Legacy sales pending installation or carrier validation during the cutover window could be caught in ambiguous legal/financial states.
3. Chargebacks occurring on historical orders could be mishandled using V1 reversal rules rather than legacy reserve rules.

---

## 2. Core Boundary Principle: Grandfathering

> **Inviolable Principle:**  
> All orders, sales, and connections generated prior to the V1 adoption boundary are **100% Grandfathered**. They must never be re-evaluated, re-tiered, or recalculated under V1 rules.

Specific non-negotiable boundaries:
- **No historical bonus inference:** Legacy orders never receive retroactive V1 production bonus tiers or ordinals.
- **No historical leadership reconstruction:** Legacy uplines never receive $5 internet leadership bonuses on pre-V1 connections.
- **No legacy chargeback recalculation under V1:** Pre-V1 chargebacks are governed strictly by the legacy 120-day reserve policy and legacy rate tables.

---

## 3. The Single Deterministic Boundary Rule

### 3.1 The Adoption Boundary Timestamp (`V1_EFFECTIVE_AT`)

The platform defines a global boundary timestamp:
- **Identifier:** `V1_EFFECTIVE_AT`
- **Timezone standard:** Defined in `America/Los_Angeles` (Pacific Time), stored as absolute UTC.
- **Required Owner Action:** Moisés Caicedo must select the exact effective date (e.g., `2026-11-01 00:00:00-07`, corresponding to `2026-11-01 07:00:00 UTC`).

### 3.2 Boundary Rule Definition

To resolve all transition ambiguities across the connection lifecycle (`sale_date`, `activation_date`, `validation_date`), the system adopts **ONE SINGLE DETERMINISTIC RULE**:

$$\text{Program Classification} = \begin{cases} 
\mathbf{LEGACY} & \text{if } \text{sale\_date} < \text{V1\_EFFECTIVE\_AT} \\ 
\mathbf{IZZY\text{-}COMM\text{-}V1} & \text{if } \text{sale\_date} \ge \text{V1\_EFFECTIVE\_AT} 
\end{cases}$$

### 3.3 Resolution of Transition Scenarios

| Scenario | Condition | Classification | Economic Rules Applied |
|---|---|---|---|
| **A: Pure Legacy** | `sale_date < V1_EFFECTIVE_AT`<br>`activation_date < V1_EFFECTIVE_AT`<br>`validation_date < V1_EFFECTIVE_AT` | **LEGACY** | Legacy rate table; legacy category lookup; legacy 120-day reserve policy; zero V1 bonuses. |
| **B: In-Flight Activation** | `sale_date < V1_EFFECTIVE_AT`<br>`activation_date >= V1_EFFECTIVE_AT`<br>`validation_date >= V1_EFFECTIVE_AT` | **LEGACY** (Grandfathered) | **Treated strictly as LEGACY.** Commission paid based on the rate active at `sale_date`. Does NOT enter the V1 25/50 pool. Does NOT generate V1 leadership. |
| **C: Late Validation** | `sale_date < V1_EFFECTIVE_AT`<br>`activation_date < V1_EFFECTIVE_AT`<br>`validation_date >= V1_EFFECTIVE_AT` | **LEGACY** (Grandfathered) | **Treated strictly as LEGACY.** Governed by legacy compensation terms. Cannot be injected into V1 monthly closed periods. |
| **D: Pure V1** | `sale_date >= V1_EFFECTIVE_AT`<br>`activation_date >= V1_EFFECTIVE_AT`<br>`validation_date >= V1_EFFECTIVE_AT` | **IZZY-COMM-V1** | V1 exact product rate; enters 25/50 pool; generates $5 leadership if eligible; 3-month/100% reversal policy. |

### 3.4 Justification for `sale_date` as the Boundary Anchor

1. **Commercial Contract Integrity:** The commercial commitment between IZZY, the agent, and the customer occurs at `sale_date`. The agent sold the product under the understanding of the commission active on that day.
2. **Preventing Gaming and Distortion:** If `validation_date` were used as the boundary, agents could intentionally delay submitting or validating pre-boundary sales to artificially inflate their V1 25/50 production bonus pool in the new month.
3. **Auditing Feasibility:** `sale_date` is an immutable historical fact recorded at initial customer order placement.

---

## 4. Economic Snapshot Anchor within V1

Once a connection is classified as `IZZY-COMM-V1`, when is its economic snapshot created and frozen?

### 4.1 Evaluation of Snapshot Anchors

| Candidate Anchor | Pros | Cons | Recommendation |
|---|---|---|---|
| **At `sale_date`** | Earliest timestamp; captures immediate intent. | Connection may never be installed; cancellations are frequent; 25/50 pool cannot be finalized until validation. | Not viable for pool economics. |
| **At `activation_date`** | Physical installation is complete. | Carrier billing confirmation and satisfaction may lag; disputes may still cancel connection. | Incomplete verification. |
| **At `validation_date`** (Recommended) | Connection is economically verified by carrier; exact date when production becomes payable; matches V1 rules for 25/50 ordering. | Lags `sale_date` by installation lead time. | **RECOMMENDED DESIGN** |

### 4.2 Recommended Snapshot Anchor Rule

1. When a connection reaches `validation_date`, the V1 engine determines the agent's effective rank and hierarchy as of that exact timestamp.
2. The snapshot locks:
   - Seller effective rank at `validation_date`.
   - Supervisor and Sponsor effective at `validation_date`.
   - Active `commission_table_version` effective for that connection's `sale_date`.
   - 25/50 pool ordinal based on `validation_date` ordering within the commercial period.
3. **Owner Decision D-04 — APPROVED 2026-10-06:** Moisés Caicedo confirmed `validation_date` as the economic snapshot anchor. The alternative (`activation_date`) was not selected. Rank, recipient and hierarchy applicable to a connection are frozen at validation, except for a documented administrative correction; there is no historical recalculation due to later promotions.

---

## 5. Structural Implementation Contract

In the database schema, every order entity (`izzy_orders`) and snapshot entity receives an immutable discriminator:

```sql
-- CONCEPTUAL COLUMN CONTRACT
ALTER TABLE izzy_orders 
ADD COLUMN program_code VARCHAR(20) NOT NULL DEFAULT 'LEGACY' 
CHECK (program_code IN ('LEGACY', 'IZZY-COMM-V1'));
```

- When an order is ingested:
  - If `sale_date < V1_EFFECTIVE_AT` $\implies$ `program_code = 'LEGACY'`.
  - If `sale_date >= V1_EFFECTIVE_AT` $\implies$ `program_code = 'IZZY-COMM-V1'`.
- The V1 Engine selects **only** rows where `program_code = 'IZZY-COMM-V1'`.

---

## 6. Summary of Required Owner Decisions

1. **Approval of exact `V1_EFFECTIVE_AT` timestamp** (e.g., `2026-11-01 07:00:00 UTC`).
2. **Confirmation of `sale_date`** as the sole boundary discriminator for grandfathering.
3. **Confirmation of `validation_date`** as the V1 economic snapshot anchor — APPROVED 2026-10-06 (D-04).
