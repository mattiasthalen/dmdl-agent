# DMDL Model Examples

Complete, annotated YAML examples for generating valid `model.yaml` files. Every example is copy-pasteable and follows DMDL schema rules.

**Formatting rules used throughout:**
- 2-space indentation
- Quoted string values for `id`, `name`, `definition`, `description`, `type`, `source_entity_id`, `target_entity_id`
- Boolean values unquoted (`true`, `false`)
- Field ordering: `id`, `name`, `definition`, `description`, then type-specific fields

---

## 1. Minimal Model

A single entity with three attributes and no relationships. This is the smallest valid model.

The top-level `model` object provides metadata for the entire model. Every element (model, entity, attribute) requires `id`, `name`, and `definition`. The `id` and `name` fields are always set to the same UPPERCASE_WITH_UNDERSCORES value. The `description` field is optional but recommended for additional business context.

```yaml
model:
  id: "CUSTOMER_MODEL"
  name: "CUSTOMER_MODEL"
  definition: "Customer account data model"
  description: "Defines the structure for customer account information"

  entities:
    - id: "CUSTOMER"
      name: "CUSTOMER"
      definition: "A customer account"
      description: "Represents an individual or organization that makes purchases"
      attributes:
        - id: "CUSTOMER_NAME"
          name: "CUSTOMER_NAME"
          definition: "Customer full name"
          description: "Legal or display name of the customer"
          type: "STRING"
          effective_timestamp: true

        - id: "EMAIL"
          name: "EMAIL"
          definition: "Customer email address"
          description: "Primary contact email for the customer account"
          type: "STRING"
          effective_timestamp: true

        - id: "SIGNUP_DATE"
          name: "SIGNUP_DATE"
          definition: "Account creation date"
          description: "When the customer account was first created"
          type: "START_TIMESTAMP"
```

**Why these fields are set this way:**

- `CUSTOMER_NAME` is a `STRING` with `effective_timestamp: true` because names can change over time and we want to track the history.
- `EMAIL` is a `STRING` with `effective_timestamp: true` because email addresses can be updated.
- `SIGNUP_DATE` is a `START_TIMESTAMP` because it represents a point when something began. It omits `effective_timestamp` (defaults to `false`) because a creation date never changes.
- When `effective_timestamp` is `false` (the default), the field can be omitted entirely, as shown on `SIGNUP_DATE`.

---

## 2. Complete Model

A full model with four entities (CUSTOMER, ORDER, PRODUCT, ORDER_LINE), a grouped attribute, and relationships. This demonstrates the complete file structure.

```yaml
model:
  id: "ECOMMERCE"
  name: "ECOMMERCE"
  definition: "E-commerce business data model"
  description: "Defines entities and relationships for an online retail operation"

  entities:
    - id: "CUSTOMER"
      name: "CUSTOMER"
      definition: "A customer account"
      description: "Represents an individual or organization that makes purchases"
      attributes:
        - id: "CUSTOMER_NAME"
          name: "CUSTOMER_NAME"
          definition: "Customer full name"
          description: "Legal or display name of the customer"
          type: "STRING"
          effective_timestamp: true

        - id: "LOYALTY_TIER"
          name: "LOYALTY_TIER"
          definition: "Customer loyalty program level"
          description: "Current tier in the loyalty program such as BRONZE, SILVER, GOLD"
          type: "STRING"
          effective_timestamp: true

        - id: "SIGNUP_DATE"
          name: "SIGNUP_DATE"
          definition: "Account creation date"
          description: "When the customer account was first created"
          type: "START_TIMESTAMP"

    - id: "ORDER"
      name: "ORDER"
      definition: "A customer purchase order"
      description: "Represents a single transaction placed by a customer"
      attributes:
        - id: "ORDER_STATUS"
          name: "ORDER_STATUS"
          definition: "Current order status"
          description: "Processing state of the order such as PENDING, SHIPPED, DELIVERED"
          type: "STRING"
          effective_timestamp: true

        - id: "ORDER_AMOUNT"
          name: "ORDER_AMOUNT"
          definition: "Order monetary value with currency"
          description: "Total order amount paired with its currency code"
          effective_timestamp: true
          group:
            - id: "ORDER_AMOUNT"
              name: "ORDER_AMOUNT"
              definition: "The monetary amount"
              type: "NUMBER"
            - id: "ORDER_AMOUNT_CURRENCY"
              name: "ORDER_AMOUNT_CURRENCY"
              definition: "Currency code"
              type: "UNIT"

        - id: "PLACED_AT"
          name: "PLACED_AT"
          definition: "Order placement timestamp"
          description: "When the order was submitted by the customer"
          type: "START_TIMESTAMP"

        - id: "DELIVERED_AT"
          name: "DELIVERED_AT"
          definition: "Order delivery timestamp"
          description: "When the order was delivered to the customer"
          type: "END_TIMESTAMP"

    - id: "PRODUCT"
      name: "PRODUCT"
      definition: "A product in the catalog"
      description: "Represents an item available for purchase"
      attributes:
        - id: "PRODUCT_NAME"
          name: "PRODUCT_NAME"
          definition: "Product display name"
          description: "The name shown to customers in the catalog"
          type: "STRING"
          effective_timestamp: true

        - id: "UNIT_PRICE"
          name: "UNIT_PRICE"
          definition: "Product price with currency"
          description: "Current selling price paired with its currency code"
          effective_timestamp: true
          group:
            - id: "UNIT_PRICE"
              name: "UNIT_PRICE"
              definition: "The price amount"
              type: "NUMBER"
            - id: "UNIT_PRICE_CURRENCY"
              name: "UNIT_PRICE_CURRENCY"
              definition: "Currency code"
              type: "UNIT"

    - id: "ORDER_LINE"
      name: "ORDER_LINE"
      definition: "A line item within an order"
      description: "Represents a single product entry in an order with its quantity"
      attributes:
        - id: "QUANTITY"
          name: "QUANTITY"
          definition: "Number of units ordered"
          description: "How many units of the product were included in this line"
          type: "NUMBER"
          effective_timestamp: true

  relationships:
    - id: "IS_PLACED_BY"
      name: "IS_PLACED_BY"
      definition: "Links an order to the customer who placed it"
      description: "Each order is placed by exactly one customer"
      source_entity_id: "ORDER"
      target_entity_id: "CUSTOMER"

    - id: "CONTAINS"
      name: "CONTAINS"
      definition: "Links an order line to its parent order"
      description: "Each order line belongs to exactly one order"
      source_entity_id: "ORDER_LINE"
      target_entity_id: "ORDER"

    - id: "REFERS_TO"
      name: "REFERS_TO"
      definition: "Links an order line to the product ordered"
      description: "Each order line refers to exactly one product"
      source_entity_id: "ORDER_LINE"
      target_entity_id: "PRODUCT"
```

**Structure notes:**

- The `entities` list and `relationships` list are both children of `model`.
- Relationships are defined after all entities, in their own list.
- Each relationship's `source_entity_id` and `target_entity_id` must reference an entity `id` that exists in the model.

---

## 3. Attribute Type Examples

DMDL supports five attribute types. Here is one example of each, shown in context within an entity.

```yaml
      attributes:
        - id: "CUSTOMER_NAME"
          name: "CUSTOMER_NAME"
          definition: "Customer full name"
          type: "STRING"
          effective_timestamp: true

        - id: "ORDER_TOTAL"
          name: "ORDER_TOTAL"
          definition: "Total order value"
          type: "NUMBER"
          effective_timestamp: true

        - id: "PRICE_CURRENCY"
          name: "PRICE_CURRENCY"
          definition: "Currency code for pricing"
          type: "UNIT"
          effective_timestamp: true

        - id: "CREATED_AT"
          name: "CREATED_AT"
          definition: "Record creation timestamp"
          type: "START_TIMESTAMP"

        - id: "CLOSED_AT"
          name: "CLOSED_AT"
          definition: "Record closure timestamp"
          type: "END_TIMESTAMP"
```

**When to use each type:**

- **STRING** -- Text values: names, statuses, codes, descriptions, email addresses, identifiers. The most common type.
- **NUMBER** -- Numeric values: amounts, quantities, counts, scores, ratings, percentages. Often paired with UNIT in a group.
- **UNIT** -- Unit qualifiers: currency codes (USD, EUR), units of measure (KG, LB). Almost always appears inside a group alongside a NUMBER.
- **START_TIMESTAMP** -- Points in time when something began: creation dates, signup dates, order placement times, start dates.
- **END_TIMESTAMP** -- Points in time when something ended or completed: delivery dates, closure dates, expiration dates, completion times.

---

## 4. Grouped Attribute Example

Groups bundle related attributes that answer a single "atomic question." The most common pattern is an amount paired with its currency.

```yaml
        - id: "ORDER_AMOUNT"
          name: "ORDER_AMOUNT"
          definition: "Order monetary value with currency"
          description: "The total amount of the order paired with its currency code"
          effective_timestamp: true
          group:
            - id: "ORDER_AMOUNT"
              name: "ORDER_AMOUNT"
              definition: "The monetary amount"
              type: "NUMBER"
            - id: "ORDER_AMOUNT_CURRENCY"
              name: "ORDER_AMOUNT_CURRENCY"
              definition: "Currency code"
              type: "UNIT"
```

**Annotations:**

- **Outer attribute** has `id`, `name`, `definition`, `description`, and `effective_timestamp`, but no `type`. It uses `group` instead of `type`.
- **Inner attributes** each have `id`, `name`, `definition`, and `type`, but no `effective_timestamp` (inherited from the outer attribute).
- **Shared ID convention:** The outer attribute and its first group member intentionally share the same `id` (`ORDER_AMOUNT`). The outer `id` identifies the group as a whole; the inner `id` identifies the specific value within the group. This is standard DMDL convention and should not be flagged as a duplicate.
- **Naming convention for additional members:** Subsequent group members append a suffix to the outer `id` describing their role (e.g., `ORDER_AMOUNT_CURRENCY`).
- **Constraint rules:** Each group can contain at most one of each type -- at most 1 NUMBER, 1 STRING, 1 UNIT, 1 START_TIMESTAMP, and 1 END_TIMESTAMP. A group with two NUMBERs is invalid.

---

## 5. Relationship Examples

### Simple Relationship

A relationship linking ORDER to CUSTOMER.

```yaml
  relationships:
    - id: "IS_PLACED_BY"
      name: "IS_PLACED_BY"
      definition: "Links an order to the customer who placed it"
      description: "Each order is placed by exactly one customer"
      source_entity_id: "ORDER"
      target_entity_id: "CUSTOMER"
```

**Direction explained:** The source entity is ORDER because it holds the foreign key -- each order record contains a reference to the customer who placed it. The target entity is CUSTOMER because it is the entity being referenced.

**Rule of thumb:** Ask "which entity holds the reference to the other?" That entity is the source. In a typical database, the orders table has a `customer_id` column, so ORDER is the source.

### Dual Relationships

When two entities relate to each other in more than one way, each relationship gets its own entry with a distinct `id`.

```yaml
  relationships:
    - id: "IS_PLACED_BY"
      name: "IS_PLACED_BY"
      definition: "Links an order to the customer who placed it"
      description: "Each order is placed by exactly one customer"
      source_entity_id: "ORDER"
      target_entity_id: "CUSTOMER"

    - id: "IS_SHIPPED_TO"
      name: "IS_SHIPPED_TO"
      definition: "Links an order to the customer receiving shipment"
      description: "Each order is shipped to exactly one customer, who may differ from the purchaser"
      source_entity_id: "ORDER"
      target_entity_id: "CUSTOMER"
```

**Direction explained:** Both relationships have ORDER as the source because in both cases the order record holds the reference -- once for the purchasing customer and once for the shipping customer. The relationship `id` uses a distinct verb phrase to differentiate them (`IS_PLACED_BY` vs `IS_SHIPPED_TO`).

### Correct Source/Target Direction

Common patterns and their correct direction:

| Natural language | source_entity_id | target_entity_id | Why |
|---|---|---|---|
| "Order is placed by Customer" | ORDER | CUSTOMER | Order holds the customer reference |
| "Order line belongs to Order" | ORDER_LINE | ORDER | Line item holds the order reference |
| "Order line refers to Product" | ORDER_LINE | PRODUCT | Line item holds the product reference |
| "Employee reports to Manager" | EMPLOYEE | MANAGER | Employee record holds the manager reference |

The source is always the entity whose records contain a pointer to the other entity.
