---
name: contract-first-design
description: Design phase playbook. Produce the OpenAPI 3.0 draft, event schemas, design.md (traceability, data, authorization, failure modes), an ADR with real alternatives, and Mermaid diagrams; check them mechanically.
---

# contract-first-design

Design phase playbook for the `solution-architect` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Intake artifact and the existing repo. On a brownfield repo also read `docs/architecture.md`, `docs/design/system/context-map.md`, the `docs/onboarding/modules/` documents for the touched modules, and `docs/discovery/endpoints.txt` (an operation the draft adds must not clash with one that exists).
2. Define the feature contract draft at `docs/design/<feature>/openapi.yaml`: one self-contained OpenAPI 3.0 file (no external `$ref`) holding only the paths and components this feature adds or changes. Operations use `/api/v1/...`, each with a unique `operationId`, a 2xx response, security, and (for POST) an `Idempotency-Key` header parameter. Do not edit the org catalog (`openapi/api-v1.yaml`, or the catalog path in `docs/project-profile.md`; `openapi/<service>-v1.yaml` with `Service roots`) during Design. Build merges this approved draft into that catalog (`workflow-orchestration.mdc`).
2b. When the feature publishes or consumes async messages, add `docs/design/<feature>/asyncapi.yaml` (AsyncAPI 2.x or 3.x): one channel per topic or queue, each `publish`/`subscribe` message with `x-event-type` or `payload.properties.eventType`, aligned with the JSON schemas under `docs/design/<feature>/events/`. Skip this file when the feature is REST-only.
3. Define event schemas under `docs/design/<feature>/events/` with `eventVersion`; evolution additive; envelope includes `eventId`, `eventType`, `eventVersion`, `timestamp`, `source`, `correlationId`, `data`, `idempotency_key`.
4. Pick one error envelope per API surface: RFC 7807 (`application/problem+json`) **or** the custom `{success, data/error}` envelope — do not mix without versioning.
5. Add idempotency keys on non-idempotent POST/create/pay/cancel.
6. Write `docs/design/<feature>/design.md` from `docs/design/_design.template.md`:
   - **Traceability:** every `AC-n` and NFR of the requirements artifact maps to the operation, event, UX component, or ADR that satisfies it.
   - **Data model:** entities, keys, indexes, volume, retention, PII, and the migration shape (`migration-safety`).
   - **Authorization:** one row per `operationId`: roles or scopes, and the resource rule that proves the caller may touch this `{id}` (BOLA, `security-baseline.mdc` §2).
   - **Failure modes:** per dependency and step, the slow and the partial failure, the behavior, and what the user sees.
   - **Observability** and **Rollout** (flag, deploy order, backward compatibility, rollback).
   A section that does not apply says `N/A: <reason>`.
7. Write an ADR for non-trivial decisions at `docs/adr/<NN>-<slug>.md` with at least two real alternatives and why they lost; name it on the `ADR:` line of `design.md`.
8. Produce Mermaid diagrams (`flowchart`/`sequenceDiagram`) following `architecture-and-diagrams.mdc` conventions; place under `docs/diagrams/sequences/<service>.md`.
9. Write `docs/design/<feature>/helper-brief.md` (`helper: schema-author`) listing `docs/design/<feature>/openapi.yaml` and the event files as `outputs`. Do not launch the helper. Continue after the main session returns its result (`workflow-orchestration.mdc` Helper agents).
10. Run the checks and fix until they pass: `sh ci/check-openapi.sh lint docs/design/<feature>/openapi.yaml`, `sh ci/check-openapi.sh compat docs/design/<feature>/openapi.yaml <catalog>` (when the catalog exists), `sh ci/check-asyncapi.sh lint docs/design/<feature>/asyncapi.yaml` (when that file exists), and `sh ci/check-design.sh <feature>`.
11. Present the Design gate result and wait for approval before Build. The gate names the feature draft, not a catalog edit. After approval the design is pinned (`sh ci/check-design.sh <feature> --pin "approved"`); later changes are amendments (`/design` Amending an approved design).

## Rule-compliance checklist
- [ ] `api-and-events.mdc`: contract-first; `/api/v1/`; idempotency keys; one envelope per surface; event `eventVersion`; pagination contract.
- [ ] Feature draft is `docs/design/<feature>/openapi.yaml`, self-contained. The org catalog is not edited in Design.
- [ ] `design.md`: every AC traced; every operation in the authorization matrix; data, failure modes, observability, rollout written or `N/A: <reason>`.
- [ ] `architecture-and-diagrams.mdc`: DDD boundaries; DB per service; ADR with alternatives; Mermaid conventions; diagram locations.
- [ ] `project-delivery-core.mdc`: async/messaging/cache justified; no reactive/MVC switch without ADR.
- [ ] `security-baseline.mdc` §2: BOLA — authorized lookup for every `{id}` path.
- [ ] `ci/check-openapi.sh lint`/`compat`, `ci/check-asyncapi.sh lint` (when asyncapi.yaml exists), and `ci/check-design.sh` pass.
- [ ] `workflow-orchestration.mdc`: Design gate criteria met; stopped for approval.
