# USS Worked Example

This reference walks through a complete USS generation from bootstrap data to final SQL files, using an e-commerce domain.

## Domain

Four entities with the following business attributes:

- **ORDER** — timestamps: `order_placed_on`, `order_required_by`; no numeric measures
- **ORDER_LINE** — numeric measures: `unit_price`, `quantity`, `discount`; no timestamps directly
- **CUSTOMER** — strings: `first_name`, `last_name`, `email`, `city`
- **PRODUCT** — strings: `product_name`, `category`; numeric: `list_price`

Relationships (all M:1):

- ORDER_LINE → ORDER (via `ORDER_LINE_ORDER_X`)
- ORDER → CUSTOMER (via `ORDER_CUSTOMER_X`)
- ORDER_LINE → PRODUCT (via `ORDER_LINE_PRODUCT_X`)

## 1. Sample Bootstrap Output

This is what the focal agent returns after running `f_focal_read()`:

| focal_name | descriptor_concept_name | atomic_context_name | atom_contx_key | attribute_name | table_pattern_column_name |
|---|---|---|---|---|---|
| CUSTOMER_FOCAL | CUSTOMER_DESC | CUSTOMER_CUSTOMER_FIRST_NAME | 30 | CUSTOMER_FIRST_NAME | VAL_STR |
| CUSTOMER_FOCAL | CUSTOMER_DESC | CUSTOMER_CUSTOMER_LAST_NAME | 31 | CUSTOMER_LAST_NAME | VAL_STR |
| CUSTOMER_FOCAL | CUSTOMER_DESC | CUSTOMER_CUSTOMER_EMAIL_ADDRESS | 32 | CUSTOMER_EMAIL | VAL_STR |
| CUSTOMER_FOCAL | CUSTOMER_DESC | CUSTOMER_CUSTOMER_CITY | 33 | CUSTOMER_CITY | VAL_STR |
| PRODUCT_FOCAL | PRODUCT_DESC | PRODUCT_PRODUCT_NAME | 34 | PRODUCT_NAME | VAL_STR |
| PRODUCT_FOCAL | PRODUCT_DESC | PRODUCT_PRODUCT_CATEGORY | 35 | PRODUCT_CATEGORY | VAL_STR |
| PRODUCT_FOCAL | PRODUCT_DESC | PRODUCT_PRODUCT_LIST_PRICE | 36 | PRODUCT_LIST_PRICE | VAL_NUM |
| ORDER_FOCAL | ORDER_DESC | ORDER_ORDER_PLACED_ON | 60 | ORDER_PLACED_ON | STA_TMSTP |
| ORDER_FOCAL | ORDER_DESC | ORDER_ORDER_REQUIRED_BY | 61 | ORDER_REQUIRED_BY | STA_TMSTP |
| ORDER_FOCAL | ORDER_CUSTOMER_X | ORDER_BOUGHT_BY_CUSTOMER | 70 | ORDER_KEY | FOCAL01_KEY |
| ORDER_FOCAL | ORDER_CUSTOMER_X | ORDER_BOUGHT_BY_CUSTOMER | 70 | CUSTOMER_KEY | FOCAL02_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_DESC | ORDER_LINE_UNIT_PRICE | 40 | UNIT_PRICE | VAL_NUM |
| ORDER_LINE_FOCAL | ORDER_LINE_DESC | ORDER_LINE_QUANTITY | 41 | QUANTITY | VAL_NUM |
| ORDER_LINE_FOCAL | ORDER_LINE_DESC | ORDER_LINE_DISCOUNT | 42 | DISCOUNT | VAL_NUM |
| ORDER_LINE_FOCAL | ORDER_LINE_ORDER_X | ORDER_LINE_BELONGS_TO_ORDER | 50 | ORDER_LINE_KEY | FOCAL01_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_ORDER_X | ORDER_LINE_BELONGS_TO_ORDER | 50 | ORDER_KEY | FOCAL02_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_PRODUCT_X | ORDER_LINE_FOR_PRODUCT | 51 | ORDER_LINE_KEY | FOCAL01_KEY |
| ORDER_LINE_FOCAL | ORDER_LINE_PRODUCT_X | ORDER_LINE_FOR_PRODUCT | 51 | PRODUCT_KEY | FOCAL02_KEY |

## 2. Entity Classification Reasoning

### Bridge Candidates

Entities that have **timestamp attributes** (STA_TMSTP or END_TMSTP) and/or **numeric measures** (VAL_NUM) are bridge candidates — they represent events or facts.

- **ORDER_LINE_FOCAL** — Has 3 numeric measures (`unit_price`, `quantity`, `discount`). No direct timestamps, but inherits them from ORDER via M:1 relationship. Bridge source.
- **ORDER_FOCAL** — Has 2 timestamp attributes (`order_placed_on`, `order_required_by`). These are the event timestamps. Bridge source.

### Peripheral Candidates

Entities referenced on the **FOCAL02_KEY** side of relationships are peripherals — they are referenced by facts but don't produce fact rows themselves.

- **CUSTOMER_FOCAL** — Referenced by ORDER_CUSTOMER_X on FOCAL02_KEY side. All attributes are strings (descriptive). Peripheral.
- **PRODUCT_FOCAL** — Referenced by ORDER_LINE_PRODUCT_X on FOCAL02_KEY side. Has strings and a numeric (`list_price`), but `list_price` is a reference attribute (not a transactional measure). Peripheral.

### Classification Summary

| Entity | Role | Reason |
|--------|------|--------|
| ORDER_LINE_FOCAL | Bridge source | Has transactional measures (unit_price, quantity, discount) |
| ORDER_FOCAL | Bridge source | Has event timestamps (order_placed_on, order_required_by) |
| CUSTOMER_FOCAL | Peripheral | Referenced entity (FOCAL02_KEY side), descriptive attributes only |
| PRODUCT_FOCAL | Peripheral | Referenced entity (FOCAL02_KEY side), reference data |

## 3. Relationship Chain Analysis

### Direct M:1 Relationships

From the bootstrap, identify relationship tables by looking for `FOCAL01_KEY` and `FOCAL02_KEY` pairs:

| Relationship Table | atom_contx_key | FOCAL01_KEY (many) | FOCAL02_KEY (one) | Direction |
|---|---|---|---|---|
| ORDER_LINE_ORDER_X | 50 | ORDER_LINE_KEY | ORDER_KEY | ORDER_LINE → ORDER (M:1) |
| ORDER_LINE_PRODUCT_X | 51 | ORDER_LINE_KEY | PRODUCT_KEY | ORDER_LINE → PRODUCT (M:1) |
| ORDER_CUSTOMER_X | 70 | ORDER_KEY | CUSTOMER_KEY | ORDER → CUSTOMER (M:1) |

All relationships are M:1 (bridge source on FOCAL01_KEY side). No M:M detected.

### Multi-Hop Chains

ORDER_LINE needs CUSTOMER_KEY, but there is no direct ORDER_LINE → CUSTOMER relationship. The chain is:

```
ORDER_LINE → ORDER (via ORDER_LINE_ORDER_X, TYPE_KEY=50)
    ORDER → CUSTOMER (via ORDER_CUSTOMER_X, TYPE_KEY=70)
```

Resolution: Join ORDER_LINE to ORDER first, then inherit ORDER's CUSTOMER_KEY.

### Relationship Map

```
ORDER_LINE ──M:1──→ ORDER ──M:1──→ CUSTOMER
     │
     └──────M:1──→ PRODUCT
```

In the bridge:
- ORDER_LINE rows get: `_key__order`, `_key__product`, `_key__customer` (via ORDER)
- ORDER rows get: `_key__customer`

## 4. Generated Peripheral SQL

### `customer.sql`

```sql
CREATE OR REPLACE VIEW uss.customer AS
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
),
pivoted AS (
    SELECT
        CUSTOMER_KEY,
        MAX(CASE WHEN TYPE_KEY = 30 THEN VAL_STR END) AS customer_first_name,
        MAX(CASE WHEN TYPE_KEY = 31 THEN VAL_STR END) AS customer_last_name,
        MAX(CASE WHEN TYPE_KEY = 32 THEN VAL_STR END) AS customer_email,
        MAX(CASE WHEN TYPE_KEY = 33 THEN VAL_STR END) AS customer_city
    FROM ranked
    WHERE rnk = 1
    GROUP BY CUSTOMER_KEY
)
SELECT
    ROW_NUMBER() OVER (ORDER BY CUSTOMER_KEY) AS _peripheral_key,
    CUSTOMER_KEY,
    customer_first_name,
    customer_last_name,
    customer_email,
    customer_city
FROM pivoted

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS CUSTOMER_KEY,
    NULL AS customer_first_name,
    NULL AS customer_last_name,
    NULL AS customer_email,
    NULL AS customer_city;
```

### `product.sql`

```sql
CREATE OR REPLACE VIEW uss.product AS
WITH ranked AS (
    SELECT
        PRODUCT_KEY,
        TYPE_KEY,
        VAL_STR,
        VAL_NUM,
        RANK() OVER (
            PARTITION BY PRODUCT_KEY, TYPE_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.PRODUCT_DESC
    WHERE ROW_ST = 'Y'
),
pivoted AS (
    SELECT
        PRODUCT_KEY,
        MAX(CASE WHEN TYPE_KEY = 34 THEN VAL_STR END) AS product_name,
        MAX(CASE WHEN TYPE_KEY = 35 THEN VAL_STR END) AS product_category,
        MAX(CASE WHEN TYPE_KEY = 36 THEN VAL_NUM END) AS product_list_price
    FROM ranked
    WHERE rnk = 1
    GROUP BY PRODUCT_KEY
)
SELECT
    ROW_NUMBER() OVER (ORDER BY PRODUCT_KEY) AS _peripheral_key,
    PRODUCT_KEY,
    product_name,
    product_category,
    product_list_price
FROM pivoted

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS PRODUCT_KEY,
    NULL AS product_name,
    NULL AS product_category,
    NULL AS product_list_price;
```

### `order.sql`

ORDER is both a bridge source AND a peripheral (ORDER_LINE rows reference it). As a peripheral, it shows all attributes for direct lookup.

```sql
CREATE OR REPLACE VIEW uss.order AS
WITH ranked AS (
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
    FROM ranked
    WHERE rnk = 1
    GROUP BY ORDER_KEY
),
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
rel_customer AS (
    SELECT ORDER_KEY, CUSTOMER_KEY
    FROM ranked_order_customer_x
    WHERE rnk = 1
),
pivoted AS (
    SELECT
        o.ORDER_KEY,
        o.order_placed_on,
        o.order_required_by,
        r.CUSTOMER_KEY
    FROM order_attrs o
    LEFT JOIN rel_customer r
        ON o.ORDER_KEY = r.ORDER_KEY
)
SELECT
    ROW_NUMBER() OVER (ORDER BY ORDER_KEY) AS _peripheral_key,
    ORDER_KEY,
    order_placed_on,
    order_required_by,
    CUSTOMER_KEY
FROM pivoted

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS ORDER_KEY,
    NULL::timestamp AS order_placed_on,
    NULL::timestamp AS order_required_by,
    NULL AS CUSTOMER_KEY;
```

## 5. Generated Bridge SQL — Event-Grain, Snapshot

### `_bridge.sql`

```sql
CREATE OR REPLACE VIEW uss._bridge AS
WITH
-- ============================================================
-- ORDER_LINE: Resolve descriptors (measures)
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
-- ORDER_LINE: Resolve relationships
-- ============================================================
ranked_ol_order_x AS (
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
rel_ol_order AS (
    SELECT ORDER_LINE_KEY, ORDER_KEY
    FROM ranked_ol_order_x
    WHERE rnk = 1
),
ranked_ol_product_x AS (
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
rel_ol_product AS (
    SELECT ORDER_LINE_KEY, PRODUCT_KEY
    FROM ranked_ol_product_x
    WHERE rnk = 1
),

-- ============================================================
-- ORDER: Resolve descriptors (timestamps)
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
-- ORDER: Resolve relationships
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
        COALESCE(p_customer._peripheral_key, -1) AS _key__customer
    FROM order_attrs o
    LEFT JOIN rel_order_customer r
        ON o.ORDER_KEY = r.ORDER_KEY
    LEFT JOIN uss.customer p_customer
        ON r.CUSTOMER_KEY = p_customer.CUSTOMER_KEY
),

-- ============================================================
-- ORDER_LINE: Join descriptors + relationships + inherit ORDER data
-- ============================================================
order_line_joined AS (
    SELECT
        ola.ORDER_LINE_KEY,
        ola.unit_price,
        ola.quantity,
        ola.discount,
        COALESCE(p_order._peripheral_key, -1) AS _key__order,
        COALESCE(p_product._peripheral_key, -1) AS _key__product,
        -- Inherit from ORDER (multi-hop chain resolution)
        oj._key__customer,
        oj.order_placed_on,
        oj.order_required_by
    FROM order_line_attrs ola
    LEFT JOIN rel_ol_order ro
        ON ola.ORDER_LINE_KEY = ro.ORDER_LINE_KEY
    LEFT JOIN rel_ol_product rp
        ON ola.ORDER_LINE_KEY = rp.ORDER_LINE_KEY
    LEFT JOIN order_joined oj
        ON ro.ORDER_KEY = oj.ORDER_KEY
    LEFT JOIN uss.order p_order
        ON ro.ORDER_KEY = p_order.ORDER_KEY
    LEFT JOIN uss.product p_product
        ON rp.PRODUCT_KEY = p_product.PRODUCT_KEY
),

-- ============================================================
-- ORDER_LINE: Unpivot timestamps to events
-- ============================================================
order_line_events AS (
    SELECT
        olj.ORDER_LINE_KEY,
        olj._key__order,
        olj._key__product,
        olj._key__customer,
        olj.unit_price AS _measure__order_line__unit_price,
        olj.quantity AS _measure__order_line__quantity,
        olj.discount AS _measure__order_line__discount,
        e.event_name AS event,
        e.event_tmstp AS event_occurred_on,
        e.event_tmstp::date AS _key__dates,
        e.event_tmstp::time AS _key__times
    FROM order_line_joined olj
    CROSS JOIN LATERAL (
        VALUES
            ('order_placed_on', olj.order_placed_on),
            ('order_required_by', olj.order_required_by)
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
-- UNION ALL: Bridge
-- ============================================================
SELECT
    'order_line' AS peripheral,
    COALESCE(p_self._peripheral_key, -1) AS _key__order_line,
    ole._key__order,
    ole._key__product,
    ole._key__customer,
    ole.event,
    ole.event_occurred_on,
    ole._key__dates,
    ole._key__times,
    ole._measure__order_line__unit_price,
    ole._measure__order_line__quantity,
    ole._measure__order_line__discount
FROM order_line_events ole
LEFT JOIN uss.order_line p_self
    ON ole.ORDER_LINE_KEY = p_self.ORDER_LINE_KEY

UNION ALL

SELECT
    'order' AS peripheral,
    NULL::bigint AS _key__order_line,
    COALESCE(p_self._peripheral_key, -1) AS _key__order,
    NULL::bigint AS _key__product,
    oe._key__customer,
    oe.event,
    oe.event_occurred_on,
    oe._key__dates,
    oe._key__times,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount
FROM order_events oe
LEFT JOIN uss.order p_self
    ON oe.ORDER_KEY = p_self.ORDER_KEY

UNION ALL

-- ============================================================
-- CUSTOMER: Peripheral bridge rows
-- ============================================================
SELECT
    'customer' AS peripheral,
    NULL::bigint AS _key__order_line,
    NULL::bigint AS _key__order,
    NULL::bigint AS _key__product,
    c._peripheral_key AS _key__customer,
    NULL AS event,
    NULL::timestamp AS event_occurred_on,
    NULL::date AS _key__dates,
    NULL::time AS _key__times,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount
FROM uss.customer c

UNION ALL

-- ============================================================
-- PRODUCT: Peripheral bridge rows
-- ============================================================
SELECT
    'product' AS peripheral,
    NULL::bigint AS _key__order_line,
    NULL::bigint AS _key__order,
    p._peripheral_key AS _key__product,
    NULL::bigint AS _key__customer,
    NULL AS event,
    NULL::timestamp AS event_occurred_on,
    NULL::date AS _key__dates,
    NULL::time AS _key__times,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount
FROM uss.product p;
```

### How to read this bridge

Each row represents one **event** from one **entity**:

| peripheral | Meaning |
|---|---|
| `order_line` | An order line event — carries unit_price, quantity, discount measures; inherits order/customer/product keys from relationships |
| `order` | An order event — carries no measures directly; has customer key |

The `event` column names the timestamp (`order_placed_on` or `order_required_by`), and `event_occurred_on` holds the actual timestamp value. This enables a single `_dates` join for any date-based analysis regardless of which timestamp it is.

### Join pattern for consumers

```sql
SELECT
    b.event,
    b.event_occurred_on,
    d.year,
    d.month_name,
    c.customer_first_name,
    c.customer_last_name,
    p.product_name,
    b._measure__order_line__unit_price,
    b._measure__order_line__quantity
FROM uss._bridge b
LEFT JOIN uss._dates d ON b._key__dates = d._key__dates
LEFT JOIN uss._times t ON b._key__times = t._key__times
LEFT JOIN uss.customer c ON b._key__customer = c._peripheral_key
LEFT JOIN uss.product p ON b._key__product = p._peripheral_key
LEFT JOIN uss.order o ON b._key__order = o._peripheral_key
WHERE b.peripheral = 'order_line'
  AND b.event = 'order_placed_on';
```

### Historical Mode — Peripheral Joins

Point-in-time resolution happens in the bridge during surrogate key resolution. Consumers always join via `_peripheral_key` — no temporal predicate needed at query time.

```sql
SELECT p.product_name, SUM(b._measure__order_line__unit_price)
FROM uss._bridge b
LEFT JOIN uss.product p ON b._key__product = p._peripheral_key
WHERE b.peripheral = 'order_line'
  AND b.event = 'order_placed_on'
GROUP BY p.product_name
```

> **Note:** Both snapshot and historical peripherals use `_peripheral_key` joins. The bridge resolves the correct version at generation time, so consumers never need temporal predicates.

## 6. Generated Synthetic SQL

### `_dates.sql`

```sql
CREATE OR REPLACE VIEW uss._dates AS
WITH date_range AS (
    SELECT
        DATE_TRUNC('year', MIN(event_occurred_on))::date AS start_date,
        (DATE_TRUNC('year', MAX(event_occurred_on)) + INTERVAL '1 year' - INTERVAL '1 day')::date AS end_date
    FROM uss._bridge
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
ORDER BY date_key;
```

### `_times.sql`

```sql
CREATE OR REPLACE VIEW uss._times AS
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
ORDER BY time_key;
```

## 7. Variant: Columnar Mode Bridge

When the user selects "Columnar dates" in the interview, timestamps stay as named columns instead of being unpivoted. Here is how `_bridge.sql` differs:

### Key Changes

1. **No `CROSS JOIN LATERAL` unpivot** — The events CTEs are removed entirely.
2. **No `event` or `event_occurred_on` columns** — Timestamps appear as named columns.
3. **No `_key__dates` or `_key__times` columns** — No synthetic peripheral joins.
4. **`_dates.sql` and `_times.sql` are NOT generated.**

### `_bridge.sql` (Columnar, Snapshot)

```sql
CREATE OR REPLACE VIEW uss._bridge AS
WITH
-- (Same CTEs as event-grain for descriptor and relationship resolution)
-- ranked_order_line, order_line_attrs, rel_ol_order, rel_ol_product,
-- ranked_order, order_attrs, rel_order_customer, order_joined, order_line_joined
-- ... (identical to event-grain through order_line_joined and order_joined) ...

-- Skip unpivot — go directly to UNION ALL

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
ranked_ol_order_x AS (
    SELECT
        ORDER_LINE_KEY, ORDER_KEY,
        RANK() OVER (PARTITION BY ORDER_LINE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS rnk
    FROM {source_schema}.ORDER_LINE_ORDER_X
    WHERE ROW_ST = 'Y' AND TYPE_KEY = 50
),
rel_ol_order AS (
    SELECT ORDER_LINE_KEY, ORDER_KEY FROM ranked_ol_order_x WHERE rnk = 1
),
ranked_ol_product_x AS (
    SELECT
        ORDER_LINE_KEY, PRODUCT_KEY,
        RANK() OVER (PARTITION BY ORDER_LINE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS rnk
    FROM {source_schema}.ORDER_LINE_PRODUCT_X
    WHERE ROW_ST = 'Y' AND TYPE_KEY = 51
),
rel_ol_product AS (
    SELECT ORDER_LINE_KEY, PRODUCT_KEY FROM ranked_ol_product_x WHERE rnk = 1
),
ranked_order AS (
    SELECT
        ORDER_KEY, TYPE_KEY, STA_TMSTP,
        RANK() OVER (PARTITION BY ORDER_KEY, TYPE_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS rnk
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
ranked_order_customer_x AS (
    SELECT
        ORDER_KEY, CUSTOMER_KEY,
        RANK() OVER (PARTITION BY ORDER_KEY ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS rnk
    FROM {source_schema}.ORDER_CUSTOMER_X
    WHERE ROW_ST = 'Y' AND TYPE_KEY = 70
),
rel_order_customer AS (
    SELECT ORDER_KEY, CUSTOMER_KEY FROM ranked_order_customer_x WHERE rnk = 1
),
order_joined AS (
    SELECT
        o.ORDER_KEY,
        o.order_placed_on,
        o.order_required_by,
        COALESCE(p_customer._peripheral_key, -1) AS _key__customer
    FROM order_attrs o
    LEFT JOIN rel_order_customer r ON o.ORDER_KEY = r.ORDER_KEY
    LEFT JOIN uss.customer p_customer ON r.CUSTOMER_KEY = p_customer.CUSTOMER_KEY
),
order_line_joined AS (
    SELECT
        ola.ORDER_LINE_KEY,
        ola.unit_price,
        ola.quantity,
        ola.discount,
        COALESCE(p_order._peripheral_key, -1) AS _key__order,
        COALESCE(p_product._peripheral_key, -1) AS _key__product,
        oj._key__customer,
        oj.order_placed_on,
        oj.order_required_by
    FROM order_line_attrs ola
    LEFT JOIN rel_ol_order ro ON ola.ORDER_LINE_KEY = ro.ORDER_LINE_KEY
    LEFT JOIN rel_ol_product rp ON ola.ORDER_LINE_KEY = rp.ORDER_LINE_KEY
    LEFT JOIN order_joined oj ON ro.ORDER_KEY = oj.ORDER_KEY
    LEFT JOIN uss.order p_order ON ro.ORDER_KEY = p_order.ORDER_KEY
    LEFT JOIN uss.product p_product ON rp.PRODUCT_KEY = p_product.PRODUCT_KEY
)

-- No unpivot — timestamps stay as columns
SELECT
    'order_line' AS peripheral,
    COALESCE(p_self._peripheral_key, -1) AS _key__order_line,
    olj._key__order,
    olj._key__product,
    olj._key__customer,
    olj.order_placed_on,
    olj.order_required_by,
    olj.unit_price AS _measure__order_line__unit_price,
    olj.quantity AS _measure__order_line__quantity,
    olj.discount AS _measure__order_line__discount
FROM order_line_joined olj
LEFT JOIN uss.order_line p_self ON olj.ORDER_LINE_KEY = p_self.ORDER_LINE_KEY

UNION ALL

SELECT
    'order' AS peripheral,
    NULL::bigint AS _key__order_line,
    COALESCE(p_self._peripheral_key, -1) AS _key__order,
    NULL::bigint AS _key__product,
    oj._key__customer,
    oj.order_placed_on,
    oj.order_required_by,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount
FROM order_joined oj
LEFT JOIN uss.order p_self ON oj.ORDER_KEY = p_self.ORDER_KEY;
```

### Columnar join pattern for consumers

Without event unpivoting, consumers filter on specific timestamp columns:

```sql
SELECT
    b.order_placed_on,
    b.order_required_by,
    c.customer_first_name,
    c.customer_last_name,
    p.product_name,
    b._measure__order_line__unit_price
FROM uss._bridge b
LEFT JOIN uss.customer c ON b._key__customer = c._peripheral_key
LEFT JOIN uss.product p ON b._key__product = p._peripheral_key
WHERE b.peripheral = 'order_line'
  AND b.order_placed_on >= '2024-01-01';
```

## 8. Variant: Historical Mode

When the user selects "Historical (valid_from / valid_to)" in the interview, all temporal versions are preserved. Here are the key changes applied to the event-grain bridge:

### Changes to Descriptor CTEs

Remove `ROW_ST = 'Y'` filter. Use RANK only within each `EFF_TMSTP` to handle re-deliveries:

```sql
ranked_order_line AS (
    SELECT
        ORDER_LINE_KEY,
        TYPE_KEY,
        VAL_NUM,
        ROW_ST,
        EFF_TMSTP,
        RANK() OVER (
            PARTITION BY ORDER_LINE_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_LINE_DESC
    -- No ROW_ST filter — keep all versions
),
order_line_attrs AS (
    SELECT
        ORDER_LINE_KEY,
        EFF_TMSTP,
        -- NULL out values when ROW_ST = 'N' (deleted/removed)
        MAX(CASE WHEN TYPE_KEY = 40 AND ROW_ST = 'Y' THEN VAL_NUM END) AS unit_price,
        MAX(CASE WHEN TYPE_KEY = 41 AND ROW_ST = 'Y' THEN VAL_NUM END) AS quantity,
        MAX(CASE WHEN TYPE_KEY = 42 AND ROW_ST = 'Y' THEN VAL_NUM END) AS discount
    FROM ranked_order_line
    WHERE rnk = 1
    GROUP BY ORDER_LINE_KEY, EFF_TMSTP
),
```

### Changes to Relationship CTEs

Same pattern — remove `ROW_ST = 'Y'` and keep all `EFF_TMSTP` values:

```sql
ranked_ol_order_x AS (
    SELECT
        ORDER_LINE_KEY,
        ORDER_KEY,
        EFF_TMSTP,
        RANK() OVER (
            PARTITION BY ORDER_LINE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM {source_schema}.ORDER_LINE_ORDER_X
      AND TYPE_KEY = 50
    -- No ROW_ST filter
),
```

### Add valid_from / valid_to via LEAD Window

After joining descriptors and relationships, compute temporal boundaries:

```sql
order_line_versioned AS (
    SELECT
        olj.*,
        olj.eff_tmstp AS valid_from,
        COALESCE(
            LEAD(olj.eff_tmstp) OVER (
                PARTITION BY olj.ORDER_LINE_KEY
                ORDER BY olj.eff_tmstp
            ),
            '9999-12-31'::timestamp
        ) AS valid_to
    FROM order_line_joined olj
)
```

### Bridge Output Adds Temporal Columns

```sql
SELECT
    'order_line' AS peripheral,
    COALESCE(p_self._peripheral_key, -1) AS _key__order_line,
    ole._key__order,
    ole._key__product,
    ole._key__customer,
    ole.event,
    ole.event_occurred_on,
    ole._key__dates,
    ole._key__times,
    ole._measure__order_line__unit_price,
    ole._measure__order_line__quantity,
    ole._measure__order_line__discount,
    ole.valid_from,
    ole.valid_to
FROM order_line_events ole
LEFT JOIN uss.order_line p_self
    ON ole.ORDER_LINE_KEY = p_self.ORDER_LINE_KEY

UNION ALL

SELECT
    'order' AS peripheral,
    NULL::bigint AS _key__order_line,
    COALESCE(p_self._peripheral_key, -1) AS _key__order,
    NULL::bigint AS _key__product,
    oe._key__customer,
    oe.event,
    oe.event_occurred_on,
    oe._key__dates,
    oe._key__times,
    NULL::numeric AS _measure__order_line__unit_price,
    NULL::numeric AS _measure__order_line__quantity,
    NULL::numeric AS _measure__order_line__discount,
    oe.valid_from,
    oe.valid_to
FROM order_events oe
LEFT JOIN uss.order p_self
    ON oe.ORDER_KEY = p_self.ORDER_KEY;
```

### Historical join pattern for consumers

Add temporal filtering to get values as-of a specific date:

```sql
SELECT
    b.event,
    b.event_occurred_on,
    b.valid_from,
    b.valid_to,
    c.customer_first_name,
    b._measure__order_line__unit_price
FROM uss._bridge b
LEFT JOIN uss.customer c ON b._key__customer = c._peripheral_key
WHERE b.peripheral = 'order_line'
  AND b.valid_from <= '2024-06-15'
  AND b.valid_to > '2024-06-15';
```
