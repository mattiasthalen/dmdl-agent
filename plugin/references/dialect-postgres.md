# Dialect: PostgreSQL

## Connection

### Via connections.yaml

Extract `host`, `port`, `user`, `database`, `password` from the chosen profile. The container name for `docker exec` must be provided by the user or derived from the connection profile's host.

### Execution command

All queries run via `docker exec`:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "<SQL>"
```

**Important:** Never use `-it` flags — Claude Code's Bash tool has no interactive TTY. Always include `-P pager=off --csv`.

## Bootstrap Query

PostgreSQL's `f_focal_read` returns `table_pattern_column_name` directly — no join to `logical_physical_x` or `tbl_ptrn_col_nm` needed.

```sql
SELECT
  focal_name,
  descriptor_concept_name,
  atomic_context_name,
  atom_contx_key,
  attribute_name,
  table_pattern_column_name
FROM daana_metadata.f_focal_read('9999-12-31')
WHERE focal_physical_schema = 'DAANA_DW'
ORDER BY focal_name, descriptor_concept_name, atomic_context_name
```

**Note:** `focal_physical_schema` is uppercase (`'DAANA_DW'`, not `'daana_dw'`).

## SQL Syntax

### Schemas

PostgreSQL uses lowercase schema names in queries: `daana_dw.customer_desc`, `daana_metadata.f_focal_read()`.

### QUALIFY alternative

PostgreSQL does not support `QUALIFY`. Use a subquery instead:

**BigQuery:**
```sql
SELECT * FROM table
QUALIFY RANK() OVER (PARTITION BY key ORDER BY ts DESC) = 1
```

**PostgreSQL:**
```sql
SELECT * FROM (
  SELECT *, RANK() OVER (PARTITION BY key ORDER BY ts DESC) AS rnk
  FROM table
) sub WHERE rnk = 1
```

### Window frames

PostgreSQL supports `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` in window functions — same as BigQuery.

### Temporal alignment carry-forward

The `MAX(...) OVER W` pattern for carry-forward works in PostgreSQL:

```sql
MAX(CASE WHEN timeline = 'ATTR_NAME' THEN eff_tmstp END)
  OVER (
    PARTITION BY entity_key
    ORDER BY eff_tmstp
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS eff_tmstp_attr_name
```

### Statement timeout

Prefix queries with `SET statement_timeout = '30s';` to prevent long-running queries.

### Type casting

```sql
CAST('2024-01-01' AS TIMESTAMP)
```

## Relationship table columns

In PostgreSQL Focal installations, relationship table columns use `ATTRIBUTE_NAME` from the bootstrap as the physical column name — not `FOCAL01_KEY` / `FOCAL02_KEY` pattern names. When `table_pattern_column_name` returns `FOCAL01_KEY` or `FOCAL02_KEY`, use the corresponding `attribute_name` value instead.
