# Test: Factless Fact — Sales Order Detail Coverage

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** SALES_ORDER_DETAIL
- **Type:** Fact
- **Fact Type:** Factless
- **Materialization:** View
- **Output folder:** star/
- **Target schema:** star
- **Grain:** One row per sales order detail
- **Measures:** None
- **Dimension FKs:**
  - PRODUCT via SALES_ORDER_DETAIL_PRODUCT_X (TYPE_KEY 20, SALES_ORDER_DETAIL_KEY / PRODUCT_KEY)
  - SALES_ORDER via SALES_ORDER_DETAIL_SALES_ORDER_X (TYPE_KEY 48, SALES_ORDER_DETAIL_KEY / SALES_ORDER_KEY)
  - SPECIAL_OFFER via SALES_ORDER_DETAIL_SPECIAL_OFFER_X (TYPE_KEY 3, SALES_ORDER_DETAIL_KEY / SPECIAL_OFFER_KEY)

## Expected Output

### fact_sales_order_detail_coverage.sql

```sql
CREATE OR REPLACE VIEW star.fact_sales_order_detail_coverage AS
WITH rel_product AS (
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
)

SELECT
  rp.sales_order_detail_key,
  rp.product_key,
  rso.sales_order_key,
  rspo.special_offer_key
FROM rel_product rp
JOIN rel_sales_order rso ON rp.sales_order_detail_key = rso.sales_order_detail_key
JOIN rel_special_offer rspo ON rp.sales_order_detail_key = rspo.sales_order_detail_key;
```
