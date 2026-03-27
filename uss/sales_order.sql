CREATE OR REPLACE VIEW uss.sales_order AS
WITH ranked AS (
    SELECT
        SALES_ORDER_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_STR,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        RANK() OVER (
            PARTITION BY SALES_ORDER_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER -> CUSTOMER (TYPE_KEY=7)
ranked_sales_order_customer_x AS (
    SELECT
        SALES_ORDER_KEY,
        EFF_TMSTP,
        CUSTOMER_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_CUSTOMER_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 7
),
rel_customer AS (
    SELECT SALES_ORDER_KEY, EFF_TMSTP, CUSTOMER_KEY
    FROM ranked_sales_order_customer_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER -> ADDRESS (billed_to, TYPE_KEY=189)
ranked_sales_order_bill_address_x AS (
    SELECT
        SALES_ORDER_KEY,
        EFF_TMSTP,
        ADDRESS_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_ADDRESS_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 189
),
rel_bill_address AS (
    SELECT SALES_ORDER_KEY, EFF_TMSTP, ADDRESS_KEY
    FROM ranked_sales_order_bill_address_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER -> ADDRESS (shipped_to, TYPE_KEY=190)
ranked_sales_order_ship_address_x AS (
    SELECT
        SALES_ORDER_KEY,
        EFF_TMSTP,
        ADDRESS_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_ADDRESS_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 190
),
rel_ship_address AS (
    SELECT SALES_ORDER_KEY, EFF_TMSTP, ADDRESS_KEY
    FROM ranked_sales_order_ship_address_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER -> SALES_PERSON (TYPE_KEY=117)
ranked_sales_order_sales_person_x AS (
    SELECT
        SALES_ORDER_KEY,
        EFF_TMSTP,
        SALES_PERSON_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_SALES_PERSON_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 117
),
rel_sales_person AS (
    SELECT SALES_ORDER_KEY, EFF_TMSTP, SALES_PERSON_KEY
    FROM ranked_sales_order_sales_person_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER -> SALES_TERRITORY (TYPE_KEY=21)
ranked_sales_order_sales_territory_x AS (
    SELECT
        SALES_ORDER_KEY,
        EFF_TMSTP,
        SALES_TERRITORY_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_SALES_TERRITORY_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 21
),
rel_sales_territory AS (
    SELECT SALES_ORDER_KEY, EFF_TMSTP, SALES_TERRITORY_KEY
    FROM ranked_sales_order_sales_territory_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT SALES_ORDER_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT SALES_ORDER_KEY, EFF_TMSTP
    FROM rel_customer
    UNION
    SELECT DISTINCT SALES_ORDER_KEY, EFF_TMSTP
    FROM rel_bill_address
    UNION
    SELECT DISTINCT SALES_ORDER_KEY, EFF_TMSTP
    FROM rel_ship_address
    UNION
    SELECT DISTINCT SALES_ORDER_KEY, EFF_TMSTP
    FROM rel_sales_person
    UNION
    SELECT DISTINCT SALES_ORDER_KEY, EFF_TMSTP
    FROM rel_sales_territory
),
pivoted AS (
    SELECT
        t.SALES_ORDER_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 95 THEN d.VAL_STR END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_account_number,
        MAX(CASE WHEN d.TYPE_KEY = 58 THEN d.VAL_STR END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_comment,
        MAX(CASE WHEN d.TYPE_KEY = 76 THEN d.END_TMSTP END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_due_date,
        MAX(CASE WHEN d.TYPE_KEY = 126 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_freight,
        MAX(CASE WHEN d.TYPE_KEY = 87 THEN d.VAL_STR END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_online_order_flag,
        MAX(CASE WHEN d.TYPE_KEY = 55 THEN d.STA_TMSTP END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_order_date,
        MAX(CASE WHEN d.TYPE_KEY = 26 THEN d.VAL_STR END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_purchase_order_number,
        MAX(CASE WHEN d.TYPE_KEY = 10 THEN d.END_TMSTP END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_ship_date,
        MAX(CASE WHEN d.TYPE_KEY = 71 THEN d.VAL_STR END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_status,
        MAX(CASE WHEN d.TYPE_KEY = 110 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_sub_total,
        MAX(CASE WHEN d.TYPE_KEY = 17 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_tax_amt,
        MAX(r_customer.CUSTOMER_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS CUSTOMER_KEY,
        MAX(r_bill_address.ADDRESS_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS BILL_TO_ADDRESS_KEY,
        MAX(r_ship_address.ADDRESS_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SHIP_TO_ADDRESS_KEY,
        MAX(r_sales_person.SALES_PERSON_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SALES_PERSON_KEY,
        MAX(r_sales_territory.SALES_TERRITORY_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SALES_TERRITORY_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.SALES_ORDER_KEY = d.SALES_ORDER_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_customer r_customer ON t.SALES_ORDER_KEY = r_customer.SALES_ORDER_KEY AND t.EFF_TMSTP = r_customer.EFF_TMSTP
    LEFT JOIN rel_bill_address r_bill_address ON t.SALES_ORDER_KEY = r_bill_address.SALES_ORDER_KEY AND t.EFF_TMSTP = r_bill_address.EFF_TMSTP
    LEFT JOIN rel_ship_address r_ship_address ON t.SALES_ORDER_KEY = r_ship_address.SALES_ORDER_KEY AND t.EFF_TMSTP = r_ship_address.EFF_TMSTP
    LEFT JOIN rel_sales_person r_sales_person ON t.SALES_ORDER_KEY = r_sales_person.SALES_ORDER_KEY AND t.EFF_TMSTP = r_sales_person.EFF_TMSTP
    LEFT JOIN rel_sales_territory r_sales_territory ON t.SALES_ORDER_KEY = r_sales_territory.SALES_ORDER_KEY AND t.EFF_TMSTP = r_sales_territory.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.SALES_ORDER_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.SALES_ORDER_KEY,
        p.sales_order_account_number,
        p.sales_order_comment,
        p.sales_order_due_date,
        p.sales_order_freight,
        p.sales_order_online_order_flag,
        p.sales_order_order_date,
        p.sales_order_purchase_order_number,
        p.sales_order_ship_date,
        p.sales_order_status,
        p.sales_order_sub_total,
        p.sales_order_tax_amt,
        p.CUSTOMER_KEY,
        p.BILL_TO_ADDRESS_KEY,
        p.SHIP_TO_ADDRESS_KEY,
        p.SALES_PERSON_KEY,
        p.SALES_TERRITORY_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.SALES_ORDER_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.SALES_ORDER_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS SALES_ORDER_KEY,
    NULL AS sales_order_account_number,
    NULL AS sales_order_comment,
    NULL::timestamp AS sales_order_due_date,
    NULL::numeric AS sales_order_freight,
    NULL AS sales_order_online_order_flag,
    NULL::timestamp AS sales_order_order_date,
    NULL AS sales_order_purchase_order_number,
    NULL::timestamp AS sales_order_ship_date,
    NULL AS sales_order_status,
    NULL::numeric AS sales_order_sub_total,
    NULL::numeric AS sales_order_tax_amt,
    NULL AS CUSTOMER_KEY,
    NULL AS BILL_TO_ADDRESS_KEY,
    NULL AS SHIP_TO_ADDRESS_KEY,
    NULL AS SALES_PERSON_KEY,
    NULL AS SALES_TERRITORY_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
