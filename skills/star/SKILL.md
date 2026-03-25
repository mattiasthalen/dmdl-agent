---
name: daana-star
description: Generate traditional star schema SQL (fact tables + dimension tables) from a Focal-based Daana data warehouse.
allowed-tools: ["Read"]
---

# Daana Star Schema Generator

**REQUIRED SUB-SKILL:** Use daana:focal

Apply that foundational understanding before proceeding. If focal context is already present in this conversation (bootstrap metadata visible above), skip the focal invocation.

> **Status:** Skeleton — full implementation deferred to a future design spec.

This skill generates traditional star schema DDL (fact tables and dimension tables) from a Focal-based Daana data warehouse.

The focal skill establishes the database connection and bootstraps metadata. Once focal completes, the session flows through the phases below.

## Phases

1. **Interview** — Classify entities as facts or dimensions, select SCD types, choose materialization.
2. **Generate** — Produce SQL files for fact tables and dimension tables.
3. **Handover** — Offer to execute DDL or suggest `/daana-query`.

## References

- @references/dimension-patterns.md — SCD types 0-6, mixed types, design considerations.
- @references/fact-patterns.md — Transaction, periodic snapshot, accumulating snapshot, factless facts.
