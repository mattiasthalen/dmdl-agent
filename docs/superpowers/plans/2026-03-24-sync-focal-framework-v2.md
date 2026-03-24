# Sync Focal Framework v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure all skills to `references/` layout, absorb upstream teach_claude_focal files verbatim, drop derived `query-patterns.md`, and bump external.lock.

**Architecture:** Move all supporting `.md` files into `references/` subdirectories for each skill. Add four new upstream files to the query skill verbatim (kebab-case filenames only). Update all `${CLAUDE_SKILL_DIR}/` path references in SKILL.md files to include `references/`. Replace `query-patterns.md` references with `ad-hoc-query-agent.md` + `bootstrap.md`.

**Tech Stack:** Markdown, Git

**Worktree:** `.worktrees/feat/sync-focal-framework` (branch: `feat/sync-focal-framework`)

## Execution Order

```
┌─────────────────────────┐  ┌─────────────────────────┐  ┌──────────────────────────────────┐  ┌──────────────────────────────┐
│ Task 1: model refs/     │  │ Task 2: map refs/       │  │ Task 3: query refs/ + upstream   │  │ Task 4: CLAUDE.md + versions │
│ (plugin/skills/model/)  │  │ (plugin/skills/map/)    │  │ (plugin/skills/query/)           │  │ (CLAUDE.md, external.lock,   │
│                         │  │                         │  │                                  │  │  plugin.json)                │
└────────────┬────────────┘  └────────────┬────────────┘  └────────────────┬─────────────────┘  └──────────────┬───────────────┘
             │ PARALLEL                   │ PARALLEL                      │ PARALLEL                          │ PARALLEL
             └────────────────────────────┴───────────────────────────────┴──────────────────────────────────┬─┘
                                                                                                            │
                                                                                                   ┌────────▼────────┐
                                                                                                   │ Task 5: PR      │
                                                                                                   │ (push + gh pr)  │
                                                                                                   └─────────────────┘
```

**Tasks 1–4 run in parallel** — they touch completely different files. Task 5 depends on all four.

---

### Task 1: Restructure model skill to references/ ⟨PARALLEL⟩

**Files:**
- Move: `plugin/skills/model/model-examples.md` → `plugin/skills/model/references/model-examples.md`
- Move: `plugin/skills/model/model-schema.md` → `plugin/skills/model/references/model-schema.md`
- Move: `plugin/skills/model/source-schema-formats.md` → `plugin/skills/model/references/source-schema-formats.md`
- Modify: `plugin/skills/model/SKILL.md`

**Step 1: Create references directory and move files**

```bash
cd /home/mattiasthalen/repos/daana-modeler/.worktrees/feat/sync-focal-framework
mkdir -p plugin/skills/model/references
git mv plugin/skills/model/model-examples.md plugin/skills/model/references/model-examples.md
git mv plugin/skills/model/model-schema.md plugin/skills/model/references/model-schema.md
git mv plugin/skills/model/source-schema-formats.md plugin/skills/model/references/source-schema-formats.md
```

**Step 2: Update SKILL.md path references**

In `plugin/skills/model/SKILL.md`, find-and-replace all occurrences of `${CLAUDE_SKILL_DIR}/model-` with `${CLAUDE_SKILL_DIR}/references/model-`, and `${CLAUDE_SKILL_DIR}/source-` with `${CLAUDE_SKILL_DIR}/references/source-`. Lines affected: 43, 57, 58, 193, 200, 272, 307, 319.

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move model skill supporting files to references/

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Restructure map skill to references/ ⟨PARALLEL⟩

**Files:**
- Move: `plugin/skills/map/mapping-examples.md` → `plugin/skills/map/references/mapping-examples.md`
- Move: `plugin/skills/map/mapping-schema.md` → `plugin/skills/map/references/mapping-schema.md`
- Move: `plugin/skills/map/source-schema-formats.md` → `plugin/skills/map/references/source-schema-formats.md`
- Modify: `plugin/skills/map/SKILL.md`

**Step 1: Create references directory and move files**

```bash
cd /home/mattiasthalen/repos/daana-modeler/.worktrees/feat/sync-focal-framework
mkdir -p plugin/skills/map/references
git mv plugin/skills/map/mapping-examples.md plugin/skills/map/references/mapping-examples.md
git mv plugin/skills/map/mapping-schema.md plugin/skills/map/references/mapping-schema.md
git mv plugin/skills/map/source-schema-formats.md plugin/skills/map/references/source-schema-formats.md
```

**Step 2: Update SKILL.md path references**

In `plugin/skills/map/SKILL.md`, find-and-replace all occurrences of `${CLAUDE_SKILL_DIR}/mapping-` with `${CLAUDE_SKILL_DIR}/references/mapping-`, and `${CLAUDE_SKILL_DIR}/source-` with `${CLAUDE_SKILL_DIR}/references/source-`. Lines affected: 42, 57, 58, 275, 281, 334.

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move map skill supporting files to references/

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Restructure query skill to references/ and absorb upstream ⟨PARALLEL⟩

**Files:**
- Move: `plugin/skills/query/connections.md` → `plugin/skills/query/references/connections.md`
- Move: `plugin/skills/query/dialect-postgres.md` → `plugin/skills/query/references/dialect-postgres.md`
- Move: `plugin/skills/query/focal-framework.md` → `plugin/skills/query/references/focal-framework.md`
- Delete: `plugin/skills/query/query-patterns.md`
- Create: `plugin/skills/query/references/bootstrap.md` (from upstream verbatim)
- Create: `plugin/skills/query/references/ad-hoc-query-agent.md` (from upstream verbatim)
- Create: `plugin/skills/query/references/dimension-patterns.md` (from upstream verbatim)
- Create: `plugin/skills/query/references/fact-patterns.md` (from upstream verbatim)
- Modify: `plugin/skills/query/SKILL.md`

**Step 1: Create references directory and move existing files**

```bash
cd /home/mattiasthalen/repos/daana-modeler/.worktrees/feat/sync-focal-framework
mkdir -p plugin/skills/query/references
git mv plugin/skills/query/connections.md plugin/skills/query/references/connections.md
git mv plugin/skills/query/dialect-postgres.md plugin/skills/query/references/dialect-postgres.md
git mv plugin/skills/query/focal-framework.md plugin/skills/query/references/focal-framework.md
git rm plugin/skills/query/query-patterns.md
```

**Step 2: Copy upstream files verbatim**

```bash
git --git-dir=/tmp/claude-1001/teach_claude_focal_check show HEAD:bootstrap.md > plugin/skills/query/references/bootstrap.md
git --git-dir=/tmp/claude-1001/teach_claude_focal_check show HEAD:ad_hoc_query_agent.md > plugin/skills/query/references/ad-hoc-query-agent.md
git --git-dir=/tmp/claude-1001/teach_claude_focal_check show HEAD:dimension_patterns.md > plugin/skills/query/references/dimension-patterns.md
git --git-dir=/tmp/claude-1001/teach_claude_focal_check show HEAD:fact_patterns.md > plugin/skills/query/references/fact-patterns.md
git add plugin/skills/query/references/
```

**Step 3: Update SKILL.md path references**

In `plugin/skills/query/SKILL.md`, apply these changes:

| Line | Old | New |
|------|-----|-----|
| 36 | `${CLAUDE_SKILL_DIR}/connections.md` | `${CLAUDE_SKILL_DIR}/references/connections.md` |
| 84 | `${CLAUDE_SKILL_DIR}/dialect-<type>.md` | `${CLAUDE_SKILL_DIR}/references/dialect-<type>.md` |
| 90 | `${CLAUDE_SKILL_DIR}/dialect-postgres.md` | `${CLAUDE_SKILL_DIR}/references/dialect-postgres.md` |
| 98 | `Read \`${CLAUDE_SKILL_DIR}/focal-framework.md\` before proceeding.` | `Read \`${CLAUDE_SKILL_DIR}/references/focal-framework.md\` and \`${CLAUDE_SKILL_DIR}/references/bootstrap.md\` before proceeding.` |
| 116-118 | `Run the bootstrap query from the dialect file. Cache the entire result in memory for the session. This is your complete model — no further metadata queries are needed.` | `Run the bootstrap query from \`${CLAUDE_SKILL_DIR}/references/bootstrap.md\`. Re-run the bootstrap every time — even if you already ran it earlier in this session. Never reuse previous bootstrap results. Cache the entire result in memory for the session.` |
| 231 | `The full contents of \`query-patterns.md\`.` | `The full contents of \`ad-hoc-query-agent.md\`.` |
| 253 | `Read \`${CLAUDE_SKILL_DIR}/query-patterns.md\` for all query construction patterns. Follow those patterns exactly when building SQL.` | `Read \`${CLAUDE_SKILL_DIR}/references/ad-hoc-query-agent.md\` for all query construction patterns. Follow those patterns exactly when building SQL.` |
| 280 | `use Pattern 1 from query-patterns.md` | `use Pattern 1 from ad-hoc-query-agent.md` |
| 281 | `use Pattern 2 (single entity) or Pattern 3 (cross-entity) from query-patterns.md` | `use Pattern 2 (single entity) or Pattern 3 (cross-entity) from ad-hoc-query-agent.md` |
| 295 | `apply the cutoff modifier from query-patterns.md` | `apply the cutoff modifier from ad-hoc-query-agent.md` |
| 300 | `Build queries dynamically from the bootstrap data following the patterns in \`${CLAUDE_SKILL_DIR}/query-patterns.md\`.` | `Build queries dynamically from the bootstrap data following the patterns in \`${CLAUDE_SKILL_DIR}/references/ad-hoc-query-agent.md\`.` |
| 309 | `${CLAUDE_SKILL_DIR}/focal-framework.md` | `${CLAUDE_SKILL_DIR}/references/focal-framework.md` |

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: restructure query skill to references/ and absorb upstream files

Move existing supporting files to references/. Delete derived
query-patterns.md. Add upstream files verbatim from teach_claude_focal:
bootstrap.md, ad-hoc-query-agent.md, dimension-patterns.md,
fact-patterns.md. Update SKILL.md references.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Update CLAUDE.md and bump versions ⟨PARALLEL⟩

**Files:**
- Modify: `CLAUDE.md`
- Modify: `external.lock`
- Modify: `plugin/.claude-plugin/plugin.json`

**Step 1: Update CLAUDE.md**

Replace the Repository Structure section and add External References section:

```markdown
## Repository Structure

- **`.claude-plugin/`** — Marketplace manifest
  - `marketplace.json` — Marketplace catalog for plugin discovery
- **`plugin/`** — Distributable plugin contents
  - `.claude-plugin/plugin.json` — Plugin metadata (name: `daana`)
  - `skills/model/SKILL.md` — Model interview skill (`/daana-model`)
  - `skills/model/references/` — Model schema, examples, source format references
  - `skills/map/SKILL.md` — Mapping interview skill (`/daana-map`)
  - `skills/map/references/` — Mapping schema, examples, source format references
  - `skills/query/SKILL.md` — Data query skill (`/daana-query`)
  - `skills/query/references/` — Focal framework, bootstrap, query patterns, dimension/fact patterns, dialect, connections
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans

## External References

- `external.lock` pins upstream repos. When exploring project context (e.g., start of brainstorming), fresh-clone each repo and compare HEAD against the pinned commit to detect new upstream changes.
```

**Step 2: Bump external.lock**

Update `teach_claude_focal` commit from `280f8e457afc82bf00af864a9cdd00bae745ecc9` to `f556f4c11309d6c8ddd8338bf6e8a9c3d12319b4`.

**Step 3: Bump plugin version**

Update `plugin/.claude-plugin/plugin.json` version from `1.7.0` to `1.8.0`.

**Step 4: Commit**

```bash
git add CLAUDE.md external.lock plugin/.claude-plugin/plugin.json
git commit -m "feat: bump external.lock to teach_claude_focal f556f4c and version to 1.8.0

Syncs 10 new upstream commits: bootstrap extraction, dimension patterns,
fact patterns, ad-hoc query agent rename. Adds external references
section to CLAUDE.md.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Push and create PR ⟨SEQUENTIAL — after Tasks 1–4⟩

**Step 1: Push branch**

```bash
git push -u origin feat/sync-focal-framework
```

**Step 2: Create PR**

```bash
gh pr create --title "feat: sync focal framework v2 + restructure skills to references/" --body "$(cat <<'EOF'
## Summary

- Restructure all three skills (model, map, query) to `SKILL_NAME/references/*.md` layout
- Absorb 4 new upstream files from teach_claude_focal verbatim: `bootstrap.md`, `ad-hoc-query-agent.md`, `dimension-patterns.md`, `fact-patterns.md`
- Drop derived `query-patterns.md` in favor of upstream originals
- Bump `external.lock` to `f556f4c` (10 new commits)
- Bump plugin version to `1.8.0`
- Add external references sync note to `CLAUDE.md`

## Test plan

- [ ] Verify all `${CLAUDE_SKILL_DIR}/references/` paths resolve correctly in each SKILL.md
- [ ] Verify upstream files are byte-identical to teach_claude_focal HEAD
- [ ] Verify no stale references to `query-patterns.md` remain
- [ ] Test `/daana-query` skill end-to-end against a live database
- [ ] Test `/daana-model` skill creates a valid model.yaml
- [ ] Test `/daana-map` skill creates a valid mapping file

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
