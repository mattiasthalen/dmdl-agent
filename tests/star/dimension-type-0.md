# Test: Dimension SCD Type 0 — Retain Original Product Attributes

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** PRODUCT
- **Type:** Dimension
- **SCD Type:** 0
- **Materialization:** View
- **Output folder:** star/
- **Target schema:** star
- **Attributes:**
  - product_name (TYPE_KEY 22, VAL_STR)
  - product_number (TYPE_KEY 14, VAL_STR)
  - product_color (TYPE_KEY 118, VAL_STR)
  - product_list_price (TYPE_KEY 50, VAL_NUM)

## Expected Output

### dim_product.sql

```sql
CREATE OR REPLACE VIEW star.dim_product AS
SELECT
  product_key,
  MAX(CASE WHEN type_key = 22 THEN val_str END) AS product_name,
  MAX(CASE WHEN type_key = 14 THEN val_str END) AS product_number,
  MAX(CASE WHEN type_key = 118 THEN val_str END) AS product_color,
  MAX(CASE WHEN type_key = 50 THEN val_num END) AS product_list_price
FROM (
  SELECT
    product_key,
    type_key,
    row_st,
    RANK() OVER (
      PARTITION BY product_key, type_key
      ORDER BY eff_tmstp ASC, ver_tmstp ASC
    ) AS nbr,
    val_str,
    val_num
  FROM daana_dw.product_desc
  WHERE type_key IN (22, 14, 118, 50)
) a
WHERE nbr = 1 AND row_st = 'Y'
GROUP BY product_key;
```
