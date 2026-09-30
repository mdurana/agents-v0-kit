# Network

> Ports and dependencies for this service. Update when topology changes (`architecture-and-diagrams.mdc`).

## Ports

| Service | Port (dev) | Exposes | Notes |
|---------|-----------|---------|-------|
| <!-- svc --> | <!-- 8080 --> | <!-- /api/v1, /health --> | |

## Dependencies

| Dependency | Address (env var) | Purpose |
|------------|-------------------|---------|
| PostgreSQL | `DB_HOST`, `DB_PORT=5432` | primary store |
| Redis | `REDIS_HOST`, `REDIS_PORT=6379` | cache / session |
| IdP (Okta) | `IDP_ISSUER` | OAuth2/OIDC |
| Kafka | `KAFKA_BOOTSTRAP_SERVERS` | events (if used) |

## Outbound timeouts and resilience

- HTTP clients: ~10s timeout, retry with backoff, circuit breaker (Resilience4j).
- Event consumers: bounded backoff, DLQ after max failures, idempotent.
