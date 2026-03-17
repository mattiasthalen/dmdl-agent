# Query Skill Improvements — Design

**Date:** 2026-03-17
**Status:** Approved

## Problem

The query skill has three issues:

1. **No connections.yaml awareness** — it asks for container/user/database manually every time, ignoring the `connections.yaml` file that already exists in the Daana ecosystem.
2. **Dual query execution** — every user query runs twice (CSV + tabular), which is wasteful. A single CSV run can be parsed and formatted by the agent.
3. **No upfront execution consent** — the skill defaults to confirm mode with conversational switching ("just run it" / "show me first"). Users get prompted repeatedly with no way to opt out cleanly.

## Design

### Approach

Rewrite the skill with clearer phase separation and extract Focal reference content into a shared reference file. Postgres-only for now.

### Phase 1: Connection

1. **Look for `connections.yaml`** in the working directory.
2. **If found:** parse and list all profiles with their type (e.g., `dev (postgresql)`, `bigquery-prod (bigquery)`). Ask the user which one to use.
   - If the user picks a non-Postgres profile: inform them only PostgreSQL is supported and ask them to pick another or connect manually.
3. **If not found:** fall back to current manual flow — ask container name, database user, database name one at a time.
4. **Validate connectivity** with `SELECT 1` via `docker exec psql`.

### Phase 2: Discovery

1. **Ask for consent:** "Connected! Want me to discover the schema? I'll query metadata for schemas, tables, columns, and type keys." (yes / no)
2. **If yes:** run all four discovery queries as a batch (schemas, tables, columns, type keys). Present a greeting summary with entity count, attribute counts, and relationship count.
3. **If no:** skip discovery, go straight to the query loop. The agent works without metadata but may need to ask more clarifying questions about table/column names.

### Phase 3: Query Loop

1. **Generate SQL** from the user's natural language question.
2. **Execution consent** — show the SQL and prompt with Claude's question format:
   - **yes** — run this query, ask again next time
   - **yes, don't ask again** — auto-execute for the rest of the session
   - **no** — don't run, ask what to adjust
3. **Single execution** — run once as CSV via `docker exec psql --csv`. The agent parses the CSV for its summary and formats a readable table in the response.
4. **Result presentation:**
   - Formatted table (agent-rendered from CSV)
   - Natural language summary
   - Suggested follow-up questions

### Phase 4: Handover

Same as today — detect unmapped entities and suggest `/daana-map`.

### File Changes

| File | Action |
|---|---|
| `skills/query/SKILL.md` | Rewrite — four phases: Connection, Discovery, Query Loop, Handover |
| `references/focal-framework.md` | New — extracted Focal table taxonomy and timestamp types |
| `references/connections-schema.md` | New — connections.yaml field reference for PostgreSQL profiles |

### What's NOT changing

- Read-only safety guardrails (SELECT only, LIMIT 100 default, statement_timeout)
- Adaptive behavior (technical vs non-technical users)
- SQL generation safety (no user string interpolation)
- Discovery queries themselves (schemas, tables, columns, type keys)
- Handover to `/daana-map` for unmapped entities

### Future considerations (not in scope)

- Multi-engine support (BigQuery, MSSQL, Oracle, Snowflake) — connections.yaml already supports these, but query execution is Postgres-only for now.
- Direct host connections (non-Docker) — currently all queries go through `docker exec`.
