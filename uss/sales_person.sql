CREATE OR REPLACE VIEW uss.sales_person AS
WITH ranked AS (
    SELECT
        SALES_PERSON_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_NUM,
        RANK() OVER (
            PARTITION BY SALES_PERSON_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_PERSON_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: SALES_PERSON -> EMPLOYEE (TYPE_KEY=62)
ranked_sales_person_employee_x AS (
    SELECT
        SALES_PERSON_KEY,
        EFF_TMSTP,
        EMPLOYEE_KEY,
        RANK() OVER (
            PARTITION BY SALES_PERSON_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_PERSON_EMPLOYEE_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 62
),
rel_employee AS (
    SELECT SALES_PERSON_KEY, EFF_TMSTP, EMPLOYEE_KEY
    FROM ranked_sales_person_employee_x
    WHERE rnk = 1
),
-- Resolve relationships: SALES_PERSON -> SALES_TERRITORY (TYPE_KEY=66)
ranked_sales_person_sales_territory_x AS (
    SELECT
        SALES_PERSON_KEY,
        EFF_TMSTP,
        SALES_TERRITORY_KEY,
        RANK() OVER (
            PARTITION BY SALES_PERSON_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.SALES_PERSON_SALES_TERRITORY_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 66
),
rel_sales_territory AS (
    SELECT SALES_PERSON_KEY, EFF_TMSTP, SALES_TERRITORY_KEY
    FROM ranked_sales_person_sales_territory_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT SALES_PERSON_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT SALES_PERSON_KEY, EFF_TMSTP
    FROM rel_employee
    UNION
    SELECT DISTINCT SALES_PERSON_KEY, EFF_TMSTP
    FROM rel_sales_territory
),
pivoted AS (
    SELECT
        t.SALES_PERSON_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 54 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_person_bonus,
        MAX(CASE WHEN d.TYPE_KEY = 105 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_person_commission_pct,
        MAX(CASE WHEN d.TYPE_KEY = 16 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_person_sales_last_year,
        MAX(CASE WHEN d.TYPE_KEY = 5 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_person_sales_quota,
        MAX(CASE WHEN d.TYPE_KEY = 88 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sales_person_sales_ytd,
        MAX(r_employee.EMPLOYEE_KEY) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS EMPLOYEE_KEY,
        MAX(r_sales_territory.SALES_TERRITORY_KEY) OVER (
            PARTITION BY t.SALES_PERSON_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SALES_TERRITORY_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.SALES_PERSON_KEY = d.SALES_PERSON_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_employee r_employee ON t.SALES_PERSON_KEY = r_employee.SALES_PERSON_KEY AND t.EFF_TMSTP = r_employee.EFF_TMSTP
    LEFT JOIN rel_sales_territory r_sales_territory ON t.SALES_PERSON_KEY = r_sales_territory.SALES_PERSON_KEY AND t.EFF_TMSTP = r_sales_territory.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.SALES_PERSON_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.SALES_PERSON_KEY,
        p.sales_person_bonus,
        p.sales_person_commission_pct,
        p.sales_person_sales_last_year,
        p.sales_person_sales_quota,
        p.sales_person_sales_ytd,
        p.EMPLOYEE_KEY,
        p.SALES_TERRITORY_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.SALES_PERSON_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.SALES_PERSON_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS SALES_PERSON_KEY,
    NULL::numeric AS sales_person_bonus,
    NULL::numeric AS sales_person_commission_pct,
    NULL::numeric AS sales_person_sales_last_year,
    NULL::numeric AS sales_person_sales_quota,
    NULL::numeric AS sales_person_sales_ytd,
    NULL AS EMPLOYEE_KEY,
    NULL AS SALES_TERRITORY_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
