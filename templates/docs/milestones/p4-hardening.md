# Milestone: P4 — Hardening

## Goal
Security, performance, and reliability hardening with integrated `/verify` on manifest scope.

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
