# USS Peripheral Relationship Type 2 Dedup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix relationship CTEs in USS peripheral views to use Type 2 dedup with carry-forward instead of snapshot dedup, so relationship FKs reflect historical state at each effective timestamp.

**Architecture:** Each peripheral's relationship CTEs change from snapshot dedup (latest-only) to Type 2 dedup (one row per EFF_TMSTP). Relationship EFF_TMSTPs merge into the timeline spine. Relationship FKs get carry-forward windows in the pivoted CTE, eliminating separate LEFT JOINs in peripheral_final.

**Tech Stack:** PostgreSQL SQL, USS skill reference patterns

**Design spec:** `docs/superpowers/specs/2026-03-27-uss-peripheral-relationship-type2-design.md`

---

## Notes

- `store.sql` is listed in the issue but has NO relationship CTEs — it is NOT affected.
- There are no automated tests; verification is visual inspection of SQL correctness.
- All SQL file tasks are independent and can run in parallel.

## Transformation Pattern

Every affected file applies the same 4-step transformation:

### A. Relationship CTE: Snapshot -> Type 2 Dedup

**Before:**
```sql
ranked_{rel_table} AS (
    SELECT
        {SOURCE}_KEY,
        {TARGET}_KEY,
        RANK() OVER (
            PARTITION BY {SOURCE}_KEY
            ORDER BY EFF_TMSTP DESC, VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.{REL_TABLE}
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = {N}
),
rel_{alias} AS (
    SELECT {SOURCE}_KEY, {TARGET}_KEY
    FROM ranked_{rel_table}
    WHERE rnk = 1
)
```

**After:**
```sql
ranked_{rel_table} AS (
    SELECT
        {SOURCE}_KEY,
        {TARGET}_KEY,
        EFF_TMSTP,
        RANK() OVER (
            PARTITION BY {SOURCE}_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.{REL_TABLE}
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = {N}
),
rel_{alias} AS (
    SELECT {SOURCE}_KEY, {TARGET}_KEY, EFF_TMSTP
    FROM ranked_{rel_table}
    WHERE rnk = 1
)
```

Changes: (1) add `EFF_TMSTP` to SELECT, (2) add `EFF_TMSTP` to PARTITION BY, (3) remove `EFF_TMSTP DESC` from ORDER BY, (4) add `EFF_TMSTP` to rel output.

### B. Timeline CTE: Add UNION for Each Relationship

**Before:**
```sql
timeline AS (
    SELECT DISTINCT {ENTITY}_KEY, EFF_TMSTP
    FROM deduped
)
```

**After:**
```sql
timeline AS (
    SELECT DISTINCT {ENTITY}_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT {SOURCE}_KEY, EFF_TMSTP
    FROM rel_{alias_1}
    UNION
    SELECT DISTINCT {SOURCE}_KEY, EFF_TMSTP
    FROM rel_{alias_2}
    -- ... one UNION per relationship
)
```

### C. Pivoted CTE: Add Relationship FK Carry-Forward + LEFT JOINs

Add to the SELECT list (after descriptor columns):
```sql
MAX(r_{alias}.{TARGET}_KEY) OVER (
    PARTITION BY t.{ENTITY}_KEY
    ORDER BY t.EFF_TMSTP
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS {TARGET}_KEY
```

Add to the FROM clause (after the deduped LEFT JOIN):
```sql
LEFT JOIN rel_{alias} r_{alias}
    ON t.{SOURCE}_KEY = r_{alias}.{SOURCE}_KEY AND t.EFF_TMSTP = r_{alias}.EFF_TMSTP
```

### D. peripheral_final: Remove Separate Relationship JOINs

- Remove all `LEFT JOIN rel_* ...` from peripheral_final
- Change `r{alias}.{TARGET}_KEY` references to `p.{TARGET}_KEY` (now from pivoted_deduped)
- For aliased columns (e.g., `rba.ADDRESS_KEY AS BILL_TO_ADDRESS_KEY`), the alias moves into the pivoted CTE

---

## Task 1: Fix customer.sql

**Can run in parallel with:** Tasks 2-8

**File:** `uss/customer.sql`
**Relationships:** 3 (person TYPE_KEY=65, sales_territory TYPE_KEY=33, store TYPE_KEY=63)

**Step 1: Update relationship CTEs**

Apply pattern A to all 3 relationship CTEs:

```sql
-- Resolve relationships: CUSTOMER -> PERSON (TYPE_KEY=65)
ranked_customer_person_x AS (
    SELECT
        CUSTOMER_KEY,
        PERSON_KEY,
        EFF_TMSTP,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_PERSON_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 65
),
rel_person AS (
    SELECT CUSTOMER_KEY, PERSON_KEY, EFF_TMSTP
    FROM ranked_customer_person_x
    WHERE rnk = 1
),
-- Resolve relationships: CUSTOMER -> SALES_TERRITORY (TYPE_KEY=33)
ranked_customer_sales_territory_x AS (
    SELECT
        CUSTOMER_KEY,
        SALES_TERRITORY_KEY,
        EFF_TMSTP,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_SALES_TERRITORY_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 33
),
rel_sales_territory AS (
    SELECT CUSTOMER_KEY, SALES_TERRITORY_KEY, EFF_TMSTP
    FROM ranked_customer_sales_territory_x
    WHERE rnk = 1
),
-- Resolve relationships: CUSTOMER -> STORE (TYPE_KEY=63)
ranked_customer_store_x AS (
    SELECT
        CUSTOMER_KEY,
        STORE_KEY,
        EFF_TMSTP,
        RANK() OVER (
            PARTITION BY CUSTOMER_KEY, EFF_TMSTP
            ORDER BY VER_TMSTP DESC
        ) AS rnk
    FROM daana_dw.CUSTOMER_STORE_X
    WHERE ROW_ST = 'Y'
      AND TYPE_KEY = 63
),
rel_store AS (
    SELECT CUSTOMER_KEY, STORE_KEY, EFF_TMSTP
    FROM ranked_customer_store_x
    WHERE rnk = 1
),
```

**Step 2: Move relationship CTEs before timeline**

The relationship CTEs must be defined BEFORE the timeline CTE (since timeline references them). Move them to after `deduped`.

**Step 3: Update timeline CTE**

```sql
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
```

**Step 4: Update pivoted CTE**

```sql
pivoted AS (
    SELECT
        t.CUSTOMER_KEY,
        t.EFF_TMSTP,
        MAX(CASE WHEN d.TYPE_KEY = 89 THEN d.VAL_STR END) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS customer_account_number,
        MAX(rp.PERSON_KEY) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PERSON_KEY,
        MAX(rst.SALES_TERRITORY_KEY) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SALES_TERRITORY_KEY,
        MAX(rs.STORE_KEY) OVER (
            PARTITION BY t.CUSTOMER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS STORE_KEY
    FROM timeline t
    LEFT JOIN deduped d ON t.CUSTOMER_KEY = d.CUSTOMER_KEY AND t.EFF_TMSTP = d.EFF_TMSTP
    LEFT JOIN rel_person rp ON t.CUSTOMER_KEY = rp.CUSTOMER_KEY AND t.EFF_TMSTP = rp.EFF_TMSTP
    LEFT JOIN rel_sales_territory rst ON t.CUSTOMER_KEY = rst.CUSTOMER_KEY AND t.EFF_TMSTP = rst.EFF_TMSTP
    LEFT JOIN rel_store rs ON t.CUSTOMER_KEY = rs.CUSTOMER_KEY AND t.EFF_TMSTP = rs.EFF_TMSTP
),
```

**Step 5: Update peripheral_final**

Remove `LEFT JOIN rel_*` lines. Reference FK columns from `p.` instead of `rp.`/`rst.`/`rs.`:

```sql
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
```

**Step 6: Commit**

```bash
git add uss/customer.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in customer peripheral"
```

---

## Task 2: Fix employee.sql

**Can run in parallel with:** Tasks 1, 3-8

**File:** `uss/employee.sql`
**Relationships:** 1 (person TYPE_KEY=83)

Apply the same transformation pattern (A-D) with these specifics:

**Step 1: Update ranked_employee_person_x** — add `EFF_TMSTP` to SELECT/PARTITION BY, remove from ORDER BY. Update `rel_person` to include `EFF_TMSTP`.

**Step 2: Move relationship CTEs before timeline.**

**Step 3: Update timeline:**
```sql
timeline AS (
    SELECT DISTINCT EMPLOYEE_KEY, EFF_TMSTP
    FROM deduped
    UNION
    SELECT DISTINCT EMPLOYEE_KEY, EFF_TMSTP
    FROM rel_person
),
```

**Step 4: Add to pivoted CTE** (after last descriptor column):
```sql
        MAX(rp.PERSON_KEY) OVER (
            PARTITION BY t.EMPLOYEE_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS PERSON_KEY
```
Add LEFT JOIN: `LEFT JOIN rel_person rp ON t.EMPLOYEE_KEY = rp.EMPLOYEE_KEY AND t.EFF_TMSTP = rp.EFF_TMSTP`

**Step 5: Update peripheral_final** — remove `LEFT JOIN rel_person rp`, change `rp.PERSON_KEY` to `p.PERSON_KEY`.

**Step 6: Commit**
```bash
git add uss/employee.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in employee peripheral"
```

---

## Task 3: Fix sales_person.sql

**Can run in parallel with:** Tasks 1-2, 4-8

**File:** `uss/sales_person.sql`
**Relationships:** 2 (employee TYPE_KEY=62, sales_territory TYPE_KEY=66)

Apply transformation pattern (A-D):

**Step 1:** Update both ranked CTEs + rel CTEs with EFF_TMSTP.

**Step 2:** Move relationship CTEs before timeline.

**Step 3:** Timeline unions rel_employee + rel_sales_territory.

**Step 4:** Add carry-forward for EMPLOYEE_KEY and SALES_TERRITORY_KEY in pivoted. Add 2 LEFT JOINs.

**Step 5:** Remove `LEFT JOIN rel_employee re` and `LEFT JOIN rel_sales_territory rst` from peripheral_final. Change `re.EMPLOYEE_KEY` to `p.EMPLOYEE_KEY`, `rst.SALES_TERRITORY_KEY` to `p.SALES_TERRITORY_KEY`.

**Step 6: Commit**
```bash
git add uss/sales_person.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in sales_person peripheral"
```

---

## Task 4: Fix vendor.sql

**Can run in parallel with:** Tasks 1-3, 5-8

**File:** `uss/vendor.sql`
**Relationships:** 1 (person TYPE_KEY=91)

Apply transformation pattern (A-D):

**Step 1:** Update ranked_vendor_person_x + rel_person with EFF_TMSTP.

**Step 2:** Move relationship CTEs before timeline.

**Step 3:** Timeline unions rel_person.

**Step 4:** Add carry-forward for PERSON_KEY in pivoted. Add LEFT JOIN.

**Step 5:** Remove `LEFT JOIN rel_person rp` from peripheral_final. Change `rp.PERSON_KEY` to `p.PERSON_KEY`.

**Step 6: Commit**
```bash
git add uss/vendor.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in vendor peripheral"
```

---

## Task 5: Fix sales_order.sql

**Can run in parallel with:** Tasks 1-4, 6-8

**File:** `uss/sales_order.sql`
**Relationships:** 5 (customer TYPE_KEY=7, bill_address TYPE_KEY=189, ship_address TYPE_KEY=190, sales_person TYPE_KEY=117, sales_territory TYPE_KEY=21)

**Special:** Two ADDRESS relationships with aliases (BILL_TO_ADDRESS_KEY, SHIP_TO_ADDRESS_KEY).

Apply transformation pattern (A-D):

**Step 1:** Update all 5 ranked CTEs + rel CTEs with EFF_TMSTP.

**Step 2:** Move all relationship CTEs before timeline.

**Step 3:** Timeline unions all 5 rel CTEs.

**Step 4:** Add carry-forward for all 5 FK columns in pivoted. For the address relationships, use aliases in the carry-forward:
```sql
        MAX(rba.ADDRESS_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS BILL_TO_ADDRESS_KEY,
        MAX(rsa.ADDRESS_KEY) OVER (
            PARTITION BY t.SALES_ORDER_KEY
            ORDER BY t.EFF_TMSTP
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS SHIP_TO_ADDRESS_KEY,
```

Add 5 LEFT JOINs to pivoted.

**Step 5:** Remove all 5 `LEFT JOIN rel_*` from peripheral_final. Change all alias references to `p.`:
- `rc.CUSTOMER_KEY` -> `p.CUSTOMER_KEY`
- `rba.ADDRESS_KEY AS BILL_TO_ADDRESS_KEY` -> `p.BILL_TO_ADDRESS_KEY`
- `rsa.ADDRESS_KEY AS SHIP_TO_ADDRESS_KEY` -> `p.SHIP_TO_ADDRESS_KEY`
- `rsp.SALES_PERSON_KEY` -> `p.SALES_PERSON_KEY`
- `rst.SALES_TERRITORY_KEY` -> `p.SALES_TERRITORY_KEY`

**Step 6: Commit**
```bash
git add uss/sales_order.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in sales_order peripheral"
```

---

## Task 6: Fix sales_order_detail.sql

**Can run in parallel with:** Tasks 1-5, 7-8

**File:** `uss/sales_order_detail.sql`
**Relationships:** 3 (sales_order TYPE_KEY=48, product TYPE_KEY=20, special_offer TYPE_KEY=3)

Apply transformation pattern (A-D):

**Step 1:** Update all 3 ranked CTEs + rel CTEs with EFF_TMSTP.

**Step 2:** Move relationship CTEs before timeline.

**Step 3:** Timeline unions all 3 rel CTEs.

**Step 4:** Add carry-forward for SALES_ORDER_KEY, PRODUCT_KEY, SPECIAL_OFFER_KEY. Add 3 LEFT JOINs.

**Step 5:** Remove `LEFT JOIN rel_*` from peripheral_final. Change:
- `rso.SALES_ORDER_KEY` -> `p.SALES_ORDER_KEY`
- `rpd.PRODUCT_KEY` -> `p.PRODUCT_KEY`
- `rspo.SPECIAL_OFFER_KEY` -> `p.SPECIAL_OFFER_KEY`

**Step 6: Commit**
```bash
git add uss/sales_order_detail.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in sales_order_detail peripheral"
```

---

## Task 7: Fix purchase_order.sql

**Can run in parallel with:** Tasks 1-6, 8

**File:** `uss/purchase_order.sql`
**Relationships:** 2 (employee TYPE_KEY=30, vendor TYPE_KEY=12)

Apply transformation pattern (A-D):

**Step 1:** Update both ranked CTEs + rel CTEs with EFF_TMSTP.

**Step 2:** Move relationship CTEs before timeline.

**Step 3:** Timeline unions rel_employee + rel_vendor.

**Step 4:** Add carry-forward for EMPLOYEE_KEY and VENDOR_KEY. Add 2 LEFT JOINs.

**Step 5:** Remove `LEFT JOIN rel_*` from peripheral_final. Change:
- `re.EMPLOYEE_KEY` -> `p.EMPLOYEE_KEY`
- `rv.VENDOR_KEY` -> `p.VENDOR_KEY`

**Step 6: Commit**
```bash
git add uss/purchase_order.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in purchase_order peripheral"
```

---

## Task 8: Fix work_order.sql

**Can run in parallel with:** Tasks 1-7

**File:** `uss/work_order.sql`
**Relationships:** 1 (product TYPE_KEY=74)

Apply transformation pattern (A-D):

**Step 1:** Update ranked_wo_product_x + rel_product with EFF_TMSTP.

**Step 2:** Move relationship CTEs before timeline.

**Step 3:** Timeline unions rel_product.

**Step 4:** Add carry-forward for PRODUCT_KEY. Add LEFT JOIN.

**Step 5:** Remove `LEFT JOIN rel_product rpd` from peripheral_final. Change `rpd.PRODUCT_KEY` to `p.PRODUCT_KEY`.

**Step 6: Commit**
```bash
git add uss/work_order.sql
git commit -m "fix: use Type 2 dedup for relationship CTEs in work_order peripheral"
```

---

## Task 9: Update uss-patterns.md

**Can run in parallel with:** Tasks 1-8

**File:** `skills/uss/references/uss-patterns.md`

The current patterns doc only documents the snapshot relationship pattern (used in the bridge). Since peripherals now use a different pattern, we need to document the peripheral-specific Type 2 relationship pattern.

**Step 1:** After the existing "Step 2: Resolve Relationships" section (which is bridge-specific), add a note clarifying this is the bridge pattern. Then add a new subsection for the peripheral relationship pattern:

Add after the existing relationship pattern section (~line 355), a new section:

```markdown
### Peripheral Relationship Resolution

> **Important:** The snapshot relationship pattern above applies to the **bridge** only. Peripherals use Type 2 dedup for relationships, matching how they handle descriptors.

In peripherals, relationships must preserve history. The pattern:

1. **Dedup per EFF_TMSTP** (not snapshot):

    ```sql
    ranked_{rel_table} AS (
        SELECT
            {source_attr_name},
            {target_attr_name},
            EFF_TMSTP,
            RANK() OVER (
                PARTITION BY {source_attr_name}, EFF_TMSTP
                ORDER BY VER_TMSTP DESC
            ) AS rnk
        FROM {source_schema}.{relationship_table}
        WHERE ROW_ST = 'Y'
          AND TYPE_KEY = {rel_type_key}
    ),
    {rel_alias} AS (
        SELECT
            {source_attr_name},
            {target_attr_name},
            EFF_TMSTP
        FROM ranked_{rel_table}
        WHERE rnk = 1
    )
    ```

2. **Merge into timeline spine** — UNION relationship EFF_TMSTPs with descriptor EFF_TMSTPs:

    ```sql
    timeline AS (
        SELECT DISTINCT {entity}_KEY, EFF_TMSTP
        FROM deduped
        UNION
        SELECT DISTINCT {source_attr_name}, EFF_TMSTP
        FROM {rel_alias_1}
        UNION
        SELECT DISTINCT {source_attr_name}, EFF_TMSTP
        FROM {rel_alias_2}
    )
    ```

3. **Carry-forward** — join relationships to timeline and apply window:

    ```sql
    MAX(r.{target_attr_name}) OVER (
        PARTITION BY t.{entity}_KEY
        ORDER BY t.EFF_TMSTP
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS {target_attr_name}
    ```

    With LEFT JOIN:
    ```sql
    LEFT JOIN {rel_alias} r
        ON t.{source_attr_name} = r.{source_attr_name}
        AND t.EFF_TMSTP = r.EFF_TMSTP
    ```

This ensures relationship FKs reflect the relationship as-of each effective timestamp, not just the latest.
```

**Step 2: Commit**
```bash
git add skills/uss/references/uss-patterns.md
git commit -m "docs: document Type 2 peripheral relationship pattern in uss-patterns"
```

---

## Task 10: Version bump + final commit

**Depends on:** Tasks 1-9

**File:** `.claude-plugin/plugin.json`

**Step 1:** Read current version, bump patch.

**Step 2: Commit**
```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to {new_version}"
```

**Step 3: Push**
```bash
git push -u origin fix/uss-peripheral-relationship-dedup
```
