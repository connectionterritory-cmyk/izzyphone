# 10 — Test Contract and Deterministic Verification Suite

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-10`  
**Phase:** Quality Assurance & Acceptance Test Contract  
**Status:** PROPOSED — PENDING OWNER DECISION  
**Target Authority:** Moisés Caicedo  

---

## 1. Overview and Verification Mandate

Before any code deployment to production, the V1 calculation engine, ledger, and security models must execute and pass the following deterministic test contract. Every test case defines explicit inputs, expected outputs, and mathematical invariants.

---

## 2. Test Suite 1: 25/50 Production Bonus Tranches & Ordinal Boundaries

**Setup:** Supervisor $S$ has a production pool consisting of personal sales and direct Associate downline sales for product `SPEC-500M` (Spectrum 500 Mbps: Base Associate = $90, Tier 1 = +$10, Tier 2 = +$20).

| Test ID | Connection Target | Input Conditions | Expected Ordinal ($k$) | Expected Tier | Expected Production Bonus | Mathematical Invariant |
|---|---|---|:---:|:---:|:---:|---|
| **TC-1.1** | `conn_01` | First validated connection in month | 1 | 0 | **$0.00** | Tranche 0: $k \in [1, 24] \implies \$0.00$ |
| **TC-1.2** | `conn_24` | 24th validated connection in month | 24 | 0 | **$0.00** | Boundary check: $k = 24 \implies \$0.00$ |
| **TC-1.3** | `conn_25` | 25th validated connection in month | 25 | 1 | **+$10.00** | Boundary check: $k = 25 \implies \text{Tier 1}$ |
| **TC-1.4** | `conn_49` | 49th validated connection in month | 49 | 1 | **+$10.00** | Boundary check: $k = 49 \implies \text{Tier 1}$ |
| **TC-1.5** | `conn_50` | 50th validated connection in month | 50 | 2 | **+$20.00** | Boundary check: $k = 50 \implies \text{Tier 2}$ |
| **TC-1.6** | `conn_51` | 51st validated connection in month | 51 | 2 | **+$20.00** | Tranche 2: $k \ge 50 \implies \text{Tier 2}$ |
| **TC-1.7** | Non-Retroactivity | Inspect `conn_01` after `conn_50` validates | 1 | 0 | **$0.00** | **INVARIANT:** `conn_01` bonus remains $0.00 permanently. |

---

## 3. Test Suite 2: Mid-Month Rank Ascension & Breakaway Dynamics

### TC-2.1: Mid-Month Agent Ascension (Training $\to$ Associate)
- **Setup:** Agent $A$ is promoted from `training` to `associate` on `2026-11-15 12:00:00 PT`. Product: `SPEC-500M`.
- **Validation Event 1:** Connection validated on `2026-11-14 10:00:00 PT` ($< T_{\text{promotion}}$).  
  $\implies$ Evaluated as `training`. Base Commission = **$70.00**.
- **Validation Event 2:** Connection validated on `2026-11-16 14:00:00 PT` ($\ge T_{\text{promotion}}$).  
  $\implies$ Evaluated as `associate`. Base Commission = **$90.00**.
- **Invariant:** Prior connection snapshot is **not updated** when promotion occurs.

### TC-2.2: Mid-Month Ascension to Supervisor (Agent $\to$ Supervisor)
- **Setup:** Agent $B$ under Supervisor $S$ is promoted to `supervisor` on `2026-11-20 00:00:00 PT`.
- **Connection 1 (Validated Nov 18):** $B$ was an Associate. Enters Supervisor $S$'s 25/50 production pool. $S$ receives pool credit.
- **Connection 2 (Validated Nov 22):** $B$ is now a Supervisor. Enters $B$'s own new personal 25/50 pool. **Excluded from $S$'s 25/50 pool.**
- **Invariant:** A single user cannot produce volume for two different supervisors' pools at the same point in time.

### TC-2.3: Breakaway Base Dynamics (Supervisor Developing a New Supervisor)
- **Setup:** Supervisor $B$ is promoted under Supervisor $A$. $B$ has downline agents $D_1$ and $D_2$.
- **Action:** $D_1$ validates a connection post-promotion.
- **Result:** Connection enters $B$'s 25/50 production pool. Connection is **strictly excluded** from $A$'s 25/50 pool. $A$ earns $5.00 leadership bonus if internet.

---

## 4. Test Suite 3: Leadership Depth & Product Eligibility

### TC-3.1: Single-Depth Leadership Traversal (Hierarchy A $\to$ B $\to$ C)
- **Setup:** Supervisor $A$ oversees Supervisor $B$, who oversees Supervisor $C$.
- **Event:** $C$ validates an eligible internet connection (`SPEC-1G`).
- **Outcome:**
  - $C$ receives Base Commission ($135) and personal pool credit.
  - $B$ (immediate Supervisor) receives **$5.00 Leadership Bonus**.
  - $A$ (upline at depth 2) receives **$0.00 Leadership Bonus**.
- **Invariant:** Leadership traversal terminates strictly at depth = 1. No multi-level leadership.

### TC-3.2 to TC-3.5: Product Eligibility Matrix for Leadership Bonus

| Test ID | Product Code | Product Description | Service Type | Leadership Eligible | Expected Leadership Bonus |
|---|---|---|:---:|:---:|:---:|
| **TC-3.2** | `SPEC-500M` | Spectrum 500 Mbps | `internet` | **TRUE** | **$5.00** |
| **TC-3.3** | `ATT-CEL-LINE`| AT&T Celular + Línea | `cellular` | **FALSE** | **$0.00** |
| **TC-3.4** | `ATT-BYOD` | AT&T BYOD | `byod` | **FALSE** | **$0.00** |
| **TC-3.5a**| `ATT-AIR` | AT&T Air (Option 1: Broadband) — **APPLICABLE per D-06 (APPROVED 2026-10-06)** | `internet` | **TRUE** | **$5.00** |
| **TC-3.5b**| `ATT-AIR` | AT&T Air (Option 2: Wireless) — **SUPERSEDED by D-06; NOT APPLICABLE (kept for history)** | `cellular` | **FALSE** | **$0.00** |

### TC-3.6: Direct Agents Do Not Generate Leadership (per `06-IZZY-COMM-V1-CLARIFICATIONS.md`)
- **Setup:** Supervisor $A$ has direct non-Supervisor agent $D$.
- **Event:** $D$ validates an eligible internet connection.
- **Outcome:** $A$ receives **$0.00** Leadership Bonus; the connection counts in $A$'s 25/50 pool.

### TC-3.7: Leadership Over a Supervisor and Eligible Base
- **Setup:** $A$ developed Supervisor $B$; $C$ is a non-Supervisor direct agent of $B$.
- **Events:** $B$ validates an eligible internet connection; $C$ validates an eligible internet connection.
- **Outcome:** $A$ receives **$5.00** on each. $B$ receives **$0.00** leadership on $C$'s connection (it counts in $B$'s 25/50 pool).

### TC-3.8: Promotion Under D-04 (`validation_date` Anchor)
- **Setup:** As TC-3.7. $C$ is promoted to Supervisor with effective timestamp $T$.
- **Events:** Connection 1 validated before $T$; Connection 2 validated after $T$ (both eligible internet).
- **Outcome:** Connection 1: $A$ receives $5.00 (snapshot frozen at validation; no recalculation). Connection 2: $B$ receives $5.00 and $A$ receives **$0.00**.

### TC-3.9: Maintenance Does Not Condition Leadership (D-16, Option 1)
- **Setup:** Supervisor $A$ did not meet the 150-connection requirement in the prior quarter. $B$ (Supervisor developed by $A$) validates an eligible internet connection.
- **Outcome:** $A$ receives **$5.00**. No rank loss, grace period, retention or retroactivity is applied (those consequences are undefined and out of scope).

---

## 5. Test Suite 4: Chargebacks, Reversals, and Negative Balance Offsetting

### TC-4.1: Chargeback within 3-Month Window (Before Period Close)
- **Setup:** Connection validated Nov 10. Churns Dec 15 (Day 35 $<$ 90 days).
- **Result:**
  - `reversal_amount_base` = 100% of Base Commission.
  - `reversal_amount_production` = 100% of Production Bonus.
  - `reversal_amount_leadership` = 100% of Leadership Bonus.
  - Reversal entries generated in active accounting period.

### TC-4.2: Chargeback after Period `CLOSED` (Historical Immutability)
- **Setup:** Period `2026-11` is `CLOSED` on Dec 6. Chargeback arrives on Jan 10.
- **Result:**
  - Closed period `2026-11` remains immutable; original ledger rows untouched.
  - `close_state` tagged as `'ADJUSTED'`.
  - Reversal entries posted in current active period (`2027-01`), debiting each recipient's negative balance account.
  - Historical 25/50 ordinals for other agents in Nov 2026 **do not shift**.

### TC-4.3 & TC-4.4: Negative Balance Creation and Subsequent Earnings Offset
- **Setup:** Agent $A$ has an unpaid clawback of -$150.00. Account records `current_negative_balance = $150.00`.
- **Event:** In next cycle, Agent $A$ earns $200.00 gross commission.
- **Offset Pipeline Execution:**
  - Auto-generate `NEGATIVE_BALANCE_OFFSET` entry: -$150.00 (linked to debt source).
  - Net payable to Agent $A$: $200.00 - $150.00 = **$50.00**.
  - Updated `current_negative_balance` = **$0.00**.

### TC-4.5: Inactive Agent Debt Preservation
- **Setup:** Agent $B$ is terminated or deactivated with an outstanding balance of -$85.00.
- **Action:** User profile marked `status = 'inactive'`.
- **Result:** Debt record in `izzy_negative_balance_accounts` remains **-$85.00**. Zero deletion or waiver of debt.

---

## 6. Test Suite 5: Commission Plan Versioning & Historical Immutability

### TC-5.1 & TC-5.2: Version Cutover (V1 $\to$ V2)
- **Setup:** Version `IZZY-COMM-2026-10-V1` is active. Connection 101 sold Nov 10 snaps to V1 rates.
- **Action:** On Dec 1, carrier changes payouts; `IZZY-COMM-2026-12-V2` is published with higher rates. Connection 202 sold Dec 5 snaps to V2 rates.
- **Verification:** Connection 101 snapshot and ledger entries are re-inspected.
- **Result:** Connection 101 retains V1 rates byte-for-byte. Zero rate modification.

---

## 7. Test Suite 6: Period Close & Pacific Time Boundary Tests

| Test ID | Timestamp Input (Pacific Time) | Timezone Boundary Evaluation | Expected Period ID |
|---|---|---|:---:|
| **TC-6.1** | `2026-11-30 23:59:59.999-08` | Final millisecond of November | `2026-11` |
| **TC-6.2** | `2026-12-01 00:00:00.000-08` | First millisecond of December | `2026-12` |
| **TC-6.3** | `2026-12-03 14:00:00.000-08` | Inside Days 1–5 Preliminary Window | `2026-11` is `PRELIMINARY` |
| **TC-6.4** | `2026-12-06 00:00:01.000-08` | Post Day 6 Close Trigger | `2026-11` is `CLOSED` |
