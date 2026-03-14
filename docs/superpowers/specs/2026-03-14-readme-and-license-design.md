# README and License Design Spec

**Date:** 2026-03-14
**Status:** Implemented

## Overview

Add a user-facing README.md and MIT LICENSE file to the daana-modeler repository.

## Audience

Developers who want to use the `/daana` Claude Code skill to build DMDL model files.

## LICENSE

- **License:** MIT
- **Copyright:** 2026 Mattias Thalén
- **Rationale:** Permissive and simple. The project may be donated to Daana (whose CLI uses Elastic License 2.0) in the future. As the sole contributor, Mattias can re-license upon donation without friction.
- **File:** Standard MIT license text at `/LICENSE`

## README.md Structure

### 1. Title + Tagline

Project name `daana-modeler` as an H1, followed by a one-line description of what it is: a Claude Code skill that interviews you to build DMDL model files.

### 2. Badges

- MIT license badge (shields.io, linking to LICENSE file)
- "Built for Claude Code" badge

### 3. What It Does

2-3 sentences explaining:
- It's a `/daana` slash command for Claude Code
- It interviews you to define business entities, attributes, and relationships
- It generates valid DMDL `model.yaml` files

Link to [docs.daana.dev](https://docs.daana.dev) for more on Daana and DMDL.

### 4. Installation

Primary path: install as a Claude Code plugin via the repository URL.

Secondary path: copy `skills/daana/` into a project's `.claude/skills/` directory.

### 5. Usage

- Invoke `/daana` in Claude Code
- Brief description: the skill walks you through an interview to define your data model, then writes a `model.yaml` file

### 6. Documentation

Links to:
- [docs.daana.dev](https://docs.daana.dev) — Daana CLI documentation
- [docs.daana.dev/dmdl](https://docs.daana.dev/dmdl) — DMDL specification

### 7. License

One-liner: "This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details."

## CLAUDE.md Changes

CLAUDE.md currently contains "How to Test", "Repository Structure", and "Documentation" sections that overlap with the README. Since CLAUDE.md is an agent-facing file and README is human-facing, CLAUDE.md will be trimmed to agent-only instructions (project description, repo structure for context, and any agent-specific guidance). Human-facing content like installation steps and external doc links moves to the README.

## What's NOT Included

- No contributor guide or CONTRIBUTING.md (audience is users, not contributors)
- No changelog
- No CI/CD badge (`.github/` only contains dependabot config, no workflows)
- No logo or banner image
