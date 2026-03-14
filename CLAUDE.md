# daana-modeler

daana-modeler is a Claude Code skill (`/daana`) that interviews users to build DMDL model.yaml files for the Daana data platform.

## Repository Structure

- **`skills/daana/`** — Main skill deliverable with the `/daana` slash command
  - `SKILL.md` — Skill documentation
  - `references/` — DMDL schema and examples
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans

## How to Test

1. **As a plugin:** Install this repository as a plugin in Claude Code
2. **As a local skill:** Copy `skills/daana/` into a daana project's `.claude/skills/` directory
3. **Invoke:** Use `/daana` slash command to start the interviewer

## Documentation

- **Daana CLI:** [docs.daana.dev](https://docs.daana.dev)
- **DMDL Specification:** [docs.daana.dev/dmdl](https://docs.daana.dev/dmdl)
