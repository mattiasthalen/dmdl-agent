# Plugin Scoping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move plugin-distributable files into a `plugin/` subdirectory so only skills and references are distributed to users.

**Architecture:** Use `git mv` to relocate skills/, references/, and plugin.json into plugin/. Update marketplace.json source path and CLAUDE.md structure docs.

**Tech Stack:** Git, Markdown

---

### Task 1: Create plugin directory and move files

**Files:**
- Move: `skills/` → `plugin/skills/`
- Move: `references/` → `plugin/references/`
- Move: `.claude-plugin/plugin.json` → `plugin/.claude-plugin/plugin.json`

**Step 1: Create directory structure and move files**

```bash
mkdir -p plugin/.claude-plugin
git mv skills plugin/skills
git mv references plugin/references
git mv .claude-plugin/plugin.json plugin/.claude-plugin/plugin.json
```

**Step 2: Bump version to 1.2.0**

Edit `plugin/.claude-plugin/plugin.json` and change `"version": "1.1.0"` to `"version": "1.2.0"`.

**Step 3: Commit**

```bash
git add plugin/
git commit -m "refactor: move plugin files into plugin/ subdirectory

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Update marketplace.json source path

**Files:**
- Modify: `.claude-plugin/marketplace.json`

**Step 1: Update source**

Change `"source": "./"` to `"source": "./plugin/"` in `.claude-plugin/marketplace.json`.

**Step 2: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "fix: point marketplace source to plugin/ subdirectory

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Update CLAUDE.md repository structure

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the Repository Structure section**

Replace the current structure section with:

```markdown
## Repository Structure

- **`.claude-plugin/`** — Marketplace manifest
  - `marketplace.json` — Marketplace catalog for plugin discovery
- **`plugin/`** — Distributable plugin contents
  - `.claude-plugin/plugin.json` — Plugin metadata (name: `daana`)
  - `skills/model/SKILL.md` — Model interview skill (`/daana-model`)
  - `skills/map/SKILL.md` — Mapping interview skill (`/daana-map`)
  - `skills/query/SKILL.md` — Data query skill (`/daana-query`)
  - `references/` — Shared DMDL schema, examples, and source schema formats
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update repo structure for plugin/ layout

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Verify

**Step 1: Check file structure**

Verify these exist:
- `plugin/.claude-plugin/plugin.json` — has version 1.2.0
- `plugin/skills/model/SKILL.md`
- `plugin/skills/map/SKILL.md`
- `plugin/skills/query/SKILL.md`
- `plugin/references/` — all 7 reference files
- `.claude-plugin/marketplace.json` — source is `"./plugin/"`

**Step 2: Check these do NOT exist at root**

- `skills/` — should be gone
- `references/` — should be gone
- `.claude-plugin/plugin.json` — should only be in `plugin/.claude-plugin/`

**Step 3: Verify cross-references in skill files**

Grep for `references/` in skill files and confirm paths still work relative to `plugin/`.
