# Query Patterns

Reference for all SQL query construction patterns. The agent reads this file at the start of Phase 3 (Query Loop).

All patterns use placeholders from the bootstrap result:
- `[entity]` — entity name from `focal_name` (e.g., `customer`, `ride`)
- `[descriptor_table]` — from `descriptor_concept_name` (e.g., `customer_desc`)
- `[key1]`, `[key2]` — from `atom_contx_key`
- `[physical_column]` — from `table_pattern_column_name` (e.g., `val_str`, `val_num`)
- `[attribute_name]` — from `attribute_name` (e.g., `customer_email`)
- `[schema]` — always `daana_dw` for data layer queries

## ROW_ST Filtering Rules

The Focal framework uses an **insert-only architecture**. Data is never updated or deleted — new rows are inserted to capture each change. `row_st` tracks whether a row represents an active value:

- **`row_st = 'Y'`** — The row holds a valid value. Multiple rows for the same entity + type_key can all have `row_st = 'Y'` at different `eff_tmstp` values — each represents the attribute's state at that point in time.
- **`row_st = 'N'`** — The attribute value was removed at the source (delivered as NULL). A new row is inserted with the removal timestamp and `row_st = 'N'` to record when the value disappeared.

**ROW_ST handling per pattern:**

- **Latest queries:** Filter `row_st = 'Y'` + RANK by `eff_tmstp DESC` → take `nbr = 1` to get the current active value.
- **History queries:** Do **not** filter `row_st` in the UNION ALL — include all rows so the `row_st = 'N'` row's `eff_tmstp` marks when the attribute was removed. Instead, null out the data values in the per-attribute CTEs using `CASE WHEN row_st = 'Y' THEN [column] ELSE NULL END`. This keeps the removal timestamp in the timeline while ensuring the pivoted output shows NULL from that point forward.

**Cutoff date modifier (applies to both patterns):**

- **Latest with cutoff:** Add `AND eff_tmstp <= '<cutoff>'` to the inner query's `WHERE` clause. The RANK + `row_st = 'Y'` filter then picks the most recent active value as of that date.
- **History with cutoff:** Add `AND eff_tmstp <= '<cutoff>'` to each UNION ALL member in the `twine` CTE. This restricts the timeline to events on or before the cutoff date. Everything else (carry-forward, deduplication, per-attribute CTEs, final join) stays the same.

## Pattern 1: Latest

Use this when the user wants a **single snapshot** of the data — either the current state or the state at a specific cutoff date. This pattern uses a RANK window to get the most recent version of each attribute, filters on `row_st = 'Y'`, and pivots the typed rows into a flat result.

```sql
SELECT
  [entity]_key,
  MAX(CASE WHEN type_key = [key1] THEN [physical_column1] END) AS [attribute_name1],
  MAX(CASE WHEN type_key = [key2] THEN [physical_column2] END) AS [attribute_name2]
  -- ... one CASE per atomic context/attribute ...
FROM (
  SELECT
    [entity]_key,
    type_key,
    row_st,
    RANK() OVER (
      PARTITION BY [entity]_key, type_key
      ORDER BY eff_tmstp DESC, ver_tmstp DESC
    ) AS nbr,
    sta_tmstp,
    end_tmstp,
    val_str,
    val_num,
    uom
  FROM [schema].[descriptor_table]
  WHERE type_key IN ([key1], [key2])
    -- With cutoff date, add:
    -- AND eff_tmstp <= '<cutoff>'
) AS a
WHERE nbr = 1 AND row_st = 'Y'
GROUP BY [entity]_key
```

**How it works:**

1. **Inner query:** Selects from the descriptor table, filtering to the relevant TYPE_KEYs. The `RANK()` window orders by `eff_tmstp DESC, ver_tmstp DESC` within each entity + type_key combination, so the most recent version gets `nbr = 1`.
2. **Filter:** `nbr = 1 AND row_st = 'Y'` keeps only the latest active row for each entity + attribute.
3. **Outer pivot:** `MAX(CASE WHEN type_key = ... THEN ... END)` pivots the typed rows into named columns, grouped by entity key.
4. **With cutoff date:** Adding `AND eff_tmstp <= '<cutoff>'` in the inner query restricts the RANK window to only consider rows up to the cutoff — giving the latest value as of that date.

### Complex atomic contexts

For atomic contexts with **multiple attributes in one type_key** (e.g., ride duration), include multiple CASE expressions for the same type_key, each reading a different physical column:

```sql
  MAX(CASE WHEN type_key = [key] THEN val_num END) AS [duration],
  MAX(CASE WHEN type_key = [key] THEN uom END) AS [duration_time_unit],
  MAX(CASE WHEN type_key = [key] THEN sta_tmstp END) AS [start_tmstp],
  MAX(CASE WHEN type_key = [key] THEN end_tmstp END) AS [end_tmstp]
```

### Relationship tables in latest queries

Relationship tables follow the **same RANK pattern** as descriptor tables. Relationships are temporal — they can change over time — so a direct `row_st = 'Y'` filter without RANK would return multiple rows if the relationship changed at different timestamps. Always resolve the latest active relationship first in its own CTE:

```sql
, latest_relationship AS (
  SELECT [entity_01]_key, [entity_02]_key
  FROM (
    SELECT
      [entity_01]_key, [entity_02]_key, row_st,
      RANK() OVER (
        PARTITION BY [entity_01]_key, [entity_02]_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM [schema].[relationship_table]
    WHERE type_key = [rel_atom_contx_key]
      -- With cutoff date, add:
      -- AND eff_tmstp <= '<cutoff>'
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
)
```

Then join to this CTE (not directly to the relationship table) when combining with descriptor data.

## Pattern 2: History — Temporal Alignment

When the user wants a **flat, pivoted history** across **multiple attributes**, the agent must solve the **temporal alignment problem**. Each attribute changes independently at different `eff_tmstp` values, so a simple GROUP BY pivot won't work — it would show NULLs for attributes that didn't change at a given timestamp.

The solution is a five-stage CTE pattern that builds a **merged timeline** and carries forward each attribute's value to every point in time.

### When to use this pattern

- The user asks for "history" or "changes over time" for an entity with **multiple attributes**
- The user wants to see the **full state of an entity at every point any attribute changed**
- The user wants a flat table (not raw typed rows) showing how an entity evolved

### Stage 1: `twine` CTE — Merge all attributes into one timeline

UNION ALL the selected atomic contexts from the descriptor table into a single CTE, tagging each with a `timeline` label:

```sql
WITH twine AS (
  SELECT [entity]_key, type_key, eff_tmstp, ver_tmstp, row_st,
         sta_tmstp, end_tmstp, val_str, val_num, uom,
         '[atomic_context_name_1]' AS timeline
  FROM [schema].[descriptor_table]
  WHERE type_key = [key1]
    -- With cutoff date, add:
    -- AND eff_tmstp <= '<cutoff>'
  UNION ALL
  SELECT [entity]_key, type_key, eff_tmstp, ver_tmstp, row_st,
         sta_tmstp, end_tmstp, val_str, val_num, uom,
         '[atomic_context_name_2]' AS timeline
  FROM [schema].[descriptor_table]
  WHERE type_key = [key2]
    -- With cutoff date, add:
    -- AND eff_tmstp <= '<cutoff>'
  -- ... one UNION ALL per atomic context ...
)
```

### Stage 2: `in_effect` CTE — Carry-forward timestamps and rank

Add carry-forward window columns and a RANK for deduplication. The window specification is written inline (no `WINDOW` clause) for platform compatibility:

```sql
, in_effect AS (
  SELECT
    [entity]_key,
    type_key,
    eff_tmstp,
    ver_tmstp,
    row_st,
    sta_tmstp,
    end_tmstp,
    val_str,
    val_num,
    uom,
    MAX(CASE WHEN timeline = '[atomic_context_name_1]' THEN eff_tmstp END)
      OVER (PARTITION BY [entity]_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_[atomic_context_name_1],
    MAX(CASE WHEN timeline = '[atomic_context_name_2]' THEN eff_tmstp END)
      OVER (PARTITION BY [entity]_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_[atomic_context_name_2],
    -- ... one carry-forward column per atomic context ...
    RANK() OVER (
      PARTITION BY [entity]_key, eff_tmstp
      ORDER BY eff_tmstp DESC
    ) AS rn
  FROM twine
)
```

**What this does:**

- The `MAX(...) OVER (PARTITION BY ... ORDER BY ... RANGE ...)` window propagates the most recent `eff_tmstp` for each atomic context forward through time — this is the **carry-forward** mechanism. At any row in the timeline, `eff_tmstp_[atomic_context_name]` tells you the timestamp of the most recent change to that specific attribute.
- The `RANK()` column is used for deduplication in the next stage.

### Stage 3: `filtered_in_effect` CTE — Deduplicate

Filter to one row per entity per `eff_tmstp`. This replaces `QUALIFY` (which is not supported on all platforms):

```sql
, filtered_in_effect AS (
  SELECT * FROM in_effect WHERE rn = 1
)
```

### Stage 4: Per-attribute CTEs — Extract each attribute's value

Create one CTE per atomic context that extracts the attribute value at each `eff_tmstp`. Use `CASE WHEN row_st = 'Y' THEN ... ELSE NULL END` to null out values from closed rows — this preserves the `eff_tmstp` in the timeline (so we know *when* the attribute was removed) while ensuring the carry-forward propagates NULL from that point forward:

```sql
, cte_[atomic_context_name_1] AS (
  SELECT
    [entity]_key,
    eff_tmstp,
    CASE WHEN row_st = 'Y' THEN [physical_column] ELSE NULL END AS [attribute_name]
  FROM filtered_in_effect
  WHERE type_key = [key1]
)
, cte_[atomic_context_name_2] AS (
  SELECT
    [entity]_key,
    eff_tmstp,
    CASE WHEN row_st = 'Y' THEN [physical_column] ELSE NULL END AS [attribute_name]
  FROM filtered_in_effect
  WHERE type_key = [key2]
)
-- ... one CTE per atomic context ...
```

For **complex atomic contexts** (multiple attributes in one type_key), apply the same pattern to all relevant physical columns:

```sql
, cte_[atomic_context_name] AS (
  SELECT
    [entity]_key,
    eff_tmstp,
    CASE WHEN row_st = 'Y' THEN [physical_column_1] ELSE NULL END AS [attribute_name_1],
    CASE WHEN row_st = 'Y' THEN [physical_column_2] ELSE NULL END AS [attribute_name_2]
    -- ... one column per attribute in the atomic context ...
  FROM filtered_in_effect
  WHERE type_key = [key]
)
```

### Stage 5: Final SELECT — Join using carry-forward timestamps

Join all per-attribute CTEs back to `filtered_in_effect` using the entity key AND the carry-forward timestamp for each attribute:

```sql
SELECT DISTINCT
  filtered_in_effect.[entity]_key,
  filtered_in_effect.eff_tmstp,
  cte_[atomic_context_name_1].[attribute_name_1],
  cte_[atomic_context_name_2].[attribute_name_2]
  -- ... one column per attribute ...
FROM filtered_in_effect
LEFT JOIN cte_[atomic_context_name_1]
  ON filtered_in_effect.[entity]_key = cte_[atomic_context_name_1].[entity]_key
  AND filtered_in_effect.eff_tmstp_[atomic_context_name_1] = cte_[atomic_context_name_1].eff_tmstp
LEFT JOIN cte_[atomic_context_name_2]
  ON filtered_in_effect.[entity]_key = cte_[atomic_context_name_2].[entity]_key
  AND filtered_in_effect.eff_tmstp_[atomic_context_name_2] = cte_[atomic_context_name_2].eff_tmstp
-- ... one LEFT JOIN per atomic context ...
```

**Critical:** The join condition uses the **carry-forward timestamp** (`eff_tmstp_[atomic_context_name]`), NOT the row's own `eff_tmstp`. This is what ensures each attribute shows the value that was **in effect at that moment**, even if that attribute wasn't the one that changed on that timeline row.

### Why this pattern is necessary

In a typed table, each attribute occupies its own rows with independent `eff_tmstp` values. Consider a customer where:
- Email changed at T1
- Org number changed at T2
- Industry classification changed at T3

A simple pivot (GROUP BY `[entity]_key`) would collapse these into one row — losing the timeline. A pivot grouped by `eff_tmstp` would show NULLs for attributes that didn't change at each timestamp.

The carry-forward pattern creates a **complete snapshot at every point in time**. At T2, the result shows the email value from T1 (carried forward), the new org number from T2, and NULL for industry classification (not yet set). At T3, it shows email from T1, org number from T2, and the new industry classification from T3.

### Building this from the bootstrap

The agent has everything it needs from the bootstrap result:

1. **`twine` CTE:** One UNION ALL member per `atomic_context_name` for the entity, using `atom_contx_key` as the `type_key` filter
2. **`in_effect` CTE:** One carry-forward column (`eff_tmstp_[atomic_context_name]`) per atomic context, plus RANK for deduplication
3. **`filtered_in_effect` CTE:** Simple `WHERE rn = 1` filter
4. **Per-attribute CTEs:** One per atomic context, reading from `filtered_in_effect`, using `CASE WHEN row_st = 'Y' THEN [physical_column] ELSE NULL END` → `attribute_name` mapping
5. **Final SELECT:** One LEFT JOIN per CTE, joining on entity key + carry-forward timestamp

The agent should generate all of these dynamically from the bootstrap data — never hardcode type_keys or column names.

## Relationship Queries

### Detecting relationships from bootstrap

When `table_pattern_column_name` is `FOCAL01_KEY` or `FOCAL02_KEY`, the descriptor concept is a **relationship table** (X table). The `attribute_name` values are the **actual physical column names** — not `FOCAL01_KEY`/`FOCAL02_KEY`.

Example bootstrap rows for `RIDE_STATION_X`:

| `descriptor_concept_name` | `atomic_context_name` | `atom_contx_key` | `attribute_name` | `table_pattern_column_name` |
|---|---|---|---|---|
| `RIDE_STATION_X` | `RIDE_START_STATION` | 16 | `ride_key` | `FOCAL01_KEY` |
| `RIDE_STATION_X` | `RIDE_START_STATION` | 16 | `station_key` | `FOCAL02_KEY` |
| `RIDE_STATION_X` | `RIDE_END_STATION` | 23 | `ride_key` | `FOCAL01_KEY` |
| `RIDE_STATION_X` | `RIDE_END_STATION` | 23 | `station_key` | `FOCAL02_KEY` |

This tells the agent:
- The relationship table has two key columns: `ride_key` (pattern: `FOCAL01_KEY`) and `station_key` (pattern: `FOCAL02_KEY`)
- `type_key = 16` means "start station", `type_key = 23` means "end station"

### Column name rule

```sql
-- CORRECT: use attribute_name as the column name
SELECT ride_key, station_key FROM daana_dw.ride_station_x WHERE type_key = 16

-- WRONG: FOCAL01_KEY and FOCAL02_KEY don't exist in the physical table
SELECT FOCAL01_KEY, FOCAL02_KEY FROM daana_dw.ride_station_x WHERE type_key = 16
```

### Building a relationship query

Relationship tables are temporal just like descriptor tables. In **latest** queries, always resolve relationships using the RANK pattern first, then join the result to descriptor CTEs:

```sql
-- Step 1: Resolve the latest active relationship
WITH latest_rel AS (
  SELECT [entity_01]_key, [entity_02]_key
  FROM (
    SELECT
      [entity_01]_key, [entity_02]_key, row_st,
      RANK() OVER (
        PARTITION BY [entity_01]_key, [entity_02]_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM [schema].[relationship_table]
    WHERE type_key = [rel_atom_contx_key]
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
),
-- Step 2: Resolve the latest descriptor value (same RANK pattern)
latest_desc AS (
  SELECT
    [entity]_key,
    MAX(CASE WHEN type_key = [desc_atom_contx_key] THEN [physical_column] END) AS [attribute_name]
  FROM (
    SELECT
      [entity]_key, type_key, row_st, [physical_column],
      RANK() OVER (
        PARTITION BY [entity]_key, type_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM [schema].[entity_desc_table]
    WHERE type_key = [desc_atom_contx_key]
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY [entity]_key
)
-- Step 3: Join the resolved CTEs
SELECT
  ld.[attribute_name],
  COUNT(*) AS ride_count
FROM latest_rel lr
JOIN latest_desc ld
  ON lr.[entity_02]_key = ld.[entity]_key
GROUP BY ld.[attribute_name]
```

**Important:** The physical column names in relationship tables (`FOCAL01_KEY`, `FOCAL02_KEY`) are generic pattern columns. The metadata maps them to logical entity key names. When joining to descriptor tables, use the descriptor table's own entity key column (e.g., `station_key` in `station_desc`), not the generic pattern column name.

## Bootstrap Fallback

If `f_focal_read` is not available, the agent can bootstrap using `atom_contx_nm` as the entry point. This table can always be searched by `val_str` without needing to know a type_key first:

```sql
SELECT atom_contx_key, val_str
FROM daana_metadata.atom_contx_nm
WHERE val_str IN (
  'FOCAL_NAME',
  'FOCAL_PHYSICAL_SCHEMA',
  'ATOMIC_CONTEXT_NAME',
  'ATTRIBUTE_NAME',
  'DESCRIPTOR_CONCEPT_NAME',
  'TABLE_PATTERN_COLUMN_NAME'
)
AND row_st = 'Y'
```

The agent should cache these resolved keys for the duration of its session and use them whenever reading from metadata tables.

If the bootstrap is not available, fall back to searching `atom_contx_nm.val_str` directly:

```sql
SELECT atom_contx_key, val_str
FROM daana_metadata.atom_contx_nm
WHERE UPPER(val_str) LIKE UPPER('%<keyword>%')
  AND row_st = 'Y'
```

Tips:
- The naming convention is `ENTITY_ATTRIBUTE_NAME` — so searching for "CUSTOMER" narrows to that entity
- Try multiple keywords if the first search returns nothing (e.g., "email" → "MAIL", "ADDRESS")
- If too many results, combine entity + attribute keywords (e.g., `%CUSTOMER%EMAIL%`)

Then resolve the full chain manually using the individual metadata tables (see `focal-framework.md` for the step-by-step chain).

## Lineage Tracing

Every physical table includes `inst_key` for pipeline execution logging. Join to `procinst_desc` in the metadata layer to retrieve the actual SQL that loaded a data row:

```sql
SELECT DISTINCT pd.val_str
FROM daana_metadata.procinst_desc pd
INNER JOIN daana_dw.[descriptor_table] dt
  ON dt.inst_key = pd.procinst_key
WHERE dt.[entity]_key = '<entity_key_value>'
```

## Decision Tree

```
User asks a question
  │
  ├─ Entity clear?
  │   ├─ YES → continue
  │   └─ NO → ask user to pick from bootstrapped entities
  │
  ├─ Attributes clear?
  │   ├─ YES → match against atomic_context_name / attribute_name
  │   └─ NO → list available atomic contexts for entity, ask user to pick
  │
  ├─ Cross-entity data needed?
  │   ├─ YES → resolve relationship table + join
  │   └─ NO → single table query
  │
  ├─ Latest or history? (HARD-GATE)
  │   ├─ LATEST → Pattern 1
  │   └─ HISTORY → Pattern 2 (Temporal Alignment)
  │
  └─ Cutoff date? (HARD-GATE)
      ├─ NO → use current data (no eff_tmstp filter)
      └─ YES → add eff_tmstp <= '<cutoff>' to inner query (Pattern 1) or twine CTE (Pattern 2)
```

---

## End-to-End Worked Example

This example shows the full process from a vague user question to a final SQL query. The agent knows **nothing** about the data model in advance — it could be any domain.

### User says: "show me the total amount per supplier"

#### Step 1: Bootstrap

The agent runs the bootstrap query and discovers these entities (hypothetical):

```
focal_name     | descriptor_concept_name | atomic_context_name         | atom_contx_key | attribute_name   | table_pattern_column_name
INVOICE_FOCAL  | INVOICE_DESC            | INVOICE_INVOICE_AMOUNT      | 42             | INVOICE_AMOUNT   | VAL_NUM
INVOICE_FOCAL  | INVOICE_DESC            | INVOICE_INVOICE_CURRENCY    | 43             | INVOICE_CURRENCY | VAL_STR
INVOICE_FOCAL  | INVOICE_SUPPLIER_X      | INVOICE_SUPPLIED_BY         | 50             | INVOICE_KEY      | FOCAL01_KEY
INVOICE_FOCAL  | INVOICE_SUPPLIER_X      | INVOICE_SUPPLIED_BY         | 50             | SUPPLIER_KEY     | FOCAL02_KEY
SUPPLIER_FOCAL | SUPPLIER_DESC           | SUPPLIER_SUPPLIER_NAME      | 61             | SUPPLIER_NAME    | VAL_STR
```

#### Step 2: Match keywords

- **"amount"** → matches `INVOICE_INVOICE_AMOUNT` (atom_contx_key = 42, stored in `val_num`)
- **"supplier"** → matches `SUPPLIER_FOCAL` entity, with `SUPPLIER_SUPPLIER_NAME` (atom_contx_key = 61, stored in `val_str`)
- **"per supplier"** → requires a relationship. The bootstrap shows `INVOICE_SUPPLIER_X` links the two entities via `INVOICE_SUPPLIED_BY` (atom_contx_key = 50)

The word "total" suggests SUM. If unsure, the agent asks.

#### Step 3: Resolve relationship columns

From the bootstrap:
- `INVOICE_SUPPLIER_X` has `FOCAL01_KEY` → attribute name `invoice_key`
- `INVOICE_SUPPLIER_X` has `FOCAL02_KEY` → attribute name `supplier_key`

Since these are relationship columns, use `attribute_name` as the physical column (not `FOCAL01_KEY`/`FOCAL02_KEY`).

#### Step 4: Build the query

```sql
SELECT
  sd.val_str AS supplier_name,
  SUM(id.val_num) AS total_amount
FROM daana_dw.invoice_supplier_x rx
JOIN daana_dw.invoice_desc id
  ON rx.invoice_key = id.invoice_key
  AND id.type_key = 42 AND id.row_st = 'Y'
JOIN daana_dw.supplier_desc sd
  ON rx.supplier_key = sd.supplier_key
  AND sd.type_key = 61 AND sd.row_st = 'Y'
WHERE rx.type_key = 50 AND rx.row_st = 'Y'
GROUP BY sd.val_str
ORDER BY total_amount DESC
```

#### Key takeaways

1. **The agent never assumed any model structure.** Everything was discovered from the bootstrap.
2. **Entity names, attribute names, and column names were all different from any prior example.** The process works regardless of domain.
3. **The agent matched natural language to metadata names.** "amount" → `INVOICE_AMOUNT`, "supplier" → `SUPPLIER_NAME`.
4. **Relationship columns used `attribute_name`, not `table_pattern_column_name`.** The agent detected `FOCAL01_KEY`/`FOCAL02_KEY` and switched to attribute names.
5. **The agent asked clarifying questions** when "total" could mean different things.
