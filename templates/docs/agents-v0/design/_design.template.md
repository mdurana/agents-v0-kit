# Design: <feature>

> Copy to `docs/agents-v0/design/<feature>/design.md`. `sh .agents-v0/ci/check-design.sh <feature>` checks it: every section below must say something, or say `N/A: <reason>`; every `AC-n` of the requirements artifact appears in Traceability; every `operationId` of `openapi.yaml` appears in Authorization; the ADR line names a real ADR with at least two alternatives and Status `Proposed` or `Accepted`. A pin requires `Accepted`. A later decision supersedes that file. Delete each `TEMPLATE:` line when you replace it.

ADR: <!-- TEMPLATE: docs/agents-v0/adr/NN-slug.md, or "N/A: <reason>" -->

## Traceability

Every acceptance criterion and NFR of `docs/agents-v0/requirements/<feature>.md` maps to what satisfies it.

| Requirement | Satisfied by | Notes |
|-------------|--------------|-------|
| <!-- TEMPLATE: AC-1 --> | <!-- operationId `createOrder`, event `OrderCreated`, UX component `Place order button`, ADR NN --> | |

## Data model

<!-- TEMPLATE: the entities and tables this feature adds or changes, keys and indexes, expected volume and growth, retention, which columns hold PII and how they are protected, and the migration shape (expand/contract, `migration-safety`). "N/A: <reason>" for a story with no persistence. -->

## Authorization

One row per operation of the contract draft. The resource rule is the BOLA check: how the service proves this principal may touch this `{id}`. A public operation uses the pack's public marker in Notes (Pack `java`: `@PreAuthorize("permitAll()")`; do not name `org.springframework.security.access.prepost.PermitAll`). When the story has no `/api/v1` operation, this section is `N/A: no /api/v1 operation`.

| operationId | Roles or scopes | Resource rule | Notes |
|-------------|-----------------|---------------|-------|
| <!-- TEMPLATE: createOrder --> | <!-- ROLE_CUSTOMER --> | <!-- the order belongs to the caller --> | |

## Failure modes

<!-- TEMPLATE: for each dependency and step, what fails, what the service does (timeout, retry, circuit breaker, fallback, compensation), and what the user sees. Include the slow and the partially-failed case, not only "down". Name every Kind: negative and Kind: edge id from the requirements artifact (AC-2, AC-3, …). -->

## Observability

<!-- TEMPLATE: metrics (rate, errors, duration) and any business metric, log fields, trace spans, alerts and who is paged, dashboards. -->

## Rollout

<!-- TEMPLATE: feature flag and default, order of deployment across services, backward compatibility of the contract and the data, how to roll back. -->
