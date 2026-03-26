# Design: USS Surrogate Keys (Issue #50)

## Problem

USS peripherals and bridge currently use raw Focal entity keys (`CUSTOMER_KEY`, `ORDER_KEY`) directly. These keys have no guaranteed data type — they come from the source system via Focal's IDFR layer and can be integers, strings, or anything else.

Since USS is a variation of Star schema, it should follow the same conventions: surrogate integer keys for peripherals, `COALESCE(..., -1)` for unknown members, and `-1` default rows. The current `NULL::bigint` cast in UNION ALL members happens to be the right type but for the wrong reason — the `_key__` columns should hold surrogate integers, not raw entity keys.

## Context

- Patrik's Star schema design (teach_claude_focal) uses `VERSION_DIM_KEY` as a surrogate integer on all dimensions, with a `-1` default row for "unknown/unresolved."
- Fact tables resolve dimension keys via point-in-time LEFT JOINs and `COALESCE(dim.VERSION_DIM_KEY, -1)`.
- SCD type is a user decision per attribute/dimension — Focal data supports all types equally.
- USS has no "dimensions" and "facts" — every entity is both. Peripherals are the equivalent of dimensions; the bridge is the universal fact table.

## Design

### 1. Peripheral Changes

Each peripheral gains:

- **`_peripheral_key`** — surrogate integer via `ROW_NUMBER() OVER (ORDER BY {entity}_KEY, EFF_TMSTP)`.
- **`-1` default row** — appended via UNION ALL with `'UNKNOWN'` as the entity key and NULLs for all attributes. Covers `effective_from = '1900-01-01'` to `effective_to = '9999-12-31'`.
- **SCD type support:**
  - **Type 1 (latest):** One row per entity, current values. `_peripheral_key` is still assigned. No `effective_from` / `effective_to` needed (single row per entity makes joins trivial).
  - **Type 2 (versioned):** Multiple rows per entity with `effective_from` / `effective_to` date ranges, derived from `EFF_TMSTP` and `LEAD(EFF_TMSTP)`. Enables point-in-time joins from the bridge.

### 2. Bridge Changes

`_key__` columns change from raw entity keys to surrogate integers:

- **Current:** `r_ord.ORDER_KEY AS _key__order` (raw Focal key, unknown type)
- **New:** `COALESCE(p_order._peripheral_key, -1) AS _key__order` (surrogate integer)

Join pattern depends on peripheral SCD type:

- **Type 1 peripheral:** Simple key join (one row per entity).
  ```sql
  LEFT JOIN order_peripheral p_order
      ON j.ORDER_KEY = p_order.ORDER_KEY
  ```
- **Type 2 peripheral:** Point-in-time temporal join.
  ```sql
  LEFT JOIN order_peripheral p_order
      ON j.ORDER_KEY = p_order.ORDER_KEY
      AND event_occurred_on >= p_order.effective_from
      AND event_occurred_on < p_order.effective_to
  ```

`NULL::bigint` for missing peripherals in UNION ALL remains correct — all `_key__` columns are now surrogate integers.

### 3. Interview Change

New question added to the USS skill interview for peripheral versioning mode:

> **Peripheral versioning:**
> 1. Latest for all (Type 1 — one row per entity, current state)
> 2. Full history for all (Type 2 — versioned with date ranges)
> 3. Per peripheral (choose SCD type for each peripheral individually)

Option 3 triggers a follow-up question per peripheral.

### 4. Column Alignment Rule Update

Update the rule in uss-patterns.md from:
> "Missing FK keys are `NULL::bigint`."

To clarify these are surrogate peripheral keys, not raw entity keys.

## Files Affected

- `skills/uss/references/uss-patterns.md` — peripheral pattern, bridge pattern, column alignment rules
- `skills/uss/references/uss-examples.md` — worked examples updated to use surrogate keys
- `skills/uss/SKILL.md` — interview flow (new versioning question)

## Alignment with Star Schema

| Concept | Star Schema | USS |
|---------|-------------|-----|
| Entity view | Dimension table | Peripheral |
| Surrogate key | `VERSION_DIM_KEY` | `_peripheral_key` |
| Unknown member | `-1` default row | `-1` default row |
| Missing key handling | `COALESCE(dim.KEY, -1)` | `COALESCE(p._peripheral_key, -1)` |
| SCD type selection | Per attribute (user decides) | Per peripheral (user decides) |
| Temporal resolution | `event_date BETWEEN eff_from AND eff_to` | `event_occurred_on >= eff_from AND < eff_to` |
| Key type | Always integer | Always integer |
