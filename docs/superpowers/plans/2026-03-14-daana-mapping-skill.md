# Daana Mapping Skill — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `/daana` into an orchestrator, extract `/daana-model`, create `/daana-mapping`, and add shared source schema parsing reference.

**Architecture:** Three skills under `skills/` — `daana` (orchestrator), `daana-model` (extracted model interview), `daana-mapping` (new mapping interview). All reference material lives in `skills/daana/references/`. The orchestrator detects project state and routes to sub-skills via the Skill tool, auto-chaining from model → mapping.

**Tech Stack:** Claude Code skills (SKILL.md + references), YAML, DMDL

**Spec:** `docs/superpowers/specs/2026-03-14-daana-mapping-skill-design.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `skills/daana-model/SKILL.md` | Model interview skill (extracted from current `/daana`) |
| Create | `skills/daana-mapping/SKILL.md` | Mapping interview skill (new) |
| Create | `skills/daana/references/mapping-schema.md` | DMDL mapping schema reference |
| Create | `skills/daana/references/mapping-examples.md` | Annotated mapping YAML examples |
| Create | `skills/daana/references/source-schema-formats.md` | Shared source schema parsing guide |
| Rewrite | `skills/daana/SKILL.md` | Orchestrator (replaces current model interview) |
| Update | `CLAUDE.md` | Updated repo structure |

## Parallelization Strategy

```
Chunk 1: Reference docs + skill extraction (4 parallel tasks)
  ├── Task 1: mapping-schema.md         ← independent
  ├── Task 2: mapping-examples.md       ← independent
  ├── Task 3: source-schema-formats.md  ← independent
  └── Task 4: daana-model SKILL.md      ← independent (copies from existing)

Chunk 2: New skill + orchestrator (2 parallel tasks)
  ├── Task 5: daana-mapping SKILL.md    ← depends on Tasks 1,2,3 (references them)
  └── Task 6: daana orchestrator        ← depends on Task 4 (references sub-skills)

Chunk 3: Housekeeping (3 parallel tasks)
  ├── Task 7: Update CLAUDE.md          ← depends on Chunk 2
  ├── Task 8: Mark spec implemented     ← depends on Chunk 2
  └── Task 9: Structural validation     ← depends on all above
```

---

## Chunk 1: Reference Documents + Model Extraction (4 parallel tasks)

> **Parallelization:** Tasks 1, 2, 3, and 4 are fully independent. Run all four as parallel subagents.

### Task 1: Create mapping-schema.md

**Files:**
- Create: `skills/daana/references/mapping-schema.md`

- [ ] **Step 1: Fetch schema from daana-cli repo**

Check if the daana-cli repo has a mapping schema reference at `https://github.com/daana-code/daana-cli`. Use the same approach as model-schema.md — fetch the source docs page content as a starting point.

Run: `curl -s https://raw.githubusercontent.com/daana-code/daana-cli/main/docs/pages/dmdl/mapping.mdx | head -20`

If the file exists and has content, use it as the source of truth. If not accessible, use the spec's mapping documentation as fallback.

- [ ] **Step 2: Write mapping-schema.md**

Create `skills/daana/references/mapping-schema.md` following the same structure as `model-schema.md` — field tables with Required/Type/Constraints columns, validation rules, and naming conventions.

Must include these sections:
- Root-level fields (`entity_id`, `mapping_groups`)
- Mapping group fields (`name`, `allow_multiple_identifiers`, `tables`, `relationships`)
- Table fields (`connection`, `table`, `primary_keys`, `ingestion_strategy`, `where`, `entity_effective_timestamp_expression`, `attributes`)
- Attribute mapping fields (`id`, `transformation_expression`, `ingestion_strategy`, `where`, `attribute_effective_timestamp_expression`)
- Relationship mapping fields (`id`, `source_table`, `target_transformation_expression`)
- Ingestion strategies table (FULL, INCREMENTAL, FULL_LOG, TRANSACTIONAL)
- Transformation expression syntax (direct column, SQL functions, multiline styles)
- Validation rules (for when daana-cli is not available)

Use the spec section "Validation > Without daana-cli" for validation rules. Use the docs page content fetched in step 1 for field details and constraints.

- [ ] **Step 3: Verify cross-references**

Confirm all fields from the spec's YAML generation rules (lines 164-175) appear in the schema reference. Confirm the validation rules in the schema match the spec's validation section (lines 279-287).

- [ ] **Step 4: Commit**

```bash
git add skills/daana/references/mapping-schema.md
git commit -m "docs: add DMDL mapping schema reference"
```

### Task 2: Create mapping-examples.md

**Files:**
- Create: `skills/daana/references/mapping-examples.md`

- [ ] **Step 1: Write mapping-examples.md**

Create `skills/daana/references/mapping-examples.md` following the same structure as `model-examples.md` — complete, annotated, copy-pasteable YAML examples.

Must include these examples:

**1. Minimal mapping** — single table, three attributes, no relationships:
```yaml
entity_id: "CUSTOMER"

mapping_groups:
  - name: "default_mapping_group"
    allow_multiple_identifiers: false

    tables:
      - connection: "dev"
        table: "public.customers"

        primary_keys:
          - customer_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"

        attributes:
          - id: "CUSTOMER_NAME"
            transformation_expression: "customer_name"

          - id: "EMAIL"
            transformation_expression: "email"

          - id: "SIGNUP_DATE"
            transformation_expression: "signup_date"
```

**2. Complete mapping** — multiple attributes, overrides, relationships:
Use the ORDER example from the spec (lines 181-226). Add annotations explaining each field choice.

**3. Multi-table mapping** — same entity from two source tables:
Show a CUSTOMER entity mapped from both `archive.legacy_customers` and `public.new_customers`. Include annotation about `allow_multiple_identifiers`.

**4. Transformation expression examples** — direct column, SQL function, CASE expression, concatenation, multiline folded style.

**5. Relationship mapping examples** — simple relationship, relationship with expression.

Each example should have annotations in the same style as `model-examples.md` — explanatory text after each YAML block explaining why fields are set that way.

Follow formatting rules from the spec:
- 2-space indentation
- Quoted strings for `id`, `connection`, `table`, `source_table`, and expression values
- Unquoted `allow_multiple_identifiers`, `ingestion_strategy`, `primary_keys` items
- Omit optional fields when not set

- [ ] **Step 2: Verify examples match schema**

Cross-check every example against `mapping-schema.md`. Confirm field ordering, quoting conventions, and required fields all match.

- [ ] **Step 3: Commit**

```bash
git add skills/daana/references/mapping-examples.md
git commit -m "docs: add DMDL mapping examples reference"
```

### Task 3: Create source-schema-formats.md

**Files:**
- Create: `skills/daana/references/source-schema-formats.md`

- [ ] **Step 1: Write source-schema-formats.md**

Create the shared reference for parsing source schemas. This file tells both `/daana-model` and `/daana-mapping` how to extract tables, columns, and types from each supported format.

Must include these sections:

**Format Detection:**
- JSON with `swagger` or `openapi` key → Swagger/OpenAPI
- XML with `edmx` namespace → OData metadata
- JSON/YAML with `tables` key containing objects with `columns` → dlt schema

**Swagger/OpenAPI:**
- Extract from `definitions` (v2) or `components.schemas` (v3)
- Each schema object → table name (use schema key as name)
- Each property → column with name and type
- Type mapping: `string` → STRING, `integer`/`number` → NUMBER, `boolean` → STRING, `string` with `format: date-time` → START_TIMESTAMP

**OData Metadata XML:**
- Parse `<EntityType>` elements
- `Name` attribute → table name
- `<Property>` elements → columns
- Type mapping: `Edm.String`/`Edm.Guid` → STRING, `Edm.Int32`/`Edm.Int64`/`Edm.Decimal`/`Edm.Double` → NUMBER, `Edm.DateTimeOffset`/`Edm.DateTime` → START_TIMESTAMP, `Edm.Boolean` → STRING

**dlt Schema:**
- Parse `tables` object
- Each key → table name (already in `schema.table_name` format from dlt)
- `columns` object → column entries
- Type mapping: `text` → STRING, `bigint`/`double` → NUMBER, `timestamp` → START_TIMESTAMP, `bool` → STRING, `date` → START_TIMESTAMP

**Normalized Output Format:**
Describe the normalized structure the orchestrator should produce:
```
Table: schema.table_name
  Columns:
    - column_name (INFERRED_DMDL_TYPE)
    - column_name (INFERRED_DMDL_TYPE)
```

**Usage guidance:**
- `/daana-model`: Use table names to suggest entities, column names to suggest attributes, inferred types as defaults
- `/daana-mapping`: Use table names for `table` field, column names for smart matching and `transformation_expression` suggestions

- [ ] **Step 2: Commit**

```bash
git add skills/daana/references/source-schema-formats.md
git commit -m "docs: add source schema formats reference"
```

### Task 4: Create daana-model SKILL.md

**Files:**
- Create: `skills/daana-model/SKILL.md`
- Reference: `skills/daana/SKILL.md` (current, to copy from)

- [ ] **Step 1: Copy current SKILL.md content**

Read `skills/daana/SKILL.md`. This becomes the basis for `skills/daana-model/SKILL.md`.

- [ ] **Step 2: Write daana-model SKILL.md**

Create `skills/daana-model/SKILL.md` with these changes from the original:

1. **Frontmatter** — change to:
```yaml
name: daana-model
description: Interview-driven DMDL model.yaml builder. Walks users through defining entities, attributes, and relationships.
disable-model-invocation: true
```

2. **References path** — change all `${CLAUDE_SKILL_DIR}/references/` paths to `skills/daana/references/`. Specifically update:
   - Phase 1 initialization: `${CLAUDE_SKILL_DIR}/references/model-schema.md` → `skills/daana/references/model-schema.md`
   - Phase 1 initialization: `${CLAUDE_SKILL_DIR}/references/model-examples.md` → `skills/daana/references/model-examples.md`
   - Phase 2 Step 8 validation: `${CLAUDE_SKILL_DIR}/references/model-schema.md` → `skills/daana/references/model-schema.md`
   - Phase 4 validation: `${CLAUDE_SKILL_DIR}/references/model-schema.md` → `skills/daana/references/model-schema.md`
   - YAML Generation Rules reference templates: `references/model-examples.md` → `skills/daana/references/model-examples.md`

3. **Remove future-version message** — in Phase 4 step 5, remove: `"Your model is ready! Next you'll want to create mappings to connect your source data — that's coming in a future version of /daana."` Replace with: `"Your model is ready!"`

4. **Add source schema support** — add a new section after "Adaptive Behavior" and before Phase 1:

```markdown
## Source Schema Context

If the orchestrator (`/daana`) parsed a source schema before invoking this skill, the parsed tables and columns will be available in conversation context. When source schema context is present:

- In Phase 1 (Detection & Setup), when asking about entities: suggest entities based on tables found in the source schema.
- In Phase 2 (Entity Interview), when gathering attributes: suggest attributes based on columns found in the matching source table, using inferred DMDL types as defaults.
- Still confirm everything with the user — source schema suggestions are starting points, not final answers.

For source schema format details, see `skills/daana/references/source-schema-formats.md`.
```

5. **Keep everything else unchanged** — same four phases, same inference rules, same YAML generation rules, same validation approach.

- [ ] **Step 3: Verify completeness**

Compare `skills/daana-model/SKILL.md` against `skills/daana/SKILL.md` line by line. Confirm:
- All four phases are present and unchanged (except the Phase 4 message)
- All inference rules are preserved
- All YAML generation rules are preserved
- All validation logic is preserved
- Reference paths are updated correctly
- Source schema section is added

- [ ] **Step 4: Commit**

```bash
git add skills/daana-model/SKILL.md
git commit -m "feat: extract /daana-model skill from /daana"
```

---

## Chunk 2: New Mapping Skill + Orchestrator (2 parallel tasks)

> **Parallelization:** Tasks 5 and 6 are independent of each other. Run both as parallel subagents. Both depend on Chunk 1 being complete.

### Task 5: Create daana-mapping SKILL.md

**Files:**
- Create: `skills/daana-mapping/SKILL.md`
- Reference: `docs/superpowers/specs/2026-03-14-daana-mapping-skill-design.md` (spec)

- [ ] **Step 1: Write the SKILL.md frontmatter and intro**

```yaml
---
name: daana-mapping
description: Interview-driven DMDL mapping file builder. Maps source tables to model entities with transformation expressions.
disable-model-invocation: true
---
```

Write the persona section matching `/daana-model`'s style:
- Friendly, methodical mapping expert
- Guides users through building mapping YAML files via interactive interview
- Opinionated but deferential
- One question at a time

Write the scope section:
- Handles mapping files only (`mappings/<entity>-mapping.yaml`)
- Requires `model.yaml` to exist
- No database access — user provides source table details
- v1 supports creating new mappings; does not support editing or deleting existing mappings

Write the initialization section:
- Read `skills/daana/references/mapping-schema.md` — schema rules and validation constraints
- Read `skills/daana/references/mapping-examples.md` — annotated YAML templates and patterns

- [ ] **Step 2: Write Phase 1 — Entity Selection**

From spec lines 116-120:

```markdown
## Phase 1: Entity Selection

1. Read `model.yaml` with the Read tool. Parse all entities with their attributes and relationships.

2. Use the Glob tool to check for existing mapping files in `mappings/`.

3. Compare entities in the model against existing mapping files. A mapping file `mappings/<entity-lowercase>-mapping.yaml` maps to entity `<ENTITY>`.

4. Present the status:
   - *"Your model has N entities: ENTITY_A, ENTITY_B, ENTITY_C."*
   - *"Already mapped: ENTITY_A. Unmapped: ENTITY_B, ENTITY_C."*
   - Or: *"None are mapped yet."*

5. Suggest the first unmapped entity: *"Let's start with ENTITY_B. Sound good, or would you prefer a different one?"*
```

- [ ] **Step 3: Write Phase 2 — Table Interview**

From spec lines 122-147. Write each step as a numbered instruction:

1. **Connection name** — ask for the connection profile name. If a previous table in this mapping used a connection, suggest reusing it: *"Same connection as before (dev), or a different one?"*

2. **Table name** — ask in `schema.table` format: *"What's the source table? Use schema.table format, e.g., public.customers."*

3. **Primary keys** — ask for primary key column(s): *"What's the primary key? If it's composite, list all columns."* Note that primary keys can be expressions (e.g., `order_id || ' ' || line_id`).

4. **Ingestion strategy** — suggest FULL as default: *"How should data be loaded from this table? I'll suggest FULL (complete snapshot each delivery) — that works for most dimension tables. Want to change it?"* If user asks, explain all four strategies per the Ingestion Strategies table from the spec.

5. **Entity effective timestamp expression** — always ask: *"What column or expression represents when changes happen in this table? This becomes the default timestamp for all change-tracked attributes. Common choices: CURRENT_TIMESTAMP, updated_at, modified_date."*

6. **Source columns** — if source schema context is present, auto-extract columns from the matching table and present them. If the table isn't found in the schema, warn and fall back to manual. If no source schema, ask: *"List the columns available in this table that we need to map."*

7. **Smart matching** — auto-match source columns to model attributes using case-insensitive comparison after converting to UPPER_SNAKE_CASE. Present matches in a summary table:
```
Source Column          → Model Attribute          → Expression
customer_name          → CUSTOMER_NAME            → customer_name
email                  → EMAIL                    → email
signup_date            → SIGNUP_DATE              → signup_date
loyalty_tier           → LOYALTY_TIER             → loyalty_tier
```
Ask: *"These columns look like direct matches. Does this look right?"*

8. **Unmatched attributes** — for model attributes with no column match, ask one at a time: *"How should ORDER_STATUS be derived? Give me the SQL expression (e.g., UPPER(status), a CASE expression, etc.)."*

9. **Optional overrides** — after all attributes are mapped, ask: *"Do any attributes need special handling?"*
   - `where` clause (attribute-level): filter specific values
   - `attribute_effective_timestamp_expression`: override the table default
   - `ingestion_strategy`: override the table strategy

10. **Table-level where** — ask: *"Should we filter rows from this table? (e.g., status != 'deleted')"*

11. **Additional tables** — ask: *"Does this entity need data from another source table?"* If yes, loop to step 1.

- [ ] **Step 4: Write Phase 3 — Relationships**

From spec lines 148-153:

```markdown
## Phase 3: Relationships

1. Check `model.yaml` for relationships where this entity is the `source_entity_id`.

2. If no relationships exist for this entity, skip this phase silently.

3. For each relationship:
   - Show the relationship: *"Your model defines IS_PLACED_BY (ORDER → CUSTOMER). Let's map it."*
   - Suggest `source_table` from tables already defined in this mapping. If only one table, use it automatically.
   - Ask for `target_transformation_expression`: *"What column or expression identifies the target CUSTOMER? (e.g., customer_id)"*

4. Note: The target entity does not need to be mapped yet. The expression references a column in the source table, not the target's mapping.
```

- [ ] **Step 5: Write Phase 4 — Review & Write**

From spec lines 155-175:

```markdown
## Phase 4: Review & Write

1. Present the full mapping summary showing all tables, attributes, and relationships.

2. **Multiple identifiers check:** If multiple tables map the same attribute (e.g., both provide CUSTOMER_ID), ask about `allow_multiple_identifiers`:
   *"Multiple tables provide CUSTOMER_ID. This requires enabling multiple identifiers. Warning: this setting is irreversible — once enabled and materialized, you cannot go back to single identifier mode. Enable it?"*
   Otherwise, default to `false` without asking.

3. **Mapping group name:** Always use `default_mapping_group`.

4. **Write the file:** Use the Write tool to create `mappings/<entity-lowercase>-mapping.yaml`.

5. **Validate:**
   - Check if `daana-cli` is available by running `daana-cli --version`.
   - With daana-cli: Run `daana-cli check mapping mappings/<file> --model model.yaml --connections connections.yaml` and surface any errors.
   - Without daana-cli: Apply validation rules from `skills/daana/references/mapping-schema.md`.

6. **Next entity:** Ask *"Want to map another entity?"* If yes, return to Phase 1.
```

- [ ] **Step 6: Write YAML Generation Rules**

From spec lines 164-175:

```markdown
## YAML Generation Rules

### File Structure

`entity_id` at root, then `mapping_groups` array with one group.

### Field Ordering

- Mapping group: `name`, `allow_multiple_identifiers`, `tables`, `relationships`
- Table: `connection`, `table`, `primary_keys`, `ingestion_strategy`, `where` (if set), `entity_effective_timestamp_expression`, `attributes`
- Attribute: `id`, `transformation_expression`, `ingestion_strategy` (if overridden), `where` (if set), `attribute_effective_timestamp_expression` (if overridden)
- Relationship: `id`, `source_table`, `target_transformation_expression`

### Formatting

- 2-space indentation
- Quoted strings: all `id` values, `connection`, `table`, `source_table`, `name`, and all expression values (`transformation_expression`, `entity_effective_timestamp_expression`, `attribute_effective_timestamp_expression`, `where`, `target_transformation_expression`)
- Unquoted: `allow_multiple_identifiers` (boolean), `ingestion_strategy` (enum keyword), `primary_keys` items (unless they contain expressions like `||`)
- Omit optional fields entirely when not set — do not write empty values

### File Operations

- New mapping file: Use the Write tool
- Updating existing mapping: Re-read the file with Read tool first, then use Edit tool
- File path: `mappings/<entity-lowercase>-mapping.yaml` (e.g., `mappings/customer-mapping.yaml`, `mappings/order-mapping.yaml`)

### Reference Templates

Consult `skills/daana/references/mapping-examples.md` for YAML structure templates when generating output.
```

- [ ] **Step 7: Write Source Schema Context and Edge Cases sections**

```markdown
## Source Schema Context

If the orchestrator (`/daana`) parsed a source schema before invoking this skill, the parsed tables and columns will be available in conversation context. When source schema context is present:

- In Phase 2 step 6: auto-extract columns from the matching source table instead of asking the user to list them.
- In Phase 2 step 7: use source schema column names for smart matching.
- If the user references a table not found in the parsed schema, warn and fall back to manual column entry.

For source schema format details, see `skills/daana/references/source-schema-formats.md`.

## Edge Cases

- **Entity already mapped:** If `mappings/<entity>-mapping.yaml` already exists, warn: *"CUSTOMER is already mapped. Want to overwrite it or skip to the next entity?"*
- **Model changes after mapping exists:** If re-running, detect new attributes not yet mapped or removed attributes still mapped. Surface mismatches to the user.
- **Empty transformation expression:** Refuse — every attribute needs one.
- **Grouped attributes in model:** Map each inner attribute individually. The mapping file uses flat attribute IDs, not groups. For example, if the model has an ORDER_AMOUNT group with ORDER_AMOUNT (NUMBER) and ORDER_AMOUNT_CURRENCY (UNIT), map both as separate attribute entries.
```

- [ ] **Step 8: Review SKILL.md length**

Read the completed `skills/daana-mapping/SKILL.md` and verify it is under 500 lines. If over, consolidate sections or move detailed content to reference files.

- [ ] **Step 9: Commit**

```bash
git add skills/daana-mapping/SKILL.md
git commit -m "feat: add /daana-mapping skill"
```

### Task 6: Rewrite daana SKILL.md as orchestrator

**Files:**
- Rewrite: `skills/daana/SKILL.md`

- [ ] **Step 1: Read current SKILL.md**

Read `skills/daana/SKILL.md` to confirm current content before overwriting.

- [ ] **Step 2: Write orchestrator SKILL.md**

Replace the entire content of `skills/daana/SKILL.md` with the orchestrator:

```yaml
---
name: daana
description: Interview-driven DMDL builder for the Daana data platform. Routes to model and mapping sub-skills based on project state.
disable-model-invocation: true
---
```

Write the orchestrator logic:

```markdown
# Daana

You are the entrypoint for Daana DMDL file creation. You detect the current project state and route to the appropriate sub-skill. You do not build files directly — you delegate to specialized skills.

## Step 1: Source Schema (Optional)

Before routing, ask: *"Do you have a source schema to work from? (Swagger/OpenAPI JSON, OData metadata XML, or dlt schema) You can paste it, give me a file path, or skip this."*

If the user provides a schema:
1. Read `skills/daana/references/source-schema-formats.md` for parsing instructions.
2. Auto-detect the format from the content structure.
3. Parse and summarize the extracted tables, columns, and inferred DMDL types.
4. Present the summary to the user for confirmation.
5. This summary stays in conversation context for whichever sub-skill runs next.

If the user skips, proceed without source schema context.

## Step 2: Detect State

1. Use the Glob tool to check for `model.yaml` in the project root.
2. Use the Glob tool to check for existing mapping files in `mappings/`.

## Step 3: Route

**If no `model.yaml` exists:**
- *"No model found. Let's start by defining your data model."*
- Invoke `/daana-model` using the Skill tool.

**If `model.yaml` exists:**
- Read it with the Read tool. Count entities.
- Compare entities against mapping files in `mappings/`. A file `mappings/<entity-lowercase>-mapping.yaml` maps entity `<ENTITY>`.
- **If unmapped entities exist:**
  - *"Your model has N entities. M are already mapped. Want to create mappings for the unmapped ones?"*
  - If yes, invoke `/daana-mapping` using the Skill tool.
- **If all entities are mapped:**
  - *"Everything's mapped! Next step would be workflow and connections (coming soon)."*

## Step 4: Auto-Chain

After `/daana-model` completes, return to Step 2 to check for unmapped entities and offer mapping.

After `/daana-mapping` completes, summarize what was mapped and suggest next steps.
```

- [ ] **Step 3: Verify orchestrator references**

Confirm the orchestrator only references:
- `skills/daana/references/source-schema-formats.md` (for schema parsing)
- `/daana-model` and `/daana-mapping` (via Skill tool)

It should NOT reference model-schema.md, model-examples.md, mapping-schema.md, or mapping-examples.md directly — those are for the sub-skills.

- [ ] **Step 4: Commit**

```bash
git add skills/daana/SKILL.md
git commit -m "feat: rewrite /daana as orchestrator routing to sub-skills"
```

---

## Chunk 3: Housekeeping (3 parallel tasks)

> **Parallelization:** Tasks 7, 8, and 9 are independent. Run all three as parallel subagents. All depend on Chunk 2 being complete.

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md**

Read `CLAUDE.md` to see the current repo structure section.

- [ ] **Step 2: Update repo structure**

Update the Repository Structure section to reflect the new architecture:

```markdown
## Repository Structure

- **`skills/daana/`** — Orchestrator skill (`/daana` entrypoint)
  - `SKILL.md` — Routes to sub-skills based on project state
  - `references/` — Shared DMDL schema, examples, and source schema formats
- **`skills/daana-model/`** — Model interview skill (`/daana-model`)
  - `SKILL.md` — Builds model.yaml via interactive interview
- **`skills/daana-mapping/`** — Mapping interview skill (`/daana-mapping`)
  - `SKILL.md` — Builds mapping files via interactive interview
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update repo structure for orchestrator architecture"
```

### Task 8: Mark spec as implemented

**Files:**
- Modify: `docs/superpowers/specs/2026-03-14-daana-mapping-skill-design.md`

- [ ] **Step 1: Update spec status**

Change `**Status:** Draft` to `**Status:** Implemented` at the top of the spec.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-03-14-daana-mapping-skill-design.md
git commit -m "docs: mark mapping skill spec as implemented"
```

### Task 9: Structural Validation

- [ ] **Step 1: Verify all files exist**

Run: `ls -la skills/daana/SKILL.md skills/daana-model/SKILL.md skills/daana-mapping/SKILL.md skills/daana/references/mapping-schema.md skills/daana/references/mapping-examples.md skills/daana/references/source-schema-formats.md`

Expected: All six files exist.

- [ ] **Step 2: Verify frontmatter**

Check each SKILL.md has valid YAML frontmatter:
- `skills/daana/SKILL.md` → name: daana, disable-model-invocation: true
- `skills/daana-model/SKILL.md` → name: daana-model, disable-model-invocation: true
- `skills/daana-mapping/SKILL.md` → name: daana-mapping, disable-model-invocation: true

- [ ] **Step 3: Verify cross-references**

Check that:
- `skills/daana/SKILL.md` references `/daana-model` and `/daana-mapping` (Skill tool invocations)
- `skills/daana/SKILL.md` references `skills/daana/references/source-schema-formats.md`
- `skills/daana-model/SKILL.md` references `skills/daana/references/model-schema.md` and `skills/daana/references/model-examples.md`
- `skills/daana-model/SKILL.md` references `skills/daana/references/source-schema-formats.md`
- `skills/daana-mapping/SKILL.md` references `skills/daana/references/mapping-schema.md` and `skills/daana/references/mapping-examples.md`
- `skills/daana-mapping/SKILL.md` references `skills/daana/references/source-schema-formats.md`

- [ ] **Step 4: Verify YAML examples in mapping references**

Read `skills/daana/references/mapping-examples.md` and verify all YAML examples:
- Have correct field ordering per the spec
- Use correct quoting conventions
- Include all required fields
- Match the schema defined in `mapping-schema.md`

- [ ] **Step 5: Verify SKILL.md lengths**

Check that all three SKILL.md files are under 500 lines:
```bash
wc -l skills/daana/SKILL.md skills/daana-model/SKILL.md skills/daana-mapping/SKILL.md
```
