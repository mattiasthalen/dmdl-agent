# Restructure Repo Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Flatten `plugin/` into the repo root so the layout matches superpowers plugin conventions.

**Architecture:** Move `plugin/skills/` to `skills/`, move `plugin/.claude-plugin/plugin.json` to `.claude-plugin/plugin.json`, update path references in `marketplace.json` and `CLAUDE.md`, delete `plugin/`.

**Tech Stack:** Git, shell commands

---

### Task 1: Move plugin.json to root .claude-plugin/

**Files:**
- Move: `plugin/.claude-plugin/plugin.json` → `.claude-plugin/plugin.json`

**Step 1: Copy plugin.json into root .claude-plugin/**

```bash
cp plugin/.claude-plugin/plugin.json .claude-plugin/plugin.json
```

**Step 2: Verify the file is correct**

Run: `cat .claude-plugin/plugin.json`
Expected: JSON with `"name": "daana"`, `"version": "1.8.0"`

**Step 3: Remove the old plugin/.claude-plugin/ directory**

```bash
rm -rf plugin/.claude-plugin/
```

**Step 4: Commit**

```bash
git add .claude-plugin/plugin.json plugin/.claude-plugin/
git commit -m "refactor: move plugin.json to root .claude-plugin/"
```

---

### Task 2: Move skills/ to repo root

**Files:**
- Move: `plugin/skills/` → `skills/`

**Step 1: Move the skills directory**

```bash
mv plugin/skills/ skills/
```

**Step 2: Verify all three skills moved correctly**

Run: `ls skills/*/SKILL.md`
Expected:
```
skills/map/SKILL.md
skills/model/SKILL.md
skills/query/SKILL.md
```

**Step 3: Verify references directories**

Run: `ls skills/*/references/`
Expected: Reference files present for all three skills

**Step 4: Remove the now-empty plugin/ directory**

```bash
rmdir plugin/
```

**Step 5: Commit**

```bash
git add plugin/ skills/
git commit -m "refactor: move skills/ from plugin/ to repo root"
```

---

### Task 3: Update marketplace.json source path

**Files:**
- Modify: `.claude-plugin/marketplace.json:9` — change source from `"./plugin/"` to `"./"`

**Step 1: Update the source path**

In `.claude-plugin/marketplace.json`, change line 9:
```json
      "source": "./"
```

**Step 2: Verify the full file**

Run: `cat .claude-plugin/marketplace.json`
Expected:
```json
{
  "name": "daana-modeler",
  "owner": {
    "name": "Mattias Thalén"
  },
  "plugins": [
    {
      "name": "daana",
      "source": "./"
    }
  ]
}
```

**Step 3: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "refactor: update marketplace source path to repo root"
```

---

### Task 4: Update CLAUDE.md repository structure

**Files:**
- Modify: `CLAUDE.md:6-16` — flatten the structure description

**Step 1: Replace the Repository Structure section**

Replace lines 6-16 of `CLAUDE.md` with:

```markdown
## Repository Structure

- **`.claude-plugin/`** — Plugin manifests
  - `plugin.json` — Plugin metadata (name: `daana`)
  - `marketplace.json` — Marketplace catalog for plugin discovery
- **`skills/model/SKILL.md`** — Model interview skill (`/daana-model`)
  - `skills/model/references/` — Model schema, examples, source format references
- **`skills/map/SKILL.md`** — Mapping interview skill (`/daana-map`)
  - `skills/map/references/` — Mapping schema, examples, source format references
- **`skills/query/SKILL.md`** — Data query skill (`/daana-query`)
  - `skills/query/references/` — Focal framework, bootstrap, query patterns, dimension/fact patterns, dialect, connections
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
```

**Step 2: Verify the update**

Run: `head -25 CLAUDE.md`
Expected: Updated structure with no `plugin/` references in the live structure section

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to reflect new repo layout"
```

---

### Task 5: Bump plugin version

**Files:**
- Modify: `.claude-plugin/plugin.json:4` — bump version

**Step 1: Bump version from 1.8.0 to 1.9.0**

In `.claude-plugin/plugin.json`, change `"version": "1.8.0"` to `"version": "1.9.0"`.

**Step 2: Verify**

Run: `cat .claude-plugin/plugin.json`
Expected: `"version": "1.9.0"`

**Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: bump version to 1.9.0"
```
