# DMDL Mapping Schema Reference

Self-contained schema reference for generating and validating mapping YAML files without `daana-cli`.

## Root Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `entity_id` | Yes | string | Must match an existing entity `id` in `model.yaml` |
| `mapping_groups` | Yes | array | Exactly one group per file (always named `default_mapping_group`) |

## Mapping Group Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `name` | Yes | string | Always `"default_mapping_group"` |
| `allow_multiple_identifiers` | Yes | boolean | Default: `false`; set to `true` only when multiple tables map the same identifier attribute. **Irreversible once materialized.** |
| `tables` | Yes | array | At least one table |
| `relationships` | No | array | References must point to relationship IDs where this entity is the source |

## Table Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `connection` | Yes | string | Name of the connection profile |
| `table` | Yes | string | Source table in `schema.table` format (e.g., `public.orders`) |
| `primary_keys` | Yes | array | One or more column names; may use SQL expressions for composite keys (e.g., `order_id \|\| ' ' \|\| line_id`) |
| `ingestion_strategy` | Yes | string | One of: `FULL`, `INCREMENTAL`, `FULL_LOG`, `TRANSACTIONAL` |
| `where` | No | string | SQL WHERE clause to filter rows from the source table (e.g., `status != 'deleted'`) |
| `entity_effective_timestamp_expression` | Yes | string | Column or SQL expression representing when changes occur; default for all change-tracked attributes in this table |
| `attributes` | Yes | array | At least one attribute mapping |

## Attribute Mapping Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | Must match an existing attribute `id` in the entity (UPPERCASE_WITH_UNDERSCORES); unique within the table |
| `transformation_expression` | Yes | string | SQL expression mapping source column(s) to the attribute value; may not be empty |
| `ingestion_strategy` | No | string | Overrides the table-level strategy for this attribute; one of: `FULL`, `INCREMENTAL`, `FULL_LOG`, `TRANSACTIONAL` |
| `where` | No | string | SQL WHERE clause applied to this attribute only |
| `attribute_effective_timestamp_expression` | No | string | Overrides the table-level `entity_effective_timestamp_expression` for this attribute |

## Relationship Mapping Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | Must match an existing relationship `id` in `model.yaml` where this entity is the `source_entity_id` |
| `source_table` | Yes | string | Must match a `table` value defined in this mapping's `tables` array |
| `target_transformation_expression` | Yes | string | SQL expression or column that identifies the target entity |

## Ingestion Strategies

| Strategy | Default | Best For | Description |
|----------|---------|----------|-------------|
| `FULL` | Yes | Small dimension tables | Complete snapshot of all data for each delivery |
| `INCREMENTAL` | | Large fact tables | Only changed or new data since last load (requires watermark column) |
| `FULL_LOG` | | Change history tables | Complete history of all changes, with multiple rows per instance |
| `TRANSACTIONAL` | | Append-only event logs | Append-only data where each instance is delivered exactly once |

## Transformation Expression Syntax

Transformation expressions are SQL expressions evaluated in the source system context. Any valid SQL expression is allowed.

### Direct Column Reference

```yaml
transformation_expression: "customer_name"
```

### SQL Function

```yaml
transformation_expression: "UPPER(status)"
```

### CASE Expression

```yaml
transformation_expression: "CASE WHEN status = 'A' THEN 'ACTIVE' ELSE 'INACTIVE' END"
```

### Concatenation / Composite Expression

```yaml
transformation_expression: "order_id || ' ' || line_id"
```

### Type Cast

```yaml
transformation_expression: "CAST(total_amount AS DECIMAL(10,2))"
```

### Multiline (YAML Folded Style)

For long expressions, use YAML folded block scalar (`>`):

```yaml
transformation_expression: >
  CASE
    WHEN status = 'A' THEN 'ACTIVE'
    WHEN status = 'I' THEN 'INACTIVE'
    ELSE 'UNKNOWN'
  END
```

## Field Ordering

Fields must appear in this order within each YAML block:

**Mapping group:** `name`, `allow_multiple_identifiers`, `tables`, `relationships`

**Table:** `connection`, `table`, `primary_keys`, `ingestion_strategy`, `where` (if set), `entity_effective_timestamp_expression`, `attributes`

**Attribute:** `id`, `transformation_expression`, `ingestion_strategy` (if overridden), `where` (if set), `attribute_effective_timestamp_expression` (if overridden)

**Relationship:** `id`, `source_table`, `target_transformation_expression`

## Formatting Conventions

- 2-space indentation
- **Quoted strings:** all `id` values, `connection`, `table`, `name`, `source_table`, and all expression values (`transformation_expression`, `entity_effective_timestamp_expression`, `attribute_effective_timestamp_expression`, `where`, `target_transformation_expression`)
- **Unquoted:** `allow_multiple_identifiers` (boolean), `ingestion_strategy` (enum keyword), `primary_keys` items (unless they contain expressions such as `||`)
- Omit optional fields entirely when not set — do not write empty values or `null`
- File path: `mappings/<entity-lowercase>-mapping.yaml` (e.g., `mappings/customer-mapping.yaml`)

## Validation Rules

When `daana-cli` is not available, enforce these rules:

1. **Entity reference** — `entity_id` at the root must match an existing entity `id` in `model.yaml`.
2. **Attribute references** — all attribute `id` values must reference valid attributes in that entity's definition in `model.yaml`.
3. **Relationship references** — all relationship `id` values must reference valid relationships in `model.yaml` where this entity is the `source_entity_id`.
4. **Required table fields** — `connection`, `table`, `primary_keys`, `ingestion_strategy`, and `attributes` must be present on every table entry.
5. **Ingestion strategy validity** — `ingestion_strategy` (both table-level and attribute-level) must be one of: `FULL`, `INCREMENTAL`, `FULL_LOG`, `TRANSACTIONAL`.
6. **Relationship source_table** — `source_table` in each relationship entry must match a `table` value defined in the mapping's `tables` array.
7. **Attribute ID uniqueness** — no duplicate attribute `id` values within the same table entry.
