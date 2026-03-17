# Plugin Scoping — Design

**Date:** 2026-03-17
**Status:** Approved

## Problem

The marketplace.json `source` field is set to `"./"`, which means the entire repo is distributed when users install the plugin. This includes development files (docs, .devcontainer, CLAUDE.md, README, LICENSE) that users don't need.

## Design

Move plugin-distributable files into a `plugin/` subdirectory. Update `marketplace.json` source to `"./plugin/"`.

### What moves into `plugin/`

- `.claude-plugin/plugin.json` → `plugin/.claude-plugin/plugin.json`
- `skills/` → `plugin/skills/`
- `references/` → `plugin/references/`

### What stays at repo root

- `.claude-plugin/marketplace.json` — marketplace system expects this at root
- `docs/` — development documentation
- `.devcontainer/` — dev environment
- `CLAUDE.md` — project instructions
- `README.md`, `LICENSE` — repo metadata

### Changes required

1. Create `plugin/` directory and `plugin/.claude-plugin/`
2. `git mv` plugin.json, skills/, references/ into plugin/
3. Update marketplace.json source from `"./"` to `"./plugin/"`
4. Update CLAUDE.md repo structure section
5. Verify cross-references in skill files (references/ paths should still work since they're relative within plugin/)
