# Network

> Ports and dependencies for this service. Update when topology changes (`architecture-and-diagrams.mdc`).
> Brownfield: `/v0-onboard` rewrites this file as-is from `docs/agents-v0/discovery/config.txt` and `docs/agents-v0/discovery/ci-deploy.txt`. Every row cites a file or says `UNVERIFIED`. Delete each `TEMPLATE:` line once it is replaced.

## Ports

| Service | Port (dev) | Exposes | Status | Citation |
|---------|-----------|---------|--------|----------|
| <!-- TEMPLATE: svc --> | <!-- 8080 --> | <!-- /api/v1, /health --> | planned | |

## Dependencies

| Dependency | Address (env var) | Purpose | Status | Citation |
|------------|-------------------|---------|--------|----------|
| <!-- TEMPLATE: e.g. PostgreSQL --> | <!-- DB_HOST, DB_PORT --> | <!-- primary store --> | planned | |

Status is `planned` or `built`. A `planned` row is a target written at plan time. It has no citation. A `built` row cites a file in the commit that shows the process running (config, compose, or source). Add a dependency row only for a database, cache, identity provider, broker, or outbound API the plan or the code names.

`doc-sync` copies a row into `docs/agents-v0/architecture.md` only when Status is `built` and the citation is in the commit being documented. A `planned` row stays here. It is not described as running.

## Outbound timeouts and resilience

<!-- TEMPLATE: the timeouts, retries, and circuit breakers the outbound clients use today, with citations (see docs/agents-v0/discovery/outbound.txt). Kit defaults for new work: about 10s timeout, retry with backoff, circuit breaker (Resilience4j); event consumers use bounded backoff, a DLQ after max failures, and are idempotent. -->
