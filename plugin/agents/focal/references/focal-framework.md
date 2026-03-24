# The Focal Framework

A metadata-driven architecture engineered for agility and stability. It is a **self-describing system** where the physical data layer mirrors metadata definitions.

## Two-Layer Architecture

- **Data Layer** — Stores business information in generic, flexible structures. Intentionally simple.
- **Metadata Layer** — The operational core governing data structure, loading logic, and semantic interpretation. Describes itself, enabling complete lineage tracing.

## Metadata Model — Three Subject Areas

| Area | Purpose |
|------|---------|
| **Technical** | Manages data movement operations and batch control |
| **Functional** | Supports implementation-specific logic and code traceability |
| **Semantic** | Represents all data models and relationships (the "heart and soul") |

The semantic model uses **Focal constructs**: Model, Entity, Attribute, Domain, Domain Value — representing data models as rows of data.

### Model Lineage Path

Business Definition → Logical Model Representation (Focal model with Atomic Context) → Physical Mapping (specification of generic columns in physical tables)

## The Semantic Key (TYPE_KEY)

The `TYPE_KEY` column bridges physical data rows to metadata descriptions by referencing the unique key of an **Atomic Context**. This enables dynamic data interpretation without custom logic.

A semantic correction (e.g. fixing an attribute name typo) can be done with a single `UPDATE` on metadata — no code recompilation, no data migration, zero downtime.

## Ensemble Modelling — Shared Concepts

| Concept | Focal | Data Vault | Anchor Modelling |
|---------|-------|------------|-----------------|
| Core Business Concept | **Focal** | Hub | Anchor |
| Association / Relationship | **Relation** | Link | Tie |
| Descriptive Data | **Descriptor** | Satellite | Attribute |

## Three Data Categories

1. **Core Business Concepts (Keys)** — Stable identifiers, rarely change.
2. **Descriptive Data** — Attributes describing entities, change over time.
3. **Relationship Data** — Connections between entities, evolve over time.

### Core Principles

- Keys remain stable and non-historized.
- Descriptive data is temporal (timestamped).
- Relationships are temporal and support many-to-many connections.

## The Atomic Context

The smallest set of one-to-many attributes that, taken together, provides a **complete, unambiguous business fact**.

- **Simple example**: "First name" alone answers "What is your first name?"
- **Complex example**: End-of-day balance requires three attributes: date, value, and currency.

The Atomic Context — not the individual attribute — is the primary storage unit, identified by `TYPE_KEY` in physical tables.

## Four Physical Table Types

### 1. IDFR Table (Identifier)

Manages relationships between **business identifiers** and **surrogate keys** through key integration.

Example: A customer identified by internal ID (`14598AC2`) and SSN (`19990310-1693`) both map to `Customer_Key = 1234`.

| Column | Description |
|--------|-------------|
| `[ENTITY]_IDFR` | Business identifier string |
| `EFF_TMSTP` | Effective timestamp |
| `VER_TMSTP` | Version timestamp (bi-temporal) |
| `ROW_ST` | Row status (Y/N) |
| `[ENTITY]_KEY` | Stable surrogate key |
| `DATA_KEY`, `INST_KEY`, `INST_ROW_KEY`, `POPLN_TMSTP` | Audit columns |

### 2. FOCAL Table

Maintains **exactly one row per entity instance** identified by surrogate key, consolidating multiple identifiers from the IDFR table.

### 3. Descriptor Table (DESC)

Stores descriptive attributes using **generic columns** with `TYPE_KEY` identifying data type.

**Entity Identification:**

| Column | Description |
|--------|-------------|
| `[ENTITY]_KEY` | Surrogate key |
| `TYPE_KEY` | Data type identifier (links to Atomic Context) |

**Temporal:**

| Column | Description |
|--------|-------------|
| `EFF_TMSTP` | Effective timestamp |
| `VER_TMSTP` | Version timestamp (bi-temporal) |
| `SEQ_NBR` | Sequence number |
| `ROW_ST` | Row status (Y/N) |

**Value (generic storage):**

| Column | Description |
|--------|-------------|
| `STA_TMSTP` | Start/from timestamp |
| `END_TMSTP` | End/to timestamp |
| `VAL_STR` | Character/string data |
| `VAL_NUM` | Numeric data |
| `UOM` | Unit of measure classification |

**Audit:** `DATA_KEY`, `INST_KEY`, `INST_ROW_KEY`, `POPLN_TMSTP`

Loading pattern: `source_table + type_key + target_table`. New attributes are added via new `TYPE_KEY` values without touching existing pipelines.

### 4. Relationship Table (X)

Captures and tracks **relationships between entities** over time.

Naming convention: `[ENTITY1]_[ENTITY2]_X`

Example: `ORDER_CUSTOMER_X` stores relationship types like `BOUGHT_BY`, `RETURNED_BY`, `SHIPPED_TO`.

| Column | Description |
|--------|-------------|
| `[ENTITY_01]_KEY` | Driving entity surrogate key |
| `[ENTITY_02]_KEY` | Related entity surrogate key |
| `TYPE_KEY` | Relationship type identifier |
| `EFF_TMSTP` / `VER_TMSTP` | Bi-temporal tracking |
| `ROW_ST` | Row status |
| Audit columns | `DATA_KEY`, `INST_KEY`, `INST_ROW_KEY`, `POPLN_TMSTP` |

## Typed vs. Flat Tables

- **Flat Table** — One logical record = one physical row with named columns (e.g. `loan_key`, `loan_amount`, `loan_start_date`).
- **Typed Table** — One logical record split across **multiple physical rows**, each identified by `TYPE_KEY` representing a single Atomic Context. A loan instance (`1234`) might occupy two rows: one for Loan Amount (`type_key 234`), another for Loan Period (`type_key 567`).

## Operational Lineage Tracking

Every physical table includes `INST_KEY` (instance key / `PROCINST_KEY`) for pipeline execution logging. The `PROCINST_DESC` metadata table records each pipeline run.

Example query — retrieve the pipeline SQL that loaded a specific data row:

```sql
SELECT DISTINCT pd.val_str
FROM DAANA_METADATA.PROCINST_DESC pd
INNER JOIN DAANA_DW.CUSTOMER_DESC cd
  ON cd.INST_KEY = pd.PROCINST_KEY
WHERE cd.CUSTOMER_KEY = 'CUST_12345'
```

## Non-Destructive Development

New attributes are added as metadata definitions (new Atomic Contexts) — no `ALTER TABLE` needed. New rows load into pre-existing table structures, eliminating schema changes as a source of risk and delay.

## Key Advantages

- **Extreme flexibility** — Schema doesn't change when business requirements evolve
- **Self-documenting** — Full lineage maintained automatically
- **Standardized pattern** — Same reusable structures across any industry
- **Full auditability** — Every row traces to its source pipeline and metadata definition
- **Stability** — Non-destructive development prevents regression risk

---

## How the Two Layers Work Together (Observed from BigQuery)

### The Data Layer (`DAANA_DW`)

Contains the business data in generic, typed table structures. The current dataset models a **bike-sharing system** with three entities:

| Table | Type | Rows | Description |
|-------|------|------|-------------|
| `RIDE_DESC` | Descriptor | 141,438 | Ride attributes (city, duration) |
| `RIDE_STATION_X` | Relationship | 141,438 | Ride-to-station links (start/end station) |
| `RIDE_CUSTOMER_X` | Relationship | 21,000 | Ride-to-customer links (bought by) |
| `CUSTOMER_DESC` | Descriptor | 4,998 | Customer attributes (email, org number, etc.) |
| `STATION_DESC` | Descriptor | 1,028 | Station attributes (name, city, description, ID) |

Every row in these tables contains a `TYPE_KEY` (integer) and generic value columns (`VAL_STR`, `VAL_NUM`, `STA_TMSTP`, `END_TMSTP`, `UOM`). **Without metadata, these rows are meaningless numbers and strings.**

### The Metadata Layer (`DAANA_METADATA`)

Gives meaning to the data layer. The key table is `ATOM_CONTX_NM` — it maps each `TYPE_KEY` to a human-readable **Atomic Context** name.

### The TYPE_KEY Bridge — Complete Mapping

| DW Table | TYPE_KEY | Atomic Context Name | Rows |
|----------|----------|-------------------|------|
| `STATION_DESC` | 1 | `STATION_CITY_OF_STATION` | 257 |
| `STATION_DESC` | 8 | `STATION_STATION_NAME` | 257 |
| `STATION_DESC` | 20 | `STATION_STATION_DESCRIPTION` | 257 |
| `STATION_DESC` | 24 | `STATION_STATION_ID` | 257 |
| `CUSTOMER_DESC` | 5 | `CUSTOMER_CUSTOMER_ORGNIZATION_NUMBER` | 1,000 |
| `CUSTOMER_DESC` | 14 | `CUSTOMER_CUSTOMER_ID` | 1,000 |
| `CUSTOMER_DESC` | 19 | `CUSTOMER_CUSTOMER_INDUSTRY_CLASSIFICATION` | 999 |
| `CUSTOMER_DESC` | 22 | `CUSTOMER_CUSTOMER_EMAIL_ADDRESS` | 1,000 |
| `CUSTOMER_DESC` | 25 | `CUSTOMER_CUSTOMER_ALT_ID` | 999 |
| `RIDE_DESC` | 10 | `RIDE_CITY_OF_RIDE` | 70,719 |
| `RIDE_DESC` | 18 | `RIDE_RIDE_DURATION_..._START_TMSTP` | 70,719 |
| `RIDE_STATION_X` | 16 | `RIDE_START_STATION` | 70,719 |
| `RIDE_STATION_X` | 23 | `RIDE_END_STATION` | 70,719 |
| `RIDE_CUSTOMER_X` | 27 | `RIDE_BOUGHT_BY_CUSTOMER` | 21,000 |

### Example: Reading a Raw Row

A raw `RIDE_DESC` row:

```
RIDE_KEY: 2022-11-30...437735  |  TYPE_KEY: 18  |  STA_TMSTP: 2022-11-30 23:46:37  |  END_TMSTP: 2022-11-30 23:55:07  |  VAL_NUM: 510  |  UOM: seconds
```

Joining `TYPE_KEY = 18` to `ATOM_CONTX_NM` reveals this is **RIDE_RIDE_DURATION** — a complex Atomic Context using multiple generic columns together:
- `STA_TMSTP` = ride start time
- `END_TMSTP` = ride end time
- `VAL_NUM` = duration (510)
- `UOM` = unit (seconds)

This is the Atomic Context concept in action — four columns together form one complete business fact.

### Lineage: Tracing Data Back to Its Pipeline

Every DW row carries an `INST_KEY` that joins to `PROCINST_DESC.PROCINST_KEY` in the metadata layer. This returns the **actual SQL INSERT statement** that loaded that row:

```sql
SELECT DISTINCT SUBSTR(pi.VAL_STR, 1, 120) as pipeline_sql
FROM DAANA_DW.RIDE_DESC rd
JOIN DAANA_METADATA.PROCINST_DESC pi
  ON rd.INST_KEY = pi.PROCINST_KEY
LIMIT 1
-- Returns: "INSERT INTO DAANA_DW.RIDE_DESC(RIDE_KEY, TYPE_KEY, SEQ_NBR, EFF_TMSTP, ..."
```

### Metadata Describes Itself

The metadata layer follows the **same Focal table patterns** (IDFR, FOCAL, NM, DESC, X tables) as the data layer. This means the metadata is **self-describing** — you can query the metadata to understand both the data layer AND the metadata layer itself.

---

## Navigating the Metadata Model

The metadata model provides a complete chain from a **Focal entity** down to the **physical column** where each attribute is stored. This is the key to programmatically building queries against the data layer.

### The Metadata Chain

```
FOCAL_NM                          ← The entity (e.g. CUSTOMER_FOCAL)
  └─ DESC_CNCPT_FOCAL_FOCAL_X    ← Links Focal to its Descriptor Concepts
       └─ DESC_CNCPT_NM          ← The descriptor table name (e.g. CUSTOMER_DESC)
            └─ ATOM_CONTX_DESC_CNCPT_X  ← Links Descriptor Concept to its Atomic Contexts
                 └─ ATOM_CONTX_NM       ← The Atomic Context name (= the TYPE_KEY meaning)
                      └─ ATR_ATOM_CONTX_X    ← Links Atomic Context to its Attributes
                           └─ ATR_NM         ← The logical attribute name
                                └─ LOGICAL_PHYSICAL_X    ← Maps attribute + atomic context to physical column
                                     └─ TBL_PTRN_COL_NM  ← The physical column name (VAL_STR, VAL_NUM, etc.)
```

### Important: Every Table is a Typed Table

Every table in the metadata layer — including the ones you use to navigate — is itself a typed descriptor table. The `TYPE_KEY` in each row determines **which kind of value** is stored in that row.

For example, `FOCAL_NM` could contain multiple name types: a physical name, a logical name, a display name, etc. Each would have a different `TYPE_KEY` pointing to a different Atomic Context. Before reading a value from any table, you must first decide **which Atomic Context (TYPE_KEY)** to filter on.

This means navigation is a two-phase process:

1. **Resolve the Atomic Context** you need (e.g. "I want the FOCAL_NAME, not the FOCAL_PHYSICAL_NAME")
2. **Filter by that TYPE_KEY** when reading the table

The system is recursive — you use the same metadata chain to understand the metadata tables themselves. This is what makes it truly self-describing.

### Step-by-Step: Traversing the Chain

#### 1. Start at the Focal (Entity)

`FOCAL_NM` contains the entity names. Each row has a `FOCAL_KEY` and a `VAL_STR` with the entity name.

#### 2. Focal → Descriptor Concept (which table holds the data)

Join `FOCAL_NM.FOCAL_KEY` → `DESC_CNCPT_FOCAL_FOCAL_X.FOCAL_KEY` → `DESC_CNCPT_NM.DESC_CNCPT_KEY`

This tells you which **descriptor table** (e.g. `CUSTOMER_DESC`, `RIDE_DESC`) belongs to the entity.

#### 3. Descriptor Concept → Atomic Contexts (which TYPE_KEYs exist)

Join `DESC_CNCPT_NM.DESC_CNCPT_KEY` → `ATOM_CONTX_DESC_CNCPT_X.DESC_CNCPT_KEY` → `ATOM_CONTX_NM.ATOM_CONTX_KEY`

This gives you all the **Atomic Contexts** (TYPE_KEY values) that belong to that descriptor table. Each Atomic Context represents one business fact stored as typed rows.

The `ATOM_CONTX_KEY` in `ATOM_CONTX_NM` corresponds to the `TYPE_KEY` used in the data layer tables.

#### 4. Atomic Context → Attributes (the logical attribute names)

Join `ATOM_CONTX_NM.ATOM_CONTX_KEY` → `ATR_ATOM_CONTX_X.ATOM_CONTX_KEY` → `ATR_NM.ATR_KEY`

This tells you the **logical attribute names** within each Atomic Context. A simple Atomic Context has one attribute; a complex one (like ride duration) has multiple.

#### 5. Attribute + Atomic Context → Physical Column (where the value lives)

Join `ATR_NM.ATR_KEY` + `ATOM_CONTX_KEY` → `LOGICAL_PHYSICAL_X` → `TBL_PTRN_COL_NM.TBL_PTRN_COL_KEY`

This is the **logical-to-physical mapping**. It tells you which generic column (`VAL_STR`, `VAL_NUM`, `STA_TMSTP`, `END_TMSTP`, `UOM`) holds each attribute's value.

**This step is never optional.** You must always resolve the physical column from metadata — never assume a value lives in `VAL_STR`. For simple Atomic Contexts (one attribute), it might happen to be `VAL_STR`. But for complex Atomic Contexts (multiple attributes), each attribute maps to a different physical column. For example, a "ride duration" Atomic Context might map its attributes across `VAL_NUM` (duration), `UOM` (time unit), `STA_TMSTP` (start time), and `END_TMSTP` (end time). Skipping this step and guessing the column will produce incorrect queries for these cases.

### Key Tables Summary

| Table | Role | Key Column | Joins To |
|-------|------|------------|----------|
| `FOCAL_NM` | Entity name | `FOCAL_KEY` | `DESC_CNCPT_FOCAL_FOCAL_X.FOCAL_KEY` |
| `DESC_CNCPT_FOCAL_FOCAL_X` | Entity → Descriptor Concept link | `FOCAL_KEY`, `DESC_CNCPT_KEY` | both sides |
| `DESC_CNCPT_NM` | Descriptor table name | `DESC_CNCPT_KEY` | `ATOM_CONTX_DESC_CNCPT_X.DESC_CNCPT_KEY` |
| `ATOM_CONTX_DESC_CNCPT_X` | Descriptor Concept → Atomic Context link | `DESC_CNCPT_KEY`, `ATOM_CONTX_KEY` | both sides |
| `ATOM_CONTX_NM` | Atomic Context name (= TYPE_KEY meaning) | `ATOM_CONTX_KEY` | `ATR_ATOM_CONTX_X.ATOM_CONTX_KEY` |
| `ATR_ATOM_CONTX_X` | Atomic Context → Attribute link | `ATOM_CONTX_KEY`, `ATR_KEY` | both sides |
| `ATR_NM` | Logical attribute name | `ATR_KEY` | `LOGICAL_PHYSICAL_X.ATR_KEY` |
| `LOGICAL_PHYSICAL_X` | Logical-to-physical column mapping | `ATR_KEY`, `ATOM_CONTX_KEY`, `TBL_PTRN_COL_KEY` | `TBL_PTRN_COL_NM` |
| `TBL_PTRN_COL_NM` | Physical column name | `TBL_PTRN_COL_KEY` | — |

### What This Enables

Given any entity name, an agent can traverse this chain to discover:
1. **Which physical table** holds the data (from Descriptor Concept)
2. **Which TYPE_KEY values** exist for that entity (from Atomic Contexts)
3. **What each TYPE_KEY means** in business terms (from Atomic Context + Attribute names)
4. **Which generic column** to read for each attribute (from Logical-Physical mapping)

With this information, the agent can construct a pivot query (like `f_CUSTOMER`) that transforms the generic typed rows into a flat, human-readable result set.
