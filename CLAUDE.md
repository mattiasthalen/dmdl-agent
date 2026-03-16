# daana-modeler

daana-modeler is a Claude Code plugin for the Daana data platform. It provides three skills for building and querying DMDL data models.

## Repository Structure

- **`.claude-plugin/`** — Plugin manifest
  - `plugin.json` — Plugin metadata (name: `daana`)
  - `marketplace.json` — Marketplace catalog for plugin discovery
- **`skills/model/`** — Model interview skill (`/daana-model`)
  - `SKILL.md` — Builds model.yaml via interactive interview
- **`skills/map/`** — Mapping interview skill (`/daana-map`)
  - `SKILL.md` — Builds mapping files via interactive interview
- **`skills/query/`** — Data query skill (`/daana-query`)
  - `SKILL.md` — Answers natural language questions about data via live SQL
- **`references/`** — Shared DMDL schema, examples, and source schema formats
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
