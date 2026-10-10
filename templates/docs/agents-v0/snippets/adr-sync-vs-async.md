# ADR <NN>: Sync HTTP vs async messaging for <integration>

- **Date:** YYYY-MM-DD
- **Status:** Proposed
- **Deciders:** <names>

## Context

`<Service A>` must notify or query `<Service B>` for `<outcome>`. Latency budget is `<N ms / N/A>`. Failure must be `<visible to user / compensated / queued>`.

## Decision

<!-- Choose one: sync HTTP (RestClient/WebClient) OR async (Kafka/Rabbit/SCS). Delete the unused alternative summary below after acceptance. -->

**Chosen:** <sync HTTP | async messaging>

## Alternatives considered

- **Sync HTTP** — Pros: simple request/response, easy tracing on one call, immediate user feedback. Cons: couples availability and latency; retries can stampede; harder saga compensation across waits.
- **Async messaging** — Pros: temporal decoupling, retries/DLQ, better for multi-step sagas. Cons: eventual consistency, harder desk checks, needs idempotent consumers and correlation.

## Patterns considered

| Pattern | Fit | Trade-offs | Rejected because |
|---------|-----|------------|------------------|
| Sync request/response | <yes/no> | Cost low; reliability tied to callee; operability simple | <or keep> |
| Async with outbox + consumer | <yes/no> | Cost higher; reliability via DLQ; operability needs lag alerts | <or keep> |

## Consequences

- Positive: <...>
- Negative: <...>
- Neutral: idempotency keys on mutating publishes; `correlationId` on every message or outbound call.

## Compliance

- `project-delivery-core.mdc`: messaging only when justified.
- `api-and-events.mdc`: contract-first; event `eventVersion` when async.
- `security-baseline.mdc`: authn/authz on the chosen path.
