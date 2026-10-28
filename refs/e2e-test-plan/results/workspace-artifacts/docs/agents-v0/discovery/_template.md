# Discovery: <program>

> Input document for `/v0-roadmap <path>`. May live anywhere in the repository (for example `docs/product/<program>-discovery.md`).
> All six canonical `##` headings below must be present, non-empty, and free of placeholder tokens (`<...>`, `[...]`, `TBD`, `TODO`, `FIXME`, `XX`/`XXX`, `__`, `???`).

<!-- Optional: delete if no stack preference is set yet. Does not activate a pack until /v0-architecture. -->
Stack preference: <pack-id>

## Problem

<What problem, operational bottleneck, or business opportunity does this initiative solve?>

## Success metric

<!-- Write concrete numbers or ranges (for example "10-50 MB" or "under 250 ms p95"). Avoid "XX" or "TBD". -->
<Measurable target or outcome that defines success for this initiative.>

## Options

### Option 1: <Option name>

<Summary, trade-offs, and constraints of Option 1.>

### Option 2: <Option name>

<Summary, trade-offs, and constraints of Option 2.>

## Chosen option

<The selected option and the rationale for why it was chosen over the alternatives.>

## In scope

<!-- Each leaf bullet must belong to a single roadmap horizon (Now, Next, or Later) and will be copied verbatim.
     If a capability spans multiple horizons (for example batch ingestion in Now and streaming ingestion in Next),
     write them as separate bullets or as nested sub-bullets under a parent category bullet. -->
- <concrete single-horizon deliverable or capability>
- <concrete single-horizon deliverable or capability>
- **<Optional category or theme group>:**
  - <concrete leaf deliverable for one horizon>
  - <concrete leaf deliverable for one horizon>

## Out of scope

- <explicitly excluded capability or deferred requirement>
