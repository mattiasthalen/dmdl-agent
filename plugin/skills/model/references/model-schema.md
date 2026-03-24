# DMDL Model Schema Reference

Self-contained schema reference for generating and validating `model.yaml` files without `daana-cli`.

## Model Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | UPPERCASE_WITH_UNDERSCORES |
| `name` | Yes | string | Must equal `id` |
| `definition` | Yes | string | Single line, concise technical statement |
| `description` | No | string | Detailed explanation, may be multi-line |
| `entities` | Yes | array | At least one entity |
| `relationships` | No | array | References must point to existing entity IDs |

## Entity Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | UPPERCASE_WITH_UNDERSCORES, unique across all entities |
| `name` | Yes | string | Must equal `id` |
| `definition` | Yes | string | Single line |
| `description` | No | string | Detailed, may be multi-line |
| `attributes` | Yes | array | At least one attribute |

## Attribute Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | UPPERCASE_WITH_UNDERSCORES, unique within the entity |
| `name` | Yes | string | Must equal `id` |
| `definition` | Yes | string | Single line |
| `description` | No | string | Detailed, may be multi-line |
| `type` | Conditional | string | One of the valid attribute types (see below). **Mutually exclusive with `group`** |
| `effective_timestamp` | No | boolean | Default: `false` |
| `group` | Conditional | array | Array of inner attributes. **Mutually exclusive with `type`** |

**Mutual exclusivity rule:** Every attribute must have exactly one of `type` or `group`, never both, never neither.

### `effective_timestamp` Semantics

- **`true`** — Daana tracks historical changes for this attribute (SCD Type 2). Use for values that change over time: name, address, status, tier.
- **`false`** (default) — Point-in-time value that does not change. Use for creation timestamps, identifiers, codes.

The actual timestamp source is configured in the mapping file, not in the model.

## Attribute Types

| Type | Description | Use when |
|------|-------------|----------|
| `STRING` | Text value | Names, emails, statuses, codes, identifiers, descriptions |
| `NUMBER` | Numeric value | Amounts, counts, quantities, scores, ratings, percentages |
| `UNIT` | Unit-of-measure label | Currency codes, measurement units; typically paired with NUMBER in a group |
| `START_TIMESTAMP` | Timestamp marking a beginning | Creation dates, sign-up dates, start times, "placed on" |
| `END_TIMESTAMP` | Timestamp marking an end | Delivery dates, completion dates, close dates, expiry dates |

## Group Attribute Fields

A group attribute has `group` instead of `type`. Its inner attributes have a reduced field set:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | UPPERCASE_WITH_UNDERSCORES |
| `name` | Yes | string | Must equal `id` |
| `definition` | Yes | string | Single line |
| `type` | Yes | string | One of the valid attribute types |

Inner attributes do **not** have `description` or `effective_timestamp` -- those are inherited from the outer group attribute.

### Group Constraints

- Max 1 attribute of each type per group (at most 1 NUMBER, 1 STRING, 1 UNIT, 1 START_TIMESTAMP, 1 END_TIMESTAMP).
- The outer group attribute and its first inner member may share the same `id`. This is valid and expected DMDL convention -- the outer `id` identifies the group, the inner `id` identifies the specific value.

## Relationship Fields

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | UPPERCASE_WITH_UNDERSCORES, verb-phrase (e.g., `IS_PLACED_BY`, `BELONGS_TO`) |
| `name` | Yes | string | Must equal `id` |
| `definition` | Yes | string | Single line |
| `description` | No | string | Detailed, may be multi-line |
| `source_entity_id` | Yes | string | Must match an existing entity `id` |
| `target_entity_id` | Yes | string | Must match an existing entity `id` |

### Direction Convention

- **Source** = the entity that holds the foreign key (the entity that "points to" another).
- **Target** = the entity being referenced.
- Example: "ORDER is placed by CUSTOMER" -> source: `ORDER`, target: `CUSTOMER` (the order holds the customer reference).

## Naming Conventions

- All `id` and `name` values use `UPPERCASE_WITH_UNDERSCORES` (e.g., `CUSTOMER`, `ORDER_AMOUNT`, `IS_PLACED_BY`).
- `id` and `name` are always set to the same value.
- Relationship IDs should be verb phrases describing the relationship from the source's perspective.

## Validation Rules

When `daana-cli` is not available, enforce these rules:

1. **Required fields** -- `id`, `name`, `definition` present on every model, entity, attribute, relationship. `type` or `group` present on every attribute. `source_entity_id` and `target_entity_id` present on every relationship.
2. **id/name equality** -- `id` and `name` must be identical on every element.
3. **Naming format** -- All `id`/`name` values match `^[A-Z][A-Z0-9_]*$`.
4. **Attribute type validity** -- `type` is one of: `STRING`, `NUMBER`, `UNIT`, `START_TIMESTAMP`, `END_TIMESTAMP`.
5. **type/group mutual exclusivity** -- Each attribute has exactly one of `type` or `group`, never both, never neither.
6. **Group inner attribute constraints** -- Inner attributes have only `id`, `name`, `definition`, `type`. Max 1 of each type per group.
7. **Entity uniqueness** -- No duplicate entity `id` values within the model.
8. **Attribute uniqueness** -- No duplicate attribute `id` values within the same entity. Exception: an outer group attribute and its first inner member may share the same `id`.
9. **Relationship uniqueness** -- No duplicate relationship `id` values within the model.
10. **Relationship entity references** -- `source_entity_id` and `target_entity_id` must each match an existing entity `id`.
11. **Non-empty collections** -- `entities` array must have at least one entity. Each entity's `attributes` array must have at least one attribute.
12. **Boolean type** -- `effective_timestamp` must be a boolean (`true` or `false`), not a string.
13. **String quoting** -- `id`, `name`, `definition`, `description`, `type`, `source_entity_id`, `target_entity_id` values should be quoted strings in YAML.
