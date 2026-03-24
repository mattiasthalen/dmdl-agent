# DMDL Mapping Examples

Complete, annotated YAML examples for generating valid mapping YAML files. Every example is copy-pasteable and follows DMDL schema rules.

**Formatting rules used throughout:**
- 2-space indentation
- Quoted strings for `id`, `connection`, `table`, `source_table`, and all expression values (`transformation_expression`, `entity_effective_timestamp_expression`, `attribute_effective_timestamp_expression`, `where`, `target_transformation_expression`)
- Unquoted `allow_multiple_identifiers` (boolean) and `ingestion_strategy` (enum keyword)
- Unquoted `primary_keys` items unless they contain SQL expressions such as `||`
- Omit optional fields entirely when not set

---

## 1. Minimal Mapping

A single table, three attributes, no relationships. This is the smallest valid mapping.

```yaml
entity_id: "CUSTOMER"

mapping_groups:
  - name: "default_mapping_group"
    allow_multiple_identifiers: false

    tables:
      - connection: "dev"
        table: "public.customers"

        primary_keys:
          - customer_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"

        attributes:
          - id: "CUSTOMER_NAME"
            transformation_expression: "customer_name"

          - id: "EMAIL"
            transformation_expression: "email"

          - id: "SIGNUP_DATE"
            transformation_expression: "signup_date"
```

**Why these fields are set this way:**

- `entity_id` at the root must match an entity `id` in `model.yaml`. Here it maps to the `CUSTOMER` entity.
- `mapping_groups` always contains exactly one group named `"default_mapping_group"`.
- `allow_multiple_identifiers: false` is the default and should be used unless two or more tables map the same identifier attribute. Setting it to `true` is irreversible once the mapping has been materialized.
- `connection: "dev"` names the connection profile used to reach the source database.
- `table: "public.customers"` identifies the source table in `schema.table` format.
- `primary_keys` lists the column(s) that uniquely identify a row. Here a single column `customer_id` is sufficient and is written unquoted because it contains no SQL operators.
- `ingestion_strategy: FULL` loads a complete snapshot on every delivery. Appropriate for small, slowly changing tables such as a customer dimension.
- `entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"` is the default change timestamp for all attributes in this table. Using `CURRENT_TIMESTAMP` means the load time is used as the effective timestamp when no source column captures when changes occurred.
- Each attribute's `transformation_expression` is the SQL expression that produces the attribute value. For a direct column reference the expression is simply the column name as a quoted string.
- Optional fields (`where`, `attribute_effective_timestamp_expression`, `ingestion_strategy` override) are omitted because they are not needed.

---

## 2. Complete Mapping

Multiple attributes with SQL transformations, per-attribute overrides, and a relationship. This demonstrates the full range of mapping fields.

```yaml
entity_id: "ORDER"

mapping_groups:
  - name: "default_mapping_group"
    allow_multiple_identifiers: false

    tables:
      - connection: "dev"
        table: "public.orders"

        primary_keys:
          - order_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"

        attributes:
          - id: "ORDER_ID"
            transformation_expression: "order_id"
            where: "order_id IS NOT NULL"

          - id: "ORDER_STATUS"
            transformation_expression: "UPPER(status)"
            attribute_effective_timestamp_expression: "status_changed_at"

          - id: "ORDER_AMOUNT"
            transformation_expression: "CAST(total_amount AS DECIMAL(10,2))"
            where: "total_amount > 0"
            attribute_effective_timestamp_expression: "updated_at"

          - id: "ORDER_AMOUNT_CURRENCY"
            transformation_expression: "currency_code"

          - id: "PLACED_AT"
            transformation_expression: "order_date"

          - id: "DELIVERED_AT"
            transformation_expression: "delivered_date"

    relationships:
      - id: "IS_PLACED_BY"
        source_table: "public.orders"
        target_transformation_expression: "customer_id"
```

**Why these fields are set this way:**

- `ORDER_ID` uses a `where: "order_id IS NOT NULL"` filter to exclude rows that would produce a null identifier. Attribute-level `where` applies only to this attribute's rows, not to the whole table.
- `ORDER_STATUS` applies `UPPER(status)` to normalize casing. It overrides `attribute_effective_timestamp_expression` to `"status_changed_at"` because the source table tracks when status changed — using that column gives more accurate history than `CURRENT_TIMESTAMP`.
- `ORDER_AMOUNT` uses `CAST(total_amount AS DECIMAL(10,2))` to enforce a specific numeric precision. The `where: "total_amount > 0"` guard excludes zero-value rows that are likely data quality issues. The `attribute_effective_timestamp_expression` points to `"updated_at"` because monetary amounts are updated at a different cadence than the overall record.
- `ORDER_AMOUNT_CURRENCY` uses a direct column reference and inherits the table-level `entity_effective_timestamp_expression`. No override is needed.
- `PLACED_AT` and `DELIVERED_AT` are straightforward column references. No filtering or timestamp override is required.
- The `relationships` block maps the `IS_PLACED_BY` relationship defined in `model.yaml`. `source_table` must exactly match a `table` value in this mapping's `tables` array. `target_transformation_expression` is the column or SQL expression that identifies the related entity's identifier — here the foreign key `customer_id`.

---

## 3. Multi-Table Mapping

The same entity sourced from two tables: a legacy system and a new system. Both tables contribute attributes and share the same entity identifier column name.

```yaml
entity_id: "CUSTOMER"

mapping_groups:
  - name: "default_mapping_group"
    allow_multiple_identifiers: true

    tables:
      - connection: "legacy"
        table: "old_schema.customers"

        primary_keys:
          - cust_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"

        attributes:
          - id: "CUSTOMER_NAME"
            transformation_expression: "full_name"

          - id: "EMAIL"
            transformation_expression: "email_address"

      - connection: "dev"
        table: "public.customers"

        primary_keys:
          - customer_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "updated_at"

        attributes:
          - id: "CUSTOMER_NAME"
            transformation_expression: "customer_name"

          - id: "EMAIL"
            transformation_expression: "email"

          - id: "SIGNUP_DATE"
            transformation_expression: "created_at"
```

**Why these fields are set this way:**

- `allow_multiple_identifiers: true` is required because both tables provide their own primary key column (`cust_id` from the legacy system and `customer_id` from the new system). These are different column names that each identify the same logical entity. Setting this to `true` tells DMDL that it is acceptable for one entity to have identifiers from multiple sources. **This setting is irreversible once the mapping has been materialized** — changing it back after data has been loaded requires a full rebuild of the entity's history.
- Each table has its own `connection` and `table` values pointing to the respective source system.
- `primary_keys` differ between tables (`cust_id` vs `customer_id`) because the two systems use different column names for their surrogate keys.
- The legacy table uses `entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"` because it does not have a reliable change-tracking column. The new table uses `"updated_at"` because it does.
- Attribute `id` values are shared across tables (`CUSTOMER_NAME`, `EMAIL`) — this is intentional. DMDL merges attribute values from multiple tables into a unified entity history. `SIGNUP_DATE` only appears in the new table because the legacy system did not capture that information.
- Both tables run `ingestion_strategy: FULL` because neither has a reliable watermark column for incremental loads.

---

## 4. Transformation Expression Examples

All transformation expressions appear as the `transformation_expression` field inside an attribute block. The examples below show the main patterns.

### Direct Column Reference

The simplest case: the expression is just the column name.

```yaml
          - id: "CUSTOMER_NAME"
            transformation_expression: "customer_name"
```

**When to use:** The source column maps directly to the attribute with no transformation needed.

---

### SQL Function

Apply a built-in SQL function to the source column.

```yaml
          - id: "ORDER_STATUS"
            transformation_expression: "UPPER(status)"
```

**When to use:** Normalizing casing, extracting date parts (`DATE(created_at)`), null handling (`COALESCE(phone, '')`), or any other single-function transformation.

---

### Type Cast

Enforce a specific data type or precision.

```yaml
          - id: "ORDER_AMOUNT"
            transformation_expression: "CAST(total_amount AS DECIMAL(10,2))"
```

**When to use:** The source column type does not match the expected attribute type, or precision needs to be standardized across sources.

---

### String Concatenation

Combine two or more columns into a single value.

```yaml
          - id: "FULL_ADDRESS"
            transformation_expression: "street || ', ' || city || ', ' || country"
```

**When to use:** A composite expression such as a full address or a display label assembled from multiple source columns.

---

### CASE Expression (inline)

Remap discrete values from the source to canonical attribute values.

```yaml
          - id: "ORDER_STATUS"
            transformation_expression: "CASE WHEN status = 'A' THEN 'ACTIVE' ELSE 'INACTIVE' END"
```

**When to use:** Simple two-branch logic that fits on one line.

---

### CASE Expression (multiline folded style)

Use YAML folded block scalar (`>`) for longer expressions. The `>` character folds newlines into spaces, so the SQL engine receives a single-line expression.

```yaml
          - id: "ORDER_STATUS"
            transformation_expression: >
              CASE
                WHEN status = 'A' THEN 'ACTIVE'
                WHEN status = 'I' THEN 'INACTIVE'
                WHEN status = 'C' THEN 'CANCELLED'
                ELSE 'UNKNOWN'
              END
```

**When to use:** Any CASE expression with three or more branches, or any SQL expression that is easier to read when split across lines. The folded style (`>`) is preferred over the literal style (`|`) for SQL because it produces a single-line string without embedded newlines, which most SQL dialects handle correctly.

---

## 5. Relationship Mapping Examples

Relationships are declared in a `relationships` block inside the mapping group, after the `tables` block.

### Simple Relationship

Map the `IS_PLACED_BY` relationship between ORDER and CUSTOMER.

```yaml
entity_id: "ORDER"

mapping_groups:
  - name: "default_mapping_group"
    allow_multiple_identifiers: false

    tables:
      - connection: "dev"
        table: "public.orders"

        primary_keys:
          - order_id

        ingestion_strategy: FULL

        entity_effective_timestamp_expression: "CURRENT_TIMESTAMP"

        attributes:
          - id: "ORDER_STATUS"
            transformation_expression: "status"

    relationships:
      - id: "IS_PLACED_BY"
        source_table: "public.orders"
        target_transformation_expression: "customer_id"
```

**Why these fields are set this way:**

- `id: "IS_PLACED_BY"` must match a relationship `id` in `model.yaml` where `ORDER` is the `source_entity_id`. You may only map relationships where the current entity is the source.
- `source_table: "public.orders"` must exactly match a `table` value defined in this mapping's `tables` array. This tells DMDL which table row carries the foreign key column.
- `target_transformation_expression: "customer_id"` is the column in the source table that identifies the related entity (CUSTOMER). DMDL uses this expression to resolve which CUSTOMER record the ORDER points to.

---

### Relationship with Expression

When the foreign key must be derived rather than read directly from a single column, use a SQL expression.

```yaml
    relationships:
      - id: "IS_ASSIGNED_TO"
        source_table: "public.tasks"
        target_transformation_expression: "COALESCE(assigned_user_id, default_assignee_id)"
```

**Why these fields are set this way:**

- `target_transformation_expression` accepts any valid SQL expression, not just a column name. Here `COALESCE` picks the first non-null value from two candidate foreign key columns.
- This pattern is useful when the relationship target can come from one of several columns depending on business rules, or when the identifier must be constructed from multiple parts.
- The expression is evaluated in the context of the `source_table`, so all columns from that table are available.
