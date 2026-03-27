CREATE OR REPLACE VIEW uss.customer AS
WITH ranked AS (
    SELECT
        CUSTOMER_KEY,
        TYPE_KEY,
        EFF_TMSTP,
        VAL_STR,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, TYPE_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_DESC
),
deduped AS (
    SELECT * FROM ranked WHERE rnk = 1
),
-- Resolve relationships: CUSTOMER -> PERSON (TYPE_KEY=65)
ranked_customer_person_x AS (
    SELECT
        CUSTOMER_KEY,
        EFF_TMSTP,
        PERSON_KEY,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_PERSON_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 65
),
rel_person AS (
    SELECT CUSTOMER_KEY, EFF_TMSTP, PERSON_KEY
    FROM ranked_customer_person_x
    WHERE rnk = 1
),
-- Resolve relationships: CUSTOMER -> SALES_TERRITORY (TYPE_KEY=33)
ranked_customer_sales_territory_x AS (
    SELECT
        CUSTOMER_KEY,
        EFF_TMSTP,
        SALES_TERRITORY_KEY,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_SALES_TERRITORY_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 33
),
rel_sales_territory AS (
    SELECT CUSTOMER_KEY, EFF_TMSTP, SALES_TERRITORY_KEY
    FROM ranked_customer_sales_territory_x
    WHERE rnk = 1
),
-- Resolve relationships: CUSTOMER -> STORE (TYPE_KEY=63)
ranked_customer_store_x AS (
    SELECT
        CUSTOMER_KEY,
        EFF_TMSTP,
        STORE_KEY,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_STORE_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 63
),
rel_store AS (
    SELECT CUSTOMER_KEY, EFF_TMSTP, STORE_KEY
    FROM ranked_customer_store_x
    WHERE rnk = 1
),
timeline AS (
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP
    FROM rel_person
    UNION
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP
    FROM rel_sales_territory
    UNION
    SELECT DISTINCT CUSTOMER_KEY, EFF_TMSTP
    FROM rel_store
),
pivoted AS (
    SELECT
        t.CUSTOMER_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 89 THEN d.VAL_STR END) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS customer_account_number,
        MAX(r_person.PERSON_KEY) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PERSON_KEY,
        MAX(r_sales_territory.SALES_TERRITORY_KEY) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SALES_TERRITORY_KEY,
        MAX(r_store.STORE_KEY) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS STORE_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.CUSTOMER_KEY = d.CUSTOMER_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_person r_person ON t.CUSTOMER_KEY = r_person.CUSTOMER_KEY AND t.EFF_TMSTP = r_person.EFF_TMSTP
    LEFT JOIN rel_sales_territory r_sales_territory ON t.CUSTOMER_KEY = r_sales_territory.CUSTOMER_KEY AND t.EFF_TMSTP = r_sales_territory.EFF_TMSTP
    LEFT JOIN rel_store r_store ON t.CUSTOMER_KEY = r_store.CUSTOMER_KEY AND t.EFF_TMSTP = r_store.EFF_TMSTP
),
pivoted_deduped AS (
    SELECT DISTINCT * FROM pivoted
),
peripheral_final AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.CUSTOMER_KEY, p.EFF_TMSTP) AS _peripheral_key,
        p.CUSTOMER_KEY,
        p.customer_account_number,
        p.PERSON_KEY,
        p.SALES_TERRITORY_KEY,
        p.STORE_KEY,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY p.CUSTOMER_KEY ORDER BY p.EFF_TMSTP) = 1
            THEN '1900-01-01'::timestamp
            ELSE p.EFF_TMSTP
        END AS effective_from,
        COALESCE(
            LEAD(p.EFF_TMSTP) OVER (PARTITION BY p.CUSTOMER_KEY ORDER BY p.EFF_TMSTP),
            '9999-12-31'::timestamp
        ) AS effective_to
    FROM pivoted_deduped p
)
SELECT * FROM peripheral_final

UNION ALL

SELECT
    -1 AS _peripheral_key,
    'UNKNOWN' AS CUSTOMER_KEY,
    NULL AS customer_account_number,
    NULL AS PERSON_KEY,
    NULL AS SALES_TERRITORY_KEY,
    NULL AS STORE_KEY,
    '1900-01-01'::timestamp AS effective_from,
    '9999-12-31'::timestamp AS effective_to;
