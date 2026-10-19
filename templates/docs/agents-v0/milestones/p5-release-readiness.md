# Milestone: P5 — Release Readiness

## Goal
Production readiness: docs, runbooks, CI/CD, release checklist, milestone go/no-go.

## Readiness checklist

The P5 readiness stories (`P5-A`, `P5-B`, …) tick the 10 boxes in `docs/agents-v0/design/system/ops-readiness.md` while keeping each story within the Size ≤ 8 acceptance-criteria cap. A box stays open only with a named reason in that file. `.agents-v0/ci/check-architecture-pack.sh` checks that the sections exist. It does not check the boxes.

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| P5-A | As an operator, I want on-call ownership, SLO alerts, dashboards, health checks, tracing, and runbooks verified, so that the service is observable and operable in production. | docs/agents-v0/requirements/p5-a-observability-and-runbooks.md | planned | P4 | — | — |
| P5-B | As a release manager, I want rollback, dependency-kill resilience, capacity baseline, backup restore, CI security audit, and go/no-go verified, so that production starts only after an approved readiness review. | docs/agents-v0/requirements/p5-b-resilience-and-release-readiness.md | planned | P5-A | — | — |

> Replace milestone stub `P4` with concrete story-ID dependencies, fill Surface and Size, and record covered ops-readiness checklist items across stories (`ops-1`..`ops-10`) via an 8th `Covers` column or the `## Traceability` section below during `/v0-plan`.

## Security review triggers

none

## Traceability

| Story ID | Covers |
|----------|--------|
| P5-A | ops-1, ops-2, ops-3, ops-4, ops-7 |
| P5-B | ops-5, ops-6, ops-8, ops-9, ops-10 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| milestone | docs/agents-v0/milestones/p5-release-readiness.md | | | |
