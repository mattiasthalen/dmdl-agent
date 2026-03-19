# Design: Prevent Direct Commits to Main

## Problem

Direct commits to `main` are not allowed per project policy, but there is no automated enforcement. This relies on developer discipline alone.

## Solution

A git pre-commit hook that rejects commits on `main`, installed via a Makefile target.

## Components

### 1. `hooks/pre-commit`

Shell script that checks the current branch name. If it's `main`, the commit is aborted with a clear error message suggesting the developer create a feature branch. Can be bypassed with `git commit --no-verify` if truly needed.

### 2. `Makefile`

A `make install-hooks` target that copies the hook into `.git/hooks/` and ensures it's executable.

### 3. `CONTRIBUTING.md`

Setup instructions for contributors, including running `make install-hooks` after cloning.

## File Structure

```
hooks/
  pre-commit
Makefile
CONTRIBUTING.md
```
