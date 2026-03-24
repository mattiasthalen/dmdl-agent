# Dimension Patterns: Materializing Dimensions from Focal

This document describes how to generate dimension tables from the Focal framework's typed descriptor tables. Each SCD type is a different materialization strategy applied to the same underlying temporal data.

## Prerequisites

The bootstrap data is provided by the focal agent before this workflow begins. The full metadata model is already cached in context.

All patterns start from the bootstrap result and generate SQL that materializes a flat dimension table.

## How Focal Maps to Dimensions

A Focal **entity** (e.g. `CUSTOMER_FOCAL`) with its **descriptor table** (e.g. `CUSTOMER_DESC`) is a natural dimension candidate. The typed rows in the descriptor table store the dimension's attributes, and the `EFF_TMSTP` / `ROW_ST` columns provide full temporal tracking.

The materialization choice — which SCD type to use — depends on the analytical requirement, not the source data. The same Focal entity can be materialized as Type 0, 1, 2, or any other type. The data supports all of them.

## Default Row: The -1 Key

**Every dimension table must include a default row with version key = -1.** This row represents "unknown" or "unresolved" — it catches fact rows where the point-in-time dimension lookup found no matching version.

Insert this row after populating the dimension:

```sql
INSERT INTO [target_schema].[dim_table] (
  [VERSION_DIM_KEY], [ENTITY_KEY],
  [attribute_columns...],
  EFFECTIVE_FROM, EFFECTIVE_TO, IS_CURRENT
) VALUES (
  -1, 'UNKNOWN',
  [NULL or 'Unknown' for each attribute...],
  '1900-01-01', '9999-12-31', 'Y'
);
```

**Why this matters:** The fact table uses `COALESCE(dim.VERSION_DIM_KEY, -1)` when a dimension version doesn't cover the fact's event date. Without a `-1` row in the dimension, queries that join fact → dimension will drop those fact rows — silently losing data. The `-1` row ensures every fact row always has a dimension to join to.

## Mixing SCD Types Within a Dimension

In practice, a single dimension table often mixes SCD types across its attributes. For example, a Customer dimension might have:

- `CUSTOMER_ID` — **Type 0** (original identifier, never changes)
- `COMPANY_NAME` — **Type 1** (always show current name)
- `CUSTOMER_CITY` — **Type 2** (track address history for geographic analysis)
- `CUSTOMER_COUNTRY` — **Type 2** (track with city)

When mixing types, the **Type 2 attributes drive the grain** — the dimension has one row per entity per change to any Type 2 attribute. Type 0 and Type 1 attributes are resolved independently and joined onto each version row.

The mixed pattern is covered after the individual type patterns below.

---

## Type 0: Retain Original

**What it produces:** One row per entity with the **first recorded value** of each attribute.

**When to use:** Immutable attributes — birth date, original sign-up date, first identifier. The value is set once and never updated in the dimension, even if the source changes.

**Focal mapping:** Pattern 1 (Latest) with sort order reversed to `ASC`.

### SQL Template

```sql
SELECT
  [ENTITY]_KEY,
  MAX(CASE WHEN TYPE_KEY = [key1] THEN [physical_column1] END) AS [attribute_name1],
  MAX(CASE WHEN TYPE_KEY = [key2] THEN [physical_column2] END) AS [attribute_name2]
  -- ... one CASE per atomic context/attribute ...
FROM (
  SELECT
    [ENTITY]_KEY,
    TYPE_KEY,
    ROW_ST,
    RANK() OVER (
      PARTITION BY [ENTITY]_KEY, TYPE_KEY
      ORDER BY EFF_TMSTP ASC, VER_TMSTP ASC
    ) AS NBR,
    STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY IN ([key1], [key2], ...)
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
GROUP BY [ENTITY]_KEY
```

**Key difference from Type 1:** `ORDER BY EFF_TMSTP ASC, VER_TMSTP ASC` — takes the earliest version, not the latest.

### Northwind Example: Employee Original Hire Date

```sql
-- Bootstrap tells us: EMPLOYEE_HIRE_DATE → TYPE_KEY = 1, STA_TMSTP
SELECT
  EMPLOYEE_KEY,
  MAX(CASE WHEN TYPE_KEY = 1 THEN STA_TMSTP END) AS ORIGINAL_HIRE_DATE
FROM (
  SELECT EMPLOYEE_KEY, TYPE_KEY, ROW_ST, STA_TMSTP,
    RANK() OVER (
      PARTITION BY EMPLOYEE_KEY, TYPE_KEY
      ORDER BY EFF_TMSTP ASC, VER_TMSTP ASC
    ) AS NBR
  FROM DAANA_DW.EMPLOYEE_DESC
  WHERE TYPE_KEY = 1
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
GROUP BY EMPLOYEE_KEY
```

---

## Type 1: Overwrite (Current Value)

**What it produces:** One row per entity with the **current value** of each attribute. No history.

**When to use:** When only the current state matters — reporting dashboards, current customer lists, product catalogs. Also used for corrections where historical inaccuracy is not meaningful.

**Focal mapping:** Pattern 1 (Latest) — identical to the ad-hoc query latest pattern.

### SQL Template

```sql
SELECT
  [ENTITY]_KEY,
  MAX(CASE WHEN TYPE_KEY = [key1] THEN [physical_column1] END) AS [attribute_name1],
  MAX(CASE WHEN TYPE_KEY = [key2] THEN [physical_column2] END) AS [attribute_name2]
  -- ... one CASE per atomic context/attribute ...
FROM (
  SELECT
    [ENTITY]_KEY,
    TYPE_KEY,
    ROW_ST,
    RANK() OVER (
      PARTITION BY [ENTITY]_KEY, TYPE_KEY
      ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
    ) AS NBR,
    STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY IN ([key1], [key2], ...)
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
GROUP BY [ENTITY]_KEY
```

### Northwind Example: Current Customer Dimension

```sql
-- From bootstrap: COMPANY_NAME=16/VAL_STR, CONTACT_NAME=29/VAL_STR,
--   CUSTOMER_CITY=3/VAL_STR, CUSTOMER_COUNTRY=41/VAL_STR, PHONE=95/VAL_STR
SELECT
  CUSTOMER_KEY,
  MAX(CASE WHEN TYPE_KEY = 16 THEN VAL_STR END) AS COMPANY_NAME,
  MAX(CASE WHEN TYPE_KEY = 29 THEN VAL_STR END) AS CONTACT_NAME,
  MAX(CASE WHEN TYPE_KEY = 3  THEN VAL_STR END) AS CITY,
  MAX(CASE WHEN TYPE_KEY = 41 THEN VAL_STR END) AS COUNTRY,
  MAX(CASE WHEN TYPE_KEY = 95 THEN VAL_STR END) AS PHONE
FROM (
  SELECT CUSTOMER_KEY, TYPE_KEY, ROW_ST, VAL_STR,
    RANK() OVER (
      PARTITION BY CUSTOMER_KEY, TYPE_KEY
      ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
    ) AS NBR
  FROM DAANA_DW.CUSTOMER_DESC
  WHERE TYPE_KEY IN (16, 29, 3, 41, 95)
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
GROUP BY CUSTOMER_KEY
```

---

## Type 2: Full History (Versioned Rows)

**What it produces:** Multiple rows per entity — one per version. Each row has `effective_from`, `effective_to`, and `is_current` columns, enabling point-in-time joins from fact tables.

**When to use:** When you need to know what the dimension looked like at the time of each fact event. Geographic analysis (where was the customer when they ordered?), organizational tracking (which department was the employee in?), price history.

**Focal mapping:** Pattern 2 (History / Temporal Alignment) wrapped with LEAD window to produce date ranges.

### SQL Template

The template has two stages:
1. **Pattern 2** — temporal alignment to produce one row per entity per change event, with all attributes carried forward
2. **Version columns** — LEAD window to derive `effective_to` and `is_current`

#### Stage 1: Temporal Alignment (Pattern 2 from the query skill's ad-hoc-query-agent.md reference file)

```sql
WITH twine AS (
  SELECT [ENTITY]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM,
         '[ATOMIC_CONTEXT_NAME_1]' AS TIMELINE
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY = [key1]
  UNION ALL
  SELECT [ENTITY]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM,
         '[ATOMIC_CONTEXT_NAME_2]' AS TIMELINE
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY = [key2]
  -- ... one UNION ALL per atomic context ...
),

in_effect AS (
  SELECT
    [ENTITY]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
    STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM,
    MAX(CASE WHEN TIMELINE = '[ATOMIC_CONTEXT_NAME_1]' THEN EFF_TMSTP END)
      OVER (PARTITION BY [ENTITY]_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS EFF_TMSTP_[ATOMIC_CONTEXT_NAME_1],
    MAX(CASE WHEN TIMELINE = '[ATOMIC_CONTEXT_NAME_2]' THEN EFF_TMSTP END)
      OVER (PARTITION BY [ENTITY]_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS EFF_TMSTP_[ATOMIC_CONTEXT_NAME_2],
    -- ... one carry-forward column per atomic context ...
    RANK() OVER (
      PARTITION BY [ENTITY]_KEY, EFF_TMSTP
      ORDER BY EFF_TMSTP DESC
    ) AS RN
  FROM twine
),

filtered_in_effect AS (
  SELECT * FROM in_effect WHERE RN = 1
),

-- Per-attribute CTEs
CTE_[ATOMIC_CONTEXT_NAME_1] AS (
  SELECT [ENTITY]_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [ATTRIBUTE_NAME]
  FROM filtered_in_effect
  WHERE TYPE_KEY = [key1]
),
CTE_[ATOMIC_CONTEXT_NAME_2] AS (
  SELECT [ENTITY]_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [ATTRIBUTE_NAME]
  FROM filtered_in_effect
  WHERE TYPE_KEY = [key2]
),
-- ... one CTE per atomic context ...

-- Pivoted history (one row per entity per change event)
pivoted AS (
  SELECT DISTINCT
    fie.[ENTITY]_KEY,
    fie.EFF_TMSTP,
    cte1.[ATTRIBUTE_NAME_1],
    cte2.[ATTRIBUTE_NAME_2]
    -- ... one column per attribute ...
  FROM filtered_in_effect fie
  LEFT JOIN CTE_[ATOMIC_CONTEXT_NAME_1] cte1
    ON fie.[ENTITY]_KEY = cte1.[ENTITY]_KEY
    AND fie.EFF_TMSTP_[ATOMIC_CONTEXT_NAME_1] = cte1.EFF_TMSTP
  LEFT JOIN CTE_[ATOMIC_CONTEXT_NAME_2] cte2
    ON fie.[ENTITY]_KEY = cte2.[ENTITY]_KEY
    AND fie.EFF_TMSTP_[ATOMIC_CONTEXT_NAME_2] = cte2.EFF_TMSTP
  -- ... one LEFT JOIN per atomic context ...
)
```

#### Stage 2: Version Columns

```sql
SELECT
  ROW_NUMBER() OVER (ORDER BY [ENTITY]_KEY, EFF_TMSTP) AS DIM_SURROGATE_KEY,
  [ENTITY]_KEY,
  [ATTRIBUTE_NAME_1],
  [ATTRIBUTE_NAME_2],
  -- ... all attributes ...
  EFF_TMSTP AS EFFECTIVE_FROM,
  COALESCE(
    LEAD(EFF_TMSTP) OVER (
      PARTITION BY [ENTITY]_KEY
      ORDER BY EFF_TMSTP
    ),
    '9999-12-31'::timestamp
  ) AS EFFECTIVE_TO,
  CASE
    WHEN LEAD(EFF_TMSTP) OVER (
      PARTITION BY [ENTITY]_KEY
      ORDER BY EFF_TMSTP
    ) IS NULL THEN 'Y'
    ELSE 'N'
  END AS IS_CURRENT
FROM pivoted
```

**Output columns:**

| Column | Description |
|--------|-------------|
| `DIM_SURROGATE_KEY` | Unique row ID for the dimension version (fact tables reference this) |
| `[ENTITY]_KEY` | Natural/business key |
| `[ATTRIBUTE_NAME_*]` | Dimension attributes, carried forward to each version |
| `EFFECTIVE_FROM` | When this version became active |
| `EFFECTIVE_TO` | When the next version replaced it (`9999-12-31` for current) |
| `IS_CURRENT` | `'Y'` for the active version, `'N'` for historical |

### Northwind Example: Customer Dimension Type 2

```sql
WITH twine AS (
  SELECT CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST, VAL_STR,
         'COMPANY_NAME' AS TIMELINE
  FROM DAANA_DW.CUSTOMER_DESC WHERE TYPE_KEY = 16
  UNION ALL
  SELECT CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST, VAL_STR,
         'CONTACT_NAME' AS TIMELINE
  FROM DAANA_DW.CUSTOMER_DESC WHERE TYPE_KEY = 29
  UNION ALL
  SELECT CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST, VAL_STR,
         'CITY' AS TIMELINE
  FROM DAANA_DW.CUSTOMER_DESC WHERE TYPE_KEY = 3
  UNION ALL
  SELECT CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST, VAL_STR,
         'COUNTRY' AS TIMELINE
  FROM DAANA_DW.CUSTOMER_DESC WHERE TYPE_KEY = 41
),
in_effect AS (
  SELECT CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST, VAL_STR,
    MAX(CASE WHEN TIMELINE = 'COMPANY_NAME' THEN EFF_TMSTP END)
      OVER (PARTITION BY CUSTOMER_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS EFF_TMSTP_COMPANY_NAME,
    MAX(CASE WHEN TIMELINE = 'CONTACT_NAME' THEN EFF_TMSTP END)
      OVER (PARTITION BY CUSTOMER_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS EFF_TMSTP_CONTACT_NAME,
    MAX(CASE WHEN TIMELINE = 'CITY' THEN EFF_TMSTP END)
      OVER (PARTITION BY CUSTOMER_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS EFF_TMSTP_CITY,
    MAX(CASE WHEN TIMELINE = 'COUNTRY' THEN EFF_TMSTP END)
      OVER (PARTITION BY CUSTOMER_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS EFF_TMSTP_COUNTRY,
    RANK() OVER (PARTITION BY CUSTOMER_KEY, EFF_TMSTP ORDER BY EFF_TMSTP DESC) AS RN
  FROM twine
),
filtered_in_effect AS (SELECT * FROM in_effect WHERE RN = 1),
CTE_COMPANY_NAME AS (
  SELECT CUSTOMER_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN VAL_STR ELSE NULL END AS COMPANY_NAME
  FROM filtered_in_effect WHERE TYPE_KEY = 16
),
CTE_CONTACT_NAME AS (
  SELECT CUSTOMER_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN VAL_STR ELSE NULL END AS CONTACT_NAME
  FROM filtered_in_effect WHERE TYPE_KEY = 29
),
CTE_CITY AS (
  SELECT CUSTOMER_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN VAL_STR ELSE NULL END AS CITY
  FROM filtered_in_effect WHERE TYPE_KEY = 3
),
CTE_COUNTRY AS (
  SELECT CUSTOMER_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN VAL_STR ELSE NULL END AS COUNTRY
  FROM filtered_in_effect WHERE TYPE_KEY = 41
),
pivoted AS (
  SELECT DISTINCT
    fie.CUSTOMER_KEY, fie.EFF_TMSTP,
    cn.COMPANY_NAME, ct.CONTACT_NAME, ci.CITY, co.COUNTRY
  FROM filtered_in_effect fie
  LEFT JOIN CTE_COMPANY_NAME cn ON fie.CUSTOMER_KEY = cn.CUSTOMER_KEY AND fie.EFF_TMSTP_COMPANY_NAME = cn.EFF_TMSTP
  LEFT JOIN CTE_CONTACT_NAME ct ON fie.CUSTOMER_KEY = ct.CUSTOMER_KEY AND fie.EFF_TMSTP_CONTACT_NAME = ct.EFF_TMSTP
  LEFT JOIN CTE_CITY ci ON fie.CUSTOMER_KEY = ci.CUSTOMER_KEY AND fie.EFF_TMSTP_CITY = ci.EFF_TMSTP
  LEFT JOIN CTE_COUNTRY co ON fie.CUSTOMER_KEY = co.CUSTOMER_KEY AND fie.EFF_TMSTP_COUNTRY = co.EFF_TMSTP
)
SELECT
  ROW_NUMBER() OVER (ORDER BY CUSTOMER_KEY, EFF_TMSTP) AS DIM_SURROGATE_KEY,
  CUSTOMER_KEY,
  COMPANY_NAME, CONTACT_NAME, CITY, COUNTRY,
  EFF_TMSTP AS EFFECTIVE_FROM,
  COALESCE(LEAD(EFF_TMSTP) OVER (PARTITION BY CUSTOMER_KEY ORDER BY EFF_TMSTP), '9999-12-31'::timestamp) AS EFFECTIVE_TO,
  CASE WHEN LEAD(EFF_TMSTP) OVER (PARTITION BY CUSTOMER_KEY ORDER BY EFF_TMSTP) IS NULL THEN 'Y' ELSE 'N' END AS IS_CURRENT
FROM pivoted
```

---

## Type 3: Current + Previous Value

**What it produces:** One row per entity with the **current value** and the **previous value** of each tracked attribute side by side.

**When to use:** When analysis requires comparing current vs. previous state without full history — e.g. "did the customer move?" or "was the product reclassified?"

**Focal mapping:** Pattern 1 (Latest) for current value, combined with LAG window on the Type 2 output to capture the previous value, then filtered to the current row only.

### SQL Template

Build the Type 2 pivoted output first (see above), then apply LAG and filter:

```sql
-- ... (Type 2 CTEs from above producing 'pivoted') ...

, with_previous AS (
  SELECT
    [ENTITY]_KEY,
    [ATTRIBUTE_NAME_1],
    LAG([ATTRIBUTE_NAME_1]) OVER (
      PARTITION BY [ENTITY]_KEY ORDER BY EFF_TMSTP
    ) AS PREVIOUS_[ATTRIBUTE_NAME_1],
    [ATTRIBUTE_NAME_2],
    LAG([ATTRIBUTE_NAME_2]) OVER (
      PARTITION BY [ENTITY]_KEY ORDER BY EFF_TMSTP
    ) AS PREVIOUS_[ATTRIBUTE_NAME_2],
    -- ... one pair per tracked attribute ...
    EFF_TMSTP,
    ROW_NUMBER() OVER (
      PARTITION BY [ENTITY]_KEY ORDER BY EFF_TMSTP DESC
    ) AS RN
  FROM pivoted
)
SELECT
  [ENTITY]_KEY,
  [ATTRIBUTE_NAME_1],          PREVIOUS_[ATTRIBUTE_NAME_1],
  [ATTRIBUTE_NAME_2],          PREVIOUS_[ATTRIBUTE_NAME_2],
  -- ...
  EFF_TMSTP AS LAST_CHANGE_DATE
FROM with_previous
WHERE RN = 1
```

**Output:** One row per entity with pairs of `current_X` / `previous_X` columns. `PREVIOUS_*` is NULL if the attribute never changed.

---

## Type 4: Separate History Table

**What it produces:** Two tables — a **current dimension** (Type 1) and a **history table** (Type 2) stored separately.

**When to use:** When the dimension is large and most queries only need current state. History queries join to the separate table when needed. Keeps the main dimension lean.

**Focal mapping:** Simply generate both Type 1 and Type 2 outputs from the same entity:

- **Main dimension** → Type 1 pattern (one row per entity, current values)
- **History table** → Type 2 pattern (full versioned history with date ranges)

No new SQL pattern needed — it's a design choice to materialize both outputs into separate tables.

---

## Type 6: Hybrid (Type 2 + Type 3 + Type 1)

**What it produces:** Full Type 2 versioned history, but with **current attribute values added to every row**. Each historical row shows both "what was true at the time" (Type 2 columns) and "what is true now" (Type 1 columns).

**When to use:** When analysts need both perspectives — "where was the customer when they ordered?" AND "where is the customer now?" — without joining back to a separate current-state table.

**Focal mapping:** Type 2 output joined to Type 1 output on the natural key.

### SQL Template

```sql
-- ... (Type 2 query producing 'versioned') ...
-- ... (Type 1 query producing 'current_dim') ...

SELECT
  v.DIM_SURROGATE_KEY,
  v.[ENTITY]_KEY,
  -- Type 2 columns (as-of values)
  v.[ATTRIBUTE_NAME_1],
  v.[ATTRIBUTE_NAME_2],
  -- Type 1 columns (current values on every row)
  c.[ATTRIBUTE_NAME_1] AS CURRENT_[ATTRIBUTE_NAME_1],
  c.[ATTRIBUTE_NAME_2] AS CURRENT_[ATTRIBUTE_NAME_2],
  -- Version columns
  v.EFFECTIVE_FROM,
  v.EFFECTIVE_TO,
  v.IS_CURRENT
FROM versioned v
JOIN current_dim c
  ON v.[ENTITY]_KEY = c.[ENTITY]_KEY
```

**Output:** Every historical row has both the versioned (point-in-time) values and the current values. Analysts can choose which perspective to use in their queries.

---

## Mixed SCD Types Within a Dimension

In practice, different attributes in the same dimension often need different SCD types. The Type 2 attributes drive the grain (one row per change to any Type 2 attribute), while Type 0 and Type 1 attributes are resolved independently and joined onto each version row.

### Pattern

1. **Identify Type 2 attributes** — these go through the temporal alignment pattern (Pattern 2) and produce the versioned rows with `EFFECTIVE_FROM` / `EFFECTIVE_TO`
2. **Identify Type 0 attributes** — resolve using RANK ASC (first value ever)
3. **Identify Type 1 attributes** — resolve using RANK DESC (current value)
4. **Join** — Type 0 and Type 1 results join to the Type 2 output on `[ENTITY]_KEY` only (no timestamp join — same value on every version row)

### SQL Template

```sql
-- Type 2 attributes produce the versioned grain
-- (use full Type 2 pattern from above → produces 'versioned')

-- Type 0 attributes (first value)
, type0_attrs AS (
  SELECT [ENTITY]_KEY,
    MAX(CASE WHEN TYPE_KEY = [key_t0] THEN [physical_column] END) AS [TYPE0_ATTRIBUTE]
  FROM (
    SELECT [ENTITY]_KEY, TYPE_KEY, ROW_ST, [physical_column],
      RANK() OVER (PARTITION BY [ENTITY]_KEY, TYPE_KEY ORDER BY EFF_TMSTP ASC, VER_TMSTP ASC) AS NBR
    FROM [physical_schema].[descriptor_table]
    WHERE TYPE_KEY IN ([key_t0], ...)
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY [ENTITY]_KEY
)

-- Type 1 attributes (current value)
, type1_attrs AS (
  SELECT [ENTITY]_KEY,
    MAX(CASE WHEN TYPE_KEY = [key_t1] THEN [physical_column] END) AS [TYPE1_ATTRIBUTE]
  FROM (
    SELECT [ENTITY]_KEY, TYPE_KEY, ROW_ST, [physical_column],
      RANK() OVER (PARTITION BY [ENTITY]_KEY, TYPE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM [physical_schema].[descriptor_table]
    WHERE TYPE_KEY IN ([key_t1], ...)
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY [ENTITY]_KEY
)

-- Final: join all onto the Type 2 grain
SELECT
  v.DIM_SURROGATE_KEY,
  v.[ENTITY]_KEY,
  t0.[TYPE0_ATTRIBUTE],       -- Same value on every version row
  t1.[TYPE1_ATTRIBUTE],       -- Current value on every version row
  v.[TYPE2_ATTRIBUTE_1],      -- Versioned value (changes per row)
  v.[TYPE2_ATTRIBUTE_2],
  v.EFFECTIVE_FROM,
  v.EFFECTIVE_TO,
  v.IS_CURRENT
FROM versioned v
LEFT JOIN type0_attrs t0 ON v.[ENTITY]_KEY = t0.[ENTITY]_KEY
LEFT JOIN type1_attrs t1 ON v.[ENTITY]_KEY = t1.[ENTITY]_KEY
```

---

## Dimension Design Considerations

### Conformed Dimensions

Every Focal entity is naturally a conformed dimension — the same `CUSTOMER_FOCAL` entity is referenced by multiple relationship tables (`ORDER_CUSTOMER_X`, etc.). Materializing it once and referencing it from multiple fact tables maintains consistency.

### Degenerate Dimensions

Some attributes belong in the fact table, not a separate dimension — typically identifiers at the fact grain like `ORDER_ID` on a line-item fact. In Focal terms, these are attributes on the anchor entity's descriptor table that get included directly in the fact materialization rather than built into a dimension.

### Role-Playing Dimensions

A single dimension referenced multiple times by one fact table in different roles. In Focal, this is modeled as multiple relationship types (Atomic Contexts) in the same or different relationship tables — e.g. an Order might have `ORDER_DATE`, `REQUIRED_DATE`, and `SHIPPED_DATE` all referencing a Date dimension. The dimension is materialized once; the fact table has multiple foreign keys to it.

### Junk Dimensions

Groups of low-cardinality flags combined into one dimension. In Focal, these would be multiple simple atomic contexts (each storing a flag or status) on the same entity. Materialize them together using the Type 1 pattern with all flag TYPE_KEYs included, producing a compact dimension of all flag combinations.

---

## Building From the Bootstrap

For any dimension materialization, the agent follows these steps:

1. **Identify the entity** from the user's request → match to `FOCAL_NAME` in bootstrap
2. **Select the attributes** → match to `ATOMIC_CONTEXT_NAME` / `ATTRIBUTE_NAME`
3. **Classify each attribute's SCD type** — ask the user if not specified:
   - Type 0: "Should this attribute retain its original value?"
   - Type 1: "Should this always show the current value?"
   - Type 2: "Should this track historical changes?"
4. **Resolve physical details** from bootstrap → `ATOM_CONTX_KEY` (TYPE_KEY), `PHYSICAL_COLUMN`
5. **Generate the SQL** using the appropriate template(s) from this document
6. **Wrap as DDL + DML** if the user wants persistent tables:
   ```sql
   CREATE TABLE [target_schema].[dim_table_name] AS
   ( ... materialization query ... );
   ```

The agent should generate all of these dynamically from the bootstrap data — never hardcode TYPE_KEYs or column names.

---

## Delta Load Pattern for Type 2 Dimensions

The materialization patterns above describe *what* data to produce. This section describes *how* to load it incrementally — only processing rows that actually changed, and closing rows that were removed from the source.

### Why Delta Loading

A full rebuild (DROP + CREATE AS) works for initial loads and small dimensions, but fails at scale:
- Re-generates all surrogate keys (breaks fact references)
- Reprocesses unchanged rows (wasteful)
- Loses the ability to track when a row was closed

Delta loading is **idempotent** — running it twice with the same source data produces zero changes.

### DDL Requirements

Every Type 2 dimension table must include two additional columns beyond the standard pattern:

| Column | Type | Purpose |
|---|---|---|
| `DELTA_HASH` | VARCHAR | MD5 hash of the attribute values, computed at load time. Used for change detection without recalculating the target hash. |
| Surrogate key sequence | SEQUENCE | Auto-incrementing key generator. Avoids `ROW_NUMBER()` conflicts when inserting new rows into an existing table. |

```sql
CREATE TABLE [target_schema].[dim_table] (
  [VERSION_DIM_KEY]   BIGINT PRIMARY KEY,
  [ENTITY_KEY]        VARCHAR NOT NULL,
  [attribute columns...],
  EFFECTIVE_FROM      TIMESTAMP NOT NULL,
  EFFECTIVE_TO        TIMESTAMP NOT NULL,
  IS_CURRENT          CHAR(1) NOT NULL,
  DELTA_HASH          VARCHAR              -- ← new
);

CREATE SEQUENCE [target_schema].seq_[dim_table] START WITH 1;

-- Default -1 row (no hash needed)
INSERT INTO [target_schema].[dim_table] VALUES (
  -1, 'UNKNOWN', [NULLs/defaults...],
  '1900-01-01', '9999-12-31', 'Y', NULL
);
```

### Delta Hash Computation

The hash is an MD5 of the concatenated attribute values, with NULL handling:

```sql
MD5(CONCAT(
  COALESCE([attribute_1], ''),
  '|', COALESCE([attribute_2], ''),
  '|', COALESCE([attribute_3], ''),
  -- ... one per attribute ...
)) AS DELTA_HASH
```

**Rules:**
- Use `COALESCE(..., '')` to handle NULLs consistently
- Use a delimiter (`|`) between values to avoid collisions (e.g. `'AB' + 'C'` vs `'A' + 'BC'`)
- Hash only the **data attributes**, not version columns (EFFECTIVE_FROM, EFFECTIVE_TO, IS_CURRENT, surrogate key)
- The hash is computed once at source read time and stored in the dimension — never recalculated on the target side

### Delta Load Steps

The delta load uses seven steps: stage source, compare, insert new, update changed, close deleted, recalculate date ranges, and advance the sequence.

#### Step 1: Stage source with hash

Materialize the full Type 2 output from Focal into a temporary staging table, computing the delta hash for each row:

```sql
CREATE TEMPORARY TABLE stg_[dim]_src AS
-- ... (Type 2 temporal alignment query from the materialization patterns) ...
SELECT
  [ENTITY_KEY],
  EFF_TMSTP,
  [attribute columns...],
  MD5(CONCAT(
    COALESCE([attribute_1], ''), '|',
    COALESCE([attribute_2], ''), '|',
    -- ...
  )) AS SRC_DELTA_HASH
FROM pivoted;
```

#### Step 2: Build delta table (FULL OUTER JOIN)

Compare source against target on `(entity_key, effective_from)`. The stored `DELTA_HASH` in the target means no recalculation needed:

```sql
CREATE TEMPORARY TABLE stg_[dim]_delta AS
SELECT
  SRC.[ENTITY_KEY] AS SRC_ENTITY_KEY,
  SRC.EFF_TMSTP AS SRC_EFF_TMSTP,
  SRC.[attributes...] AS SRC_[attributes...],
  SRC.SRC_DELTA_HASH,
  TGT.[VERSION_DIM_KEY] AS TGT_VERSION_KEY,
  TGT.[ENTITY_KEY] AS TGT_ENTITY_KEY,
  TGT.EFFECTIVE_FROM AS TGT_EFFECTIVE_FROM,
  TGT.DELTA_HASH AS TGT_DELTA_HASH,
  CASE
    WHEN TGT.[ENTITY_KEY] IS NULL THEN 'NEW'
    WHEN SRC.[ENTITY_KEY] IS NULL THEN 'DEL'
    WHEN SRC.SRC_DELTA_HASH = TGT.DELTA_HASH THEN 'NOCHANGE'
    WHEN SRC.SRC_DELTA_HASH IS NULL AND TGT.DELTA_HASH IS NOT NULL THEN 'DEL'
    WHEN SRC.SRC_DELTA_HASH <> TGT.DELTA_HASH THEN 'CHANGE'
    ELSE 'CHANGE'
  END AS DELTAFLAG
FROM stg_[dim]_src SRC
FULL OUTER JOIN (
  SELECT * FROM [target_schema].[dim_table] WHERE [VERSION_DIM_KEY] != -1
) TGT
  ON SRC.[ENTITY_KEY] = TGT.[ENTITY_KEY]
  AND SRC.EFF_TMSTP = TGT.EFFECTIVE_FROM;
```

**DELTAFLAG values:**

| Flag | Meaning | Action |
|---|---|---|
| `NEW` | Source row has no matching target row | INSERT new dimension version |
| `CHANGE` | Both exist but hash differs | UPDATE target row attributes + hash |
| `DEL` | Target row has no matching source row | UPDATE to close (set EFFECTIVE_TO, IS_CURRENT = 'N') |
| `NOCHANGE` | Both exist, hash matches | Skip — no action needed |

#### Step 3: Insert NEW rows

```sql
INSERT INTO [target_schema].[dim_table] (
  [VERSION_DIM_KEY], [ENTITY_KEY],
  [attribute columns...],
  EFFECTIVE_FROM, EFFECTIVE_TO, IS_CURRENT, DELTA_HASH
)
SELECT
  NEXTVAL('[target_schema].seq_[dim_table]'),
  SRC_ENTITY_KEY,
  SRC_[attributes...],
  SRC_EFF_TMSTP,
  '9999-12-31'::timestamp,
  'Y',
  SRC_DELTA_HASH
FROM stg_[dim]_delta
WHERE DELTAFLAG = 'NEW';
```

#### Step 4: Update CHANGE rows

Update the existing dimension row's attributes and hash. The version key and effective_from stay the same — only the data changed:

```sql
UPDATE [target_schema].[dim_table] tgt
SET
  [attribute_1] = d.SRC_[attribute_1],
  [attribute_2] = d.SRC_[attribute_2],
  -- ...
  DELTA_HASH = d.SRC_DELTA_HASH
FROM stg_[dim]_delta d
WHERE d.DELTAFLAG = 'CHANGE'
  AND d.TGT_VERSION_KEY = tgt.[VERSION_DIM_KEY];
```

#### Step 5: Close DEL rows

Set the end date and mark as no longer current:

```sql
UPDATE [target_schema].[dim_table] tgt
SET
  EFFECTIVE_TO = LOCALTIMESTAMP,
  IS_CURRENT = 'N'
FROM stg_[dim]_delta d
WHERE d.DELTAFLAG = 'DEL'
  AND d.TGT_VERSION_KEY = tgt.[VERSION_DIM_KEY];
```

#### Step 6: Recalculate EFFECTIVE_TO and IS_CURRENT

After inserting new rows, the date ranges must be recalculated for affected entities. This uses LEAD to find the next version's EFFECTIVE_FROM:

```sql
UPDATE [target_schema].[dim_table] tgt
SET
  EFFECTIVE_TO = COALESCE(sub.next_eff, '9999-12-31'::timestamp),
  IS_CURRENT = CASE WHEN sub.next_eff IS NULL THEN 'Y' ELSE 'N' END
FROM (
  SELECT
    [VERSION_DIM_KEY],
    LEAD(EFFECTIVE_FROM) OVER (
      PARTITION BY [ENTITY_KEY] ORDER BY EFFECTIVE_FROM
    ) AS next_eff
  FROM [target_schema].[dim_table]
  WHERE [VERSION_DIM_KEY] != -1
) sub
WHERE tgt.[VERSION_DIM_KEY] = sub.[VERSION_DIM_KEY]
  AND tgt.[VERSION_DIM_KEY] != -1;
```

#### Step 7: Advance sequence and cleanup

```sql
SELECT SETVAL('[target_schema].seq_[dim_table]',
  GREATEST(
    (SELECT COALESCE(MAX([VERSION_DIM_KEY]), 0)
     FROM [target_schema].[dim_table]
     WHERE [VERSION_DIM_KEY] > 0),
    1
  ));

DROP TABLE IF EXISTS stg_[dim]_src;
DROP TABLE IF EXISTS stg_[dim]_delta;
```

### Idempotency Guarantee

When the same source data is loaded twice:
1. Step 1 produces the same staging rows with the same hashes
2. Step 2 matches every source row to a target row with the same hash → all NOCHANGE
3. Steps 3–5 process zero rows (no NEW, CHANGE, or DEL)
4. Step 6 recalculates but produces the same EFFECTIVE_TO values
5. Net result: zero changes to the dimension

### First Load vs Subsequent Loads

The delta pattern works for both initial and incremental loads:
- **First load**: Target is empty (only the -1 row). All source rows are flagged as NEW → INSERT.
- **Subsequent loads**: Most rows match → NOCHANGE. Only actual changes produce work.

No separate "initial load" script is needed.

---

## Date Dimension (Role-Playing Calendar Dimension)

The date dimension is unique — it is **not derived from Focal metadata**. It is a utility dimension generated independently and referenced by every fact table. A single date dimension table is reused (role-played) for every date column in a fact: order date, ship date, hire date, etc.

### Why Every Fact Needs a Date Dimension

Without a date dimension, time-based analysis requires inline date functions in every query (extracting month, quarter, year, checking weekends, etc.). The date dimension pre-computes all of this once, enabling:
- Grouping by any time grain (day, week, month, quarter, year) via simple joins
- Filtering by business calendar attributes (weekdays only, specific quarters)
- Consistent time hierarchies across all facts
- Role-playing: the same dimension table serves as "order date", "ship date", "hire date" — each fact foreign key points to the same table

### Date Key Format

The primary key is an **integer in YYYYMMDD format** (e.g. `19960704` for July 4, 1996). This format:
- Is human-readable without joining to the dimension
- Sorts correctly as an integer
- Is universally supported across all platforms
- Can be derived from any date/timestamp value

**Generating the key from a date value** (the fact table does this when loading):

| Concept | Description |
|---|---|
| Input | A date or timestamp value from the fact's event date |
| Output | Integer in YYYYMMDD format |
| Formula | `YEAR × 10000 + MONTH × 100 + DAY` |

Platform-specific implementations:
- **PostgreSQL:** `TO_CHAR(date_value, 'YYYYMMDD')::int`
- **BigQuery:** `CAST(FORMAT_DATE('%Y%m%d', date_value) AS INT64)`
- **Snowflake:** `TO_NUMBER(TO_CHAR(date_value, 'YYYYMMDD'))`
- **SQL Server:** `CONVERT(int, FORMAT(date_value, 'yyyyMMdd'))`
- **Generic:** `EXTRACT(YEAR FROM d) * 10000 + EXTRACT(MONTH FROM d) * 100 + EXTRACT(DAY FROM d)`

### Required Columns

The date dimension should include at minimum these columns. The agent should generate the DDL and population query for the target platform using that platform's date functions.

#### Primary Key

| Column | Type | Description | Derivation |
|---|---|---|---|
| `DATE_KEY` | INTEGER (PK) | YYYYMMDD integer | `YEAR × 10000 + MONTH × 100 + DAY` |
| `FULL_DATE` | DATE | The actual date value | The source date |

#### Day-Level Attributes

| Column | Type | Description | Derivation |
|---|---|---|---|
| `DAY_OF_MONTH` | SMALLINT | Day number within month (1–31) | Extract day from date |
| `DAY_OF_WEEK` | SMALLINT | ISO day of week (1=Monday, 7=Sunday) | Extract ISO day-of-week |
| `DAY_OF_YEAR` | SMALLINT | Day number within year (1–366) | Extract day-of-year |
| `DAY_NAME` | VARCHAR | Full name ("Monday", "Tuesday", ...) | Format date as day name |
| `IS_WEEKEND` | BOOLEAN | True if Saturday or Sunday | ISO day-of-week IN (6, 7) |

#### Week-Level Attributes

| Column | Type | Description | Derivation |
|---|---|---|---|
| `ISO_WEEK` | SMALLINT | ISO week number (1–53) | Extract ISO week |
| `ISO_YEAR` | SMALLINT | ISO year (may differ from calendar year at year boundaries) | Extract ISO year |
| `WEEK_START_DATE` | DATE | Monday of the ISO week | Date minus (ISO day-of-week - 1) |
| `WEEK_END_DATE` | DATE | Sunday of the ISO week | Date plus (7 - ISO day-of-week) |

#### Month-Level Attributes

| Column | Type | Description | Derivation |
|---|---|---|---|
| `MONTH_NUMBER` | SMALLINT | Month number (1–12) | Extract month |
| `MONTH_NAME` | VARCHAR | Full name ("January", "February", ...) | Format date as month name |
| `MONTH_SHORT` | VARCHAR(3) | Abbreviated name ("Jan", "Feb", ...) | Format date as short month |
| `YEAR_MONTH` | VARCHAR(7) | String "YYYY-MM" | Format date |
| `FIRST_DAY_OF_MONTH` | DATE | First day of the month | Truncate to month |
| `LAST_DAY_OF_MONTH` | DATE | Last day of the month | Truncate to month + 1 month - 1 day |

#### Quarter-Level Attributes

| Column | Type | Description | Derivation |
|---|---|---|---|
| `QUARTER_NUMBER` | SMALLINT | Quarter number (1–4) | Extract quarter |
| `YEAR_QUARTER` | VARCHAR(7) | String "YYYY-Q#" (e.g. "1996-Q3") | Concatenate year + "-Q" + quarter |
| `FIRST_DAY_OF_QUARTER` | DATE | First day of the quarter | Truncate to quarter |
| `LAST_DAY_OF_QUARTER` | DATE | Last day of the quarter | Truncate to quarter + 3 months - 1 day |

#### Year-Level Attributes

| Column | Type | Description | Derivation |
|---|---|---|---|
| `YEAR_NUMBER` | SMALLINT | Calendar year | Extract year |
| `FIRST_DAY_OF_YEAR` | DATE | January 1 of the year | Truncate to year |
| `LAST_DAY_OF_YEAR` | DATE | December 31 of the year | Truncate to year + 1 year - 1 day |

### Population Strategy

The date dimension is populated by generating a series of consecutive dates covering the full range needed by the data warehouse, then computing all attributes for each date.

**Steps:**
1. **Determine the date range** — from the earliest possible fact date to a future horizon. A safe default is 10 years before the earliest data to 10 years into the future.
2. **Generate one row per day** — use the platform's date series generator.
3. **Compute all columns** from each generated date using date extraction and formatting functions.

**Platform-specific date series generation:**

| Platform | Method |
|---|---|
| **PostgreSQL** | `GENERATE_SERIES('start'::date, 'end'::date, '1 day'::interval)` |
| **BigQuery** | `UNNEST(GENERATE_DATE_ARRAY('start', 'end', INTERVAL 1 DAY))` |
| **Snowflake** | `GENERATOR(ROWCOUNT => n)` with `DATEADD(DAY, SEQ4(), 'start')` |
| **SQL Server** | Recursive CTE: `DATEADD(DAY, 1, date)` from anchor |
| **Oracle** | `CONNECT BY LEVEL` with `start_date + LEVEL - 1` |
| **Generic fallback** | Recursive CTE incrementing by 1 day |

For platforms without native series generation, a recursive CTE works universally:

```
WITH RECURSIVE date_series AS (
  SELECT CAST('start_date' AS DATE) AS d
  UNION ALL
  SELECT d + 1 DAY FROM date_series WHERE d < 'end_date'
)
SELECT ... FROM date_series
```

### Extending the Date Dimension

The base columns above cover standard calendar analysis. Common extensions:

| Extension | Columns | Use Case |
|---|---|---|
| **Fiscal calendar** | `FISCAL_YEAR`, `FISCAL_QUARTER`, `FISCAL_MONTH` | Organizations with non-January fiscal years. Apply an offset (e.g. +6 months for July fiscal year start) |
| **Holiday flag** | `IS_HOLIDAY`, `HOLIDAY_NAME` | Retail/operations analysis. Requires a separate holiday reference per country/region |
| **Trading day** | `IS_TRADING_DAY`, `TRADING_DAY_NUMBER` | Financial analysis. Excludes weekends and market holidays |
| **Relative periods** | `IS_CURRENT_MONTH`, `IS_PRIOR_YEAR_SAME_MONTH` | Dashboard filtering. Computed dynamically or refreshed periodically |

These are domain-specific — the agent should ask the user whether any are needed before adding them.

### Role-Playing in Fact Tables

A single `dim_date` table is referenced multiple times by one fact table, each reference representing a different date role:

```
fact_order_line:
  ORDER_DATE_KEY    → dim_date (role: when the order was placed)
  SHIPPED_DATE_KEY  → dim_date (role: when the order was shipped)
  REQUIRED_DATE_KEY → dim_date (role: when delivery was required)
```

Each key column in the fact is derived from a different source date using the same YYYYMMDD formula. At query time, the analyst joins to `dim_date` using whichever date role they want to analyze:

```
-- Revenue by ship month
SELECT dd.YEAR_MONTH, SUM(f.REVENUE)
FROM fact_order f
JOIN dim_date dd ON f.SHIPPED_DATE_KEY = dd.DATE_KEY
GROUP BY dd.YEAR_MONTH

-- Same fact, different role: revenue by order month
SELECT dd.YEAR_MONTH, SUM(f.REVENUE)
FROM fact_order f
JOIN dim_date dd ON f.ORDER_DATE_KEY = dd.DATE_KEY
GROUP BY dd.YEAR_MONTH
```

No separate dimension tables needed — one `dim_date` serves all date roles across all facts in the warehouse.
