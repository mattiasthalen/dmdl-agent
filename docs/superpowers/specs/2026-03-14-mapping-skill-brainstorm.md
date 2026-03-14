# Mapping Skill Brainstorm

**Date:** 2026-03-14
**Status:** Brainstorm
**Scope:** `/daana-mapping` Claude Code skill for interactive DMDL mapping building

## What is a Mapping?

A DMDL mapping file (`mapping.yaml`) connects a model's entities and attributes to their source data. While `model.yaml` defines *what* business entities look like, `mapping.yaml` defines *where* the data comes from and *how* it gets there.

The mapping bridges the gap between the logical data model (entities, attributes, relationships) and the physical source systems (database tables, columns, SQL expressions).

### Schema Source of Truth

The DMDL mapping schema is defined in the daana-cli codebase:

- **Go types:** `internal/compiler/types.go` in the [daana-cli repo](https://github.com/daana-code/daana-cli)
- **Generated JSON schemas:** `docs/data/generated/schemas/mapping.json`
- **Documentation:** `docs/pages/dmdl/mapping.mdx` ([docs.daana.dev/dmdl/mapping](https://docs.daana.dev/dmdl/mapping))

> **Action needed:** Before implementation, extract the complete mapping schema from daana-cli's source of truth. The brainstorm below is based on what we can infer from the model skill's references to mapping concepts.

## What We Know From the Model Skill

The existing model skill references mapping in several places:

1. **`effective_timestamp` source** — "The actual timestamp source is configured in the mapping file (via `entity_effective_timestamp_expression` or `attribute_effective_timestamp_expression`), not in the model." This tells us mappings have SQL expressions for timestamps.

2. **Future vision** — The design spec mentions `/daana-mapping` as "interview for mapping files, with source DB introspection."

3. **Next steps prompt** — "Your model is ready! Next you'll want to create mappings to connect your source data."

4. **SQL reserved words** — "DMDL and daana-cli handle this at the mapping/deployment layer, not the model layer."

## Inferred Mapping Concepts

### Core Structure (Inferred)

Based on DMDL's declarative philosophy and the model schema patterns, a mapping likely follows this structure:

```yaml
mapping:
  id: "MY_MAPPING"
  name: "MY_MAPPING"
  definition: "Maps source tables to the business model"

  model_id: "MY_MODEL"              # Reference to the model being mapped
  connection_id: "MY_CONNECTION"     # Reference to the source database connection

  entity_mappings:
    - entity_id: "CUSTOMER"          # References model entity
      source_table: "public.customers"  # Or SQL expression

      # Timestamp expression for SCD Type 2 tracking
      entity_effective_timestamp_expression: "updated_at"

      attribute_mappings:
        - attribute_id: "CUSTOMER_NAME"
          source_expression: "full_name"   # Column name or SQL expression

        - attribute_id: "EMAIL"
          source_expression: "email_address"

        - attribute_id: "SIGNUP_DATE"
          source_expression: "created_at"

        - attribute_id: "ORDER_AMOUNT"    # Group attribute
          attribute_effective_timestamp_expression: "price_updated_at"
          group_mappings:
            - attribute_id: "ORDER_AMOUNT"
              source_expression: "amount"
            - attribute_id: "ORDER_AMOUNT_CURRENCY"
              source_expression: "currency_code"
```

### Key Mapping Fields (Inferred)

| Field | Level | Purpose |
|-------|-------|---------|
| `model_id` | Mapping | Which model this mapping implements |
| `connection_id` | Mapping | Which database connection to use |
| `entity_id` | Entity mapping | Which model entity this maps to |
| `source_table` | Entity mapping | Source table/view name (schema-qualified) |
| `entity_effective_timestamp_expression` | Entity mapping | Default SQL expression for SCD timestamps on this entity |
| `attribute_id` | Attribute mapping | Which model attribute this maps to |
| `source_expression` | Attribute mapping | SQL column or expression that provides the value |
| `attribute_effective_timestamp_expression` | Attribute mapping | Override timestamp expression for specific attributes |

## Open Questions

These must be answered by reading the actual daana-cli schema before implementation:

### Schema Questions

1. **Exact YAML structure** — What is the precise top-level key? `mapping:` or something else?
2. **Field names** — What are the exact field names? Are they snake_case?
3. **Source table syntax** — Is it `source_table`, `source`, `from`, or something else? Is it a table name or arbitrary SQL?
4. **Expression fields** — Are source columns referenced as strings, SQL expressions, or something richer?
5. **Multiple mappings** — Can one mapping file map multiple entities, or is it one file per entity?
6. **Relationship mappings** — Do relationships need explicit mapping, or are they inferred from foreign keys?
7. **Connection reference** — Does the mapping reference a connection directly, or is that configured elsewhere?
8. **Deduplication config** — Does the mapping define deduplication rules, or is that automatic?
9. **Transformation expressions** — What SQL functions/expressions are supported in mappings?
10. **Group attribute mapping** — How are grouped attributes (NUMBER + UNIT pairs) mapped? Individual columns or as a block?
11. **Validation command** — Is it `daana-cli check mapping <path>` like the model check command?
12. **File naming** — Is it always `mapping.yaml`, or can there be multiple mapping files?

### Design Questions

13. **Prerequisite: model.yaml** — The mapping skill must require an existing `model.yaml`. Should it auto-detect and parse it?
14. **Prerequisite: connections** — Does the user need a `connections.yaml` first, or can mappings work without one?
15. **Source DB introspection** — Can we read database schemas to suggest column-to-attribute mappings? What access patterns does this require?
16. **Skill orchestration** — Should `/daana-mapping` be standalone, or invoked from `/daana` after model creation?

## Proposed Interview Flow

### Phase 1: Detection & Prerequisites

1. **Check for `model.yaml`** — must exist and be valid. If missing, direct user to `/daana` first.
2. **Parse the model** — read and understand all entities, attributes, groups, and relationships.
3. **Check for existing `mapping.yaml`** — if found, summarize and ask "add more entity mappings or start fresh?"
4. **Detect connection** — check for `connections.yaml` or ask for database connection details.
5. **Source DB introspection** (if connection available) — list available schemas/tables to help the user identify source tables.
6. **Establish mapping metadata** — infer `id`, `definition` from the model name. Confirm.

### Phase 2: Entity Mapping Interview (per entity)

For each unmapped entity in the model:

1. **Present the entity** — show entity name, attributes, and types from the model.
2. **Ask for source table** — *"Where does CUSTOMER data come from? Give me a table name like `public.customers`."*
3. **Source introspection** (if available) — list columns from the source table, auto-suggest mappings based on name similarity.
4. **Map attributes one by one** — for each model attribute:
   - Suggest a source column if one matches by name
   - Ask user to confirm or provide the correct column/expression
   - Handle group attributes by mapping each inner attribute individually
5. **Timestamp expressions** — for entities with `effective_timestamp: true` attributes:
   - Ask for the `entity_effective_timestamp_expression` (default column for change tracking)
   - Allow per-attribute overrides via `attribute_effective_timestamp_expression`
6. **Present summary** — show the complete entity mapping for confirmation.
7. **Write to `mapping.yaml`** — append or create.
8. **Validate** — run `daana-cli check mapping` if available.

### Phase 3: Review & Wrap-up

1. **Coverage check** — flag unmapped entities from the model. Ask if they should be mapped now or later.
2. **Final validation** — run `daana-cli check mapping` if available.
3. **Suggest next steps** — workflows, or running `daana-cli` to execute the pipeline.

## Inference Opportunities

The mapping skill has rich inference potential because it can cross-reference two sources of information: the model schema and the source database schema.

### Column-to-Attribute Matching

| Model Attribute | Likely Source Column Patterns |
|----------------|------------------------------|
| `CUSTOMER_NAME` | `name`, `full_name`, `customer_name`, `cust_name` |
| `EMAIL` | `email`, `email_address`, `e_mail` |
| `SIGNUP_DATE` | `created_at`, `signup_date`, `registration_date` |
| `ORDER_AMOUNT` | `amount`, `total`, `order_total`, `price` |
| `STATUS` | `status`, `state`, `order_status` |

### Strategies

1. **Exact match** — attribute ID lowercased matches column name
2. **Fuzzy match** — Levenshtein distance or common abbreviations
3. **Semantic match** — understanding that `full_name` maps to `CUSTOMER_NAME`
4. **Type match** — NUMBER attributes map to numeric columns, TIMESTAMP attributes map to timestamp columns

### Auto-Mapping Confidence Levels

- **High confidence** — exact or near-exact name match + compatible types → propose as default
- **Medium confidence** — semantic match or type-only match → suggest with explanation
- **Low confidence** — no clear match → ask user directly

## Source DB Introspection

This is the biggest differentiator from the model skill. The mapping skill can potentially:

1. **List schemas and tables** — via `daana-cli` or direct database queries
2. **Describe table columns** — names, types, nullability
3. **Suggest mappings** — cross-reference source columns with model attributes
4. **Detect relationships** — foreign keys in the source can validate model relationships

### Introspection Methods

1. **Via daana-cli** — if it has commands like `daana-cli describe table <connection> <table>`
2. **Via connections.yaml** — if we have database credentials, we could run SQL information_schema queries
3. **User-provided DDL** — ask the user to paste CREATE TABLE statements
4. **No introspection** — manual mapping by asking the user for each column name

The skill should gracefully degrade: try introspection first, fall back to manual mapping.

## Persona & Behavior Considerations

### Differences from Model Skill

| Aspect | Model Skill | Mapping Skill |
|--------|-------------|---------------|
| **Starting point** | Blank slate or existing model | Existing model (required) |
| **User input** | Business domain knowledge | Technical source system knowledge |
| **Inference basis** | Natural language → DMDL types | Source columns → attribute mappings |
| **Validation** | Schema compliance | Schema compliance + source compatibility |
| **Teaching focus** | DMDL concepts | Mapping concepts, SCD timestamps, SQL expressions |
| **Autonomy** | Mostly manual with suggestions | More automated with introspection |

### Key Behaviors

- **Model-aware** — always shows what the model expects, so the user doesn't have to remember
- **Source-curious** — actively explores source schema when possible
- **Mapping-by-entity** — processes one entity at a time, like the model skill
- **Expression-literate** — understands SQL expressions for column references, transformations, and timestamps
- **Progressive complexity** — starts with simple column mappings, introduces expressions only when needed

## File Structure

```
daana-modeler/
├── skills/
│   ├── daana/                     # Existing model skill
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── model-schema.md
│   │       └── model-examples.md
│   └── daana-mapping/             # New mapping skill
│       ├── SKILL.md               # /daana-mapping slash command
│       └── references/
│           ├── mapping-schema.md  # DMDL mapping YAML schema rules
│           └── mapping-examples.md # Complete annotated examples
```

### Skill Configuration

```yaml
---
name: daana-mapping
description: Interview-driven DMDL mapping builder. Connects your model entities to source database tables and columns, then writes a valid mapping.yaml.
disable-model-invocation: true
---
```

## Risks & Challenges

### 1. Schema Uncertainty
We don't have the exact mapping schema yet. The brainstorm above is based on inferences from the model skill. The actual schema could be significantly different.

**Mitigation:** Before implementation, extract the schema from daana-cli's source code or documentation.

### 2. Source DB Access
Introspection requires database connectivity, which may not be available in all environments (especially sandboxed Claude Code sessions).

**Mitigation:** Design for graceful degradation. Introspection is a nice-to-have, not a requirement.

### 3. SQL Expression Complexity
Users may need complex SQL expressions for source mappings (CASE statements, type conversions, joins). The skill needs to handle this without becoming a SQL editor.

**Mitigation:** Support simple expressions by default. For complex cases, let users type raw SQL and validate it at the daana-cli level.

### 4. Connection Dependency
Mappings likely reference a connection, which requires a `connections.yaml`. This creates a dependency chain: connections → model → mapping.

**Mitigation:** Allow mappings to be created with a placeholder connection ID. The user can set up connections separately.

### 5. Model-Mapping Consistency
If the model changes after mappings are created, the mappings may become invalid (e.g., deleted attributes, renamed entities).

**Mitigation:** The mapping skill should re-read and validate against the current model before writing.

## Implementation Priority

### Must Have (MVP)
- Parse existing `model.yaml` as input
- Interview flow for mapping entities to source tables
- Map attributes to source columns/expressions
- Handle `entity_effective_timestamp_expression`
- Write valid `mapping.yaml`
- Validate with `daana-cli check mapping` when available

### Should Have
- Auto-suggest attribute mappings based on name similarity
- Handle group attribute mapping
- `attribute_effective_timestamp_expression` overrides
- Coverage reporting (unmapped entities/attributes)

### Nice to Have
- Source DB introspection via daana-cli or direct queries
- Smart column-to-attribute matching with confidence levels
- User-provided DDL parsing for source schema understanding
- Integration with `/daana` for end-to-end flow

## Next Steps

1. **Extract the mapping schema** — read `docs/pages/dmdl/mapping.mdx` and `internal/compiler/types.go` from daana-cli to get the exact schema
2. **Create `mapping-schema.md`** — machine-readable reference like `model-schema.md`
3. **Create `mapping-examples.md`** — annotated examples
4. **Write the design spec** — formalize the interview flow and YAML generation rules
5. **Implement `SKILL.md`** — the mapping skill itself
6. **Test with real models** — validate against actual `model.yaml` files and `daana-cli`
