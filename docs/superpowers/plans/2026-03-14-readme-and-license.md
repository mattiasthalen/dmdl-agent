# README and License Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user-facing README.md and MIT LICENSE file, and trim CLAUDE.md to agent-only content.

**Architecture:** Three static file changes — no code, no tests. Create LICENSE and README.md at repo root, then edit CLAUDE.md to remove human-facing content that moves to the README.

**Tech Stack:** Markdown, shields.io badges

**Spec:** `docs/superpowers/specs/2026-03-14-readme-and-license-design.md`

---

## Chunk 1: All Tasks

### Task 1: Create LICENSE file

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Create the MIT LICENSE file**

Write standard MIT license text to `/workspaces/daana-modeler/LICENSE`:

```text
MIT License

Copyright (c) 2026 Mattias Thalén

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Commit**

```bash
git add LICENSE
git commit -m "chore: add MIT license"
```

---

### Task 2: Create README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

Write to `/workspaces/daana-modeler/README.md`:

```markdown
# daana-modeler

A Claude Code skill that interviews you to build DMDL model files.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built_for-Claude_Code-6f42c1.svg)](https://docs.anthropic.com/en/docs/claude-code)

## What It Does

`/daana` is a slash command for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that walks you through an interactive interview to define business entities, attributes, and relationships — then generates a valid DMDL `model.yaml` file. Learn more about Daana and DMDL at [docs.daana.dev](https://docs.daana.dev).

## Installation

**As a Claude Code plugin** (recommended):

```bash
claude plugin add https://github.com/mattiasthalen/daana-modeler
```

**As a local skill:**

Copy the `skills/daana/` directory into your project's `.claude/skills/` directory.

## Usage

Run the `/daana` slash command in Claude Code. The skill will interview you to define your data model step by step, then write a `model.yaml` file to your project.

## Documentation

- [Daana CLI](https://docs.daana.dev) — Daana CLI documentation
- [DMDL Specification](https://docs.daana.dev/dmdl) — DMDL language reference

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

### Task 3: Trim CLAUDE.md to agent-only content

**Files:**
- Modify: `CLAUDE.md`

The current CLAUDE.md has four sections: project description, Repository Structure, How to Test, and Documentation. The "How to Test" and "Documentation" sections are human-facing and now live in the README. Keep the project description and Repository Structure (useful agent context). Remove the rest.

- [ ] **Step 1: Edit CLAUDE.md**

Replace the full contents of `/workspaces/daana-modeler/CLAUDE.md` with:

```markdown
# daana-modeler

daana-modeler is a Claude Code skill (`/daana`) that interviews users to build DMDL model.yaml files for the Daana data platform.

## Repository Structure

- **`skills/daana/`** — Main skill deliverable with the `/daana` slash command
  - `SKILL.md` — Skill documentation
  - `references/` — DMDL schema and examples
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "chore: trim CLAUDE.md to agent-only content"
```
