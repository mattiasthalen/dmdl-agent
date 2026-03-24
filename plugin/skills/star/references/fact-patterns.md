# Fact Patterns: Materializing Fact Tables from Focal

This document describes how to generate fact tables from the Focal framework by combining descriptor tables (for measures) with relationship tables (for dimension keys). Each fact table type serves a different analytical purpose.

## Prerequisites

The bootstrap data is provided by the focal agent before this workflow begins. The full metadata model is already cached in context.

## How Focal Maps to Facts

A Focal **entity** becomes a fact table candidate when it has:
- **At least one date/time attribute** → every fact table must have a time dimension. Without it, there is no "when" and no ability to analyze trends, periods, or temporal comparisons. This is a hard requirement — if the entity has no date attribute, it is not a fact.
- **Numeric attributes** in its descriptor table → these become **measures** (or the fact is factless — dimension keys only)
- **Relationships** to other entities → these become **dimension foreign keys**

The relationship tables (`_X` tables) are the bridge — they link the fact entity to its dimension entities. The bootstrap reveals the full structure: which TYPE_KEY identifies each relationship, and which key columns connect the entities.

## Identifying Facts vs. Dimensions from the Bootstrap

| Bootstrap Signal | Likely Role |
|---|---|
| Entity has mostly numeric attributes (`VAL_NUM`) | Fact candidate |
| Entity has mostly string attributes (`VAL_STR`) | Dimension candidate |
| Entity is the FOCAL01_KEY (driving side) of multiple relationships | Fact candidate |
| Entity is the FOCAL02_KEY (target side) of relationships | Dimension candidate |
| Entity is referenced by many others | Dimension candidate |

In Northwind: `ORDER_LINE_FOCAL` is the natural fact (numeric measures + relationships to ORDER, PRODUCT). `CUSTOMER_FOCAL`, `PRODUCT_FOCAL`, `EMPLOYEE_FOCAL` are dimensions.

## Resolving Dimension Keys

Every fact table needs foreign keys to its dimensions. In Focal, these come from relationship tables. The pattern for resolving dimension keys is the same across all fact types — only the anchor entity's treatment changes.

For **latest** fact tables (transaction, periodic snapshot), use Pattern 1 (RANK DESC) on each relationship:

```sql
-- Resolve one relationship to get a dimension key
, latest_[RELATIONSHIP] AS (
  SELECT [ANCHOR]_KEY, [DIMENSION]_KEY
  FROM (
    SELECT [ANCHOR]_KEY, [DIMENSION]_KEY, ROW_ST,
      RANK() OVER (
        PARTITION BY [ANCHOR]_KEY, [DIMENSION]_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [physical_schema].[relationship_table]
    WHERE TYPE_KEY = [rel_type_key]
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
)
```

For **history** fact tables, use the combined twine approach from Pattern 3 (Multi-Entity History) — the relationship becomes part of the anchor's timeline with carry-forward.

### Multi-Hop Relationships

When the fact needs a dimension key that's two or more hops away (e.g. ORDER_LINE → ORDER → CUSTOMER), resolve each hop independently, then chain:

```sql
-- Hop 1: ORDER_LINE → ORDER
, latest_order_rel AS (
  SELECT ORDER_LINE_KEY, ORDER_KEY FROM ( ... RANK pattern ... ) WHERE NBR = 1 AND ROW_ST = 'Y'
)
-- Hop 2: ORDER → CUSTOMER
, latest_customer_rel AS (
  SELECT ORDER_KEY, CUSTOMER_KEY FROM ( ... RANK pattern ... ) WHERE NBR = 1 AND ROW_ST = 'Y'
)
-- Chain: ORDER_LINE → ORDER → CUSTOMER
... JOIN latest_order_rel lor ON fact.ORDER_LINE_KEY = lor.ORDER_LINE_KEY
    JOIN latest_customer_rel lcr ON lor.ORDER_KEY = lcr.ORDER_KEY ...
```

---

## Fact Type 1: Transaction Fact Table

**What it produces:** One row per business event at the finest grain. Each row has measures and foreign keys to dimensions.

**When to use:** Most common fact type. Needed when analysis requires line-item detail — revenue per order line, quantity per transaction, drill-down to individual events.

**Focal mapping:** Pattern 1 (Latest) on the anchor entity's descriptor table for measures, Pattern 1 on each relationship table for dimension keys.

### Why Latest Pattern for Transactions

Transactions are typically immutable events — an order line doesn't change after it's placed. Using Pattern 1 (RANK DESC) retrieves the current state of each transaction. If a transaction's attributes were corrected after the fact, the latest version is the correct one for the fact table.

### SQL Template

```sql
-- Step 1: Resolve measures from anchor descriptor table
WITH fact_measures AS (
  SELECT
    [ANCHOR]_KEY,
    MAX(CASE WHEN TYPE_KEY = [measure_key1] THEN [physical_column] END) AS [MEASURE_1],
    MAX(CASE WHEN TYPE_KEY = [measure_key2] THEN [physical_column] END) AS [MEASURE_2]
    -- ... one CASE per measure ...
  FROM (
    SELECT [ANCHOR]_KEY, TYPE_KEY, ROW_ST,
      STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM,
      RANK() OVER (
        PARTITION BY [ANCHOR]_KEY, TYPE_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [physical_schema].[anchor_desc_table]
    WHERE TYPE_KEY IN ([measure_key1], [measure_key2], ...)
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY [ANCHOR]_KEY
),

-- Step 2: Resolve each dimension key via relationship tables
latest_rel_[DIM1] AS (
  SELECT [ANCHOR]_KEY, [DIM1]_KEY
  FROM (
    SELECT [ANCHOR]_KEY, [DIM1]_KEY, ROW_ST,
      RANK() OVER (
        PARTITION BY [ANCHOR]_KEY, [DIM1]_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [physical_schema].[relationship_table_1]
    WHERE TYPE_KEY = [rel_type_key_1]
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
),
-- ... one CTE per relationship ...

-- Step 3: Resolve the event timestamp
-- Use descriptor table's EFF_TMSTP as the fact date, or a specific date attribute
fact_date AS (
  SELECT [ANCHOR]_KEY,
    MAX(CASE WHEN TYPE_KEY = [date_key] THEN STA_TMSTP END) AS EVENT_DATE
  FROM (
    SELECT [ANCHOR]_KEY, TYPE_KEY, ROW_ST, STA_TMSTP,
      RANK() OVER (
        PARTITION BY [ANCHOR]_KEY, TYPE_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [physical_schema].[anchor_desc_table]
    WHERE TYPE_KEY = [date_key]
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY [ANCHOR]_KEY
)

-- Step 4: Assemble the fact table
SELECT
  fm.[ANCHOR]_KEY,
  fd.EVENT_DATE,
  r1.[DIM1]_KEY,
  r2.[DIM2]_KEY,
  -- ... dimension keys ...
  fm.[MEASURE_1],
  fm.[MEASURE_2],
  -- ... derived measures ...
  ROUND((fm.[MEASURE_1] * fm.[MEASURE_2])::numeric, 2) AS [DERIVED_MEASURE]
FROM fact_measures fm
JOIN fact_date fd ON fm.[ANCHOR]_KEY = fd.[ANCHOR]_KEY
JOIN latest_rel_[DIM1] r1 ON fm.[ANCHOR]_KEY = r1.[ANCHOR]_KEY
JOIN latest_rel_[DIM2] r2 ON fm.[ANCHOR]_KEY = r2.[ANCHOR]_KEY
-- ... one JOIN per relationship ...
```

### Northwind Example: Order Line Transaction Fact

```sql
-- Bootstrap: ORDER_LINE_DESC
--   UNIT_PRICE: TYPE_KEY=82, VAL_NUM
--   QUANTITY:   TYPE_KEY=15, VAL_NUM
--   DISCOUNT:   TYPE_KEY=21, VAL_NUM
-- ORDER_LINE_ORDER_X:   TYPE_KEY=90 → ORDER_KEY
-- ORDER_LINE_PRODUCT_X: TYPE_KEY=86 → PRODUCT_KEY
-- ORDER_CUSTOMER_X:     TYPE_KEY=70 → CUSTOMER_KEY
-- ORDER_EMPLOYEE_X:     TYPE_KEY=5  → EMPLOYEE_KEY (check bootstrap for current key)

WITH fact_measures AS (
  SELECT
    ORDER_LINE_KEY,
    MAX(CASE WHEN TYPE_KEY = 82 THEN VAL_NUM END) AS UNIT_PRICE,
    MAX(CASE WHEN TYPE_KEY = 15 THEN VAL_NUM END) AS QUANTITY,
    MAX(CASE WHEN TYPE_KEY = 21 THEN VAL_NUM END) AS DISCOUNT
  FROM (
    SELECT ORDER_LINE_KEY, TYPE_KEY, ROW_ST, VAL_NUM,
      RANK() OVER (PARTITION BY ORDER_LINE_KEY, TYPE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_LINE_DESC
    WHERE TYPE_KEY IN (82, 15, 21)
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY ORDER_LINE_KEY
),

-- Dimension key: ORDER_LINE → PRODUCT
rel_product AS (
  SELECT ORDER_LINE_KEY, PRODUCT_KEY FROM (
    SELECT ORDER_LINE_KEY, PRODUCT_KEY, ROW_ST,
      RANK() OVER (PARTITION BY ORDER_LINE_KEY, PRODUCT_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_LINE_PRODUCT_X WHERE TYPE_KEY = 86
  ) A WHERE NBR = 1 AND ROW_ST = 'Y'
),

-- Dimension key: ORDER_LINE → ORDER
rel_order AS (
  SELECT ORDER_LINE_KEY, ORDER_KEY FROM (
    SELECT ORDER_LINE_KEY, ORDER_KEY, ROW_ST,
      RANK() OVER (PARTITION BY ORDER_LINE_KEY, ORDER_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_LINE_ORDER_X WHERE TYPE_KEY = 90
  ) A WHERE NBR = 1 AND ROW_ST = 'Y'
),

-- Dimension key: ORDER → CUSTOMER (multi-hop)
rel_customer AS (
  SELECT ORDER_KEY, CUSTOMER_KEY FROM (
    SELECT ORDER_KEY, CUSTOMER_KEY, ROW_ST,
      RANK() OVER (PARTITION BY ORDER_KEY, CUSTOMER_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_CUSTOMER_X WHERE TYPE_KEY = 70
  ) A WHERE NBR = 1 AND ROW_ST = 'Y'
),

-- Dimension key: ORDER → EMPLOYEE (multi-hop)
rel_employee AS (
  SELECT ORDER_KEY, EMPLOYEE_KEY FROM (
    SELECT ORDER_KEY, EMPLOYEE_KEY, ROW_ST,
      RANK() OVER (PARTITION BY ORDER_KEY, EMPLOYEE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_EMPLOYEE_X WHERE TYPE_KEY = 5
  ) A WHERE NBR = 1 AND ROW_ST = 'Y'
)

SELECT
  fm.ORDER_LINE_KEY,
  fm.UNIT_PRICE,
  fm.QUANTITY,
  fm.DISCOUNT,
  ROUND((fm.UNIT_PRICE * fm.QUANTITY * (1 - fm.DISCOUNT))::numeric, 2) AS REVENUE,
  rp.PRODUCT_KEY,
  ro.ORDER_KEY,
  rc.CUSTOMER_KEY,
  re.EMPLOYEE_KEY
FROM fact_measures fm
JOIN rel_product rp ON fm.ORDER_LINE_KEY = rp.ORDER_LINE_KEY
JOIN rel_order ro ON fm.ORDER_LINE_KEY = ro.ORDER_LINE_KEY
JOIN rel_customer rc ON ro.ORDER_KEY = rc.ORDER_KEY
JOIN rel_employee re ON ro.ORDER_KEY = re.ORDER_KEY
```

### Measures Classification

When building transaction facts, classify each measure:

| Measure | Type | Aggregation |
|---------|------|-------------|
| `QUANTITY` | Additive | SUM across all dimensions |
| `REVENUE` (derived: price * qty * (1-discount)) | Additive | SUM across all dimensions |
| `UNIT_PRICE` | Non-additive | Do not SUM — store for line-level detail |
| `DISCOUNT` | Non-additive | Do not SUM — store as component for derived measures |

**Design rule:** Store the additive components (`UNIT_PRICE`, `QUANTITY`, `DISCOUNT`) and derive the additive measure (`REVENUE`) in the query or as a calculated column. This ensures correct aggregation at any level.

---

## Fact Type 2: Periodic Snapshot Fact Table

**What it produces:** One row per entity (or group) per time period — a summary of activity or state at regular intervals.

**When to use:** When transaction volume is too large for line-level analysis, or when the business question is about periodic state: "monthly revenue by product", "weekly inventory levels", "daily order counts".

**Focal mapping:** Transaction fact (Fact Type 1) aggregated by time period + dimension keys.

### SQL Template

Build the transaction fact first, then aggregate:

```sql
-- ... (Transaction Fact CTEs from above producing the full fact) ...

SELECT
  DATE_TRUNC('[period]', EVENT_DATE) AS PERIOD_START,
  [DIM1]_KEY,
  [DIM2]_KEY,
  -- ... dimension keys to keep in the snapshot ...
  SUM([ADDITIVE_MEASURE_1]) AS TOTAL_[MEASURE_1],
  SUM([ADDITIVE_MEASURE_2]) AS TOTAL_[MEASURE_2],
  COUNT(*) AS TRANSACTION_COUNT,
  -- Derived: non-additive measures calculated from aggregated components
  ROUND((SUM([REVENUE_COMPONENT]) / NULLIF(SUM([QUANTITY_COMPONENT]), 0))::numeric, 2) AS AVG_UNIT_PRICE
FROM transaction_fact
GROUP BY DATE_TRUNC('[period]', EVENT_DATE), [DIM1]_KEY, [DIM2]_KEY
ORDER BY PERIOD_START, [DIM1]_KEY
```

**`[period]` values:** `'day'`, `'week'`, `'month'`, `'quarter'`, `'year'`

### Northwind Example: Monthly Revenue by Product

```sql
-- ... (Order Line Transaction Fact CTEs from above) ...

SELECT
  DATE_TRUNC('month', fm.EFF_TMSTP) AS MONTH,
  rp.PRODUCT_KEY,
  SUM(fm.QUANTITY) AS TOTAL_QUANTITY,
  ROUND(SUM(fm.UNIT_PRICE * fm.QUANTITY * (1 - fm.DISCOUNT))::numeric, 2) AS TOTAL_REVENUE,
  COUNT(*) AS ORDER_LINE_COUNT,
  ROUND((SUM(fm.UNIT_PRICE * fm.QUANTITY * (1 - fm.DISCOUNT)) /
    NULLIF(SUM(fm.QUANTITY), 0))::numeric, 2) AS AVG_REVENUE_PER_UNIT
FROM fact_measures fm
JOIN rel_product rp ON fm.ORDER_LINE_KEY = rp.ORDER_LINE_KEY
GROUP BY DATE_TRUNC('month', fm.EFF_TMSTP), rp.PRODUCT_KEY
ORDER BY MONTH, PRODUCT_KEY
```

### Semi-Additive Measures in Periodic Snapshots

When the snapshot captures a **state** (balance, inventory level) rather than activity, the measures are semi-additive — they can be summed across non-time dimensions but not across time:

```sql
-- Example: End-of-month inventory (semi-additive)
-- SUM across products = total inventory on that date ✓
-- SUM across months = meaningless ✗
-- Use MAX, MIN, or AVG for time-based aggregation
SELECT
  PERIOD_START,
  SUM(ENDING_BALANCE) AS TOTAL_BALANCE,       -- Valid: across entities
  -- For time aggregation, use:
  AVG(ENDING_BALANCE) AS AVG_BALANCE_OVER_TIME -- Valid: across time
  -- NOT: SUM(ENDING_BALANCE) across time periods
```

---

## Fact Type 3: Accumulating Snapshot Fact Table

**What it produces:** One row per process instance with **multiple milestone date columns** tracking progression through a workflow. The row is inserted at the first milestone and updated at each subsequent one.

**When to use:** When the business process has well-defined sequential stages — order fulfillment, claims processing, project delivery. Enables analysis of cycle times and bottleneck identification.

**Focal mapping:** The process entity (e.g. ORDER) has multiple timestamp attributes — each representing a milestone. Use Pattern 1 (Latest) to materialize the current state of each process instance with all milestone dates.

### Identifying Milestones from the Bootstrap

In Focal, milestone dates are stored as `STA_TMSTP` or `END_TMSTP` attributes in the entity's descriptor table. The bootstrap reveals them via their `PHYSICAL_COLUMN`:

| PHYSICAL_COLUMN | Typical Milestone Role |
|---|---|
| `STA_TMSTP` | Process start date (order date, claim submission date) |
| `END_TMSTP` | Process completion dates (ship date, approval date) |

### SQL Template

```sql
-- Resolve all milestone dates + measures from the process entity
WITH process_snapshot AS (
  SELECT
    [PROCESS]_KEY,
    -- Milestone dates
    MAX(CASE WHEN TYPE_KEY = [milestone_key1] THEN STA_TMSTP END) AS [MILESTONE_1_DATE],
    MAX(CASE WHEN TYPE_KEY = [milestone_key2] THEN END_TMSTP END) AS [MILESTONE_2_DATE],
    MAX(CASE WHEN TYPE_KEY = [milestone_key3] THEN END_TMSTP END) AS [MILESTONE_3_DATE],
    -- Measures
    MAX(CASE WHEN TYPE_KEY = [measure_key] THEN VAL_NUM END) AS [MEASURE]
  FROM (
    SELECT [PROCESS]_KEY, TYPE_KEY, ROW_ST,
      STA_TMSTP, END_TMSTP, VAL_NUM,
      RANK() OVER (
        PARTITION BY [PROCESS]_KEY, TYPE_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [physical_schema].[process_desc_table]
    WHERE TYPE_KEY IN ([milestone_key1], [milestone_key2], [milestone_key3], [measure_key])
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY [PROCESS]_KEY
)

-- Add dimension keys and derived cycle-time measures
SELECT
  ps.[PROCESS]_KEY,
  ps.[MILESTONE_1_DATE],
  ps.[MILESTONE_2_DATE],
  ps.[MILESTONE_3_DATE],
  -- Cycle time between milestones (in days)
  EXTRACT(DAY FROM ps.[MILESTONE_2_DATE] - ps.[MILESTONE_1_DATE]) AS DAYS_[STAGE_1]_TO_[STAGE_2],
  EXTRACT(DAY FROM ps.[MILESTONE_3_DATE] - ps.[MILESTONE_2_DATE]) AS DAYS_[STAGE_2]_TO_[STAGE_3],
  EXTRACT(DAY FROM ps.[MILESTONE_3_DATE] - ps.[MILESTONE_1_DATE]) AS DAYS_TOTAL_CYCLE,
  -- Process status
  CASE
    WHEN ps.[MILESTONE_3_DATE] IS NOT NULL THEN 'COMPLETED'
    WHEN ps.[MILESTONE_2_DATE] IS NOT NULL THEN 'IN_PROGRESS'
    ELSE 'PENDING'
  END AS PROCESS_STATUS,
  ps.[MEASURE],
  -- Dimension keys
  r1.[DIM1]_KEY,
  r2.[DIM2]_KEY
FROM process_snapshot ps
JOIN latest_rel_[DIM1] r1 ON ps.[PROCESS]_KEY = r1.[PROCESS]_KEY
JOIN latest_rel_[DIM2] r2 ON ps.[PROCESS]_KEY = r2.[PROCESS]_KEY
```

### Northwind Example: Order Fulfillment Accumulating Snapshot

```sql
-- Bootstrap: ORDER_DESC
--   ORDER_DATE:    TYPE_KEY=3, STA_TMSTP (milestone 1: order placed)
--   REQUIRED_DATE: TYPE_KEY=8, END_TMSTP (milestone 2: delivery required by)
--   SHIPPED_DATE:  TYPE_KEY=14, END_TMSTP (milestone 3: order shipped)
--   FREIGHT:       TYPE_KEY=73, VAL_NUM
--   ORDER_ID:      TYPE_KEY=54, VAL_STR (degenerate dimension)
-- ORDER_CUSTOMER_X: TYPE_KEY=70
-- ORDER_EMPLOYEE_X: TYPE_KEY=5

WITH order_snapshot AS (
  SELECT
    ORDER_KEY,
    MAX(CASE WHEN TYPE_KEY = 54 THEN VAL_STR END) AS ORDER_ID,
    MAX(CASE WHEN TYPE_KEY = 3  THEN STA_TMSTP END) AS ORDER_DATE,
    MAX(CASE WHEN TYPE_KEY = 8  THEN END_TMSTP END) AS REQUIRED_DATE,
    MAX(CASE WHEN TYPE_KEY = 14 THEN END_TMSTP END) AS SHIPPED_DATE,
    MAX(CASE WHEN TYPE_KEY = 73 THEN VAL_NUM END) AS FREIGHT
  FROM (
    SELECT ORDER_KEY, TYPE_KEY, ROW_ST, STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM,
      RANK() OVER (PARTITION BY ORDER_KEY, TYPE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_DESC
    WHERE TYPE_KEY IN (54, 3, 8, 14, 73)
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY ORDER_KEY
),

rel_customer AS (
  SELECT ORDER_KEY, CUSTOMER_KEY FROM (
    SELECT ORDER_KEY, CUSTOMER_KEY, ROW_ST,
      RANK() OVER (PARTITION BY ORDER_KEY, CUSTOMER_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_CUSTOMER_X WHERE TYPE_KEY = 70
  ) A WHERE NBR = 1 AND ROW_ST = 'Y'
),

rel_employee AS (
  SELECT ORDER_KEY, EMPLOYEE_KEY FROM (
    SELECT ORDER_KEY, EMPLOYEE_KEY, ROW_ST,
      RANK() OVER (PARTITION BY ORDER_KEY, EMPLOYEE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM DAANA_DW.ORDER_EMPLOYEE_X WHERE TYPE_KEY = 5
  ) A WHERE NBR = 1 AND ROW_ST = 'Y'
)

SELECT
  os.ORDER_KEY,
  os.ORDER_ID,
  os.ORDER_DATE,
  os.REQUIRED_DATE,
  os.SHIPPED_DATE,
  -- Cycle times
  EXTRACT(DAY FROM os.SHIPPED_DATE - os.ORDER_DATE) AS DAYS_TO_SHIP,
  EXTRACT(DAY FROM os.REQUIRED_DATE - os.ORDER_DATE) AS DAYS_ALLOWED,
  EXTRACT(DAY FROM os.SHIPPED_DATE - os.REQUIRED_DATE) AS DAYS_LATE,
  -- Status
  CASE
    WHEN os.SHIPPED_DATE IS NOT NULL AND os.SHIPPED_DATE <= os.REQUIRED_DATE THEN 'ON_TIME'
    WHEN os.SHIPPED_DATE IS NOT NULL AND os.SHIPPED_DATE > os.REQUIRED_DATE THEN 'LATE'
    WHEN os.SHIPPED_DATE IS NULL THEN 'NOT_SHIPPED'
  END AS FULFILLMENT_STATUS,
  os.FREIGHT,
  rc.CUSTOMER_KEY,
  re.EMPLOYEE_KEY
FROM order_snapshot os
JOIN rel_customer rc ON os.ORDER_KEY = rc.ORDER_KEY
JOIN rel_employee re ON os.ORDER_KEY = re.ORDER_KEY
```

**Analysis enabled:**
- Average days to ship by employee (who's fastest?)
- Late shipment rate by customer (who has the most delays?)
- Fulfillment bottleneck analysis (which stage takes longest?)

---

## Fact Type 4: Factless Fact Table

**What it produces:** Rows recording that an **event occurred** or a **relationship exists**, without any numeric measures. The fact is the combination of dimension keys itself.

**When to use:** Coverage analysis, assignment tracking, event participation. "Which employees cover which territories?" "Which products were NOT sold in a given month?"

**Focal mapping:** A relationship table (`_X` table) directly — the relationship IS the factless fact. The two entity keys are the dimension foreign keys. No descriptor table needed for measures.

### SQL Template

```sql
-- A relationship table IS a factless fact — just resolve it with the RANK pattern
SELECT
  [ENTITY_01]_KEY,
  [ENTITY_02]_KEY,
  EFF_TMSTP AS ASSIGNMENT_DATE
FROM (
  SELECT
    [ENTITY_01]_KEY,
    [ENTITY_02]_KEY,
    EFF_TMSTP,
    ROW_ST,
    RANK() OVER (
      PARTITION BY [ENTITY_01]_KEY, [ENTITY_02]_KEY
      ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
    ) AS NBR
  FROM [physical_schema].[relationship_table]
  WHERE TYPE_KEY = [rel_type_key]
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
```

### Northwind Example: Employee Territory Coverage

```sql
-- Bootstrap: EMPLOYEE_TERRITORY_X, TYPE_KEY=26
--   EMPLOYEE_KEY (FOCAL01_KEY), TERRITORY_KEY (FOCAL02_KEY)

SELECT
  EMPLOYEE_KEY,
  TERRITORY_KEY,
  EFF_TMSTP AS ASSIGNMENT_DATE
FROM (
  SELECT EMPLOYEE_KEY, TERRITORY_KEY, EFF_TMSTP, ROW_ST,
    RANK() OVER (
      PARTITION BY EMPLOYEE_KEY, TERRITORY_KEY
      ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
    ) AS NBR
  FROM DAANA_DW.EMPLOYEE_TERRITORY_X
  WHERE TYPE_KEY = 26
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
```

**Analysis enabled:**
- Territory coverage gaps: which territories have no employees?
- Employee workload: how many territories per employee?
- Coverage analysis with NOT EXISTS: which products were never ordered by a customer?

### Coverage Analysis Pattern (NOT EXISTS)

Factless facts are powerful for finding what **didn't** happen:

```sql
-- Products never ordered by a specific customer
SELECT p.PRODUCT_KEY
FROM dim_product p
WHERE NOT EXISTS (
  SELECT 1 FROM fact_order_line f
  WHERE f.PRODUCT_KEY = p.PRODUCT_KEY
    AND f.CUSTOMER_KEY = '<specific_customer>'
)
```

---

## Transaction Fact with History (Temporal Fact)

When the user needs a fact table that **tracks how measures evolved over time** — not just the current state of each transaction — use Pattern 3 (Multi-Entity History).

This produces a temporal fact where each row represents the state of a transaction at a point in time, with dimension keys resolved via carry-forward and LATERAL joins.

**When to use:** Audit trails, correction tracking, temporal aggregation where the fact values themselves changed over time.

**Focal mapping:** Pattern 3 (Multi-Entity History) — the anchor entity's descriptor and relationship tables are merged into a combined twine, related entity attributes resolved via LATERAL.

The full temporal alignment pattern is documented in the query skill's `ad-hoc-query-agent.md` reference file.

---

## Building From the Bootstrap

For any fact materialization, the agent follows these steps:

1. **Identify the fact entity** — the entity at the transaction grain (e.g. ORDER_LINE)
2. **Identify the event date (mandatory)** — every fact must have at least one date/time dimension. Look for `STA_TMSTP` or `END_TMSTP` attributes in the bootstrap, or use `EFF_TMSTP`. If no date attribute exists on the entity, it cannot be a fact table.
3. **Identify measures** — numeric attributes from the entity's descriptor table (`VAL_NUM` columns in bootstrap)
4. **Identify dimension keys** — relationship tables where the fact entity is the FOCAL01_KEY side
5. **Identify multi-hop dimensions** — follow relationship chains (e.g. ORDER_LINE → ORDER → CUSTOMER)
6. **Choose the fact type:**
   - Transaction → Pattern 1 on measures + relationships
   - Periodic snapshot → Transaction fact aggregated by time period
   - Accumulating snapshot → Pattern 1 with multiple milestone timestamp attributes
   - Factless → Relationship table directly with RANK pattern
7. **Classify measures** — additive, semi-additive, or non-additive
8. **Generate the SQL** using the appropriate template from this document

### Dimension Joins: Always LEFT JOIN, Default to -1

Dimension version joins in the fact must always be **LEFT JOINs**, never INNER JOINs. If a dimension version doesn't exist for the fact's event date (data timing issue, missing dimension data, etc.), the fact row must still be loaded — with `-1` as the dimension key to flag the mismatch:

```sql
COALESCE(dc.CUSTOMER_VERSION_DIM_KEY, -1) AS CUSTOMER_VERSION_DIM_KEY
```

This ensures:
- **All fact rows load** regardless of dimension coverage gaps
- **`-1` flags** are easily queried to find dimension mismatches: `WHERE CUSTOMER_VERSION_DIM_KEY = -1`
- **No silent data loss** — a missing dimension version is visible, not hidden by an INNER JOIN

### Degenerate Dimensions in Facts

Some attributes from the anchor entity belong directly in the fact table rather than in a separate dimension — typically identifiers at the fact grain:

- `ORDER_ID` on an order line fact (degenerate — no separate Order ID dimension needed)
- `ORDER_LINE_KEY` itself (the fact grain identifier)

Include these as `VAL_STR` columns in the fact measures CTE alongside the numeric measures.

### Date Dimension Integration

Every fact table needs at least one date reference. Options:

1. **Use `EFF_TMSTP` directly** — the effective timestamp from the descriptor table
2. **Use a specific date attribute** — e.g. `ORDER_DATE` (`STA_TMSTP` in the bootstrap)
3. **Generate a date key** — `TO_CHAR(EVENT_DATE, 'YYYYMMDD')::integer` for joining to a date dimension

For role-playing date dimensions (order date, ship date, required date), include multiple date columns in the fact — each references the same date dimension in a different role.
