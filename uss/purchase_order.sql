CREATE OR REPLACE VIEW uss.purchase_order AS
WITH ranked AS (
    SELECT
        PURCHASE_ORDER_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_STR,
        VAL_NUM,
        STA_TMSTP,
        END_TMSTP,
        RANK() OVER (
            PARTITION BY PURCHASE_ORDER_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.PURCHASE_ORDER_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: PURCHASE_ORDER -> EMPLOYEE (TYPE_KEY=30)
ranked_po_employee_x AS (
    SELECT
        PURCHASE_ORDER_KEY,
        EFF_TMSTP,
        EMPLOYEE_KEY,
        RANK() OVER (
            PARTITION BY PURCHASE_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.PURCHASE_ORDER_EMPLOYEE_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 30
),
rel_employee AS (
    SELECT PURCHASE_ORDER_KEY, EFF_TMSTP, EMPLOYEE_KEY
    FROM ranked_po_employee_x
    WHERE rnk = 1
),
-- Resolve relationships: PURCHASE_ORDER -> VENDOR (TYPE_KEY=12)
ranked_po_vendor_x AS (
    SELECT
        PURCHASE_ORDER_KEY,
        EFF_TMSTP,
        VENDOR_KEY,
        RANK() OVER (
            PARTITION BY PURCHASE_ORDER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.PURCHASE_ORDER_VENDOR_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 12
),
rel_vendor AS (
    SELECT PURCHASE_ORDER_KEY, EFF_TMSTP, VENDOR_KEY
    FROM ranked_po_vendor_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT PURCHASE_ORDER_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT PURCHASE_ORDER_KEY, EFF_TMSTP
    FROM rel_employee
    UNION
    SELECT DISTINCT PURCHASE_ORDER_KEY, EFF_TMSTP
    FROM rel_vendor
),
pivoted AS (
    SELECT
        t.PURCHASE_ORDER_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 56 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_freight,
        MAX(CASE WHEN d.TYPE_KEY = 98 THEN d.STA_TMSTP END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_order_date,
        MAX(CASE WHEN d.TYPE_KEY = 32 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_revision_number,
        MAX(CASE WHEN d.TYPE_KEY = 8 THEN d.END_TMSTP END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_ship_date,
        MAX(CASE WHEN d.TYPE_KEY = 121 THEN d.VAL_STR END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_status,
        MAX(CASE WHEN d.TYPE_KEY = 61 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_sub_total,
        MAX(CASE WHEN d.TYPE_KEY = 51 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS purchase_order_tax_amt,
        MAX(r_employee.EMPLOYEE_KEY) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS EMPLOYEE_KEY,
        MAX(r_vendor.VENDOR_KEY) OVER (
            PARTITION BY t.PURCHASE_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS VENDOR_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.PURCHASE_ORDER_KEY = d.PURCHASE_ORDER_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_employee r_employee ON t.PURCHASE_ORDER_KEY = r_employee.PURCHASE_ORDER_KEY AND t.EFF_TMSTP = r_employee.EFF_TMSTP
    LEFT JOIN rel_vendor r_vendor ON t.PURCHASE_ORDER_KEY = r_vendor.PURCHASE_ORDER_KEY AND t.EFF_TMSTP = r_vendor.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.PURCHASE_ORDER_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.PURCHASE_ORDER_KEY,
        p.purchase_order_freight,
        p.purchase_order_order_date,
        p.purchase_order_revision_number,
        p.purchase_order_ship_date,
        p.purchase_order_status,
        p.purchase_order_sub_total,
        p.purchase_order_tax_amt,
        p.EMPLOYEE_KEY,
        p.VENDOR_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.PURCHASE_ORDER_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.PURCHASE_ORDER_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS PURCHASE_ORDER_KEY,
    NULL::numeric AS purchase_order_freight,
    NULL::timestamp AS purchase_order_order_date,
    NULL::numeric AS purchase_order_revision_number,
    NULL::timestamp AS purchase_order_ship_date,
    NULL AS purchase_order_status,
    NULL::numeric AS purchase_order_sub_total,
    NULL::numeric AS purchase_order_tax_amt,
    NULL AS EMPLOYEE_KEY,
    NULL AS VENDOR_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
