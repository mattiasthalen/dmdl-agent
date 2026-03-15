# Plugin Restructure Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure daana-modeler as a proper Claude Code plugin with clean `/daana:model`, `/daana:map`, `/daana:query` namespacing. Resolves issues #4, #5, #6.

**Architecture:** Create `.claude-plugin/plugin.json` manifest, rename skill directories, remove orchestrator, add handover chains between skills, move shared references to plugin root.

**Tech Stack:** Claude Code plugin system, Markdown (SKILL.md files), JSON (plugin.json)

**Pre-step:** All work is in the worktree at `/tmp/plugin-restructure` on branch `feat/plugin-restructure`.

---

## Chunk 1: Plugin manifest and directory restructure

### Task 1: Create plugin manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create `.claude-plugin/` directory and manifest**

```json
{
  "name": "daana",
  "description": "Interview-driven DMDL model and mapping builder for the Daana data platform",
  "version": "1.0.0",
  "author": {
    "name": "Mattias Thalén"
  },
  "repository": "https://github.com/mattiasthalen/daana-modeler",
  "license": "MIT",
  "keywords": ["daana", "dmdl", "data-modeling", "data-warehouse"]
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add Claude Code plugin manifest"
```

### Task 2: Move references to plugin root

**Files:**
- Move: `skills/daana/references/` → `references/`

- [ ] **Step 1: Move the references directory**

```bash
mv skills/daana/references/ references/
```

- [ ] **Step 2: Verify all 5 files moved**

```bash
ls references/
```

Expected: `mapping-examples.md`, `mapping-schema.md`, `model-examples.md`, `model-schema.md`, `source-schema-formats.md`

- [ ] **Step 3: Commit**

```bash
git add references/ skills/daana/references/
git commit -m "refactor: move shared references to plugin root"
```

### Task 3: Rename skill directories

**Files:**
- Move: `skills/daana-model/` → `skills/model/`
- Move: `skills/daana-mapping/` → `skills/map/`
- Move: `skills/daana-query/` → `skills/query/`

- [ ] **Step 1: Rename all three directories**

```bash
mv skills/daana-model/ skills/model/
mv skills/daana-mapping/ skills/map/
mv skills/daana-query/ skills/query/
```

- [ ] **Step 2: Verify structure**

```bash
ls skills/*/SKILL.md
```

Expected: `skills/map/SKILL.md`, `skills/model/SKILL.md`, `skills/query/SKILL.md`

- [ ] **Step 3: Commit**

```bash
git add skills/
git commit -m "refactor: rename skill directories for plugin namespacing"
```

### Task 4: Delete orchestrator

**Files:**
- Delete: `skills/daana/` (should be empty after references moved)

- [ ] **Step 1: Verify only SKILL.md remains**

```bash
ls skills/daana/
```

Expected: `SKILL.md` only (references/ already moved in Task 2)

- [ ] **Step 2: Delete the orchestrator directory**

```bash
rm -rf skills/daana/
```

- [ ] **Step 3: Commit**

```bash
git add skills/daana/
git commit -m "refactor: remove orchestrator skill, replaced by handover chains"
```

---

## Chunk 2: Update model skill

### Task 5: Update `skills/model/SKILL.md`

**Files:**
- Modify: `skills/model/SKILL.md`

**Spec references:**
- Remove `disable-model-invocation: true` (spec: Frontmatter changes)
- Update reference paths (spec: Reference path updates)
- Replace Source Schema Context section (spec: Source schema parsing)
- Add handover section (spec: Handover sections)

**Note:** Line references below are against the original unmodified file. Since earlier steps change the file, match edits by content (old_string), not line numbers.

- [ ] **Step 1: Remove `disable-model-invocation: true` from frontmatter**

Replace lines 1-5:
```yaml
---
name: daana-model
description: Interview-driven DMDL model.yaml builder. Walks users through defining entities, attributes, and relationships.
disable-model-invocation: true
---
```

With:
```yaml
---
name: model
description: Interview-driven DMDL model.yaml builder. Walks users through defining entities, attributes, and relationships.
---
```

- [ ] **Step 2: Update reference paths in Initialization section**

Replace lines 19-20:
```markdown
1. `skills/daana/references/model-schema.md` — schema rules and validation constraints
2. `skills/daana/references/model-examples.md` — annotated YAML templates and patterns
```

With:
```markdown
1. `references/model-schema.md` — schema rules and validation constraints
2. `references/model-examples.md` — annotated YAML templates and patterns
```

- [ ] **Step 3: Replace Source Schema Context section**

Replace lines 42-50 (the entire "Source Schema Context" section):
```markdown
## Source Schema Context

If the orchestrator (`/daana`) parsed a source schema before invoking this skill, the parsed tables and columns will be available in conversation context. When source schema context is present:

- In Phase 1 (Detection & Setup), when asking about entities: suggest entities based on tables found in the source schema.
- In Phase 2 (Entity Interview), when gathering attributes: suggest attributes based on columns found in the matching source table, using inferred DMDL types as defaults.
- Still confirm everything with the user — source schema suggestions are starting points, not final answers.

For source schema format details, see `skills/daana/references/source-schema-formats.md`.
```

With:
```markdown
## Source Schema Context

In Phase 1 (Detection & Setup), after detecting existing model state, ask: *"Do you have a source schema file to work from? (Swagger/OpenAPI JSON, OData metadata XML, or dlt schema) You can paste it, give me a file path, or skip this."*

If the user provides a schema:
1. Read `references/source-schema-formats.md` for parsing instructions.
2. Auto-detect the format from the content structure.
3. Parse and summarize the extracted tables, columns, and inferred DMDL types.
4. Present the summary to the user for confirmation.

When source schema context is available:
- In Phase 1, when asking about entities: suggest entities based on tables found in the source schema.
- In Phase 2 (Entity Interview), when gathering attributes: suggest attributes based on columns found in the matching source table, using inferred DMDL types as defaults.
- Still confirm everything with the user — source schema suggestions are starting points, not final answers.
```

- [ ] **Step 4: Update reference path in Phase 2 Step 8 (validation)**

Replace line 156:
```markdown
3. **Without daana-cli:** Apply validation rules from `skills/daana/references/model-schema.md` (required fields, naming format, type validity, group constraints, uniqueness, etc.).
```

With:
```markdown
3. **Without daana-cli:** Apply validation rules from `references/model-schema.md` (required fields, naming format, type validity, group constraints, uniqueness, etc.).
```

- [ ] **Step 5: Update reference path in Phase 4 Step 4 (final validation)**

Replace line 199:
```markdown
   - Otherwise apply built-in validation rules from `skills/daana/references/model-schema.md`.
```

With:
```markdown
   - Otherwise apply built-in validation rules from `references/model-schema.md`.
```

- [ ] **Step 6: Update reference path in Reference Templates section**

Replace line 239:
```markdown
Consult `skills/daana/references/model-examples.md` for YAML structure templates when generating output — minimal model, complete model with relationships, grouped attributes, and relationship direction patterns.
```

With:
```markdown
Consult `references/model-examples.md` for YAML structure templates when generating output — minimal model, complete model with relationships, grouped attributes, and relationship direction patterns.
```

- [ ] **Step 7: Update reference path in Initial Creation section**

Replace line 227:
```markdown
Refer to `skills/daana/references/model-examples.md` for the exact YAML structure.
```

With:
```markdown
Refer to `references/model-examples.md` for the exact YAML structure.
```

- [ ] **Step 8: Add handover section at end of Phase 4**

After the "Suggest next steps" item in Phase 4 (line 202), replace:
```markdown
5. **Suggest next steps:**
   *"Your model is ready!"*
```

With:
```markdown
5. **Suggest next steps and offer handover:**
   *"Your model is ready! Want to create source mappings for your entities? I can hand you over to `/daana:map`."*
   If the user accepts, invoke `/daana:map` using the Skill tool.
```

- [ ] **Step 9: Verify no remaining old paths**

Search `skills/model/SKILL.md` for any remaining `skills/daana/references/` or `/daana-` references.

- [ ] **Step 10: Commit**

```bash
git add skills/model/SKILL.md
git commit -m "refactor: update model skill for plugin structure

Remove disable-model-invocation, update reference paths,
add self-sufficient source schema parsing, add handover to /daana:map."
```

---

## Chunk 3: Update map skill

### Task 6: Update `skills/map/SKILL.md`

**Files:**
- Modify: `skills/map/SKILL.md`

**Spec references:**
- Remove `disable-model-invocation: true` (spec: Frontmatter changes)
- Update reference paths (spec: Reference path updates)
- Replace Source Schema Context section (spec: Source schema parsing)
- Add handover section (spec: Handover sections)

**Note:** Line references below are against the original unmodified file. Since earlier steps change the file, match edits by content (old_string), not line numbers.

- [ ] **Step 1: Remove `disable-model-invocation: true` from frontmatter**

Replace lines 1-5:
```yaml
---
name: daana-mapping
description: Interview-driven DMDL mapping file builder. Maps source tables to model entities with transformation expressions.
disable-model-invocation: true
---
```

With:
```yaml
---
name: map
description: Interview-driven DMDL mapping file builder. Maps source tables to model entities with transformation expressions.
---
```

- [ ] **Step 2: Update reference paths in Initialization section**

Replace lines 19-20:
```markdown
1. `skills/daana/references/mapping-schema.md` — schema rules and validation constraints
2. `skills/daana/references/mapping-examples.md` — annotated YAML templates and patterns
```

With:
```markdown
1. `references/mapping-schema.md` — schema rules and validation constraints
2. `references/mapping-examples.md` — annotated YAML templates and patterns
```

- [ ] **Step 3: Replace Source Schema Context section**

Replace lines 41-50 (the entire "Source Schema Context" section):
```markdown
## Source Schema Context

If the orchestrator (`/daana`) parsed a source schema before invoking this skill, the parsed tables and columns will be available in conversation context. When source schema context is present:

- In Phase 2 step 6: auto-extract columns from the matching source table instead of asking the user to list them.
- In Phase 2 step 7: use extracted columns for smart matching against model attributes.
- If the user references a table not found in the parsed schema, warn and fall back to manual column entry.
- Still confirm everything with the user — source schema suggestions are starting points, not final answers.

For source schema format details, see `skills/daana/references/source-schema-formats.md`.
```

With:
```markdown
## Source Schema Context

In Phase 1 (Entity Selection), after listing unmapped entities, ask: *"Do you have a source schema file to work from? (Swagger/OpenAPI JSON, OData metadata XML, or dlt schema) You can paste it, give me a file path, or skip this."*

If the user provides a schema:
1. Read `references/source-schema-formats.md` for parsing instructions.
2. Auto-detect the format from the content structure.
3. Parse and summarize the extracted tables, columns, and inferred DMDL types.
4. Present the summary to the user for confirmation.

When source schema context is available:
- In Phase 2 step 6: auto-extract columns from the matching source table instead of asking the user to list them.
- In Phase 2 step 7: use extracted columns for smart matching against model attributes.
- If the user references a table not found in the parsed schema, warn and fall back to manual column entry.
- Still confirm everything with the user — source schema suggestions are starting points, not final answers.
```

- [ ] **Step 4: Update reference path in Phase 4 Step 5 (validation)**

Replace line 222:
```markdown
3. **Without daana-cli:** Apply validation rules from `skills/daana/references/mapping-schema.md`:
```

With:
```markdown
3. **Without daana-cli:** Apply validation rules from `references/mapping-schema.md`:
```

- [ ] **Step 5: Update reference path in Reference Templates section**

Replace line 270:
```markdown
Consult `skills/daana/references/mapping-examples.md` for YAML structure templates when generating output — minimal mapping, complete mapping with overrides, multi-table mapping, and relationship patterns.
```

With:
```markdown
Consult `references/mapping-examples.md` for YAML structure templates when generating output — minimal mapping, complete mapping with overrides, multi-table mapping, and relationship patterns.
```

- [ ] **Step 6: Add handover section after Phase 4 Step 6**

Replace the existing "Next Entity" step at end of Phase 4:
```markdown
### Step 6: Next Entity

*"Mapping for ORDER is saved and validated. Want to map another entity? (PRODUCT and SUPPLIER still need mappings.)"*

If yes, loop back to Phase 1.
```

With:
```markdown
### Step 6: Next Entity or Handover

*"Mapping for ORDER is saved and validated. Want to map another entity? (PRODUCT and SUPPLIER still need mappings.)"*

If yes, loop back to Phase 1.

If all entities are mapped (or the user declines), offer handover:
*"All done with mappings! Want to explore your data with live queries? I can hand you over to `/daana:query`."*
If the user accepts, invoke `/daana:query` using the Skill tool.
```

- [ ] **Step 7: Verify no remaining old paths**

Search `skills/map/SKILL.md` for any remaining `skills/daana/references/` or `/daana-` references.

- [ ] **Step 8: Commit**

```bash
git add skills/map/SKILL.md
git commit -m "refactor: update map skill for plugin structure

Remove disable-model-invocation, update reference paths,
add self-sufficient source schema parsing, add handover to /daana:query."
```

---

## Chunk 4: Update query skill

### Task 7: Update `skills/query/SKILL.md`

**Files:**
- Modify: `skills/query/SKILL.md`

**Spec references:**
- Remove `disable-model-invocation: true` (spec: Frontmatter changes)
- Update inline slash command references (spec: Inline slash command references)
- Add handover section (spec: Handover sections)

- [ ] **Step 1: Remove `disable-model-invocation: true` from frontmatter**

Replace lines 1-5:
```yaml
---
name: daana-query
description: Data agent that answers natural language questions about Focal-based Daana data warehouses via live SQL queries.
disable-model-invocation: true
---
```

With:
```yaml
---
name: query
description: Data agent that answers natural language questions about Focal-based Daana data warehouses via live SQL queries.
---
```

- [ ] **Step 2: Update inline slash command references**

Replace line 15:
```markdown
- Never create or edit DMDL model or mapping files — that is the job of `/daana-model` and `/daana-mapping`.
```

With:
```markdown
- Never create or edit DMDL model or mapping files — that is the job of `/daana:model` and `/daana:map`.
```

- [ ] **Step 3: Add handover suggestion at end of file**

After the last line (line 203, end of "Focal Framework Context"), append:

```markdown

## Handover

If during the conversation you detect unmapped entities (e.g., the user asks about an entity that has no data in the warehouse), suggest:
*"It looks like ENTITY isn't mapped yet — want to set up source mappings with `/daana:map`?"*
If the user accepts, invoke `/daana:map` using the Skill tool.
```

- [ ] **Step 4: Verify no remaining old references**

Search `skills/query/SKILL.md` for any remaining `/daana-` references.

- [ ] **Step 5: Commit**

```bash
git add skills/query/SKILL.md
git commit -m "refactor: update query skill for plugin structure

Remove disable-model-invocation, update slash command references,
add handover suggestion to /daana:map."
```

---

## Chunk 5: Update documentation

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite CLAUDE.md**

Replace entire contents with:

```markdown
# daana-modeler

daana-modeler is a Claude Code plugin for the Daana data platform. It provides three skills for building and querying DMDL data models.

## Repository Structure

- **`.claude-plugin/`** — Plugin manifest
  - `plugin.json` — Plugin metadata (name: `daana`)
- **`skills/model/`** — Model interview skill (`/daana:model`)
  - `SKILL.md` — Builds model.yaml via interactive interview
- **`skills/map/`** — Mapping interview skill (`/daana:map`)
  - `SKILL.md` — Builds mapping files via interactive interview
- **`skills/query/`** — Data query skill (`/daana:query`)
  - `SKILL.md` — Answers natural language questions about data via live SQL
- **`references/`** — Shared DMDL schema, examples, and source schema formats
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for plugin structure"
```

### Task 9: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README.md**

Replace entire contents with:

```markdown
# daana-modeler

A Claude Code plugin that interviews you to build DMDL model and mapping files, and query your data warehouse.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built_for-Claude_Code-6f42c1.svg)](https://docs.anthropic.com/en/docs/claude-code)

## What It Does

daana-modeler is a plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that provides three skills:

- **`/daana:model`** — Interactive interview to define business entities, attributes, and relationships, generating a valid DMDL `model.yaml` file.
- **`/daana:map`** — Interactive interview to map source tables to model entities, generating DMDL mapping files.
- **`/daana:query`** — Natural language data agent that answers questions about your Focal-based Daana data warehouse via live SQL queries.

Learn more about Daana and DMDL at [docs.daana.dev](https://docs.daana.dev).

## Installation

```bash
claude plugin add https://github.com/mattiasthalen/daana-modeler
```

## Usage

Run any of the skills as slash commands in Claude Code:

- `/daana:model` — Start building your data model
- `/daana:map` — Create source-to-model mappings
- `/daana:query` — Query your data warehouse

Each skill can hand you over to the next logical step when it completes.

## Documentation

- [Daana CLI](https://docs.daana.dev) — Daana CLI documentation
- [DMDL Specification](https://docs.daana.dev/dmdl) — DMDL language reference

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README.md for plugin structure"
```

---

## Chunk 6: Final verification

### Task 10: Verify complete structure

- [ ] **Step 1: Verify directory structure**

```bash
find . -not -path './.git/*' -not -path './.git' | sort
```

Expected structure should match the spec's directory tree: `.claude-plugin/plugin.json`, `skills/model/`, `skills/map/`, `skills/query/`, `references/`, no `skills/daana/` or `skills/daana-*/`.

- [ ] **Step 2: Verify no stale references remain**

Search all SKILL.md files for old paths:

```bash
grep -rn 'skills/daana' skills/ || echo "No stale path references found"
grep -rn '/daana-' skills/ || echo "No stale slash command references found"
grep -rn 'disable-model-invocation' skills/ || echo "No disable-model-invocation flags found"
```

All three should print the "not found" message.

- [ ] **Step 3: Verify plugin.json is valid JSON**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('Valid JSON')"
```

- [ ] **Step 4: Push branch**

```bash
git push -u origin feat/plugin-restructure
```
