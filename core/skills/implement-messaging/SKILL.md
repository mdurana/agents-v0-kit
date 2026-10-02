---
name: implement-messaging
description: Build phase playbook. Producers, idempotent consumers, transactional outbox, DLQ, and saga steps for Kafka, RabbitMQ, or Spring Cloud Stream, with Testcontainers tests.
---

# implement-messaging

Build phase playbook for the `backend-engineer` agent, used together with `implement-spring-service` when a story publishes or consumes events or runs a saga (`workflow-orchestration.mdc`, `api-and-events.mdc`). It replaces no step of `implement-spring-service`; baseline, plan, red–green loop, attempt budget, and the full verify gate stay as written there.

## Steps
1. Read the approved event schemas under `docs/agents-v0/design/<feature>/events/` and the ADR that justifies async messaging (`project-delivery-core.mdc`). Stop if no schema or no ADR exists. Do not invent an event shape.
2. Copy the approved schemas to the event-schema path in `docs/agents-v0/project-profile.md` when that path is set. Every payload carries the envelope fields (`eventId`, `eventType`, `eventVersion`, `timestamp`, `source`, `correlationId`, `data`, `idempotency_key`).
3. **Producer.** Write the domain change and the outbox row in one transaction (transactional outbox). A relay publishes from the outbox. Never publish from inside the domain transaction. Partition key = aggregate ID, so one aggregate's events stay ordered.
4. **Consumer.** Dedupe by `eventId` before any side effect, in the same transaction as the side effect. Retry with bounded exponential backoff. After the last retry, send to the dead-letter topic or queue with the error and `correlationId`. Never swallow a failure. Log the event ID and a hash or redacted summary, not the payload.
5. **Saga step.** One local transaction per step, plus a compensating action for every step that has a side effect. Persist saga state (`saga_id`, step, status, timestamps). A timeout moves a stuck saga to compensation. Compensations are idempotent.
6. Propagate `correlationId` and `traceparent` in event headers. A consumer restores them into MDC before it logs.
7. Tests (red–green, one per plan row), with Testcontainers for the broker and the database:
   - duplicate delivery of the same `eventId` produces one side effect;
   - a poison message reaches the DLQ after the bounded retries and does not block the partition;
   - the outbox row exists when the domain write commits, and does not exist when it rolls back;
   - each compensation runs when its step fails;
   - a consumer accepts an older `eventVersion` that the schema still allows.
8. Persist evidence to `docs/agents-v0/build/<feature>/build-report.md` as `implement-spring-service` step 17 says.

## Rule-compliance checklist
- [ ] `api-and-events.mdc`: idempotent consumers, bounded retries, DLQ, outbox, envelope, additive `eventVersion`.
- [ ] `project-delivery-core.mdc`: messaging justified by an ADR.
- [ ] `security-baseline.mdc`: no secrets or PII in event logs.
- [ ] Every saga step with a side effect has an idempotent compensation and a test.
- [ ] Testcontainers tests cover duplicate, poison message, outbox rollback, and compensation.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
