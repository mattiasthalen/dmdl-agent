# USS Peripheral Relationship Type 2 Dedup

**Issue:** #55
**Date:** 2026-03-27

## Problem

Peripheral views with relationships use snapshot dedup for relationship CTEs:

```sql
PARTITION BY CUSTOMER_KEY
ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
```

This always resolves to the latest relationship, discarding history. Descriptor CTEs in the same file correctly use Type 2 dedup:

```sql
PARTITION BY CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP
ORDER BY VER_TMSTP DESC
```

Result: all historical peripheral rows show the *current* relationship, not the relationship as-of each `effective_from` point.

## Approach: Unified Timeline with Carry-Forward

Treat relationships identically to descriptors: dedup per `EFF_TMSTP`, merge into the timeline spine, and carry-forward via window functions.

### Change 1: Relationship CTE Dedup

From snapshot (one row per entity):
```sql
RANK() OVER (
    PARTITION BY CUSTOMER_KEY
    ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
) AS rnk
```

To Type 2 (one row per entity per EFF_TMSTP):
```sql
RANK() OVER (
    PARTITION BY CUSTOMER_KEY, EFF_TMSTP
    ORDER BY VER_TMSTP DESC
) AS rnk
```

Expose `EFF_TMSTP` in the output of the rel CTE.

### Change 2: Timeline Spine Merge

From descriptors only:
```sql
timeline AS (
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP FROM deduped
)
```

To descriptors + relationships:
```sql
timeline AS (
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP FROM deduped
    UNION
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP FROM rel_person
    UNION
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP FROM rel_sales_territory
    UNION
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP FROM rel_store
)
```

### Change 3: Carry-Forward for Relationship FKs

Join relationship CTEs to the timeline spine in the `pivoted` CTE (alongside descriptors), and apply the same carry-forward window:

```sql
MAX(rp.PERSON_KEY) OVER (
    PARTITION BY t.CUSTOMER_KEY
    ORDER BY t.EFF_TMSTP
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS PERSON_KEY
```

With LEFT JOINs:
```sql
LEFT JOIN rel_person rp
    ON t.CUSTOMER_KEY = rp.CUSTOMER_KEY AND t.EFF_TMSTP = rp.EFF_TMSTP
```

### Change 4: Simplify peripheral_final

Remove separate `LEFT JOIN rel_*` from `peripheral_final` — everything is already resolved in `pivoted_deduped`.

## Affected Files

### SQL files (9 peripherals):
- `uss/customer.sql`
- `uss/employee.sql`
- `uss/purchase_order.sql`
- `uss/sales_order.sql`
- `uss/sales_order_detail.sql`
- `uss/sales_person.sql`
- `uss/store.sql`
- `uss/vendor.sql`
- `uss/work_order.sql`

### Reference patterns:
- `skills/uss/references/uss-patterns.md` — update peripheral relationship pattern documentation

## Non-Goals

- Bridge relationship resolution is out of scope (bridge uses snapshot dedup intentionally, resolving against peripheral `effective_from`/`effective_to` via point-in-time joins).
