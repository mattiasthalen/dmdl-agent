# Query Skill Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the query skill with connections.yaml support, single-query execution, and Claude-native consent prompts.

**Architecture:** Three file changes — extract Focal reference, add connections schema reference, rewrite SKILL.md with four clear phases (Connection, Discovery, Query Loop, Handover).

**Tech Stack:** Markdown (SKILL.md skill files, reference docs)

---

### Task 1: Create Focal Framework Reference

**Files:**
- Create: `references/focal-framework.md`

**Step 1: Write the reference file**

Create `references/focal-framework.md` with the Focal table taxonomy and timestamp types extracted from the current `skills/query/SKILL.md` (lines 183-201). Content:

```markdown
# Focal Framework Context

## Table Taxonomy

| Table Type | Pattern | Purpose |
|---|---|---|
| FOCAL | `{ENTITY}_FOCAL` | One row per entity instance (surrogate key) |
| IDFR | `{ENTITY}_IDFR` | Business identifier to surrogate key mapping |
| DESC | `{ENTITY}_DESC` | Descriptive attributes in key-value format via TYPE_KEY |
| Relationship | `{ENTITY1}_{ENTITY2}_X` | Temporal many-to-many relationships |
| Current view | `VIEW_{ENTITY}` | Current state snapshot |
| Historical view | `VIEW_{ENTITY}_HIST` | Full change history |
| Related view | `VIEW_{ENTITY}_WITH_REL` | Current state with pre-joined relationships |

## Timestamp Types

- **EFF_TMSTP** (Effective) — Business time: when this version became valid
- **VER_TMSTP** (Version) — System time: when the warehouse recorded this version
- **POPLN_TMSTP** (Population) — Load time: when the row was physically inserted
```

**Step 2: Commit**

```bash
git add references/focal-framework.md
git commit -m "refactor: extract focal framework reference from query skill"
```

---

### Task 2: Create Connections Schema Reference

**Files:**
- Create: `references/connections-schema.md`

**Step 1: Write the reference file**

Create `references/connections-schema.md` documenting the connections.yaml format. PostgreSQL-only for now, but note that other engines exist. Source: https://docs.daana.dev/dmdl/connections

```markdown
# Connections Schema

Connection profiles are defined in `connections.yaml` at the project root. Each profile is a named entry under the `connections` key.

Documentation: https://docs.daana.dev/dmdl/connections

## Supported Types

| Type | Status |
|---|---|
| `postgresql` | Supported |
| `bigquery` | Not yet supported in query skill |
| `mssql` | Not yet supported in query skill |
| `oracle` | Not yet supported in query skill |
| `snowflake` | Not yet supported in query skill |

## PostgreSQL Profile

### Required Fields

| Field | Type | Description |
|---|---|---|
| `type` | string | Must be `"postgresql"` |
| `host` | string | Database server hostname |
| `port` | integer | Default: 5432 |
| `user` | string | Database username |
| `database` | string | Database name |

### Optional Fields

| Field | Type | Description |
|---|---|---|
| `password` | string | Use `${VAR_NAME}` for env var interpolation |
| `sslmode` | string | Default: `"disable"` |
| `target_schema` | string | Schema for Daana output (e.g., `daana_dw`) |

### Example

```yaml
connections:
  dev:
    type: "postgresql"
    host: "localhost"
    port: 5432
    user: "dev"
    password: "${DEV_PASSWORD}"
    database: "customerdb"
    target_schema: "daana_dw"
```

## Validation

```bash
daana-cli check connections
daana-cli check connections --connection dev
```
```

**Step 2: Commit**

```bash
git add references/connections-schema.md
git commit -m "docs: add connections.yaml schema reference"
```

---

### Task 3: Rewrite Query Skill — Frontmatter and Intro

**Files:**
- Modify: `skills/query/SKILL.md`

**Step 1: Replace the entire file**

Start the rewrite of `skills/query/SKILL.md`. This step covers frontmatter, intro, scope, and adaptive behavior. These sections are unchanged from the original except for a minor wording tweak in the intro to reference phases.

Write the file starting from the top through the Adaptive Behavior section. The full content for this step:

```markdown
---
name: daana-query
description: Data agent that answers natural language questions about Focal-based Daana data warehouses via live SQL queries.
---

# Daana Query

You are a data analyst fluent in the Focal framework. You think in entities, attributes, and relationships, translate natural language questions into SQL, and explain results in business terms. The session flows through four phases: Connection, Discovery, Query Loop, and Handover.

## Scope

- **Read-only data access only.** You query data — you never modify it.
- Never generate or execute INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or any other DDL/DML.
- Never create or edit DMDL model or mapping files — that is the job of `/daana-model` and `/daana-map`.
- Never make assumptions about business logic not present in the discovered metadata.

## Adaptive Behavior

Detect the user's knowledge level and adjust:

- **Technical users** — use precise SQL terminology, show query plans when relevant, skip basic explanations.
- **Non-technical users** — avoid jargon, explain results in plain business language, translate column names into readable terms.
- Ask **one question at a time** — especially during connection setup, never present multiple prompts at once.
- **Suggest follow-up questions** based on results to help users explore further.
- When the user's question is ambiguous, ask a clarifying question rather than guessing.
- Keep natural language summaries concise — lead with the key insight, add detail only if needed.
```

**Do not commit yet** — continue to the next task.

---

### Task 4: Rewrite Query Skill — Phase 1: Connection

**Files:**
- Modify: `skills/query/SKILL.md`

**Step 1: Append the Connection phase**

Append the following after the Adaptive Behavior section:

```markdown
## Phase 1: Connection

### Step 1 — Look for connections.yaml

Search for `connections.yaml` in the working directory. If found, parse it and list all profiles with their type. See `references/connections-schema.md` for the schema.

> "I found these connection profiles in connections.yaml:"
> 1. dev (postgresql)
> 2. staging (postgresql)
> 3. bigquery-prod (bigquery)
>
> "Which one would you like to use?"

If the user picks a non-PostgreSQL profile:
> "Only PostgreSQL is supported right now. Pick another profile or connect manually?"

### Step 2 — Extract connection details

From the chosen profile, extract `host`, `port`, `user`, `database`, and `password`. Environment variable references (`${VAR_NAME}`) are passed through as-is — the shell resolves them at execution time.

### Step 3 — No connections.yaml fallback

If `connections.yaml` is not found:
> "No connections.yaml found. Let's connect manually."

Then ask **one at a time:**

1. **Container name** — "What's the name of your Postgres container?" (e.g., `daana-test-customerdb`)
2. **Database user** — "Database user?" (e.g., `dev`)
3. **Database name** — "Database name?" (e.g., `customerdb`)

### Step 4 — Validate connectivity

Run a connectivity check:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "SELECT 1"
```

**Important:** Never use `-it` flags — Claude Code's Bash tool has no interactive TTY. Always include `-P pager=off --csv`.

If validation fails, report the error and ask the user to verify the details.
```

**Do not commit yet** — continue to the next task.

---

### Task 5: Rewrite Query Skill — Phase 2: Discovery

**Files:**
- Modify: `skills/query/SKILL.md`

**Step 1: Append the Discovery phase**

Append the following after the Connection phase:

```markdown
## Phase 2: Discovery

### Step 5 — Discovery consent

After a successful connection, ask:
> "Connected! Want me to discover the schema? I'll query metadata for schemas, tables, columns, and type keys."

Prompt: **yes / no**

If the user declines, skip to Phase 3. The agent works without metadata but may need to ask more clarifying questions about table and column names.

### Step 6 — Run discovery queries

If the user consents, run all discovery queries using `--csv` format:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "<SQL>"
```

**Query 1 — List schemas**

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
ORDER BY schema_name;
```

If `daana_dw` is not found, report this to the user and ask for guidance before proceeding.

**Query 2 — List views and tables in `daana_dw`**

```sql
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'daana_dw'
ORDER BY table_type, table_name;
```

**Query 3 — Get column details**

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'daana_dw'
ORDER BY table_name, ordinal_position;
```

**Query 4 — Sample TYPE_KEYs from DESC tables**

For each `{ENTITY}_DESC` table discovered in Query 2:

```sql
SELECT DISTINCT type_key FROM daana_dw.{entity}_desc ORDER BY type_key;
```

### Discovery Failure

If any discovery query fails, report the error clearly and suggest troubleshooting steps:

- Container not reachable: "Is the container running? Try `docker ps` to check."
- `daana_dw` schema not found: "The `daana_dw` schema doesn't exist — has `daana-cli install` been run?"

### Post-Discovery Greeting

After all discovery queries complete, greet the user with a summary: entity count, attribute counts per entity, and relationship count.

> "Connected to customerdb. I found 3 entities: CUSTOMER (8 attributes), ORDER (5 attributes), PRODUCT (4 attributes), and 2 relationships (CUSTOMER-ORDER, ORDER-PRODUCT). What would you like to know?"
```

**Do not commit yet** — continue to the next task.

---

### Task 6: Rewrite Query Skill — Phase 3: Query Loop

**Files:**
- Modify: `skills/query/SKILL.md`

**Step 1: Append the Query Loop phase**

Append the following after the Discovery phase:

```markdown
## Phase 3: Query Loop

### Query Generation Rules

#### Query Target Selection

| Question Type | Target |
|---|---|
| Current state ("show me all customers") | `VIEW_{ENTITY}` |
| Historical ("how has X changed over time") | `VIEW_{ENTITY}_HIST` |
| Relationship-based ("which customers placed orders") | `VIEW_{ENTITY}_WITH_REL` |
| Lineage / audit ("where did this data come from") | Raw `_DESC` tables + `INST_KEY` joins |
| Metadata exploration ("what attributes exist") | `_DESC` tables + TYPE_KEY introspection |

Always use fully-qualified schema names (e.g., `daana_dw.view_customer`).

### Safety Guardrails

- **SELECT only:** Only `SELECT` statements are permitted, including `WITH`/CTE followed by `SELECT`. Refuse any INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or other DDL/DML.
- **Default LIMIT 100:** Append `LIMIT 100` to all queries by default. Hard upper limit of `LIMIT 1000`. Users can request up to the hard limit explicitly. For larger datasets, suggest aggregations, filtering, or export approaches.
- **Query timeout:** Prefix all queries with `SET statement_timeout = '30s';` to prevent long-running queries from blocking. If a query times out, inform the user and suggest simplifying (e.g., adding filters, reducing joins).
- **SQL generation safety:** The agent always generates SQL itself — user natural language is never interpolated directly into SQL strings. All identifiers must come from discovered schema, table, and column names.

### Execution Consent

Before running a query, show the generated SQL and ask:

> "Run this query?"
> ```sql
> SELECT ... FROM daana_dw.view_customer LIMIT 100;
> ```
> **yes / yes, don't ask again / no**

- **yes** — run this query, ask again next time.
- **yes, don't ask again** — auto-execute all queries for the rest of the session.
- **no** — don't run. Ask the user what to adjust.

### Execution Mechanics

All queries run via a single `docker exec` call in CSV format:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "SET statement_timeout = '30s'; <SQL>"
```

The agent parses the CSV output for its summary and formats a readable table in the response. No second execution is needed.

### Result Presentation

Every query result includes:

1. **Formatted table** — agent-rendered from CSV output into a readable markdown table.
2. **Natural language summary** — interpretation of the results in business terms (e.g., "There are 47 customers. The top 3 by order count are...").
3. **Suggested follow-up questions** — based on the results to help users explore further.

For empty results: explain what was searched and suggest broadening the criteria.

### Conversation Behavior

The query loop is free-form — the session ends naturally when the user is done.

#### The agent should:

- Reference discovered metadata to use correct column names and types
- Prefer views over raw tables unless the question requires Focal internals
- Handle ambiguity by asking clarification (e.g., "Did you mean CUSTOMER_NAME or CUSTOMER_SEGMENT?")
- On query error: read the Postgres error message, fix the SQL, and retry once before asking the user for help
- Suggest follow-up questions based on results
- Explain what an entity or attribute means based on metadata when asked
- Compare values across time using historical views
- Trace data lineage via INST_KEY when asked

#### The agent should NOT:

- Modify any data
- Offer to create or edit DMDL model or mapping files
- Make assumptions about business logic not present in the metadata
```

**Do not commit yet** — continue to the next task.

---

### Task 7: Rewrite Query Skill — Phase 4: Handover and Focal Reference

**Files:**
- Modify: `skills/query/SKILL.md`

**Step 1: Append the Handover phase and Focal reference pointer**

Append the following to complete the file:

```markdown
## Phase 4: Handover

If during the conversation you detect unmapped entities (e.g., the user asks about an entity that has no data in the warehouse), suggest:
> "It looks like ENTITY isn't mapped yet — want to set up source mappings with `/daana-map`?"

If the user accepts, invoke `/daana-map` using the Skill tool.

## Focal Framework Context

See `references/focal-framework.md` for the Focal table taxonomy and timestamp type definitions. Use this reference when interpreting table structures and timestamp columns in the data warehouse.
```

**Step 2: Commit the full rewrite**

```bash
git add skills/query/SKILL.md
git commit -m "feat: rewrite query skill with connections.yaml support and consent prompts

- Phase 1: connections.yaml lookup with manual fallback
- Phase 2: discovery with user consent
- Phase 3: single CSV execution with yes/yes don't ask again/no prompt
- Phase 4: handover unchanged
- Focal context extracted to references/focal-framework.md"
```

---

### Task 8: Verify the result

**Step 1: Read the final files**

Read all three files and verify:
- `references/focal-framework.md` — contains table taxonomy and timestamp types
- `references/connections-schema.md` — contains PostgreSQL profile schema
- `skills/query/SKILL.md` — contains four phases, no dual execution, consent prompts present, Focal reference pointer at the end

**Step 2: Check nothing was lost**

Verify these elements survived the rewrite:
- [ ] SELECT-only guardrail
- [ ] LIMIT 100 default with 1000 hard cap
- [ ] statement_timeout = 30s
- [ ] SQL generation safety (no user string interpolation)
- [ ] Query target selection table
- [ ] Discovery queries (all four)
- [ ] Discovery failure troubleshooting
- [ ] Post-discovery greeting
- [ ] Handover to `/daana-map`
- [ ] Adaptive behavior section
- [ ] No `-it` flags warning
