# 06 — Period Close and Calendar Model Specification

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-06`  
**Phase:** Period Lifecycle & Financial Close Architecture  
**Status:** PROPOSED — PENDING OWNER DECISION  
**Target Authority:** Moisés Caicedo  

---

## 1. Context and Problem Statement

In the legacy platform, commission calculations are performed ad-hoc upon order status changes, with no concept of accounting cutoff dates, monthly closes, or financial immutability.

Without a formal period close model:
1. Past months can shift whenever historical orders are updated or re-validated.
2. Supervisor 25/50 production tiers cannot be finalized, because new retroactive orders could shift connections from tier 0 into tier 1 or tier 2 weeks later.
3. Financial reconciliation is impossible because payment amounts change continuously.

---

## 2. Calendar and Timezone Standard

To eliminate timezone discrepancies between field sales in California and cloud databases in UTC:
- **Commercial Timezone:** **`America/Los_Angeles`** (Pacific Time). All business rules, monthly boundaries, cutoff dates, and operational reports operate strictly on Pacific Time.
- **Storage Standard:** **`UTC`** (Coordinated Universal Time). All database timestamps (`TIMESTAMPTZ`) are stored normalized to UTC.
- **Monthly Cadence:** The commercial period begins at `00:00:00.000` Pacific Time on Day 1 of the calendar month and ends at `23:59:59.999` Pacific Time on the final day of that calendar month.

```
Example for Period '2026-11':
- Pacific Window:  2026-11-01 00:00:00-07 (PDT)  to  2026-11-30 23:59:59.999-08 (PST)
- UTC Storage:     2026-11-01 07:00:00+00  to  2026-12-01 07:59:59.999+00
- Note: DST ends at 02:00 local on 2026-11-01, so midnight that day is still PDT (UTC-7).
  The November 2026 period is 721 hours (2026-11-01 07:00:00 UTC to 2026-12-01 08:00:00 UTC, exclusive).
  Corrected 2026-10-07 per owner confirmation (earlier text showed -08 / 08:00 UTC, which was wrong).
```

---

## 3. Period Lifecycle State Machine

Each accounting cycle moves through four deterministic states in `izzy_compensation_periods`:

```
+-------------+         Day 1 (00:00 PT)         +-------------------+
|    OPEN     |  =============================>  |    PRELIMINARY    |
| (Days 1-End)|                                  |    (Days 1-5)     |
+-------------+                                  +---------+---------+
                                                           |
                                                           | Day 6 (00:00 PT)
                                                           | Automated Close Job
                                                           v
+--------------+     Post-Close Chargeback       +-------------------+
|   ADJUSTED   |  <----------------------------  |      CLOSED       |
|  (Audit Tag) |       or Dispute Entry          |   (IMMUTABLE)     |
+--------------+                                 +-------------------+
```

### 3.1 `OPEN` State
- **Active Window:** Day 1 through the final calendar day of the month (until 23:59:59 PT).
- **Behavior:**
  - Sales, installations, and carrier validations are ingested continuously.
  - The calculation engine generates provisional snapshot projections.
  - 25/50 production ordinals and tiers are calculated provisionally to provide real-time dashboard feedback to Supervisors.
  - No payable payouts are finalized.

### 3.2 `PRELIMINARY` State
- **Active Window:** Days 1 through 5 of the following calendar month (e.g., Nov 1–5 for the Oct period).
- **Behavior:**
  - New connections for the closed month are locked (only sales with `sale_date` and `validation_date` inside the period are accepted).
  - Reconciliation window: carrier activation reports are audited, missing installation dates are resolved, and disputes are addressed.
  - Final rank review: all rank promotions effective within the period are verified and locked.

### 3.3 `CLOSED` State
- **Trigger:** Automated scheduled cron job on **Day 6 at 00:00:00 Pacific Time**.
- **Execution Workflow:**
  1. Freeze all connection snapshots in `izzy_connection_compensation_snapshots`.
  2. Finalize deterministic ordering (`ORDER BY validation_date ASC, connection_id ASC`).
  3. Lock 25/50 ordinals and tiers permanently.
  4. Write all final `BASE_COMMISSION`, `PRODUCTION_BONUS`, and `LEADERSHIP_BONUS` entries into `izzy_compensation_ledger_entries`.
  5. Apply automated offsets against any outstanding negative balances.
  6. Transition `close_state` to `'CLOSED'` and stamp `closed_at`.
- **Immutability Guarantee:** Once `CLOSED`, the financial data for this period is permanently read-only. Database triggers prevent any direct inserts, updates, or deletes referencing this `period_id`.

### 3.4 `ADJUSTED` State
- **Behavior:** If a clawback (chargeback) or authorized adjustment occurs in subsequent months affecting a connection from this period:
  - The historical closed period record receives a secondary status tag (`close_state = 'ADJUSTED'`) for reporting transparency.
  - **Zero modifications are made to historical entries.**
  - The financial adjustment is posted as a `REVERSAL` or `ADJUSTMENT` in the **CURRENT open period**, referencing the original snapshot and ledger entry IDs.

---

## 4. Handling Post-Close Chargebacks and Invariants

When a connection is clawed back 60 days after its period was `CLOSED`:
1. **No Re-opening of Closed Periods:** The closed period remains intact; past bank statements and payout receipts match the ledger 100%.
2. **No Re-tiering of Other Connections:** The churned connection does **NOT** cause other connections in the historical 25/50 pool to shift positions (e.g., connection 25 does not fall back to 24). The historical tier assignment was an earned milestone at close.
3. **Targeted 100% Reversal:**
   - 100% of the base commission is clawed back from the seller.
   - 100% of the production bonus earned on that specific connection is clawed back from the Supervisor.
   - 100% of the $5 leadership bonus is clawed back from the upline Supervisor.
   - Reversal entries are posted in the active billing period, debiting `izzy_negative_balance_accounts`.

---

## 5. Automated Execution Contract

The period close workflow will be executed via a dedicated Supabase Scheduled Function (pg_cron or Edge Function worker) adhering to the following contract:

```sql
-- CONCEPTUAL AUDIT SCHEMA
CREATE TABLE izzy_period_close_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id VARCHAR(7) NOT NULL REFERENCES izzy_compensation_periods(period_id),
    execution_step VARCHAR(50) NOT NULL,
    total_snapshots_finalized INTEGER NOT NULL,
    total_ledger_entries_created INTEGER NOT NULL,
    total_gross_payout NUMERIC(12,2) NOT NULL,
    execution_status VARCHAR(20) NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
```
