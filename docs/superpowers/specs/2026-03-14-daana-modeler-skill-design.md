# Daana Modeler Skill Design

**Date:** 2026-03-14
**Status:** Draft
**Scope:** `/daana` Claude Code skill for interactive DMDL model building

## Overview

A Claude Code skill (`/daana`) that interviews users and incrementally builds a valid DMDL `model.yaml` file. The skill guides users through defining business entities, attributes, and relationships using natural conversation, then generates well-structured YAML that conforms to the Daana Model Description Language specification.

### What is DMDL?

The Daana Model Description Language (DMDL) is a YAML-based declarative language for defining data transformation pipelines. A DMDL model defines:

- **Entities** — business objects (e.g., CUSTOMER, ORDER, PRODUCT)
- **Attributes** — properties of entities with typed values (STRING, NUMBER, UNIT, START_TIMESTAMP, END_TIMESTAMP)
- **Relationships** — how entities connect to each other (e.g., ORDER is placed by CUSTOMER)

This skill focuses exclusively on `model.yaml`. Mapping, workflow, and connections files are out of scope for v1.

### Schema Source of Truth

The DMDL model schema is defined in the daana-cli codebase:

- **Go types:** `internal/compiler/types.go` in the [daana-cli repo](https://github.com/daana-code/daana-cli)
- **Generated JSON schemas:** `docs/data/generated/schemas/model.json`
- **Documentation:** `docs/pages/dmdl/model.mdx`

The `references/model-schema.md` file in this skill is derived from these sources. When the DMDL schema evolves, update `model-schema.md` to match.

## Key DMDL Concepts

### `id` vs `name`

Every element (model, entity, attribute, relationship) has both `id` and `name` fields. By DMDL convention, they are set to the same UPPERCASE_WITH_UNDERSCORES value. The `id` is the internal identifier used for cross-references (e.g., relationship targets), while `name` is the display label. The skill always generates identical values for both and does not ask the user to distinguish them.

### `definition` vs `description`

Both fields appear on every element:

- **`definition`** (required) — a concise, single-line technical statement of what the element represents. Used for documentation and metadata. Example: `"A customer account"`
- **`description`** (optional) — a detailed explanation with business context, valid values, or additional notes. Can be multi-line. Example: `"Represents an individual or organization that has made at least one purchase"`

The skill drafts both from the user's natural language. `definition` is kept to one sentence; everything else goes into `description`.

### `effective_timestamp`

This is a **boolean** field on attributes (default: `false`). It controls whether Daana tracks historical changes for the attribute's value over time (SCD Type 2 behavior):

- **`true`** — Daana records when each value was effective, enabling point-in-time queries. Use for attributes that change: customer name, address, status, tier.
- **`false`** (default) — the attribute represents a point-in-time value that doesn't change, like a creation timestamp or an identifier.

The actual timestamp source is configured later in the mapping file (via `entity_effective_timestamp_expression` or `attribute_effective_timestamp_expression`), not in the model.

### Group Attributes

When multiple attributes logically belong together and answer a single "atomic question," they are defined as a group. The group shares a single `effective_timestamp` setting and its members are tracked together historically.

**Constraints:** Each group can have at most 1 of each type: 1 NUMBER, 1 STRING, 1 UNIT, 1 START_TIMESTAMP, 1 END_TIMESTAMP.

**YAML structure:**

```yaml
attributes:
  - id: "ORDER_AMOUNT"
    name: "ORDER_AMOUNT"
    definition: "Order monetary value with currency"
    description: "The total amount of the order paired with its currency code"
    effective_timestamp: true
    group:
      - id: "ORDER_AMOUNT"
        name: "ORDER_AMOUNT"
        definition: "The monetary amount"
        type: "NUMBER"
      - id: "ORDER_AMOUNT_CURRENCY"
        name: "ORDER_AMOUNT_CURRENCY"
        definition: "Currency code"
        type: "UNIT"
```

The outer attribute has no `type` (it has `group` instead). Each inner attribute has a `type` but no `effective_timestamp` (inherited from the outer).

**Note:** The outer attribute and its first group member intentionally share the same `id` (e.g., both are `ORDER_AMOUNT`). This is standard DMDL convention — the outer `id` identifies the group as a whole, while the inner `id` identifies the specific value within the group. The skill's duplicate-ID detection should not flag this pattern.

### Relationship Direction

Relationships have `source_entity_id` and `target_entity_id`. In DMDL, the **source** is the entity that "has" or "holds" the foreign key — the entity that points to another:

- "ORDER is placed by CUSTOMER" → source: ORDER, target: CUSTOMER (the order holds the customer reference)
- "ORDER contains LINE_ITEM" → source: ORDER, target: LINE_ITEM (but actually LINE_ITEM holds the order reference, so: source: LINE_ITEM, target: ORDER)

**Inference rule:** When the user says "A relates to B", the skill should determine which entity holds the reference to the other. The entity with the foreign key is the source. When ambiguous, the skill asks: *"Which side holds the reference — does each ORDER point to a CUSTOMER, or does each CUSTOMER point to an ORDER?"*

**Relationship ID convention:** Derive a verb-phrase ID in UPPERCASE_WITH_UNDERSCORES that describes the relationship from the source's perspective. Examples: `IS_PLACED_BY`, `CONTAINS`, `BELONGS_TO`. When the user's description is vague (e.g., "customers and orders are linked"), the skill proposes a specific verb phrase and confirms: *"I'd call this IS_PLACED_BY — does that describe the relationship?"*

## File Structure

```
daana-modeler/
├── skills/
│   └── daana/
│       ├── SKILL.md              # /daana slash command — persona + interview flow
│       └── references/
│           ├── model-schema.md   # DMDL model YAML schema rules & constraints
│           └── model-examples.md # Complete annotated examples
├── CLAUDE.md                     # Project-level instructions
└── .claude/
    └── settings.json             # Existing config
```

### SKILL.md

The main skill file containing:

- **Frontmatter** — skill registration and configuration
- **Persona** — the skill's identity as a friendly, methodical daana modeling expert
- **Interview flow** — the structured-but-flexible conversation logic
- **YAML generation rules** — how to write and update `model.yaml`
- **References to supporting files** — pointers to `references/` for schema details

### references/model-schema.md

Machine-readable schema rules derived from daana-cli's source of truth (see [Schema Source of Truth](#schema-source-of-truth)):

- All fields for model, entity, attribute, and relationship (required/optional, types, constraints)
- Attribute type definitions (STRING, NUMBER, UNIT, START_TIMESTAMP, END_TIMESTAMP)
- Group attribute structure and constraints (max 1 of each type per group)
- Naming conventions (UPPERCASE_WITH_UNDERSCORES for ids/names)
- `effective_timestamp` boolean semantics and defaults
- Relationship direction conventions (source = entity holding the foreign key)
- Validation rules the skill should enforce even without `daana-cli`

### references/model-examples.md

Annotated examples optimized for quick reference:

- A minimal model (1 entity, no relationships)
- A complete model (3-4 entities with relationships and grouped attributes)
- Examples of each attribute type in context
- Common patterns (amount + currency group, start/end timestamp pairs)
- A grouped attribute example showing the nested YAML structure

## Skill Configuration

### Frontmatter

```yaml
---
name: daana
description: Interview-driven DMDL model builder. Guides you through defining business entities, attributes, and relationships, then writes a valid model.yaml.
disable-model-invocation: true
---
```

- **`disable-model-invocation: true`** — user-triggered only via `/daana`. Prevents Claude from auto-triggering during normal work.
- **No `context: fork`** — runs inline in the main conversation for interactive back-and-forth.
- **No `allowed-tools` restriction** — needs Read, Edit, Write, Bash (for `daana-cli check model`), and Glob (to detect existing files).

### Installation

Users install by either:

1. Adding this repo as a plugin in their `.claude/settings.json`
2. Copying the `skills/daana/` directory into their project's `.claude/skills/`

## Interview Flow

### Phase 1: Detection & Setup

1. **Check for existing model** — use Glob to look for `model.yaml` in the project root.
2. **If found and valid** — read and parse it, summarize what's there (entities, attributes, relationships), then ask: *"I found an existing model with N entities. Want to add more entities, or start fresh?"*
3. **If found but malformed** — warn the user: *"I found a model.yaml but it has issues: [describe problem]. Want me to try to fix it, or start fresh?"* If YAML syntax is broken, offer to start fresh. If it's valid YAML but doesn't conform to DMDL schema, attempt to preserve what's valid and flag what's not.
4. **If not found** — detect the user's knowledge level by asking: *"Do you already know what business entities you need, or should we explore your domain together?"*
5. **Establish model metadata** — for new models, ask about the model's name and purpose. Infer `id` (UPPERCASE), draft `definition` and `description` from the user's natural language. Confirm before writing.

**Scope of "modify":** In v1, the skill supports **adding** entities, attributes, and relationships to an existing model. It does not support deleting or renaming existing elements — users should edit `model.yaml` directly for those operations.

### Phase 2: Entity Interview (per entity)

Each entity goes through this loop, whether introduced directly or through relationship expansion:

1. **Check for duplicates** — if an entity with the same id already exists in the model, inform the user and ask whether to add attributes to the existing entity or skip it.
2. **User describes the entity** — in natural language (e.g., "Customers have a name, email, a loyalty tier, and a signup date"). If the user lists many attributes (roughly 10+), the skill suggests batching: *"That's a lot of attributes — let's start with the most important ones. You can always add more later."*
3. **Infer DMDL fields** from the description:
   - `id` / `name` — UPPERCASE_WITH_UNDERSCORES version of what the user said (always identical)
   - `type` — inferred from semantics:
     - Dates, timestamps, "created at", "started on" → `START_TIMESTAMP`
     - "Ended", "delivered", "completed", "closed" → `END_TIMESTAMP`
     - Amounts, counts, quantities, ratings, scores → `NUMBER`
     - Currency codes, unit labels → `UNIT`
     - Everything else → `STRING`
   - `effective_timestamp` — inferred based on whether the attribute changes over time:
     - Names, statuses, tiers, addresses → `true` (these change)
     - Creation dates, IDs → `false` (these don't change)
   - `group` — detect pairs like "amount and currency" that form composite attributes (see [Group Attributes](#group-attributes) for YAML structure)
   - `definition` — one-sentence technical statement, drafted from user's words
   - `description` — additional context and detail, drafted from user's words
4. **Present summary table** for confirmation:
   ```
   CUSTOMER_NAME     → STRING, track changes: yes
   EMAIL             → STRING, track changes: yes
   LOYALTY_TIER      → STRING, track changes: yes
   SIGNUP_DATE       → START_TIMESTAMP, track changes: no
   ```
   For grouped attributes, show them as a group:
   ```
   ORDER_AMOUNT (group):
     ORDER_AMOUNT          → NUMBER
     ORDER_AMOUNT_CURRENCY → UNIT
   Track changes: yes
   ```
5. **User confirms or corrects** — e.g., "Actually, don't track email changes."
6. **Re-read `model.yaml` before editing** — to avoid conflicts if the file was modified externally.
7. **Write entity to `model.yaml`** — append to the entities list using Edit (or Write for the first entity).
8. **Validate** — if `daana-cli` is available (detected by running `daana-cli --version`; if exit code is non-zero, fall back), run `daana-cli check model model.yaml`. Otherwise rely on built-in schema knowledge from `references/model-schema.md`.

### Phase 3: Relationship-Driven Expansion

After each entity is written:

1. **Ask about related entities** — *"CUSTOMER is saved. Does CUSTOMER relate to any other entities? For example, do customers place orders, own accounts, or have subscriptions?"*
2. **If yes** — capture the relationship semantics (e.g., "customers place orders").
3. **Infer relationship fields**:
   - `id` — e.g., `IS_PLACED_BY`
   - `source_entity_id` / `target_entity_id` — determine direction using the [Relationship Direction](#relationship-direction) convention. The entity holding the foreign key is the source. When ambiguous, ask the user.
   - `definition` / `description` — drafted from the user's words
4. **Check if the related entity already exists** — if it's already in the model (from a previous interview or from an existing file), skip the entity interview and just create the relationship. This prevents circular expansion (e.g., CUSTOMER → ORDER → CUSTOMER).
5. **If the entity is new** — immediately interview it using the full Phase 2 loop. This captures attributes while the user's mental context is fresh.
6. **Write the new entity (if any) and the relationship** to `model.yaml`.
7. **Continue expanding** — *"ORDER is saved, linked to CUSTOMER via IS_PLACED_BY. Does ORDER relate to any other entities?"*
8. **Repeat** until the user says no more related entities exist.

This creates a graph traversal pattern — start with one entity and spider outward through relationships until the user says "that's all." Already-defined entities are never re-interviewed.

### Phase 4: Review & Wrap-up

1. **Relationship review** — present a summary of all entities and relationships. Flag any entities with zero relationships: *"CURRENCY has no relationships — is that intentional, or should it connect to something?"* Ask: *"Any relationships missing or incorrect?"*
2. **Final validation** — run `daana-cli check model` if available.
3. **Suggest next steps** — *"Your model is ready! Next you'll want to create mappings to connect your source data — that's coming in a future version of /daana."*

## Persona & Behavior

### Identity

The skill acts as a friendly, methodical daana modeling expert. It stays in its lane — only handles model definition, never touches mapping, workflow, or connections.

### Adaptive Detection

The skill detects what the user knows and adapts:

- **User knows their domain** — jumps straight to entity definition, minimal hand-holding
- **User is exploring** — asks guiding questions about the business domain, suggests entity candidates
- **User is technical** — uses precise DMDL terminology
- **User is non-technical** — avoids jargon, explains concepts in plain language

### Key Behaviors

- **One question at a time** — never overwhelms with multiple questions
- **Opinionated but deferential** — suggests sensible defaults (types, effective_timestamp), always confirms before writing
- **Teaches as it goes** — briefly explains DMDL concepts when relevant (e.g., "I'm marking this as tracking changes because customer names can update over time")
- **Incremental building** — writes to `model.yaml` after each entity, giving users visible progress
- **Proactive relationship suggestions** — after each entity, suggests connections to trigger natural domain expansion
- **Re-reads before editing** — always re-reads `model.yaml` before making changes to avoid conflicts with external edits

### Inference Rules

The skill infers DMDL fields from natural language:

| User says | Inferred type | Inferred effective_timestamp |
|-----------|--------------|------------------------------|
| "name", "email", "address", "status", "tier" | STRING | true (these change) |
| "ID", "code", "reference number" | STRING | false (identifiers don't change) |
| "amount", "total", "quantity", "score", "rating" | NUMBER | true |
| "currency", "unit of measure" | UNIT | true |
| "created at", "signed up", "started", "placed on" | START_TIMESTAMP | false |
| "delivered", "completed", "ended", "closed at" | END_TIMESTAMP | false |
| "amount and currency" (pair) | group (NUMBER + UNIT) | true (on the group) |

These are defaults — the summary table gives the user a chance to override.

## YAML Generation

### Initial Creation

When no `model.yaml` exists, the skill writes the model metadata + first entity after the first entity interview completes:

```yaml
model:
  id: "MY_MODEL"
  name: "MY_MODEL"
  definition: "A comprehensive business data model"
  description: "Defines entities and relationships for business operations"

  entities:
    - id: "CUSTOMER"
      name: "CUSTOMER"
      definition: "A customer account"
      description: "Represents an individual or organization that makes purchases"
      attributes:
        - id: "CUSTOMER_NAME"
          name: "CUSTOMER_NAME"
          definition: "Customer full name"
          description: "Legal or display name of the customer"
          type: "STRING"
          effective_timestamp: true

        - id: "SIGNUP_DATE"
          name: "SIGNUP_DATE"
          definition: "Account creation date"
          description: "When the customer account was first created"
          type: "START_TIMESTAMP"
```

### Grouped Attribute Example

When the user mentions "amount and currency" or similar pairs:

```yaml
        - id: "ORDER_AMOUNT"
          name: "ORDER_AMOUNT"
          definition: "Order monetary value with currency"
          description: "Total order amount paired with its currency code"
          effective_timestamp: true
          group:
            - id: "ORDER_AMOUNT"
              name: "ORDER_AMOUNT"
              definition: "The monetary amount"
              type: "NUMBER"
            - id: "ORDER_AMOUNT_CURRENCY"
              name: "ORDER_AMOUNT_CURRENCY"
              definition: "Currency code"
              type: "UNIT"
```

### Incremental Updates

For each subsequent entity, the skill re-reads `model.yaml` then uses the Edit tool to append to the `entities` list. Relationships are appended to a `relationships` list (created on first relationship).

### Existing Model

When loading an existing `model.yaml`, the skill reads it, parses what's there, and adds in place using Edit. It never overwrites the whole file.

### YAML Formatting

The skill generates YAML with:
- 2-space indentation
- Quoted string values for `id`, `name`, `definition`, `description`, `type`, `source_entity_id`, `target_entity_id`
- Boolean values unquoted (`true`, `false`)
- Consistent ordering of fields: `id`, `name`, `definition`, `description`, then type-specific fields

### File Path

Default is `model.yaml` in the project root. The skill asks for a different path only if no existing `model.yaml` is found.

## Validation

### With daana-cli

When `daana-cli` is available (detected by running `daana-cli --version`; if the command is not found or exits non-zero, fall back to built-in validation):

- Run `daana-cli check model <path>` (using the actual model file path, which may differ from the default `model.yaml`) after each entity is added
- Surface any errors to the user and help fix them
- Run a final validation at wrap-up

### Without daana-cli

Fall back to built-in schema knowledge from `references/model-schema.md`:

- Verify required fields are present (id, name, definition for all elements; type or group for attributes)
- Check naming conventions (UPPERCASE_WITH_UNDERSCORES)
- Validate attribute types are one of: STRING, NUMBER, UNIT, START_TIMESTAMP, END_TIMESTAMP
- Check group constraints (max 1 of each type per group)
- Verify relationship references point to existing entities
- Check for duplicate entity or attribute IDs

## Edge Cases

### Duplicate Entity IDs

If the user describes an entity whose `id` already exists in the model, the skill informs them and asks: *"CUSTOMER already exists with these attributes: [list]. Want to add more attributes to it, or did you mean a different entity?"*

### Duplicate Attribute IDs

Attribute IDs are scoped to their entity — `NAME` on CUSTOMER and `NAME` on SUPPLIER are both valid and independent. However, within a single entity, attribute IDs must be unique.

If the user describes an attribute whose `id` already exists within the same entity, the skill flags it: *"CUSTOMER_NAME already exists on CUSTOMER. Want to replace it or choose a different name?"*

### Circular Relationships

The relationship-driven expansion tracks which entities have already been defined. If the user describes a relationship to an existing entity, the skill creates only the relationship without re-interviewing the entity.

### SQL Reserved Words as Entity Names

Entity names like ORDER, GROUP, TABLE are valid in DMDL (they're used in the official examples). The skill does not warn about SQL reserved words — DMDL and daana-cli handle this at the mapping/deployment layer, not the model layer.

## Out of Scope (v1)

- Mapping YAML generation (`/daana-mapping` — future skill)
- Workflow YAML generation (`/daana-workflow` — future skill)
- Connections YAML generation (`/daana-connections` — future skill)
- Source database introspection for entity/attribute suggestion
- Visual companion / browser-based UI
- Multi-model file support (splitting entities across files)
- Deleting or renaming entities/attributes in existing models
- Large model optimization (50+ entities) — Edit tool should handle typical model sizes

## Future Extensions

- `/daana-mapping` — interview for mapping files, with source DB introspection
- `/daana-workflow` — interview for workflow orchestration
- `/daana-connections` — interview for database connection profiles
- `/daana` as orchestrator — ties all sub-skills together for end-to-end pipeline creation
