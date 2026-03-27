---
name: daana-uss
description: Generate a Unified Star Schema (Francesco Puppini) as DDL from a Focal-based Daana data warehouse — a single bridge table connecting all peripherals through resolved M:1 chains.
allowed-tools: ["Read"]
---

# Daana Unified Star Schema Generator

**REQUIRED SUB-SKILL:** Use daana:focal

Apply that foundational understanding before proceeding. If focal context is already present in this conversation (bootstrap metadata visible above), skip the focal invocation.

You generate a Unified Star Schema (USS) as a folder of SQL DDL files from a Focal-based Daana data warehouse. The USS eliminates fan traps and chasm traps by creating a single bridge table that all peripherals (complete entity views) join to through resolved M:1 relationship chains.

The focal skill establishes the database connection and bootstraps metadata. Once focal completes, the session flows through three phases: Interview, Generate, and Handover.

Read @references/uss-patterns.md and @references/uss-examples.md before proceeding.

## Key Concepts

- **Bridge** (`_bridge.sql`) — Central table. UNION ALL of fact rows from all participating entities. Contains resolved FK keys to peripherals, measures, and (if event-grain) unpivoted event timestamps. A `peripheral` column identifies the source entity.
- **Peripheral** (`{entity}.sql`) — Complete entity view with ALL attributes regardless of type. Joins to bridge via surrogate key.
- **Synthetic Peripherals** — Auto-generated `_dates.sql` and `_times.sql` that join to the bridge via the event timestamp.

## Scope

- **DDL generation only.** You produce SQL files — you do not modify existing data.
- Never hardcode TYPE_KEYs — always resolve from bootstrap.
- Only follow M:1 relationship chains (no fan-out). Exclude or flag M:M relationships.
- Never assume physical columns — always resolve via bootstrap.
- Use the active dialect from the focal context for all SQL generation. Only PostgreSQL patterns are currently implemented.

## Phase 1: Interview

Ask the user one question at a time using the `AskUserQuestion` tool. Do NOT print questions as text.

### Question 1 — Entity Selection

Auto-classify entities from the bootstrap:
- **Bridge candidates:** Entities with at least one timestamp attribute (STA_TMSTP or END_TMSTP) and/or numeric attributes (VAL_NUM)
- **Peripheral candidates:** ALL entities reachable via recursive M:1 relationship chains from the bridge sources. Follow the "Recursive Peripheral Discovery" algorithm in `uss-patterns.md` — walk every M:1 chain to its terminal entity. Every discovered entity becomes a peripheral AND contributes rows to the bridge.

<HARD-GATE>
**You MUST ask the user to confirm the entity classification before proceeding. Do NOT skip this step.**
</HARD-GATE>

Present the classification and ask the user to confirm. Call the `AskUserQuestion` tool (do NOT print the question as text):
- Question: "Based on the metadata, here's my proposed USS layout:\n\n**Bridge sources:** ENTITY_A, ENTITY_B\n**Peripherals:** ENTITY_C, ENTITY_D\n\nDoes this look right?"
- Options: "Yes" / "No, let me adjust"

**STOP and wait for the user's answer before proceeding.**

If the user adjusts, re-classify based on their input.

### Question 2 — Temporal Mode

- Question: "How should timestamps be handled in the bridge?"
- Options:
  - "Event-grain unpivot (Recommended)" — Unpivots all timestamps into `event` + `event_occurred_on` rows. Enables canonical `_dates` and `_times` peripherals.
  - "Columnar dates" — Each timestamp stays as a separate column (e.g., `order_date`, `ship_date`). No synthetic date/time peripherals.

### Question 3 — Peripheral Versioning

- Question: "How should peripherals handle versioning?"
- Options:
  - "Latest for all (Type 1)" — One row per entity, current state. Simple key joins in the bridge.
  - "Full history for all (Type 2)" — Versioned rows with `effective_from` / `effective_to`. Point-in-time joins in the bridge.
  - "Per peripheral" — Choose SCD type for each peripheral individually.

If "Per peripheral", ask for each peripheral entity:
- Question: "Versioning for {ENTITY}?"
- Options:
  - "Type 1 (latest only)" — One row per entity.
  - "Type 2 (full history)" — Versioned rows with temporal ranges.

### Question 4 — Materialization

- Question: "How should the USS be materialized?"
- Options:
  - "All views" — Every file is a CREATE VIEW statement
  - "All tables" — Every file is a CREATE TABLE AS statement
  - "Bridge as table, peripherals as views" — Bridge materialized, peripherals are views
  - "Custom" — I'll specify per file

If "Custom", ask for each file type (bridge, peripherals, synthetics) separately.

### Question 5 — Output Folder

- Question: "Where should I write the SQL files? Default: `uss/`"
- Options: "uss/" / "Custom path"

If "Custom path", ask the user to provide the path.

## Phase 2: Generate

After all interview answers are collected, dispatch a single subagent using the `Agent` tool to generate all SQL files.

**Source schema:** Use `FOCAL_PHYSICAL_SCHEMA` from the bootstrap result as the source schema in all generated SQL `FROM` clauses. This is typically `daana_dw` but varies by installation. Never hardcode the schema — always resolve it from the bootstrap.

### Subagent prompt template

The subagent prompt MUST include all of the following — the subagent has no other context:

1. **Role:** "You are a SQL DDL generator creating a Unified Star Schema from Focal metadata."
2. **Scope rules:** Copy the Scope section from this skill verbatim:
   - DDL generation only. You produce SQL files — you do not modify existing data.
   - Never hardcode TYPE_KEYs — always resolve from bootstrap.
   - Only follow M:1 relationship chains (no fan-out). Exclude or flag M:M relationships.
   - Never assume physical columns — always resolve via bootstrap.
   - Use the active dialect from the focal context for all SQL generation. Only PostgreSQL patterns are currently implemented.
   - Every `ranked` CTE in snapshot mode MUST include `WHERE ROW_ST = 'Y'` — both in peripherals and in the bridge. Historical mode omits this filter.
3. **Bootstrap data:** The full cached bootstrap result from the current session context, serialized as a markdown table.
4. **Connection details:** Host, port, user, database, password (env var reference), sslmode — from the current session context.
5. **Dialect instructions:** The full dialect instructions from the current session context — execution command, statement timeout, syntax rules.
6. **USS patterns:** Read @references/uss-patterns.md and include the full contents in the subagent prompt.
7. **USS examples:** Read @references/uss-examples.md and include the full contents in the subagent prompt.
8. **Interview answers:**
   - Entity classification: bridge sources and peripherals
   - Temporal mode: event-grain unpivot or columnar dates
   - Peripheral versioning: latest all (Type 1), full history all (Type 2), or per-peripheral with individual choices
   - Materialization: views, tables, mixed, or custom per-file
   - Output folder path
   - Target schema name
9. **Column naming conventions:**

   | Pattern | Example | Description |
   |---------|---------|-------------|
   | `peripheral` | `peripheral` | Source entity name (no prefix) |
   | `event` | `event` | Event name (no prefix) |
   | `event_occurred_on` | `event_occurred_on` | Full timestamp (no prefix) |
   | `_key__{entity}` | `_key__customer` | FK to peripheral |
   | `_key__dates` | `_key__dates` | FK to synthetic date peripheral |
   | `_key__times` | `_key__times` | FK to synthetic time peripheral |
   | `_measure__{entity}__{attr}` | `_measure__order_line__unit_price` | Measure value |
   | `valid_from` | `valid_from` | Historical mode only |
   | `valid_to` | `valid_to` | Historical mode only |

10. **File naming rules:**
    - Peripheral entities: lowercased entity name without `_FOCAL` suffix (e.g., `CUSTOMER_FOCAL` -> `customer.sql`)
    - Synthetic files: prefixed with underscore (`_bridge.sql`, `_dates.sql`, `_times.sql`)

11. **DDL wrapping rules:** Based on the user's materialization choice:
    - **View:** `CREATE OR REPLACE VIEW {schema}.{name} AS ...`
    - **Table:** `CREATE TABLE {schema}.{name} AS ...`

12. **Generation order:** Peripherals first, then bridge, then synthetic date peripheral, then synthetic time peripheral.

13. **Output instructions:** "Generate all SQL files and write them to {output_folder}. Return a list of generated files with brief descriptions."

### Result handling

Present the subagent's file list to the user. If the subagent reports errors, offer to retry with adjusted parameters.

Then proceed to Phase 3.

## Phase 3: Handover

After generating all files:

1. List the generated files with a brief description of each.
2. <HARD-GATE>
**You MUST ask the user for permission before executing any DDL. Do NOT execute DDL without explicit consent.**
</HARD-GATE>

   Call the `AskUserQuestion` tool (do NOT print the question as text):
   - Question: "Want me to execute these DDL statements against the database?"
   - Options: "Yes, execute all" / "No, I'll run them manually"

   **STOP and wait for the user's answer. Do NOT execute DDL until the user responds.**

   - If yes: execute each file in order (peripherals -> bridge -> synthetics) using the connection details from the focal context.
   - If no: "Files are ready in `{output_folder}/`. You can run them manually."
3. Suggest: "You can now use `/daana-query` to query the unified star schema."
