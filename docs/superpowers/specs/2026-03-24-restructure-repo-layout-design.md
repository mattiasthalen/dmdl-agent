# Restructure Repo Layout to Match Superpowers Conventions

**Issue:** #31
**Date:** 2026-03-24

## Context

The daana-modeler plugin wraps distributable content in a `plugin/` subdirectory. The superpowers plugin convention places skills, plugin.json, and marketplace.json directly at the repo root. This restructuring aligns daana-modeler with that convention.

## Design

Flatten `plugin/` into the repo root. No functionality changes.

### File Moves

| From | To |
|------|-----|
| `plugin/skills/` | `skills/` |
| `plugin/.claude-plugin/plugin.json` | `.claude-plugin/plugin.json` |

### File Updates

| File | Change |
|------|--------|
| `.claude-plugin/marketplace.json` | `"source": "./plugin/"` → `"source": "./"` |
| `CLAUDE.md` | Update paths referencing `plugin/` |

### Deletions

| Path | Reason |
|------|--------|
| `plugin/` | Empty after moves |

### Result

```
repo-root/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   ├── model/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── map/
│   │   ├── SKILL.md
│   │   └── references/
│   └── query/
│       ├── SKILL.md
│       └── references/
├── docs/
├── external/
├── scripts/
├── CLAUDE.md
└── README.md
```
