# Test: Accumulating Snapshot Fact — Sales Order Lifecycle

Read @bootstrap-context.md and @connection-context.md before proceeding.

## Skill

`/daana-star`

## Inputs

- **Entity:** SALES_ORDER
- **Type:** Fact
- **Fact Type:** Accumulating Snapshot
- **Materialization:** View
- **Output folder:** star/
- **Target schema:** star
- **Grain:** One row per sales order
- **Milestone timestamps:**
  - order_date (TYPE_KEY 55, STA_TMSTP)
  - ship_date (TYPE_KEY 10, END_TMSTP)
  - due_date (TYPE_KEY 76, END_TMSTP)
- **Measures:**
  - sales_order_sub_total (TYPE_KEY 110, VAL_NUM)
  - sales_order_tax_amt (TYPE_KEY 17, VAL_NUM)
  - sales_order_freight (TYPE_KEY 126, VAL_NUM)
- **Dimension FKs:**
  - CUSTOMER via SALES_ORDER_CUSTOMER_X (TYPE_KEY 7, SALES_ORDER_KEY / CUSTOMER_KEY)

## Expected Output

### fact_sales_order_lifecycle.sql

```sql
CREATE OR REPLACE VIEW star.fact_sales_order_lifecycle AS
WITH order_snapshot AS (
  SELECT
    sales_order_key,
    MAX(CASE WHEN type_key = 55 THEN sta_tmstp END) AS order_date,
    MAX(CASE WHEN type_key = 10 THEN end_tmstp END) AS ship_date,
    MAX(CASE WHEN type_key = 76 THEN end_tmstp END) AS due_date,
    MAX(CASE WHEN type_key = 110 THEN val_num END) AS sales_order_sub_total,
    MAX(CASE WHEN type_key = 17 THEN val_num END) AS sales_order_tax_amt,
    MAX(CASE WHEN type_key = 126 THEN val_num END) AS sales_order_freight
  FROM (
    SELECT sales_order_key, type_key, row_st,
      sta_tmstp, end_tmstp, val_num,
      RANK() OVER (
        PARTITION BY sales_order_key, type_key
        ORDER BY eff_tmstp DESC, ver_tmstp DESC
      ) AS nbr
    FROM daana_dw.sales_order_desc
    WHERE type_key IN (55, 10, 76, 110, 17, 126)
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
)

SELECT
  os.sales_order_key,
  os.order_date,
  os.ship_date,
  os.due_date,
  EXTRACT(DAY FROM os.ship_date - os.order_date) AS days_to_ship,
  EXTRACT(DAY FROM os.due_date - os.order_date) AS days_allowed,
  EXTRACT(DAY FROM os.ship_date - os.due_date) AS days_late,
  CASE
    WHEN os.ship_date IS NOT NULL AND os.ship_date <= os.due_date THEN 'ON_TIME'
    WHEN os.ship_date IS NOT NULL AND os.ship_date > os.due_date THEN 'LATE'
    WHEN os.ship_date IS NULL THEN 'NOT_SHIPPED'
  END AS fulfillment_status,
  os.sales_order_sub_total,
  os.sales_order_tax_amt,
  os.sales_order_freight,
  rc.customer_key
FROM order_snapshot os
JOIN rel_customer rc ON os.sales_order_key = rc.sales_order_key;
```
