# Focal Skill Rearchitecture Design

**Date:** 2026-03-24
**Issue:** #32 — Rearchitect focal from agent to skill invocation pattern

## Context

PR #29 (unmerged) proposed a focal **agent** (subagent) for shared Focal knowledge. Subagents lose main session context, requiring state-passing. This design replaces the agent pattern with a **skill** pattern — `daana:focal` as a prerequisite invoked by consumer skills. Skills load into the main context via the Skill tool (proven by the superpowers plugin pattern), avoiding context forking.

## Scope

- Create `focal` skill with connection + bootstrap workflow and early-exit
- Refactor `query` skill to invoke `daana:focal` as prerequisite
- Create `uss` skill (Unified Star Schema generation) using the same pattern
- Create `star` skill skeleton using the same pattern
- Migrate reference files to their new owners

## Approach

**Focal as standalone skill (Approach A).** `daana:focal` is its own skill under `skills/focal/`. Consumer skills declare `**REQUIRED SUB-SKILL:** Use daana:focal`. Focal early-exits if bootstrap context is already present in the session.

Chosen over:
- **Inline reference block** — would duplicate bootstrap logic across consumers and force-load context
- **Routing skill** — would tightly couple focal to consumers and break existing invocation patterns

---

## Focal Skill

### Structure

```
skills/focal/
  SKILL.md
  references/
    focal-framework.md    (moved from query)
    bootstrap.md          (moved from query)
    connections.md        (moved from query)
    dialect-postgres.md   (moved from query)
```

### Behavior

**Early-exit gate:** On invocation, focal checks if the bootstrap result (the metadata entity/attribute listing from `f_focal_read()`) is already present in the conversation context. If yes — announce "Focal context already active, skipping bootstrap" and exit. If no — run full flow.

**Full flow (3 phases):**

1. **Connection** — Read `connections.md`, discover available profiles, ask user to confirm which profile to use.
2. **Bootstrap** — Run `f_focal_read()` per `bootstrap.md`, present discovered entities/attributes to user.
3. **Context handoff** — Expose the active dialect (derived from connection profile type) and bootstrap results. No explicit handoff needed — everything is in the conversation context.

**Dialect awareness:** Focal loads the appropriate dialect file based on the connection profile type. Only `dialect-postgres.md` exists in this deliverable. The pattern supports future dialect files (`dialect-bigquery.md`, etc.).

---

## Query Skill Refactor

### Changes

**Removed:**
- Phase 1 (Connection) — moved to focal
- Phase 2 (Bootstrap) — moved to focal
- Reference files: `focal-framework.md`, `bootstrap.md`, `connections.md`, `dialect-postgres.md`

**Added:**
- `**REQUIRED SUB-SKILL:** Use daana:focal` at top of SKILL.md

**Retained:**
- Phase 3 (Query Loop) — renamed to Phase 1
- Phase 4 (Handover) — renamed to Phase 2
- `references/ad-hoc-query-agent.md`

### Resulting structure

```
skills/query/
  SKILL.md
  references/
    ad-hoc-query-agent.md
```

---

## USS Skill

### Structure

```
skills/uss/
  SKILL.md
  references/
    uss-patterns.md     (carried from PR #29)
    uss-examples.md     (carried from PR #29)
```

### Behavior

**Prerequisite:** `**REQUIRED SUB-SKILL:** Use daana:focal`

**Interview flow (4 phases):**

1. **Entity Selection** — Using bootstrap metadata, classify entities as bridge candidates (fact-bearing) or peripheral candidates (M:1 referenced). Present to user for confirmation. Flag M:M relationships as unsupported.
2. **Temporal Mode** — Event-grain unpivot (recommended) or columnar dates.
3. **Historical Mode** — Snapshot (latest via RANK dedup) or historical (valid_from/valid_to).
4. **Materialization & Output** — Materialization strategy (all views, all tables, bridge-as-table, custom mix). Output directory (ask user, suggest sensible default). Generate and write files.

### Generated files

- `_bridge.sql` — UNION ALL of fact-bearing entities with resolved FK keys, unpivoted events (if event-grain), synthetic date/time keys.
- `{entity}.sql` — One peripheral per entity, all attributes pivoted from descriptor tables via `MAX(CASE WHEN type_key = ... THEN ...)`.
- `_dates.sql` — Synthetic date spine via `generate_series` (min/max year from bridge).
- `_times.sql` — Synthetic time spine (86,400 rows, second grain).

### Dialect awareness

USS reads the active dialect from focal's context and uses dialect-specific SQL patterns from `uss-patterns.md`. Only Postgres patterns in this deliverable.

---

## Star Skill Skeleton

### Structure

```
skills/star/
  SKILL.md
  references/
    dimension-patterns.md   (moved from query)
    fact-patterns.md        (moved from query)
```

### Behavior

Minimal placeholder:
- `**REQUIRED SUB-SKILL:** Use daana:focal`
- Brief description of intent (traditional star schema generation)
- Note that the skill is not yet implemented
- No interview flow, no SQL generation

---

## File Movement Summary

### Migrations

| File | From | To |
|---|---|---|
| `focal-framework.md` | `skills/query/references/` | `skills/focal/references/` |
| `bootstrap.md` | `skills/query/references/` | `skills/focal/references/` |
| `connections.md` | `skills/query/references/` | `skills/focal/references/` |
| `dialect-postgres.md` | `skills/query/references/` | `skills/focal/references/` |
| `dimension-patterns.md` | `skills/query/references/` | `skills/star/references/` |
| `fact-patterns.md` | `skills/query/references/` | `skills/star/references/` |

### Stays in query

| File | Status |
|---|---|
| `ad-hoc-query-agent.md` | Unchanged |

### New files

| File | Source |
|---|---|
| `skills/focal/SKILL.md` | New |
| `skills/uss/SKILL.md` | New |
| `skills/uss/references/uss-patterns.md` | Carried from PR #29 |
| `skills/uss/references/uss-examples.md` | Carried from PR #29 |
| `skills/star/SKILL.md` | New (skeleton) |

### Plugin updates

- `plugin.json` — version bump (1.9.0 -> 1.10.0)
- `CLAUDE.md` — update repo structure docs to reflect new skills
