# Parallel Queries Design

**Date:** 2026-03-18
**Status:** Approved

## Overview

Enable users to ask multiple data questions at once and choose whether to run them sequentially in the current session or in parallel via subagents. The goal is to avoid repeating connection/bootstrap setup for each question while giving users control over execution mode.

## Approach

Modify the existing `/daana-query` skill (SKILL.md) to detect multiple questions and add a multi-query flow. No new skills or files needed — subagent prompts are constructed from existing skill contents.

## Multi-Question Detection

After bootstrap completes and the user sends a message, the skill checks if it contains multiple distinct questions. Detection is natural — the agent uses its language understanding (no regex parsing).

- **One question** → existing Phase 3 query loop (no change).
- **Multiple questions** → enter the multi-query flow.

Detection happens at the start of Phase 3 on each user message, so it works both on the first question after bootstrap and on subsequent messages mid-session.

## Multi-Query Flow

### Step 1 — Confirm the questions

Present the parsed questions as a numbered list and ask the user to confirm or adjust.

### Step 2 — Time dimension (once)

Ask the two existing hard-gate questions (latest/history, cutoff date) — same as today, but applied to all questions in the batch.

### Step 3 — Execution mode

Ask: "Run these sequentially in this session, or in parallel via subagents?"

### Step 4a — Sequential

Loop through each question using the existing Phase 3 query loop. Skip the time dimension questions (already answered) and skip execution consent (auto-execute). Present each result as it completes.

### Step 4b — Parallel

Ask execution consent once: "Auto-execute all queries in this batch?" Then dispatch subagents.

## Parallel Subagent Dispatch

### Subagent prompt construction

Each subagent receives a self-contained prompt with:

- The full query skill instructions for Phase 3 only (query loop behavior, query patterns, safety guardrails, result presentation)
- The serialized bootstrap result (the cached metadata table)
- Connection details (host, port, user, database, password env var reference)
- Dialect file contents (e.g., `dialect-postgres.md`)
- The pre-answered time dimension choices (latest/history, cutoff)
- Execution consent pre-approved
- A single question to answer

### Subagent behavior

Each subagent:

1. Matches the question against bootstrap metadata
2. Builds the SQL query
3. Executes it (pre-approved, no consent prompt)
4. Returns: the SQL, the result table, a natural language summary, and suggested follow-ups

### Result presentation

- Each subagent's result is presented as it arrives (question number, SQL, table, summary)
- After all complete, present a combined summary: a brief recap of all answers together with any cross-cutting insights

### Error handling

If a subagent fails (bad SQL, no results, ambiguous match), it returns the error. The main agent reports it alongside the successful results and offers to retry that question interactively.

## Scope & Constraints

### What stays the same

- Phases 1-2 (Connection, Bootstrap) — unchanged
- Single-question flow — unchanged
- All existing hard gates — still enforced, just consolidated for batches
- Phase 4 (Handover) — unchanged
- Read-only safety guardrails — enforced in subagents too

### What changes

- Phase 3 gains multi-question detection at the start of each user message
- New multi-query flow inserted between detection and the existing query loop
- Subagent prompts are constructed from existing skill files — no new reference files

### Limitations

- Each subagent works independently — no cross-question joins. The combined summary can note connections, but complex cross-analysis needs a follow-up sequential query
- Bootstrap data size is bounded by the number of entities/attributes in the model — typically manageable within prompt limits
- Subagents share the same time dimension choices — if a user wants "latest" for one and "history" for another, they should run those separately
