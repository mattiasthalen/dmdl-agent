# Daana Modeler Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/daana` Claude Code skill that interviews users and incrementally generates valid DMDL `model.yaml` files.

**Architecture:** A single Claude Code skill (`SKILL.md`) with two reference documents (`model-schema.md`, `model-examples.md`). The skill runs inline in the main conversation for interactive back-and-forth. Reference docs are read on-demand during the interview.

**Tech Stack:** Claude Code skills (Markdown + YAML frontmatter), DMDL YAML schema

**Spec:** `docs/superpowers/specs/2026-03-14-daana-modeler-skill-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `skills/daana/references/model-schema.md` | Create | DMDL model schema rules, field definitions, constraints, validation rules |
| `skills/daana/references/model-examples.md` | Create | Annotated YAML examples for every pattern the skill needs to generate |
| `skills/daana/SKILL.md` | Create | Skill frontmatter + persona + interview flow + YAML generation instructions |
| `CLAUDE.md` | Create | Project-level instructions for contributors |

---

## Chunk 1: Reference Documents

These are the knowledge base the skill reads during interviews. They must be written first because `SKILL.md` references them.

### Task 1: Create model-schema.md

**Files:**
- Create: `skills/daana/references/model-schema.md`
- Reference: daana-cli `docs/data/generated/schemas/model.json` and `docs/pages/dmdl/model.mdx` (fetch via `gh api`)

This file is the skill's machine-readable schema reference. It must contain every field, constraint, and validation rule the skill needs to generate and validate DMDL model YAML — without relying on `daana-cli` being installed.

- [ ] **Step 1: Fetch the latest DMDL model schema from daana-cli**

```bash
# Fetch the generated JSON schema for model
gh api repos/daana-code/daana-cli/contents/docs/data/generated/schemas/model.json --jq '.content' | base64 -d > /tmp/model-schema.json

# Fetch the model documentation
gh api repos/daana-code/daana-cli/contents/docs/pages/dmdl/model.mdx --jq '.content' | base64 -d > /tmp/model-docs.mdx
```

**Fallback:** If `gh api` fails (repo unavailable or auth issues), use the spec document (`docs/superpowers/specs/2026-03-14-daana-modeler-skill-design.md`) as the source of truth — it contains all DMDL schema details needed to write `model-schema.md`.

- [ ] **Step 2: Write model-schema.md**

Create `skills/daana/references/model-schema.md` with the following sections derived from the fetched sources:

1. **Model Fields** — `id` (required, string, UPPERCASE), `name` (required, string, same as id), `definition` (required, string, one-line), `description` (optional, string, detailed), `entities` (required, array), `relationships` (optional, array)
2. **Entity Fields** — `id`, `name`, `definition`, `description`, `attributes` (all documented with required/optional, types, constraints)
3. **Attribute Fields** — `id`, `name`, `definition`, `description`, `type`, `effective_timestamp`, `group` (with mutual exclusivity rule: `type` OR `group`, never both). Include `effective_timestamp` semantics: boolean (default `false`), `true` means Daana tracks historical changes (SCD Type 2), `false` means point-in-time value that doesn't change.
4. **Attribute Types** — STRING, NUMBER, UNIT, START_TIMESTAMP, END_TIMESTAMP (with descriptions of when to use each)
5. **Group Attribute Fields** — inner attribute fields have: `id`, `name`, `definition`, `type`. They do NOT have `description` or `effective_timestamp` (inherited from outer). Constraint: max 1 of each type per group. Document that the outer group attribute and its first inner member sharing the same `id` is valid and expected DMDL convention.
6. **Relationship Fields** — `id`, `name`, `definition`, `description`, `source_entity_id`, `target_entity_id` (with direction convention: source = entity holding FK)
7. **Naming Conventions** — UPPERCASE_WITH_UNDERSCORES for all ids/names
8. **Validation Rules** — complete list of rules the skill should check when `daana-cli` is not available

Keep it concise and structured for quick lookup — this is a reference, not a tutorial. Use tables and bullet points, not prose.

- [ ] **Step 3: Verify model-schema.md covers all fields from the JSON schema**

Read the written file and cross-reference against `/tmp/model-schema.json` to ensure no fields are missing.

- [ ] **Step 4: Commit**

```bash
git add skills/daana/references/model-schema.md
git commit -m "feat: add DMDL model schema reference for /daana skill"
```

---

### Task 2: Create model-examples.md

**Files:**
- Create: `skills/daana/references/model-examples.md`
- Reference: daana-cli test flows (e.g., `test/test-flows/flow-20-honeymoon/step-00-install/model.yaml`, `test/test-flows/flow-48-bigquery-full-model/step-00-base/model.yaml`)

This file provides complete, annotated YAML examples the skill uses as templates when generating output.

- [ ] **Step 1: Fetch example models from daana-cli**

```bash
# Simple model (2 entities, no relationships)
gh api repos/daana-code/daana-cli/contents/test/test-flows/flow-20-honeymoon/step-00-install/model.yaml --jq '.content' | base64 -d > /tmp/example-simple.yaml

# Full model (4 entities with relationships)
gh api repos/daana-code/daana-cli/contents/test/test-flows/flow-48-bigquery-full-model/step-00-base/model.yaml --jq '.content' | base64 -d > /tmp/example-full.yaml

# Dual relationships model
gh api repos/daana-code/daana-cli/contents/test/test-flows/flow-30-dual-relationships/step-00-setup/model.yaml --jq '.content' | base64 -d > /tmp/example-relationships.yaml
```

**Fallback:** If `gh api` fails, use the YAML examples embedded in the spec document and the model documentation page content (already captured during brainstorming).

- [ ] **Step 2: Write model-examples.md**

Create `skills/daana/references/model-examples.md` with these sections:

1. **Minimal Model** — 1 entity (CUSTOMER), 3 attributes, no relationships. Annotate each line explaining why fields are set the way they are.
2. **Complete Model** — 3-4 entities (CUSTOMER, ORDER, PRODUCT, ORDER_LINE) with relationships. Show the full file structure with all sections.
3. **Attribute Type Examples** — one example of each type (STRING, NUMBER, UNIT, START_TIMESTAMP, END_TIMESTAMP) in context, with a brief note on when to use each.
4. **Grouped Attribute Example** — amount + currency group showing the nested YAML structure, with annotations explaining the outer/inner id sharing convention and the constraint rules.
5. **Relationship Examples** — simple relationship, plus an example showing correct source/target direction. Annotate which entity holds the FK and why.

Each example should be a valid, copy-pasteable YAML block. Annotations go in comments above the relevant lines or in prose between examples — not inline where they'd break the YAML.

- [ ] **Step 3: Verify all examples are valid YAML**

Read the file and check that each YAML block is syntactically valid and follows the schema from `model-schema.md`.

- [ ] **Step 4: Commit**

```bash
git add skills/daana/references/model-examples.md
git commit -m "feat: add DMDL model examples reference for /daana skill"
```

---

## Chunk 2: SKILL.md

The main skill file that drives the interview. This is the core deliverable.

### Task 3: Create SKILL.md

**Files:**
- Create: `skills/daana/SKILL.md`
- Reference: `skills/daana/references/model-schema.md`, `skills/daana/references/model-examples.md`
- Reference: Spec at `docs/superpowers/specs/2026-03-14-daana-modeler-skill-design.md`

This is the largest task. The file contains the skill frontmatter, persona, and complete interview flow instructions. Keep it under 500 lines (per Claude Code best practices — detailed schema/examples are in the reference files).

- [ ] **Step 1: Write the frontmatter**

```yaml
---
name: daana
description: Interview-driven DMDL model builder. Guides you through defining business entities, attributes, and relationships, then writes a valid model.yaml.
disable-model-invocation: true
---
```

- [ ] **Step 2: Write the persona section**

After the frontmatter, write the skill's identity and behavior guidelines:

- Identity: friendly, methodical daana modeling expert
- Scope: model.yaml only — never touch mapping, workflow, or connections
- Adaptive: detect user's knowledge level and adjust tone/depth
- Key behaviors: one question at a time, opinionated but deferential, teaches as it goes, incremental building, proactive relationship suggestions
- Do NOT warn about SQL reserved words as entity names (e.g., ORDER, GROUP) — DMDL handles this at the mapping/deployment layer
- Reference files: point to `references/model-schema.md` for schema rules and `references/model-examples.md` for YAML templates. Instruct to read these using the Read tool at the start of the skill, using `${CLAUDE_SKILL_DIR}` for path resolution.

- [ ] **Step 3: Write Phase 1 — Detection & Setup**

Instructions for:
1. Use Glob to check for `model.yaml` in the project root
2. If found and valid: read it, summarize entities/attributes/relationships, ask "add more or start fresh?"
3. If found but malformed: warn user, offer to fix or start fresh
4. If not found: ask "do you know your entities, or should we explore?"
5. For new models: ask about name/purpose, infer model metadata, confirm, then proceed to entity interview
6. Note: v1 supports adding only, not deleting/renaming

- [ ] **Step 4: Write Phase 2 — Entity Interview**

Instructions for the per-entity loop:
1. Check for duplicate entity IDs (offer to add attributes to existing entity)
2. Check for duplicate attribute IDs within the same entity (attribute IDs are entity-scoped, not global). Exclude the group attribute id-sharing pattern from duplicate detection.
3. Ask user to describe the entity in natural language
4. If 10+ attributes listed, suggest batching
5. Inference rules table from spec section "Persona & Behavior > Inference Rules" — maps user descriptions to DMDL type and effective_timestamp values
6. Present summary table for confirmation (show type and "track changes" for each attribute; show groups as groups)
7. Accept corrections
8. Re-read `model.yaml` before editing
9. Write entity using Edit tool (or Write for first entity)
10. Validate with `daana-cli check model <path>` if available (detect via `daana-cli --version`), otherwise apply validation rules from `model-schema.md`

- [ ] **Step 5: Write Phase 3 — Relationship-Driven Expansion**

Instructions for:
1. After each entity, ask "does this entity relate to others?" with suggestive examples
2. Capture relationship semantics
3. Infer relationship fields (id as verb phrase, source/target direction per convention, ask when ambiguous)
4. Check if related entity already exists — if yes, skip interview, just create relationship (circular guard)
5. If entity is new — immediately run full Phase 2 interview
6. Write entity (if new) and relationship to `model.yaml`
7. Continue expanding until user says done

- [ ] **Step 6: Write Phase 4 — Review & Wrap-up**

Instructions for:
1. Present summary of all entities and relationships
2. Flag entities with zero relationships ("is that intentional?")
3. Ask for missing/incorrect relationships
4. Run final `daana-cli check model` validation if available
5. Suggest next steps

- [ ] **Step 7: Write YAML generation rules**

Instructions for how the skill writes YAML:
1. `id` and `name` are always set to the same UPPERCASE_WITH_UNDERSCORES value. Never ask the user to distinguish them.
2. `definition` is always one concise sentence; `description` gets remaining detail and business context.
3. YAML formatting: 2-space indent, quoted strings for id/name/definition/description/type/source_entity_id/target_entity_id, unquoted booleans, field order (id, name, definition, description, then type-specific)
4. Initial creation: Write tool for first entity (include model metadata + entities section)
5. Incremental updates: re-read then Edit tool to append entities and relationships
6. File path: default `model.yaml`, ask for different path only if none found
7. Reference `model-examples.md` for YAML structure templates

- [ ] **Step 8: Review SKILL.md length and trim if needed**

Read the file and verify it's under 500 lines. If over, move detailed content to a supporting file or trim prose. The key behaviors, inference rules table, and flow instructions must stay — trim examples and explanations first (those are in the reference files).

- [ ] **Step 9: Commit**

```bash
git add skills/daana/SKILL.md
git commit -m "feat: add /daana skill for interactive DMDL model building"
```

---

## Chunk 3: Project Setup & Testing

### Task 4: Create CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

Project-level instructions for contributors working on this repo.

- [ ] **Step 1: Write CLAUDE.md**

Include:
- Project description: "daana-modeler is a Claude Code skill (`/daana`) that interviews users to build DMDL model.yaml files for the Daana data platform."
- Repo structure: point to `skills/daana/` as the main deliverable, `docs/superpowers/specs/` for design specs, `docs/superpowers/plans/` for implementation plans
- How to test: install as a plugin or copy `skills/daana/` into a daana project's `.claude/skills/`, then invoke `/daana`
- Link to daana-cli docs at `docs.daana.dev`
- Link to DMDL spec at `docs.daana.dev/dmdl`

Keep it short — this is a small project.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add CLAUDE.md with project overview and testing instructions"
```

---

### Task 5: Structural Validation

**Files:**
- Read: all files in `skills/daana/`

Verify all cross-references and structural integrity before manual testing.

- [ ] **Step 1: Verify SKILL.md frontmatter is valid YAML**

Read `skills/daana/SKILL.md` and confirm the frontmatter between `---` markers parses as valid YAML with the expected fields (`name`, `description`, `disable-model-invocation`).

- [ ] **Step 2: Verify reference file cross-references**

Read `SKILL.md` and confirm all file references to `references/model-schema.md` and `references/model-examples.md` match the actual file paths. Check that `${CLAUDE_SKILL_DIR}` is used for path resolution.

- [ ] **Step 3: Verify YAML examples in model-examples.md parse correctly**

Read `skills/daana/references/model-examples.md` and verify each YAML code block is syntactically valid. Check that examples follow the formatting rules from the spec (2-space indent, quoted strings, field ordering).

- [ ] **Step 4: Verify model-schema.md covers all spec requirements**

Cross-reference `model-schema.md` against the spec's "Key DMDL Concepts" and "Validation" sections. Confirm all fields, constraints, and validation rules are documented.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during structural validation"
```

(Only if changes were made.)

---

### Task 6: Manual Testing (requires human tester)

This task cannot be automated — it requires invoking `/daana` interactively in a Claude Code session.

- [ ] **Step 1: Set up test project**

```bash
mkdir -p /tmp/daana-test-project/.claude/skills
cp -r skills/daana /tmp/daana-test-project/.claude/skills/daana
cd /tmp/daana-test-project
```

- [ ] **Step 2: Test — new model from scratch**

Invoke `/daana` in the test project. Walk through:
1. Verify it detects no existing `model.yaml`
2. Verify it asks about the user's knowledge level
3. Describe a simple entity ("Customers have a name, email, and signup date")
4. Verify the summary table is presented correctly
5. Confirm and verify `model.yaml` is written correctly
6. Verify it asks about related entities

- [ ] **Step 3: Test — relationship expansion**

Continue the session:
1. Say "customers place orders"
2. Verify it creates the relationship and interviews for ORDER
3. Describe ORDER attributes
4. Verify both ORDER entity and IS_PLACED_BY relationship are written
5. Say "no more related entities"
6. Verify it returns to ask about other entities or proceeds to review

- [ ] **Step 4: Test — existing model**

Re-invoke `/daana` in the same project:
1. Verify it detects the existing `model.yaml`
2. Verify it summarizes what's there
3. Verify it offers to add or start fresh

- [ ] **Step 5: Fix any issues found during testing**

If the skill doesn't behave as expected, update `SKILL.md` or reference docs. Re-test after fixes.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "fix: address issues found during manual testing"
```

(Only if changes were made during testing.)
