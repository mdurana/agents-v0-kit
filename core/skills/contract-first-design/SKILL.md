---
name: contract-first-design
description: Design phase playbook. Produce OpenAPI 3.0 and event schemas, an ADR, and Mermaid diagrams.
---

# contract-first-design

Design phase playbook for the `solution-architect` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Intake artifact and the existing repo.
2. Define the feature contract draft at `docs/design/<feature>/openapi.yaml`. Operations use `/api/v1/...`. Do not edit the org catalog (`openapi/api-v1.yaml`, or the catalog path in `docs/project-profile.md`) during Design. Build merges this approved draft into that catalog (`workflow-orchestration.mdc`).
3. Define event schemas under `docs/design/<feature>/events/` with `eventVersion`; evolution additive; envelope includes `eventId`, `eventType`, `eventVersion`, `timestamp`, `source`, `correlationId`, `data`, `idempotency_key`.
4. Pick one error envelope per API surface: RFC 7807 (`application/problem+json`) **or** the custom `{success, data/error}` envelope — do not mix without versioning.
5. Add idempotency keys on non-idempotent POST/create/pay/cancel.
6. Write an ADR for non-trivial decisions at `docs/adr/<NN>-<slug>.md`.
7. Produce Mermaid diagrams (`flowchart`/`sequenceDiagram`) following `architecture-and-diagrams.mdc` conventions; place under `docs/diagrams/sequences/<service>.md`.
8. Write `docs/design/<feature>/helper-brief.md` (`helper: schema-author`) listing `docs/design/<feature>/openapi.yaml` and the event files as `outputs`. Do not launch the helper. Continue after the main session returns its result (`workflow-orchestration.mdc` Helper agents).
9. Present the Design gate result and wait for approval before Build. The gate names the feature draft, not a catalog edit.

## Rule-compliance checklist
- [ ] `api-and-events.mdc`: contract-first; `/api/v1/`; idempotency keys; one envelope per surface; event `eventVersion`; pagination contract.
- [ ] Feature draft is `docs/design/<feature>/openapi.yaml`. The org catalog is not edited in Design.
- [ ] `architecture-and-diagrams.mdc`: DDD boundaries; DB per service; ADR; Mermaid conventions; diagram locations.
- [ ] `project-delivery-core.mdc`: async/messaging/cache justified; no reactive/MVC switch without ADR.
- [ ] `security-baseline.mdc` §2: BOLA — authorized lookup for every `{id}` path.
- [ ] `workflow-orchestration.mdc`: Design gate criteria met; stopped for approval.
