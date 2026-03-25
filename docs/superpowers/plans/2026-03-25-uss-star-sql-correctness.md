# USS/Star SQL Correctness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 6 SQL generation bugs (#38-43) in USS and Star skill reference files so generated SQL is correct.

**Architecture:** All changes are edits to skill reference `.md` files — no code, no structural changes. Fixes target column naming algorithms, relationship column resolution rules, schema variable usage, recursive peripheral discovery, and temporal join documentation.

**Tech Stack:** Markdown reference files consumed by Claude as LLM context during SQL generation.

**Design spec:** `docs/superpowers/specs/2026-03-25-uss-star-sql-correctness-design.md`

**Test reference:** `adventure-works-ddw` repo (pinned in `external.lock`) — clone and use `/daana-uss` and `/daana-star` to verify fixes.

---

### Task 1: Fix column naming algorithm in uss-patterns.md (#43)

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:81`
- Modify: `skills/uss/references/uss-patterns.md:144-179` (CUSTOMER example)

**Step 1: Replace vague column naming rule**

At line 81, replace:

```markdown
The `{attr_name_N}` values are derived from `atomic_context_name` — lowercased, with the entity prefix stripped.
```

With:

```markdown
The `{attr_name_N}` values are derived from `atomic_context_name` using this algorithm:

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
```

**Step 2: Update CUSTOMER example**

At lines 155-179, update the generated SQL column aliases to match the new algorithm:

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

Note: Also replace `daana_dw` with `{source_schema}` here (for #42).

**Step 3: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "fix: explicit column naming algorithm — strip entity prefix once (#43)"
```

---

### Task 2: Add source schema variable to uss-patterns.md (#42)

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:7-16` (Prerequisites section)
- Modify: `skills/uss/references/uss-patterns.md` (ALL SQL templates — replace `daana_dw.` with `{source_schema}.`)

**Step 1: Add source schema rule to Prerequisites**

After the existing table at line 16, add:

```markdown

> **CRITICAL:** The source schema for all SQL is the `FOCAL_PHYSICAL_SCHEMA` value from the bootstrap (e.g., `daana_dw`). Use `{source_schema}` in all `FROM` clauses. **Never** hardcode `daana_dw` or use `focal` as a schema name.
```

**Step 2: Replace all `daana_dw.` with `{source_schema}.` in SQL templates**

Search-and-replace all occurrences of `daana_dw.` in uss-patterns.md with `{source_schema}.`. This affects approximately 20+ occurrences across:
- RANK Dedup Pattern (line 30)
- Peripheral Pattern (lines 68, 101, 123, 167)
- Bridge Pattern Steps 1-2 (lines 205, 391, 416, 434, 473, 489-499)
- Historical Bridge Pattern (line 648)
- Synthetic Date/Time patterns (line 799)

**Step 3: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "fix: use {source_schema} variable instead of hardcoded daana_dw (#42)"
```

---

### Task 3: Reinforce FOCAL01/02 → attribute_name rule in uss-patterns.md (#40)

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:221-249` (Step 2: Resolve Relationships)
- Modify: `skills/uss/references/uss-patterns.md` (after line 920 — add Common Mistakes section)

**Step 1: Add CRITICAL callout before Step 2 SQL template**

At line 221, before the existing `### Step 2: Resolve Relationships (M:1 Only)` section heading, insert nothing. Instead, after the section heading and the existing text at line 225, insert a prominent callout:

After line 225 (the existing "Important:" paragraph), wrap it in a stronger callout:

Replace lines 224-225:

```markdown
**Important:** In relationship tables, `FOCAL01_KEY` and `FOCAL02_KEY` are pattern names from the bootstrap — the actual physical column names are the `attribute_name` values. For example, if the bootstrap shows `attribute_name = ORDER_LINE_KEY` with `table_pattern_column_name = FOCAL01_KEY`, then `ORDER_LINE_KEY` is the real column name.
```

With:

```markdown
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
```

**Step 2: Add inline comments to relationship SQL template**

In the SQL template at lines 227-246, ensure the comments reinforce this. The existing template already has good comments (`-- e.g., ORDER_LINE_KEY (the FOCAL01_KEY attribute)`). Keep those as-is.

**Step 3: Add Common Mistakes section at end of file**

After the DDL Wrapping section (after line 920), add:

```markdown

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
```

**Step 4: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "fix: reinforce FOCAL01/02 → attribute_name mapping rule (#40)"
```

---

### Task 4: Add recursive peripheral discovery + all-entity bridge to uss-patterns.md (#38)

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:860-900` (Fan-Out Prevention / Multi-Hop section)
- Modify: `skills/uss/references/uss-patterns.md:181-183` (Bridge Pattern intro)
- Modify: `skills/uss/references/uss-patterns.md:311-313` (Step 5: UNION ALL description)

**Step 1: Update bridge pattern intro**

At line 182-183, replace:

```markdown
The bridge UNION ALLs fact rows from multiple entities. Each entity contributes:
```

With:

```markdown
The bridge UNION ALLs rows from **ALL entities** — both bridge sources and peripherals. Every entity in the USS participates in the bridge, making each entity both a fact (contributing rows) and a dimension (joinable via FK). Each entity contributes:
```

**Step 2: Update Step 5 UNION ALL description**

At line 311-313, replace:

```markdown
Combine all entity event CTEs into the final bridge. Add a `peripheral` column to identify the source entity. NULL-pad measures that don't exist in a given entity.
```

With:

```markdown
Combine **ALL entity** CTEs (bridge sources AND peripherals) into the final bridge via UNION ALL. Every entity contributes rows — bridge sources contribute their measures and timestamps, peripherals contribute their entity key (with NULL measures/timestamps). Add a `peripheral` column to identify the source entity. NULL-pad columns that don't exist in a given entity.
```

**Step 3: Add Recursive Peripheral Discovery section**

After the existing "Multi-Hop Chain Resolution" section (after line 900), add:

```markdown

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
| 1 | SALES_ORDER_DETAIL | SALES_ORDER, SPECIAL_OFFER, PRODUCT | SPECIAL_OFFER, PRODUCT |
| 1 | SALES_ORDER | CUSTOMER, SALES_PERSON, SALES_TERRITORY | CUSTOMER, SALES_PERSON, SALES_TERRITORY |
| 1 | PURCHASE_ORDER | VENDOR, EMPLOYEE | VENDOR, EMPLOYEE |
| 1 | WORK_ORDER | PRODUCT | (already found) |
| 2 | CUSTOMER | PERSON, STORE, SALES_TERRITORY | PERSON, STORE |
| 2 | SALES_PERSON | EMPLOYEE | (already found) |
| 2 | EMPLOYEE | DEPARTMENT | DEPARTMENT |
| 2 | STORE | SALES_PERSON | (already found) |
| 2 | PERSON | ADDRESS | ADDRESS |
| 3 | ADDRESS | (no M:1 relationships) | — |
| 3 | DEPARTMENT | (no M:1 relationships) | — |

**Final peripheral set:** SPECIAL_OFFER, PRODUCT, CUSTOMER, SALES_PERSON, SALES_TERRITORY, VENDOR, EMPLOYEE, PERSON, STORE, DEPARTMENT, ADDRESS

**All entities in bridge UNION ALL:** SALES_ORDER_DETAIL, SALES_ORDER, PURCHASE_ORDER, WORK_ORDER, SPECIAL_OFFER, PRODUCT, CUSTOMER, SALES_PERSON, SALES_TERRITORY, VENDOR, EMPLOYEE, PERSON, STORE, DEPARTMENT, ADDRESS

### Peripheral Bridge Rows

Peripheral entities contribute rows to the bridge just like bridge sources, but they typically have no measures or timestamps. Their bridge rows contain:

- `peripheral` = entity name (e.g., `'customer'`)
- `_key__{entity}` = entity key (e.g., `CUSTOMER_KEY`)
- All other `_key__*` columns = their own M:1 relationship targets (e.g., `_key__person`, `_key__store`) or NULL
- All `_measure__*` columns = NULL
- `event` / `event_occurred_on` / `_key__dates` / `_key__times` = NULL (unless the peripheral has timestamps)

This means consumers can query `WHERE peripheral = 'customer'` to get one row per customer with all their relationship keys resolved — enabling customer-centric analysis without joining through the bridge sources.
```

**Step 4: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "feat: recursive peripheral discovery + all-entity bridge rows (#38)"
```

---

### Task 5: Add temporal bridge key rule to uss-patterns.md (#39)

**Files:**
- Modify: `skills/uss/references/uss-patterns.md:655-676` (Historical Bridge Pattern, section 2)

**Step 1: Add valid_from to bridge FK columns**

After the existing "### 2. Add valid_from / valid_to columns" section (around line 676), add:

```markdown

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
```

**Step 2: Commit**

```bash
git add skills/uss/references/uss-patterns.md
git commit -m "fix: bridge FK keys include valid_from for temporal peripherals (#39)"
```

---

### Task 6: Update uss-examples.md — column names, peripheral bridge rows, temporal joins (#38, #41, #43)

**Files:**
- Modify: `skills/uss/references/uss-examples.md:109-215` (peripheral SQL examples)
- Modify: `skills/uss/references/uss-examples.md:217-451` (bridge SQL example)
- Modify: `skills/uss/references/uss-examples.md:466-485` (consumer join pattern)

**Step 1: Fix peripheral column names**

Update `customer.sql` example (lines 125-133) — change column aliases:
- `first_name` → `customer_first_name`
- `last_name` → `customer_last_name`
- `email` → `customer_email`
- `city` → `customer_city`

Also replace `daana_dw.` with `{source_schema}.` in all SQL templates.

Update `product.sql` example (lines 153-161) — change column aliases:
- `product_name` stays `product_name` (already correct — `PRODUCT_PRODUCT_NAME` → strip one PRODUCT_ → `PRODUCT_NAME` → `product_name`)
- `category` → `product_category`
- `list_price` → `product_list_price`

Update `order.sql` example (lines 179-214) — replace `daana_dw.` with `{source_schema}.`.

**Step 2: Add peripheral bridge row examples to bridge SQL**

After the existing bridge UNION ALL (after line 450), add CUSTOMER and PRODUCT UNION ALL members:

```sql
UNION ALL

-- ============================================================
-- CUSTOMER: Peripheral bridge rows
-- ============================================================
SELECT
    'customer' AS peripheral,
    NULL::bigint AS _key__order_line,
    NULL::bigint AS _key__order,
    NULL::bigint AS _key__product,
    c.CUSTOMER_KEY AS _key__customer,
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
    p.PRODUCT_KEY AS _key__product,
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

**Step 3: Add historical consumer join pattern**

After the existing consumer join pattern (after line 485), add:

```markdown

### Historical Mode — Temporal Peripheral Joins

When peripherals are generated in historical mode (`valid_from` / `valid_to`), a simple key join produces duplicates — multiple versions of the peripheral match each bridge row. Use a temporal predicate to resolve the correct version:

**Wrong — produces duplicates:**
```sql
-- Multiple valid_from versions per product match → fan-out
SELECT p.product_name, SUM(b._measure__order_line__unit_price)
FROM uss._bridge b
JOIN uss.product p ON b._key__product = p.PRODUCT_KEY
GROUP BY p.product_name
```

**Correct — temporal join:**
```sql
SELECT p.product_name, SUM(b._measure__order_line__unit_price)
FROM uss._bridge b
JOIN uss.product p ON b._key__product = p.PRODUCT_KEY
    AND p.valid_from <= b.event_occurred_on
    AND p.valid_to > b.event_occurred_on
WHERE b.peripheral = 'order_line'
  AND b.event = 'order_placed_on'
GROUP BY p.product_name
```

The temporal predicate `p.valid_from <= b.event_occurred_on AND p.valid_to > b.event_occurred_on` resolves exactly one version of each peripheral row per bridge row.

> **Note:** This only applies when peripherals are historical. Snapshot peripherals have one row per entity key and don't need temporal predicates.
```

**Step 4: Update consumer join pattern column names**

In the existing consumer join pattern (lines 466-485), update column references to match new naming:
- `c.first_name` → `c.customer_first_name`
- `c.last_name` → `c.customer_last_name`
- `p.product_name` stays `p.product_name`

Also replace `daana_dw.` and hardcoded schema references with `{source_schema}`.

**Step 5: Commit**

```bash
git add skills/uss/references/uss-examples.md
git commit -m "fix: update examples for column naming, peripheral bridge rows, temporal joins (#38, #41, #43)"
```

---

### Task 7: Update uss SKILL.md — entity classification + schema instruction (#38, #42)

**Files:**
- Modify: `skills/uss/SKILL.md:36-39` (Entity classification)
- Modify: `skills/uss/SKILL.md:84-86` (Phase 2: Generate)

**Step 1: Update entity classification**

At lines 36-39, replace:

```markdown
Auto-classify entities from the bootstrap:
- **Bridge candidates:** Entities with at least one timestamp attribute (STA_TMSTP or END_TMSTP) and/or numeric attributes (VAL_NUM)
- **Peripheral candidates:** Entities referenced via M:1 relationships (on the FOCAL02_KEY side)
```

With:

```markdown
Auto-classify entities from the bootstrap:
- **Bridge candidates:** Entities with at least one timestamp attribute (STA_TMSTP or END_TMSTP) and/or numeric attributes (VAL_NUM)
- **Peripheral candidates:** ALL entities reachable via recursive M:1 relationship chains from the bridge sources. Follow the "Recursive Peripheral Discovery" algorithm in `uss-patterns.md` — walk every M:1 chain to its terminal entity. Every discovered entity becomes a peripheral AND contributes rows to the bridge.
```

**Step 2: Add source schema instruction to Phase 2**

At line 86, after "Follow the patterns in `${CLAUDE_SKILL_DIR}/references/uss-patterns.md` exactly.", add:

```markdown

**Source schema:** Use `FOCAL_PHYSICAL_SCHEMA` from the bootstrap result as the source schema in all generated SQL `FROM` clauses. This is typically `daana_dw` but varies by installation. Never hardcode the schema — always resolve it from the bootstrap.
```

**Step 3: Commit**

```bash
git add skills/uss/SKILL.md
git commit -m "fix: recursive peripheral discovery + source schema instruction (#38, #42)"
```

---

### Task 8: Fix star dimension-patterns.md (#40, #43)

**Files:**
- Modify: `skills/star/references/dimension-patterns.md:1-10` (Prerequisites section)
- Modify: `skills/star/references/dimension-patterns.md:65-66` (Type 0 SQL template)

**Step 1: Add column naming algorithm after Prerequisites**

After line 9 ("All patterns start from the bootstrap result and generate SQL that materializes a flat dimension table."), add:

```markdown

## Column Naming Convention

Dimension column aliases are derived from the bootstrap's `atomic_context_name`:

1. Take the `atomic_context_name` (e.g., `PRODUCT_PRODUCT_NAME`)
2. Identify the entity name — the `focal_name` without `_FOCAL` (e.g., `PRODUCT`)
3. Strip exactly one leading `{ENTITY}_` prefix (e.g., `PRODUCT_NAME`)
4. Lowercase the result → `product_name`

> **CRITICAL:** Strip only ONE leading `{ENTITY}_` prefix. Do NOT strip recursively. `PRODUCT_PRODUCT_NAME` → `product_name`, never `name`.

| `atomic_context_name` | Entity | Result |
|---|---|---|
| `PRODUCT_PRODUCT_NAME` | PRODUCT | `product_name` |
| `STORE_STORE_NAME` | STORE | `store_name` |
| `DEPARTMENT_DEPARTMENT_NAME` | DEPARTMENT | `department_name` |
| `CUSTOMER_CUSTOMER_FIRST_NAME` | CUSTOMER | `customer_first_name` |

## Relationship Column Names

> **CRITICAL — FOCAL01_KEY / FOCAL02_KEY ARE NOT COLUMN NAMES**
>
> In relationship tables, the bootstrap's `table_pattern_column_name` returns `FOCAL01_KEY` or `FOCAL02_KEY`. These are **pattern indicators**, not physical column names. The actual column names are the `attribute_name` values from the bootstrap.
>
> **NEVER write `SELECT FOCAL01_KEY` or `SELECT FOCAL02_KEY`** — these columns do not exist in physical tables. Use the `attribute_name` instead (e.g., `ORDER_KEY`, `CUSTOMER_KEY`).
```

**Step 2: Commit**

```bash
git add skills/star/references/dimension-patterns.md
git commit -m "fix: add column naming algorithm + FOCAL01/02 warning to dimension patterns (#40, #43)"
```

---

### Task 9: Fix star fact-patterns.md (#40, #42)

**Files:**
- Modify: `skills/star/references/fact-patterns.md:30-51` (Resolving Dimension Keys section)

**Step 1: Add FOCAL01/02 callout and schema reinforcement**

After line 32 ("Every fact table needs foreign keys to its dimensions..."), add:

```markdown

> **CRITICAL — Relationship Column Names**
>
> The bootstrap's `table_pattern_column_name` returns `FOCAL01_KEY` / `FOCAL02_KEY` for relationship tables. These are **pattern indicators**, not physical column names. Always use the `attribute_name` from the bootstrap as the actual SQL column name. For example: `ORDER_KEY`, `CUSTOMER_KEY` — never `FOCAL01_KEY`.

> **Source Schema:** The `[physical_schema]` placeholder in all templates below must be resolved from the bootstrap's `FOCAL_PHYSICAL_SCHEMA` value (e.g., `daana_dw`). Never hardcode the schema or use `focal` as a schema name.
```

**Step 2: Commit**

```bash
git add skills/star/references/fact-patterns.md
git commit -m "fix: add FOCAL01/02 warning + schema rule to fact patterns (#40, #42)"
```

---

### Task 10: Version bump

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Step 1: Read current version**

```bash
cat .claude-plugin/plugin.json | grep version
```

**Step 2: Bump patch version**

Increment the patch version number.

**Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to X.Y.Z"
```

---

### Task 11: Push and verify

**Step 1: Push branch**

```bash
git push
```

**Step 2: Clone adventure-works-ddw for verification**

```bash
gh repo clone mattiasthalen/adventure-works-ddw /tmp/claude-1001/adventure-works-ddw
```

**Step 3: Invoke `/daana-uss` in the adventure-works-ddw repo**

Run the USS skill against the adventure-works-ddw project. During the interview:
- Accept the proposed entity classification (verify recursive discovery found all peripherals)
- Select event-grain unpivot
- Select snapshot mode
- Select all views
- Output to `uss/`

**Step 4: Verify USS output**

Check the generated SQL files for:
- [ ] No `FOCAL01` or `FOCAL02` in any SQL file
- [ ] No `focal.` as schema prefix — only `daana_dw.`
- [ ] Column names: `product_name` not `name`, `store_name` not `name`
- [ ] All peripheral entities discovered (PERSON, STORE, ADDRESS, DEPARTMENT, etc.)
- [ ] All entities contribute bridge rows (UNION ALL members for peripherals)

**Step 5: Invoke `/daana-star` in the adventure-works-ddw repo**

Run the Star skill against the same project.

**Step 6: Verify Star output**

Check the generated SQL files for:
- [ ] No `FOCAL01` or `FOCAL02` in any SQL file
- [ ] No `focal.` as schema prefix
- [ ] Dimension column names properly qualified (`product_name` not `name`)

---

## Parallelization

Tasks 1-5 are sequential edits to `uss-patterns.md` (same file).

Tasks 6-9 are **independent** and can run in parallel:
- Task 6: `uss-examples.md`
- Task 7: `uss SKILL.md`
- Task 8: `star dimension-patterns.md`
- Task 9: `star fact-patterns.md`

But Tasks 6-9 depend on Tasks 1-5 completing first (they reference the new patterns).

**Recommended execution order:**
1. Tasks 1-5 sequentially (all uss-patterns.md edits)
2. Tasks 6-9 in parallel (different files)
3. Task 10 (version bump)
4. Task 11 (push + verify)
