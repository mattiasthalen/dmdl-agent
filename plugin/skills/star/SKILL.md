---
name: daana-star
description: Generate traditional star schema SQL (fact tables + dimension tables) from a Focal-based Daana data warehouse.
---

# Daana Star Schema Generator

> **Status:** Skeleton — full implementation deferred to a future design spec.

This skill generates traditional star schema DDL (fact tables and dimension tables) from a Focal-based Daana data warehouse.

## Phases

1. **Bootstrap** — Dispatch the focal agent to connect and bootstrap metadata.
2. **Interview** — Classify entities as facts or dimensions, select SCD types, choose materialization.
3. **Generate** — Produce SQL files for fact tables and dimension tables.
4. **Handover** — Offer to execute DDL or suggest `/daana-query`.

## References

- `${CLAUDE_SKILL_DIR}/references/dimension-patterns.md` — SCD types 0-6, mixed types, design considerations.
- `${CLAUDE_SKILL_DIR}/references/fact-patterns.md` — Transaction, periodic snapshot, accumulating snapshot, factless facts.
