# USS SQL Patterns

This reference documents the SQL patterns for generating Unified Star Schema components from Focal-based data warehouses. All patterns use PostgreSQL syntax.

## Prerequisites

The bootstrap data from `f_focal_read()` must be available in context. Each bootstrap row provides:

| Column | Usage |
|--------|-------|
| `focal_name` | Entity identifier (e.g., `CUSTOMER_FOCAL`) |
| `descriptor_concept_name` | Physical table name (e.g., `CUSTOMER_DESC`) |
| `atomic_context_name` | TYPE_KEY meaning — used for column naming |
| `atom_contx_key` | Actual TYPE_KEY value for WHERE clauses |
| `attribute_name` | Logical attribute name within the atomic context |
| `table_pattern_column_name` | Physical column: `VAL_STR`, `VAL_NUM`, `STA_TMSTP`, `END_TMSTP`, `UOM`, `FOCAL01_KEY`, `FOCAL02_KEY` |

> **CRITICAL:** The source schema for all SQL is the `FOCAL_PHYSICAL_SCHEMA` value from the bootstrap (e.g., `daana_dw`). Use `{source_schema}` in all `FROM` clauses. **Never** hardcode `daana_dw` or use `focal` as a schema name.

## RANK Dedup Pattern (Base)

All USS patterns use the RANK window function to resolve the latest version of each row. This is the foundational CTE used throughout.

```sql
WITH ranked AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY {entity}_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{table}
    WHERE ROW_ST = 'Y'
),
deduped AS (
    SELECT *
    FROM ranked
    WHERE rnk = 1
)
```

**Key rules:**

- `PARTITION BY` always includes `{entity}_KEY` and `TYPE_KEY` — this ensures one latest row per entity per atomic context.
- `ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC` — effective timestamp first, then version timestamp as tiebreaker.
- `ROW_ST = 'Y'` — only active rows (snapshot mode). Historical mode omits this filter.

## Peripheral Pattern

Each peripheral is a complete entity view — ALL attributes regardless of type. It pivots typed rows from descriptor tables into a flat result with one row per entity.

### Single Descriptor Table

When an entity has one descriptor table, a single CTE with RANK dedup followed by a pivot produces the peripheral.

```sql
WITH ranked AS (
    SELECT
        {entity}_KEY,
        TYPE_KEY,
        VAL_STR,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        UOM,
        RANK() OVER (
            PARTITION BY {entity}_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{descriptor_table}
    WHERE ROW_ST = 'Y'
)
SELECT
    {entity}_KEY,
    MAX(CASE WHEN TYPE_KEY = {key_1} THEN {column_1} END) AS {attr_name_1},
    MAX(CASE WHEN TYPE_KEY = {key_2} THEN {column_2} END) AS {attr_name_2},
    MAX(CASE WHEN TYPE_KEY = {key_3} THEN {column_3} END) AS {attr_name_3}
FROM ranked
WHERE rnk = 1
GROUP BY {entity}_KEY
```

The `{column_N}` values come from `table_pattern_column_name` in the bootstrap (e.g., `VAL_STR`, `VAL_NUM`, `STA_TMSTP`). The `{key_N}` values come from `atom_contx_key`. The `{attr_name_N}` values are derived from `atomic_context_name` using this algorithm:

1. Take the `atomic_context_name` (e.g., `PRODUCT_PRODUCT_NAME`)
2. Identify the entity name — the `focal_name` without the `_FOCAL` suffix (e.g., `PRODUCT`)
3. Strip exactly one leading `{ENTITY}_` prefix (e.g., `PRODUCT_PRODUCT_NAME` → `PRODUCT_NAME`)
4. Lowercase the result → `product_name`

**Examples:**

| `atomic_context_name` | Entity | Strip prefix | Result |
|---|---|---|---|
| `PRODUCT_PRODUCT_NAME` | PRODUCT | `PRODUCT_NAME` | `product_name` |
| `PRODUCT_PRODUCT_LIST_PRICE` | PRODUCT | `PRODUCT_LIST_PRICE` | `product_list_price` |
| `STORE_STORE_NAME` | STORE | `STORE_NAME` | `store_name` |
| `CUSTOMER_CUSTOMER_FIRST_NAME` | CUSTOMER | `CUSTOMER_FIRST_NAME` | `customer_first_name` |
| `CUSTOMER_CUSTOMER_CITY` | CUSTOMER | `CUSTOMER_CITY` | `customer_city` |
| `ORDER_LINE_UNIT_PRICE` | ORDER_LINE | `UNIT_PRICE` | `unit_price` |

> **CRITICAL:** Strip only ONE leading `{ENTITY}_` prefix. Do NOT strip recursively. `PRODUCT_PRODUCT_NAME` → `product_name`, never `name`.

### Multiple Descriptor Tables

When an entity has attributes spread across multiple descriptor tables, create one CTE per table, then join them on the entity key.

```sql
WITH ranked_desc AS (
    SELECT
        {entity}_KEY,
        TYPE_KEY,
        VAL_STR,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        UOM,
        RANK() OVER (
            PARTITION BY {entity}_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{descriptor_table_1}
    WHERE ROW_ST = 'Y'
),
desc_pivoted AS (
    SELECT
        {entity}_KEY,
        MAX(CASE WHEN TYPE_KEY = {key_1} THEN {column_1} END) AS {attr_name_1},
        MAX(CASE WHEN TYPE_KEY = {key_2} THEN {column_2} END) AS {attr_name_2}
    FROM ranked_desc
    WHERE rnk = 1
    GROUP BY {entity}_KEY
),
ranked_desc2 AS (
    SELECT
        {entity}_KEY,
        TYPE_KEY,
        VAL_STR,
        VAL_NUM,
        RANK() OVER (
            PARTITION BY {entity}_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{descriptor_table_2}
    WHERE ROW_ST = 'Y'
),
desc2_pivoted AS (
    SELECT
        {entity}_KEY,
        MAX(CASE WHEN TYPE_KEY = {key_3} THEN {column_3} END) AS {attr_name_3}
    FROM ranked_desc2
    WHERE rnk = 1
    GROUP BY {entity}_KEY
)
SELECT
    d1.{entity}_KEY,
    d1.{attr_name_1},
    d1.{attr_name_2},
    d2.{attr_name_3}
FROM desc_pivoted d1
LEFT JOIN desc2_pivoted d2
    ON d1.{entity}_KEY = d2.{entity}_KEY
```

### Complete Example — CUSTOMER Peripheral

Bootstrap data for CUSTOMER_FOCAL (from CUSTOMER_DESC):

| atomic_context_name | atom_contx_key | attribute_name | table_pattern_column_name |
|---------------------|----------------|----------------|---------------------------|
| CUSTOMER_CUSTOMER_FIRST_NAME | 30 | CUSTOMER_FIRST_NAME | VAL_STR |
| CUSTOMER_CUSTOMER_LAST_NAME | 31 | CUSTOMER_LAST_NAME | VAL_STR |
| CUSTOMER_CUSTOMER_EMAIL_ADDRESS | 32 | CUSTOMER_EMAIL | VAL_STR |
| CUSTOMER_CUSTOMER_CITY | 33 | CUSTOMER_CITY | VAL_STR |

Generated SQL (`customer.sql`):

```sql
WITH ranked AS (
    SELECT
        CUSTOMER_KEY,
        TYPE_KEY,
        VAL_STR,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.CUSTOMER_DESC
    WHERE ROW_ST = 'Y'
)
SELECT
    CUSTOMER_KEY,
    MAX(CASE WHEN TYPE_KEY = 30 THEN VAL_STR END) AS customer_first_name,
    MAX(CASE WHEN TYPE_KEY = 31 THEN VAL_STR END) AS customer_last_name,
    MAX(CASE WHEN TYPE_KEY = 32 THEN VAL_STR END) AS customer_email,
    MAX(CASE WHEN TYPE_KEY = 33 THEN VAL_STR END) AS customer_city
FROM ranked
WHERE rnk = 1
GROUP BY CUSTOMER_KEY
```

### Surrogate Key and Versioning Layer

Every peripheral — regardless of SCD type — wraps its pivoted output with a surrogate integer key and a `-1` default row.

#### Type 1 (Latest Only)

One row per entity. The peripheral query from above is wrapped with `ROW_NUMBER()`:

```sql
, peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY {entity}_KEY) AS _peripheral_key,
        p.*
    FROM ({pivoted_query}) p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS {entity}_KEY,
    {NULL for each attribute column...}
```

- `_peripheral_key` is the surrogate integer key. Bridge `_key__` columns reference this, not the raw entity key.
- The `-1` default row catches bridge rows where the relationship lookup finds no match.
- `'UNKNOWN'` as the entity key follows the Star schema convention from teach_claude_focal.

#### Type 2 (Full History — Versioned Rows)

Multiple rows per entity with temporal ranges. Uses the carry-forward temporal alignment pattern, then adds version columns:

```sql
, peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY {entity}_KEY, EFF_TMSTP) AS _peripheral_key,
        {entity}_KEY,
        {attribute columns...},
        EFF_TMSTP AS effective_from,
        COALESCE(
            LEAD(EFF_TMSTP) OVER (
                PARTITION BY {entity}_KEY
                ORDER BY EFF_TMSTP
            ),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM ({pivoted_versioned_query}) p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS {entity}_KEY,
    {NULL for each attribute column...},
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to
```

- `effective_from` / `effective_to` enable point-in-time joins from the bridge.
- The `-1` default row spans all time (`1900-01-01` to `9999-12-31`).
- The bridge uses `COALESCE(p._peripheral_key, -1)` when a point-in-time lookup finds no matching version.

#### Consumer Join Pattern

Consumers join to peripherals via `_peripheral_key`, NOT via the raw entity key:

```sql
-- Type 1 peripheral (simple join)
LEFT JOIN uss.customer c ON b._key__customer = c._peripheral_key

-- Type 2 peripheral (same — _peripheral_key already resolved in bridge)
LEFT JOIN uss.product p ON b._key__product = p._peripheral_key
```

## Bridge Pattern — Event-Grain, Snapshot

The bridge UNION ALLs rows from **ALL entities** — both bridge sources and peripherals. Every entity in the USS participates in the bridge, making each entity both a fact (contributing rows) and a dimension (joinable via FK). Each entity contributes:
1. Resolved descriptor attributes (measures via RANK + pivot)
2. Resolved relationship keys (M:1 only, via RANK on relationship tables)
3. Unpivoted timestamps into `event` + `event_occurred_on`

### Step 1: Resolve Descriptors per Entity

For each bridge source entity, create a CTE that deduplicates and pivots the descriptor table. Extract both measures (VAL_NUM columns) and timestamps (STA_TMSTP, END_TMSTP columns).

```sql
ranked_{entity} AS (
    SELECT
        {entity}_KEY,
        TYPE_KEY,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        UOM,
        RANK() OVER (
            PARTITION BY {entity}_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{entity}_DESC
    WHERE ROW_ST = 'Y'
),
{entity}_attrs AS (
    SELECT
        {entity}_KEY,
        MAX(CASE WHEN TYPE_KEY = {measure_key_1} THEN VAL_NUM END) AS {measure_name_1},
        MAX(CASE WHEN TYPE_KEY = {measure_key_2} THEN VAL_NUM END) AS {measure_name_2},
        MAX(CASE WHEN TYPE_KEY = {ts_key_1} THEN STA_TMSTP END) AS {ts_name_1},
        MAX(CASE WHEN TYPE_KEY = {ts_key_2} THEN END_TMSTP END) AS {ts_name_2}
    FROM ranked_{entity}
    WHERE rnk = 1
    GROUP BY {entity}_KEY
)
```

### Step 2: Resolve Relationships (M:1 Only)

For each relationship table connecting a bridge source to a peripheral, create a RANK CTE. The `FOCAL01_KEY` side is the many (bridge source), the `FOCAL02_KEY` side is the one (peripheral).

> **CRITICAL — FOCAL01_KEY / FOCAL02_KEY ARE NOT COLUMN NAMES**
>
> In relationship tables, `FOCAL01_KEY` and `FOCAL02_KEY` are **pattern indicators** from the bootstrap, NOT physical column names. The actual column names are the `attribute_name` values:
>
> | Bootstrap `table_pattern_column_name` | Bootstrap `attribute_name` | Use in SQL |
> |---|---|---|
> | `FOCAL01_KEY` | `ORDER_LINE_KEY` | `SELECT ORDER_LINE_KEY FROM ...` |
> | `FOCAL02_KEY` | `ORDER_KEY` | `SELECT ORDER_KEY FROM ...` |
>
> **NEVER write `SELECT FOCAL01_KEY` or `SELECT FOCAL02_KEY`** — these columns do not exist in physical tables.

```sql
ranked_{rel_table} AS (
    SELECT
        {source_attr_name},   -- e.g., ORDER_LINE_KEY (the FOCAL01_KEY attribute)
        {target_attr_name},   -- e.g., ORDER_KEY (the FOCAL02_KEY attribute)
        RANK() OVER (
            PARTITION BY {source_attr_name}
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{relationship_table}
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = {rel_type_key}
),
{rel_alias} AS (
    SELECT
        {source_attr_name},
        {target_attr_name}
    FROM ranked_{rel_table}
    WHERE rnk = 1
)
```

**Fan-out prevention:** Only include relationships where the bridge source entity is on the `FOCAL01_KEY` side (many) and the peripheral is on the `FOCAL02_KEY` side (one). This ensures M:1 only — no fan-out. If an entity appears on `FOCAL01_KEY` of multiple relationships to the same entity, those are different relationship types (different TYPE_KEYs) and each should be a separate join.

### Step 3: Join Descriptors + Relationships

For each bridge source entity, join its descriptor CTE with all applicable relationship CTEs on the entity key.

```sql
{entity}_joined AS (
    SELECT
        a.{entity}_KEY,
        -- Measures
        a.{measure_name_1},
        a.{measure_name_2},
        -- Timestamps
        a.{ts_name_1},
        a.{ts_name_2},
        -- Relationship FKs (these become _key__{peripheral} in the bridge)
        r1.{target_attr_name_1} AS _key__{peripheral_1},
        r2.{target_attr_name_2} AS _key__{peripheral_2}
    FROM {entity}_attrs a
    LEFT JOIN {rel_alias_1} r1
        ON a.{entity}_KEY = r1.{source_attr_name_1}
    LEFT JOIN {rel_alias_2} r2
        ON a.{entity}_KEY = r2.{source_attr_name_2}
)
```

### Step 4: Unpivot Timestamps to Events

For each timestamp attribute (STA_TMSTP or END_TMSTP columns), generate event rows using `CROSS JOIN LATERAL` with a `VALUES` list.

```sql
{entity}_events AS (
    SELECT
        j.{entity}_KEY,
        -- Peripheral FK keys
        j._key__{peripheral_1},
        j._key__{peripheral_2},
        -- Measures
        j.{measure_name_1},
        j.{measure_name_2},
        -- Event columns
        e.event_name AS event,
        e.event_tmstp AS event_occurred_on,
        e.event_tmstp::date AS _key__dates,
        e.event_tmstp::time AS _key__times
    FROM {entity}_joined j
    CROSS JOIN LATERAL (
        VALUES
            ('{ts_name_1}', j.{ts_name_1}),
            ('{ts_name_2}', j.{ts_name_2})
    ) AS e(event_name, event_tmstp)
    WHERE e.event_tmstp IS NOT NULL
)
```

The `WHERE e.event_tmstp IS NOT NULL` filters out timestamps that are not populated for a given row.

Derive join keys from the event timestamp:
- `_key__dates` = `event_occurred_on::date` — joins to the `_dates` synthetic peripheral
- `_key__times` = `event_occurred_on::time` — joins to the `_times` synthetic peripheral

### Step 5: UNION ALL Across Entities

Combine **ALL entity** CTEs (bridge sources AND peripherals) into the final bridge via UNION ALL. Every entity contributes rows — bridge sources contribute their measures and timestamps, peripherals contribute their entity key (with NULL measures/timestamps). Add a `peripheral` column to identify the source entity. NULL-pad columns that don't exist in a given entity.

```sql
SELECT
    '{entity_1_name}' AS peripheral,
    {entity_1}_KEY AS _key__{entity_1},
    NULL::bigint AS _key__{entity_2},
    _key__{peripheral_1},
    _key__{peripheral_2},
    event,
    event_occurred_on,
    _key__dates,
    _key__times,
    _measure__{entity_1}__{measure_1} AS _measure__{entity_1}__{measure_1},
    _measure__{entity_1}__{measure_2} AS _measure__{entity_1}__{measure_2},
    NULL::numeric AS _measure__{entity_2}__{measure_3}
FROM {entity_1}_events

UNION ALL

SELECT
    '{entity_2_name}' AS peripheral,
    NULL::bigint AS _key__{entity_1},
    {entity_2}_KEY AS _key__{entity_2},
    _key__{peripheral_1},
    NULL::bigint AS _key__{peripheral_2},
    event,
    event_occurred_on,
    _key__dates,
    _key__times,
    NULL::numeric AS _measure__{entity_1}__{measure_1},
    NULL::numeric AS _measure__{entity_1}__{measure_2},
    _measure__{entity_2}__{measure_3} AS _measure__{entity_2}__{measure_3}
FROM {entity_2}_events
```

**Column alignment rules:**
- Every entity contributes the same column set in every UNION ALL member.
- Missing FK keys are `NULL::bigint`.
- Missing measures are `NULL::numeric`.
- `peripheral`, `event`, `event_occurred_on`, `_key__dates`, `_key__times` are always present.

### Complete Example — Event-Grain, Snapshot Bridge

Domain: ORDER_LINE and ORDER are bridge sources. ORDER_LINE has measures (unit_price, quantity, discount). ORDER has timestamps (order_placed_on, order_required_by). ORDER_LINE relates to ORDER (M:1) and PRODUCT (M:1). ORDER relates to CUSTOMER (M:1).

Bootstrap data used:

| focal_name | descriptor_concept_name | atomic_context_name | atom_contx_key | attribute_name | table_pattern_column_name |
|---|---|---|---|---|---|
| ORDER_LINE_FOCAL | ORDER_LINE_DESC | ORDER_LINE_UNIT_PRICE | 40 | UNIT_PRICE | VAL_NUM |
| ORDER_LINE_FOCAL | ORDER_LINE_DESC | ORDER_LINE_QUANTITY | 41 | QUANTITY | VAL_NUM |
| ORDER_LINE_FOCAL | ORDER_LINE_DESC | ORDER_LINE_DISCOUNT | 42 | DISCOUNT | VAL_NUM |
| ORDER_LINE_FOCAL | ORDER_LINE_ORDER_X | ORDER_LINE_BELONGS_TO_ORDER | 50 | ORDER_LINE_KEY | FOCAL01_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_ORDER_X | ORDER_LINE_BELONGS_TO_ORDER | 50 | ORDER_KEY | FOCAL02_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_PRODUCT_X | ORDER_LINE_FOR_PRODUCT | 51 | ORDER_LINE_KEY | FOCAL01_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_PRODUCT_X | ORDER_LINE_FOR_PRODUCT | 51 | PRODUCT_KEY | FOCAL02_KEY |
| ORDER_FOCAL | ORDER_DESC | ORDER_ORDER_PLACED_ON | 60 | ORDER_PLACED_ON | STA_TMSTP |
| ORDER_FOCAL | ORDER_DESC | ORDER_ORDER_REQUIRED_BY | 61 | ORDER_REQUIRED_BY | STA_TMSTP |
| ORDER_FOCAL | ORDER_CUSTOMER_X | ORDER_BOUGHT_BY_CUSTOMER | 70 | ORDER_KEY | FOCAL01_KEY |
| ORDER_FOCAL | ORDER_CUSTOMER_X | ORDER_BOUGHT_BY_CUSTOMER | 70 | CUSTOMER_KEY | FOCAL02_KEY |

Generated SQL (`_bridge.sql`):

```sql
WITH
-- ============================================================
-- ORDER_LINE: Resolve descriptors (measures only, no timestamps)
-- ============================================================
ranked_order_line AS (
    SELECT
        ORDER_LINE_KEY,
        TYPE_KEY,
        VAL_NUM,
        RANK() OVER (
            PARTITION BY ORDER_LINE_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_LINE_DESC
    WHERE ROW_ST = 'Y'
),
order_line_attrs AS (
    SELECT
        ORDER_LINE_KEY,
        MAX(CASE WHEN TYPE_KEY = 40 THEN VAL_NUM END) AS unit_price,
        MAX(CASE WHEN TYPE_KEY = 41 THEN VAL_NUM END) AS quantity,
        MAX(CASE WHEN TYPE_KEY = 42 THEN VAL_NUM END) AS discount
    FROM ranked_order_line
    WHERE rnk = 1
    GROUP BY ORDER_LINE_KEY
),

-- ============================================================
-- ORDER_LINE: Resolve relationships (M:1)
-- ============================================================
ranked_order_line_order_x AS (
    SELECT
        ORDER_LINE_KEY,
        ORDER_KEY,
        RANK() OVER (
            PARTITION BY ORDER_LINE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_LINE_ORDER_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 50
),
rel_order_line_order AS (
    SELECT ORDER_LINE_KEY, ORDER_KEY
    FROM ranked_order_line_order_x
    WHERE rnk = 1
),
ranked_order_line_product_x AS (
    SELECT
        ORDER_LINE_KEY,
        PRODUCT_KEY,
        RANK() OVER (
            PARTITION BY ORDER_LINE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_LINE_PRODUCT_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 51
),
rel_order_line_product AS (
    SELECT ORDER_LINE_KEY, PRODUCT_KEY
    FROM ranked_order_line_product_x
    WHERE rnk = 1
),

-- ============================================================
-- ORDER_LINE: Join descriptors + relationships
-- ============================================================
order_line_joined AS (
    SELECT
        a.ORDER_LINE_KEY,
        a.unit_price,
        a.quantity,
        a.discount,
        r_ord.ORDER_KEY AS _key__order,
        r_prd.PRODUCT_KEY AS _key__product
    FROM order_line_attrs a
    LEFT JOIN rel_order_line_order r_ord
        ON a.ORDER_LINE_KEY = r_ord.ORDER_LINE_KEY
    LEFT JOIN rel_order_line_product r_prd
        ON a.ORDER_LINE_KEY = r_prd.ORDER_LINE_KEY
),

-- ============================================================
-- ORDER: Resolve descriptors (timestamps only, no measures)
-- ============================================================
ranked_order AS (
    SELECT
        ORDER_KEY,
        TYPE_KEY,
        STA_TMSTP,
        RANK() OVER (
            PARTITION BY ORDER_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_DESC
    WHERE ROW_ST = 'Y'
),
order_attrs AS (
    SELECT
        ORDER_KEY,
        MAX(CASE WHEN TYPE_KEY = 60 THEN STA_TMSTP END) AS order_placed_on,
        MAX(CASE WHEN TYPE_KEY = 61 THEN STA_TMSTP END) AS order_required_by
    FROM ranked_order
    WHERE rnk = 1
    GROUP BY ORDER_KEY
),

-- ============================================================
-- ORDER: Resolve relationships (M:1)
-- ============================================================
ranked_order_customer_x AS (
    SELECT
        ORDER_KEY,
        CUSTOMER_KEY,
        RANK() OVER (
            PARTITION BY ORDER_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_CUSTOMER_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 70
),
rel_order_customer AS (
    SELECT ORDER_KEY, CUSTOMER_KEY
    FROM ranked_order_customer_x
    WHERE rnk = 1
),

-- ============================================================
-- ORDER: Join descriptors + relationships
-- ============================================================
order_joined AS (
    SELECT
        o.ORDER_KEY,
        o.order_placed_on,
        o.order_required_by,
        r_cust.CUSTOMER_KEY AS _key__customer
    FROM order_attrs o
    LEFT JOIN rel_order_customer r_cust
        ON o.ORDER_KEY = r_cust.ORDER_KEY
),

-- ============================================================
-- ORDER_LINE: No timestamps directly — inherit from ORDER via relationship
-- We join ORDER_LINE to ORDER to get timestamps for unpivoting
-- ============================================================
order_line_with_order AS (
    SELECT
        ol.ORDER_LINE_KEY,
        ol._key__order,
        ol._key__product,
        ol.unit_price,
        ol.quantity,
        ol.discount,
        oj._key__customer,
        oj.order_placed_on,
        oj.order_required_by
    FROM order_line_joined ol
    LEFT JOIN order_joined oj
        ON ol._key__order = oj.ORDER_KEY
),

-- ============================================================
-- ORDER_LINE: Unpivot timestamps to events
-- ============================================================
order_line_events AS (
    SELECT
        ol.ORDER_LINE_KEY,
        ol._key__order,
        ol._key__product,
        ol._key__customer,
        ol.unit_price AS _measure__order_line__unit_price,
        ol.quantity AS _measure__order_line__quantity,
        ol.discount AS _measure__order_line__discount,
        e.event_name AS event,
        e.event_tmstp AS event_occurred_on,
        e.event_tmstp::date AS _key__dates,
        e.event_tmstp::time AS _key__times
    FROM order_line_with_order ol
    CROSS JOIN LATERAL (
        VALUES
            ('order_placed_on', ol.order_placed_on),
            ('order_required_by', ol.order_required_by)
    ) AS e(event_name, event_tmstp)
    WHERE e.event_tmstp IS NOT NULL
),

-- ============================================================
-- ORDER: Unpivot timestamps to events
-- ============================================================
order_events AS (
    SELECT
        oj.ORDER_KEY,
        oj._key__customer,
        oj.order_placed_on,
        oj.order_required_by,
        e.event_name AS event,
        e.event_tmstp AS event_occurred_on,
        e.event_tmstp::date AS _key__dates,
        e.event_tmstp::time AS _key__times
    FROM order_joined oj
    CROSS JOIN LATERAL (
        VALUES
            ('order_placed_on', oj.order_placed_on),
            ('order_required_by', oj.order_required_by)
    ) AS e(event_name, event_tmstp)
    WHERE e.event_tmstp IS NOT NULL
)

-- ============================================================
-- UNION ALL: Combine all entities into the bridge
-- ============================================================
SELECT
    'order_line' AS peripheral,
    ORDER_LINE_KEY AS _key__order_line,
    _key__order,
    _key__product,
    _key__customer,
    event,
    event_occurred_on,
    _key__dates,
    _key__times,
    _measure__order_line__unit_price,
    _measure__order_line__quantity,
    _measure__order_line__discount
FROM order_line_events

UNION ALL

SELECT
    'order' AS peripheral,
    NULL::bigint AS _key__order_line,
    ORDER_KEY AS _key__order,
    NULL::bigint AS _key__product,
    _key__customer,
    event,
    event_occurred_on,
    _key__dates,
    _key__times,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount
FROM order_events
```

**Multi-hop relationship chains:** ORDER_LINE does not directly relate to CUSTOMER. The chain is ORDER_LINE → ORDER → CUSTOMER. The bridge resolves this by joining ORDER_LINE to ORDER (via the ORDER_LINE_ORDER_X relationship), and then inheriting ORDER's CUSTOMER_KEY. This means the `order_line_with_order` CTE joins the ORDER_LINE's relationships with ORDER's resolved relationships.

## Bridge Pattern — Event-Grain, Historical

Same structure as snapshot but with these changes:

### 1. Remove RANK dedup — keep all versions

Replace the `ROW_ST = 'Y'` filter and RANK pattern with inclusion of all rows:

```sql
ranked_{entity} AS (
    SELECT
        {entity}_KEY,
        TYPE_KEY,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        EFF_TMSTP,
        ROW_ST,
        RANK() OVER (
            PARTITION BY {entity}_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.{entity}_DESC
    -- No ROW_ST filter — include all rows to track deletions
)
```

Note: We still RANK by `VER_TMSTP DESC` within each `EFF_TMSTP` to handle re-deliveries, but we keep all `EFF_TMSTP` values.

### 2. Add valid_from / valid_to columns

Use `LEAD` window function to compute `valid_to` from the next row's `EFF_TMSTP`:

```sql
{entity}_versioned AS (
    SELECT
        {entity}_KEY,
        {measure_name_1},
        {ts_name_1},
        _key__{peripheral},
        EFF_TMSTP AS valid_from,
        COALESCE(
            LEAD(EFF_TMSTP) OVER (
                PARTITION BY {entity}_KEY
                ORDER BY EFF_TMSTP
            ),
            '9999-12-31'::timestamp
        ) AS valid_to
    FROM {entity}_joined
)
```

### 2a. Temporal Peripheral FK Keys

When historical mode is selected, the bridge's FK to each peripheral must include the peripheral's `valid_from` so consumers can perform point-in-time joins. For each peripheral FK column `_key__{peripheral}`, also include `_valid_from__{peripheral}`:

```sql
-- In the bridge output, for each temporal peripheral:
_key__{peripheral},
_valid_from__{peripheral},   -- peripheral's valid_from for point-in-time join
```

This enables the consumer join pattern:

```sql
JOIN uss.product p ON b._key__product = p.PRODUCT_KEY
    AND b._valid_from__product = p.valid_from
```

> **Note:** Only add `_valid_from__{peripheral}` columns when historical mode is selected. In snapshot mode, there is only one version per entity key, so the simple FK join is sufficient.

### 3. Include ROW_ST in output for deletion tracking

When `ROW_ST = 'N'`, NULL out measures and timestamps so downstream consumers see the value disappearing at that point in time:

```sql
CASE WHEN ROW_ST = 'Y' THEN VAL_NUM END AS {measure_name}
```

### 4. Bridge output adds valid_from and valid_to

```sql
SELECT
    '{entity_name}' AS peripheral,
    ...
    event,
    event_occurred_on,
    _key__dates,
    _key__times,
    valid_from,
    valid_to,
    ...measures...
FROM {entity}_events
```

## Bridge Pattern — Columnar, Snapshot

Same as event-grain snapshot but timestamps stay as named columns instead of being unpivoted.

### Key differences from event-grain

1. **No unpivot step** — Skip Step 4 entirely. Timestamps remain as named columns.
2. **No `event` or `event_occurred_on` columns** — These only exist in event-grain mode.
3. **No `_key__dates` or `_key__times` columns** — No synthetic date/time peripherals.
4. **No synthetic date/time peripheral files** — `_dates.sql` and `_times.sql` are not generated.

```sql
-- Instead of unpivot, the joined CTE goes directly to UNION ALL
SELECT
    'order_line' AS peripheral,
    ol.ORDER_LINE_KEY AS _key__order_line,
    NULL::bigint AS _key__order,
    ol._key__order,
    ol._key__product,
    ol._key__customer,
    ol.order_placed_on,
    ol.order_required_by,
    ol.unit_price AS _measure__order_line__unit_price,
    ol.quantity AS _measure__order_line__quantity,
    ol.discount AS _measure__order_line__discount
FROM order_line_with_order ol

UNION ALL

SELECT
    'order' AS peripheral,
    NULL::bigint AS _key__order_line,
    oj.ORDER_KEY AS _key__order,
    oj.ORDER_KEY AS _key__order,
    NULL::bigint AS _key__product,
    oj._key__customer,
    oj.order_placed_on,
    oj.order_required_by,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount
FROM order_joined oj
```

## Bridge Pattern — Columnar, Historical

Combination of columnar (no unpivot) + historical (valid_from/valid_to, no ROW_ST filter). Apply both sets of changes:

- Timestamps stay as named columns (no event/event_occurred_on)
- No _key__dates or _key__times
- No ROW_ST = 'Y' filter (keep all versions)
- RANK within each EFF_TMSTP by VER_TMSTP DESC only
- Add `valid_from` and `valid_to` columns via LEAD window

```sql
SELECT
    'order_line' AS peripheral,
    ol.ORDER_LINE_KEY AS _key__order_line,
    ol._key__order,
    ol._key__product,
    ol._key__customer,
    ol.order_placed_on,
    ol.order_required_by,
    ol._measure__order_line__unit_price,
    ol._measure__order_line__quantity,
    ol._measure__order_line__discount,
    ol.valid_from,
    ol.valid_to
FROM order_line_versioned ol

UNION ALL

SELECT
    'order' AS peripheral,
    NULL::bigint AS _key__order_line,
    oj.ORDER_KEY AS _key__order,
    NULL::bigint AS _key__product,
    oj._key__customer,
    oj.order_placed_on,
    oj.order_required_by,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount,
    oj.valid_from,
    oj.valid_to
FROM order_versioned oj
```

## Synthetic Date Peripheral (`_dates.sql`)

Date spine generated from bridge data. Depends on `_bridge` existing first to determine the min/max year range.

```sql
WITH date_range AS (
    SELECT
        DATE_TRUNC('year', MIN(event_occurred_on))::date AS start_date,
        (DATE_TRUNC('year', MAX(event_occurred_on)) + INTERVAL '1 year' - INTERVAL '1 day')::date AS end_date
    FROM {schema}._bridge
),
date_spine AS (
    SELECT
        d::date AS date_key
    FROM date_range,
         GENERATE_SERIES(date_range.start_date, date_range.end_date, '1 day'::interval) AS d
)
SELECT
    date_key AS _key__dates,
    EXTRACT(YEAR FROM date_key)::int AS year,
    EXTRACT(QUARTER FROM date_key)::int AS quarter,
    EXTRACT(MONTH FROM date_key)::int AS month,
    TO_CHAR(date_key, 'Month') AS month_name,
    EXTRACT(DAY FROM date_key)::int AS day_of_month,
    EXTRACT(ISODOW FROM date_key)::int AS day_of_week,
    TO_CHAR(date_key, 'Day') AS day_name,
    EXTRACT(DOY FROM date_key)::int AS day_of_year,
    EXTRACT(WEEK FROM date_key)::int AS iso_week,
    CASE
        WHEN EXTRACT(ISODOW FROM date_key) IN (6, 7) THEN FALSE
        ELSE TRUE
    END AS is_weekday
FROM date_spine
ORDER BY date_key
```

**Notes:**
- `_key__dates` matches the `_key__dates` column in the bridge (`event_occurred_on::date`).
- The date range is derived from the bridge's `event_occurred_on` — no hardcoded years.
- For columnar mode bridges (no `event_occurred_on`), this file is NOT generated.

## Synthetic Time Peripheral (`_times.sql`)

Time-of-day at second grain. Produces 86,400 rows (24 hours x 60 minutes x 60 seconds). Independent of bridge data.

```sql
WITH time_spine AS (
    SELECT
        (INTERVAL '0 seconds' + (s || ' seconds')::interval)::time AS time_key
    FROM GENERATE_SERIES(0, 86399) AS s
)
SELECT
    time_key AS _key__times,
    EXTRACT(HOUR FROM time_key)::int AS hour,
    EXTRACT(MINUTE FROM time_key)::int AS minute,
    EXTRACT(SECOND FROM time_key)::int AS second,
    CASE
        WHEN EXTRACT(HOUR FROM time_key) < 6 THEN 'Night'
        WHEN EXTRACT(HOUR FROM time_key) < 12 THEN 'Morning'
        WHEN EXTRACT(HOUR FROM time_key) < 18 THEN 'Afternoon'
        ELSE 'Evening'
    END AS day_part
FROM time_spine
ORDER BY time_key
```

**Notes:**
- `_key__times` matches the `_key__times` column in the bridge (`event_occurred_on::time`).
- For columnar mode bridges (no `event_occurred_on`), this file is NOT generated.

## Fan-Out Prevention

### Detecting Relationship Cardinality from Bootstrap

The bootstrap's `table_pattern_column_name` tells you which side of a relationship each entity is on:

- `FOCAL01_KEY` = the **many** side (source/driving entity)
- `FOCAL02_KEY` = the **one** side (target/referenced entity)

### Decision Rules

For each relationship table in the bootstrap:

1. **Identify the sides.** Find the two rows for the same `atom_contx_key` — one with `FOCAL01_KEY` and one with `FOCAL02_KEY`.

2. **Check if the bridge source is on FOCAL01_KEY side.** If yes, this is a valid M:1 relationship — include it. The FOCAL02_KEY entity becomes a peripheral FK in the bridge.

3. **Check for M:M.** If both entities in a relationship are bridge sources (i.e., both appear on the FOCAL01_KEY side of different relationships), this is an M:M relationship. **Exclude it** from the bridge and warn the user.

### Example Detection

Given bootstrap rows:

| descriptor_concept_name | atom_contx_key | attribute_name | table_pattern_column_name |
|---|---|---|---|
| ORDER_LINE_ORDER_X | 50 | ORDER_LINE_KEY | FOCAL01_KEY |
| ORDER_LINE_ORDER_X | 50 | ORDER_KEY | FOCAL02_KEY |

- ORDER_LINE is on the FOCAL01_KEY side (many)
- ORDER is on the FOCAL02_KEY side (one)
- Result: ORDER_LINE → ORDER is M:1. Include in bridge. ORDER becomes a peripheral (or bridge source with its own relationships).

### Multi-Hop Chain Resolution

When a bridge source entity (e.g., ORDER_LINE) has a M:1 relationship to another bridge source (e.g., ORDER), and ORDER itself has M:1 relationships (e.g., ORDER → CUSTOMER):

1. Resolve ORDER_LINE → ORDER relationship (get ORDER_KEY)
2. Use that ORDER_KEY to inherit ORDER's relationships (ORDER → CUSTOMER gives CUSTOMER_KEY)
3. Both ORDER_KEY and CUSTOMER_KEY appear as FK columns in ORDER_LINE's bridge rows

This is implemented in the `order_line_with_order` CTE in the complete example above — join through intermediate entities to resolve the full chain.

### Recursive Peripheral Discovery

The USS requires **every entity reachable via M:1 chains** to be included — both as a peripheral (joinable dimension) and as a bridge participant (contributing rows). Use this algorithm to discover all peripherals:

**Algorithm:**

1. **Initialize** — Start with the set of bridge source entities selected by the user.
2. **Collect direct M:1 targets** — For each entity in the working set, find all relationship tables where it appears on the `FOCAL01_KEY` side. The `FOCAL02_KEY` entity is a peripheral. Add it to the peripheral set.
3. **Recurse** — For each newly discovered peripheral, repeat step 2. Check if the peripheral has its own M:1 relationships (i.e., it appears on the `FOCAL01_KEY` side of other relationship tables). If yes, add the targets to the peripheral set.
4. **Terminate** — Stop when no new entities are discovered.
5. **Result** — The peripheral set contains ALL entities that should be generated as peripheral SQL files AND included in the bridge UNION ALL.

**Example — Adventure Works:**

Starting bridge sources: `SALES_ORDER_DETAIL`, `SALES_ORDER`, `PURCHASE_ORDER`, `WORK_ORDER`

| Iteration | Entity examined | M:1 targets found | New peripherals |
|---|---|---|---|
| 1 | SALES_ORDER_DETAIL | SALES_ORDER, PRODUCT, SPECIAL_OFFER | PRODUCT, SPECIAL_OFFER |
| 1 | SALES_ORDER | CUSTOMER, SALES_PERSON, SALES_TERRITORY, ADDRESS | CUSTOMER, SALES_PERSON, SALES_TERRITORY, ADDRESS |
| 1 | PURCHASE_ORDER | EMPLOYEE, VENDOR | EMPLOYEE, VENDOR |
| 1 | WORK_ORDER | PRODUCT | (already found) |
| 2 | PRODUCT | (no M:1 relationships) | — |
| 2 | SPECIAL_OFFER | (no M:1 relationships) | — |
| 2 | CUSTOMER | PERSON, SALES_TERRITORY, STORE | PERSON, STORE |
| 2 | SALES_PERSON | EMPLOYEE, SALES_TERRITORY | (already found) |
| 2 | SALES_TERRITORY | (no M:1 relationships) | — |
| 2 | ADDRESS | (no M:1 relationships) | — |
| 2 | EMPLOYEE | PERSON | (already found) |
| 2 | VENDOR | PERSON | (already found) |
| 3 | PERSON | (no M:1 relationships) | — |
| 3 | STORE | SALES_PERSON | (already found) |

**Final peripheral set:** PRODUCT, SPECIAL_OFFER, CUSTOMER, SALES_PERSON, SALES_TERRITORY, ADDRESS, EMPLOYEE, VENDOR, PERSON, STORE

**All entities in bridge UNION ALL:** SALES_ORDER_DETAIL, SALES_ORDER, PURCHASE_ORDER, WORK_ORDER, PRODUCT, SPECIAL_OFFER, CUSTOMER, SALES_PERSON, SALES_TERRITORY, ADDRESS, EMPLOYEE, VENDOR, PERSON, STORE

### Peripheral Bridge Rows

Peripheral entities contribute rows to the bridge just like bridge sources, but they typically have no measures or timestamps. Their bridge rows contain:

- `peripheral` = entity name (e.g., `'customer'`)
- `_key__{entity}` = entity key (e.g., `CUSTOMER_KEY`)
- All other `_key__*` columns = their own M:1 relationship targets (e.g., `_key__person`, `_key__store`) or NULL
- All `_measure__*` columns = NULL
- `event` / `event_occurred_on` / `_key__dates` / `_key__times` = NULL (unless the peripheral has timestamps)

This means consumers can query `WHERE peripheral = 'customer'` to get one row per customer with all their relationship keys resolved — enabling customer-centric analysis without joining through the bridge sources.

## DDL Wrapping

### View

```sql
CREATE OR REPLACE VIEW {schema}.{name} AS
-- ... select statement ...
;
```

### Table

```sql
CREATE TABLE {schema}.{name} AS
-- ... select statement ...
;
```

The `{schema}` is determined from the user's connection profile or asked during the interview. The `{name}` follows the file naming conventions (e.g., `customer`, `_bridge`, `_dates`, `_times`).

## Common Mistakes

### Mistake 1: Using FOCAL01_KEY / FOCAL02_KEY as column names

**Wrong:**
```sql
SELECT FOCAL01_KEY, FOCAL02_KEY FROM {source_schema}.ORDER_LINE_ORDER_X
```

**Correct:**
```sql
-- Use attribute_name from bootstrap, not table_pattern_column_name
SELECT ORDER_LINE_KEY, ORDER_KEY FROM {source_schema}.ORDER_LINE_ORDER_X
```

The bootstrap's `table_pattern_column_name` tells you the ROLE (`FOCAL01_KEY` = many side, `FOCAL02_KEY` = one side). The `attribute_name` tells you the ACTUAL COLUMN NAME.

### Mistake 2: Using wrong schema name

**Wrong:**
```sql
SELECT * FROM focal.CUSTOMER_DESC
```

**Correct:**
```sql
-- Use FOCAL_PHYSICAL_SCHEMA from bootstrap
SELECT * FROM {source_schema}.CUSTOMER_DESC
```

### Mistake 3: Over-stripping column names

**Wrong:** `PRODUCT_PRODUCT_NAME` → `name`

**Correct:** `PRODUCT_PRODUCT_NAME` → `product_name` (strip entity prefix exactly once)
