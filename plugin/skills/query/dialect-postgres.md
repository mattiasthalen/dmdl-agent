# Dialect: PostgreSQL

## Connection

### Via connections.yaml

Extract `host`, `port`, `user`, `database`, `password`, and `container` from the chosen profile.

If `container` is not in the profile, try to resolve it automatically before asking the user:

1. Search for `docker-compose.yaml` or `docker-compose.yml` using the Glob tool (`**/docker-compose.{yaml,yml}`)
2. If found, read it and look for a service whose container name, service name, or database configuration matches the connection profile (e.g., matching `host`, `database`, or `port`)
3. If a match is found, use that container/service name
4. If no match or no docker-compose file, then ask the user: "What's the Docker container name for this database?"

### Execution command

All queries run via `docker exec`:

```bash
docker exec <container> psql -U <user> -d <database> -P pager=off --csv -c "<SQL>"
```

**Important:** Never use `-it` flags — Claude Code's Bash tool has no interactive TTY. Always include `-P pager=off --csv`.

## Bootstrap Query

Join `f_focal_read` with `logical_physical_x` and `tbl_ptrn_col_nm` to resolve the physical column for each attribute:

```sql
SELECT
  fr.focal_name,
  fr.focal_physical_schema,
  fr.descriptor_concept_name,
  fr.atomic_context_name,
  fr.atom_contx_key,
  fr.attribute_name,
  fr.atr_key,
  tcn.val_str AS physical_column
FROM daana_metadata.f_focal_read('9999-12-31') fr
LEFT JOIN daana_metadata.logical_physical_x lp
  ON lp.atr_key = fr.atr_key AND lp.atom_contx_key = fr.atom_contx_key AND lp.row_st = 'Y'
LEFT JOIN daana_metadata.tbl_ptrn_col_nm tcn
  ON lp.tbl_ptrn_col_key = tcn.tbl_ptrn_col_key AND tcn.row_st = 'Y'
WHERE fr.focal_physical_schema = 'DAANA_DW'
ORDER BY fr.focal_name, fr.descriptor_concept_name, fr.atomic_context_name
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

In PostgreSQL Focal installations, relationship table columns use `attribute_name` from the bootstrap as the physical column name — not `FOCAL01_KEY` / `FOCAL02_KEY` pattern names. When `physical_column` returns `FOCAL01_KEY` or `FOCAL02_KEY`, use the corresponding `attribute_name` value instead.
