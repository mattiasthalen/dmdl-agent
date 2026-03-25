# Skill DX Improvements Design

**Date:** 2026-03-25
**Milestone:** Skill DX Improvements
**Issues:** #30, #35, #36, #37

## Summary

Four improvements to the daana plugin's skill developer/user experience: consistent descriptions, permission-free reference reads, reliable prerequisite wiring, and subagent-based execution to reduce main context bloat.

---

## Issue #35 — Refine Skill Descriptions

Fix inconsistent terminology in SKILL.md frontmatter descriptions.

| Skill | Current | Proposed |
|-------|---------|----------|
| `daana-focal` | "...Invoke as a prerequisite from consumer skills." | Remove "Invoke as a prerequisite" (implementation detail) |
| `daana-query` | "Data **agent** that answers..." | "Data **skill** that answers..." |
| `daana-model` | No change | — |
| `daana-map` | No change | — |
| `daana-uss` | No change | — |
| `daana-star` | No change | — |

---

## Issue #36 — Remove Permission Prompts for Reference Reads

**Problem:** Skills use `Read ${CLAUDE_SKILL_DIR}/references/file.md` which triggers Read tool permission prompts, breaking the flow.

**Solution:** Two changes:

1. Add `allowed-tools: ["Read"]` to each skill's YAML frontmatter. This grants the Read tool permission without prompting while the skill is active.

2. Simplify reference paths from:
   ```
   Read `${CLAUDE_SKILL_DIR}/references/focal-framework.md`
   ```
   to:
   ```
   Read @references/focal-framework.md
   ```
   This follows the superpowers convention and is cleaner.

**Affected skills:** All six (focal, query, model, map, uss, star).

---

## Issue #30 — Make Focal a Prerequisite Skill

**Problem:** Consumer skills say `REQUIRED SUB-SKILL: Use daana:focal` as plain text. Claude sometimes skips or misinterprets this.

**Finding:** Claude Code has no formal `requires:` frontmatter. Superpowers uses the same `REQUIRED SUB-SKILL` convention — so the pattern is correct.

**Solution:**

1. Keep `**REQUIRED SUB-SKILL:** Use daana:focal` (matches superpowers convention).
2. Add explicit fallback text: "If focal context is already present in this conversation (bootstrap metadata visible above), skip the focal invocation."
3. Ensure the skill name `daana:focal` exactly matches the plugin-qualified name for reliable Skill tool invocation.

---

## Issue #37 — Move Query/USS/Star Execution to Subagents

**Problem:** Consumer skills load focal bootstrap + reference files + generated SQL + query results all into the main context, causing it to balloon quickly.

**Architecture:**

- **Focal stays in main context** — bootstrap metadata is reusable across invocations.
- **Consumer skills split into two phases:**
  - **Interview phase (main context)** — user interaction, entity selection, parameter gathering.
  - **Execution phase (subagent)** — SQL generation, execution, result presentation.

### Per-skill breakdown

| Skill | Interview (main context) | Execution (subagent) |
|-------|--------------------------|----------------------|
| `/daana-query` | Time dimension questions, question parsing, execution consent | SQL generation, execution, result presentation |
| `/daana-uss` | Entity classification, temporal/historical/materialization choices, output folder | DDL generation, file writing |
| `/daana-star` | Fact/dimension classification, SCD types, materialization | DDL generation, file writing |

### Subagent prompt construction

Each subagent receives a self-contained prompt with:

1. Role and scope rules (copied from the skill)
2. Bootstrap data (full metadata from focal)
3. Connection and dialect details
4. Reference file contents (query patterns, USS patterns, etc.)
5. Interview answers (user choices from the main context)
6. Output format instructions

### Skills NOT affected

- `/daana-model` — pure interview, no SQL execution
- `/daana-map` — pure interview, no SQL execution
- `/daana-focal` — foundation skill, must stay in main context

### Interaction with existing multi-query pattern

`/daana-query` already dispatches parallel subagents for multi-question batches. The single-query path also moves to a subagent, making the pattern consistent. The multi-query flow becomes: interview in main -> dispatch N subagents (one per question).

---

## Testing

Use the `adventure-works-ddw` reference project (in `external/adventure-works-ddw`) to test all skills end-to-end after changes.
