# Prevent Direct Commits to Main — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent direct commits to `main` branch via a git pre-commit hook, installable through a Makefile.

**Architecture:** A shell-based pre-commit hook stored in `hooks/`, installed to `.git/hooks/` via `make install-hooks`. Setup documented in `CONTRIBUTING.md`.

**Tech Stack:** Shell (bash), Make

---

### Task 1: Create the pre-commit hook

**Files:**
- Create: `hooks/pre-commit`

**Step 1: Create the hook script**

```bash
#!/usr/bin/env bash

branch="$(git symbolic-ref --short HEAD 2>/dev/null)"

if [ "$branch" = "main" ]; then
  echo "Error: Direct commits to main are not allowed."
  echo "Create a feature branch first:"
  echo "  git checkout -b feat/my-feature"
  exit 1
fi
```

**Step 2: Make the hook executable**

Run: `chmod +x hooks/pre-commit`

**Step 3: Commit**

```bash
git add hooks/pre-commit
git commit -m "feat: add pre-commit hook to prevent commits on main"
```

---

### Task 2: Create the Makefile

**Files:**
- Create: `Makefile`

**Step 1: Create the Makefile**

```makefile
.PHONY: install-hooks

install-hooks:
	cp hooks/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "Git hooks installed."
```

**Step 2: Test it**

Run: `make install-hooks`
Expected: "Git hooks installed." and `.git/hooks/pre-commit` exists and is executable.

**Step 3: Verify the hook works**

Run (on main): `git commit --allow-empty -m "test: should be blocked"`
Expected: Error message and commit is rejected.

**Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile with install-hooks target"
```

---

### Task 3: Create CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

**Step 1: Create the file**

```markdown
# Contributing

## Setup

After cloning the repository, install the git hooks:

```bash
make install-hooks
```

This installs a pre-commit hook that prevents direct commits to `main`. All changes should go through feature branches and pull requests.
```

**Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING.md with setup instructions"
```

---

### Task 4: Install hooks and verify end-to-end

**Step 1: Run install**

Run: `make install-hooks`
Expected: "Git hooks installed."

**Step 2: Verify hook blocks commits on main**

Run: `git commit --allow-empty -m "test: should fail"`
Expected: Rejected with "Error: Direct commits to main are not allowed."

**Step 3: Verify hook allows commits on feature branches**

Run: `git checkout -b test/verify-hook && git commit --allow-empty -m "test: should succeed"`
Expected: Commit succeeds.

**Step 4: Clean up test branch**

Run: `git checkout main && git branch -D test/verify-hook`
