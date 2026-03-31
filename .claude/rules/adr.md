# Architecture Decision Records (ADR)

## Format

Each feature gets one ADR file in `docs/superpowers/adr/`, named `<date>-<feature-slug>-adr.md` (matching the spec/plan naming convention). Decisions are appended as numbered entries:

### Template

    ## ADR-NNN: <Title>

    - **Date:** YYYY-MM-DD
    - **Status:** accepted | superseded by ADR-NNN

    ### Context
    What prompted the decision.

    ### Options Considered
    - **Option A** — trade-offs
    - **Option B** — trade-offs

    ### Decision
    What was chosen and why.

    ### Consequences
    What this means going forward.

## Conventions

- Numbering is sequential within the feature file (ADR-001, ADR-002, ...). There is no global numbering.
- Discovery is convention-based: use the `*-adr.md` naming pattern and search. There is no index file.

## Rules

- NEVER modify an existing ADR entry. Append a new entry that supersedes it.
- NEVER create an ADR file without following the naming convention `<date>-<feature-slug>-adr.md`.
- NEVER omit "Options Considered" — if there were no alternatives, it is not a decision worth recording.
- NEVER log trivial implementation details (variable names, formatting). Only log choices between meaningful alternatives.
