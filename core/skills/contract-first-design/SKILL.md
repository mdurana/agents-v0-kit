---
name: contract-first-design
description: Design phase playbook. Produce OpenAPI 3.0 and event schemas, an ADR, and Mermaid diagrams.
---

# contract-first-design

Design phase playbook for the `solution-architect` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Intake artifact and the existing repo.
2. Define OpenAPI 3.0 contracts under `/api/v1/...` for new/changed cross-service APIs.
3. Define event schemas with `eventVersion`; evolution additive; envelope includes `eventId`, `eventType`, `eventVersion`, `timestamp`, `source`, `correlationId`, `data`, `idempotency_key`.
4. Pick one error envelope per API surface: RFC 7807 (`application/problem+json`) **or** the custom `{success, data/error}` envelope — do not mix without versioning.
5. Add idempotency keys on non-idempotent POST/create/pay/cancel.
6. Write an ADR for non-trivial decisions at `docs/adr/<NN>-<slug>.md`.
7. Produce Mermaid diagrams (`flowchart`/`sequenceDiagram`) following `architecture-and-diagrams.mdc` conventions; place under `docs/diagrams/sequences/<service>.md`.
8. Launch the `schema-author` subagent to draft schema/contract files.
9. Present the Design gate result and wait for approval before Build.

## Rule-compliance checklist
- [ ] `api-and-events.mdc`: contract-first; `/api/v1/`; idempotency keys; one envelope per surface; event `eventVersion`; pagination contract.
- [ ] `architecture-and-diagrams.mdc`: DDD boundaries; DB per service; ADR; Mermaid conventions; diagram locations.
- [ ] `project-delivery-core.mdc`: async/messaging/cache justified; no reactive/MVC switch without ADR.
- [ ] `security-baseline.mdc` §2: BOLA — authorized lookup for every `{id}` path.
- [ ] `workflow-orchestration.mdc`: Design gate criteria met; stopped for approval.
