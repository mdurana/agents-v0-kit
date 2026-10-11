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
  `.agents-v0/scripts/run-local-container.sh` (Podman or Docker).
- Out: business features, production deployment, full OpenAPI catalog (P1).

## Dependencies

- None (first milestone). P1 depends on this milestone merged with a green
  `./mvnw -B clean verify` or frontend equivalent.

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| P0-A | As a developer, I want a known-good baseline — the build and tests pass, this milestone is the tracked manifest, coverage and CVE scanning are bound to verify, and I can run the app locally with Dockerfile and Compose — so that feature work starts from a stack that already runs. | docs/agents-v0/requirements/p0-a-platform-skeleton.md | planned | — | vertical slice | 4 |

> When `.cursor/` and `.agents-v0/` are already present, do not reinstall the kit. `bootstrap-greenfield.sh` or `install.sh` already did that. Prefer `bootstrap-greenfield.sh --scaffold-app` so `templates/app/p0-platform-skeleton.tar.gz` seeds `app/backend` and `app/frontend`. Copy container starters from `docker/` only when not using that archive.
> This row is one story. Record `Vertical slice: yes`. Do not write `## Proposed split` because the container files sit next to the service. Acceptance criteria are only:
> - `AC-1` the build and tests pass
> - `AC-2` this milestone is the tracked manifest, and the kit is not installed again when it is already present
> - `AC-3` coverage, static analysis, and CVE scanning are bound to verify
> - `AC-4` the app runs locally with Dockerfile and Compose
> A `/health`, `/ready`, or `/live` route with `@PreAuthorize("permitAll()")` does not by itself require `design-reviewer`. Split this row only when a part of the baseline has its own `/api/v1` contract.
> `/v0-build` records `Milestone: P0 — Platform Skeleton` and `Story: P0-A` in the feature artifact. Do not launch `requirements-analyst`.
> Do not run `/v0-intake` or `/v0-design`. `/v0-build` copies this story and AC-1 through AC-4 into `docs/agents-v0/requirements/p0-a-platform-skeleton.md`, writes `design.md` (`N/A: no /api/v1 operation`, `ADR: N/A: no product decision`), and pins it. One approval, at Release, after the test report exists and `glab mr create` has returned a URL. That approval writes the Intake, Design, Build, Verify, and Release rows. Optional `/v0-local-release` may write the first four rows and Decision `Local` first; Release then writes only the Release row.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| milestone | docs/agents-v0/milestones/p0-platform-skeleton.md, story artifacts | | | |

> Go/no-go: `ci/check-approvals.sh docs/agents-v0/milestones/p0-platform-skeleton.md milestone`
> and `ci/check-milestone.sh docs/agents-v0/milestones/p0-platform-skeleton.md verify`.
