# Bootstrap: Discover the Metadata Model

**Run this before every query, dimension, or fact generation — even within the same session.** TYPE_KEYs and metadata can change between installations and deployments. Never reuse cached bootstrap results across tasks.

## Why Bootstrap First

Before an agent can build any query or generate any table, it needs to understand what entities, descriptor tables, atomic contexts, and attributes exist. **Keys differ between installations** — they must never be hardcoded.

The bootstrap query returns the **entire metadata model including physical column mappings** in a single result set. Every other agent file depends on this.

## Bootstrap Query: `f_focal_read` + Physical Column Mapping

```sql
SELECT
  fr.FOCAL_NAME,
  fr.FOCAL_PHYSICAL_SCHEMA,
  fr.DESCRIPTOR_CONCEPT_NAME,
  fr.ATOMIC_CONTEXT_NAME,
  fr.ATOM_CONTX_KEY,
  fr.ATTRIBUTE_NAME,
  fr.ATR_KEY,
  tcn.VAL_STR as PHYSICAL_COLUMN
FROM DAANA_METADATA.f_focal_read('9999-12-31') fr
LEFT JOIN DAANA_METADATA.LOGICAL_PHYSICAL_X lp
  ON lp.ATR_KEY = fr.ATR_KEY AND lp.ATOM_CONTX_KEY = fr.ATOM_CONTX_KEY AND lp.ROW_ST = 'Y'
LEFT JOIN DAANA_METADATA.TBL_PTRN_COL_NM tcn
  ON lp.TBL_PTRN_COL_KEY = tcn.TBL_PTRN_COL_KEY AND tcn.ROW_ST = 'Y'
WHERE fr.FOCAL_PHYSICAL_SCHEMA = 'DAANA_DW'
ORDER BY fr.FOCAL_NAME, fr.DESCRIPTOR_CONCEPT_NAME, fr.ATOMIC_CONTEXT_NAME
```

Change the `WHERE` filter to see different layers:
- `FOCAL_PHYSICAL_SCHEMA = 'DAANA_DW'` — data layer entities (the business data)
- `FOCAL_PHYSICAL_SCHEMA = 'DAANA_METADATA'` — metadata layer entities (the framework's own structure)

## What the Bootstrap Reveals

Each row in the result maps the full chain from entity to physical column:

| Column | What it tells you |
|--------|-------------------|
| `FOCAL_NAME` | The entity (e.g. `CUSTOMER_FOCAL`, `RIDE_FOCAL`) |
| `FOCAL_PHYSICAL_SCHEMA` | Which dataset the entity's tables live in |
| `DESCRIPTOR_CONCEPT_NAME` | The physical table name (e.g. `CUSTOMER_DESC`, `RIDE_STATION_X`) |
| `ATOMIC_CONTEXT_NAME` | The TYPE_KEY meaning (e.g. `CUSTOMER_CUSTOMER_EMAIL_ADDRESS`) |
| `ATOM_CONTX_KEY` | The actual TYPE_KEY value to use in queries |
| `ATTRIBUTE_NAME` | The logical attribute name within the atomic context |
| `PHYSICAL_COLUMN` | The generic column where the value is stored (e.g. `VAL_STR`, `VAL_NUM`, `STA_TMSTP`, `FOCAL01_KEY`) |

## Example Bootstrap Result

```
FOCAL_NAME      | DESC_CONCEPT_NAME | ATOMIC_CONTEXT_NAME              | ATOM_CONTX_KEY | ATTRIBUTE_NAME     | PHYSICAL_COLUMN
CUSTOMER_FOCAL  | CUSTOMER_DESC     | CUSTOMER_CUSTOMER_EMAIL_ADDRESS  | 22             | CUSTOMER_EMAIL     | VAL_STR
RIDE_FOCAL      | RIDE_DESC         | RIDE_RIDE_DURATION_...           | 18             | RIDE_DURATION      | VAL_NUM
RIDE_FOCAL      | RIDE_DESC         | RIDE_RIDE_DURATION_...           | 18             | RIDE_START_TMSTP   | STA_TMSTP
RIDE_FOCAL      | RIDE_DESC         | RIDE_RIDE_DURATION_...           | 18             | RIDE_END_TMSTP     | END_TMSTP
RIDE_FOCAL      | RIDE_DESC         | RIDE_RIDE_DURATION_...           | 18             | RIDE_DURATION_UNIT | UOM
RIDE_FOCAL      | RIDE_STATION_X    | RIDE_START_STATION               | 16             | RIDE_KEY           | FOCAL01_KEY
RIDE_FOCAL      | RIDE_STATION_X    | RIDE_START_STATION               | 16             | STATION_KEY        | FOCAL02_KEY
```

From this, the agent can immediately see:
- A simple attribute like `CUSTOMER_EMAIL_ADDRESS` uses one column (`VAL_STR`)
- A complex atomic context like ride duration uses four columns (`VAL_NUM`, `UOM`, `STA_TMSTP`, `END_TMSTP`)
- Which TYPE_KEY to use for each attribute when building queries

## Relationship Table Columns: Pattern vs Physical Names

For **descriptor tables** (e.g. `CUSTOMER_DESC`), the `PHYSICAL_COLUMN` from the bootstrap (e.g. `VAL_STR`, `VAL_NUM`) is the actual column name in the physical table.

For **relationship tables** (e.g. `RIDE_STATION_X`), the `PHYSICAL_COLUMN` returns generic pattern names like `FOCAL01_KEY` and `FOCAL02_KEY`. These are **not** the actual column names in the physical table. Instead:

- `FOCAL01_KEY` = the first entity key column
- `FOCAL02_KEY` = the second entity key column

The **actual physical column names** are the `ATTRIBUTE_NAME` values from the bootstrap. For example:

| PHYSICAL_COLUMN (pattern) | ATTRIBUTE_NAME (actual column) |
|---------------------------|-------------------------------|
| `FOCAL01_KEY` | `RIDE_KEY` |
| `FOCAL02_KEY` | `STATION_KEY` |

So when building a relationship query, use the `ATTRIBUTE_NAME` as the column name, not the `PHYSICAL_COLUMN`:

```sql
-- CORRECT: use ATTRIBUTE_NAME as the column name
SELECT RIDE_KEY, STATION_KEY FROM DAANA_DW.RIDE_STATION_X WHERE TYPE_KEY = 16

-- WRONG: FOCAL01_KEY and FOCAL02_KEY don't exist in the physical table
SELECT FOCAL01_KEY, FOCAL02_KEY FROM DAANA_DW.RIDE_STATION_X WHERE TYPE_KEY = 16
```

The agent can detect relationship tables by checking if `PHYSICAL_COLUMN` is `FOCAL01_KEY` or `FOCAL02_KEY`. When it sees these values, it should use `ATTRIBUTE_NAME` as the column name instead.

## Fallback: Direct Metadata Queries

If `f_focal_read` is not available, the agent can bootstrap using `ATOM_CONTX_NM` as the entry point. This table can always be searched by `VAL_STR` without needing to know a TYPE_KEY first:

```sql
SELECT ATOM_CONTX_KEY, VAL_STR
FROM DAANA_METADATA.ATOM_CONTX_NM
WHERE VAL_STR IN (
  'FOCAL_NAME',                -- TYPE_KEY used in FOCAL_NM
  'FOCAL_PHYSICAL_SCHEMA',     -- TYPE_KEY used in FOCAL_CL for schema/dataset
  'ATOMIC_CONTEXT_NAME',       -- TYPE_KEY used in ATOM_CONTX_NM
  'ATTRIBUTE_NAME',            -- TYPE_KEY used in ATR_NM
  'DESCRIPTOR_CONCEPT_NAME',   -- TYPE_KEY used in DESC_CNCPT_NM
  'TABLE_PATTERN_COLUMN_NAME'  -- TYPE_KEY used in TBL_PTRN_COL_NM
)
AND ROW_ST = 'Y'
```

The agent should cache these resolved keys for the duration of the current task only, and re-run the bootstrap for each new task.
