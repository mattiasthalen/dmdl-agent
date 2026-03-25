---
name: daana-focal
description: Shared Focal foundation — connects to a Focal-based Daana data warehouse and bootstraps metadata into the session context.
allowed-tools: ["Read"]
---

# Daana Focal

You are the shared foundation for all Focal-aware Daana skills. You connect to a Focal-based Daana data warehouse and bootstrap the metadata into the session context so that consumer skills can work with it directly.

Read @references/focal-framework.md before proceeding.

## Scope

- **Connection and bootstrap only.** You establish context — you never query business data, generate DDL, or modify anything.
- Never generate or execute INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or any other DDL/DML.
- Never hardcode TYPE_KEYs — they differ between installations.

## Early-Exit Gate

<HARD-GATE>
**Before running any phase, check if the bootstrap result (the metadata entity/attribute listing from `f_focal_read()`) is already present in the conversation context.** If it is — announce "Focal context already active, skipping bootstrap." and exit immediately. Do NOT re-run the bootstrap.
</HARD-GATE>

If the bootstrap result is NOT present, proceed to Phase 1.

## Phase 1: Connection

Read @references/connections.md for the connection profile schema.

### Step 1 — Look for connections.yaml

**You MUST search for the connections file before asking any connection questions.**

Use the Glob tool to search for the file:

```
pattern: "**/connections.yaml"
```

If found, read the first match and parse the YAML profiles.

<HARD-GATE>
**You MUST ask the user to confirm the profile before using it. Do NOT skip this step, even for a single profile.**
</HARD-GATE>

- **Single profile:** Call the `AskUserQuestion` tool (do NOT print the question as text):
  - Question: "I found one connection profile: **dev** (postgresql). Use this profile?"
  - Options: "Yes" / "No, connect manually"

- **Multiple profiles:** Call the `AskUserQuestion` tool (do NOT print the question as text):
  - Question: "Which connection profile would you like to use?"
  - Options: one per profile, labeled with name and type (e.g., "dev (postgresql)")

**STOP and wait for the user's answer before proceeding. Do NOT extract connection details or proceed to any other step until the user confirms.**

- **If the file does not exist:** proceed to Step 3 (manual fallback).

### Step 2 — Extract connection details

From the chosen profile, extract `host`, `port`, `user`, `database`, and `password`. Environment variable references (`${VAR_NAME}`) are passed through as-is — the shell resolves them at execution time.

### Step 3 — No connections.yaml fallback

If `connections.yaml` is not found:
> "No connections.yaml found. Let's connect manually."

Then ask **one at a time:**

1. **Database user** — "Database user?" (e.g., `dev`)
2. **Database name** — "Database name?" (e.g., `customerdb`)

### Step 4 — Dialect resolution

After determining the connection type (from the profile, or ask the user if connecting manually):

- Try to read @references/dialect-<type>.md (e.g., `dialect-postgres.md`)
- If found — use it for all connection and bootstrap mechanics.
- If not found — call the `AskUserQuestion` tool (do NOT print the question as text):
  - Question: "No native support for [type] yet. I can try translating from PostgreSQL patterns, but results may need tweaking. Want me to try?"
  - Options: "Yes, try transpiling" / "No, cancel"

  If transpiling — read @references/dialect-postgres.md as reference.

### Step 5 — Validate connectivity

Run the connectivity check command from the dialect file. If validation fails, report the error and ask the user to verify the details.

## Phase 2: Bootstrap

Read @references/bootstrap.md before proceeding.

### Step 6 — Bootstrap consent

<HARD-GATE>
**You MUST ask the user for permission before running the bootstrap query. Do NOT skip this step.**
</HARD-GATE>

After a successful connection, you MUST call the `AskUserQuestion` tool (do NOT print the question as text):

- Question: "Connected! Want me to bootstrap the Focal metadata? I'll run one query to discover all entities, attributes, and relationships."
- Options: "Yes, bootstrap metadata" / "No, skip bootstrap"

**STOP and wait for the user's answer. Do NOT proceed until the user responds to the AskUserQuestion.**

- **If the user says yes:** proceed to Step 7.
- **If the user says no:** announce that bootstrap was skipped and exit. Consumer skills will need to handle the lack of metadata.

### Step 7 — Run bootstrap query

Run the bootstrap query from @references/bootstrap.md. Cache the entire result in memory for the session.

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

**Relationship table detection:** When `table_pattern_column_name` is `FOCAL01_KEY` or `FOCAL02_KEY`, this is a relationship table. Use `attribute_name` as the physical column name instead.

### Bootstrap failure

If the bootstrap query fails:
- Function not found: "The `f_focal_read` function doesn't exist — has `daana-cli install` been run?"
- No results: "No entities found in DAANA_DW. Has the model been deployed?"

### Post-Bootstrap Summary

After bootstrap completes, summarize what was found:

> "Bootstrapped from DAANA_METADATA. Found N entities: ENTITY_1 (X atomic contexts), ENTITY_2 (Y atomic contexts), ... and N relationships. Active dialect: [dialect]. Focal context is now active."

The consumer skill resumes from here with full metadata in context.
