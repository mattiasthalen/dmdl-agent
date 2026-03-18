# Skill Modularization — Model & Map

**Date:** 2026-03-18
**Status:** Approved

## Problem

The model and map skills have two issues the query skill already solved:

1. **Permission prompts** — reading `references/` files at startup triggers approval prompts before anything useful happens
2. **No AskUserQuestion enforcement** — questions are printed as text instead of using the tool, which makes them easy to skip or ignore

## Decision

**Approach A: Modularize + AskUserQuestion in one pass.** Apply the same pattern as the query skill: copy references as supporting files in each skill directory, use `${CLAUDE_SKILL_DIR}` for on-demand reads, and convert every user-facing question to an explicit `AskUserQuestion` tool call.

### Alternatives considered

- **Two separate passes:** Smaller diffs but more churn — two rounds of changes to the same files.
- **Shared supporting files directory:** `skills/shared/` with `${CLAUDE_SKILL_DIR}/../shared/` paths. Fragile relative path, untested pattern, diverges from established query skill approach.
- **Symlinks:** Single source of truth, but unknown whether Claude Code resolves symlinks in `${CLAUDE_SKILL_DIR}` context.

## Structure

### Model skill

```
skills/model/
  SKILL.md                  (workflow only, ${CLAUDE_SKILL_DIR} reads)
  model-schema.md           (copied from references/model-schema.md)
  model-examples.md         (copied from references/model-examples.md)
  source-schema-formats.md  (copied from references/source-schema-formats.md)
```

### Map skill

```
skills/map/
  SKILL.md                  (workflow only, ${CLAUDE_SKILL_DIR} reads)
  mapping-schema.md         (copied from references/mapping-schema.md)
  mapping-examples.md       (copied from references/mapping-examples.md)
  source-schema-formats.md  (copied from references/source-schema-formats.md)
```

## SKILL.md changes

Both skills get the same two categories of changes:

### 1. Reference modularization

- Remove the "Initialization" section that reads all references upfront
- Replace `references/` paths with `${CLAUDE_SKILL_DIR}/` reads at the right phase boundaries
- Read supporting files on demand, not all at startup

### 2. AskUserQuestion enforcement

Convert **every** user-facing question to an explicit `AskUserQuestion` tool call with:
- `(do NOT print the question as text)` instruction
- Explicit options where applicable
- `STOP and wait` instruction after each call

### Model skill AskUserQuestion points

| # | Phase | Question | Options |
|---|-------|----------|---------|
| 1 | Phase 1 | Existing model found — add more or start fresh? | "Add more entities" / "Start fresh" |
| 2 | Phase 1 | Malformed model — fix or start fresh? | "Try to fix it" / "Start fresh" |
| 3 | Phase 1 | No model — know entities or explore? | "I know my entities" / "Let's explore together" |
| 4 | Phase 1 | Source schema file? | "I have a file" / "Skip" |
| 5 | Phase 1 | Model metadata confirmation | "Looks good" / "Change something" |
| 6 | Phase 2 | Entity already exists — add attributes or different? | "Add attributes to ENTITY" / "Different entity" |
| 7 | Phase 2 | Attribute summary confirmation | "Looks good" / "I have corrections" |
| 8 | Phase 2 | Accept corrections | Free-text (no predefined options) |
| 9 | Phase 3 | Does entity relate to others? | Free-text with examples |
| 10 | Phase 3 | Relationship direction | "ENTITY_A holds the reference" / "ENTITY_B holds the reference" |
| 11 | Phase 4 | Orphan entity — intentional? | "Yes, intentional" / "Connect it to..." |
| 12 | Phase 4 | Any relationships missing? | "No, looks good" / Free-text corrections |
| 13 | Phase 4 | Handover to /daana-map | "Yes, create mappings" / "No, I'm done" |

### Map skill AskUserQuestion points

| # | Phase | Question | Options |
|---|-------|----------|---------|
| 1 | Phase 1 | Source schema file? | "I have a file" / "Skip" |
| 2 | Phase 1 | Entity selection | One option per unmapped entity |
| 3 | Phase 1 | Entity already mapped — overwrite? | "Overwrite" / "Pick different entity" |
| 4 | Phase 2 | Connection name | Free-text (suggest previous if available) |
| 5 | Phase 2 | Table name | Free-text |
| 6 | Phase 2 | Primary key column(s) | Free-text |
| 7 | Phase 2 | Ingestion strategy confirmation | "FULL" / "INCREMENTAL" / "FULL_LOG" / "TRANSACTIONAL" |
| 8 | Phase 2 | Effective timestamp expression | Free-text |
| 9 | Phase 2 | Source columns (no schema context) | Free-text |
| 10 | Phase 2 | Smart matching confirmation | "Looks right" / "I have corrections" |
| 11 | Phase 2 | Each unmatched attribute expression | Free-text / "Skip this attribute" |
| 12 | Phase 2 | Optional overrides | "No overrides needed" / Free-text |
| 13 | Phase 2 | Table-level where clause | "No filter" / Free-text expression |
| 14 | Phase 2 | Additional tables? | "Yes, another table" / "No, that's all" |
| 15 | Phase 3 | Relationship target expression | Free-text |
| 16 | Phase 4 | Summary confirmation before writing | "Looks good, write it" / "I have corrections" |
| 17 | Phase 4 | Multiple identifiers warning | "Yes, allow multiple identifiers" / "No, go back" |
| 18 | Phase 4 | Next entity or handover | One option per remaining entity / "Done, hand over to /daana-query" / "Done" |

## What stays unchanged

- `references/` directory — kept as-is (other tools or future skills may use it)
- Query skill — already modularized
- All YAML generation rules, validation logic, edge cases — content stays the same
- Adaptive behavior sections
- Scope sections

## Version

Bump plugin version after both skills are updated.
