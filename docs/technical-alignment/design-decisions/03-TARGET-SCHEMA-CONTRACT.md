# 03 — Target Schema Contract Specification

**Document Reference:** `IZZY-COMM-2026-10-V1-DD-03`  
**Phase:** Schema Contract & Data Model Architecture  
**Status:** PROPOSED — PENDING OWNER DECISION  
**Target Authority:** Moisés Caicedo  

---

## 1. Context and Problem Statement

The legacy system determines commissions based on coarse service categories (`basic`, `standard`, `premium`) and generic carrier plan tags in `izzy_service_categories` and `izzy_commission_rates`.

The frozen V1 Compensation Plan (`IZZY-COMM-2026-10-V1`) rejects category-based compensation entirely. It requires:
1. **Exact Product Identification:** Every connection must be bound to an explicit product code from a master catalog of exactly ten approved products.
2. **Elimination of Category Pricing:** Categories may be retained exclusively as visual or marketing metadata; they must **never** serve as foreign keys or calculation parameters for economic engines.
3. **Additive Schema Architecture:** No existing production tables (`izzy_orders`, `izzy_portal_users`, etc.) will be dropped or modified destructively. All V1 structures are purely additive.

---

## 2. Master Data Contract: Exactly Ten V1 Products

The table `izzy_v1_products` establishes the canonical product catalog. It enforces exact product codes, carrier branding, service types, and leadership bonus eligibility.

### 2.1 Table Schema Contract: `izzy_v1_products`

```sql
-- CONCEPTUAL SCHEMA CONTRACT (NOT MIGRATION SQL)
CREATE TABLE izzy_v1_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code VARCHAR(30) NOT NULL UNIQUE,
    carrier VARCHAR(30) NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    service_type VARCHAR(20) NOT NULL CHECK (service_type IN ('internet', 'cellular', 'byod')),
    speed_tier VARCHAR(50) NULL,
    leadership_eligible BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'deprecated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
```

### 2.2 Canonical Catalog: The Ten V1 Products

| # | `product_code` | `carrier` | `product_name` | `service_type` | `leadership_eligible` | Notes |
|---|---|---|---|---|:---:|---|
| 1 | `SPEC-500M` | `Spectrum` | Spectrum 500 Mbps | `internet` | **TRUE** | High-speed fixed broadband |
| 2 | `SPEC-1G` | `Spectrum` | Spectrum 1 Gig | `internet` | **TRUE** | Gigabit fixed broadband |
| 3 | `ATT-FIB-300M` | `AT&T` | AT&T Fiber 300 Mbps | `internet` | **TRUE** | Fiber broadband |
| 4 | `ATT-FIB-500M` | `AT&T` | AT&T 500 Mbps | `internet` | **TRUE** | Fiber broadband |
| 5 | `ATT-FIB-1-5G` | `AT&T` | AT&T 1–5 Gig | `internet` | **TRUE** | Multi-Gig fiber broadband |
| 6 | `ATT-AIR` | `AT&T` | AT&T Air | `internet`* | **TRUE** | Fixed Wireless Access (FWA). D-06 APPROVED 2026-10-06 (Option 1): classified as `internet`; eligible for $5 leadership. |
| 7 | `ATT-CEL-LINE` | `AT&T` | AT&T Celular + Línea | `cellular` | **FALSE** | Wireless mobile service. Excluded from leadership. |
| 8 | `ATT-BYOD` | `AT&T` | AT&T BYOD | `byod` | **FALSE** | Bring Your Own Device. Excluded from leadership. |
| 9 | `FRONT-500M` | `Frontier` | Frontier 500 Mbps | `internet` | **TRUE** | Fiber broadband |
| 10 | `FRONT-1G` | `Frontier` | Frontier 1 Gig | `internet` | **TRUE** | Gigabit fiber broadband |

*\*Note on AT&T Air:* RESOLVED — Decision D-06 APPROVED 2026-10-06 (Option 1): AT&T Air is classified as `internet` and `leadership_eligible = TRUE` (see `06-IZZY-COMM-V1-CLARIFICATIONS.md`). The Option 2 (wireless exclusion) alternative was not selected and is retained only as historical context. (The former reference to a "Section 7" is obsolete.)

---

## 3. Commission Versioning Contract

To prevent rate changes from altering historical accounting, plan versions and rate schedules are decoupled into immutable headers and line-item tables.

### 3.1 Version Header Contract: `izzy_commission_plan_versions`

```sql
CREATE TABLE izzy_commission_plan_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_code VARCHAR(50) NOT NULL UNIQUE, -- E.g., 'IZZY-COMM-2026-10-V1'
    version_name VARCHAR(100) NOT NULL,
    effective_from TIMESTAMPTZ NOT NULL,
    effective_to TIMESTAMPTZ NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'frozen', 'retired')),
    approved_by VARCHAR(100) NOT NULL,
    approved_at TIMESTAMPTZ NOT NULL,
    target_gross_margin NUMERIC(5,2) NOT NULL DEFAULT 40.00,
    margin_review_floor NUMERIC(5,2) NOT NULL DEFAULT 35.00,
    margin_paused_floor NUMERIC(5,2) NOT NULL DEFAULT 30.00,
    operating_reserve_target NUMERIC(5,2) NOT NULL DEFAULT 15.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
```

### 3.2 Product Rates Contract: `izzy_commission_product_rates`

```sql
CREATE TABLE izzy_commission_product_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id UUID NOT NULL REFERENCES izzy_commission_plan_versions(id),
    product_id UUID NOT NULL REFERENCES izzy_v1_products(id),
    -- Internal confidential carrier payout (protected by RLS / DTO filters)
    carrier_internal_payout NUMERIC(10,2) NOT NULL,
    -- Agent base rates by rank
    rate_training NUMERIC(10,2) NOT NULL,
    rate_associate NUMERIC(10,2) NOT NULL,
    rate_supervisor NUMERIC(10,2) NOT NULL,
    -- Supervisor 25/50 production bonus increments
    tier_1_bonus NUMERIC(10,2) NOT NULL, -- Tranche 25-49
    tier_2_bonus NUMERIC(10,2) NOT NULL, -- Tranche 50+
    -- Leadership bonus per connection
    leadership_bonus_rate NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_version_product UNIQUE (version_id, product_id)
);
```

---

## 4. Organizational State Contract (Event-Sourced)

User rank and team hierarchy must be tracked with timestamp precision so that retroactive promotions never alter past economic snapshots.

### 4.1 Rank Events: `izzy_v1_rank_events`

```sql
CREATE TABLE izzy_v1_rank_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES izzy_portal_users(id),
    rank_code VARCHAR(20) NOT NULL CHECK (rank_code IN ('training', 'associate', 'supervisor')),
    effective_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NULL,
    reason VARCHAR(50) NOT NULL,
    approved_by UUID NOT NULL REFERENCES izzy_portal_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_v1_rank_lookup ON izzy_v1_rank_events (user_id, effective_at, ended_at);
```

### 4.2 Hierarchy Events: `izzy_v1_hierarchy_events`

```sql
CREATE TABLE izzy_v1_hierarchy_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES izzy_portal_users(id),
    sponsor_id UUID NULL REFERENCES izzy_portal_users(id),
    supervisor_id UUID NULL REFERENCES izzy_portal_users(id),
    effective_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_v1_hierarchy_lookup ON izzy_v1_hierarchy_events (user_id, effective_at, ended_at);
```

---

## 5. Operational Accounting Schema Contract

### 5.1 Commercial Periods: `izzy_compensation_periods`

```sql
CREATE TABLE izzy_compensation_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id VARCHAR(7) NOT NULL UNIQUE, -- E.g., '2026-11'
    period_start_pt TIMESTAMPTZ NOT NULL, -- 00:00:00 Pacific Time
    period_end_pt TIMESTAMPTZ NOT NULL,   -- 23:59:59.999 Pacific Time
    period_start_utc TIMESTAMPTZ NOT NULL,
    period_end_utc TIMESTAMPTZ NOT NULL,
    close_state VARCHAR(20) NOT NULL DEFAULT 'OPEN' 
        CHECK (close_state IN ('OPEN', 'PRELIMINARY', 'CLOSED', 'ADJUSTED')),
    closed_at TIMESTAMPTZ NULL,
    closed_by UUID NULL REFERENCES izzy_portal_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
```

### 5.2 Immutable Connection Snapshot: `izzy_connection_compensation_snapshots`

```sql
CREATE TABLE izzy_connection_compensation_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES izzy_orders(id) UNIQUE,
    program_code VARCHAR(20) NOT NULL CHECK (program_code IN ('LEGACY', 'IZZY-COMM-V1')),
    version_id UUID NOT NULL REFERENCES izzy_commission_plan_versions(id),
    product_id UUID NOT NULL REFERENCES izzy_v1_products(id),
    period_id VARCHAR(7) NOT NULL REFERENCES izzy_compensation_periods(period_id),
    
    -- Economic Parties Frozen State
    seller_id UUID NOT NULL REFERENCES izzy_portal_users(id),
    seller_rank VARCHAR(20) NOT NULL CHECK (seller_rank IN ('training', 'associate', 'supervisor')),
    sponsor_id UUID NULL REFERENCES izzy_portal_users(id),
    supervisor_id UUID NULL REFERENCES izzy_portal_users(id),
    leadership_recipient_id UUID NULL REFERENCES izzy_portal_users(id),
    
    -- Critical Timestamps Frozen State
    sale_date TIMESTAMPTZ NOT NULL,
    activation_date TIMESTAMPTZ NOT NULL,
    validation_date TIMESTAMPTZ NOT NULL,
    snapshot_frozen_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    rank_effective_at TIMESTAMPTZ NOT NULL,
    hierarchy_effective_at TIMESTAMPTZ NOT NULL,

    -- Production Pool Facts
    pool_supervisor_id UUID NULL REFERENCES izzy_portal_users(id),
    production_ordinal INTEGER NULL, -- 1-indexed rank within supervisor's monthly pool
    production_tier INTEGER NOT NULL DEFAULT 0 CHECK (production_tier IN (0, 1, 2)),

    -- Materialized Compensation Amounts
    base_commission_amount NUMERIC(10,2) NOT NULL,
    production_bonus_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    leadership_bonus_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    total_commission_amount NUMERIC(10,2) GENERATED ALWAYS AS (
        base_commission_amount + production_bonus_amount + leadership_bonus_amount
    ) STORED,

    -- Chargeback State
    is_chargeback BOOLEAN NOT NULL DEFAULT FALSE,
    chargeback_at TIMESTAMPTZ NULL,
    chargeback_reason VARCHAR(100) NULL,
    reversal_amount_base NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    reversal_amount_production NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    reversal_amount_leadership NUMERIC(10,2) NOT NULL DEFAULT 0.00,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_snapshot_period_seller ON izzy_connection_compensation_snapshots (period_id, seller_id);
CREATE INDEX idx_snapshot_supervisor_pool ON izzy_connection_compensation_snapshots (period_id, pool_supervisor_id, production_ordinal);
```

### 5.3 Compensation Ledger: `izzy_compensation_ledger_entries`

```sql
CREATE TABLE izzy_compensation_ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id VARCHAR(7) NOT NULL REFERENCES izzy_compensation_periods(period_id),
    recipient_id UUID NOT NULL REFERENCES izzy_portal_users(id),
    connection_id UUID NULL REFERENCES izzy_orders(id),
    snapshot_id UUID NULL REFERENCES izzy_connection_compensation_snapshots(id),
    component_type VARCHAR(30) NOT NULL CHECK (component_type IN (
        'BASE_COMMISSION',
        'PRODUCTION_BONUS',
        'LEADERSHIP_BONUS',
        'REVERSAL',
        'ADJUSTMENT',
        'NEGATIVE_BALANCE_OFFSET'
    )),
    amount NUMERIC(10,2) NOT NULL, -- Signed: positive for earnings, negative for debits/offsets
    source_entry_id UUID NULL REFERENCES izzy_compensation_ledger_entries(id),
    version_id UUID NOT NULL REFERENCES izzy_commission_plan_versions(id),
    audit_actor_id UUID NULL REFERENCES izzy_portal_users(id),
    notes TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_ledger_recipient_period ON izzy_compensation_ledger_entries (recipient_id, period_id);
CREATE INDEX idx_ledger_source ON izzy_compensation_ledger_entries (source_entry_id);
```

### 5.4 Negative Balance Projections: `izzy_negative_balance_accounts`

```sql
CREATE TABLE izzy_negative_balance_accounts (
    user_id UUID PRIMARY KEY REFERENCES izzy_portal_users(id),
    current_negative_balance NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (current_negative_balance >= 0.00),
    total_reversals_accumulated NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    total_offsets_applied NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
```

---

## 6. Schema Integrity and Migration Rules

1. **No Drops:** Existing tables `izzy_orders`, `izzy_commission_rates`, and `izzy_director_bonus_rates` remain active.
2. **Order Foreign Key:** `izzy_orders` receives an optional `v1_product_id` foreign key and `program_code` column.
3. **Immutability Triggers:** In the implementation phase, PostgreSQL triggers will prevent `UPDATE` and `DELETE` operations on `izzy_compensation_ledger_entries` and `izzy_connection_compensation_snapshots` when the linked period is `CLOSED`.
