# daana-modeler

daana-modeler is a Claude Code plugin for the Daana data platform. It provides three skills for building and querying DMDL data models.

## Repository Structure

- **`.claude-plugin/`** — Marketplace manifest
  - `marketplace.json` — Marketplace catalog for plugin discovery
- **`plugin/`** — Distributable plugin contents
  - `.claude-plugin/plugin.json` — Plugin metadata (name: `daana`)
  - `skills/model/SKILL.md` — Model interview skill (`/daana-model`)
  - `skills/map/SKILL.md` — Mapping interview skill (`/daana-map`)
  - `skills/query/SKILL.md` — Data query skill (`/daana-query`)
  - `references/` — Shared DMDL schema, examples, and source schema formats
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans
