# Test: Dimension SCD Type 2 — Full Product History

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** PRODUCT
- **Type:** Dimension
- **SCD Type:** 2
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
WITH twine AS (
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
         val_str, val_num,
         'PRODUCT_PRODUCT_NAME' AS timeline
  FROM daana_dw.product_desc WHERE type_key = 22
  UNION ALL
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
         val_str, val_num,
         'PRODUCT_PRODUCT_NUMBER' AS timeline
  FROM daana_dw.product_desc WHERE type_key = 14
  UNION ALL
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
         val_str, val_num,
         'PRODUCT_PRODUCT_COLOR' AS timeline
  FROM daana_dw.product_desc WHERE type_key = 118
  UNION ALL
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
         val_str, val_num,
         'PRODUCT_PRODUCT_LIST_PRICE' AS timeline
  FROM daana_dw.product_desc WHERE type_key = 50
),

in_effect AS (
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
    val_str, val_num,
    MAX(CASE WHEN timeline = 'PRODUCT_PRODUCT_NAME' THEN eff_tmstp END)
      OVER (PARTITION BY product_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_product_product_name,
    MAX(CASE WHEN timeline = 'PRODUCT_PRODUCT_NUMBER' THEN eff_tmstp END)
      OVER (PARTITION BY product_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_product_product_number,
    MAX(CASE WHEN timeline = 'PRODUCT_PRODUCT_COLOR' THEN eff_tmstp END)
      OVER (PARTITION BY product_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_product_product_color,
    MAX(CASE WHEN timeline = 'PRODUCT_PRODUCT_LIST_PRICE' THEN eff_tmstp END)
      OVER (PARTITION BY product_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_product_product_list_price,
    RANK() OVER (PARTITION BY product_key, eff_tmstp ORDER BY eff_tmstp DESC) AS rn
  FROM twine
),

filtered_in_effect AS (SELECT * FROM in_effect WHERE rn = 1),

cte_product_name AS (
  SELECT product_key, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN val_str ELSE NULL END AS product_name
  FROM filtered_in_effect WHERE type_key = 22
),

cte_product_number AS (
  SELECT product_key, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN val_str ELSE NULL END AS product_number
  FROM filtered_in_effect WHERE type_key = 14
),

cte_product_color AS (
  SELECT product_key, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN val_str ELSE NULL END AS product_color
  FROM filtered_in_effect WHERE type_key = 118
),

cte_product_list_price AS (
  SELECT product_key, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN val_num ELSE NULL END AS product_list_price
  FROM filtered_in_effect WHERE type_key = 50
),

pivoted AS (
  SELECT DISTINCT
    fie.product_key,
    fie.eff_tmstp,
    cn.product_name,
    cnum.product_number,
    cc.product_color,
    cp.product_list_price
  FROM filtered_in_effect fie
  LEFT JOIN cte_product_name cn
    ON fie.product_key = cn.product_key
    AND fie.eff_tmstp_product_product_name = cn.eff_tmstp
  LEFT JOIN cte_product_number cnum
    ON fie.product_key = cnum.product_key
    AND fie.eff_tmstp_product_product_number = cnum.eff_tmstp
  LEFT JOIN cte_product_color cc
    ON fie.product_key = cc.product_key
    AND fie.eff_tmstp_product_product_color = cc.eff_tmstp
  LEFT JOIN cte_product_list_price cp
    ON fie.product_key = cp.product_key
    AND fie.eff_tmstp_product_product_list_price = cp.eff_tmstp
)

SELECT
  ROW_NUMBER() OVER (ORDER BY product_key, eff_tmstp) AS dim_surrogate_key,
  product_key,
  product_name,
  product_number,
  product_color,
  product_list_price,
  eff_tmstp AS effective_from,
  COALESCE(
    LEAD(eff_tmstp) OVER (PARTITION BY product_key ORDER BY eff_tmstp),
    '9999-12-31'::timestamp
  ) AS effective_to,
  CASE
    WHEN LEAD(eff_tmstp) OVER (PARTITION BY product_key ORDER BY eff_tmstp) IS NULL THEN 'Y'
    ELSE 'N'
  END AS is_current
FROM pivoted;
```
