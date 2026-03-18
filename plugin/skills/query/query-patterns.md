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
