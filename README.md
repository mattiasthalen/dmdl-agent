# daana-modeler

A Claude Code plugin that interviews you to build DMDL model and mapping files, and query your data warehouse.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built_for-Claude_Code-6f42c1.svg)](https://docs.anthropic.com/en/docs/claude-code)

## What It Does

daana-modeler is a plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that provides three skills:

- **`/daana:model`** — Interactive interview to define business entities, attributes, and relationships, generating a valid DMDL `model.yaml` file.
- **`/daana:map`** — Interactive interview to map source tables to model entities, generating DMDL mapping files.
- **`/daana:query`** — Natural language data agent that answers questions about your Focal-based Daana data warehouse via live SQL queries.

Learn more about Daana and DMDL at [docs.daana.dev](https://docs.daana.dev).

## Installation

```bash
claude plugin install https://github.com/mattiasthalen/daana-modeler
```

## Usage

Run any of the skills as slash commands in Claude Code:

- `/daana:model` — Start building your data model
- `/daana:map` — Create source-to-model mappings
- `/daana:query` — Query your data warehouse

Each skill can hand you over to the next logical step when it completes.

## Documentation

- [Daana CLI](https://docs.daana.dev) — Daana CLI documentation
- [DMDL Specification](https://docs.daana.dev/dmdl) — DMDL language reference

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
