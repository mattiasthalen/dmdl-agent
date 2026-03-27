CREATE OR REPLACE VIEW uss.sales_order_detail AS
WITH ranked AS (
    SELECT
        SALES_ORDER_DETAIL_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_STR,
        VAL_NUM,
        RANK() OVER (
            PARTITION BY SALES_ORDER_DETAIL_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_DETAIL_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER_DETAIL -> SALES_ORDER (TYPE_KEY=48)
ranked_sod_sales_order_x AS (
    SELECT
        SALES_ORDER_DETAIL_KEY,
        EFF_TMSTP,
        SALES_ORDER_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_DETAIL_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_DETAIL_SALES_ORDER_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 48
),
rel_sales_order AS (
    SELECT SALES_ORDER_DETAIL_KEY, EFF_TMSTP, SALES_ORDER_KEY
    FROM ranked_sod_sales_order_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER_DETAIL -> PRODUCT (TYPE_KEY=20)
ranked_sod_product_x AS (
    SELECT
        SALES_ORDER_DETAIL_KEY,
        EFF_TMSTP,
        PRODUCT_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_DETAIL_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_DETAIL_PRODUCT_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 20
),
rel_product AS (
    SELECT SALES_ORDER_DETAIL_KEY, EFF_TMSTP, PRODUCT_KEY
    FROM ranked_sod_product_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_ORDER_DETAIL -> SPECIAL_OFFER (TYPE_KEY=3)
ranked_sod_special_offer_x AS (
    SELECT
        SALES_ORDER_DETAIL_KEY,
        EFF_TMSTP,
        SPECIAL_OFFER_KEY,
        RANK() OVER (
            PARTITION BY SALES_ORDER_DETAIL_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_ORDER_DETAIL_SPECIAL_OFFER_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 3
),
rel_special_offer AS (
    SELECT SALES_ORDER_DETAIL_KEY, EFF_TMSTP, SPECIAL_OFFER_KEY
    FROM ranked_sod_special_offer_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT SALES_ORDER_DETAIL_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT SALES_ORDER_DETAIL_KEY, EFF_TMSTP
    FROM rel_sales_order
    UNION
    SELECT DISTINCT SALES_ORDER_DETAIL_KEY, EFF_TMSTP
    FROM rel_product
    UNION
    SELECT DISTINCT SALES_ORDER_DETAIL_KEY, EFF_TMSTP
    FROM rel_special_offer
),
pivoted AS (
    SELECT
        t.SALES_ORDER_DETAIL_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 131 THEN d.VAL_STR END) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_detail_carrier_tracking_number,
        MAX(CASE WHEN d.TYPE_KEY = 60 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_detail_order_qty,
        MAX(CASE WHEN d.TYPE_KEY = 129 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_detail_unit_price,
        MAX(CASE WHEN d.TYPE_KEY = 36 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_order_detail_unit_price_discount,
        MAX(r_sales_order.SALES_ORDER_KEY) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SALES_ORDER_KEY,
        MAX(r_product.PRODUCT_KEY) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PRODUCT_KEY,
        MAX(r_special_offer.SPECIAL_OFFER_KEY) OVER (
            PARTITION BY t.SALES_ORDER_DETAIL_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SPECIAL_OFFER_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.SALES_ORDER_DETAIL_KEY = d.SALES_ORDER_DETAIL_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_sales_order r_sales_order ON t.SALES_ORDER_DETAIL_KEY = r_sales_order.SALES_ORDER_DETAIL_KEY AND t.EFF_TMSTP = r_sales_order.EFF_TMSTP
    LEFT JOIN rel_product r_product ON t.SALES_ORDER_DETAIL_KEY = r_product.SALES_ORDER_DETAIL_KEY AND t.EFF_TMSTP = r_product.EFF_TMSTP
    LEFT JOIN rel_special_offer r_special_offer ON t.SALES_ORDER_DETAIL_KEY = r_special_offer.SALES_ORDER_DETAIL_KEY AND t.EFF_TMSTP = r_special_offer.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.SALES_ORDER_DETAIL_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.SALES_ORDER_DETAIL_KEY,
        p.sales_order_detail_carrier_tracking_number,
        p.sales_order_detail_order_qty,
        p.sales_order_detail_unit_price,
        p.sales_order_detail_unit_price_discount,
        p.SALES_ORDER_KEY,
        p.PRODUCT_KEY,
        p.SPECIAL_OFFER_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.SALES_ORDER_DETAIL_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.SALES_ORDER_DETAIL_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS SALES_ORDER_DETAIL_KEY,
    NULL AS sales_order_detail_carrier_tracking_number,
    NULL::numeric AS sales_order_detail_order_qty,
    NULL::numeric AS sales_order_detail_unit_price,
    NULL::numeric AS sales_order_detail_unit_price_discount,
    NULL AS SALES_ORDER_KEY,
    NULL AS PRODUCT_KEY,
    NULL AS SPECIAL_OFFER_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
