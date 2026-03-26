# Connection Context — Adventure Works DDW

Mocked connection profile for test fixtures. Do not execute queries — this is for SQL generation testing only.

## Connection Profile

- **Type:** PostgreSQL
- **Host:** localhost
- **Port:** 5442
- **User:** dev
- **Database:** customerdb
- **Source Schema:** daana_dw
- **Target Schema:** (varies per test — specified in each fixture)

## Dialect Rules

- Use PostgreSQL syntax
- No QUALIFY — use subquery with WHERE clause
- Window frames: `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
- Use lowercase for all identifiers
