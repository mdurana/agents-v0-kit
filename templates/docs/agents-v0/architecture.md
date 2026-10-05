# Architecture

> System context for this service. `/v0-onboard` or the P0 build fills the as-is sections. `/v0-architecture` adds the C4 sections and the `architecture` approval before any story. A later feature updates as-is text in a docs-only follow-up (`doc-sync`).
> Brownfield: `/v0-onboard` rewrites the as-is sections. Every statement cites code (`path/File.java:42`) or says `UNVERIFIED`. `/v0-architecture` keeps those citations and adds the target C4 sections beside them. Delete each `TEMPLATE:` line once it is replaced.

## Context

<!-- TEMPLATE: one paragraph — what this system is and who uses it. -->

## Containers

<!-- TEMPLATE: replace with a Mermaid flowchart of the services, BFF, frontends, data stores, and messaging that exist. Draw only what the code and config show. -->

```mermaid
flowchart LR
  %% TEMPLATE: replace this placeholder
  placeholder[Describe the real containers]
```

## Service boundaries

| Service | Owns | DB | API |
|---------|------|----|----|
| <!-- TEMPLATE: e.g. order-service --> | <!-- Order aggregate --> | <!-- order_db --> | <!-- /api/v1/orders --> |

## Cross-cutting

<!-- TEMPLATE: how correlation ID, tracing, logging, auth, and health work in this system today, each with a citation. Kit defaults for new work: X-Correlation-ID header + MDC, W3C Trace Context (traceparent), JWT for users and X-API-Key or service Bearer for S2S, /health /ready /live. -->

## ADRs

See `docs/agents-v0/adr/`.

## C4 Context

<!-- /v0-architecture: people and external systems. No product, database, or broker names. -->

## C4 Container

<!-- /v0-architecture: containers only, still technology-agnostic. The pattern ADR chooses technology. -->

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|

> `/v0-architecture` appends the `architecture` row after one explicit approval. The Artifacts cell names `docs/agents-v0/design/system/arc-record.md`. An `arc` row is only for a later story that amends the recommendation. `/v0-plan` waits for the `architecture` row. Who skips this command: `workflow-orchestration.mdc` Architecture.
