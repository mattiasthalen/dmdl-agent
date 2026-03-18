# Direct psql Connection Design

**Date:** 2026-03-18
**Status:** Approved

## Goal

Replace docker exec with direct psql in `/daana-query`. No new skill needed.

## Context

The query skill currently connects to PostgreSQL via `docker exec <container> psql ...`, requiring a running Docker container. This is limiting — users may run Postgres natively, on a remote host, or in managed cloud services. Direct psql is simpler, more portable, and eliminates the Docker dependency.

## Design

### Connection Phase Changes (`SKILL.md`)

The query skill's connection phase becomes:

1. Glob for `connections.yaml`, parse profiles, let user pick
2. Only proceed with `postgresql` type profiles
3. Check if `psql` is on PATH
4. If not found, auto-detect platform and ask user if it should install:
   - **macOS:** `brew install libpq`
   - **Debian/Ubuntu:** `sudo apt install postgresql-client`
   - **Fedora/RHEL:** `sudo dnf install postgresql`
   - **Windows:** `winget install PostgreSQL.PostgreSQL`
5. Hard gate: cannot proceed without psql
6. Resolve `${VAR_NAME}` password references from environment
7. Run connectivity test via `SELECT 1`

### Execution Command (`dialect-postgres.md`)

All queries run via direct psql:

```bash
PGPASSWORD=<pwd> psql -h <host> -p <port> -U <user> -d <database> -P pager=off --csv -c "<SQL>"
```

No `-it` flags. Always include `-P pager=off --csv`.

### Removed

- All `container` field handling in connections schema
- Docker-compose auto-detection logic
- `docker exec` command pattern

### Cleanup

- Delete `plugin/references/` directory (redundant — each skill owns its reference files)
- Update `CLAUDE.md` repo structure section (remove `references/` mention)

## Files Changed

| File | Change |
|------|--------|
| `plugin/skills/query/SKILL.md` | Update connection phase: psql detection + install, remove docker/container logic |
| `plugin/skills/query/dialect-postgres.md` | Replace docker exec with direct psql, remove container resolution, add psql install section |
| `plugin/skills/query/connections.md` | Remove `container` field and docker exec note |
| `plugin/references/` | Delete entire directory |
| `CLAUDE.md` | Remove `references/` from repo structure |
| `plugin/.claude-plugin/plugin.json` | Version bump |
