# 04 — Commission and Bonus Engine Design Specification

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-04`  
**Phase:** Commission Calculation Engine Architecture  
**Status:** PROPOSED — PENDING OWNER DECISION  
**Target Authority:** Moisés Caicedo  

---

## 1. Executive Summary and Architecture Overview

The V1 Compensation Plan (`IZZY-COMM-2026-10-V1`) defines a multi-tiered, deterministic compensation engine. The engine computes three economic components for every validated connection:
1. **Base Commission:** Payable to the selling agent based on exact product and effective rank.
2. **Supervisor 25/50 Production Bonus:** Payable to the qualified Supervisor on incremental tranches (connections 25–49 and 50+).
3. **Supervisor Leadership Bonus:** Flat $5 payable on eligible internet connections to the direct Supervisor's upline Supervisor (single depth).

```
                      +------------------------------------------+
                      |        Connection Validation Event       |
                      |          (Snapshot Anchor Point)         |
                      +--------------------+---------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |       Snapshot Context Resolver          |
                      |  - Locks seller rank at validation       |
                      |  - Locks supervisor/sponsor at validation|
                      |  - Locks active commission version       |
                      +--------------------+---------------------+
                                           |
             +-----------------------------+-----------------------------+
             |                             |                             |
             v                             v                             v
+--------------------------+  +--------------------------+  +--------------------------+
|  Base Commission Engine  |  |    25/50 Production      |  |    Leadership Engine     |
|                          |  |      Bonus Engine        |  |                          |
| - Exact V1 Product Rate  |  | - Supervisor Pool Eval   |  | - Internet Only          |
| - Rank: Training/        |  | - Exclude Breakaway Bases|  | - Single Depth (1 Level) |
|   Associate/Supervisor   |  | - Sort: Date, ID         |  | - Rate: $5.00            |
| - Result: Base Amount    |  | - Tranche: 1-24/25-49/50+|  | - Recipient: Direct Sup  |
+------------+-------------+  +------------+-------------+  +------------+-------------+
             |                             |                             |
             +-----------------------------+-----------------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |      Materialize Connection Snapshot     |
                      |   izzy_connection_compensation_snapshots |
                      +--------------------+---------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |       Append-Only Ledger Posting         |
                      |   izzy_compensation_ledger_entries       |
                      +------------------------------------------+
```

---

## 2. Component 1: Base Commission Engine

### 2.1 Resolution Logic
When a connection is evaluated at its snapshot anchor timestamp ($T_{\text{anchor}}$):
1. Resolve the connection's exact `product_id` from `izzy_v1_products`.
2. Resolve the seller's effective V1 rank from `izzy_v1_rank_events` active at $T_{\text{anchor}}$:
   - `training` $\implies$ lookup `rate_training` in `izzy_commission_product_rates`.
   - `associate` $\implies$ lookup `rate_associate` in `izzy_commission_product_rates`.
   - `supervisor` $\implies$ lookup `rate_supervisor` in `izzy_commission_product_rates`.
3. If no rank event exists, the transaction fails with audit exception `ERR_NO_V1_RANK`.
4. Output: `base_commission_amount` written to snapshot and posted as `BASE_COMMISSION` in ledger.

### 2.2 Approved Frozen Base Rates Matrix (`IZZY-COMM-2026-10-V1`)

| Product | Entrenamiento | Asociado | Supervisor |
|---|---:|---:|---:|
| Spectrum 500 Mbps | $70 | $90 | $105 |
| Spectrum 1 Gig | $90 | $115 | $135 |
| AT&T Fiber 300 Mbps | $90 | $115 | $135 |
| AT&T 500 Mbps | $100 | $125 | $150 |
| AT&T 1–5 Gig | $140 | $175 | $210 |
| AT&T Air | $50 | $65 | $75 |
| AT&T Celular + Línea | $60 | $75 | $90 |
| AT&T BYOD | $30 | $40 | $45 |
| Frontier 500 Mbps | $100 | $125 | $150 |
| Frontier 1 Gig | $140 | $175 | $210 |

---

## 3. Component 2: 25/50 Supervisor Production Bonus Engine

The 25/50 engine rewards Supervisors who achieve high production volumes within a Pacific-time calendar month.

### 3.1 Mathematical Pool Membership Definition

For a given qualified Supervisor $S$ and commercial monthly period $P$:
Let $\mathcal{C}(P)$ be the set of all validated V1 connections where:
$$\text{validation\_date} \ge P_{\text{start\_utc}} \quad \text{AND} \quad \text{validation\_date} \le P_{\text{end\_utc}}$$

The production pool $\mathcal{M}(S, P)$ for Supervisor $S$ consists of:
1. **Personal Connections:** All connections where $\text{seller\_id} = S$.
2. **Direct Non-Supervisor Base:** All connections where:
   - $\text{supervisor\_id} = S$ (the seller was directly assigned to $S$ in `izzy_v1_hierarchy_events` at $T_{\text{anchor}}$), **AND**
   - $\text{seller\_rank} \in \{\text{'training'}, \text{'associate'}\}$ at $T_{\text{anchor}}$.

#### Strict Pool Exclusions (Breakaway Rule)
The pool $\mathcal{M}(S, P)$ strictly **excludes**:
- Any connection where $\text{seller\_id} = S'$ and $S'$ is another Supervisor ($\text{seller\_rank} = \text{'supervisor'}$).
- Any connection where the seller's direct supervisor is $S'$, even if $S'$ was developed or sponsored by $S$. The base of a promoted Supervisor breaks away from $S$'s 25/50 production pool.

### 3.2 Deterministic Ordering Algorithm

To ensure 100% reproducible ordinal assignment:
1. Query all connections $c \in \mathcal{M}(S, P)$.
2. Apply strict two-column sorting:
   $$\text{ORDER BY } c.\text{validation\_date} \text{ ASC}, \ c.\text{connection\_id} \text{ ASC}$$
3. Assign a 1-indexed sequential ordinal position $k \in \{1, 2, 3, \dots, N\}$.

### 3.3 Tranche Bonus Assignment (Non-Retroactive)

For each connection $c$ at position $k$:
- **Tranche 0 (Connections 1 through 24):**
  $$k \in [1, 24] \implies \text{Tier} = 0, \quad \text{production\_bonus\_amount} = \$0.00$$
- **Tranche 1 (Connections 25 through 49):**
  $$k \in [25, 49] \implies \text{Tier} = 1, \quad \text{production\_bonus\_amount} = \text{tier\_1\_bonus}(c.\text{product\_id})$$
- **Tranche 2 (Connections 50 and above):**
  $$k \ge 50 \implies \text{Tier} = 2, \quad \text{production\_bonus\_amount} = \text{tier\_2\_bonus}(c.\text{product\_id})$$

> **Critical Invariant: Non-Retroactive Application**  
> Connections 1–24 never receive retroactive bonus money when connection 25 is reached. Each connection receives only the bonus rate corresponding to its own ordinal position.

### 3.4 Approved Frozen Production Bonus Schedule (`IZZY-COMM-2026-10-V1`)

| Product | Tranche 1 (Conn 25–49) | Tranche 2 (Conn 50+) |
|---|---:|---:|
| Spectrum 500 Mbps | +$10 | +$20 |
| Spectrum 1 Gig | +$10 | +$20 |
| AT&T Fiber 300 Mbps | +$10 | +$20 |
| AT&T 500 Mbps | +$15 | +$25 |
| AT&T 1–5 Gig | +$20 | +$35 |
| AT&T Air | +$5 | +$15 |
| AT&T Celular + Línea | +$10 | +$15 |
| AT&T BYOD | +$5 | +$10 |
| Frontier 500 Mbps | +$15 | +$25 |
| Frontier 1 Gig | +$20 | +$35 |

### 3.5 Materialization Contract
- The resulting ordinal $k$, tier (0, 1, or 2), and bonus amount are stamped directly onto `izzy_connection_compensation_snapshots`.
- A corresponding `PRODUCTION_BONUS` ledger entry is posted crediting Supervisor $S$.
- Once period $P$ transitions to `CLOSED`, ordinals and bonus amounts are permanently frozen.

---

## 4. Component 3: Leadership Bonus Engine

The leadership bonus rewards Supervisors who mentor other Supervisors.

### 4.1 Eligibility Rules
1. **Rate:** Flat **$5.00** per eligible connection.
2. **Product Requirement:** **Internet Only.** 
   - `service_type = 'internet'` AND `leadership_eligible = TRUE`.
   - **Exclusions:** Cellular (`ATT-CEL-LINE`) and BYOD (`ATT-BYOD`) are strictly **$0.00**.
3. **Single Depth Rule (No Multi-Generational Pay):**
   - If Supervisor $A$ is the immediate supervisor of Supervisor $B$, and $B$ is the immediate supervisor of Supervisor $C$:
     - On connections produced by $B$ or $B$'s eligible non-supervisor base: **$A$ receives $5.00$ leadership bonus.**
     - On connections produced by $C$ or $C$'s base: **$B$ receives $5.00$ leadership bonus.**
     - **$A$ receives $0.00$ on $C$'s production.** Traversal terminates strictly at depth = 1.

### 4.2 Recipient Determination Logic
When evaluating connection $c$:
1. Identify the seller's direct supervisor $S_1$ at $T_{\text{anchor}}$.
2. If the seller is themselves a Supervisor ($S_1 = \text{seller}$), or if the seller belongs to $S_1$'s base:
   - Identify $S_1$'s direct supervisor $S_2$ from `izzy_v1_hierarchy_events` at $T_{\text{anchor}}$.
   - Verify that $S_2$'s rank is `supervisor` at $T_{\text{anchor}}$.
3. If $S_2$ exists and is qualified:
   $$\text{leadership\_recipient\_id} = S_2, \quad \text{leadership\_bonus\_amount} = \$5.00 \ (\text{if internet})$$
4. Otherwise:
   $$\text{leadership\_recipient\_id} = \text{NULL}, \quad \text{leadership\_bonus\_amount} = \$0.00$$

### 4.3 Materialization Contract
- Snapshot fields populated: `leadership_recipient_id` and `leadership_bonus_amount`.
- Ledger entry posted: `LEADERSHIP_BONUS` crediting `leadership_recipient_id`.

---

## 5. Resolved Owner Decision D-06: AT&T Air Leadership Classification — APPROVED (Option 1)

- **The Conflict:** `IZZY-COMM-2026-10-V1-AGENT` states that leadership applies to **internet only** and explicitly excludes cellular and BYOD. However, AT&T Air is a Fixed Wireless Access (FWA) product (cellular-based home internet). The mandate states "No wireless."
- **Option 1 (Recommended by Business Usage):** Classify AT&T Air as `internet` (`leadership_eligible = TRUE`) because it serves as home broadband internet.
- **Option 2 (Strict RF / Wireless Exclusion):** Classify AT&T Air as `wireless` (`leadership_eligible = FALSE`) because it operates over cellular radio spectrum.
- **RESOLUTION (2026-10-06):** Moisés Caicedo APPROVED **Option 1**. AT&T Air is classified as `internet` with `leadership_eligible = TRUE`. Option 2 was not selected; both options above are preserved as historical record only.

### 5.1 Other Owner Decisions Resolved on 2026-10-06 (see `06-IZZY-COMM-V1-CLARIFICATIONS.md`)

- **D-04 (APPROVED):** The economic snapshot anchor is `validation_date`. Rank, recipient and hierarchy applicable to a connection are frozen when the connection is validated, except for a documented administrative correction. There is no historical recalculation due to later promotions ($T_{\text{anchor}}$ = `validation_date`).
- **D-16 (APPROVED, Option 1):** The quarterly 150-connection maintenance requirement does **not**, by itself, condition payment of the $5 Leadership Bonus. The general consequence of not maintaining 150 connections is a separate, still-undefined owner decision; no rank loss, grace period, commission retention or retroactivity may be implemented.
- **Hierarchy semantics (APPROVED):** `supervisor_id` governs the economic structure (pool, eligible base, leadership recipient). `sponsor_id` is recruitment/origin only. No schema change.
- **Eligible base (APPROVED):** defined in `06-IZZY-COMM-V1-CLARIFICATIONS.md`, section 2.

---

## 6. Anti-Double-Counting and Idempotency Invariants

1. **One Base Commission per Connection:** Exactly one `BASE_COMMISSION` entry per `connection_id`.
2. **One Production Bonus per Connection:** Exactly one `PRODUCTION_BONUS` entry per `connection_id`, credited to exactly one Supervisor.
3. **One Leadership Bonus per Connection:** Exactly one `LEADERSHIP_BONUS` entry per `connection_id`, credited to exactly one upline Supervisor at depth 1.
4. **Unique Pool Assignment:** A connection cannot belong to two different supervisors' pools in the same period.
5. **Idempotent Re-runs:** Re-running the calculation pipeline for an open period must yield the exact same snapshot attributes and ledger entries without creating duplicate financial records.
