# Milestone: P0 — Platform Skeleton

> Program manifest for the first greenfield milestone: runnable repo, kit installed,
> quality gate wired, and a minimal vertical slice ready for P1 contracts. Each story
> runs Intake → Design → Build → Verify → Release with approvals in its own feature
> artifact (`workflow-orchestration.mdc`).

## Goal

Deliver a **known-good baseline**: the project builds and tests cleanly, Maven or
frontend quality plugins are bound to `verify`, the agents-v0 kit is installed, and
one minimal health or hello endpoint (or static shell UI) proves the stack runs locally
and in CI.

## Scope

- In: repo layout, CI skeleton, quality gate wiring from kit templates, kit install,
  minimal service or app entrypoint, README build/run/test commands, optional local
  local container run via `Dockerfile` + `docker-compose.yml` and
  `scripts/run-local-container.sh` (Podman or Docker).
- Out: business features, production deployment, full OpenAPI catalog (P1).

## Dependencies

- None (first milestone). P1 depends on this milestone merged with a green
  `mvn -B clean verify` or frontend equivalent.

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| P0-A | As a developer I can clone the repo and run the standard build/test command successfully | docs/requirements/p0-a-green-baseline.md | planned | — |
| P0-B | As a developer I have the delivery kit installed and P0 milestone tracked | docs/requirements/p0-b-kit-and-milestone.md | planned | P0-A |
| P0-C | As a developer I have quality plugins (coverage, static analysis, CVE scan) bound to verify | docs/requirements/p0-c-quality-gate.md | planned | P0-A |
| P0-D | As a developer I can build and run the app locally with Dockerfile + Compose (Podman or Docker) | docs/requirements/p0-d-local-container.md | planned | P0-A |

> Replace or extend rows as your stack requires (BFF-only, frontend-only, etc.).
> P0-D: copy the matching starter from `docker/` per `docker/README.md`.
> Record `Milestone: P0 — Platform Skeleton` and `Story: <id>` in each feature artifact
> (`spec-intake` skill).

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| milestone | docs/milestones/p0-platform-skeleton.md, story artifacts | | | |

> Go/no-go: `ci/check-approvals.sh docs/milestones/p0-platform-skeleton.md milestone`
> and `ci/check-milestone.sh docs/milestones/p0-platform-skeleton.md verify`.
