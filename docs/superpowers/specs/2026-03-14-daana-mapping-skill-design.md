# `/daana-mapping` Skill Design — Orchestrator Refactor + Mapping Interview

**Date:** 2026-03-14
**Status:** Implemented

## Overview

Refactor the existing `/daana` skill into an orchestrator architecture and add a new mapping interview skill. The result is three skills:

- `/daana` — lightweight orchestrator that detects state and routes to sub-skills
- `/daana-model` — the current model interview (extracted from `/daana`)
- `/daana-mapping` — new interview-driven mapping file builder

All three share reference material from a single canonical location (`skills/daana/references/`).

## Architecture

### Skill Structure

```
skills/
  daana/
    SKILL.md                          ← orchestrator (entrypoint)
    references/
      source-schema-formats.md        ← shared by both sub-skills
      model-schema.md                 ← used by daana-model
      model-examples.md               ← used by daana-model
      mapping-schema.md               ← used by daana-mapping
      mapping-examples.md             ← used by daana-mapping
  daana-model/
    SKILL.md                          ← references skills/daana/references/*
  daana-mapping/
    SKILL.md                          ← references skills/daana/references/*
```

All reference material lives under the orchestrator. Sub-skills are SKILL.md files that point to `skills/daana/references/` — no duplication.

### Invocation Flow

```
User runs /daana
  │
  ├── No model.yaml? ──→ Invoke /daana-model (via Skill tool)
  │                           │
  │                           └── Model complete ──→ "Want to create mappings?"
  │                                                      │
  │                                                      └── Yes ──→ Invoke /daana-mapping (via Skill tool)
  │
  ├── model.yaml exists, unmapped entities? ──→ Invoke /daana-mapping (via Skill tool)
  │
  └── All entities mapped ──→ Summarize status, suggest next steps
```

The orchestrator auto-chains: after `/daana-model` completes, it flows directly into mapping. After `/daana-mapping` completes, it suggests next steps (workflow/connections — future).

**Invocation mechanism:** The orchestrator uses the Skill tool to invoke sub-skills (e.g., `Skill(daana-model)`, `Skill(daana-mapping)`). Sub-skills run inline in the same conversation context — no `context: fork`. This preserves conversation history, including any parsed source schema context.

### Source Schema Shortcut

Before routing to either sub-skill, the orchestrator asks: "Do you have a source schema to work from? (Swagger/OpenAPI, OData metadata, or dlt schema)"

If yes, the orchestrator parses the schema and summarizes the extracted tables/columns/types in conversation text. This summary becomes part of the conversation context available to whichever sub-skill runs next — no file persistence needed.

## Orchestrator: `/daana`

The orchestrator is lightweight — detection and routing only:

1. **Read `model.yaml`** — if missing, invoke `/daana-model`
2. **After model exists** — scan `mappings/` for existing mapping files, compare against entities in model
3. **If unmapped entities exist** — "Your model has X entities. Y are already mapped. Want to create mappings for the rest?"
4. **If all mapped** — "Everything's mapped! Next step would be workflow and connections (coming soon)."
5. **Auto-chain** — after `/daana-model` completes, flow directly into step 2

### Frontmatter

```yaml
name: daana
description: Interview-driven DMDL builder for the Daana data platform. Routes to model and mapping sub-skills based on project state.
disable-model-invocation: true
```

## `/daana-model` (Extracted)

This is the current `/daana` SKILL.md moved to its own skill directory with two changes:

1. **Source schema support** — if the orchestrator parsed a source schema, `/daana-model` uses it to suggest entities and attributes instead of relying purely on natural language. It still confirms everything with the user.
2. **References path update** — all references point to `skills/daana/references/` instead of local `references/`
3. **Remove future-version message** — the current Phase 4 wrap-up says "Next you'll want to create mappings — coming in a future version." This is replaced by the orchestrator's auto-chain into `/daana-mapping`.

No other behavioral changes. Same four phases:

- Phase 1: Detection & Setup
- Phase 2: Entity Interview Loop
- Phase 3: Relationship-Driven Expansion
- Phase 4: Review & Wrap-up

### Frontmatter

```yaml
name: daana-model
description: Interview-driven DMDL model.yaml builder. Walks users through defining entities, attributes, and relationships.
disable-model-invocation: true
```

## `/daana-mapping` (New)

### Design Principles

- No database access — purely conversational, user provides source table details
- Requires `model.yaml` to exist (orchestrator guarantees this)
- One mapping file per entity: `mappings/<entity-lowercase>-mapping.yaml`
- Step-by-step interview with smart batching for column matching
- Mirrors `/daana-model`'s guided, one-question-at-a-time style
- Opinionated but deferential: suggests defaults, always confirms before writing

### Phase 1: Entity Selection

- Read `model.yaml` to get all entities with their attributes and relationships
- Check `mappings/` for existing mapping files — show mapped vs unmapped
- Suggest first unmapped entity, let user pick

### Phase 2: Table Interview (per table)

1. Ask for **connection name** (if a previous table in this mapping used a connection, suggest reusing it)
2. Ask for **table name** (`schema.table` format)
3. Ask for **primary key column(s)** (array of column names; can be a composite expression like `order_id || ' ' || line_id`)
4. Confirm **ingestion strategy** (default FULL, explain options if user asks — see Ingestion Strategies below)
5. Ask for **entity effective timestamp expression** — "What column or expression represents when changes happen in this table?"
6. If source schema was parsed: auto-extract columns from the matching table and present them. If source schema table not found: warn and fall back to manual. If no source schema: ask user to list available columns in this table
7. **Smart matching**: auto-match source columns to model attributes using case-insensitive comparison after converting to UPPER_SNAKE_CASE (e.g., `customer_name` → `CUSTOMER_NAME`, `customerName` → `CUSTOMER_NAME`). Present matches in a summary table for confirmation
8. For unmatched attributes: ask one at a time for the transformation expression
9. Offer optional overrides for attributes that need them:
   - **`where`** clause (attribute-level) — filter specific attribute values (e.g., `customer_name IS NOT NULL`)
   - **`attribute_effective_timestamp_expression`** — override the table-level default for this attribute
   - **`ingestion_strategy`** — override the table-level strategy for this attribute
10. Offer optional **table-level `where`** clause — filter rows from the source table entirely (e.g., `status != 'deleted'`)
11. Ask "Does this entity need data from another table?" — if yes, loop to step 1 (new connection/table)

### Ingestion Strategies

| Strategy | Default | Best For | Description |
|----------|---------|----------|-------------|
| **FULL** | Yes | Small dimension tables | Complete snapshot of all data for each delivery |
| **INCREMENTAL** | | Large fact tables | Only changed or new data since last load (requires watermark column) |
| **FULL_LOG** | | Change history tables | Complete history of all changes, with multiple rows per instance |
| **TRANSACTIONAL** | | Append-only event logs | Append-only data where each instance is delivered exactly once |

### Phase 3: Relationships

- Check model for relationships where this entity is the source
- For each relationship: suggest `source_table` from tables already defined in this mapping, ask for `target_transformation_expression` (the column/expression that identifies the target entity)
- Relationship target entity does not need to be mapped yet — the expression references a source table column, not the target's mapping
- Skip silently if no relationships exist for this entity

### Phase 4: Review & Write

- Present full mapping summary
- `allow_multiple_identifiers` defaults to `false` — only surface if multiple tables map the same identifier attribute, then warn: "This setting is irreversible. Once enabled and materialized, you cannot go back to single identifier mode."
- Mapping group name is always `default_mapping_group`
- Write to `mappings/<entity-lowercase>-mapping.yaml`
- Validate with `daana-cli check mapping` if available, otherwise use built-in validation
- Ask "Want to map another entity?" — if yes, loop to Phase 1

### YAML Generation Rules

- File structure: `entity_id` at root, then `mapping_groups` array with one group
- Mapping group fields in order: `name` (always `"default_mapping_group"`), `allow_multiple_identifiers`, `tables`, `relationships`
- Table fields in order: `connection`, `table`, `primary_keys`, `ingestion_strategy`, `where` (if set), `entity_effective_timestamp_expression`, `attributes`
- Attribute fields in order: `id`, `transformation_expression`, `ingestion_strategy` (if overridden), `where` (if set), `attribute_effective_timestamp_expression` (if overridden)
- Relationship fields in order: `id`, `source_table`, `target_transformation_expression`
- Formatting: 2-space indentation, quoted strings for all `id` values, `connection`, `table`, `source_table`, and expression values
- Unquoted: `allow_multiple_identifiers` (boolean), `ingestion_strategy` (enum), `primary_keys` items (unless they contain expressions)
- Omit optional fields entirely when not set (don't write empty values)
- Initial creation: Write tool for new mapping file
- Re-read file before editing if updating an existing mapping

### Example Output

Complete mapping file for an ORDER entity:

```yaml
entity_id: "ORDER"

mapping_groups:
  - name: "default_mapping_group"
    allow_multiple_identifiers: false

    tables:
      - connection: "dev"
        table: "public.orders"

        primary_keys:
          - order_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"

        attributes:
          - id: "ORDER_ID"
            transformation_expression: "order_id"
            where: "order_id IS NOT NULL"

          - id: "ORDER_STATUS"
            transformation_expression: "UPPER(status)"
            attribute_effective_timestamp_expression: "status_changed_at"

          - id: "ORDER_AMOUNT"
            transformation_expression: "CAST(total_amount AS DECIMAL(10,2))"
            where: "total_amount > 0"
            attribute_effective_timestamp_expression: "updated_at"

          - id: "ORDER_AMOUNT_CURRENCY"
            transformation_expression: "currency_code"

          - id: "PLACED_AT"
            transformation_expression: "order_date"

          - id: "DELIVERED_AT"
            transformation_expression: "delivered_date"

    relationships:
      - id: "IS_PLACED_BY"
        source_table: "public.orders"
        target_transformation_expression: "customer_id"
```

### Frontmatter

```yaml
name: daana-mapping
description: Interview-driven DMDL mapping file builder. Maps source tables to model entities with transformation expressions.
disable-model-invocation: true
```

## Source Schema Parsing

### Supported Formats

**Swagger/OpenAPI JSON/YAML**
- Extract `definitions` or `components.schemas` objects
- Each schema → potential table, properties → columns
- Use property types to inform attribute type inference in `/daana-model`
- Use property names for column matching in `/daana-mapping`

**OData Metadata XML**
- Parse `EntityType` elements from `$metadata`
- Each entity type → potential table, `Property` elements → columns
- `EdmType` maps to DMDL types (e.g., `Edm.String` → STRING, `Edm.Decimal` → NUMBER)

**dlt Schema JSON/YAML**
- Parse `tables` from dlt schema
- Each table → source table (already in `schema.table_name` format), columns with `data_type` → columns
- dlt types map to DMDL types (e.g., `text` → STRING, `bigint`/`double` → NUMBER, `timestamp` → START_TIMESTAMP)

### Behavior

- Orchestrator asks once: "Do you have a source schema?"
- User pastes content or provides a file path
- Skill auto-detects format from structure:
  - JSON with `swagger` or `openapi` key → Swagger/OpenAPI
  - XML with `edmx` namespace → OData metadata
  - JSON/YAML with dlt `tables` structure → dlt schema
- Parsed result: a normalized list of tables with their columns and inferred types
- Orchestrator summarizes the parsed schema in conversation text before invoking the sub-skill, making it available as conversation context

### Usage in Sub-Skills

- **`/daana-model`**: suggests entities from tables, attributes from columns, with inferred DMDL types
- **`/daana-mapping`**: auto-populates connection/table names, auto-matches columns, suggests transformation expressions

## Validation

### With `daana-cli`

Run `daana-cli check mapping <file> --model model.yaml --connections connections.yaml` if available.

### Without `daana-cli` (Built-in Checks)

1. `entity_id` references a valid entity in `model.yaml`
2. All attribute `id` values reference valid attributes in that entity
3. All relationship `id` values reference valid relationships where this entity is the source
4. Required fields present: `connection`, `table`, `primary_keys`, `ingestion_strategy`, `attributes`
5. Ingestion strategy is one of: FULL, INCREMENTAL, FULL_LOG, TRANSACTIONAL
6. `source_table` in relationships matches a table defined in the mapping
7. No duplicate attribute IDs within a table

## Edge Cases

- **Entity already mapped**: warn user, offer to overwrite or skip
- **Model changes after mapping exists**: detect mismatches (new attributes not yet mapped, removed attributes still mapped)
- **Multiple tables mapping same attribute**: valid scenario (e.g., legacy + new table both provide CUSTOMER_ID) — surface `allow_multiple_identifiers` question with irreversibility warning
- **Empty transformation expression**: refuse, every attribute needs one
- **Grouped attributes in model**: map each inner attribute individually — the mapping file uses flat attribute IDs, not groups
- **No relationships for entity**: skip Phase 3 silently
- **Source schema table not found**: if user references a table not in the parsed schema, warn and fall back to manual column entry
- **Connection reuse**: when mapping multiple tables for the same entity, suggest reusing the previous connection name

## Out of Scope

- Database introspection / live connection
- Workflow files (`/daana-workflow` — future)
- Connections files (`/daana-connections` — future)
- Delete/rename operations on existing mappings
- Visual UI or diagram generation
- Multi-model file support
- Multiple mapping groups per file (schema supports it, but this skill always creates one `default_mapping_group` — can be extended later)
