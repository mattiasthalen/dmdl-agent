CREATE OR REPLACE VIEW uss.employee AS
WITH ranked AS (
    SELECT
        EMPLOYEE_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_STR,
        VAL_NUM,
        STA_TMSTP,
        RANK() OVER (
            PARTITION BY EMPLOYEE_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.EMPLOYEE_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: EMPLOYEE -> PERSON (TYPE_KEY=83)
ranked_employee_person_x AS (
    SELECT
        EMPLOYEE_KEY,
        EFF_TMSTP,
        PERSON_KEY,
        RANK() OVER (
            PARTITION BY EMPLOYEE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.EMPLOYEE_PERSON_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 83
),
rel_person AS (
    SELECT EMPLOYEE_KEY, EFF_TMSTP, PERSON_KEY
    FROM ranked_employee_person_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT EMPLOYEE_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT EMPLOYEE_KEY, EFF_TMSTP
    FROM rel_person
),
pivoted AS (
    SELECT
        t.EMPLOYEE_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 37 THEN d.STA_TMSTP END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_birth_date,
        MAX(CASE WHEN d.TYPE_KEY = 27 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_current_flag,
        MAX(CASE WHEN d.TYPE_KEY = 24 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_gender,
        MAX(CASE WHEN d.TYPE_KEY = 23 THEN d.STA_TMSTP END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_hire_date,
        MAX(CASE WHEN d.TYPE_KEY = 9 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_job_title,
        MAX(CASE WHEN d.TYPE_KEY = 2 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_login_id,
        MAX(CASE WHEN d.TYPE_KEY = 93 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_marital_status,
        MAX(CASE WHEN d.TYPE_KEY = 106 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_national_id_number,
        MAX(CASE WHEN d.TYPE_KEY = 85 THEN d.VAL_STR END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_salaried_flag,
        MAX(CASE WHEN d.TYPE_KEY = 49 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_sick_leave_hours,
        MAX(CASE WHEN d.TYPE_KEY = 13 THEN d.VAL_NUM END) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employee_vacation_hours,
        MAX(r_person.PERSON_KEY) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PERSON_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.EMPLOYEE_KEY = d.EMPLOYEE_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_person r_person ON t.EMPLOYEE_KEY = r_person.EMPLOYEE_KEY AND t.EFF_TMSTP = r_person.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.EMPLOYEE_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.EMPLOYEE_KEY,
        p.employee_birth_date,
        p.employee_current_flag,
        p.employee_gender,
        p.employee_hire_date,
        p.employee_job_title,
        p.employee_login_id,
        p.employee_marital_status,
        p.employee_national_id_number,
        p.employee_salaried_flag,
        p.employee_sick_leave_hours,
        p.employee_vacation_hours,
        p.PERSON_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.EMPLOYEE_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.EMPLOYEE_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS EMPLOYEE_KEY,
    NULL::timestamp AS employee_birth_date,
    NULL AS employee_current_flag,
    NULL AS employee_gender,
    NULL::timestamp AS employee_hire_date,
    NULL AS employee_job_title,
    NULL AS employee_login_id,
    NULL AS employee_marital_status,
    NULL AS employee_national_id_number,
    NULL AS employee_salaried_flag,
    NULL::numeric AS employee_sick_leave_hours,
    NULL::numeric AS employee_vacation_hours,
    NULL AS PERSON_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
