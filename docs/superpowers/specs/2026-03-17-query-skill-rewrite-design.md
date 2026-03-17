# Query Skill Rewrite — Design

**Date:** 2026-03-17
**Status:** Approved

## Problem

The current query skill discovers the data model via `information_schema` and queries pre-built views (`VIEW_CUSTOMER`, etc.). This is fragile and installation-specific. Patrik Lager's teach_claude_focal repo demonstrates the correct approach: bootstrap from Focal metadata via `f_focal_read()` and query raw Focal tables with TYPE_KEY resolution.

## Design

### Approach

Full rewrite of `/daana-query`. The skill becomes dialect-agnostic with Postgres as the first supported dialect. It bootstraps from Focal metadata and queries raw tables — no views, no information_schema.

### Connection

- Read `connections.yaml` (explicit `cat connections.yaml` command)
- List all profiles, user picks one
- PostgreSQL only for now — reject non-Postgres profiles
- Validate with `SELECT 1`
- No `config.yaml` needed — everything from customerdb

### Bootstrap

Single query against `DAANA_METADATA.f_focal_read('9999-12-31')` in the customerdb:

```sql
SELECT
  focal_name, descriptor_concept_name, atomic_context_name,
  atom_contx_key, attribute_name, table_pattern_column_name
FROM daana_metadata.f_focal_read('9999-12-31')
WHERE focal_physical_schema = 'DAANA_DW'
ORDER BY focal_name, descriptor_concept_name, atomic_context_name
```

Returns: entities, descriptor tables, atomic contexts (TYPE_KEYs), attributes, and physical column mappings. Agent caches result in memory for the session.

Discovery consent required (HARD-GATE) before running.

### Query Patterns (dialect-agnostic)

Four patterns, all resolving TYPE_KEYs from bootstrap — never hardcoded:

1. **Single attribute (latest)** — one atomic context from DESC table, `ROW_ST = 'Y'`
2. **Multi-attribute pivot (latest)** — `MAX(CASE WHEN TYPE_KEY = ...)` pivot, `GROUP BY entity_key`
3. **Full history (single attribute)** — no `ROW_ST` filter, ordered by `EFF_TMSTP`, `VER_TMSTP`
4. **Temporal alignment (multi-attribute history)** — three-stage CTE with carry-forward

Relationship queries via X tables, resolved from bootstrap metadata.

### Execution

- HARD-GATE consent prompt (yes / yes, don't ask again / no)
- Single CSV execution, agent renders markdown table
- No default LIMIT — ask the user if they want to limit
- Natural language summary + suggested follow-ups

### Dialect modularity

SKILL.md is dialect-agnostic — describes workflow and query patterns abstractly. Dialect-specific reference files provide:
- Connection/execution commands (e.g., `docker exec psql` for Postgres)
- SQL syntax specifics (e.g., window functions, temporal functions)
- Type mappings

Start with `dialect-postgres.md`. New dialects added as additional reference files.

### File Changes

| File | Action |
|---|---|
| `plugin/skills/query/SKILL.md` | Rewrite — dialect-agnostic, metadata-driven |
| `plugin/references/focal-framework.md` | Replace — from Patrik's teach_claude_focal |
| `plugin/references/dialect-postgres.md` | New — Postgres-specific syntax and commands |
| `plugin/references/connections-schema.md` | Keep as-is |
| `external/teach_claude_focal` | New — git submodule |
| `external/daana-cli` | New — git submodule |

### What's removed

- All view-based query logic (`VIEW_CUSTOMER`, etc.)
- All `information_schema` discovery queries
- Default `LIMIT 100` behavior
- Dual query execution (already removed, but confirmed gone)
- Inlined Focal table taxonomy (replaced by full framework reference)

### What's kept

- Read-only safety guardrails (SELECT only, statement_timeout)
- SQL generation safety (no user string interpolation)
- Adaptive behavior (technical vs non-technical users)
- Handover to `/daana-map` for unmapped entities
- Consent prompts with HARD-GATE

### Version

Bump to 1.3.0 (new feature).
