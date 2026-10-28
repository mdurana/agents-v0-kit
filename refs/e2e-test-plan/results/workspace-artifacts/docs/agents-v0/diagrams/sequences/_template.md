# Sequence: <service>

> Non-trivial flow for <service>. Follow Mermaid conventions (`architecture-and-diagrams.mdc`).

## <Flow name>

```mermaid
sequenceDiagram
  participant client as Client
  participant bff as BFF
  participant svc as Service
  participant db as DB
  client->>bff: POST /api/v1/<resource>
  bff->>svc: authorize + forward
  svc->>db: persist
  svc-->>bff: 201 Created
  bff-->>client: 201 Created
```

## Notes

- Idempotency key on non-idempotent creates (`api-and-events.mdc`).
- Correlation ID propagated end-to-end.
