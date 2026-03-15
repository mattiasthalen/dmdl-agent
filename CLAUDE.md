# daana-modeler

daana-modeler is a suite of Claude Code skills for the Daana data platform. The `/daana` entrypoint orchestrates model and mapping creation.

## Repository Structure

- **`skills/daana/`** — Orchestrator skill (`/daana` entrypoint)
  - `SKILL.md` — Routes to sub-skills based on project state
  - `references/` — Shared DMDL schema, examples, and source schema formats
- **`skills/daana-model/`** — Model interview skill (`/daana-model`)
  - `SKILL.md` — Builds model.yaml via interactive interview
- **`skills/daana-mapping/`** — Mapping interview skill (`/daana-mapping`)
  - `SKILL.md` — Builds mapping files via interactive interview
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
