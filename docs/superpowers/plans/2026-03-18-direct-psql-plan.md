# Direct psql Connection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace docker exec with direct psql in the query skill, add psql detection/install guidance, and clean up obsolete references.

**Architecture:** Update the query skill's dialect and connections references to use direct `psql` with `PGPASSWORD`. Add platform-aware psql detection to the SKILL.md connection phase. Remove the `plugin/references/` directory.

**Tech Stack:** Markdown (SKILL.md, dialect, connections docs), YAML (plugin.json)

---

### Task 1: Update dialect-postgres.md — replace docker exec with direct psql

**Files:**
- Modify: `plugin/skills/query/dialect-postgres.md`

**Step 1: Replace the Connection section (lines 1–24)**

Replace the entire `## Connection` section with:

```markdown
## Connection

### Via connections.yaml

Extract `host`, `port`, `user`, `database`, `password`, and `sslmode` from the chosen profile.

### psql detection

Check if `psql` is available:

1. Run `which psql` (Linux/macOS) or `where psql` (Windows) via the Bash tool
2. If found, confirm with `psql --version` and proceed
3. If not found, detect the platform and ask the user if you should install it:

Call the `AskUserQuestion` tool (do NOT print the question as text):

- Question: "psql is not installed. Want me to install it?"
- Options: "Yes" / "No"

If yes, detect the platform and run the appropriate command:

| Platform | Command |
|----------|---------|
| macOS (Homebrew) | `brew install libpq && brew link --force libpq` |
| Debian/Ubuntu | `sudo apt install postgresql-client` |
| Fedora/RHEL | `sudo dnf install postgresql` |
| Windows | `winget install PostgreSQL.PostgreSQL` |

After install, re-check `which psql` / `where psql` to confirm.

**Hard gate:** Cannot proceed without `psql` on PATH.

### Execution command

All queries run via direct `psql`:

` ` `bash
PGPASSWORD=<password> psql -h <host> -p <port> -U <user> -d <database> -P pager=off --csv -c "<SQL>"
` ` `

- `<password>`: from profile. If it uses `${VAR_NAME}` syntax, pass it through — the shell resolves it at execution time.
- `<sslmode>`: if set in profile, add `sslmode=<value>` to the command via the `PGSSLMODE` env var: `PGSSLMODE=<sslmode> PGPASSWORD=<password> psql ...`
- **Important:** Never use `-it` flags — Claude Code's Bash tool has no interactive TTY. Always include `-P pager=off --csv`.

### Connectivity check

` ` `bash
PGPASSWORD=<password> psql -h <host> -p <port> -U <user> -d <database> -P pager=off --csv -c "SELECT 1"
` ` `
```

**Step 2: Verify the rest of the file is unchanged**

Lines 26–99 (Bootstrap Query, SQL Syntax, Relationship table columns) remain exactly as they are.

**Step 3: Commit**

```bash
git add plugin/skills/query/dialect-postgres.md
git commit -m "feat: replace docker exec with direct psql in dialect-postgres"
```

---

### Task 2: Update connections.md — remove container field and docker exec note

**Files:**
- Modify: `plugin/skills/query/connections.md`

**Step 1: Remove `container` from Optional Fields table (line 36)**

Remove this row from the Optional Fields table:

```
| `container` | string | Docker container name (used by dialect for `docker exec`) |
```

**Step 2: Remove `container` from the YAML example (line 50)**

Remove this line from the example:

```yaml
    container: "daana-test-customerdb"
```

**Step 3: Remove the docker exec note (lines 53)**

Remove:

```markdown
> **Note:** The current query skill connects via `docker exec` into the database container. A future version will use a proper client connection (e.g., `psql` or a native driver) instead, making the `container` field unnecessary.
```

**Step 4: Commit**

```bash
git add plugin/skills/query/connections.md
git commit -m "feat: remove container field and docker exec note from connections schema"
```

---

### Task 3: Update SKILL.md — revise connection phase

**Files:**
- Modify: `plugin/skills/query/SKILL.md`

**Step 1: Remove Step 5 (Gather dialect-specific details) — lines 92–94**

Delete the entire Step 5 section:

```markdown
### Step 5 — Gather dialect-specific details

The dialect file specifies what additional information is needed (e.g., Docker container name for PostgreSQL). Check the connection profile first — only ask the user for details that are missing from it.
```

This step existed solely for the docker container name. The dialect file now handles psql detection directly.

**Step 2: Renumber Step 6 to Step 5**

Rename `### Step 6 — Validate connectivity` to `### Step 5 — Validate connectivity`. Keep its content the same.

**Step 3: Commit**

```bash
git add plugin/skills/query/SKILL.md
git commit -m "feat: remove dialect-specific details step from connection phase"
```

---

### Task 4: Delete plugin/references/ directory

**Files:**
- Delete: `plugin/references/` (entire directory — 8 files)

**Step 1: Verify no skill references this path**

Search for `references/` in all SKILL.md files to confirm nothing imports from `plugin/references/`. Skills use `${CLAUDE_SKILL_DIR}/` to reference their own local copies.

**Step 2: Delete the directory**

```bash
rm -rf plugin/references/
```

**Step 3: Commit**

```bash
git add -A plugin/references/
git commit -m "chore: remove redundant plugin/references directory"
```

---

### Task 5: Update CLAUDE.md — remove references/ from repo structure

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Remove the references line (line 14)**

Remove:

```markdown
  - `references/` — Shared DMDL schema, examples, and source schema formats
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: remove references/ from repo structure"
```

---

### Task 6: Bump plugin version

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`

**Step 1: Bump version from 1.4.0 to 1.5.0**

Change:

```json
"version": "1.4.0"
```

To:

```json
"version": "1.5.0"
```

**Step 2: Commit**

```bash
git add plugin/.claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 1.5.0"
```
