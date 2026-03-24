# Focal Agent & USS Skill — Design Spec

## Context

The query skill currently bundles connection handling, Focal bootstrap, framework knowledge, dialect specifics, and ad-hoc query patterns into one skill with seven reference files. As we add new skills that need database interaction (USS generation, traditional star schema generation), this knowledge needs to be reusable without duplication.

Francesco Puppini's Unified Star Schema (USS) is a modeling technique that eliminates fan traps and chasm traps by creating a single bridge table connecting all peripherals (complete entity views) through resolved M:1 relationship chains.

## Scope

Four changes delivered as one cohesive design:

1. **Focal agent** — new reusable agent for connection, bootstrap, and SQL execution
2. **Query skill refactor** — slim down to ad-hoc query patterns, dispatch focal agent
3. **USS skill** — new skill for generating USS SQL files
4. **Star skill** — new skill skeleton for traditional star schema generation (future)

## Plugin Structure

```
plugin/
  .claude-plugin/
    plugin.json
  agents/
    focal/                           # NEW — reusable Focal expert agent
      AGENT.md
      references/
        focal-framework.md           # Moved from query
        bootstrap.md                 # Moved from query
        connections.md               # Moved from query
        dialect-postgres.md          # Moved from query
  skills/
    model/                           # Unchanged
      SKILL.md
      references/
    map/                             # Unchanged
      SKILL.md
      references/
    query/                           # REFACTORED
      SKILL.md                       # Dispatches focal agent, then ad-hoc query loop
      references/
        ad-hoc-query-agent.md        # Kept
    uss/                             # NEW
      SKILL.md                       # Dispatches focal agent, then USS interview + generate
      references/
        uss-patterns.md              # Bridge, peripheral, synthetic SQL templates
        uss-examples.md              # Worked example: bootstrap to generated SQL
    star/                            # NEW (skeleton)
      SKILL.md                       # Dispatches focal agent, then star schema interview
      references/
        dimension-patterns.md        # Moved from query
        fact-patterns.md             # Moved from query
```

## 1. Focal Agent

### Purpose

Reusable agent dispatched by query, USS, and star skills. Handles all database interaction with the Focal data warehouse.

### Responsibilities

- Discover `connections.yaml` in the project
- Validate connectivity via platform-specific check commands
- Run `f_focal_read()` bootstrap query to discover entities, attributes, and relationships
- Execute SQL queries against the Focal database
- Return structured metadata and query results to the calling skill

### Agent Definition

`agents/focal/AGENT.md` with frontmatter:

```yaml
---
name: focal
description: |
  Focal data warehouse expert agent. Handles connection discovery,
  metadata bootstrap via f_focal_read(), and SQL execution against
  Focal databases. Dispatched by query, USS, and star skills.
model: inherit
---
```

### References (moved from query)

- `focal-framework.md` — Focal architecture (two-layer model, four table types, metadata navigation chain)
- `bootstrap.md` — `f_focal_read()` query, result interpretation, TYPE_KEY resolution
- `connections.md` — Connection profile schema (PostgreSQL, BigQuery, MSSQL, Oracle, Snowflake)
- `dialect-postgres.md` — PostgreSQL-specific syntax (RANK alternative to QUALIFY, window frames, statement timeout)

## 2. Query Skill Refactor

### Changes

- Remove Phase 1 (Connection) and Phase 2 (Bootstrap) — replaced with: "Dispatch the focal agent if metadata is not in context"
- Remove references: `focal-framework.md`, `bootstrap.md`, `connections.md`, `dialect-postgres.md`
- Move `dimension-patterns.md` and `fact-patterns.md` to `star/references/`
- Keep: `ad-hoc-query-agent.md` (Pattern 1/2/3 query generation)
- SKILL.md updated to dispatch focal agent, then enter the ad-hoc query loop (Phase 3+4 from current skill)

### Retained References

- `ad-hoc-query-agent.md` — Pattern 1 (Latest/Snapshot), Pattern 2 (Single Entity History), Pattern 3 (Multi-Entity History), cutoff date modifier, multi-query detection

## 3. USS Skill

### Overview

`/daana-uss` generates a Unified Star Schema as a folder of SQL files (DDL). The USS eliminates fan traps and chasm traps by creating a single bridge table that all peripherals join to.

### Phases

**Phase 1: Bootstrap**
- Dispatch the focal agent to connect and run `f_focal_read()`
- Receive full entity/attribute/relationship metadata

**Phase 2: Interview**

Ask the user one question at a time:

1. **Entity selection** — present discovered entities, confirm which participate in the USS. Auto-classify from bootstrap: entities with date/numeric attributes as bridge candidates, entities referenced via M:1 chains as peripheral candidates.
2. **Temporal mode** — event-grain unpivot (recommended default) vs columnar dates. Event-grain unpivots all timestamps into `event` + `event_occurred_on`, enabling canonical date/time peripherals.
3. **Historical mode** — snapshot (latest values via RANK) vs historical (includes `valid_from` / `valid_to` columns). Conditional: historical mode adds temporal columns to bridge and peripherals.
4. **Materialization** — all views, all tables, bridge as table + peripherals as views, or custom mix. Skill asks user preference.
5. **Output folder** — where to write the SQL files.

**Phase 3: Generate**

Produce SQL files in a flat folder:

- `_bridge.sql` — unified bridge
- `_dates.sql` — synthetic date peripheral
- `_times.sql` — synthetic time peripheral
- `{entity}.sql` — one per peripheral entity

**Phase 4: Handover**
- Offer to execute the DDL via the focal agent
- Suggest `/daana-query` for ad-hoc querying against the generated schema

### Bridge (`_bridge.sql`)

The bridge UNION ALLs rows from all fact-bearing entities. Only M:1 relationship chains are resolved (no fan-out).

**Columns:**

| Column | Description |
|--------|-------------|
| `peripheral` | Source entity name |
| `event` | Event name (unpivoted from timestamp attributes) |
| `event_occurred_on` | Full timestamp value |
| `_key__dates` | Date part of `event_occurred_on` (FK to `_dates`) |
| `_key__times` | Time part of `event_occurred_on` (FK to `_times`) |
| `_key__{entity}` | Surrogate key per peripheral (e.g., `_key__customer`) |
| `_measure__{entity}__{attribute}` | Measure value (e.g., `_measure__order_line__unit_price`) |
| `valid_from` | (Historical mode only) Effective start |
| `valid_to` | (Historical mode only) Effective end |

**SQL pattern (event-grain, snapshot mode):**

For each entity with facts:
1. CTE per descriptor table: RANK to get latest values, pivot TYPE_KEY to named columns
2. CTE per relationship: RANK to resolve FK keys (M:1 only)
3. UNPIVOT timestamp columns into `event` + `event_occurred_on` rows
4. Derive `_key__dates` as `event_occurred_on::date`, `_key__times` as `event_occurred_on::time`
5. UNION ALL all entity CTEs, with NULL for non-shared measures

### Peripherals (`{entity}.sql`)

Each peripheral is a complete entity view with ALL attributes (strings, numbers, timestamps — everything), not just traditional dimension attributes.

**SQL pattern:**
1. CTE per descriptor table: RANK for latest values, pivot TYPE_KEY to named columns
2. Final SELECT joining all CTEs on the entity's FOCAL key

### Synthetic Date Peripheral (`_dates.sql`)

Date spine generated from bridge min/max year.

```sql
WITH date_spine AS (
  SELECT generate_series(
    make_date(
      (SELECT MIN(EXTRACT(YEAR FROM event_occurred_on))::int FROM _bridge),
      1, 1),
    make_date(
      (SELECT MAX(EXTRACT(YEAR FROM event_occurred_on))::int FROM _bridge),
      12, 31),
    '1 day'::interval
  )::date AS date_key
)
SELECT
  date_key,
  EXTRACT(YEAR FROM date_key)::int AS year,
  EXTRACT(QUARTER FROM date_key)::int AS quarter,
  EXTRACT(MONTH FROM date_key)::int AS month,
  TO_CHAR(date_key, 'Month') AS month_name,
  EXTRACT(DAY FROM date_key)::int AS day_of_month,
  EXTRACT(DOW FROM date_key)::int AS day_of_week,
  TO_CHAR(date_key, 'Day') AS day_name
FROM date_spine
```

### Synthetic Time Peripheral (`_times.sql`)

Time-of-day at second grain (86,400 rows).

```sql
WITH time_spine AS (
  SELECT (n || ' seconds')::interval AS t
  FROM generate_series(0, 86399) AS n
)
SELECT
  t::time AS time_key,
  EXTRACT(HOUR FROM t)::int AS hour,
  EXTRACT(MINUTE FROM t)::int AS minute,
  EXTRACT(SECOND FROM t)::int AS second
FROM time_spine
```

### Key Conventions

- **Double underscore** separates namespace levels: `_key__entity`, `_measure__entity__attribute`
- **Single underscore prefix** for structural/FK columns: `_key__`, `_measure__`
- **No prefix** for business columns: `peripheral`, `event`, `event_occurred_on`
- **Peripheral file names**: lowercased entity name (e.g., `customer.sql`)
- **Synthetic files**: prefixed with underscore (`_bridge.sql`, `_dates.sql`, `_times.sql`)
- **Entity peripheral keys**: named `_key__{entity}` in the bridge, primary key in the peripheral matches

### Fan-Out Prevention

Only M:1 relationship chains are followed from bridge to peripheral. The skill detects cardinality from bootstrap metadata:
- M:1: entity is on FOCAL01_KEY side (many), related entity on FOCAL02_KEY side (one)
- M:M or 1:M chains are excluded or flagged to the user during the interview

## 4. Star Skill (Skeleton)

### Purpose

`/daana-star` generates traditional star schema SQL files (fact tables + dimension tables). Absorbs the dimension and fact pattern references from the query skill.

### Skeleton only

This design covers the folder structure and reference placement. Full star skill design is deferred to a future spec:

```
skills/star/
  SKILL.md        # Placeholder: dispatches focal agent, star schema interview
  references/
    dimension-patterns.md   # Moved from query
    fact-patterns.md        # Moved from query
```

## Dialect Support

PostgreSQL only (matching current query skill). Other dialects deferred to future work.

## Version Bump

Bump `plugin.json` version after all changes are complete.
