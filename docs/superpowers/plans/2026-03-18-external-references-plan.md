# External References Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a gitignored `external/` folder with a tracked lockfile and setup script so contributors can clone private reference repos at pinned commits.

**Architecture:** A JSON lockfile (`external.lock`) tracks repo URLs and pinned SHAs. A bash script (`scripts/setup-external.sh`) reads the lockfile and clones/updates repos into `external/`. The `external/` directory is gitignored so cloned repos are never committed.

**Tech Stack:** Bash, jq (for JSON parsing), git

---

### Task 1: Add `external/` to `.gitignore`

**Files:**
- Modify: `.gitignore`

**Step 1: Add the gitignore entry**

Append to `.gitignore`:

```
external/
```

**Step 2: Verify**

Run: `cat .gitignore`
Expected: `external/` appears in the file alongside existing entries.

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore external/ directory"
```

---

### Task 2: Create `external.lock`

**Files:**
- Create: `external.lock`

**Step 1: Create the lockfile with pinned SHAs**

```json
{
  "repos": [
    {
      "name": "teach_claude_focal",
      "url": "git@github.com:PatrikLager/teach_claude_focal.git",
      "commit": "d49cb259e02de9f989298902b95b37a73ab7edf3"
    },
    {
      "name": "daana-cli",
      "url": "git@github.com:daana-code/daana-cli.git",
      "commit": "1b9a55be4d69597c5ac2ec375c88c07130da7513"
    }
  ]
}
```

**Step 2: Validate JSON**

Run: `cat external.lock | jq .`
Expected: Pretty-printed JSON without errors.

**Step 3: Commit**

```bash
git add external.lock
git commit -m "chore: add external.lock with pinned reference repos"
```

---

### Task 3: Create `scripts/setup-external.sh`

**Files:**
- Create: `scripts/setup-external.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCKFILE="$ROOT_DIR/external.lock"
EXTERNAL_DIR="$ROOT_DIR/external"

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Install it with your package manager."
  exit 1
fi

if [ ! -f "$LOCKFILE" ]; then
  echo "Error: $LOCKFILE not found."
  exit 1
fi

mkdir -p "$EXTERNAL_DIR"

repo_count=$(jq '.repos | length' "$LOCKFILE")

for i in $(seq 0 $((repo_count - 1))); do
  name=$(jq -r ".repos[$i].name" "$LOCKFILE")
  url=$(jq -r ".repos[$i].url" "$LOCKFILE")
  commit=$(jq -r ".repos[$i].commit" "$LOCKFILE")
  target="$EXTERNAL_DIR/$name"

  echo "--- $name ---"

  if [ -d "$target/.git" ]; then
    echo "Fetching updates..."
    git -C "$target" fetch --quiet
  else
    echo "Cloning..."
    git clone --no-recurse-submodules --quiet "$url" "$target"
  fi

  echo "Checking out $commit..."
  git -C "$target" checkout --quiet "$commit"

  actual=$(git -C "$target" rev-parse HEAD)
  echo "Pinned at: $actual"
  echo ""
done

echo "All external repos are set up."
```

**Step 2: Make executable**

Run: `chmod +x scripts/setup-external.sh`

**Step 3: Test the script**

Run: `./scripts/setup-external.sh`
Expected: Both repos cloned into `external/`, checked out at pinned commits, summary printed.

**Step 4: Verify repos are gitignored**

Run: `git status`
Expected: `external/` does NOT appear in untracked files.

**Step 5: Commit**

```bash
git add scripts/setup-external.sh
git commit -m "feat: add setup script for external reference repos"
```

---

### Task 4: Add external references section to README

**Files:**
- Modify: `README.md`

**Step 1: Add section before the License section**

Add this after the Documentation section and before the License section:

```markdown
## Development Setup

This project references private repos for development. To clone them locally:

```bash
./scripts/setup-external.sh
```

This reads `external.lock` and clones the pinned versions into `external/` (gitignored). Requires `jq` and SSH access to the referenced repos.
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add development setup section for external repos"
```

---

### Task 5: Bump plugin version

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`

**Step 1: Bump the patch version**

Read `plugin/.claude-plugin/plugin.json` and increment the version number.

**Step 2: Commit**

```bash
git add plugin/.claude-plugin/plugin.json
git commit -m "chore: bump plugin version"
```
