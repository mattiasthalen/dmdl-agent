---
name: daana-star
description: Generate traditional star schema SQL (fact tables + dimension tables) from a Focal-based Daana data warehouse.
allowed-tools: ["Read"]
---

# Daana Star Schema Generator

**REQUIRED SUB-SKILL:** Use daana:focal

Apply that foundational understanding before proceeding. If focal context is already present in this conversation (bootstrap metadata visible above), skip the focal invocation.

> **Status:** Skeleton — full implementation deferred to a future design spec.

This skill generates traditional star schema DDL (fact tables and dimension tables) from a Focal-based Daana data warehouse.

The focal skill establishes the database connection and bootstraps metadata. Once focal completes, the session flows through the phases below.

## Phase 1: Interview

> **Status:** Skeleton — interview questions to be fully specified in a future design spec.

The interview phase classifies entities and gathers DDL preferences. All questions use the `AskUserQuestion` tool. Outline:

1. **Entity Classification** — Classify bootstrap entities as facts or dimensions.
2. **SCD Type Selection** — For each dimension, choose SCD type (0-6).
3. **Materialization** — Views, tables, or mixed.
4. **Output Folder** — Where to write the SQL files.

## Phase 2: Generate

After all interview answers are collected, dispatch a single subagent using the `Agent` tool to generate all SQL files.

### Subagent prompt template

The subagent prompt MUST include all of the following — the subagent has no other context:

1. **Role:** "You are a SQL DDL generator creating a traditional star schema from Focal metadata."
2. **Scope rules:** DDL generation only. Never hardcode TYPE_KEYs — always resolve from bootstrap. Use the active dialect from the focal context for all SQL generation.
3. **Bootstrap data:** The full cached bootstrap result from the current session context, serialized as a markdown table.
4. **Connection details:** Host, port, user, database, password (env var reference), sslmode — from the current session context.
5. **Dialect instructions:** The full dialect instructions from the current session context.
6. **Dimension patterns:** Read @references/dimension-patterns.md for SCD type patterns.
7. **Fact patterns:** Read @references/fact-patterns.md for fact table patterns.
8. **Interview answers:**
   - Entity classification: which entities are facts, which are dimensions
   - SCD type per dimension
   - Materialization choice
   - Output folder path
   - Target schema name
9. **Output instructions:** "Generate all SQL files and write them to {output_folder}. Return a list of generated files with brief descriptions."

### Result handling

Present the subagent's file list to the user. If the subagent reports errors, offer to retry with adjusted parameters.

## Phase 3: Handover

After generating all files:

1. List the generated files with a brief description of each.
2. Ask the user for permission before executing any DDL (same pattern as USS skill).
3. Suggest: "You can now use `/daana-query` to query the star schema."

## References

- @references/dimension-patterns.md — SCD types 0-6, mixed types, design considerations.
- @references/fact-patterns.md — Transaction, periodic snapshot, accumulating snapshot, factless facts.
