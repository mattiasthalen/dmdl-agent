# USS Peripheral ROW_ST Filter — Design Spec

**Issue:** mattiasthalen/daana-modeler#54
**Date:** 2026-03-27

## Problem

The USS skill's subagent prompt does not explicitly require `WHERE ROW_ST = 'Y'` in peripheral `ranked` CTEs. While the reference patterns (`uss-patterns.md`) and worked examples (`uss-examples.md`) correctly include this filter, the subagent can miss it because the scope rules in `SKILL.md` don't call it out as a critical requirement.

This results in generated peripheral SQL that includes soft-deleted rows (`ROW_ST = 'N'`) in the carry-forward timeline, while the bridge correctly filters them out.

## Root Cause

The subagent prompt template (SKILL.md, Phase 2) lists scope rules that get copied verbatim into the subagent's context. These rules cover TYPE_KEY resolution, M:1 chains, physical columns, and dialect — but not ROW_ST filtering. The subagent must infer the filter from patterns alone, which is unreliable.

## Fix

Add one scope rule to the subagent prompt template in `skills/uss/SKILL.md`:

> Every `ranked` CTE in snapshot mode MUST include `WHERE ROW_ST = 'Y'` — both in peripherals and in the bridge. Historical mode omits this filter.

This is added to the existing scope rules list (item #2 in the subagent prompt template, line 110), which the parent agent copies verbatim into the subagent prompt.

## Affected Files

- `skills/uss/SKILL.md` — Add scope rule to subagent prompt template

## Out of Scope

- Regenerating the 14 existing peripheral SQL files in `uss/` (output files, not the skill)
- Changes to `uss-patterns.md` or `uss-examples.md` (already correct)
