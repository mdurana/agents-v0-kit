# Milestone: P4 — Hardening

## Goal
Security, performance, and reliability hardening with integrated `/v0-verify` on manifest scope.

## SLO evidence

P4 `verify` and `release` require `docs/agents-v0/design/system/slo-evidence.md` (`slo-evidence` skill). `.agents-v0/ci/check-milestone.sh` reads that path from this manifest. Every filled row in `docs/agents-v0/design/system/nfr-slo.md` is `measured` (command and an output file) or `waiver` (reason, approver, date). The ARC record points its SLO targets at that table. The structural fitness-function table in the same section is not an SLO list, and this milestone does not close it.

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| P4-A | As an operator, I want the service to meet the SLO recorded for this system, so that production traffic stays inside the error budget. | docs/agents-v0/requirements/p4-a-slo.md | planned | P3 | — | — |
| P4-B | As a security reviewer, I want a VAPT retest with no open Critical findings, so that the agreed vulnerability checks are closed before release. | docs/agents-v0/requirements/p4-b-vapt-retest.md | planned | P3 | — | — |
| P4-C | As an operator, I want a tested rollback for the current release, so that a bad deploy can be reversed without data loss. | docs/agents-v0/requirements/p4-c-rollback.md | planned | P3 | — | — |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| milestone | docs/agents-v0/milestones/p4-hardening.md | | | |
