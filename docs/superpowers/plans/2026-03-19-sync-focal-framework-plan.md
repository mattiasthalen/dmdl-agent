# Sync Focal Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Sync query skill files with upstream teach_claude_focal changes (2 commits behind) — adding relationship RANK patterns, Pattern 3 (Multi-Entity History), and EFF_TMSTP workaround.

**Architecture:** Targeted merge of upstream `agent_workflow.md` changes into our existing `query-patterns.md` and `SKILL.md`. No new files. The upstream diff is the source of truth for SQL patterns.

**Tech Stack:** Markdown (skill documentation), SQL (pattern templates)

**Worktree:** `.worktrees/feat/sync-focal-framework` (branch: `feat/sync-focal-framework`)

---

### Task 1: Add relationship RANK pattern to Pattern 1 section

**Files:**
- Modify: `plugin/skills/query/query-patterns.md:79` (after Complex atomic contexts section)

**Step 1: Add "Relationship tables in latest queries" subsection**

Insert after line 79 (end of Complex atomic contexts code block), before the Pattern 2 heading at line 81:

```markdown
### Relationship tables in latest queries

Relationship tables follow the **same RANK pattern** as descriptor tables. Relationships are temporal — they can change over time — so a direct `row_st = 'Y'` filter without RANK would return multiple rows if the relationship changed at different timestamps. Always resolve the latest active relationship first in its own CTE:

` ` `sql
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
` ` `

Then join to this CTE (not directly to the relationship table) when combining with descriptor data.
```

**Step 2: Verify the insertion point**

Read `query-patterns.md` lines 75-90 to confirm the new subsection sits between Complex atomic contexts and Pattern 2.

**Step 3: Commit**

```bash
git add plugin/skills/query/query-patterns.md
git commit -m "feat(query): add relationship RANK pattern to Pattern 1 section"
```

---

### Task 2: Replace relationship join section with CTE-based approach

**Files:**
- Modify: `plugin/skills/query/query-patterns.md:281-297` (the "Joining relationship tables to descriptor tables" section)

**Step 1: Replace the section**

Replace lines 281-297 (from `### Joining relationship tables to descriptor tables` through the `**Important:**` paragraph) with:

```markdown
### Building a relationship query

Relationship tables are temporal just like descriptor tables. In **latest** queries, always resolve relationships using the RANK pattern first, then join the result to descriptor CTEs:

` ` `sql
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
` ` `

**Important:** The physical column names in relationship tables (`FOCAL01_KEY`, `FOCAL02_KEY`) are generic pattern columns. The metadata maps them to logical entity key names. When joining to descriptor tables, use the descriptor table's own entity key column (e.g., `station_key` in `station_desc`), not the generic pattern column name.
```

**Step 2: Verify the replacement**

Read `query-patterns.md` around the replacement to confirm it flows correctly between "Column name rule" and "Bootstrap Fallback".

**Step 3: Commit**

```bash
git add plugin/skills/query/query-patterns.md
git commit -m "feat(query): replace direct relationship joins with CTE-based RANK approach"
```

---

### Task 3: Add Pattern 3 — Multi-Entity History

**Files:**
- Modify: `plugin/skills/query/query-patterns.md` (insert after Pattern 2's "Building this from the bootstrap" section, before "## Relationship Queries")

**Step 1: Insert Pattern 3 section**

Insert the following new section before the `## Relationship Queries` heading:

```markdown
## Pattern 3: Multi-Entity History

When the user wants a **history view that spans multiple entities connected through relationships**, the agent must combine independent temporal timelines from different tables — each with its own key — into one golden timeline.

This extends Pattern 2 (single-entity history) with a modular approach: each entity and relationship is resolved independently, then composed.

### When to use this pattern

- The user asks for history across entities (e.g. "order line revenue history with product names")
- The query involves relationship tables that connect the entities
- The user needs to see how cross-entity data evolved over time

### Architecture: Three modules

| Module | Source | Key | Produces |
|--------|--------|-----|----------|
| **Anchor descriptors** | `[ANCHOR]_DESC` | `[ANCHOR]_KEY` | Per-attribute CTEs (values from the anchor entity) |
| **Relationship** | `[ANCHOR]_[RELATED]_X` | `[ANCHOR]_KEY` + `[RELATED]_KEY` | CTE carrying forward the related entity's key |
| **Related descriptors** | `[RELATED]_DESC` | `[RELATED]_KEY` | Per-attribute CTEs (values from the related entity) |

The **anchor entity** is the primary entity the query is about — the one whose key defines the golden timeline. The agent infers this from the user's question (e.g. "order line revenue" → anchor is ORDER_LINE).

### Module 1 + 2: Combined twine (anchor descriptors + relationship)

The anchor's descriptor attributes and the relationship share the same anchor key, so they merge into **one twine**. The relationship's related-entity key (`[RELATED]_KEY`) is included as a value column to be carried forward alongside the descriptor values.

` ` `sql
WITH twine AS (
  -- Anchor descriptor attribute 1
  SELECT [ANCHOR]_KEY, type_key, eff_tmstp, ver_tmstp, row_st,
         [physical_column_1], CAST(NULL AS VARCHAR) AS [RELATED]_KEY,
         '[ATOMIC_CONTEXT_NAME_1]' AS timeline
  FROM [physical_schema].[anchor_desc_table]
  WHERE type_key = [key1]
  UNION ALL
  -- Anchor descriptor attribute 2
  SELECT [ANCHOR]_KEY, type_key, eff_tmstp, ver_tmstp, row_st,
         [physical_column_2], NULL,
         '[ATOMIC_CONTEXT_NAME_2]' AS timeline
  FROM [physical_schema].[anchor_desc_table]
  WHERE type_key = [key2]
  -- ... one UNION ALL per anchor atomic context ...
  UNION ALL
  -- Relationship (both keys are values — the combination represents an event)
  SELECT [ANCHOR]_KEY, type_key, eff_tmstp, ver_tmstp, row_st,
         CAST(NULL AS NUMERIC) AS [physical_column], [RELATED]_KEY,
         '[RELATIONSHIP_NAME]' AS timeline
  FROM [physical_schema].[relationship_table]
  WHERE type_key = [rel_key]
)
` ` `

**Column alignment:** The UNION ALL requires consistent columns. Descriptor rows have NULL for `[RELATED]_KEY`; relationship rows have NULL for value columns. Cast NULLs to match the column types.

Then apply the standard carry-forward and deduplication stages from Pattern 2:

` ` `sql
, in_effect AS (
  SELECT
    [ANCHOR]_KEY, type_key, eff_tmstp, ver_tmstp, row_st,
    [physical_column], [RELATED]_KEY,
    -- Carry-forward per anchor descriptor attribute
    MAX(CASE WHEN timeline = '[ATOMIC_CONTEXT_NAME_1]' THEN eff_tmstp END)
      OVER (PARTITION BY [ANCHOR]_KEY ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_[ATOMIC_CONTEXT_NAME_1],
    MAX(CASE WHEN timeline = '[ATOMIC_CONTEXT_NAME_2]' THEN eff_tmstp END)
      OVER (PARTITION BY [ANCHOR]_KEY ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_[ATOMIC_CONTEXT_NAME_2],
    -- ... one carry-forward column per anchor atomic context ...
    -- Carry-forward for the relationship
    MAX(CASE WHEN timeline = '[RELATIONSHIP_NAME]' THEN eff_tmstp END)
      OVER (PARTITION BY [ANCHOR]_KEY ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_[RELATIONSHIP_NAME],
    RANK() OVER (
      PARTITION BY [ANCHOR]_KEY, eff_tmstp
      ORDER BY eff_tmstp DESC
    ) AS rn
  FROM twine
)

, filtered_in_effect AS (
  SELECT * FROM in_effect WHERE rn = 1
)
` ` `

Per-attribute CTEs for anchor descriptors follow the standard Pattern 2 approach. The relationship CTE extracts the carried-forward related-entity key:

` ` `sql
-- Anchor descriptor CTEs (standard)
, cte_[ATOMIC_CONTEXT_NAME_1] AS (
  SELECT [ANCHOR]_KEY, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN [physical_column] ELSE NULL END AS [attribute_name]
  FROM filtered_in_effect
  WHERE type_key = [key1]
)
-- ... one CTE per anchor atomic context ...

-- Relationship CTE (carries forward the related entity key)
, cte_[RELATIONSHIP_NAME] AS (
  SELECT [ANCHOR]_KEY, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN [RELATED]_KEY ELSE NULL END AS [RELATED]_KEY
  FROM filtered_in_effect
  WHERE type_key = [rel_key]
)
` ` `

### Module 3: Related entity history (self-contained)

The related entity runs its own independent history pattern, keyed on `[RELATED]_KEY`. This is a standard Pattern 2 applied to the related entity's descriptor table:

` ` `sql
, related_twine AS (
  SELECT [RELATED]_KEY, type_key, eff_tmstp, ver_tmstp, row_st,
         [physical_column],
         '[RELATED_ATOMIC_CONTEXT_NAME]' AS timeline
  FROM [physical_schema].[related_desc_table]
  WHERE type_key = [related_key]
  -- ... UNION ALL for additional related attributes ...
)
, related_in_effect AS (
  SELECT
    [RELATED]_KEY, type_key, eff_tmstp, ver_tmstp, row_st, [physical_column],
    RANK() OVER (PARTITION BY [RELATED]_KEY, eff_tmstp ORDER BY eff_tmstp DESC) AS rn
  FROM related_twine
)
, related_filtered AS (
  SELECT * FROM related_in_effect WHERE rn = 1
)
, cte_[RELATED_ATOMIC_CONTEXT_NAME] AS (
  SELECT [RELATED]_KEY, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN [physical_column] ELSE NULL END AS [related_attribute_name]
  FROM related_filtered
  WHERE type_key = [related_key]
)
` ` `

### Final join: Composing the modules

Join the anchor's golden timeline to its own CTEs using carry-forward timestamps (standard Pattern 2), then bridge to the related entity via a **point-in-time LATERAL join**:

` ` `sql
SELECT DISTINCT
  fie.[ANCHOR]_KEY,
  fie.eff_tmstp,
  cte1.[attribute_name_1],
  cte2.[attribute_name_2],
  -- ... anchor attributes ...
  cte_rel.[RELATED]_KEY,
  related_pn.[related_attribute_name]
FROM filtered_in_effect fie
-- Anchor descriptor CTEs (standard carry-forward join)
LEFT JOIN cte_[ATOMIC_CONTEXT_NAME_1] cte1
  ON fie.[ANCHOR]_KEY = cte1.[ANCHOR]_KEY
  AND fie.eff_tmstp_[ATOMIC_CONTEXT_NAME_1] = cte1.eff_tmstp
LEFT JOIN cte_[ATOMIC_CONTEXT_NAME_2] cte2
  ON fie.[ANCHOR]_KEY = cte2.[ANCHOR]_KEY
  AND fie.eff_tmstp_[ATOMIC_CONTEXT_NAME_2] = cte2.eff_tmstp
-- ... one LEFT JOIN per anchor atomic context ...
-- Relationship CTE (carry-forward join — resolves which related entity was linked)
LEFT JOIN cte_[RELATIONSHIP_NAME] cte_rel
  ON fie.[ANCHOR]_KEY = cte_rel.[ANCHOR]_KEY
  AND fie.eff_tmstp_[RELATIONSHIP_NAME] = cte_rel.eff_tmstp
-- Related entity attributes (point-in-time lookup via LATERAL)
LEFT JOIN LATERAL (
  SELECT [related_attribute_name]
  FROM cte_[RELATED_ATOMIC_CONTEXT_NAME]
  WHERE [RELATED]_KEY = cte_rel.[RELATED]_KEY
    AND eff_tmstp <= fie.eff_tmstp
  ORDER BY eff_tmstp DESC
  LIMIT 1
) related_pn ON TRUE
` ` `

**How the LATERAL join works:** At each row on the anchor's golden timeline, the carry-forward has already resolved *which* related entity is linked (via `cte_rel.[RELATED]_KEY`). The LATERAL subquery then looks into the related entity's own history to find the attribute value that was in effect at that moment — the latest `eff_tmstp` that is `<=` the golden timeline's timestamp.

### Cutoff date modifier

Add `AND eff_tmstp <= '<cutoff>'` to:
- Each UNION ALL member in the anchor `twine`
- Each UNION ALL member in the `related_twine`
- The LATERAL subquery's `WHERE` clause (already filtered by `<= fie.eff_tmstp`, which will be bounded by the cutoff)

### Fidelity note

This pattern captures events from the **anchor entity's perspective**. If a related entity's attribute changes (e.g. product name updated) but nothing changes on the anchor side, that event will **not** appear as a new row on the golden timeline — the LATERAL lookup will resolve the updated name at the next anchor event.

For most analytical queries (revenue aggregation, status tracking), this is the correct behavior — the related entity's attributes serve as labels resolved at lookup time. If full fidelity is needed (a new timeline row for every change in any connected entity), the related entity's events must be projected onto the anchor's timeline by including them in the anchor's twine — but this requires resolving the relationship first, creating a two-pass approach.

### Multiple relationships

If the query involves multiple relationship tables (e.g. ORDER → CUSTOMER and ORDER → EMPLOYEE), add each relationship as an additional UNION ALL member in the anchor twine with its own timeline label, carry-forward column, and CTE. Each related entity gets its own independent history module and LATERAL join in the final SELECT.

### Building this from the bootstrap

1. **Identify the anchor entity** from the user's question
2. **Anchor twine:** UNION ALL members from the anchor's `descriptor_concept_name` (descriptor tables) + relationship tables where the anchor is the FOCAL01_KEY side. Include the related entity's key column as a value in the UNION ALL.
3. **Carry-forward:** One column per anchor atomic context + one per relationship
4. **Per-attribute CTEs:** Standard for descriptors; relationship CTE extracts the related key
5. **Related entity modules:** For each related entity, run a standard Pattern 2 history on its descriptor table
6. **Final join:** Anchor CTEs via carry-forward timestamps; related entity CTEs via LATERAL point-in-time lookup using the carried-forward related key
```

**Step 2: Verify the insertion**

Read `query-patterns.md` to confirm Pattern 3 sits between Pattern 2's "Building this from the bootstrap" section and `## Relationship Queries`.

**Step 3: Commit**

```bash
git add plugin/skills/query/query-patterns.md
git commit -m "feat(query): add Pattern 3 Multi-Entity History with LATERAL joins"
```

---

### Task 4: Update decision tree in query-patterns.md

**Files:**
- Modify: `plugin/skills/query/query-patterns.md` (the `## Decision Tree` section)

**Step 1: Replace the decision tree**

Find the existing decision tree (currently between `## Decision Tree` and `---`) and replace it with:

```markdown
## Decision Tree

` ` `
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
  │   ├─ YES → resolve relationship table
  │   └─ NO → single table query
  │
  ├─ Latest or history? (HARD-GATE)
  │   ├─ LATEST → Pattern 1
  │   │   └─ Relationships use the same RANK pattern in their own CTE
  │   │
  │   └─ HISTORY
  │       ├─ Single entity? → Pattern 2: Temporal Alignment (carry-forward + per-attribute CTEs + join)
  │       └─ Cross-entity? → Pattern 3: Multi-Entity History
  │           ├─ Anchor descriptors + relationship → combined twine (same anchor key)
  │           ├─ Related entity descriptors → independent history module (own key)
  │           └─ Final join: carry-forward for anchor CTEs + LATERAL point-in-time for related CTEs
  │
  └─ Cutoff date? (HARD-GATE)
      ├─ NO → use current data (no eff_tmstp filter)
      └─ YES → add eff_tmstp <= '<cutoff>' to inner query (Pattern 1), twine CTEs + LATERAL WHERE (Pattern 2/3)
` ` `
```

**Step 2: Verify the replacement**

Read the decision tree section to confirm it renders correctly.

**Step 3: Commit**

```bash
git add plugin/skills/query/query-patterns.md
git commit -m "feat(query): update decision tree to route cross-entity history to Pattern 3"
```

---

### Task 5: Update worked example with CTE-based RANK approach

**Files:**
- Modify: `plugin/skills/query/query-patterns.md` (the "End-to-End Worked Example" section, specifically Step 4 and Key takeaways)

**Step 1: Replace Step 4 "Build the query"**

Find the current Step 4 SQL block and key takeaways (from `#### Step 4: Build the query` to end of file) and replace with:

```markdown
#### Step 4: Build the query

Every table — descriptors AND relationships — uses the same RANK pattern for latest queries:

` ` `sql
WITH invoice_amount AS (
  SELECT
    invoice_key,
    MAX(CASE WHEN type_key = 42 THEN val_num END) AS amount
  FROM (
    SELECT invoice_key, type_key, row_st, val_num,
      RANK() OVER (PARTITION BY invoice_key, type_key ORDER BY eff_tmstp DESC, ver_tmstp DESC) AS nbr
    FROM daana_dw.invoice_desc
    WHERE type_key = 42
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY invoice_key
),
invoice_supplier AS (
  SELECT invoice_key, supplier_key
  FROM (
    SELECT invoice_key, supplier_key, row_st,
      RANK() OVER (PARTITION BY invoice_key, supplier_key ORDER BY eff_tmstp DESC, ver_tmstp DESC) AS nbr
    FROM daana_dw.invoice_supplier_x
    WHERE type_key = 50
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
),
supplier_name AS (
  SELECT
    supplier_key,
    MAX(CASE WHEN type_key = 61 THEN val_str END) AS supplier_name
  FROM (
    SELECT supplier_key, type_key, row_st, val_str,
      RANK() OVER (PARTITION BY supplier_key, type_key ORDER BY eff_tmstp DESC, ver_tmstp DESC) AS nbr
    FROM daana_dw.supplier_desc
    WHERE type_key = 61
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY supplier_key
)
SELECT
  sn.supplier_name,
  SUM(ia.amount) AS total_amount
FROM invoice_amount ia
JOIN invoice_supplier isx
  ON ia.invoice_key = isx.invoice_key
JOIN supplier_name sn
  ON isx.supplier_key = sn.supplier_key
GROUP BY sn.supplier_name
ORDER BY total_amount DESC
` ` `

#### Key takeaways

1. **The agent never assumed any model structure.** Everything was discovered from the bootstrap.
2. **Entity names, attribute names, and column names were all different from any prior example.** The process works regardless of domain.
3. **The agent matched natural language to metadata names.** "amount" → `INVOICE_AMOUNT`, "supplier" → `SUPPLIER_NAME`.
4. **Relationship columns used `attribute_name`, not `table_pattern_column_name`.** The agent detected `FOCAL01_KEY`/`FOCAL02_KEY` and switched to attribute names.
5. **Every table uses the same RANK pattern.** Descriptors and relationship tables both use `RANK() OVER (...) + nbr = 1 + row_st = 'Y'` in latest queries — relationships are temporal and must be resolved to their latest active state, not just filtered by `row_st = 'Y'`.
6. **The agent asked clarifying questions** when "total" could mean different things.
```

**Step 2: Verify the replacement**

Read the worked example section to confirm the SQL and takeaways are correct.

**Step 3: Commit**

```bash
git add plugin/skills/query/query-patterns.md
git commit -m "feat(query): update worked example to use CTE-based RANK approach"
```

---

### Task 6: Add EFF_TMSTP workaround section

**Files:**
- Modify: `plugin/skills/query/query-patterns.md` (append before end of file, after the worked example)

**Step 1: Append the workaround section**

Add after the Key takeaways (end of worked example):

```markdown

---

## Workaround: Fixing relationship EFF_TMSTP on PostgreSQL (daana-cli <= 0.5.18)

> **Temporary note.** As of daana-cli 0.5.18, the standard (non-focalc) installation does not apply `entity_effective_timestamp_expression` to relationship tables — they always receive `CURRENT_TIMESTAMP`. The experimental `--use-focalc` flag fixes this but does not fully populate the metadata layer. Until this is resolved in a future release, the workaround below can be used to patch relationship timestamps after execution.

**Prerequisites:**
- Source tables must have an `updated_at` column (or equivalent timestamp)
- The installation uses `allow_multiple_identifiers: false`, so entity keys in the DW match the natural business keys from the source

**Pattern:** For each relationship table, join back to the source table using the natural key and update `EFF_TMSTP`:

` ` `sql
-- Relationship sourced from a table that has its own updated_at
UPDATE daana_dw.[RELATIONSHIP_TABLE] rx
SET eff_tmstp = src.updated_at
FROM [source_schema].[source_table] src
WHERE rx.[FOCAL01_KEY] = CAST(src.[source_pk] AS VARCHAR);

-- Relationship sourced from a junction table with a composite key
UPDATE daana_dw.[RELATIONSHIP_TABLE] rx
SET eff_tmstp = parent.updated_at
FROM [source_schema].[parent_table] parent
WHERE CAST(parent.[parent_pk] AS VARCHAR) = SPLIT_PART(rx.[FOCAL01_KEY], '|', 1);

-- Relationship where all rows share a fixed date (static reference data)
UPDATE daana_dw.[RELATIONSHIP_TABLE] SET eff_tmstp = '[fixed_date]';
` ` `

**Important:** This is a post-execution patch — it must be re-applied after every `daana-cli execute`. It does not survive re-execution.
```

**Step 2: Verify the addition**

Read the end of `query-patterns.md` to confirm the workaround section is appended correctly.

**Step 3: Commit**

```bash
git add plugin/skills/query/query-patterns.md
git commit -m "feat(query): add EFF_TMSTP workaround for daana-cli <= 0.5.18"
```

---

### Task 7: Update SKILL.md decision tree routing

**Files:**
- Modify: `plugin/skills/query/SKILL.md:280-283` (the pattern routing after Question 1)

**Step 1: Update the pattern routing text**

Find the current routing text (lines 280-283):

```
- **Latest** — use Pattern 1 from query-patterns.md. Ask again next time.
- **Full history** — use Pattern 2 (Temporal Alignment) from query-patterns.md. Ask again next time.
- **Latest, don't ask again** — default to Pattern 1 for all future queries. Do not ask again.
- **History, don't ask again** — default to Pattern 2 for all future queries. Do not ask again.
```

Replace with:

```
- **Latest** — use Pattern 1 from query-patterns.md (relationships use the same RANK CTE pattern). Ask again next time.
- **Full history** — use Pattern 2 (single entity) or Pattern 3 (cross-entity) from query-patterns.md. Ask again next time.
- **Latest, don't ask again** — default to Pattern 1 for all future queries. Do not ask again.
- **History, don't ask again** — default to Pattern 2 or 3 (based on whether cross-entity) for all future queries. Do not ask again.
```

**Step 2: Verify the change**

Read `SKILL.md` lines 275-290 to confirm the routing text is correct.

**Step 3: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat(query): update SKILL.md routing to reference Pattern 3 for cross-entity history"
```

---

### Task 8: Bump external.lock

**Files:**
- Modify: `external.lock:6`

**Step 1: Update the pinned commit**

Change the `teach_claude_focal` commit from `d49cb259e02de9f989298902b95b37a73ab7edf3` to `280f8e457afc82bf00af864a9cdd00bae745ecc9`.

**Step 2: Verify the change**

Read `external.lock` to confirm the new commit hash and that `daana-cli` is unchanged.

**Step 3: Commit**

```bash
git add external.lock
git commit -m "chore: bump teach_claude_focal to 280f8e4"
```

---

### Task 9: Bump plugin version

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`

**Step 1: Read current version**

Read `plugin/.claude-plugin/plugin.json` and find the current `version` field.

**Step 2: Bump the patch version**

Increment the patch version (e.g., `0.5.0` → `0.6.0` for a feature).

**Step 3: Commit**

```bash
git add plugin/.claude-plugin/plugin.json
git commit -m "chore: bump plugin version"
```

---

### Task 10: Final verification and push

**Step 1: Review all changes**

Run `git log --oneline` in the worktree to verify all commits are present and in order.

**Step 2: Diff check**

Run `git diff main..HEAD --stat` to confirm only the expected files were changed:
- `plugin/skills/query/query-patterns.md`
- `plugin/skills/query/SKILL.md`
- `external.lock`
- `plugin/.claude-plugin/plugin.json`
- `docs/superpowers/specs/2026-03-19-sync-focal-framework-design.md`
- `docs/superpowers/plans/2026-03-19-sync-focal-framework-plan.md`

**Step 3: Push branch**

```bash
git push -u origin feat/sync-focal-framework
```
