# Skill Test Fixtures — Design Spec

**Date:** 2026-03-26
**Issue:** #49
**Approach:** Markdown test fixtures with mocked bootstrap context and expected SQL output

## Context

The query, USS, and star skills generate SQL from Focal bootstrap metadata. Currently there's no way to verify their output is correct without manual testing against a live database. We need test fixtures that mock the bootstrap context so skills can be tested in isolation, with exact-match SQL comparison.

## Scope

Three SQL-generating skills: query, USS, and star. Focal is out of scope (requires live database).

## Structure

```
tests/
  bootstrap-context.md          # Real f_focal_read() output from Adventure Works DDW
  connection-context.md         # Mocked PostgreSQL connection profile
  query/
    latest-snapshot.md
    history-single-entity.md
    history-multi-entity.md
    cutoff-date-latest.md
  uss/
    event-grain-snapshot.md
    columnar-dates-snapshot.md
    event-grain-historical.md
    columnar-dates-historical.md
  star/
    dimension-type-0.md
    dimension-type-1.md
    dimension-type-2.md
    dimension-mixed.md
    fact-transaction.md
    fact-periodic-snapshot.md
    fact-accumulating-snapshot.md
    fact-factless.md
```

## Bootstrap Context

Real output from `f_focal_read('9999-12-31')` against Adventure Works DDW (313 rows, 15 entities). Stored as a markdown table in `tests/bootstrap-context.md`. This mirrors the production bootstrap format and is the same dataset used for manual testing.

Entities: ADDRESS, CUSTOMER, DEPARTMENT, EMPLOYEE, PERSON, PRODUCT, PURCHASE_ORDER, SALES_ORDER, SALES_ORDER_DETAIL, SALES_PERSON, SALES_TERRITORY, SPECIAL_OFFER, STORE, VENDOR, WORK_ORDER.

## Connection Context

Mocked PostgreSQL connection profile in `tests/connection-context.md`:
- Dialect: PostgreSQL
- Source schema: `daana_dw`
- No real credentials — just enough for dialect selection and schema references

## Test Fixture Format

Each test file follows this structure:

```markdown
# Test: <Scenario Name>

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Inputs

<Interview answers or user question specific to this scenario>

## Expected Output

<Exact SQL the skill should generate>
```

Test files reference bootstrap/connection context via `@bootstrap-context.md` (same pattern as skill reference files).

For USS and star tests that generate multiple files, the Expected Output section has subsections per file (e.g., `### customer.sql`, `### _bridge.sql`).

## Scenario Coverage

### Query (4 tests)

| File | Question | Mode | Pattern exercised |
|------|----------|------|-------------------|
| `latest-snapshot.md` | Show all customers with names and emails | Latest | Pattern 1: RANK + pivot |
| `history-single-entity.md` | Show history of customer names | History | Pattern 2: temporal alignment |
| `history-multi-entity.md` | Show order history with customer names | History | Pattern 3: cross-entity UNION ALL |
| `cutoff-date-latest.md` | Show all customers as of 2024-01-01 | Latest + cutoff | Pattern 1 + cutoff modifier |

### USS (4 tests)

| File | Temporal mode | Peripheral versioning | Key variation |
|------|---------------|----------------------|---------------|
| `event-grain-snapshot.md` | Event-grain unpivot | Type 1 (latest) for all | Main path — unpivot timestamps, surrogate peripheral keys, synthetic date/time peripherals |
| `columnar-dates-snapshot.md` | Columnar dates | Type 1 (latest) for all | Timestamps as columns, no synthetic peripherals |
| `event-grain-historical.md` | Event-grain unpivot | Type 2 (full history) for all | effective_from/effective_to on peripherals, point-in-time bridge joins |
| `columnar-dates-historical.md` | Columnar dates | Type 2 (full history) for all | Columnar timestamps + versioned peripherals |

### Star (8 tests)

| File | Type | Key variation |
|------|------|---------------|
| `dimension-type-0.md` | Dimension | Retain original (ASC ordering) |
| `dimension-type-1.md` | Dimension | Overwrite (DESC ordering, current only) |
| `dimension-type-2.md` | Dimension | Full history (valid_from/valid_to) |
| `dimension-mixed.md` | Dimension | Mix of Type 0 + 1 + 2 in one dimension |
| `fact-transaction.md` | Fact | Transaction grain, measures + dimension FKs |
| `fact-periodic-snapshot.md` | Fact | Periodic snapshot at regular intervals |
| `fact-accumulating-snapshot.md` | Fact | Accumulating with milestone timestamps |
| `fact-factless.md` | Fact | No measures, just FK relationships |

## Comparison Strategy

Exact string match between generated SQL and expected SQL. If Claude's non-deterministic output causes too much drift, we can loosen to normalized matching (collapse whitespace, normalize casing) in a future iteration.

## Deliverable Scope

The `tests/` directory is part of the repository (not gitignored). Test fixtures are committed alongside the skills they validate. The test runner (if implemented as a skill) is a separate concern.
