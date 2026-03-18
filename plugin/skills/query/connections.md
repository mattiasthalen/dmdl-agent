# Connections Schema

Connection profiles are defined in `connections.yaml` at the project root. Each profile is a named entry under the `connections` key.

Documentation: https://docs.daana.dev/dmdl/connections

## Supported Types

| Type | Status |
|---|---|
| `postgresql` | Supported |
| `bigquery` | Not yet supported in query skill |
| `mssql` | Not yet supported in query skill |
| `oracle` | Not yet supported in query skill |
| `snowflake` | Not yet supported in query skill |

## PostgreSQL Profile

### Required Fields

| Field | Type | Description |
|---|---|---|
| `type` | string | Must be `"postgresql"` |
| `host` | string | Database server hostname |
| `port` | integer | Default: 5432 |
| `user` | string | Database username |
| `database` | string | Database name |

### Optional Fields

| Field | Type | Description |
|---|---|---|
| `password` | string | Use `${VAR_NAME}` for env var interpolation |
| `sslmode` | string | Default: `"disable"` |
| `target_schema` | string | Schema for Daana output (e.g., `daana_dw`) |
| `container` | string | Docker container name (used by dialect for `docker exec`) |

### Example

```yaml
connections:
  dev:
    type: "postgresql"
    host: "localhost"
    port: 5432
    user: "dev"
    password: "${DEV_PASSWORD}"
    database: "customerdb"
    target_schema: "daana_dw"
    container: "daana-test-customerdb"
```

> **Note:** The current query skill connects via `docker exec` into the database container. A future version will use a proper client connection (e.g., `psql` or a native driver) instead, making the `container` field unnecessary.

## Validation

```bash
daana-cli check connections
daana-cli check connections --connection dev
```
