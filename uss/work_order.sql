CREATE OR REPLACE VIEW uss.work_order AS
WITH ranked AS (
    SELECT
        WORK_ORDER_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        RANK() OVER (
            PARTITION BY WORK_ORDER_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.WORK_ORDER_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: WORK_ORDER -> PRODUCT (TYPE_KEY=74)
ranked_wo_product_x AS (
    SELECT
        WORK_ORDER_KEY,
        EFF_TMSTP,
        PRODUCT_KEY,
        RANK() OVER (
            PARTITION BY WORK_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.WORK_ORDER_PRODUCT_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 74
),
rel_product AS (
    SELECT WORK_ORDER_KEY, EFF_TMSTP, PRODUCT_KEY
    FROM ranked_wo_product_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT WORK_ORDER_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT WORK_ORDER_KEY, EFF_TMSTP
    FROM rel_product
),
pivoted AS (
    SELECT
        t.WORK_ORDER_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 52 THEN d.END_TMSTP END) OVER (
            PARTITION BY t.WORK_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS work_order_due_date,
        MAX(CASE WHEN d.TYPE_KEY = 29 THEN d.END_TMSTP END) OVER (
            PARTITION BY t.WORK_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS work_order_end_date,
        MAX(CASE WHEN d.TYPE_KEY = 4 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.WORK_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS work_order_order_qty,
        MAX(CASE WHEN d.TYPE_KEY = 73 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.WORK_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS work_order_scrapped_qty,
        MAX(CASE WHEN d.TYPE_KEY = 128 THEN d.STA_TMSTP END) OVER (
            PARTITION BY t.WORK_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS work_order_start_date,
        MAX(r_product.PRODUCT_KEY) OVER (
            PARTITION BY t.WORK_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PRODUCT_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.WORK_ORDER_KEY = d.WORK_ORDER_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_product r_product ON t.WORK_ORDER_KEY = r_product.WORK_ORDER_KEY AND t.EFF_TMSTP = r_product.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.WORK_ORDER_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.WORK_ORDER_KEY,
        p.work_order_due_date,
        p.work_order_end_date,
        p.work_order_order_qty,
        p.work_order_scrapped_qty,
        p.work_order_start_date,
        p.PRODUCT_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.WORK_ORDER_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.WORK_ORDER_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS WORK_ORDER_KEY,
    NULL::timestamp AS work_order_due_date,
    NULL::timestamp AS work_order_end_date,
    NULL::numeric AS work_order_order_qty,
    NULL::numeric AS work_order_scrapped_qty,
    NULL::timestamp AS work_order_start_date,
    NULL AS PRODUCT_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
