# Sync Focal Framework v2 — Design Spec

## Context

The `teach_claude_focal` external reference is 10 commits behind (`280f8e45` → `f556f4c`). Upstream added:

- `bootstrap.md` — extracted from `agent_workflow.md`
- `dimension_patterns.md` — SCD Types 0–6, mixed types, delta loads
- `fact_patterns.md` — transaction, periodic snapshot, accumulating snapshot, factless
- `agent_workflow.md` → `ad_hoc_query_agent.md` (rename, bootstrap section replaced with pointer)
- `.gitignore` — ignores `output/`
- `focal_framework.md` — unchanged

Additionally, all three skills need restructuring to the standard `SKILL_NAME/references/*.md` layout.

## Approach

Use upstream files verbatim — no convention layer. Drop our derived `query-patterns.md` in favor of Patrik's original files. Handle plugin-specific concerns (paths, dialect) in `SKILL.md` and `dialect-postgres.md` only.

## Changes

### 1. Restructure all skills to `references/`

Move supporting files into `references/` subdirectories:

**model:**
```
plugin/skills/model/SKILL.md
plugin/skills/model/references/model-examples.md
plugin/skills/model/references/model-schema.md
plugin/skills/model/references/source-schema-formats.md
```

**map:**
```
plugin/skills/map/SKILL.md
plugin/skills/map/references/mapping-examples.md
plugin/skills/map/references/mapping-schema.md
plugin/skills/map/references/source-schema-formats.md
```

**query:**
```
plugin/skills/query/SKILL.md
plugin/skills/query/references/connections.md
plugin/skills/query/references/dialect-postgres.md
plugin/skills/query/references/focal-framework.md
plugin/skills/query/references/bootstrap.md
plugin/skills/query/references/ad-hoc-query-agent.md
plugin/skills/query/references/dimension-patterns.md
plugin/skills/query/references/fact-patterns.md
```

### 2. Absorb upstream files (verbatim)

Add four new files to `plugin/skills/query/references/`:

| Upstream file | Plugin file | Notes |
|---|---|---|
| `bootstrap.md` | `bootstrap.md` | Verbatim |
| `ad_hoc_query_agent.md` | `ad-hoc-query-agent.md` | Verbatim (kebab-case filename only) |
| `dimension_patterns.md` | `dimension-patterns.md` | Verbatim (kebab-case filename only) |
| `fact_patterns.md` | `fact-patterns.md` | Verbatim (kebab-case filename only) |

### 3. Delete `query-patterns.md`

Replace with upstream's `ad-hoc-query-agent.md` + `bootstrap.md`. These cover the same patterns (Pattern 1/2/3, decision tree, cutoff modifier) plus the dimension/fact patterns reference them directly.

### 4. Update `SKILL.md` path references

All three skills: update `${CLAUDE_SKILL_DIR}/foo.md` → `${CLAUDE_SKILL_DIR}/references/foo.md`.

For query skill specifically:
- `query-patterns.md` references → `ad-hoc-query-agent.md`
- Add bootstrap reference → `bootstrap.md`
- Remove the inline bootstrap interpretation table (now in `bootstrap.md`)

### 5. Update `CLAUDE.md`

Add external references section:

```markdown
## External References

- `external.lock` pins upstream repos. When exploring project context (e.g., start of brainstorming), fresh-clone each repo and compare HEAD against the pinned commit to detect new upstream changes.
```

Update repository structure to reflect `references/` layout.

### 6. Bump `external.lock`

Update `teach_claude_focal` pinned commit from `280f8e457afc82bf00af864a9cdd00bae745ecc9` to `f556f4c`.

### 7. Bump plugin version

Update `plugin/.claude-plugin/plugin.json` version.

## Files Changed

| File | Change |
|---|---|
| `plugin/skills/query/references/bootstrap.md` | New (from upstream) |
| `plugin/skills/query/references/ad-hoc-query-agent.md` | New (from upstream) |
| `plugin/skills/query/references/dimension-patterns.md` | New (from upstream) |
| `plugin/skills/query/references/fact-patterns.md` | New (from upstream) |
| `plugin/skills/query/query-patterns.md` | Deleted |
| `plugin/skills/query/references/focal-framework.md` | Moved from `plugin/skills/query/` |
| `plugin/skills/query/references/connections.md` | Moved from `plugin/skills/query/` |
| `plugin/skills/query/references/dialect-postgres.md` | Moved from `plugin/skills/query/` |
| `plugin/skills/query/SKILL.md` | Path updates, bootstrap pointer |
| `plugin/skills/model/references/model-examples.md` | Moved from `plugin/skills/model/` |
| `plugin/skills/model/references/model-schema.md` | Moved from `plugin/skills/model/` |
| `plugin/skills/model/references/source-schema-formats.md` | Moved from `plugin/skills/model/` |
| `plugin/skills/model/SKILL.md` | Path updates |
| `plugin/skills/map/references/mapping-examples.md` | Moved from `plugin/skills/map/` |
| `plugin/skills/map/references/mapping-schema.md` | Moved from `plugin/skills/map/` |
| `plugin/skills/map/references/source-schema-formats.md` | Moved from `plugin/skills/map/` |
| `plugin/skills/map/SKILL.md` | Path updates |
| `external.lock` | Bump teach_claude_focal commit |
| `CLAUDE.md` | Add external references section, update structure |
| `plugin/.claude-plugin/plugin.json` | Version bump |

## Out of Scope

- New star schema skill (postponed)
- Content changes to model/map skills beyond path fixes
- Convention layers on upstream files
