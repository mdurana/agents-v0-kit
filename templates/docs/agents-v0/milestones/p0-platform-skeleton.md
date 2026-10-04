# Milestone: P0 — Platform Skeleton

> Program manifest for the first greenfield milestone. One story, one branch, and one
> merge request: the repo builds, this manifest is the tracked program, quality plugins
> are bound to verify, and the app runs locally in a container. Later milestones split
> into one story per contract (`workflow-orchestration.mdc`).

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
| P0-A | As a developer, I want a known-good baseline — the build and tests pass, this milestone is the tracked manifest, coverage and CVE scanning are bound to verify, and I can run the app locally with Dockerfile and Compose — so that feature work starts from a stack that already runs. | docs/agents-v0/requirements/p0-a-platform-skeleton.md | planned | — |

> When `.cursor/` and `.agents-v0/` are already present, do not reinstall the kit. `bootstrap-greenfield.sh` or `install.sh` already did that. Copy the container starter from `docker/` per `docker/README.md`.
> Split this row only when a part of the baseline has its own `/api/v1` contract. Keep at most eight acceptance criteria (`AC-1` through `AC-8`).
> Record `Milestone: P0 — Platform Skeleton` and `Story: P0-A` in the feature artifact (`spec-intake` skill).

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| milestone | docs/agents-v0/milestones/p0-platform-skeleton.md, story artifacts | | | |

> Go/no-go: `ci/check-approvals.sh docs/agents-v0/milestones/p0-platform-skeleton.md milestone`
> and `ci/check-milestone.sh docs/agents-v0/milestones/p0-platform-skeleton.md verify`.
