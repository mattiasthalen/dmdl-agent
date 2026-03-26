# Test: Periodic Snapshot Fact — Monthly Sales Order Summary

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** SALES_ORDER
- **Type:** Fact
- **Fact Type:** Periodic Snapshot
- **Materialization:** View
- **Output folder:** star/
- **Target schema:** star
- **Grain:** One row per month per customer
- **Measures:**
  - sales_order_sub_total (TYPE_KEY 110, VAL_NUM)
  - sales_order_tax_amt (TYPE_KEY 17, VAL_NUM)
  - sales_order_freight (TYPE_KEY 126, VAL_NUM)
- **Dimension FKs:**
  - CUSTOMER via SALES_ORDER_CUSTOMER_X (TYPE_KEY 7, SALES_ORDER_KEY / CUSTOMER_KEY)
- **Event date:** order_date (TYPE_KEY 55, STA_TMSTP), truncated to month

## Expected Output

### fact_sales_order_monthly.sql

```sql
CREATE OR REPLACE VIEW star.fact_sales_order_monthly AS
WITH fact_measures AS (
  SELECT
    sales_order_key,
    MAX(CASE WHEN type_key = 110 THEN val_num END) AS sales_order_sub_total,
    MAX(CASE WHEN type_key = 17 THEN val_num END) AS sales_order_tax_amt,
    MAX(CASE WHEN type_key = 126 THEN val_num END) AS sales_order_freight,
    MAX(CASE WHEN type_key = 55 THEN sta_tmstp END) AS order_date
  FROM (
    SELECT sales_order_key, type_key, row_st, val_num, sta_tmstp,
      RANK() OVER (
        PARTITION BY sales_order_key, type_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_desc
    WHERE type_key IN (110, 17, 126, 55)
  ) a
  WHERE nbr = 1 AND row_st = 'Y'
  GROUP BY sales_order_key
),

rel_customer AS (
  SELECT sales_order_key, customer_key FROM (
    SELECT sales_order_key, customer_key, row_st,
      RANK() OVER (
        PARTITION BY sales_order_key, customer_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_customer_x
    WHERE type_key = 7
  ) a WHERE nbr = 1 AND row_st = 'Y'
),

transaction_fact AS (
  SELECT
    fm.sales_order_key,
    fm.order_date,
    rc.customer_key,
    fm.sales_order_sub_total,
    fm.sales_order_tax_amt,
    fm.sales_order_freight
  FROM fact_measures fm
  JOIN rel_customer rc ON fm.sales_order_key = rc.sales_order_key
)

SELECT
  DATE_TRUNC('month', order_date) AS period_start,
  customer_key,
  SUM(sales_order_sub_total) AS total_sub_total,
  SUM(sales_order_tax_amt) AS total_tax_amt,
  SUM(sales_order_freight) AS total_freight,
  COUNT(*) AS order_count
FROM transaction_fact
GROUP BY DATE_TRUNC('month', order_date), customer_key
ORDER BY period_start, customer_key;
```
