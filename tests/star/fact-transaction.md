# Test: Transaction Fact — Sales Order Detail

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** SALES_ORDER_DETAIL
- **Type:** Fact
- **Fact Type:** Transaction
- **Materialization:** View
- **Output folder:** star/
- **Target schema:** star
- **Grain:** One row per sales order detail
- **Measures:**
  - sales_order_detail_order_qty (TYPE_KEY 60, VAL_NUM)
  - sales_order_detail_unit_price (TYPE_KEY 129, VAL_NUM)
  - sales_order_detail_unit_price_discount (TYPE_KEY 36, VAL_NUM)
- **Dimension FKs:**
  - PRODUCT via SALES_ORDER_DETAIL_PRODUCT_X (TYPE_KEY 20, SALES_ORDER_DETAIL_KEY / PRODUCT_KEY)
  - SALES_ORDER via SALES_ORDER_DETAIL_SALES_ORDER_X (TYPE_KEY 48, SALES_ORDER_DETAIL_KEY / SALES_ORDER_KEY)
  - SPECIAL_OFFER via SALES_ORDER_DETAIL_SPECIAL_OFFER_X (TYPE_KEY 3, SALES_ORDER_DETAIL_KEY / SPECIAL_OFFER_KEY)
- **Event date:** Inherited from SALES_ORDER via multi-hop (SOD -> SO -> order_date, TYPE_KEY 55, STA_TMSTP)

## Expected Output

### fact_sales_order_detail.sql

```sql
CREATE OR REPLACE VIEW star.fact_sales_order_detail AS
WITH fact_measures AS (
  SELECT
    sales_order_detail_key,
    MAX(CASE WHEN type_key = 60 THEN val_num END) AS sales_order_detail_order_qty,
    MAX(CASE WHEN type_key = 129 THEN val_num END) AS sales_order_detail_unit_price,
    MAX(CASE WHEN type_key = 36 THEN val_num END) AS sales_order_detail_unit_price_discount
  FROM (
    SELECT sales_order_detail_key, type_key, row_st, val_num,
      RANK() OVER (
        PARTITION BY sales_order_detail_key, type_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_detail_desc
    WHERE type_key IN (60, 129, 36)
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY sales_order_detail_key
),

rel_product AS (
  SELECT sales_order_detail_key, product_key FROM (
    SELECT sales_order_detail_key, product_key, row_st,
      RANK() OVER (
        PARTITION BY sales_order_detail_key, product_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_detail_product_x
    WHERE type_key = 20
  ) a WHERE nbr = 1 AND row_st = 'Y'
),

rel_sales_order AS (
  SELECT sales_order_detail_key, sales_order_key FROM (
    SELECT sales_order_detail_key, sales_order_key, row_st,
      RANK() OVER (
        PARTITION BY sales_order_detail_key, sales_order_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_detail_sales_order_x
    WHERE type_key = 48
  ) a WHERE nbr = 1 AND row_st = 'Y'
),

rel_special_offer AS (
  SELECT sales_order_detail_key, special_offer_key FROM (
    SELECT sales_order_detail_key, special_offer_key, row_st,
      RANK() OVER (
        PARTITION BY sales_order_detail_key, special_offer_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_detail_special_offer_x
    WHERE type_key = 3
  ) a WHERE nbr = 1 AND row_st = 'Y'
),

fact_date AS (
  SELECT sales_order_key,
    MAX(CASE WHEN type_key = 55 THEN sta_tmstp END) AS order_date
  FROM (
    SELECT sales_order_key, type_key, row_st, sta_tmstp,
      RANK() OVER (
        PARTITION BY sales_order_key, type_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_desc
    WHERE type_key = 55
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY sales_order_key
)

SELECT
  fm.sales_order_detail_key,
  fd.order_date,
  rp.product_key,
  rso.sales_order_key,
  rspo.special_offer_key,
  fm.sales_order_detail_order_qty,
  fm.sales_order_detail_unit_price,
  fm.sales_order_detail_unit_price_discount,
  ROUND((fm.sales_order_detail_unit_price * fm.sales_order_detail_order_qty * (1 - fm.sales_order_detail_unit_price_discount))::numeric, 2) AS line_total
FROM fact_measures fm
JOIN rel_sales_order rso ON fm.sales_order_detail_key = rso.sales_order_detail_key
JOIN fact_date fd ON rso.sales_order_key = fd.sales_order_key
JOIN rel_product rp ON fm.sales_order_detail_key = rp.sales_order_detail_key
JOIN rel_special_offer rspo ON fm.sales_order_detail_key = rspo.sales_order_detail_key;
```
