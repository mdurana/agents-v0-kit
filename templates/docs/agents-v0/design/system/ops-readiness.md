# Operations readiness

> Produced by `program-architecture`. Who runs the system, how an error budget is spent, what must be true before go-live, and how the database is kept healthy. SLO numbers live only in `docs/agents-v0/design/system/nfr-slo.md`; do not copy them here. `.agents-v0/ci/check-architecture-pack.sh` requires these sections to be written. It does not tick the checklist. The P5 readiness story closes the boxes.

## Build and run ownership

<!-- The delivery team owns the service in production. Name the owning team, the on-call rotation, the escalation path, and where runbooks live. -->

| Item | Value |
|------|-------|
| Owning team | |
| On-call rotation | |
| Escalation path | |
| Runbook location | |

## Error budget policy

<!-- What happens when a budget in nfr-slo.md is spent: who is told, which work stops, and what must be true to resume releases. -->

## Database maintenance and operation

<!-- One row per datastore. Schema and migration ownership and retention come from the Physical data model; fill the runtime rows here. `N/A: <reason>` when the system has no datastore. -->

| Datastore | Backup and recovery (schedule, PITR, restore test) | Performance maintenance (pooling, replicas, vacuum or equivalent) | Alerts and runbook |
|-----------|-----------------------------------------------------|---------------------------------------------------------------------|--------------------|
| | | | |

## Production readiness checklist

The P5 readiness story ticks these boxes (`docs/agents-v0/milestones/p5-release-readiness.md`). A box stays open only with a named reason. A production deploy waits on that (`release-deploy`).

- [ ] On-call rotation and escalation path are defined.
- [ ] SLOs and error budgets are measurable (`slo-evidence.md`).
- [ ] Dashboards and SLO-based alerts exist; each alert links its runbook.
- [ ] Health checks (`/health`, `/ready`, `/live`) and graceful shutdown work.
- [ ] Rollback and feature-flag strategy was exercised in a non-production environment.
- [ ] Resilience patterns were validated by a dependency-kill test, not only unit tests.
- [ ] Trace and correlation IDs cross every service and async boundary.
- [ ] Capacity baseline exists for the critical paths.
- [ ] Backup restore or failover was tested when `nfr-slo.md` sets an RPO or RTO.
- [ ] Security scan and dependency audit passed in CI.

## Runbook template

One file per service, linked from `ops-readiness.md` and the component plan.

```markdown
# Runbook: <service>

## Alert: <name>
Severity: P1 | P2 | P3
SLO impact: <which SLO is burning>

### Symptoms
### Diagnosis steps
### Mitigation
### Escalation path
### Rollback procedure
```
