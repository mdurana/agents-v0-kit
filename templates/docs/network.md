# Network

> Ports and dependencies for this service. Update when topology changes (`architecture-and-diagrams.mdc`).
> Brownfield: `/onboard` rewrites this file as-is from `docs/discovery/config.txt` and `docs/discovery/ci-deploy.txt`. Every row cites a file or says `UNVERIFIED`. Delete each `TEMPLATE:` line once it is replaced.

## Ports

| Service | Port (dev) | Exposes | Notes |
|---------|-----------|---------|-------|
| <!-- TEMPLATE: svc --> | <!-- 8080 --> | <!-- /api/v1, /health --> | |

## Dependencies

| Dependency | Address (env var) | Purpose |
|------------|-------------------|---------|
| <!-- TEMPLATE: e.g. PostgreSQL --> | <!-- DB_HOST, DB_PORT --> | <!-- primary store --> |

Add a row only for a dependency the code or config actually uses (database, cache, identity provider, broker, outbound API).

## Outbound timeouts and resilience

<!-- TEMPLATE: the timeouts, retries, and circuit breakers the outbound clients use today, with citations (see docs/discovery/outbound.txt). Kit defaults for new work: about 10s timeout, retry with backoff, circuit breaker (Resilience4j); event consumers use bounded backoff, a DLQ after max failures, and are idempotent. -->
