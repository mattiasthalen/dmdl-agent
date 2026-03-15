# daana-query Skill Design

**Date:** 2026-03-15
**Status:** Draft

## Overview

`/daana-query` is a data agent skill that answers natural language questions about data stored in a Focal-based Daana data warehouse. It connects to a PostgreSQL container, introspects the database to discover entities, attributes, and relationships, then enters a free-form conversational loop where users ask questions and receive live query results with natural language interpretation.

## Skill Identity

- **Name:** `daana-query`
- **Invocation:** `/daana-query`
- **Location:** `skills/daana-query/SKILL.md`
- **Persona:** A data analyst fluent in the Focal framework — thinks in entities, attributes, and relationships, translates natural language into SQL, and explains results in business terms.
- **Orchestrator integration:** Not part of this iteration. `/daana-query` is invoked directly. Routing from `/daana` can be added later as a separate change.

## Database Connection

### Connection Setup

On startup (before discovery), the skill asks the user for connection details:

1. **Container name:** "What's the name of your Postgres container?" (e.g., `daana-test-customerdb`)
2. **Database user:** "Database user?" (e.g., `dev`)
3. **Database name:** "Database name?" (e.g., `customerdb`)

The skill then connects via `docker exec`:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off -c "<SQL>"
```

### Connection Flags

- No `-it` flags — Claude Code's Bash tool has no interactive TTY
- `-P pager=off` — prevents pager activation on large results
- For machine-parseable output (agent interpretation): add `--csv` flag
- For display output (showing to user): default `psql` tabular format

The skill runs each query twice when presenting results: once with `--csv` for the agent to parse and summarize, once in default format for the user to read. Both invocations must include the `SET statement_timeout = '30s';` prefix since each `docker exec` is a separate `psql` session. For discovery queries (internal only), use `--csv` exclusively.

### Connection Validation

After collecting details, the skill runs a simple validation query (`SELECT 1`) to confirm connectivity before proceeding to discovery. If it fails, report the error and ask the user to verify the details.

## Discovery Phase

On startup, the skill automatically introspects the database by running a sequence of metadata queries. This builds the agent's understanding of the data model before the user asks anything.

### Discovery Queries

All discovery queries use `--csv` format for easy parsing.

1. **List all schemas:** Identify available schemas. In a Focal warehouse, `daana_dw` is the standard target schema — the remaining discovery queries assume it exists. If it does not, report this to the user and ask for guidance.
   ```sql
   SELECT schema_name FROM information_schema.schemata
   WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
   ORDER BY schema_name;
   ```

2. **List all views and tables in `daana_dw`:**
   ```sql
   SELECT table_name, table_type
   FROM information_schema.tables
   WHERE table_schema = 'daana_dw'
   ORDER BY table_type, table_name;
   ```

3. **Get column details for all views:**
   ```sql
   SELECT table_name, column_name, data_type
   FROM information_schema.columns
   WHERE table_schema = 'daana_dw'
   ORDER BY table_name, ordinal_position;
   ```

4. **Sample TYPE_KEYs from DESC tables:** For each `{ENTITY}_DESC` table discovered in step 2:
   ```sql
   SELECT DISTINCT type_key FROM daana_dw.{entity}_desc ORDER BY type_key;
   ```

### Post-Discovery Greeting

After discovery completes, greet the user with a summary:

> "Connected to customerdb. I found 3 entities: CUSTOMER (8 attributes), ORDER (5 attributes), PRODUCT (4 attributes), with 2 relationships. What would you like to know?"

### Discovery Failure

If discovery fails (container not running, no `daana_dw` schema, connection error), report the error clearly and suggest troubleshooting steps (e.g., "Is the daana-test-customerdb container running? Try `docker ps` to check.").

## Query Generation & Execution

### Flow

1. **Interpret the question:** Map natural language to discovered entities, attributes, and relationships
2. **Generate SQL:** Build a SELECT query against the appropriate views/tables
3. **Mode check:**
   - *Confirm mode* (default): Show the SQL and ask "Run this?"
   - *Auto-execute mode*: Run immediately
4. **Execute:** Run via `docker exec <container> psql -U <user> -d <database> -P pager=off -c "..."`
5. **Present results:** Show raw table output AND natural language summary/interpretation

### Query Target Selection

| Question Type | Target |
|---|---|
| Current state ("show me all customers") | `VIEW_{ENTITY}` |
| Historical ("how has X changed over time") | `VIEW_{ENTITY}_HIST` |
| Relationship-based ("which customers placed orders") | `VIEW_{ENTITY}_WITH_REL` |
| Lineage / audit ("where did this data come from") | Raw `_DESC` tables + `INST_KEY` joins |
| Metadata exploration ("what attributes exist") | `_DESC` tables + TYPE_KEY introspection |

### Safety Guardrails

- **Read-only only:** Only `SELECT` statements permitted. The skill refuses to generate or execute INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or any other DDL/DML.
- **Validation:** Before execution, verify the generated SQL is a SELECT statement (or a WITH/CTE followed by SELECT).
- **Result limits:** Append `LIMIT 100` by default. Hard upper limit of `LIMIT 1000`. User can request up to the hard limit explicitly. For larger datasets, suggest aggregations, filtering, or export approaches.
- **Query timeout:** Prefix all queries with `SET statement_timeout = '30s';` to prevent long-running queries from blocking. If a query times out, inform the user and suggest simplifying (e.g., adding filters, reducing joins).
- **Empty results:** When a valid query returns zero rows, explain what was searched and suggest broadening criteria.
- **SQL generation safety:** The agent always generates SQL itself — user natural language is never interpolated directly into SQL strings. All identifiers use the discovered schema/table/column names.

## Mode Switching

The skill supports two execution modes:

- **Confirm mode** (default): Shows generated SQL and asks "Run this?" before executing.
- **Auto-execute mode:** Generates and runs SQL immediately, showing results.

Users switch modes conversationally:
- "Just run it" / "auto mode" → switches to auto-execute
- "Show me first" / "confirm mode" → switches back to confirm

## Conversation Loop

After discovery, the skill enters an open-ended free-form conversation. There are no phases or structured interview — the user asks questions and gets answers.

### The Agent Should

- Reference discovered metadata to use correct column names and types
- Prefer views over raw tables unless the question requires Focal internals
- Handle ambiguity by asking clarification ("Did you mean CUSTOMER_NAME or CUSTOMER_SEGMENT?")
- When a query errors, read the Postgres error message, fix the SQL, and retry once before asking the user for help
- Suggest follow-up questions based on results
- Explain what an entity/attribute means based on metadata when asked
- Compare values across time using historical views
- Trace data lineage via INST_KEY when asked

### The Agent Should NOT

- Modify any data
- Offer to create/edit DMDL model or mapping files (that's `/daana-model` and `/daana-mapping`)
- Make assumptions about business logic not present in the metadata

### Session End

The session ends when the user is done asking questions. No explicit wrap-up phase.

## Result Presentation

Every query result includes both:

1. **Raw table output:** The `psql` output as-is — tabular format
2. **Natural language summary:** Interpretation of the results in business terms (e.g., "There are 47 customers. The top 3 by order count are...")

## File Structure

```
skills/
  daana-query/
    SKILL.md          — Complete skill definition
```

No new reference files needed. The skill derives all knowledge from the live database, not from static reference docs.

### SKILL.md Structure

- YAML frontmatter (`name`, `description`, `disable-model-invocation: true`)
- Persona section
- Discovery phase (startup queries + greeting)
- Query generation rules (target selection logic, safety guardrails, result limits)
- Execution mechanics (`docker exec` pattern)
- Presentation rules (raw output + natural language summary)
- Mode switching (confirm vs auto-execute)
- Conversation loop behavior

## Focal Framework Context

The skill has full access to the Focal data architecture:

- **Views** (`VIEW_*`): User-friendly current state, historical, and relationship views
- **Metadata**: TYPE_KEYs, semantic definitions, attribute descriptions
- **Raw Focal tables**: `_FOCAL`, `_DESC`, `_IDFR`, `_X` tables for advanced queries (lineage, temporal deep-dives)

The agent understands the Focal table taxonomy:

| Table Type | Pattern | Purpose |
|---|---|---|
| FOCAL | `{ENTITY}_FOCAL` | One row per entity instance (surrogate key) |
| IDFR | `{ENTITY}_IDFR` | Business identifier to surrogate key mapping |
| DESC | `{ENTITY}_DESC` | Descriptive attributes in key-value format via TYPE_KEY |
| Relationship | `{ENTITY1}_{ENTITY2}_X` | Temporal many-to-many relationships |
| Current view | `VIEW_{ENTITY}` | Current state snapshot |
| Historical view | `VIEW_{ENTITY}_HIST` | Full change history |
| Related view | `VIEW_{ENTITY}_WITH_REL` | Current state with pre-joined relationships |

The agent understands the three timestamp types:
- **EFF_TMSTP** (Effective): Business time — when this version became valid
- **VER_TMSTP** (Version): System time — when the warehouse recorded this version
- **POPLN_TMSTP** (Population): Load time — when the row was physically inserted

**Schema qualification:** Always use fully-qualified names (e.g., `daana_dw.view_customer`) to avoid ambiguity when multiple schemas contain similarly-named objects.

## Future Work

- **Orchestrator routing:** Add `/daana-query` as a routing target in `/daana` orchestrator, with criteria like "if the user asks a data question rather than wanting to build model/mapping files."
- **Connection persistence:** Remember connection details across sessions (via memory system) so the user doesn't re-enter them each time.
- **Export capabilities:** Support exporting query results to CSV files for larger datasets.
