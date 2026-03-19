# Parallel Queries Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable `/daana-query` to detect multiple questions in a single message and offer sequential or parallel (subagent) execution, with shared bootstrap and time dimension choices.

**Architecture:** Modify the existing SKILL.md to add multi-question detection after bootstrap, a consolidated prompt flow (time dimension + execution consent asked once), and a parallel dispatch path that constructs self-contained subagent prompts from existing skill files.

**Tech Stack:** Claude Code skills (Markdown), Agent tool for subagent dispatch

---

### Task 1: Add Multi-Question Detection to Phase 3

**Files:**
- Modify: `plugin/skills/query/SKILL.md:147-149` (between Phase 2 post-bootstrap greeting and Phase 3 header)

**Step 1: Add the multi-question detection section**

Insert a new section between the Post-Bootstrap Greeting section (line 146) and before the existing `## Phase 3: Query Loop` header:

```markdown
## Multi-Question Detection

At the start of every user message in Phase 3, check whether it contains **multiple distinct data questions**. Use natural language understanding — no regex parsing.

- **One question** → proceed to the normal Phase 3 query loop below.
- **Multiple questions** → enter the Multi-Query Flow (Phase 3B) before the query loop.

This detection applies to every user message, not just the first one after bootstrap.
```

**Step 2: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat: add multi-question detection to query skill"
```

---

### Task 2: Add Phase 3B — Multi-Query Flow

**Files:**
- Modify: `plugin/skills/query/SKILL.md` (insert after the Multi-Question Detection section from Task 1)

**Step 1: Add Phase 3B section**

Insert the following after the Multi-Question Detection section:

```markdown
## Phase 3B: Multi-Query Flow

Enter this flow when multiple questions are detected in a single user message.

### Step 1 — Confirm the questions

Present the parsed questions as a numbered list. Call the `AskUserQuestion` tool (do NOT print the question as text):

- Question: "I see N questions:\n1. [question 1]\n2. [question 2]\n3. [question 3]\n\nIs this right?"
- Options: "Yes" / "No, let me adjust"

**STOP and wait for the user's answer. If they adjust, re-parse and confirm again.**

### Step 2 — Time dimension (once for all)

Ask the two existing time dimension hard-gate questions — same as Phase 3, but the answers apply to **all questions in the batch**:

1. Latest or history? (same options as Phase 3)
2. Cutoff date? (same options as Phase 3)

These choices are locked in for the entire batch.

### Step 3 — Execution mode

Call the `AskUserQuestion` tool (do NOT print the question as text):

- Question: "Run these sequentially in this session, or in parallel via subagents?"
- Options: "Sequential" / "Parallel"

**STOP and wait for the user's answer.**

- **Sequential** → proceed to Step 4A.
- **Parallel** → proceed to Step 4B.

### Step 4A — Sequential execution

Loop through each question using the existing Phase 3 query loop. For each question:

- Skip the time dimension questions (already answered in Step 2).
- Skip execution consent (auto-execute).
- Present each result as it completes (SQL, table, summary, follow-ups).

After all questions are answered, present a **combined summary**: a brief recap of all answers with any cross-cutting insights.

Then return to the normal Phase 3 query loop for further questions.

### Step 4B — Parallel execution

<HARD-GATE>
**You MUST ask for execution consent before dispatching subagents. Do NOT skip this step.**
</HARD-GATE>

Call the `AskUserQuestion` tool (do NOT print the question as text):

- Question: "Auto-execute all queries in this batch?"
- Options: "Yes, auto-execute" / "No, cancel"

**STOP and wait for the user's answer.**

- **Yes** → dispatch subagents (see Parallel Subagent Dispatch below).
- **No** → return to the normal Phase 3 query loop.
```

**Step 2: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat: add multi-query flow (Phase 3B) to query skill"
```

---

### Task 3: Add Parallel Subagent Dispatch Section

**Files:**
- Modify: `plugin/skills/query/SKILL.md` (insert after Phase 3B Step 4B)

**Step 1: Add the parallel dispatch section**

Insert the following after Step 4B:

```markdown
### Parallel Subagent Dispatch

After execution consent is granted, dispatch one subagent per question using the `Agent` tool. Launch **all subagents in a single message** so they run concurrently.

#### Subagent prompt construction

Each subagent prompt MUST include all of the following — the subagent has no other context:

1. **Role:** "You are a data analyst answering a single question against a Focal-based Daana data warehouse."
2. **Scope rules:** Copy the Scope section from this skill (read-only, no DDL/DML, no hardcoded TYPE_KEYs, etc.)
3. **Bootstrap data:** The full cached bootstrap result, serialized as a markdown table or CSV block.
4. **Connection details:** Host, port, user, database, password (env var reference), sslmode.
5. **Dialect instructions:** The full contents of the dialect file (e.g., `dialect-postgres.md`) — execution command, statement timeout, syntax rules.
6. **Query patterns:** The full contents of `query-patterns.md`.
7. **Time dimension choices:** The pre-answered latest/history and cutoff date decisions from Step 2.
8. **Execution consent:** "Execution is pre-approved. Execute the query without asking."
9. **The question:** The single question this subagent must answer.
10. **Output format:** "Return: (a) the generated SQL in a code block, (b) the query result as a markdown table, (c) a natural language summary in business terms, (d) 2-3 suggested follow-up questions."

#### Result presentation

- Present each subagent's result as it arrives: question number, SQL, result table, summary.
- After **all** subagents complete, present a **combined summary**: a brief recap of all answers with any cross-cutting insights the agent notices across results.

#### Error handling

If a subagent fails (bad SQL, no results, ambiguous metadata match):

- Report the error alongside successful results.
- Offer to retry the failed question interactively in the current session (using the normal Phase 3 query loop).

After all results are presented, return to the normal Phase 3 query loop for further questions.
```

**Step 2: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat: add parallel subagent dispatch to query skill"
```

---

### Task 4: Update Phase 3 Hard Gates for Multi-Query Support

**Files:**
- Modify: `plugin/skills/query/SKILL.md:163-193` (time dimension hard gate) and `plugin/skills/query/SKILL.md:216-218` (execution consent hard gate)

**Step 1: Update the time dimension hard gate**

Change:

```markdown
<HARD-GATE>
**You MUST ask about the time dimension before building any query, unless the user has previously chosen "don't ask again" for both questions. Two sequential questions — ask one, wait for answer, then ask the next.**
</HARD-GATE>
```

To:

```markdown
<HARD-GATE>
**You MUST ask about the time dimension before building any query, unless the user has previously chosen "don't ask again" for both questions, OR the time dimension was already answered in the Multi-Query Flow (Phase 3B Step 2). Two sequential questions — ask one, wait for answer, then ask the next.**
</HARD-GATE>
```

**Step 2: Update the execution consent hard gate**

Change:

```markdown
<HARD-GATE>
**You MUST ask the user for permission before executing any query. Do NOT run queries without explicit consent unless the user has previously chosen "yes, don't ask again".**
</HARD-GATE>
```

To:

```markdown
<HARD-GATE>
**You MUST ask the user for permission before executing any query. Do NOT run queries without explicit consent unless the user has previously chosen "yes, don't ask again", OR execution was pre-approved in the Multi-Query Flow (Phase 3B Step 4A/4B).**
</HARD-GATE>
```

**Step 3: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat: update hard gates to support multi-query pre-answered choices"
```

---

### Task 5: Bump Plugin Version

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`

**Step 1: Read the current version**

Read `plugin/.claude-plugin/plugin.json` and note the current version.

**Step 2: Bump the minor version**

Increment the minor version (e.g., `1.5.0` → `1.6.0`).

**Step 3: Commit**

```bash
git add plugin/.claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 1.6.0"
```

---

### Task 6: Verify the Complete SKILL.md

**Step 1: Read the full SKILL.md**

Read `plugin/skills/query/SKILL.md` end-to-end and verify:

- Multi-Question Detection section exists between Post-Bootstrap Greeting and Phase 3
- Phase 3B section exists with all steps (confirm, time dimension, execution mode, sequential, parallel)
- Parallel Subagent Dispatch section exists with prompt construction, result presentation, and error handling
- Phase 3 hard gates have the skip clauses for multi-query flow
- No duplicate sections or broken references
- The flow is coherent: Phase 1 → Phase 2 → Detection → Phase 3 (single) or Phase 3B (multi) → Phase 4

**Step 2: Fix any issues found**

If anything is off, fix it and commit:

```bash
git add plugin/skills/query/SKILL.md
git commit -m "fix: correct SKILL.md structure after parallel queries additions"
```
