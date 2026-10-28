# Component plan: <service>

> One file per bounded context, at `docs/agents-v0/design/system/components/<service>.md`. It deepens `docs/agents-v0/architecture.md` for this service and never contradicts it. Boundaries, topology, and technology choices stay in the system documents and the ADRs.

Parent: `docs/agents-v0/architecture.md`
Context map row: `docs/agents-v0/design/system/context-map.md` (Context: <name>)
Service root: <path>

## Scope

<!-- What this service owns, and what it explicitly does not. One paragraph. -->

## Internal modules

<!-- C4 level 3: the main modules and how they depend on each other. A Mermaid flowchart, or `N/A: <reason>`. -->

## Owned data

<!-- The entities this service owns, taken from the logical and physical data models in architecture.md. Name the store, the migration tool, and the retention rule. `N/A: stateless`. -->

## Integrations

| Peer | Direction | Style (sync or async) | Contract | Failure behaviour |
|------|-----------|-----------------------|----------|-------------------|
| | | | | |

## Operations

<!-- Component-scoped detail only. Link the system-level targets in nfr-slo.md and ops-readiness.md; do not restate them. -->

| Item | Value |
|------|-------|
| RPO / RTO | |
| Connection pool and timeouts | |
| Alerts that page | |
| Runbook | |

## Consistency check

- [ ] Names, boundaries, and technology match `docs/agents-v0/architecture.md` and the Accepted pattern ADR.
- [ ] Every integration appears in the system data flow.
- [ ] No section restates a number that lives in `nfr-slo.md`.
