# Source Schema Formats Reference

Shared reference for parsing source schemas. Used by `/daana-model`, `/daana-mapping`, and the `/daana` orchestrator to extract tables, columns, and types from source metadata.

## Format Detection

| Signal | Format |
|--------|--------|
| JSON with top-level `swagger` or `openapi` key | Swagger/OpenAPI |
| XML with `edmx` namespace | OData Metadata |
| JSON or YAML with top-level `tables` key containing objects with a `columns` key | dlt Schema |

## Swagger/OpenAPI

### Extraction

| Version | Schema location |
|---------|----------------|
| v2 | `definitions` |
| v3 | `components.schemas` |

- Each schema object key → table name
- Each property in the schema → column (use property key as column name)

### Type Mapping

| Source type | DMDL type |
|-------------|-----------|
| `string` | `STRING` |
| `string` with `format: date-time` | `START_TIMESTAMP` |
| `integer` | `NUMBER` |
| `number` | `NUMBER` |
| `boolean` | `STRING` |

Note: `string` with `format: date-time` takes precedence over the plain `string` rule.

## OData Metadata XML

### Extraction

- Parse `<EntityType>` elements
- `Name` attribute on `<EntityType>` → table name
- Each `<Property>` child element → column (use `Name` attribute as column name, `Type` attribute for type mapping)

### Type Mapping

| Source type | DMDL type |
|-------------|-----------|
| `Edm.String` | `STRING` |
| `Edm.Guid` | `STRING` |
| `Edm.Boolean` | `STRING` |
| `Edm.Int32` | `NUMBER` |
| `Edm.Int64` | `NUMBER` |
| `Edm.Decimal` | `NUMBER` |
| `Edm.Double` | `NUMBER` |
| `Edm.DateTimeOffset` | `START_TIMESTAMP` |
| `Edm.DateTime` | `START_TIMESTAMP` |

## dlt Schema

### Extraction

- Parse `tables` object
- Each key → table name (dlt already formats names as `schema.table_name`)
- `columns` object within each table entry → column entries (use each key as column name, `data_type` value for type mapping)

### Type Mapping

| Source type | DMDL type |
|-------------|-----------|
| `text` | `STRING` |
| `bigint` | `NUMBER` |
| `double` | `NUMBER` |
| `timestamp` | `START_TIMESTAMP` |
| `date` | `START_TIMESTAMP` |
| `bool` | `STRING` |

## Normalized Output Format

After parsing, represent each table as:

```
Table: schema.table_name
  Columns:
    - column_name (INFERRED_DMDL_TYPE)
    - column_name (INFERRED_DMDL_TYPE)
```

If the source does not include a schema prefix, use the table name as-is.

## Usage Guidance

| Skill | How to use normalized output |
|-------|------------------------------|
| `/daana-model` | Use table names to suggest entity names; use column names to suggest attribute names; use inferred DMDL types as default `type` values |
| `/daana-mapping` | Use table names for the `table` field in mapping entries; use column names for smart matching and as defaults in `transformation_expression` |
