# daana-modeler

daana-modeler is a Claude Code plugin for the Daana data platform. It provides three skills for building and querying DMDL data models.

## Repository Structure

- **`.claude-plugin/`** — Marketplace manifest
  - `marketplace.json` — Marketplace catalog for plugin discovery
- **`plugin/`** — Distributable plugin contents
  - `.claude-plugin/plugin.json` — Plugin metadata (name: `daana`)
  - `skills/model/SKILL.md` — Model interview skill (`/daana-model`)
  - `skills/model/references/` — Model schema, examples, source format references
  - `skills/map/SKILL.md` — Mapping interview skill (`/daana-map`)
  - `skills/map/references/` — Mapping schema, examples, source format references
  - `skills/query/SKILL.md` — Data query skill (`/daana-query`)
  - `skills/query/references/` — Focal framework, bootstrap, query patterns, dimension/fact patterns, dialect, connections
- **`docs/superpowers/specs/`** — Design specifications
- **`docs/superpowers/plans/`** — Implementation plans

## External References

- `external.lock` pins upstream repos. When exploring project context (e.g., start of brainstorming), fresh-clone each repo and compare HEAD against the pinned commit to detect new upstream changes.
