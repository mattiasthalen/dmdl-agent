# USS Surrogate Keys Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make USS peripherals use surrogate integer keys with `-1` default rows and point-in-time bridge resolution, aligning with Star schema conventions from teach_claude_focal.

**Architecture:** Update USS skill reference patterns and examples to introduce `_peripheral_key` (surrogate int via `ROW_NUMBER()`), `-1` default rows per peripheral, SCD type selection per peripheral, and `COALESCE(p._peripheral_key, -1)` in the bridge. Replace the global "snapshot vs historical" interview question with a per-peripheral versioning question.

**Tech Stack:** Markdown skill files (no application code). PostgreSQL SQL patterns.

---

## Parallelization

```
Task 1 (SKILL.md interview) ─────────────────────────────── ┐
Task 2 (uss-patterns.md peripheral pattern) ──→ Task 3 ──→ ├─→ Task 5 (uss-examples.md) ──→ Task 6 (version bump + commit)
                        (uss-patterns.md bridge pattern)    ┘
```

- **Task 1** and **Task 2** can run in parallel (different files)
- **Task 3** depends on Task 2 (same file: uss-patterns.md)
- **Task 4** is deleted — columnar/historical variants derive from the same changes
- **Task 5** depends on Tasks 1, 2, 3 (examples must match updated patterns)
- **Task 6** depends on all previous tasks

---

### Task 1: Update SKILL.md Interview Flow

**Files:**
- Modify: `skills/uss/SKILL.md:55-68`

**Step 1: Replace Question 3 — Historical Mode**

Replace the current Question 3 (lines 55-68) which asks about snapshot vs historical globally. The new question asks about peripheral versioning mode with three options.

Replace:

```markdown
### Question 3 — Historical Mode

- Question: "Should the USS capture the latest snapshot or preserve temporal history?"
- Options:
  - "Snapshot (latest values)" — RANK pattern for dedup. One row per fact instance.
  - "Historical (valid_from / valid_to)" — Preserve effective timestamps. Adds `valid_from` and `valid_to` columns to bridge and peripherals.
```

With:

```markdown
### Question 3 — Peripheral Versioning

- Question: "How should peripherals handle versioning?"
- Options:
  - "Latest for all (Type 1)" — One row per entity, current state. Simple key joins in the bridge.
  - "Full history for all (Type 2)" — Versioned rows with `effective_from` / `effective_to`. Point-in-time joins in the bridge.
  - "Per peripheral" — Choose SCD type for each peripheral individually.

If "Per peripheral", ask for each peripheral entity:
- Question: "Versioning for {ENTITY}?"
- Options:
  - "Type 1 (latest only)" — One row per entity.
  - "Type 2 (full history)" — Versioned rows with temporal ranges.
```

**Step 2: Update subagent prompt interview answers**

In the subagent prompt template (line 112), replace:

```markdown
   - Historical mode: snapshot or historical (valid_from/valid_to)
```

With:

```markdown
   - Peripheral versioning: latest all (Type 1), full history all (Type 2), or per-peripheral with individual choices
```

**Step 3: Commit**

```bash
git add skills/uss/SKILL.md
git commit -m "fix: replace global historical mode with per-peripheral versioning in USS interview (#50)"
```

---

### Task 2: Update uss-patterns.md — Peripheral Pattern

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:48-199` (Peripheral Pattern section)

**Step 1: Add surrogate key and versioning to the peripheral pattern**

After the existing peripheral pattern (single descriptor table, lines 56-81), add a new section explaining the surrogate key layer. This goes between the current peripheral examples and the bridge pattern.

Insert after line 199 (after the Complete Example — CUSTOMER Peripheral section), before the Bridge Pattern section:

```markdown
### Surrogate Key and Versioning Layer

Every peripheral — regardless of SCD type — wraps its pivoted output with a surrogate integer key and a `-1` default row.

#### Type 1 (Latest Only)

One row per entity. The peripheral CTE from above is wrapped with `ROW_NUMBER()`:

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

Multiple rows per entity with temporal ranges. Uses Pattern 2 (temporal alignment with carry-forward) from the ad-hoc query agent, then adds version columns:

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
```

**Step 2: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "fix: add surrogate key and versioning layer to USS peripheral pattern (#50)"
```

---

### Task 3: Update uss-patterns.md — Bridge Pattern and Column Rules

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:280-382` (Bridge Step 3 + Step 5 + Column Rules)

**Step 1: Update Step 3 — Join Descriptors + Relationships**

The bridge currently stores raw entity keys as `_key__` columns (line 294-296):

```sql
r1.{target_attr_name_1} AS _key__{peripheral_1},
r2.{target_attr_name_2} AS _key__{peripheral_2}
```

Replace with surrogate key resolution. The joined CTE now resolves peripheral surrogate keys via LEFT JOIN to the peripheral view:

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
        -- Resolve peripheral surrogate keys
        COALESCE(p1._peripheral_key, -1) AS _key__{peripheral_1},
        COALESCE(p2._peripheral_key, -1) AS _key__{peripheral_2}
    FROM {entity}_attrs a
    LEFT JOIN {rel_alias_1} r1
        ON a.{entity}_KEY = r1.{source_attr_name_1}
    LEFT JOIN {rel_alias_2} r2
        ON a.{entity}_KEY = r2.{source_attr_name_2}
    -- Type 1 peripheral join (simple key match)
    LEFT JOIN {target_schema}.{peripheral_1} p1
        ON r1.{target_attr_name_1} = p1.{peripheral_1_entity}_KEY
    -- Type 2 peripheral join (point-in-time)
    LEFT JOIN {target_schema}.{peripheral_2} p2
        ON r2.{target_attr_name_2} = p2.{peripheral_2_entity}_KEY
        AND a.{event_timestamp} >= p2.effective_from
        AND a.{event_timestamp} < p2.effective_to
)
```

**Step 2: Update Step 5 — UNION ALL column alignment rules**

Replace lines 378-382:

```markdown
**Column alignment rules:**
- Every entity contributes the same column set in every UNION ALL member.
- Missing FK keys are `NULL::bigint`.
- Missing measures are `NULL::numeric`.
- `peripheral`, `event`, `event_occurred_on`, `_key__dates`, `_key__times` are always present.
```

With:

```markdown
**Column alignment rules:**
- Every entity contributes the same column set in every UNION ALL member.
- All `_key__` columns hold surrogate integer keys (`_peripheral_key` from the peripheral view), not raw entity keys. Missing keys are `NULL::bigint`.
- Missing measures are `NULL::numeric`.
- `peripheral`, `event`, `event_occurred_on`, `_key__dates`, `_key__times` are always present.
- Bridge sources also contribute their own `_peripheral_key` as their `_key__{entity}` column, resolved from the peripheral view by self-joining on the entity key.
```

**Step 3: Update the complete bridge example**

Update the complete bridge example (lines 384-651) to show surrogate key resolution. Key changes in the example:

1. Add `LEFT JOIN` to peripheral views in the `order_line_joined` and `order_joined` CTEs
2. Replace `r_ord.ORDER_KEY AS _key__order` with `COALESCE(p_order._peripheral_key, -1) AS _key__order`
3. Replace `r_prd.PRODUCT_KEY AS _key__product` with `COALESCE(p_product._peripheral_key, -1) AS _key__product`
4. Replace `r_cust.CUSTOMER_KEY AS _key__customer` with `COALESCE(p_customer._peripheral_key, -1) AS _key__customer`
5. In the UNION ALL, bridge source entities also resolve their own `_peripheral_key`:
   - `ORDER_LINE_KEY AS _key__order_line` → `COALESCE(p_self._peripheral_key, -1) AS _key__order_line`
   - `ORDER_KEY AS _key__order` → `COALESCE(p_self._peripheral_key, -1) AS _key__order`
6. Peripheral bridge rows (CUSTOMER, PRODUCT) reference their own `_peripheral_key` directly

**Step 4: Update columnar and historical bridge variants**

Apply the same surrogate key resolution pattern to:
- Bridge Pattern — Columnar, Snapshot (lines 750-791)
- Bridge Pattern — Columnar, Historical (lines 794+)
- Bridge Pattern — Event-Grain, Historical (lines 655-706)

**Step 5: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "fix: resolve surrogate peripheral keys in USS bridge pattern (#50)"
```

---

### Task 5: Update uss-examples.md — Full Worked Example

**Files:**
- Modify: `skills/uss/references/uss-examples.md`

**Step 1: Update peripheral SQL examples (lines 109-215)**

Add `_peripheral_key` and `-1` default row to each peripheral:

- `customer.sql` — wrap with `ROW_NUMBER() OVER (ORDER BY CUSTOMER_KEY) AS _peripheral_key`, add `-1` UNION ALL
- `product.sql` — same pattern
- `order.sql` — same pattern (ORDER is both bridge source and peripheral)

**Step 2: Update bridge SQL example (lines 219-490)**

Replace all raw entity key references with surrogate key resolution:

1. In `order_line_joined` CTE: add LEFT JOINs to `uss.order`, `uss.product`, `uss.customer` peripherals, resolve `_peripheral_key` via `COALESCE(..., -1)`
2. In `order_joined` CTE: add LEFT JOIN to `uss.customer` peripheral
3. In UNION ALL: replace `ORDER_LINE_KEY AS _key__order_line` with resolved `_peripheral_key`, same for all entity keys
4. Peripheral bridge rows (CUSTOMER, PRODUCT): use `c._peripheral_key AS _key__customer` instead of `c.CUSTOMER_KEY AS _key__customer`

**Step 3: Update consumer join pattern (lines 504-524)**

Replace entity key joins with surrogate key joins:

```sql
-- Old:
LEFT JOIN uss.customer c ON b._key__customer = c.CUSTOMER_KEY

-- New:
LEFT JOIN uss.customer c ON b._key__customer = c._peripheral_key
```

**Step 4: Update historical mode consumer join pattern (lines 527-554)**

The temporal join is now done in the bridge (during surrogate key resolution), so consumers always join via `_peripheral_key` — no temporal predicate needed:

```sql
-- Old (temporal join at query time):
JOIN uss.product p ON b._key__product = p.PRODUCT_KEY
    AND p.valid_from <= b.event_occurred_on
    AND p.valid_to > b.event_occurred_on

-- New (temporal join already resolved in bridge):
LEFT JOIN uss.product p ON b._key__product = p._peripheral_key
```

Update the explanation text to clarify that point-in-time resolution happens in the bridge, not at consumer query time.

**Step 5: Update columnar mode bridge example (lines 617-781)**

Apply the same surrogate key resolution pattern to the columnar variant.

**Step 6: Update historical mode bridge example (lines 783-917)**

Apply the same surrogate key resolution pattern to the historical variant.

**Step 7: Commit**

```bash
git add skills/uss/references/uss-examples.md
git commit -m "fix: update USS worked examples to use surrogate peripheral keys (#50)"
```

---

### Task 6: Version Bump and Final Commit

**Files:**
- Modify: `.claude-plugin/plugin.json:4`

**Step 1: Bump version**

Change `"version": "1.12.0"` to `"version": "1.13.0"` (minor bump — new feature: surrogate keys in USS).

**Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 1.13.0 (#50)"
```

**Step 3: Push**

```bash
git push
```
