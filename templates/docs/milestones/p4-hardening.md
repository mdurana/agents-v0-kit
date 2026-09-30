# Milestone: P4 — Hardening

## Goal
Security, performance, and reliability hardening with integrated `/verify` on manifest scope.

## SLO evidence

P4 `verify` and `release` require `docs/design/system/slo-evidence.md` (`slo-evidence` skill). `ci/check-milestone.sh` reads that path from this manifest. Every filled row in `docs/design/system/nfr-slo.md` is `measured` (command and an output file) or `waiver` (reason, approver, date).

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| P4-A | As an operator, I want the service to meet the SLO recorded for this system, so that production traffic stays inside the error budget. | docs/requirements/p4-a-slo.md | planned | P3 |
| P4-B | As a security reviewer, I want a VAPT retest with no open Critical findings, so that the agreed vulnerability checks are closed before release. | docs/requirements/p4-b-vapt-retest.md | planned | P3 |
| P4-C | As an operator, I want a tested rollback for the current release, so that a bad deploy can be reversed without data loss. | docs/requirements/p4-c-rollback.md | planned | P3 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| milestone | docs/milestones/p4-hardening.md | | | |
