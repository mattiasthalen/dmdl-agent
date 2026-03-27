CREATE OR REPLACE VIEW uss.vendor AS
WITH ranked AS (
    SELECT
        VENDOR_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_STR,
        VAL_NUM,
        RANK() OVER (
            PARTITION BY VENDOR_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.VENDOR_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: VENDOR -> PERSON (TYPE_KEY=91)
ranked_vendor_person_x AS (
    SELECT
        VENDOR_KEY,
        EFF_TMSTP,
        PERSON_KEY,
        RANK() OVER (
            PARTITION BY VENDOR_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.VENDOR_PERSON_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 91
),
rel_person AS (
    SELECT VENDOR_KEY, EFF_TMSTP, PERSON_KEY
    FROM ranked_vendor_person_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT VENDOR_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT VENDOR_KEY, EFF_TMSTP
    FROM rel_person
),
pivoted AS (
    SELECT
        t.VENDOR_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 99 THEN d.VAL_STR END) OVER (
            PARTITION BY t.VENDOR_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS vendor_account_number,
        MAX(CASE WHEN d.TYPE_KEY = 86 THEN d.VAL_STR END) OVER (
            PARTITION BY t.VENDOR_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS vendor_active_flag,
        MAX(CASE WHEN d.TYPE_KEY = 70 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.VENDOR_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS vendor_credit_rating,
        MAX(CASE WHEN d.TYPE_KEY = 46 THEN d.VAL_STR END) OVER (
            PARTITION BY t.VENDOR_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS vendor_name,
        MAX(CASE WHEN d.TYPE_KEY = 84 THEN d.VAL_STR END) OVER (
            PARTITION BY t.VENDOR_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS vendor_preferred_status,
        MAX(r_person.PERSON_KEY) OVER (
            PARTITION BY t.VENDOR_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PERSON_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.VENDOR_KEY = d.VENDOR_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_person r_person ON t.VENDOR_KEY = r_person.VENDOR_KEY AND t.EFF_TMSTP = r_person.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.VENDOR_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.VENDOR_KEY,
        p.vendor_account_number,
        p.vendor_active_flag,
        p.vendor_credit_rating,
        p.vendor_name,
        p.vendor_preferred_status,
        p.PERSON_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.VENDOR_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.VENDOR_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS VENDOR_KEY,
    NULL AS vendor_account_number,
    NULL AS vendor_active_flag,
    NULL::numeric AS vendor_credit_rating,
    NULL AS vendor_name,
    NULL AS vendor_preferred_status,
    NULL AS PERSON_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
