# Query Skill Modularization

## Problem

The query skill has two pain points:

1. **Permission prompts** — reading reference files at startup triggers approval prompts before anything useful happens
2. **Mixed concerns** — connection handling, Focal knowledge, SQL dialect, and query patterns are all in one file, making it hard to maintain and extend

The same problems affect model and map skills (out of scope for this PR).

## Decision

**Approach A: Supporting files in skill directory.** Split reference content into sibling files within `skills/query/`. SKILL.md stays lean and references them with `${CLAUDE_SKILL_DIR}`. Claude reads them on demand, not upfront.

### Alternatives considered

- **Approach B (Agent with preloaded skills):** True modularity with reusable sub-skills, but runs in forked context — loses conversation history, which is a dealbreaker for the query workflow.
- **Approach C (Hybrid skill + forked agent):** Best modularity, but same forked context problem.
- **Inlining everything:** Solves permissions but makes SKILL.md bloated and hard to maintain.

Approach A is the simplest change that solves both problems and is a natural stepping stone to B or C if forked context gains conversation history support in the future.

## Structure

```
skills/query/
  SKILL.md                (~150 lines - workflow only)
  focal-framework.md      (Focal architecture, table types, metadata chain)
  dialect-postgres.md     (PostgreSQL connection, bootstrap query, execution, SQL syntax)
  connections.md          (connection profile schema, supported types)
```

## File responsibilities

| File | Content | When read |
|------|---------|-----------|
| `SKILL.md` | Workflow phases, query patterns, consent gates, AskUserQuestion prompts, bootstrap interpretation | Always (it's the skill entrypoint) |
| `connections.md` | Profile schema, supported types, example YAML | Phase 1 — when parsing connections.yaml |
| `focal-framework.md` | Table types, TYPE_KEY semantics, Atomic Context, lineage tracing | Phase 2 — before building first query (needed to understand bootstrap results) |
| `dialect-postgres.md` | Execution command, bootstrap query, QUALIFY alternative, carry-forward pattern, type casting, schema casing | Phase 2 — before bootstrap and all subsequent queries |

## Dialect resolution

The dialect is not hardcoded. After determining the connection type from the profile:

1. Try to read `${CLAUDE_SKILL_DIR}/dialect-<type>.md` (e.g., `dialect-postgres.md`)
2. **If found** — use it as the dialect reference
3. **If not found** — use `AskUserQuestion`:
   - Question: "No native support for [type] yet. I can try translating from PostgreSQL patterns, but results may need tweaking. Want me to try?"
   - Options: "Yes, try transpiling" / "No, cancel"
4. If user accepts transpiling — read `dialect-postgres.md` as reference and adapt SQL to the target dialect

This means adding a new dialect = drop in a `dialect-<type>.md` file. No SKILL.md changes needed.

## Bootstrap query location

The bootstrap query lives in the dialect file, not SKILL.md. The function call (`f_focal_read`), schema casing rules, and execution mechanics are all dialect-specific. SKILL.md describes what bootstrap does and how to interpret results; the dialect file provides the actual query.

## What stays in SKILL.md

- Phase workflow (Connection, Bootstrap, Query Loop, Handover)
- Bootstrap result interpretation (column meanings, relationship detection)
- Query patterns (single attribute, multi-attribute pivot, full history, temporal alignment)
- ROW_ST filtering rules
- Safety guardrails
- Execution consent gates (AskUserQuestion)
- Result presentation format
- Handover to `/daana-model`

## Out of scope

- Applying the same pattern to model and map skills (separate PR)
- Creating new dialect files beyond PostgreSQL
