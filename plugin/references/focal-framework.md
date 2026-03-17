# Focal Framework Context

## Table Taxonomy

| Table Type | Pattern | Purpose |
|---|---|---|
| FOCAL | `{ENTITY}_FOCAL` | One row per entity instance (surrogate key) |
| IDFR | `{ENTITY}_IDFR` | Business identifier to surrogate key mapping |
| DESC | `{ENTITY}_DESC` | Descriptive attributes in key-value format via TYPE_KEY |
| Relationship | `{ENTITY1}_{ENTITY2}_X` | Temporal many-to-many relationships |
| Current view | `VIEW_{ENTITY}` | Current state snapshot |
| Historical view | `VIEW_{ENTITY}_HIST` | Full change history |
| Related view | `VIEW_{ENTITY}_WITH_REL` | Current state with pre-joined relationships |

## Timestamp Types

- **EFF_TMSTP** (Effective) — Business time: when this version became valid
- **VER_TMSTP** (Version) — System time: when the warehouse recorded this version
- **POPLN_TMSTP** (Population) — Load time: when the row was physically inserted
