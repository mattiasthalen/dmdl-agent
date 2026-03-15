# Plugin Restructure Design

Restructure daana-modeler from a loose collection of skills into a proper Claude Code plugin. Resolves GitHub issues #4, #5, and #6.

## Context

daana-modeler currently has skills under `skills/` at the repo root but lacks a `.claude-plugin/plugin.json` manifest, so Claude Code cannot discover it as a plugin. The skills are named `daana-model`, `daana-mapping`, and `daana-query`, with an orchestrator at `skills/daana/` that routes between them. All three skills and the orchestrator have `disable-model-invocation: true`, preventing Claude from invoking them via the Skill tool — which breaks inter-skill handovers.

## Goals

1. Add a plugin manifest so the repo is a proper Claude Code plugin.
2. Rename skills to produce clean slash commands: `/daana:model`, `/daana:map`, `/daana:query`.
3. Remove the orchestrator and replace it with handover chains between skills.
4. Remove `disable-model-invocation: true` so skills can invoke each other.
5. Move shared references to the plugin root level.

## New Directory Structure

```
daana-modeler/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── model/
│   │   └── SKILL.md
│   ├── map/
│   │   └── SKILL.md
│   └── query/
│       └── SKILL.md
├── references/
│   ├── model-schema.md
│   ├── model-examples.md
│   ├── mapping-schema.md
│   ├── mapping-examples.md
│   └── source-schema-formats.md
├── .claude/
│   └── settings.json
├── .devcontainer/
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── CLAUDE.md
├── README.md
└── LICENSE
```

### What's unchanged

- `.claude/settings.json` — project-level Claude Code settings (superpowers plugin config).
- `.devcontainer/` — dev container configuration.
- `docs/` — design specs and implementation plans.

### What's removed

- `skills/daana/` — the orchestrator skill. Its routing logic is replaced by handover sections in each skill. Its source schema parsing guidance moves into `model` and `map` skills directly.
- `skills/daana/references/` — moved to `references/` at the plugin root.

### What's renamed

| Old path | New path |
|---|---|
| `skills/daana-model/` | `skills/model/` |
| `skills/daana-mapping/` | `skills/map/` |
| `skills/daana-query/` | `skills/query/` |

## Plugin Manifest

`.claude-plugin/plugin.json`:

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

No custom component paths are needed. The `skills/` directory is the default discovery location and will be auto-discovered. The `references/` directory is not a plugin component — skills read its files directly via paths relative to the plugin root (e.g., `references/model-schema.md`). When installed via `claude plugin add`, the entire plugin directory is cached locally and relative paths resolve from the plugin root.

## Skill Changes

### Frontmatter changes (all skills)

- Remove `disable-model-invocation: true` from all three skills (`model`, `map`, and `query`). This fixes issues #5 and #6, and ensures all skills can be invoked via the Skill tool for handovers. The orchestrator's flag goes away with its deletion.

### Inline slash command references (all skills)

- Update all inline references to old skill names within SKILL.md files. For example, `query/SKILL.md` currently references `/daana-model` and `/daana-mapping` — these must become `/daana:model` and `/daana:map`. Scan all three skill files for stale `/daana-*` references and update them.

### Reference path updates (model and map skills)

- Update all references from `skills/daana/references/` to `references/` (relative to plugin root).

### Source schema parsing (model and map skills)

The orchestrator currently asks "Do you have a source schema to work from?" in its Step 1 before routing, and pre-parses the schema for downstream skills. Both `model` and `map` skills have a "Source Schema Context" section that says "If the orchestrator (`/daana`) parsed a source schema before invoking this skill..." — this framing becomes invalid.

Replace the "Source Schema Context" section in both skills to make each self-sufficient:

- **`model/SKILL.md`** — In Phase 1 (Detection & Setup), after detecting existing model state, ask: "Do you have a source schema file (Swagger/OpenAPI, OData, or dlt) to work from?" If yes, read `references/source-schema-formats.md`, detect the format, parse it, and use the extracted tables/columns/types as hints during the entity interview.
- **`map/SKILL.md`** — In Phase 1 (Entity Selection), after listing unmapped entities, ask: "Do you have a source schema file to work from?" If yes, read `references/source-schema-formats.md`, parse it, and use the extracted table/column information to accelerate column-to-attribute matching.

### Handover sections

Add a wrap-up/handover section at the end of each skill:

**`model/SKILL.md`**: After writing `model.yaml`, offer to hand over to `/daana:map` to create source mappings.

**`map/SKILL.md`**: After writing a mapping file, offer to continue with another unmapped entity or hand over to `/daana:query` to explore the data.

**`query/SKILL.md`**: If unmapped entities are detected, suggest `/daana:map` to set up mappings.

Handovers are user-confirmed offers, not automatic redirects. This is a behavioral change from the orchestrator's auto-chain logic (which automatically returned to its routing loop after each sub-skill completed). The new approach gives users explicit control over the next step.

### Skill instructions

The core interview flows, validation rules, and behavioral instructions within each skill remain unchanged. Only frontmatter, reference paths, and the new handover section are modified.

## CLAUDE.md Updates

- Remove mention of the `/daana` orchestrator entrypoint.
- Update skill directory paths to `skills/model/`, `skills/map/`, `skills/query/`.
- Update shared references path to `references/`.
- Update slash command names to `/daana:model`, `/daana:map`, `/daana:query`.

## README.md Updates

- Change subtitle from "A Claude Code skill" to "A Claude Code plugin".
- Update usage section: replace `/daana` with `/daana:model`, `/daana:map`, `/daana:query`.
- Add brief description of each skill's purpose.
- Remove the "As a local skill: Copy the `skills/daana/` directory..." fallback instruction — it no longer applies with the new structure.
- Installation command remains `claude plugin add` (already correct).

## Issues Resolved

| Issue | Title | Resolution |
|---|---|---|
| #4 | Restructure project as a Claude Code plugin | Plugin manifest added, skills renamed, orchestrator removed |
| #5 | Skill daana-mapping cannot be used with Skill tool due to disable-model-invocation | `disable-model-invocation: true` removed from `map/SKILL.md` |
| #6 | Skill daana-model cannot be used with Skill tool due to disable-model-invocation | `disable-model-invocation: true` removed from `model/SKILL.md` |
