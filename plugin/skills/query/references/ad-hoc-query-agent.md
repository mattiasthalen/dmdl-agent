# Agent Workflow: From User Question to Focal Query

This document describes the decision process an agent follows when a user asks a data question. The agent must translate a natural language request into a metadata-driven query against the Focal framework.

## Phase 1: Understand What the User Wants

The user will rarely speak in Focal terms. They'll say things like "show me customer emails" or "how long are the rides." The agent needs to figure out:

1. **Which entity?** — What business concept is the user asking about?
2. **Which attributes?** — What specific data fields do they want?
3. **Single attribute or multiple?** — Should the result be a simple list or a pivoted flat table?
4. **Any filters?** — Do they want a specific record, a subset, or everything?
5. **Latest or history?** — Do they want current state or the full timeline of changes?
6. **Cutoff date?** — Do they want data as of now, or up to a specific point in time?

### Clarifying Questions the Agent Must Ask

If the request is ambiguous, the agent **must** ask before building a query — never assume defaults:

| Ambiguity | Example Question |
|-----------|-----------------|
| Entity unclear | "Are you asking about rides, customers, or stations?" |
| Attribute unclear | "By 'customer info', do you mean email, ID, organization number, or all of them?" |
| Multiple matches | "I found both CUSTOMER_ID and CUSTOMER_ALT_ID — which one do you mean?" |
| Scope unclear | "Do you want all customers, or a specific one?" |
| Latest vs history | "Do you want the latest values, or the full history of changes over time?" |
| Cutoff date | "Do you want data as of right now, or up to a specific date?" |
| Relationship needed | "Do you want just ride data, or also which station/customer each ride is linked to?" |

## Phase 2: Bootstrap

The bootstrap data is provided by the focal agent before this workflow begins. The full metadata model is already cached in context — do not run the bootstrap query again.

If the bootstrap data is not available in context, inform the calling skill that bootstrap is required.

## Phase 3: Match the User's Question to the Bootstrap Data

The agent already has the full metadata model from the bootstrap. Instead of querying the database again, it should match the user's question against the bootstrapped data in memory.

### Matching strategy

1. **Identify the entity** — Match keywords from the user's question against `FOCAL_NAME` values (e.g. "customer" matches `CUSTOMER_FOCAL`, "ride" matches `RIDE_FOCAL`)
2. **Identify the attributes** — Match keywords against `ATOMIC_CONTEXT_NAME` and `ATTRIBUTE_NAME` values for that entity (e.g. "email" matches `CUSTOMER_CUSTOMER_EMAIL_ADDRESS`, "duration" matches `RIDE_RIDE_DURATION_...`)
3. **Detect relationships** — If the user's question spans multiple entities (e.g. "rides per station"), look for `DESCRIPTOR_CONCEPT_NAME` entries with `FOCAL01_KEY`/`FOCAL02_KEY` pattern columns that link the two entities

Once matched, the agent has everything from the bootstrap row: table name, TYPE_KEY, attribute names, and physical columns. No further metadata queries needed.

### Last-resort fallback (no bootstrap in context)

If, despite the above, no bootstrap data is available, fall back to searching `ATOM_CONTX_NM.VAL_STR` directly:

```sql
SELECT ATOM_CONTX_KEY, VAL_STR
FROM DAANA_METADATA.ATOM_CONTX_NM
WHERE UPPER(VAL_STR) LIKE UPPER('%<keyword>%')
  AND ROW_ST = 'Y'
```

Tips:
- The naming convention is `ENTITY_ATTRIBUTE_NAME` — so searching for "CUSTOMER" narrows to that entity
- Try multiple keywords if the first search returns nothing (e.g. "email" → "MAIL", "ADDRESS")
- If too many results, combine entity + attribute keywords (e.g. `%CUSTOMER%EMAIL%`)

Then resolve the full chain manually using the individual metadata tables (see the Focal Framework reference doc for the step-by-step chain).

## Phase 4: Build the Query

There are **two query patterns**, each with an optional **cutoff date** modifier:

1. **Latest** — The current state of the data, pivoted into a flat result
2. **History** — The full timeline showing how the data evolved over time

**Cutoff date modifier:** Either pattern can be restricted to a specific point in time by adding `EFF_TMSTP <= '<cutoff>'`. This turns:
- **Latest** → "What was the state at this date?" (latest value as of the cutoff)
- **History** → "How did the data evolve up to this date?" (full timeline truncated at the cutoff)

The agent determines the pattern in two steps:
1. **Latest or history?** — Does the user want a single snapshot or the full timeline?
2. **Cutoff date?** — Does the user want current data or data as of a specific date?

### ROW_ST filtering rules

The Focal framework uses an **insert-only architecture**. Data is never updated or deleted — new rows are inserted to capture each change. `ROW_ST` tracks whether a row represents an active value:

- **`ROW_ST = 'Y'`** — The row holds a valid value. Multiple rows for the same entity + TYPE_KEY can all have `ROW_ST = 'Y'` at different `EFF_TMSTP` values — each represents the attribute's state at that point in time.
- **`ROW_ST = 'N'`** — The attribute value was removed at the source (delivered as NULL). A new row is inserted with the removal timestamp and `ROW_ST = 'N'` to record when the value disappeared.

**ROW_ST handling per pattern:**

- **Latest queries:** Filter `ROW_ST = 'Y'` + RANK by `EFF_TMSTP DESC` → take NBR = 1 to get the current active value.
- **History queries:** Do **not** filter `ROW_ST` in the UNION ALL — include all rows so the `ROW_ST = 'N'` row's `EFF_TMSTP` marks when the attribute was removed. Instead, null out the data values in the per-attribute CTEs using `CASE WHEN ROW_ST = 'Y' THEN [column] ELSE NULL END`. This keeps the removal timestamp in the timeline while ensuring the pivoted output shows NULL from that point forward.

**Cutoff date modifier (applies to both patterns):**

- **Latest with cutoff:** Add `AND EFF_TMSTP <= '<cutoff>'` to the inner query's `WHERE` clause. The RANK + `ROW_ST = 'Y'` filter then picks the most recent active value as of that date.
- **History with cutoff:** Add `AND EFF_TMSTP <= '<cutoff>'` to each UNION ALL member in the `twine` CTE. This restricts the timeline to events on or before the cutoff date. Everything else (carry-forward, deduplication, per-attribute CTEs, final join) stays the same.

### Pattern 1: Latest

Use this when the user wants a **single snapshot** of the data — either the current state or the state at a specific cutoff date. This pattern uses a RANK window to get the most recent version of each attribute, filters on `ROW_ST = 'Y'`, and pivots the typed rows into a flat result.

```sql
SELECT
  [ENTITY]_KEY,
  MAX(CASE WHEN TYPE_KEY = [key1] THEN [physical_column1] END) AS [attribute_name1],
  MAX(CASE WHEN TYPE_KEY = [key2] THEN [physical_column2] END) AS [attribute_name2],
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
    STA_TMSTP,
    END_TMSTP,
    VAL_STR,
    VAL_NUM,
    UOM
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY IN ([key1], [key2], ...)
    -- With cutoff date, add:
    -- AND EFF_TMSTP <= '<cutoff>'
) AS A
WHERE NBR = 1 AND ROW_ST = 'Y'
GROUP BY [ENTITY]_KEY
```

**How it works:**

1. **Inner query:** Selects from the descriptor table, filtering to the relevant TYPE_KEYs. The `RANK()` window orders by `EFF_TMSTP DESC, VER_TMSTP DESC` within each entity + TYPE_KEY combination, so the most recent version gets `NBR = 1`.
2. **Filter:** `NBR = 1 AND ROW_ST = 'Y'` keeps only the latest active row for each entity + attribute.
3. **Outer pivot:** `MAX(CASE WHEN TYPE_KEY = ... THEN ... END)` pivots the typed rows into named columns, grouped by entity key.
4. **With cutoff date:** Adding `AND EFF_TMSTP <= '<cutoff>'` in the inner query restricts the RANK window to only consider rows up to the cutoff — giving the latest value as of that date.

For **complex atomic contexts** (multiple attributes in one TYPE_KEY, e.g. ride duration), include multiple CASE expressions for the same TYPE_KEY, each reading a different physical column:

```sql
  MAX(CASE WHEN TYPE_KEY = [key] THEN VAL_NUM END) AS [DURATION],
  MAX(CASE WHEN TYPE_KEY = [key] THEN UOM END) AS [DURATION_TIME_UNIT],
  MAX(CASE WHEN TYPE_KEY = [key] THEN STA_TMSTP END) AS [START_TMSTP],
  MAX(CASE WHEN TYPE_KEY = [key] THEN END_TMSTP END) AS [END_TMSTP],
```

#### Relationship tables in latest queries

Relationship tables follow the **same RANK pattern** as descriptor tables. Relationships are temporal — they can change over time — so a direct `ROW_ST = 'Y'` filter without RANK would return multiple rows if the relationship changed at different timestamps. Always resolve the latest active relationship first in its own CTE:

```sql
, latest_relationship AS (
  SELECT [ENTITY_01]_KEY, [ENTITY_02]_KEY
  FROM (
    SELECT
      [ENTITY_01]_KEY, [ENTITY_02]_KEY, ROW_ST,
      RANK() OVER (
        PARTITION BY [ENTITY_01]_KEY, [ENTITY_02]_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [physical_schema].[relationship_table]
    WHERE TYPE_KEY = [rel_atom_contx_key]
      -- With cutoff date, add:
      -- AND EFF_TMSTP <= '<cutoff>'
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
)
```

Then join to this CTE (not directly to the relationship table) when combining with descriptor data.

### Pattern 2: History — Temporal Alignment Pattern

When the user wants a **flat, pivoted history** across **multiple attributes**, the agent must solve the **temporal alignment problem**. Each attribute changes independently at different `EFF_TMSTP` values, so a simple GROUP BY pivot won't work — it would show NULLs for attributes that didn't change at a given timestamp.

The solution is a three-stage query pattern that builds a **merged timeline** and carries forward each attribute's value to every point in time.

#### When to use this pattern

- The user asks for "history" or "changes over time" for an entity with **multiple attributes**
- The user wants to see the **full state of an entity at every point any attribute changed**
- The user wants a flat table (not raw typed rows) showing how an entity evolved

**With cutoff date:** Add `AND EFF_TMSTP <= '<cutoff>'` to each `WHERE` clause in the `twine` CTE. This truncates the timeline at the cutoff. Everything else (carry-forward, deduplication, per-attribute CTEs, final join) stays the same.

#### Stage 1: `twine` CTE — Merge all attributes into one timeline

UNION ALL the selected atomic contexts from the descriptor table into a single CTE, tagging each with a `TIMELINE` label:

```sql
WITH twine AS (
  SELECT [ENTITY]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM,
         '[ATOMIC_CONTEXT_NAME_1]' AS TIMELINE
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY = [key1]
    -- With cutoff date, add:
    -- AND EFF_TMSTP <= '<cutoff>'
  UNION ALL
  SELECT [ENTITY]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         STA_TMSTP, END_TMSTP, VAL_STR, VAL_NUM, UOM,
         '[ATOMIC_CONTEXT_NAME_2]' AS TIMELINE
  FROM [physical_schema].[descriptor_table]
  WHERE TYPE_KEY = [key2]
    -- With cutoff date, add:
    -- AND EFF_TMSTP <= '<cutoff>'
  -- ... one UNION ALL per atomic context ...
)
```

#### Stage 2: `in_effect` CTE — Carry-forward timestamps and rank

Add carry-forward window columns and a RANK for deduplication. The window specification is written inline (no `WINDOW` clause) for platform compatibility:

```sql
, in_effect AS (
  SELECT
    [ENTITY]_KEY,
    TYPE_KEY,
    EFF_TMSTP,
    VER_TMSTP,
    ROW_ST,
    STA_TMSTP,
    END_TMSTP,
    VAL_STR,
    VAL_NUM,
    UOM,
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
)
```

**What this does:**

- The `MAX(...) OVER (PARTITION BY ... ORDER BY ... RANGE ...)` window propagates the most recent `EFF_TMSTP` for each atomic context forward through time — this is the **carry-forward** mechanism. At any row in the timeline, `EFF_TMSTP_[ATOMIC_CONTEXT_NAME]` tells you the timestamp of the most recent change to that specific attribute.
- The `RANK()` column is used for deduplication in the next stage.

#### Stage 3: `filtered_in_effect` CTE — Deduplicate

Filter to one row per entity per `EFF_TMSTP`. This replaces `QUALIFY` (which is not supported on all platforms):

```sql
, filtered_in_effect AS (
  SELECT * FROM in_effect WHERE RN = 1
)
```

#### Stage 4: Per-attribute CTEs — Extract each attribute's value

Create one CTE per atomic context that extracts the attribute value at each `EFF_TMSTP`. Use `CASE WHEN ROW_ST = 'Y' THEN ... ELSE NULL END` to null out values from closed rows — this preserves the `EFF_TMSTP` in the timeline (so we know *when* the attribute was removed) while ensuring the carry-forward propagates NULL from that point forward:

```sql
, CTE_[ATOMIC_CONTEXT_NAME_1] AS (
  SELECT
    [ENTITY]_KEY,
    EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [ATTRIBUTE_NAME]
  FROM filtered_in_effect
  WHERE TYPE_KEY = [key1]
)
, CTE_[ATOMIC_CONTEXT_NAME_2] AS (
  SELECT
    [ENTITY]_KEY,
    EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [ATTRIBUTE_NAME]
  FROM filtered_in_effect
  WHERE TYPE_KEY = [key2]
)
-- ... one CTE per atomic context ...
```

For **complex atomic contexts** (multiple attributes in one TYPE_KEY, e.g. ride duration), apply the same pattern to all relevant physical columns:

```sql
, CTE_[ATOMIC_CONTEXT_NAME] AS (
  SELECT
    [ENTITY]_KEY,
    EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column_1] ELSE NULL END AS [ATTRIBUTE_NAME_1],
    CASE WHEN ROW_ST = 'Y' THEN [physical_column_2] ELSE NULL END AS [ATTRIBUTE_NAME_2],
    -- ... one column per attribute in the atomic context ...
  FROM filtered_in_effect
  WHERE TYPE_KEY = [key]
)
```

#### Stage 5: Final SELECT — Join using carry-forward timestamps

Join all per-attribute CTEs back to `filtered_in_effect` using the entity key AND the carry-forward timestamp for each attribute:

```sql
SELECT DISTINCT
  filtered_in_effect.[ENTITY]_KEY,
  filtered_in_effect.EFF_TMSTP,
  CTE_[ATOMIC_CONTEXT_NAME_1].[ATTRIBUTE_NAME_1],
  CTE_[ATOMIC_CONTEXT_NAME_2].[ATTRIBUTE_NAME_2],
  -- ... one column per attribute ...
FROM filtered_in_effect
LEFT JOIN CTE_[ATOMIC_CONTEXT_NAME_1]
  ON filtered_in_effect.[ENTITY]_KEY = CTE_[ATOMIC_CONTEXT_NAME_1].[ENTITY]_KEY
  AND filtered_in_effect.EFF_TMSTP_[ATOMIC_CONTEXT_NAME_1] = CTE_[ATOMIC_CONTEXT_NAME_1].EFF_TMSTP
LEFT JOIN CTE_[ATOMIC_CONTEXT_NAME_2]
  ON filtered_in_effect.[ENTITY]_KEY = CTE_[ATOMIC_CONTEXT_NAME_2].[ENTITY]_KEY
  AND filtered_in_effect.EFF_TMSTP_[ATOMIC_CONTEXT_NAME_2] = CTE_[ATOMIC_CONTEXT_NAME_2].EFF_TMSTP
-- ... one LEFT JOIN per atomic context ...
```

**Critical:** The join condition uses the **carry-forward timestamp** (`EFF_TMSTP_[ATOMIC_CONTEXT_NAME]`), NOT the row's own `EFF_TMSTP`. This is what ensures each attribute shows the value that was **in effect at that moment**, even if that attribute wasn't the one that changed on that timeline row.

#### Why this pattern is necessary

In a typed table, each attribute occupies its own rows with independent `EFF_TMSTP` values. Consider a customer where:
- Email changed at T1
- Org number changed at T2
- Industry classification changed at T3

A simple pivot (GROUP BY `[ENTITY]_KEY`) would collapse these into one row — losing the timeline. A pivot grouped by `EFF_TMSTP` would show NULLs for attributes that didn't change at each timestamp.

The carry-forward pattern creates a **complete snapshot at every point in time**. At T2, the result shows the email value from T1 (carried forward), the new org number from T2, and NULL for industry classification (not yet set). At T3, it shows email from T1, org number from T2, and the new industry classification from T3.

#### Building this from the bootstrap

The agent has everything it needs from the bootstrap result:

1. **`twine` CTE:** One UNION ALL member per `ATOMIC_CONTEXT_NAME` for the entity, using `ATOM_CONTX_KEY` as the `TYPE_KEY` filter
2. **`in_effect` CTE:** One carry-forward column (`EFF_TMSTP_[ATOMIC_CONTEXT_NAME]`) per atomic context, plus RANK for deduplication
3. **`filtered_in_effect` CTE:** Simple `WHERE RN = 1` filter
4. **Per-attribute CTEs:** One per atomic context, reading from `filtered_in_effect`, using `CASE WHEN ROW_ST = 'Y' THEN [PHYSICAL_COLUMN] ELSE NULL END` → `ATTRIBUTE_NAME` mapping
5. **Final SELECT:** One LEFT JOIN per CTE, joining on entity key + carry-forward timestamp

The agent should generate all of these dynamically from the bootstrap data — never hardcode TYPE_KEYs or column names.

### With relationships

If the user asks for cross-entity data (e.g. "show me rides per station"), the agent needs to join across entities via a relationship table. The metadata fully describes the relationship structure — column names are never guessed.

#### Discovering relationship tables and their structure

Given a Descriptor Concept for a relationship table (e.g. `RIDE_STATION_X`), trace down to its Atomic Contexts and attributes to discover:
- Which relationship types exist (each Atomic Context = one relationship type)
- Which entity keys are involved and their physical column names

```sql
SELECT
  acn.VAL_STR as relationship_type,
  acn.ATOM_CONTX_KEY,
  an.VAL_STR as attribute_name,
  tcn.VAL_STR as physical_column
FROM DAANA_METADATA.ATOM_CONTX_DESC_CNCPT_X acdx
JOIN DAANA_METADATA.ATOM_CONTX_NM acn
  ON acdx.ATOM_CONTX_KEY = acn.ATOM_CONTX_KEY AND acn.ROW_ST = 'Y'
JOIN DAANA_METADATA.ATR_ATOM_CONTX_X ax
  ON acn.ATOM_CONTX_KEY = ax.ATOM_CONTX_KEY AND ax.ROW_ST = 'Y'
JOIN DAANA_METADATA.ATR_NM an
  ON ax.ATR_KEY = an.ATR_KEY AND an.ROW_ST = 'Y'
JOIN DAANA_METADATA.LOGICAL_PHYSICAL_X lp
  ON lp.ATR_KEY = ax.ATR_KEY AND lp.ATOM_CONTX_KEY = ax.ATOM_CONTX_KEY AND lp.ROW_ST = 'Y'
JOIN DAANA_METADATA.TBL_PTRN_COL_NM tcn
  ON lp.TBL_PTRN_COL_KEY = tcn.TBL_PTRN_COL_KEY AND tcn.ROW_ST = 'Y'
WHERE acdx.DESC_CNCPT_KEY = <relationship_desc_cncpt_key> AND acdx.ROW_ST = 'Y'
ORDER BY acn.VAL_STR, an.VAL_STR
```

Example result for `RIDE_STATION_X`:

| relationship_type | ATOM_CONTX_KEY | attribute_name | physical_column |
|-------------------|----------------|----------------|-----------------|
| RIDE_START_STATION | 16 | RIDE_KEY | FOCAL01_KEY |
| RIDE_START_STATION | 16 | STATION_KEY | FOCAL02_KEY |
| RIDE_END_STATION | 23 | RIDE_KEY | FOCAL01_KEY |
| RIDE_END_STATION | 23 | STATION_KEY | FOCAL02_KEY |

This tells the agent:
- The relationship table has two key columns: `FOCAL01_KEY` (= RIDE_KEY) and `FOCAL02_KEY` (= STATION_KEY)
- `TYPE_KEY = 16` means "start station", `TYPE_KEY = 23` means "end station"
- The logical attribute names (`RIDE_KEY`, `STATION_KEY`) tell you which entities are linked

#### Building a relationship query

Relationship tables are temporal just like descriptor tables. In **latest** queries, always resolve relationships using the RANK pattern first, then join the result to descriptor CTEs:

```sql
-- Step 1: Resolve the latest active relationship
WITH latest_rel AS (
  SELECT [ENTITY_01]_KEY, [ENTITY_02]_KEY
  FROM (
    SELECT
      [ENTITY_01]_KEY, [ENTITY_02]_KEY, ROW_ST,
      RANK() OVER (
        PARTITION BY [ENTITY_01]_KEY, [ENTITY_02]_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [schema].[relationship_table]
    WHERE TYPE_KEY = [rel_atom_contx_key]
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
),
-- Step 2: Resolve the latest descriptor value (same RANK pattern)
latest_desc AS (
  SELECT
    [ENTITY]_KEY,
    MAX(CASE WHEN TYPE_KEY = [desc_atom_contx_key] THEN [physical_column] END) AS [attribute_name]
  FROM (
    SELECT
      [ENTITY]_KEY, TYPE_KEY, ROW_ST, [physical_column],
      RANK() OVER (
        PARTITION BY [ENTITY]_KEY, TYPE_KEY
        ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
      ) AS NBR
    FROM [schema].[entity_desc_table]
    WHERE TYPE_KEY = [desc_atom_contx_key]
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY [ENTITY]_KEY
)
-- Step 3: Join the resolved CTEs
SELECT
  ld.[attribute_name],
  COUNT(*) as ride_count
FROM latest_rel lr
JOIN latest_desc ld
  ON lr.[ENTITY_02]_KEY = ld.[ENTITY]_KEY
GROUP BY ld.[attribute_name]
```

**Important:** The physical column names in relationship tables (`FOCAL01_KEY`, `FOCAL02_KEY`) are generic pattern columns. The metadata maps them to logical entity key names. When joining to descriptor tables, use the descriptor table's own entity key column (e.g. `STATION_KEY` in `STATION_DESC`), not the generic pattern column name.

### Pattern 3: Multi-Entity History

When the user wants a **history view that spans multiple entities connected through relationships**, the agent must combine independent temporal timelines from different tables — each with its own key — into one golden timeline.

This extends Pattern 2 (single-entity history) with a modular approach: each entity and relationship is resolved independently, then composed.

#### When to use this pattern

- The user asks for history across entities (e.g. "order line revenue history with product names")
- The query involves relationship tables that connect the entities
- The user needs to see how cross-entity data evolved over time

#### Architecture: Three modules

| Module | Source | Key | Produces |
|--------|--------|-----|----------|
| **Anchor descriptors** | `[ANCHOR]_DESC` | `[ANCHOR]_KEY` | Per-attribute CTEs (values from the anchor entity) |
| **Relationship** | `[ANCHOR]_[RELATED]_X` | `[ANCHOR]_KEY` + `[RELATED]_KEY` | CTE carrying forward the related entity's key |
| **Related descriptors** | `[RELATED]_DESC` | `[RELATED]_KEY` | Per-attribute CTEs (values from the related entity) |

The **anchor entity** is the primary entity the query is about — the one whose key defines the golden timeline. The agent infers this from the user's question (e.g. "order line revenue" → anchor is ORDER_LINE).

#### Module 1 + 2: Combined twine (anchor descriptors + relationship)

The anchor's descriptor attributes and the relationship share the same anchor key, so they merge into **one twine**. The relationship's related-entity key (`[RELATED]_KEY`) is included as a value column to be carried forward alongside the descriptor values.

```sql
WITH twine AS (
  -- Anchor descriptor attribute 1
  SELECT [ANCHOR]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         [physical_column_1], CAST(NULL AS VARCHAR) AS [RELATED]_KEY,
         '[ATOMIC_CONTEXT_NAME_1]' AS TIMELINE
  FROM [physical_schema].[anchor_desc_table]
  WHERE TYPE_KEY = [key1]
  UNION ALL
  -- Anchor descriptor attribute 2
  SELECT [ANCHOR]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         [physical_column_2], NULL,
         '[ATOMIC_CONTEXT_NAME_2]' AS TIMELINE
  FROM [physical_schema].[anchor_desc_table]
  WHERE TYPE_KEY = [key2]
  -- ... one UNION ALL per anchor atomic context ...
  UNION ALL
  -- Relationship (both keys are values — the combination represents an event)
  SELECT [ANCHOR]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         CAST(NULL AS NUMERIC) AS [physical_column], [RELATED]_KEY,
         '[RELATIONSHIP_NAME]' AS TIMELINE
  FROM [physical_schema].[relationship_table]
  WHERE TYPE_KEY = [rel_key]
)
```

**Column alignment:** The UNION ALL requires consistent columns. Descriptor rows have NULL for `[RELATED]_KEY`; relationship rows have NULL for value columns. Cast NULLs to match the column types.

Then apply the standard carry-forward and deduplication stages from Pattern 2:

```sql
, in_effect AS (
  SELECT
    [ANCHOR]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
    [physical_column], [RELATED]_KEY,
    -- Carry-forward per anchor descriptor attribute
    MAX(CASE WHEN TIMELINE = '[ATOMIC_CONTEXT_NAME_1]' THEN EFF_TMSTP END)
      OVER (PARTITION BY [ANCHOR]_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS EFF_TMSTP_[ATOMIC_CONTEXT_NAME_1],
    MAX(CASE WHEN TIMELINE = '[ATOMIC_CONTEXT_NAME_2]' THEN EFF_TMSTP END)
      OVER (PARTITION BY [ANCHOR]_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS EFF_TMSTP_[ATOMIC_CONTEXT_NAME_2],
    -- ... one carry-forward column per anchor atomic context ...
    -- Carry-forward for the relationship
    MAX(CASE WHEN TIMELINE = '[RELATIONSHIP_NAME]' THEN EFF_TMSTP END)
      OVER (PARTITION BY [ANCHOR]_KEY ORDER BY EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS EFF_TMSTP_[RELATIONSHIP_NAME],
    RANK() OVER (
      PARTITION BY [ANCHOR]_KEY, EFF_TMSTP
      ORDER BY EFF_TMSTP DESC
    ) AS RN
  FROM twine
)

, filtered_in_effect AS (
  SELECT * FROM in_effect WHERE RN = 1
)
```

Per-attribute CTEs for anchor descriptors follow the standard Pattern 2 approach. The relationship CTE extracts the carried-forward related-entity key:

```sql
-- Anchor descriptor CTEs (standard)
, CTE_[ATOMIC_CONTEXT_NAME_1] AS (
  SELECT [ANCHOR]_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [ATTRIBUTE_NAME]
  FROM filtered_in_effect
  WHERE TYPE_KEY = [key1]
)
-- ... one CTE per anchor atomic context ...

-- Relationship CTE (carries forward the related entity key)
, CTE_[RELATIONSHIP_NAME] AS (
  SELECT [ANCHOR]_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [RELATED]_KEY ELSE NULL END AS [RELATED]_KEY
  FROM filtered_in_effect
  WHERE TYPE_KEY = [rel_key]
)
```

#### Module 3: Related entity history (self-contained)

The related entity runs its own independent history pattern, keyed on `[RELATED]_KEY`. This is a standard Pattern 2 applied to the related entity's descriptor table:

```sql
, related_twine AS (
  SELECT [RELATED]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST,
         [physical_column],
         '[RELATED_ATOMIC_CONTEXT_NAME]' AS TIMELINE
  FROM [physical_schema].[related_desc_table]
  WHERE TYPE_KEY = [related_key]
  -- ... UNION ALL for additional related attributes ...
)
, related_in_effect AS (
  SELECT
    [RELATED]_KEY, TYPE_KEY, EFF_TMSTP, VER_TMSTP, ROW_ST, [physical_column],
    RANK() OVER (PARTITION BY [RELATED]_KEY, EFF_TMSTP ORDER BY EFF_TMSTP DESC) AS RN
  FROM related_twine
)
, related_filtered AS (
  SELECT * FROM related_in_effect WHERE RN = 1
)
, CTE_[RELATED_ATOMIC_CONTEXT_NAME] AS (
  SELECT [RELATED]_KEY, EFF_TMSTP,
    CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [RELATED_ATTRIBUTE_NAME]
  FROM related_filtered
  WHERE TYPE_KEY = [related_key]
)
```

#### Final join: Composing the modules

Join the anchor's golden timeline to its own CTEs using carry-forward timestamps (standard Pattern 2), then bridge to the related entity via a **point-in-time LATERAL join**:

```sql
SELECT DISTINCT
  fie.[ANCHOR]_KEY,
  fie.EFF_TMSTP,
  cte1.[ATTRIBUTE_NAME_1],
  cte2.[ATTRIBUTE_NAME_2],
  -- ... anchor attributes ...
  cte_rel.[RELATED]_KEY,
  related_pn.[RELATED_ATTRIBUTE_NAME]
FROM filtered_in_effect fie
-- Anchor descriptor CTEs (standard carry-forward join)
LEFT JOIN CTE_[ATOMIC_CONTEXT_NAME_1] cte1
  ON fie.[ANCHOR]_KEY = cte1.[ANCHOR]_KEY
  AND fie.EFF_TMSTP_[ATOMIC_CONTEXT_NAME_1] = cte1.EFF_TMSTP
LEFT JOIN CTE_[ATOMIC_CONTEXT_NAME_2] cte2
  ON fie.[ANCHOR]_KEY = cte2.[ANCHOR]_KEY
  AND fie.EFF_TMSTP_[ATOMIC_CONTEXT_NAME_2] = cte2.EFF_TMSTP
-- ... one LEFT JOIN per anchor atomic context ...
-- Relationship CTE (carry-forward join — resolves which related entity was linked)
LEFT JOIN CTE_[RELATIONSHIP_NAME] cte_rel
  ON fie.[ANCHOR]_KEY = cte_rel.[ANCHOR]_KEY
  AND fie.EFF_TMSTP_[RELATIONSHIP_NAME] = cte_rel.EFF_TMSTP
-- Related entity attributes (point-in-time lookup via LATERAL)
LEFT JOIN LATERAL (
  SELECT [RELATED_ATTRIBUTE_NAME]
  FROM CTE_[RELATED_ATOMIC_CONTEXT_NAME]
  WHERE [RELATED]_KEY = cte_rel.[RELATED]_KEY
    AND EFF_TMSTP <= fie.EFF_TMSTP
  ORDER BY EFF_TMSTP DESC
  LIMIT 1
) related_pn ON TRUE
```

**How the LATERAL join works:** At each row on the anchor's golden timeline, the carry-forward has already resolved *which* related entity is linked (via `cte_rel.[RELATED]_KEY`). The LATERAL subquery then looks into the related entity's own history to find the attribute value that was in effect at that moment — the latest `EFF_TMSTP` that is `<=` the golden timeline's timestamp.

#### Cutoff date modifier

Add `AND EFF_TMSTP <= '<cutoff>'` to:
- Each UNION ALL member in the anchor `twine`
- Each UNION ALL member in the `related_twine`
- The LATERAL subquery's `WHERE` clause (already filtered by `<= fie.EFF_TMSTP`, which will be bounded by the cutoff)

#### Fidelity note

This pattern captures events from the **anchor entity's perspective**. If a related entity's attribute changes (e.g. product name updated) but nothing changes on the anchor side, that event will **not** appear as a new row on the golden timeline — the LATERAL lookup will resolve the updated name at the next anchor event.

For most analytical queries (revenue aggregation, status tracking), this is the correct behavior — the related entity's attributes serve as labels resolved at lookup time. If full fidelity is needed (a new timeline row for every change in any connected entity), the related entity's events must be projected onto the anchor's timeline by including them in the anchor's twine — but this requires resolving the relationship first, creating a two-pass approach.

#### Multiple relationships

If the query involves multiple relationship tables (e.g. ORDER → CUSTOMER and ORDER → EMPLOYEE), add each relationship as an additional UNION ALL member in the anchor twine with its own TIMELINE label, carry-forward column, and CTE. Each related entity gets its own independent history module and LATERAL join in the final SELECT.

#### Building this from the bootstrap

1. **Identify the anchor entity** from the user's question
2. **Anchor twine:** UNION ALL members from the anchor's `DESCRIPTOR_CONCEPT_NAME` (descriptor tables) + relationship tables where the anchor is the FOCAL01_KEY side. Include the related entity's key column as a value in the UNION ALL.
3. **Carry-forward:** One column per anchor atomic context + one per relationship
4. **Per-attribute CTEs:** Standard for descriptors; relationship CTE extracts the related key
5. **Related entity modules:** For each related entity, run a standard Pattern 2 history on its descriptor table
6. **Final join:** Anchor CTEs via carry-forward timestamps; related entity CTEs via LATERAL point-in-time lookup using the carried-forward related key

---

### Workaround: Fixing relationship EFF_TMSTP on PostgreSQL (daana-cli ≤ 0.5.18)

> **Temporary note.** As of daana-cli 0.5.18, the standard (non-focalc) installation does not apply `entity_effective_timestamp_expression` to relationship tables — they always receive `CURRENT_TIMESTAMP`. The experimental `--use-focalc` flag fixes this but does not fully populate the metadata layer. Until this is resolved in a future release, the workaround below can be used to patch relationship timestamps after execution.

**Prerequisites:**
- Source tables must have an `updated_at` column (or equivalent timestamp)
- The installation uses `allow_multiple_identifiers: false`, so entity keys in the DW match the natural business keys from the source

**Pattern:** For each relationship table, join back to the source table using the natural key and update `EFF_TMSTP`:

```sql
-- Relationship sourced from a table that has its own updated_at
-- Example: ORDER_CUSTOMER_X — order_key = source order_id
UPDATE daana_dw.[RELATIONSHIP_TABLE] rx
SET eff_tmstp = src.updated_at
FROM [source_schema].[source_table] src
WHERE rx.[FOCAL01_KEY] = CAST(src.[source_pk] AS VARCHAR);

-- Relationship sourced from a junction table with a composite key
-- Example: ORDER_LINE_PRODUCT_X — order_line_key = 'order_id|product_id'
-- The updated_at comes from a parent table (orders), so extract the FK
UPDATE daana_dw.[RELATIONSHIP_TABLE] rx
SET eff_tmstp = parent.updated_at
FROM [source_schema].[parent_table] parent
WHERE CAST(parent.[parent_pk] AS VARCHAR) = SPLIT_PART(rx.[FOCAL01_KEY], '|', 1);

-- Relationship where all rows share a fixed date
-- Example: TERRITORY_REGION_X — static reference data
UPDATE daana_dw.[RELATIONSHIP_TABLE] SET eff_tmstp = '[fixed_date]';
```

**Concrete Northwind examples:**

```sql
-- ORDER_CUSTOMER_X & ORDER_EMPLOYEE_X: use order_date
UPDATE daana_dw.order_customer_x rx
SET eff_tmstp = o.updated_at
FROM das.orders o WHERE rx.order_key = CAST(o.order_id AS VARCHAR);

UPDATE daana_dw.order_employee_x rx
SET eff_tmstp = o.updated_at
FROM das.orders o WHERE rx.order_key = CAST(o.order_id AS VARCHAR);

-- ORDER_LINE_ORDER_X & ORDER_LINE_PRODUCT_X: extract order_id from composite key
UPDATE daana_dw.order_line_order_x rx
SET eff_tmstp = o.updated_at
FROM das.orders o WHERE CAST(o.order_id AS VARCHAR) = SPLIT_PART(rx.order_line_key, '|', 1);

UPDATE daana_dw.order_line_product_x rx
SET eff_tmstp = o.updated_at
FROM das.orders o WHERE CAST(o.order_id AS VARCHAR) = SPLIT_PART(rx.order_line_key, '|', 1);

-- EMPLOYEE_TERRITORY_X: use employee's hire_date
UPDATE daana_dw.employee_territory_x rx
SET eff_tmstp = e.updated_at
FROM das.employees e WHERE rx.employee_key = CAST(e.employee_id AS VARCHAR);

-- TERRITORY_REGION_X: static — first hire date
UPDATE daana_dw.territory_region_x SET eff_tmstp = '1992-04-01';
```

**Important:** This is a post-execution patch — it must be re-applied after every `daana-cli execute`. It does not survive re-execution.

---

## Phase 5: Present Results

- Show the query results in a clear format
- If the result set is large, apply reasonable limits unless the user asks for everything
- Offer to refine: "Would you like to add more attributes or filter by a specific value?"

## Decision Tree Summary

```
User asks a question
  │
  ├─ Entity clear?
  │   ├─ YES → continue
  │   └─ NO → search FOCAL_NM, ask user to pick
  │
  ├─ Attributes clear?
  │   ├─ YES → search ATOM_CONTX_NM by keyword
  │   └─ NO → list available atomic contexts for entity, ask user to pick
  │
  ├─ Cross-entity data needed?
  │   ├─ YES → resolve relationship table + join
  │   └─ NO → single table query
  │
  └─ Which pattern?
      ├─ LATEST → Pattern 1: ROW_ST='Y' + RANK window (NBR=1) + pivot
      │   └─ Relationships use the same RANK pattern in their own CTE
      │
      └─ HISTORY
          ├─ Single entity? → Pattern 2: Temporal Alignment (carry-forward + per-attribute CTEs + join)
          └─ Cross-entity? → Pattern 3: Multi-Entity History
          │   ├─ Anchor descriptors + relationship → combined twine (same anchor key)
          │   ├─ Related entity descriptors → independent history module (own key)
          │   └─ Final join: carry-forward for anchor CTEs + LATERAL point-in-time for related CTEs
          │
          └─ Cutoff date?
              ├─ NO → use current data (no EFF_TMSTP filter)
              └─ YES → add EFF_TMSTP <= '<cutoff>' to twine CTEs + LATERAL WHERE clause
```

---

## End-to-End Worked Example

This example shows the full process from a vague user question to a final SQL query. The agent knows **nothing** about the data model in advance — it could be any domain (healthcare, logistics, finance, IoT, etc.).

### User says: "show me the total amount per supplier"

#### Step 1: Bootstrap

The agent runs the bootstrap query to discover the model:

```sql
SELECT
  fr.FOCAL_NAME, fr.FOCAL_PHYSICAL_SCHEMA,
  fr.DESCRIPTOR_CONCEPT_NAME, fr.ATOMIC_CONTEXT_NAME,
  fr.ATOM_CONTX_KEY, fr.ATTRIBUTE_NAME, fr.ATR_KEY,
  tcn.VAL_STR as PHYSICAL_COLUMN
FROM DAANA_METADATA.f_focal_read('9999-12-31') fr
LEFT JOIN DAANA_METADATA.LOGICAL_PHYSICAL_X lp
  ON lp.ATR_KEY = fr.ATR_KEY AND lp.ATOM_CONTX_KEY = fr.ATOM_CONTX_KEY AND lp.ROW_ST = 'Y'
LEFT JOIN DAANA_METADATA.TBL_PTRN_COL_NM tcn
  ON lp.TBL_PTRN_COL_KEY = tcn.TBL_PTRN_COL_KEY AND tcn.ROW_ST = 'Y'
WHERE fr.FOCAL_PHYSICAL_SCHEMA = '<data_layer_schema>'
ORDER BY fr.FOCAL_NAME, fr.DESCRIPTOR_CONCEPT_NAME, fr.ATOMIC_CONTEXT_NAME
```

The agent doesn't know the schema name yet either. It can discover it by first running without the `WHERE` filter, or by checking `FOCAL_PHYSICAL_SCHEMA` values in the unfiltered result.

#### Step 2: Examine the bootstrap result

Suppose the result contains these entities (this is hypothetical — the model is unknown):

```
FOCAL_NAME          | DESC_CONCEPT_NAME      | ATOMIC_CONTEXT_NAME              | ATOM_CONTX_KEY | ATTRIBUTE_NAME  | PHYSICAL_COLUMN
INVOICE_FOCAL       | INVOICE_DESC           | INVOICE_INVOICE_AMOUNT           | 42             | INVOICE_AMOUNT  | VAL_NUM
INVOICE_FOCAL       | INVOICE_DESC           | INVOICE_INVOICE_CURRENCY         | 43             | INVOICE_CURRENCY| VAL_STR
INVOICE_FOCAL       | INVOICE_SUPPLIER_X     | INVOICE_SUPPLIED_BY              | 50             | INVOICE_KEY     | FOCAL01_KEY
INVOICE_FOCAL       | INVOICE_SUPPLIER_X     | INVOICE_SUPPLIED_BY              | 50             | SUPPLIER_KEY    | FOCAL02_KEY
SUPPLIER_FOCAL      | SUPPLIER_DESC          | SUPPLIER_SUPPLIER_NAME           | 61             | SUPPLIER_NAME   | VAL_STR
SUPPLIER_FOCAL      | INVOICE_SUPPLIER_X     | INVOICE_SUPPLIED_BY              | 50             | INVOICE_KEY     | FOCAL01_KEY
SUPPLIER_FOCAL      | INVOICE_SUPPLIER_X     | INVOICE_SUPPLIED_BY              | 50             | SUPPLIER_KEY    | FOCAL02_KEY
```

#### Step 3: Match the user's question to the model

The agent matches keywords from "total amount per supplier":

- **"amount"** → matches `INVOICE_INVOICE_AMOUNT` (ATOM_CONTX_KEY = 42, stored in `VAL_NUM`)
- **"supplier"** → matches `SUPPLIER_FOCAL` entity, with `SUPPLIER_SUPPLIER_NAME` (ATOM_CONTX_KEY = 61, stored in `VAL_STR`)
- **"per supplier"** → requires a relationship. The bootstrap shows `INVOICE_SUPPLIER_X` links the two entities via `INVOICE_SUPPLIED_BY` (ATOM_CONTX_KEY = 50)

The agent now has ambiguity: does the user want SUM, AVG, or just a list? The word "total" suggests SUM. If unsure, it asks.

#### Step 4: Resolve relationship columns

From the bootstrap, the agent sees:
- `INVOICE_SUPPLIER_X` has `FOCAL01_KEY` → attribute name `INVOICE_KEY`
- `INVOICE_SUPPLIER_X` has `FOCAL02_KEY` → attribute name `SUPPLIER_KEY`

Since these are relationship columns, use `ATTRIBUTE_NAME` as the physical column (not `FOCAL01_KEY`/`FOCAL02_KEY`).

#### Step 5: Build the query

Every table — descriptors AND relationships — uses the same RANK pattern for latest queries:

```sql
WITH invoice_amount AS (
  SELECT
    INVOICE_KEY,
    MAX(CASE WHEN TYPE_KEY = 42 THEN VAL_NUM END) AS AMOUNT
  FROM (
    SELECT INVOICE_KEY, TYPE_KEY, ROW_ST, VAL_NUM,
      RANK() OVER (PARTITION BY INVOICE_KEY, TYPE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM <schema>.INVOICE_DESC
    WHERE TYPE_KEY = 42
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY INVOICE_KEY
),
invoice_supplier AS (
  SELECT INVOICE_KEY, SUPPLIER_KEY
  FROM (
    SELECT INVOICE_KEY, SUPPLIER_KEY, ROW_ST,
      RANK() OVER (PARTITION BY INVOICE_KEY, SUPPLIER_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM <schema>.INVOICE_SUPPLIER_X
    WHERE TYPE_KEY = 50
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
),
supplier_name AS (
  SELECT
    SUPPLIER_KEY,
    MAX(CASE WHEN TYPE_KEY = 61 THEN VAL_STR END) AS SUPPLIER_NAME
  FROM (
    SELECT SUPPLIER_KEY, TYPE_KEY, ROW_ST, VAL_STR,
      RANK() OVER (PARTITION BY SUPPLIER_KEY, TYPE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
    FROM <schema>.SUPPLIER_DESC
    WHERE TYPE_KEY = 61
  ) A
  WHERE NBR = 1 AND ROW_ST = 'Y'
  GROUP BY SUPPLIER_KEY
)
SELECT
  sn.SUPPLIER_NAME,
  SUM(ia.AMOUNT) AS TOTAL_AMOUNT
FROM invoice_amount ia
JOIN invoice_supplier isx
  ON ia.INVOICE_KEY = isx.INVOICE_KEY
JOIN supplier_name sn
  ON isx.SUPPLIER_KEY = sn.SUPPLIER_KEY
GROUP BY sn.SUPPLIER_NAME
ORDER BY TOTAL_AMOUNT DESC
```

#### Step 6: Present and refine

The agent runs the query and shows results. It might then ask:
- "Would you like to see this broken down by currency as well?"
- "Do you want only active invoices, or the full history?"

### Key takeaways from this example

1. **The agent never assumed any model structure.** Everything was discovered from the bootstrap.
2. **Entity names, attribute names, and column names were all different from any prior example.** The process works regardless of domain.
3. **The agent matched natural language to metadata names.** "amount" → `INVOICE_AMOUNT`, "supplier" → `SUPPLIER_NAME`. This matching is the core skill the agent needs.
4. **Relationship columns used `ATTRIBUTE_NAME`, not `PHYSICAL_COLUMN`.** The agent detected `FOCAL01_KEY`/`FOCAL02_KEY` and switched to attribute names.
5. **Every table uses the same RANK pattern.** Descriptors and relationship tables both use `RANK() OVER (...) + NBR = 1 + ROW_ST = 'Y'` in latest queries — relationships are temporal and must be resolved to their latest active state, not just filtered by `ROW_ST = 'Y'`.
6. **The agent asked clarifying questions** when "total" could mean different things.
