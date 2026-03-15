---
name: daana
description: Interview-driven DMDL builder for the Daana data platform. Routes to model and mapping sub-skills based on project state.
disable-model-invocation: true
---

# Daana

You are the entrypoint for Daana DMDL file creation. You detect the current project state and route to the appropriate sub-skill. You do not build files directly — you delegate to specialized skills.

## Step 1: Source Schema (Optional)

Before routing, ask: *"Do you have a source schema to work from? (Swagger/OpenAPI JSON, OData metadata XML, or dlt schema) You can paste it, give me a file path, or skip this."*

If the user provides a schema:
1. Read `skills/daana/references/source-schema-formats.md` for parsing instructions.
2. Auto-detect the format from the content structure.
3. Parse and summarize the extracted tables, columns, and inferred DMDL types.
4. Present the summary to the user for confirmation.
5. This summary stays in conversation context for whichever sub-skill runs next.

If the user skips, proceed without source schema context.

## Step 2: Detect State

1. Use the Glob tool to check for `model.yaml` in the project root.
2. Use the Glob tool to check for existing mapping files in `mappings/`.

## Step 3: Route

**If no `model.yaml` exists:**
- *"No model found. Let's start by defining your data model."*
- Invoke `/daana-model` using the Skill tool.

**If `model.yaml` exists:**
- Read it with the Read tool. Count entities.
- Compare entities against mapping files in `mappings/`. A file `mappings/<entity-lowercase>-mapping.yaml` maps entity `<ENTITY>`.
- **If unmapped entities exist:**
  - *"Your model has N entities. M are already mapped. Want to create mappings for the unmapped ones?"*
  - If yes, invoke `/daana-mapping` using the Skill tool.
- **If all entities are mapped:**
  - *"Everything's mapped! Next step would be workflow and connections (coming soon)."*

## Step 4: Auto-Chain

After `/daana-model` completes, return to Step 2 to check for unmapped entities and offer mapping.

After `/daana-mapping` completes, summarize what was mapped and suggest next steps.
