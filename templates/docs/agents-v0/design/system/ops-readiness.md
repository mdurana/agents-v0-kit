# Operations readiness

> Produced by `program-architecture`. Who runs the system, how an error budget is spent, what must be true before go-live, and how the database is kept healthy. SLO targets and error budgets live only in `docs/agents-v0/design/system/nfr-slo.md` (do not duplicate SLO tables here; operational parameters such as backup schedules for RPO and restore targets for RTO reference `nfr-slo.md`). `.agents-v0/ci/check-architecture-pack.sh` requires these sections to be written. It does not tick the checklist. The P5 readiness stories close the boxes.

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

The P5 readiness stories (`P5-A`, `P5-B`, … in `docs/agents-v0/milestones/p5-release-readiness.md`, split so each story stays within the Size ≤ 8 cap) tick these boxes. A box stays open only with a named reason. A production deploy waits on that (`release-deploy`).

- [ ] `ops-1` On-call rotation and escalation path are defined.
- [ ] `ops-2` SLOs and error budgets are measurable (`slo-evidence.md`).
- [ ] `ops-3` Dashboards and SLO-based alerts exist; each alert links its runbook.
- [ ] `ops-4` Health checks (`/health`, `/ready`, `/live`) and graceful shutdown work.
- [ ] `ops-5` Rollback and feature-flag strategy was exercised in a non-production environment.
- [ ] `ops-6` Resilience patterns were validated by a dependency-kill test, not only unit tests.
- [ ] `ops-7` Trace and correlation IDs cross every service and async boundary.
- [ ] `ops-8` Capacity baseline exists for the critical paths.
- [ ] `ops-9` Backup restore or failover was tested when `nfr-slo.md` sets an RPO or RTO.
- [ ] `ops-10` Security scan and dependency audit passed in CI.

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
