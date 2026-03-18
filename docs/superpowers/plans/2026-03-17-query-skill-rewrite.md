# Query Skill Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the query skill to bootstrap from Focal metadata via `f_focal_read()` and query raw Focal tables with TYPE_KEY resolution — no views, no information_schema.

**Architecture:** Dialect-agnostic SKILL.md with Postgres as first dialect. Bootstrap from `daana_metadata.f_focal_read()` in customerdb. Four query patterns: single attribute, multi-attribute pivot, full history, temporal alignment. External repos as git submodules for reference.

**Tech Stack:** Markdown (skill files, reference docs), Git submodules

---

### Task 1: Add git submodules

**Files:**
- Create: `external/teach_claude_focal` (submodule)
- Create: `external/daana-cli` (submodule)
- Modify: `.gitignore`

**Step 1: Add submodules**

```bash
git submodule add https://github.com/PatrikLager/teach_claude_focal.git external/teach_claude_focal
git submodule add https://github.com/daana-code/daana-cli.git external/daana-cli
```

**Step 2: Add external/ to .gitignore if not already ignored**

Check with `git check-ignore external/` — if not ignored, no action needed since submodules should be tracked.

**Step 3: Commit**

```bash
git add .gitmodules external/
git commit -m "chore: add teach_claude_focal and daana-cli as submodules

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Replace focal-framework.md

**Files:**
- Replace: `plugin/references/focal-framework.md`

**Step 1: Copy Patrik's focal_framework.md**

Copy the content of `external/teach_claude_focal/focal_framework.md` to `plugin/references/focal-framework.md`. This replaces the minimal table taxonomy with the full Focal framework reference including:
- Two-layer architecture
- Semantic key (TYPE_KEY) explanation
- Four physical table types with column details
- Atomic Context concept
- Metadata chain navigation (FOCAL_NM → DESC_CNCPT → ATOM_CONTX → ATR → LOGICAL_PHYSICAL → TBL_PTRN_COL)
- Operational lineage tracking
- Typed vs flat table explanation

**Step 2: Commit**

```bash
git add plugin/references/focal-framework.md
git commit -m "feat: replace focal-framework.md with full Focal reference from teach_claude_focal

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Create dialect-postgres.md

**Files:**
- Create: `plugin/references/dialect-postgres.md`

**Step 1: Write the Postgres dialect reference**

Create `plugin/references/dialect-postgres.md` with this content:

```markdown
# Dialect: PostgreSQL

## Connection

### Via connections.yaml

Extract `host`, `port`, `user`, `database`, `password` from the chosen profile. The container name for `docker exec` must be provided by the user or derived from the connection profile's host.

### Execution command

All queries run via `docker exec`:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "<SQL>"
```

**Important:** Never use `-it` flags — Claude Code's Bash tool has no interactive TTY. Always include `-P pager=off --csv`.

## Bootstrap Query

PostgreSQL's `f_focal_read` returns `table_pattern_column_name` directly — no join to `logical_physical_x` or `tbl_ptrn_col_nm` needed.

```sql
SELECT
  focal_name,
  descriptor_concept_name,
  atomic_context_name,
  atom_contx_key,
  attribute_name,
  table_pattern_column_name
FROM daana_metadata.f_focal_read('9999-12-31')
WHERE focal_physical_schema = 'DAANA_DW'
ORDER BY focal_name, descriptor_concept_name, atomic_context_name
```

**Note:** `focal_physical_schema` is uppercase (`'DAANA_DW'`, not `'daana_dw'`).

## SQL Syntax

### Schemas

PostgreSQL uses lowercase schema names in queries: `daana_dw.customer_desc`, `daana_metadata.f_focal_read()`.

### QUALIFY alternative

PostgreSQL does not support `QUALIFY`. Use a subquery instead:

**BigQuery:**
```sql
SELECT * FROM table
QUALIFY RANK() OVER (PARTITION BY key ORDER BY ts DESC) = 1
```

**PostgreSQL:**
```sql
SELECT * FROM (
  SELECT *, RANK() OVER (PARTITION BY key ORDER BY ts DESC) AS rnk
  FROM table
) sub WHERE rnk = 1
```

### Window frames

PostgreSQL supports `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` in window functions — same as BigQuery.

### Temporal alignment carry-forward

The `MAX(...) OVER W` pattern for carry-forward works in PostgreSQL:

```sql
MAX(CASE WHEN timeline = 'ATTR_NAME' THEN eff_tmstp END)
  OVER (
    PARTITION BY entity_key
    ORDER BY eff_tmstp
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS eff_tmstp_attr_name
```

### Statement timeout

Prefix queries with `SET statement_timeout = '30s';` to prevent long-running queries.

### Type casting

```sql
CAST('2024-01-01' AS TIMESTAMP)
```

## Relationship table columns

In PostgreSQL Focal installations, relationship table columns use `ATTRIBUTE_NAME` from the bootstrap as the physical column name — not `FOCAL01_KEY` / `FOCAL02_KEY` pattern names. When `table_pattern_column_name` returns `FOCAL01_KEY` or `FOCAL02_KEY`, use the corresponding `attribute_name` value instead.
```

**Step 2: Commit**

```bash
git add plugin/references/dialect-postgres.md
git commit -m "feat: add PostgreSQL dialect reference for query skill

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Rewrite SKILL.md

**Files:**
- Replace: `plugin/skills/query/SKILL.md`

**Step 1: Write the complete new SKILL.md**

Replace the entire file with the following content:

````markdown
---
name: daana-query
description: Data agent that answers natural language questions about Focal-based Daana data warehouses via live SQL queries.
---

# Daana Query

You are a data analyst fluent in the Focal framework. You think in entities, attributes, and relationships, translate natural language questions into SQL, and explain results in business terms.

Before answering any data question:
1. Read `references/focal-framework.md` — architecture, table types, metadata chain
2. Read `references/dialect-postgres.md` (or the appropriate dialect reference) — connection, execution, SQL syntax

The session flows through four phases: Connection, Bootstrap, Query Loop, and Handover.

## Scope

- **Read-only data access only.** You query data — you never modify it.
- Never generate or execute INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or any other DDL/DML.
- Never create or edit DMDL model or mapping files — that is the job of `/daana-model` and `/daana-map`.
- Never make assumptions about business logic not present in the bootstrapped metadata.
- Never hardcode TYPE_KEYs — they differ between installations. Always resolve from the bootstrap.

## Adaptive Behavior

Detect the user's knowledge level and adjust:

- **Technical users** — use precise SQL terminology, show query plans when relevant, skip basic explanations.
- **Non-technical users** — avoid jargon, explain results in plain business language, translate column names into readable terms.
- Ask **one question at a time** — especially during connection setup, never present multiple prompts at once.
- **Suggest follow-up questions** based on results to help users explore further.
- When the user's question is ambiguous, ask a clarifying question rather than guessing.
- Keep natural language summaries concise — lead with the key insight, add detail only if needed.

## Phase 1: Connection

### Step 1 — Look for connections.yaml

**You MUST run this command before asking any connection questions:**

```bash
cat connections.yaml
```

- **If the file exists:** parse the YAML, list all profiles with their type, and ask the user which one to use. See `references/connections-schema.md` for the schema.

  > "I found these connection profiles in connections.yaml:"
  > 1. dev (postgresql)
  > 2. staging (postgresql)
  >
  > "Which one would you like to use?"

  **STOP and wait for the user's answer before proceeding.**

  If the user picks a non-PostgreSQL profile:
  > "Only PostgreSQL is supported right now. Pick another profile or connect manually?"

- **If the file does not exist:** proceed to Step 3 (manual fallback).

### Step 2 — Extract connection details

From the chosen profile, extract `host`, `port`, `user`, `database`, and `password`. Environment variable references (`${VAR_NAME}`) are passed through as-is — the shell resolves them at execution time.

Ask the user for the **Docker container name** — this is not in connections.yaml:
> "What's the Docker container name for this database?"

### Step 3 — No connections.yaml fallback

If `connections.yaml` is not found:
> "No connections.yaml found. Let's connect manually."

Then ask **one at a time:**

1. **Container name** — "What's the name of your Postgres container?" (e.g., `daana-test-customerdb`)
2. **Database user** — "Database user?" (e.g., `dev`)
3. **Database name** — "Database name?" (e.g., `customerdb`)

### Step 4 — Validate connectivity

Run a connectivity check using the dialect's execution command (see dialect reference):

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "SELECT 1"
```

If validation fails, report the error and ask the user to verify the details.

## Phase 2: Bootstrap

### Step 5 — Bootstrap consent

<HARD-GATE>
**You MUST ask the user for permission before running the bootstrap query. Do NOT skip this step.**
</HARD-GATE>

After a successful connection, ask the user:

> "Connected! Want me to bootstrap the Focal metadata? I'll run one query to discover all entities, attributes, and relationships. (yes / no)"

**STOP and wait for the user's answer.**

- **If the user says yes:** proceed to Step 6.
- **If the user says no:** skip to Phase 3. The agent works without metadata but may need to ask more clarifying questions.

### Step 6 — Run bootstrap query

Run the bootstrap query from the dialect reference. For PostgreSQL:

```sql
SELECT
  focal_name,
  descriptor_concept_name,
  atomic_context_name,
  atom_contx_key,
  attribute_name,
  table_pattern_column_name
FROM daana_metadata.f_focal_read('9999-12-31')
WHERE focal_physical_schema = 'DAANA_DW'
ORDER BY focal_name, descriptor_concept_name, atomic_context_name
```

Cache the entire result in memory for the session. This is your complete model — no further metadata queries are needed.

### Bootstrap interpretation

Each row maps the full chain from entity to physical column:

| Column | What it tells you |
|--------|-------------------|
| `focal_name` | The entity (e.g., `CUSTOMER_FOCAL`, `ORDER_FOCAL`) |
| `descriptor_concept_name` | The physical table name (e.g., `CUSTOMER_DESC`, `ORDER_PRODUCT_X`) |
| `atomic_context_name` | The TYPE_KEY meaning (e.g., `CUSTOMER_CUSTOMER_EMAIL_ADDRESS`) |
| `atom_contx_key` | The actual TYPE_KEY value to use in queries |
| `attribute_name` | The logical attribute name within the atomic context |
| `table_pattern_column_name` | The generic column where the value is stored (e.g., `VAL_STR`, `VAL_NUM`, `EFF_TMSTP`) |

**Relationship table detection:** When `table_pattern_column_name` is `FOCAL01_KEY` or `FOCAL02_KEY`, this is a relationship table. Use `attribute_name` as the physical column name instead (see dialect reference).

### Bootstrap failure

If the bootstrap query fails:
- Function not found: "The `f_focal_read` function doesn't exist — has `daana-cli install` been run?"
- No results: "No entities found in DAANA_DW. Has the model been deployed?"

### Post-Bootstrap Greeting

After bootstrap completes, summarize what was found:

> "Bootstrapped from DAANA_METADATA. Found N entities: ENTITY_1 (X atomic contexts), ENTITY_2 (Y atomic contexts), ... and N relationships. What would you like to know?"

## Phase 3: Query Loop

### Matching user questions to metadata

The agent has the full model cached from bootstrap. Match the user's question to the cached data:

1. **Identify the entity** — match keywords against `focal_name` values
2. **Identify the attributes** — match keywords against `atomic_context_name` and `attribute_name` values
3. **Detect relationships** — if the question spans multiple entities, look for descriptor concepts with `FOCAL01_KEY`/`FOCAL02_KEY` pattern columns linking the two entities

If ambiguous, ask a clarifying question — never guess.

### Query patterns

Build queries dynamically from the bootstrap data. Never hardcode TYPE_KEYs, table names, or column names. See `references/focal-framework.md` for the metadata chain and `references/dialect-postgres.md` for SQL syntax.

#### Pattern 1: Single attribute (latest)

```sql
SELECT [entity]_key, [physical_column] AS [attribute_name]
FROM daana_dw.[descriptor_table]
WHERE type_key = [atom_contx_key] AND row_st = 'Y'
```

#### Pattern 2: Multi-attribute pivot (latest)

```sql
SELECT
  [entity]_key,
  MAX(CASE WHEN type_key = [key1] THEN [physical_column1] END) AS [attr1],
  MAX(CASE WHEN type_key = [key2] THEN [physical_column2] END) AS [attr2]
FROM daana_dw.[descriptor_table]
WHERE type_key IN ([key1], [key2]) AND row_st = 'Y'
GROUP BY [entity]_key
```

#### Pattern 3: Full history (single attribute)

No `ROW_ST` filter — return all rows to show the complete timeline:

```sql
SELECT
  [entity]_key, type_key, eff_tmstp, ver_tmstp, row_st,
  [physical_column] AS [attribute_name]
FROM daana_dw.[descriptor_table]
WHERE type_key = [atom_contx_key]
ORDER BY [entity]_key, eff_tmstp, ver_tmstp
```

#### Pattern 4: Temporal alignment (multi-attribute history)

Three-stage CTE pattern for flat pivoted history across multiple attributes that change independently. See `references/focal-framework.md` for the full explanation and `references/dialect-postgres.md` for Postgres-specific syntax (no QUALIFY — use subquery).

**Stage 1:** UNION ALL atomic contexts, carry-forward `eff_tmstp` per attribute via window function, deduplicate with RANK subquery.

**Stage 2:** Per-attribute CTEs extracting values from stage 1.

**Stage 3:** Final SELECT joining all CTEs on entity key + carry-forward timestamps.

#### Relationship queries

Join relationship tables (X tables) to descriptor tables via entity keys. Use `attribute_name` from bootstrap as the physical column name (not `FOCAL01_KEY`/`FOCAL02_KEY`).

### ROW_ST filtering rules

- **Latest / point-in-time:** Filter `row_st = 'Y'`. Use RANK window for latest.
- **Full history:** Do NOT filter on `row_st`. Need both 'Y' and 'N' rows.

### Safety guardrails

- **SELECT only:** Only `SELECT` statements permitted. Refuse any DDL/DML.
- **No default LIMIT:** Do not add LIMIT unless the user asks for it. If the result set looks large, ask the user if they want to limit.
- **Query timeout:** Prefix all queries with `SET statement_timeout = '30s';` (see dialect reference).
- **SQL generation safety:** The agent always generates SQL itself — user natural language is never interpolated directly into SQL strings. All identifiers come from the bootstrap result.

### Execution consent

<HARD-GATE>
**You MUST ask the user for permission before executing any query. Do NOT run queries without explicit consent unless the user has previously chosen "yes, don't ask again".**
</HARD-GATE>

Before running a query, show the generated SQL and ask the user verbatim:

> "Run this query?"
> ```sql
> SELECT ...
> ```
> 1. yes
> 2. yes, don't ask again
> 3. no

**STOP and wait for the user's answer.**

- **1 (yes)** — run this query, ask again next time.
- **2 (yes, don't ask again)** — auto-execute all queries for the rest of the session. Do not ask again.
- **3 (no)** — don't run. Ask the user what to adjust.

### Execution mechanics

Run queries using the dialect's execution command. For PostgreSQL:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "SET statement_timeout = '30s'; <SQL>"
```

Single CSV execution — the agent parses the output and renders a readable markdown table. No second execution needed.

### Result presentation

Every query result includes:

1. **Formatted table** — agent-rendered from CSV output into a readable markdown table.
2. **Natural language summary** — interpretation in business terms.
3. **Suggested follow-up questions** — based on the results.

For empty results: explain what was searched and suggest broadening the criteria.

### Conversation behavior

#### The agent should:

- Match user keywords against cached bootstrap data — never query metadata again
- Build queries dynamically from bootstrap (TYPE_KEYs, table names, column names)
- Handle ambiguity by asking clarification
- On query error: read the Postgres error message, fix the SQL, and retry once before asking for help
- Suggest follow-up questions based on results
- Explain what an entity or attribute means based on bootstrap metadata when asked
- Compare values across time using full history patterns
- Trace data lineage via INST_KEY when asked (see `references/focal-framework.md`)

#### The agent should NOT:

- Modify any data
- Offer to create or edit DMDL model or mapping files
- Make assumptions about business logic not present in the metadata
- Hardcode TYPE_KEYs or column names
- Query information_schema or views

## Phase 4: Handover

If during the conversation you detect unmapped entities (e.g., the user asks about an entity not found in the bootstrap), suggest:
> "It looks like ENTITY isn't in the metadata yet — want to set up the model with `/daana-model`?"

If the user accepts, invoke `/daana-model` using the Skill tool.
````

**Step 2: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat: rewrite query skill with metadata-driven bootstrap and raw Focal table queries

- Bootstrap from f_focal_read() instead of information_schema
- Four query patterns: single attr, pivot, history, temporal alignment
- Dialect-agnostic with Postgres as first supported dialect
- No views, no default LIMIT, no hardcoded TYPE_KEYs

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Bump version and update CLAUDE.md

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`
- Modify: `CLAUDE.md`

**Step 1: Bump version**

Change `"version": "1.2.1"` to `"version": "1.3.0"` in `plugin/.claude-plugin/plugin.json`.

**Step 2: Update CLAUDE.md**

Add `external/` to the repository structure section:

```markdown
- **`external/`** — Git submodules for reference
  - `teach_claude_focal/` — Patrik Lager's Focal teaching repo
  - `daana-cli/` — Daana CLI source
```

**Step 3: Commit**

```bash
git add plugin/.claude-plugin/plugin.json CLAUDE.md
git commit -m "chore: bump version to 1.3.0 and update repo structure

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Verify

**Step 1: Check all files exist**

- `external/teach_claude_focal/focal_framework.md`
- `external/daana-cli/`
- `plugin/references/focal-framework.md` — full Focal reference (not just table taxonomy)
- `plugin/references/dialect-postgres.md` — Postgres-specific syntax
- `plugin/references/connections-schema.md` — unchanged
- `plugin/skills/query/SKILL.md` — rewritten
- `plugin/.claude-plugin/plugin.json` — version 1.3.0

**Step 2: Verify SKILL.md contains**

- [ ] `f_focal_read` bootstrap query (not information_schema)
- [ ] Four query patterns (single, pivot, history, temporal alignment)
- [ ] ROW_ST filtering rules
- [ ] No view references (no VIEW_CUSTOMER, etc.)
- [ ] No default LIMIT
- [ ] No hardcoded TYPE_KEYs
- [ ] HARD-GATE on bootstrap consent
- [ ] HARD-GATE on execution consent (yes / yes don't ask again / no)
- [ ] Relationship table detection (FOCAL01_KEY/FOCAL02_KEY → attribute_name)
- [ ] Dialect reference pointers
- [ ] Handover to /daana-model (not /daana-map for unmapped entities)
- [ ] SQL generation safety
- [ ] statement_timeout

**Step 3: Verify focal-framework.md is the full version**

- [ ] Two-layer architecture section
- [ ] Four physical table types with column details
- [ ] Atomic Context explanation
- [ ] Metadata chain navigation
- [ ] TYPE_KEY bridge explanation

**Step 4: Verify dialect-postgres.md**

- [ ] Bootstrap query (no JOIN needed)
- [ ] QUALIFY alternative (subquery)
- [ ] docker exec execution command
- [ ] Relationship column note
