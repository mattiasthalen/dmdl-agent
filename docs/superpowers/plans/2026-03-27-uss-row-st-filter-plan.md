# USS ROW_ST Filter Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add explicit `ROW_ST = 'Y'` scope rule to USS skill subagent prompt so generated peripherals filter soft-deleted rows in snapshot mode.

**Architecture:** Single-line addition to the scope rules list in `skills/uss/SKILL.md`. The scope rules are copied verbatim into the subagent prompt by the parent agent.

**Tech Stack:** Markdown skill file

---

### Task 1: Add ROW_ST scope rule to USS skill

**Files:**
- Modify: `skills/uss/SKILL.md:110` (after the last scope rule bullet)

**Step 1: Add the scope rule**

After the existing line:
```
   - Use the active dialect from the focal context for all SQL generation. Only PostgreSQL patterns are currently implemented.
```

Add:
```
   - Every `ranked` CTE in snapshot mode MUST include `WHERE ROW_ST = 'Y'` — both in peripherals and in the bridge. Historical mode omits this filter.
```

**Step 2: Verify the edit**

Read `skills/uss/SKILL.md` lines 105-112 and confirm the new rule appears as the last bullet under item #2 (Scope rules).

**Step 3: Bump version**

In `.claude-plugin/plugin.json`, bump version from `1.13.0` to `1.14.0`.

**Step 4: Commit**

```bash
git add skills/uss/SKILL.md .claude-plugin/plugin.json
git commit -m "fix: add ROW_ST filter scope rule to USS skill subagent prompt (#54)"
```

**Step 5: Push and create PR**

```bash
git push -u origin fix/uss-row-st-filter
gh pr create --title "fix: add ROW_ST filter scope rule to USS subagent prompt" --body "Closes #54"
```
