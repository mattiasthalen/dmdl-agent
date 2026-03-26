# Test: Dimension Mixed SCD Types — Product with Type 0 + 1 + 2

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** PRODUCT
- **Type:** Dimension
- **SCD Type:** Mixed
- **Materialization:** View
- **Output folder:** star/
- **Target schema:** star
- **Attributes:**
  - product_name (TYPE_KEY 22, VAL_STR) — Type 0 (retain original name)
  - product_number (TYPE_KEY 14, VAL_STR) — Type 1 (current number)
  - product_list_price (TYPE_KEY 50, VAL_NUM) — Type 2 (full price history)
  - product_color (TYPE_KEY 118, VAL_STR) — Type 2 (full color history)

## Expected Output

### dim_product.sql

```sql
CREATE OR REPLACE VIEW star.dim_product AS
WITH twine AS (
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
         val_str, val_num,
         'PRODUCT_PRODUCT_LIST_PRICE' AS timeline
  FROM daana_dw.product_desc WHERE type_key = 50
  UNION ALL
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
         val_str, val_num,
         'PRODUCT_PRODUCT_COLOR' AS timeline
  FROM daana_dw.product_desc WHERE type_key = 118
),

in_effect AS (
  SELECT product_key, type_key, eff_tmstp, ver_tmstp, row_st,
    val_str, val_num,
    MAX(CASE WHEN timeline = 'PRODUCT_PRODUCT_LIST_PRICE' THEN eff_tmstp END)
      OVER (PARTITION BY product_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_product_product_list_price,
    MAX(CASE WHEN timeline = 'PRODUCT_PRODUCT_COLOR' THEN eff_tmstp END)
      OVER (PARTITION BY product_key ORDER BY eff_tmstp
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS eff_tmstp_product_product_color,
    RANK() OVER (PARTITION BY product_key, eff_tmstp ORDER BY eff_tmstp DESC) AS rn
  FROM twine
),

filtered_in_effect AS (SELECT * FROM in_effect WHERE rn = 1),

cte_product_list_price AS (
  SELECT product_key, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN val_num ELSE NULL END AS product_list_price
  FROM filtered_in_effect WHERE type_key = 50
),

cte_product_color AS (
  SELECT product_key, eff_tmstp,
    CASE WHEN row_st = 'Y' THEN val_str ELSE NULL END AS product_color
  FROM filtered_in_effect WHERE type_key = 118
),

pivoted AS (
  SELECT DISTINCT
    fie.product_key,
    fie.eff_tmstp,
    cp.product_list_price,
    cc.product_color
  FROM filtered_in_effect fie
  LEFT JOIN cte_product_list_price cp
    ON fie.product_key = cp.product_key
    AND fie.eff_tmstp_product_product_list_price = cp.eff_tmstp
  LEFT JOIN cte_product_color cc
    ON fie.product_key = cc.product_key
    AND fie.eff_tmstp_product_product_color = cc.eff_tmstp
),

versioned AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY product_key, eff_tmstp) AS dim_surrogate_key,
    product_key,
    product_list_price,
    product_color,
    eff_tmstp AS effective_from,
    COALESCE(
      LEAD(eff_tmstp) OVER (PARTITION BY product_key ORDER BY eff_tmstp),
      '9999-12-31'::timestamp
    ) AS effective_to,
    CASE
      WHEN LEAD(eff_tmstp) OVER (PARTITION BY product_key ORDER BY eff_tmstp) IS NULL THEN 'Y'
      ELSE 'N'
    END AS is_current
  FROM pivoted
),

type0_attrs AS (
  SELECT product_key,
    MAX(CASE WHEN type_key = 22 THEN val_str END) AS product_name
  FROM (
    SELECT product_key, type_key, row_st, val_str,
      RANK() OVER (PARTITION BY product_key, type_key ORDER BY eff_tmstp ASC, ver_tmstp ASC) AS nbr
    FROM daana_dw.product_desc
    WHERE type_key IN (22)
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY product_key
),

type1_attrs AS (
  SELECT product_key,
    MAX(CASE WHEN type_key = 14 THEN val_str END) AS product_number
  FROM (
    SELECT product_key, type_key, row_st, val_str,
      RANK() OVER (PARTITION BY product_key, type_key ORDER BY eff_tmstp DESC, ver_tmstp DESC) AS nbr
    FROM daana_dw.product_desc
    WHERE type_key IN (14)
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY product_key
)

SELECT
  v.dim_surrogate_key,
  v.product_key,
  t0.product_name,
  t1.product_number,
  v.product_list_price,
  v.product_color,
  v.effective_from,
  v.effective_to,
  v.is_current
FROM versioned v
LEFT JOIN type0_attrs t0 ON v.product_key = t0.product_key
LEFT JOIN type1_attrs t1 ON v.product_key = t1.product_key;
```
