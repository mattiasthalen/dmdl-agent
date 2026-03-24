---
name: daana-uss
description: Generate a Unified Star Schema (Francesco Puppini) as DDL from a Focal-based Daana data warehouse — a single bridge table connecting all peripherals through resolved M:1 chains.
---

# Daana Unified Star Schema Generator

You generate a Unified Star Schema (USS) as a folder of SQL DDL files from a Focal-based Daana data warehouse. The USS eliminates fan traps and chasm traps by creating a single bridge table that all peripherals (complete entity views) join to through resolved M:1 relationship chains.

Read `${CLAUDE_SKILL_DIR}/references/uss-patterns.md` and `${CLAUDE_SKILL_DIR}/references/uss-examples.md` before proceeding.

## Key Concepts

- **Bridge** (`_bridge.sql`) — Central table. UNION ALL of fact rows from all participating entities. Contains resolved FK keys to peripherals, measures, and (if event-grain) unpivoted event timestamps. A `peripheral` column identifies the source entity.
- **Peripheral** (`{entity}.sql`) — Complete entity view with ALL attributes regardless of type. Joins to bridge via surrogate key.
- **Synthetic Peripherals** — Auto-generated `_dates.sql` and `_times.sql` that join to the bridge via the event timestamp.

## Scope

- **DDL generation only.** You produce SQL files — you do not modify existing data.
- Never hardcode TYPE_KEYs — always resolve from bootstrap.
- Only follow M:1 relationship chains (no fan-out). Exclude or flag M:M relationships.
- Never assume physical columns — always resolve via bootstrap.

## Phase 1: Bootstrap

Dispatch the focal agent to connect to the database and bootstrap metadata.

<HARD-GATE>
**You MUST dispatch the focal agent before proceeding to the interview. Do NOT skip this step.**
</HARD-GATE>

Fire a subagent using the Agent tool:
- Description: "Bootstrap Focal metadata"
- Prompt: "Connect to the Focal database and run the metadata bootstrap. Return the full bootstrap result."
- The subagent uses the `focal` agent type

Once the focal agent returns, cache the bootstrap result for the session.

## Phase 2: Interview

Ask the user one question at a time using the `AskUserQuestion` tool. Do NOT print questions as text.

### Question 1 — Entity Selection

Auto-classify entities from the bootstrap:
- **Bridge candidates:** Entities with at least one timestamp attribute (STA_TMSTP or END_TMSTP) and/or numeric attributes (VAL_NUM)
- **Peripheral candidates:** Entities referenced via M:1 relationships (on the FOCAL02_KEY side)

Present the classification and ask the user to confirm:
- Question: "Based on the metadata, here's my proposed USS layout:\n\n**Bridge sources:** ENTITY_A, ENTITY_B\n**Peripherals:** ENTITY_C, ENTITY_D\n\nDoes this look right?"
- Options: "Yes" / "No, let me adjust"

If the user adjusts, re-classify based on their input.

### Question 2 — Temporal Mode

- Question: "How should timestamps be handled in the bridge?"
- Options:
  - "Event-grain unpivot (Recommended)" — Unpivots all timestamps into `event` + `event_occurred_on` rows. Enables canonical `_dates` and `_times` peripherals.
  - "Columnar dates" — Each timestamp stays as a separate column (e.g., `order_date`, `ship_date`). No synthetic date/time peripherals.

### Question 3 — Historical Mode

- Question: "Should the USS capture the latest snapshot or preserve temporal history?"
- Options:
  - "Snapshot (latest values)" — RANK pattern for dedup. One row per fact instance.
  - "Historical (valid_from / valid_to)" — Preserve effective timestamps. Adds `valid_from` and `valid_to` columns to bridge and peripherals.

### Question 4 — Materialization

- Question: "How should the USS be materialized?"
- Options:
  - "All views" — Every file is a CREATE VIEW statement
  - "All tables" — Every file is a CREATE TABLE AS statement
  - "Bridge as table, peripherals as views" — Bridge materialized, peripherals are views
  - "Custom" — I'll specify per file

If "Custom", ask for each file type (bridge, peripherals, synthetics) separately.

### Question 5 — Output Folder

- Question: "Where should I write the SQL files?"
- Options: Let the user type a path (provide a suggested default like `uss/`)

## Phase 3: Generate

Build and write SQL files to the output folder. Follow the patterns in `${CLAUDE_SKILL_DIR}/references/uss-patterns.md` exactly.

### Generation Order

1. **Peripherals first** — One `.sql` per peripheral entity (lowercased: `customer.sql`, `product.sql`)
2. **Bridge** — `_bridge.sql` (depends on knowing all peripheral keys)
3. **Synthetic date peripheral** — `_dates.sql` (depends on bridge for min/max year)
4. **Synthetic time peripheral** — `_times.sql` (independent)

### Column Naming Conventions

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

### File Naming

- Peripheral entities: lowercased entity name without `_FOCAL` suffix (e.g., `CUSTOMER_FOCAL` → `customer.sql`)
- Synthetic files: prefixed with underscore (`_bridge.sql`, `_dates.sql`, `_times.sql`)

### Wrap each file with DDL

Based on the user's materialization choice:
- **View:** `CREATE OR REPLACE VIEW {schema}.{name} AS ...`
- **Table:** `CREATE TABLE {schema}.{name} AS ...`

Ask the user for the target schema name if not obvious from the connection profile.

## Phase 4: Handover

After generating all files:

1. List the generated files with a brief description of each.
2. Ask: "Want me to execute these DDL statements against the database?"
   - If yes: dispatch the focal agent to execute each file in order (peripherals → bridge → synthetics).
   - If no: "Files are ready in `{output_folder}/`. You can run them manually."
3. Suggest: "You can now use `/daana-query` to query the unified star schema."
