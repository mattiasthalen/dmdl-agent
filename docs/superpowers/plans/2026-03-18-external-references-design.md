# External References Design

## Problem

daana-modeler needs local access to private reference repos (`teach_claude_focal`, `daana-cli`) for development. These cannot be git submodules because the Claude marketplace install recursively clones submodules, and these repos are private.

## Decision

Gitignored `external/` folder with a tracked lockfile and setup script. No `.gitmodules` file.

## Structure

```
external/                  ← gitignored (cloned repos live here)
external.lock              ← tracked, records repo URLs + pinned SHAs
scripts/setup-external.sh  ← tracked, clones/updates repos to pinned commits
```

## `external.lock` format

```json
{
  "repos": [
    {
      "name": "teach_claude_focal",
      "url": "git@github.com:PatrikLager/teach_claude_focal.git",
      "commit": "<sha>"
    },
    {
      "name": "daana-cli",
      "url": "git@github.com:daana-code/daana-cli.git",
      "commit": "<sha>"
    }
  ]
}
```

## `scripts/setup-external.sh` behavior

1. Read `external.lock`
2. For each repo: if not cloned, `git clone --no-recurse-submodules`; if already cloned, `git fetch`
3. Checkout the pinned commit
4. Print status summary

## `.gitignore` addition

```
external/
```

## README addition

Short section explaining `external/` and how to run the setup script.

## Constraints

- No `.gitmodules` file — marketplace install would try to clone private repos
- Repos are private — contributors need SSH access
- Reference-only — no modifications to external repos from this project
