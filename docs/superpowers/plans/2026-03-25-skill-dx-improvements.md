# Skill DX Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the daana plugin's skill DX by fixing descriptions, removing permission prompts, tightening prerequisite wiring, and moving heavy execution to subagents.

**Architecture:** Four independent issues (#30, #35, #36, #37) implemented as sequential commits on branch `chore/skill-dx-improvements`. Issues #35, #36, #30 are small edits across SKILL.md files. Issue #37 rewrites the execution phase of query, uss, and star skills to dispatch subagents. All work happens in the worktree at `.worktrees/chore/skill-dx-improvements/`.

**Tech Stack:** Markdown (SKILL.md skill definitions), YAML frontmatter, Claude Code plugin system.

**Design spec:** `docs/superpowers/specs/2026-03-25-skill-dx-improvements-design.md`

---

## Task 1: Fix skill descriptions (#35)

> Can be parallel with nothing — do first since it's trivial.

**Files:**
- Modify: `skills/focal/SKILL.md:1-4` (frontmatter)
- Modify: `skills/query/SKILL.md:1-4` (frontmatter)

**Step 1: Edit focal description**

In `skills/focal/SKILL.md`, change the frontmatter `description` from:

```
description: Shared Focal foundation — connects to a Focal-based Daana data warehouse and bootstraps metadata into the session context. Invoke as a prerequisite from consumer skills.
```

to:

```
description: Shared Focal foundation — connects to a Focal-based Daana data warehouse and bootstraps metadata into the session context.
```

**Step 2: Edit query description**

In `skills/query/SKILL.md`, change the frontmatter `description` from:

```
description: Data agent that answers natural language questions about Focal-based Daana data warehouses via live SQL queries.
```

to:

```
description: Data skill that answers natural language questions about Focal-based Daana data warehouses via live SQL queries.
```

**Step 3: Commit**

```bash
git add skills/focal/SKILL.md skills/query/SKILL.md
git commit -m "style: refine skill descriptions for consistency (#35)"
```

---

## Task 2: Add allowed-tools and convert reference paths (#36)

> Sequential after Task 1 (overlapping files). Touches all 6 skills.

**Files:**
- Modify: `skills/focal/SKILL.md` (frontmatter + 6 reference paths)
- Modify: `skills/model/SKILL.md` (frontmatter + 8 reference paths)
- Modify: `skills/map/SKILL.md` (frontmatter + 6 reference paths)
- Modify: `skills/query/SKILL.md` (frontmatter + 2 reference paths)
- Modify: `skills/uss/SKILL.md` (frontmatter + 3 reference paths)
- Modify: `skills/star/SKILL.md` (frontmatter + 2 reference paths)

**Step 1: Add `allowed-tools` to each skill's frontmatter**

Add `allowed-tools: ["Read"]` to the YAML frontmatter of all 6 SKILL.md files. Example for focal:

```yaml
---
name: daana-focal
description: Shared Focal foundation — connects to a Focal-based Daana data warehouse and bootstraps metadata into the session context.
allowed-tools: ["Read"]
---
```

**Step 2: Convert all reference paths**

Replace every occurrence of `${CLAUDE_SKILL_DIR}/references/` with `@references/` across all 6 skills. The pattern is:

| Before | After |
|--------|-------|
| `` Read `${CLAUDE_SKILL_DIR}/references/focal-framework.md` `` | `` Read @references/focal-framework.md `` |
| `` `${CLAUDE_SKILL_DIR}/references/model-schema.md` `` | `` @references/model-schema.md `` |

Apply to all 26 occurrences. Preserve surrounding sentence structure — only replace the path portion.

**Step 3: Verify no remaining `${CLAUDE_SKILL_DIR}` references**

Run: `grep -r 'CLAUDE_SKILL_DIR' skills/`
Expected: No matches.

**Step 4: Commit**

```bash
git add skills/
git commit -m "fix: add allowed-tools and simplify reference paths (#36)"
```

---

## Task 3: Tighten focal prerequisite wiring (#30)

> Sequential after Task 2 (overlapping files). Touches 3 consumer skills.

**Files:**
- Modify: `skills/query/SKILL.md:8` (prerequisite line)
- Modify: `skills/uss/SKILL.md:8` (prerequisite line)
- Modify: `skills/star/SKILL.md:8` (prerequisite line)

**Step 1: Update prerequisite block in all three skills**

Replace the current single-line prerequisite in query, uss, and star:

```markdown
**REQUIRED SUB-SKILL:** Use daana:focal
```

with:

```markdown
**REQUIRED SUB-SKILL:** Use daana:focal

Apply that foundational understanding before proceeding. If focal context is already present in this conversation (bootstrap metadata visible above), skip the focal invocation.
```

**Step 2: Commit**

```bash
git add skills/query/SKILL.md skills/uss/SKILL.md skills/star/SKILL.md
git commit -m "fix: tighten focal prerequisite wiring with fallback (#30)"
```

---

## Task 4: Move query execution to subagent (#37)

> Can be parallel with Tasks 5 and 6 (different files).

**Files:**
- Modify: `skills/query/SKILL.md` (rewrite Phase 1 query loop execution + Phase 1B)

**Step 1: Read current query skill**

Read `skills/query/SKILL.md` in full. Understand the Phase 1 query loop (lines 140-258) and Phase 1B multi-query flow (lines 45-138).

**Step 2: Rewrite Phase 1 query loop to dispatch subagent**

After the interview gates (time dimension, execution consent), instead of building and executing SQL inline, dispatch a subagent. The rewritten flow:

1. Time dimension questions remain in main context (unchanged).
2. Execution consent remains in main context (unchanged).
3. After consent, dispatch a single subagent with the `Agent` tool containing:
   - Role: "You are a data analyst answering a single question against a Focal-based Daana data warehouse."
   - Scope rules: Copy from the Scope section.
   - Bootstrap data: "The full bootstrap result from the current session context."
   - Connection + dialect details from the session context.
   - Query patterns: "Read @references/ad-hoc-query-agent.md for all query construction patterns."
   - Time dimension choices from the interview.
   - Execution consent: "Execution is pre-approved."
   - The user's question.
   - Output format: SQL code block, markdown result table, natural language summary, 2-3 follow-up suggestions.
4. Present the subagent's result to the user.
5. Return to the query loop for the next question.

**Step 3: Simplify Phase 1B multi-query flow**

The multi-query parallel path (Step 4B) already dispatches subagents — keep that pattern. Make the sequential path (Step 4A) also dispatch subagents one at a time (same prompt as Phase 1). This makes all execution paths consistent.

**Step 4: Add subagent execution section**

Add a new section "## Subagent Execution" after the Phase 1 query loop that documents the subagent prompt template. This is the single source of truth for what gets passed to subagents — both single-query and multi-query flows reference it.

The template must include:
1. Role and scope rules
2. Bootstrap data placeholder: `{bootstrap_data}`
3. Connection + dialect placeholder: `{connection_details}`, `{dialect_instructions}`
4. Reference content: Read @references/ad-hoc-query-agent.md
5. Time dimension choices: `{time_dimension_choices}`
6. Execution consent flag
7. The question: `{question}`
8. Output format instructions

**Step 5: Verify no inline SQL execution remains**

Grep for patterns like "Execute using", "Run the query", "agent-rendered from CSV" in the skill body. These should only appear inside the subagent prompt template section, not in the main flow.

**Step 6: Commit**

```bash
git add skills/query/SKILL.md
git commit -m "feat: move query execution to subagent (#37)"
```

---

## Task 5: Move USS execution to subagent (#37)

> Can be parallel with Tasks 4 and 6 (different files).

**Files:**
- Modify: `skills/uss/SKILL.md` (rewrite Phase 2: Generate)

**Step 1: Read current USS skill**

Read `skills/uss/SKILL.md` in full. Understand Phase 1 (Interview, lines 30-82) and Phase 2 (Generate, lines 84-120).

**Step 2: Rewrite Phase 2 to dispatch subagent**

After the interview phase collects all choices, dispatch a single subagent for DDL generation:

1. Interview phase remains in main context (unchanged) — entity classification, temporal mode, historical mode, materialization, output folder.
2. After all interview answers collected, dispatch a subagent with the `Agent` tool containing:
   - Role: "You are a SQL DDL generator creating a Unified Star Schema from Focal metadata."
   - Scope rules: Copy from the Scope section.
   - Bootstrap data from the session context.
   - Connection + dialect details.
   - USS patterns: "Read @references/uss-patterns.md for all DDL patterns."
   - USS examples: "Read @references/uss-examples.md for worked examples."
   - Interview answers: entity classification, temporal mode, historical mode, materialization choice, output folder, target schema.
   - Column naming conventions (copy the table from the current skill).
   - File naming rules (copy from current skill).
   - Output instructions: "Generate all SQL files and write them to {output_folder}. Return a list of generated files with descriptions."
3. Present the subagent's file list to the user.
4. Proceed to Phase 3 (Handover) — DDL execution consent stays in main context.

**Step 3: Add subagent execution section**

Add "## Subagent Execution" section with the USS subagent prompt template, similar to the query skill pattern.

**Step 4: Commit**

```bash
git add skills/uss/SKILL.md
git commit -m "feat: move USS generation to subagent (#37)"
```

---

## Task 6: Move star execution to subagent (#37)

> Can be parallel with Tasks 4 and 5 (different files).

**Files:**
- Modify: `skills/star/SKILL.md` (expand skeleton with subagent pattern)

**Step 1: Read current star skill**

Read `skills/star/SKILL.md` in full. It is currently a skeleton with only phase descriptions and reference pointers.

**Step 2: Expand skeleton with subagent execution pattern**

Since the star skill is a skeleton, add the subagent dispatch pattern to Phase 2 (Generate):

1. Interview phase structure (Phase 1) — outline the questions (fact/dimension classification, SCD types, materialization). Keep as skeleton stubs with TODO markers since full implementation is deferred.
2. Phase 2 dispatch to subagent with:
   - Role: "You are a SQL DDL generator creating a traditional star schema from Focal metadata."
   - Bootstrap data, connection, dialect.
   - Dimension patterns: "Read @references/dimension-patterns.md"
   - Fact patterns: "Read @references/fact-patterns.md"
   - Interview answers.
   - Output instructions.
3. Phase 3 (Handover) — same pattern as USS.

**Step 3: Commit**

```bash
git add skills/star/SKILL.md
git commit -m "feat: move star generation to subagent (#37)"
```

---

## Task 7: Version bump and push

> Sequential — after all other tasks complete.

**Files:**
- Modify: `.claude-plugin/plugin.json` (version field)

**Step 1: Bump version**

Change `"version": "1.10.0"` to `"version": "1.11.0"` in `.claude-plugin/plugin.json`.

**Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 1.11.0"
```

**Step 3: Push branch**

```bash
git push -u origin chore/skill-dx-improvements
```

---

## Parallelism Map

```
Task 1 (#35 descriptions)
  → Task 2 (#36 allowed-tools + paths)
    → Task 3 (#30 prerequisites)
      → Task 4 (#37 query subagent)  ─┐
      → Task 5 (#37 USS subagent)    ─┤ PARALLEL
      → Task 6 (#37 star subagent)   ─┘
        → Task 7 (version bump + push)
```

Tasks 4, 5, 6 touch different files and can be dispatched to parallel subagents.
