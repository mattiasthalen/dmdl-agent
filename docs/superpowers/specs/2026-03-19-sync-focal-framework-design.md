# Sync Focal Framework — Design Spec

## Context

The `teach_claude_focal` external reference is 2 commits behind (`d49cb259` → `280f8e45`). All changes are in `agent_workflow.md` (393 insertions, 22 deletions). Our `query-patterns.md` and `SKILL.md` need updating to match.

## Approach

Targeted merge — port each upstream change into our existing file structure.

## Changes

### 1. Relationship RANK Pattern (query-patterns.md)

**Current:** "Joining relationship tables to descriptor tables" section (lines 283-297) uses a direct join with `row_st = 'Y'` filter — no RANK deduplication.

**Problem:** Relationships are temporal. A direct `row_st = 'Y'` filter without RANK returns multiple rows if the relationship changed at different timestamps.

**Change:**
- Add a "Relationship tables in latest queries" subsection under Pattern 1 showing the RANK CTE template for relationships.
- Replace the "Joining relationship tables to descriptor tables" section with a CTE-based approach:
  1. Relationships get their own CTE with `RANK() OVER (PARTITION BY entity1_key, entity2_key ORDER BY eff_tmstp DESC, ver_tmstp DESC)` + `NBR = 1 AND ROW_ST = 'Y'`
  2. Descriptor tables also get their own RANK CTE
  3. Final SELECT joins resolved CTEs — not raw tables

### 2. Pattern 3 — Multi-Entity History (query-patterns.md)

**New section** after Pattern 2. Covers cross-entity temporal queries.

**Architecture — three modules:**
- **Module 1+2 (combined twine):** Anchor entity's descriptor attributes + relationship table merged into one UNION ALL twine (they share the anchor key). The related entity's key is carried as a value column.
- **Module 3 (independent):** Related entity runs its own standard Pattern 2 history, keyed on its own key.
- **Final join:** Anchor CTEs via carry-forward timestamps (standard Pattern 2). Related entity CTEs via LATERAL point-in-time lookup using the carried-forward related key.

**Sub-sections:** When to use, architecture table, combined twine SQL, carry-forward + deduplication, per-attribute CTEs, related entity module, final LATERAL join, cutoff date modifier, fidelity note, multiple relationships, building from bootstrap steps.

PostgreSQL-only (LATERAL joins). No dialect-agnostic fallback needed — the dialect system handles platform differences.

### 3. Decision Tree Updates (query-patterns.md + SKILL.md)

**query-patterns.md:** Update the decision tree to route cross-entity history to Pattern 3:

```
├─ Latest or history?
│   ├─ LATEST → Pattern 1 (relationships use same RANK CTE)
│   └─ HISTORY
│       ├─ Single entity? → Pattern 2
│       └─ Cross-entity? → Pattern 3
│
└─ Cutoff date?
    ├─ NO → no eff_tmstp filter
    └─ YES → add to inner query (P1), twine CTEs + LATERAL WHERE (P2/P3)
```

**SKILL.md:** Mirror the same routing logic in the Phase 3 query loop decision flow.

### 4. Worked Example + Workaround (query-patterns.md)

**Worked example:** Replace the current direct-join invoice/supplier example with the CTE-based version. Three separate CTEs (`invoice_amount`, `invoice_supplier`, `supplier_name`), each using the RANK pattern, joined in the final SELECT. Takeaway #5 updated: every table (descriptors AND relationships) uses the same RANK pattern.

**EFF_TMSTP workaround:** New section at end: "Workaround: Relationship EFF_TMSTP on daana-cli <= 0.5.18". Contents:
- Bug explanation (standard install doesn't apply `entity_effective_timestamp_expression` to relationship tables)
- Prerequisites (source tables need `updated_at`, `allow_multiple_identifiers: false`)
- Generic UPDATE pattern joining back to source via natural keys
- Note: post-execution patch, must be re-applied after every `daana-cli execute`

### 5. Bump external.lock

Update `teach_claude_focal` pinned commit from `d49cb259e02de9f989298902b95b37a73ab7edf3` to `280f8e457afc82bf00af864a9cdd00bae745ecc9`.

## Files Changed

| File | Change |
|------|--------|
| `plugin/skills/query/query-patterns.md` | 4 edits (RANK pattern, Pattern 3, decision tree, worked example + workaround) |
| `plugin/skills/query/SKILL.md` | 1 edit (decision tree routing) |
| `external.lock` | Bump teach_claude_focal commit |

## Out of Scope

- `focal-framework.md` — no upstream changes affect this file
- Dialect-agnostic fallbacks for LATERAL joins
- daana-cli changes
