# Plan: Enforce Focal Ways of Working in Query Skill

## Context

The query skill (`/daana-query`) generates SQL queries that aren't compliant with the Focal "ways of working" defined in the [teach_claude_focal](https://github.com/PatrikLager/teach_claude_focal) repository. The current SKILL.md has incorrect latest-query patterns (missing RANK windows), skeletal history patterns (no SQL templates), no cutoff date support, and an incomplete bootstrap query. This plan aligns the query skill with the authoritative Focal documentation.

## Files to modify

| File | Changes |
|------|---------|
| `plugin/skills/query/SKILL.md` | Fix query patterns, add clarifying questions, expand ROW_ST rules, add cutoff support |
| `plugin/skills/query/dialect-postgres.md` | Update bootstrap query to use full join pattern |

## Changes

### 1. Update bootstrap query in dialect-postgres.md (lines 28-41)

Replace the current simple `f_focal_read` SELECT with the full join pattern:

```sql
SELECT
  fr.focal_name,
  fr.focal_physical_schema,
  fr.descriptor_concept_name,
  fr.atomic_context_name,
  fr.atom_contx_key,
  fr.attribute_name,
  fr.atr_key,
  tcn.val_str AS physical_column
FROM daana_metadata.f_focal_read('9999-12-31') fr
LEFT JOIN daana_metadata.logical_physical_x lp
  ON lp.atr_key = fr.atr_key AND lp.atom_contx_key = fr.atom_contx_key AND lp.row_st = 'Y'
LEFT JOIN daana_metadata.tbl_ptrn_col_nm tcn
  ON lp.tbl_ptrn_col_key = tcn.tbl_ptrn_col_key AND tcn.row_st = 'Y'
WHERE fr.focal_physical_schema = 'DAANA_DW'
ORDER BY fr.focal_name, fr.descriptor_concept_name, fr.atomic_context_name
```

Remove the note saying "no join needed". Update column references from `table_pattern_column_name` to `physical_column` throughout.

### 2. Update bootstrap interpretation in SKILL.md (lines 122-134)

Update the column table to reflect the new bootstrap output — replace `table_pattern_column_name` with `physical_column` and add `focal_physical_schema` and `atr_key` columns.

### 3. Add structured clarifying questions table in SKILL.md (after line 158)

Insert a "### Clarifying questions" section with a table of ambiguities the agent MUST resolve before building SQL:

| Ambiguity | Example question |
|-----------|-----------------|
| Entity unclear | "Are you asking about rides, customers, or stations?" |
| Attribute unclear | "By 'customer info', do you mean email, ID, org number, or all?" |
| Multiple matches | "I found CUSTOMER_ID and CUSTOMER_ALT_ID — which one?" |
| Scope unclear | "Do you want all customers, or a specific one?" |
| Latest vs history | "Do you want the current value, or the full change history?" |
| Cutoff date | "As of today, or as of a specific date?" |

Add a rule: **Always ask about the time dimension** — two sequential questions: (1) latest or history? (2) current data or up to a specific cutoff date?

### 4. Fix Pattern 1: Single attribute latest (lines 164-170)

Replace the simple `WHERE row_st = 'Y'` with RANK window pattern:

```sql
SELECT [entity]_key, [physical_column] AS [attribute_name]
FROM (
  SELECT [entity]_key, [physical_column], ROW_ST,
    RANK() OVER (PARTITION BY [entity]_key, TYPE_KEY
                 ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
  FROM daana_dw.[descriptor_table]
  WHERE TYPE_KEY = [atom_contx_key]
    -- Optional cutoff: AND EFF_TMSTP <= '<cutoff>'
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
```

### 5. Fix Pattern 2: Multi-attribute pivot latest (lines 172-182)

Wrap in RANK subquery first, then pivot:

```sql
SELECT
  [entity]_key,
  MAX(CASE WHEN TYPE_KEY = [key1] THEN [physical_column1] END) AS [attr1],
  MAX(CASE WHEN TYPE_KEY = [key2] THEN [physical_column2] END) AS [attr2]
FROM (
  SELECT *, RANK() OVER (
    PARTITION BY [entity]_key, TYPE_KEY
    ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC) AS NBR
  FROM daana_dw.[descriptor_table]
  WHERE TYPE_KEY IN ([key1], [key2])
    -- Optional cutoff: AND EFF_TMSTP <= '<cutoff>'
) A
WHERE NBR = 1 AND ROW_ST = 'Y'
GROUP BY [entity]_key
```

### 6. Fix Pattern 3: Full history (lines 184-195)

Add ROW_ST-aware null handling:

```sql
SELECT
  [entity]_key, EFF_TMSTP, VER_TMSTP,
  CASE WHEN ROW_ST = 'Y' THEN [physical_column] ELSE NULL END AS [attribute_name]
FROM daana_dw.[descriptor_table]
WHERE TYPE_KEY = [atom_contx_key]
  -- Optional cutoff: AND EFF_TMSTP <= '<cutoff>'
ORDER BY [entity]_key, EFF_TMSTP, VER_TMSTP
```

Add note: ROW_ST='N' rows remain in the timeline to show when a value was removed, but data values are nulled out.

### 7. Replace Pattern 4: Temporal alignment with full 5-stage SQL template (lines 197-205)

Replace the skeletal 3-stage description with the complete pattern:

- **Stage 1 `twine`**: UNION ALL per atomic context with TIMELINE labels
- **Stage 2 `in_effect`**: Carry-forward windows (`MAX(CASE WHEN TIMELINE = ... THEN EFF_TMSTP END) OVER (...)`) + RANK for dedup
- **Stage 3 `filtered_in_effect`**: `WHERE RN = 1`
- **Stage 4 per-attribute CTEs**: Extract values with `CASE WHEN ROW_ST = 'Y' THEN [col] ELSE NULL END`
- **Stage 5 final SELECT**: LEFT JOIN all CTEs on entity key + carry-forward timestamps

Include full SQL templates for each stage. Add cutoff note: add `AND EFF_TMSTP <= '<cutoff>'` in each twine UNION ALL member.

### 8. Expand relationship query section (lines 207-209)

Add complete SQL example showing:
- RANK window on relationship table for latest relationships
- JOIN to descriptor tables for attribute resolution
- Note about using `attribute_name` (not `FOCAL01_KEY`/`FOCAL02_KEY`) as physical column names

### 9. Expand ROW_ST filtering rules (lines 211-214)

Replace with detailed explanation:
- Insert-only architecture — rows never physically updated/deleted
- `ROW_ST = 'Y'` = active value, `ROW_ST = 'N'` = value removed at source
- Per-pattern table:
  - Latest (1 & 2): RANK + `NBR = 1` + `ROW_ST = 'Y'`
  - History (3): Include all rows, null out data on `ROW_ST = 'N'`
  - Temporal alignment (4): Don't filter in twine, null out in per-attribute CTEs

### 10. Add cutoff date support section

New section after query patterns explaining:
- Latest + cutoff: `AND EFF_TMSTP <= '<cutoff>'` in inner subquery
- History + cutoff: `AND EFF_TMSTP <= '<cutoff>'` in WHERE or twine members

### 11. Update references throughout SKILL.md

Replace all occurrences of `table_pattern_column_name` with `physical_column` to match the updated bootstrap output.

## Verification

1. **Read the final SKILL.md** and verify all 4 query patterns match the teach_claude_focal agent_workflow.md patterns
2. **Read dialect-postgres.md** and verify the bootstrap query matches the teach_claude_focal CLAUDE.md bootstrap
3. **Check consistency**: bootstrap column names in dialect file match interpretation table in SKILL.md
4. **Diff review**: Ensure no unintended changes to Phase 1 (Connection), Phase 2 (Bootstrap flow/consent), or Phase 4 (Handover)
