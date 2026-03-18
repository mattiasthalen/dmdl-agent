# Query Skill Modularization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the monolithic query SKILL.md into a lean workflow file plus on-demand supporting files, eliminating upfront permission prompts and separating concerns.

**Architecture:** SKILL.md becomes the workflow orchestrator (~150 lines). Reference content moves to sibling files (`connections.md`, `focal-framework.md`, `dialect-postgres.md`) in the same skill directory. Claude reads them via `${CLAUDE_SKILL_DIR}` only when needed. Dialect is resolved dynamically from the connection type.

**Tech Stack:** Claude Code plugin skills with supporting files

---

### Task 1: Create `connections.md` supporting file

**Files:**
- Create: `plugin/skills/query/connections.md`

**Step 1: Create the file**

Use the existing `plugin/references/connections-schema.md` as the base. Copy it to `plugin/skills/query/connections.md` as-is — it already has the right content (profile schema, supported types, example YAML, validation commands).

```markdown
# Connections Schema

Connection profiles are defined in `connections.yaml`. Each profile is a named entry under the `connections` key.

Documentation: https://docs.daana.dev/dmdl/connections

## Supported Types

| Type | Status |
|---|---|
| `postgresql` | Supported |
| `bigquery` | Not yet supported in query skill |
| `mssql` | Not yet supported in query skill |
| `oracle` | Not yet supported in query skill |
| `snowflake` | Not yet supported in query skill |

## PostgreSQL Profile

### Required Fields

| Field | Type | Description |
|---|---|---|
| `type` | string | Must be `"postgresql"` |
| `host` | string | Database server hostname |
| `port` | integer | Default: 5432 |
| `user` | string | Database username |
| `database` | string | Database name |

### Optional Fields

| Field | Type | Description |
|---|---|---|
| `password` | string | Use `${VAR_NAME}` for env var interpolation |
| `sslmode` | string | Default: `"disable"` |
| `target_schema` | string | Schema for Daana output (e.g., `daana_dw`) |

### Example

```yaml
connections:
  dev:
    type: "postgresql"
    host: "localhost"
    port: 5432
    user: "dev"
    password: "${DEV_PASSWORD}"
    database: "customerdb"
    target_schema: "daana_dw"
```

## Validation

```bash
daana-cli check connections
daana-cli check connections --connection dev
```
```

**Step 2: Commit**

```bash
git add plugin/skills/query/connections.md
git commit -m "refactor: extract connections schema to query skill supporting file"
```

---

### Task 2: Create `focal-framework.md` supporting file

**Files:**
- Create: `plugin/skills/query/focal-framework.md`

**Step 1: Create the file**

Copy `plugin/references/focal-framework.md` to `plugin/skills/query/focal-framework.md`. This is the full 326-line Focal reference — table types, TYPE_KEY semantics, Atomic Context, lineage tracing, metadata chain. It's needed in full for building correct queries.

**Step 2: Commit**

```bash
git add plugin/skills/query/focal-framework.md
git commit -m "refactor: extract focal framework reference to query skill supporting file"
```

---

### Task 3: Create `dialect-postgres.md` supporting file

**Files:**
- Create: `plugin/skills/query/dialect-postgres.md`

**Step 1: Create the file**

Copy `plugin/references/dialect-postgres.md` to `plugin/skills/query/dialect-postgres.md`. This already contains connection extraction, execution command, bootstrap query, SQL syntax (QUALIFY alternative, carry-forward, type casting), statement timeout, and relationship table column rules.

**Step 2: Commit**

```bash
git add plugin/skills/query/dialect-postgres.md
git commit -m "refactor: extract postgres dialect to query skill supporting file"
```

---

### Task 4: Rewrite SKILL.md as workflow orchestrator

**Files:**
- Modify: `plugin/skills/query/SKILL.md`

**Step 1: Rewrite SKILL.md**

Remove all inlined reference content. Keep only the workflow logic. Add `${CLAUDE_SKILL_DIR}` read instructions at the right phase boundaries. The new SKILL.md should contain:

1. **Header** — role description, phase overview
2. **Scope** — read-only rules (keep as-is)
3. **Adaptive Behavior** — keep as-is
4. **Phase 1: Connection**
   - Search for `connections.yaml` (find command, up to 3 levels deep)
   - Instruction: `Read ${CLAUDE_SKILL_DIR}/connections.md for the profile schema`
   - Remove the inlined profile schema table
   - Keep: single-profile vs multi-profile AskUserQuestion logic
   - Keep: extract connection details, Docker container question, manual fallback
   - Keep: validate connectivity
   - **Dialect resolution** — after determining connection type from profile:
     - Try to read `${CLAUDE_SKILL_DIR}/dialect-<type>.md`
     - If found → use it
     - If not found → AskUserQuestion: "No native support for [type] yet. I can try translating from PostgreSQL patterns, but results may need tweaking. Want me to try?" Options: "Yes, try transpiling" / "No, cancel"
     - If transpiling → read `${CLAUDE_SKILL_DIR}/dialect-postgres.md` as reference
5. **Phase 2: Bootstrap**
   - Instruction: `Read ${CLAUDE_SKILL_DIR}/focal-framework.md and the dialect file before proceeding`
   - Keep: bootstrap consent (AskUserQuestion)
   - Remove: inlined bootstrap query (it's in the dialect file)
   - Instruction: `Run the bootstrap query from the dialect file`
   - Keep: bootstrap interpretation table (column meanings)
   - Keep: relationship table detection rule
   - Keep: bootstrap failure messages
   - Keep: post-bootstrap greeting
6. **Phase 3: Query Loop**
   - Keep: matching user questions to metadata
   - Keep: query patterns (these are generic, not dialect-specific)
   - Remove: inlined QUALIFY alternative and carry-forward SQL (they're in the dialect file)
   - Update Pattern 4 to say: `Use the QUALIFY alternative and carry-forward pattern from the dialect file`
   - Keep: ROW_ST filtering rules
   - Keep: lineage tracing (reference focal-framework.md for details)
   - Keep: safety guardrails
   - Keep: execution consent (AskUserQuestion)
   - Remove: inlined execution command (it's in the dialect file)
   - Instruction: `Execute using the command from the dialect file`
   - Keep: result presentation
   - Keep: conversation behavior
7. **Phase 4: Handover** — keep as-is

**Step 2: Verify line count**

The resulting SKILL.md should be roughly 150 lines. If significantly over, look for content that belongs in a supporting file.

**Step 3: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "refactor: slim down query SKILL.md to workflow orchestrator with on-demand references"
```

---

### Task 5: Bump plugin version

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`

**Step 1: Bump version**

Change `"version": "1.3.1"` to `"version": "1.3.2"`.

**Step 2: Commit**

```bash
git add plugin/.claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 1.3.2"
```

---

### Task 6: Manual testing

**Step 1: Test the skill**

Run `/daana-query` in a project with a `connections.yaml` and verify:

1. No permission prompts at startup
2. `connections.md` is read during connection phase
3. Dialect file is read after connection type is determined
4. `focal-framework.md` is read before first query
5. Bootstrap query comes from the dialect file
6. Query patterns work correctly
7. AskUserQuestion prompts render for all consent gates

**Step 2: Test missing dialect**

Temporarily change the profile type to `bigquery` and verify the transpile AskUserQuestion appears.
