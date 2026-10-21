# Milestone: <P0/P1/P2...> — <name>

> Program manifest for a delivery milestone — e.g. P0 Platform Skeleton, P1 Contracts
> & Data Models, P2 MVP/Core Features, P3 Other Features 1..N, P4 Hardening, P5
> Release Readiness. Each user story runs the standard gated chain (Intake → Design
> → Build → Verify → Release) with approvals recorded in its own feature artifact;
> this manifest groups the stories, orders them, and records the milestone go/no-go.
> (`workflow-orchestration.mdc`)

## Goal

<one paragraph: what this milestone delivers and its definition of done>

## Scope

- In: <...>
- Out: <...>

## Dependencies

<ordering, e.g. "P1 depends on the P0 skeleton merged; story P2-B depends on P2-A's contracts">

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| <P2-A> | As a [role], I want [goal], so that [benefit]. | docs/agents-v0/requirements/<feature>.md | planned | — | — | — |

> Conventions:
> - The User story cell is one sentence: `As a [role], I want [goal], so that [benefit].`
>   Replace every `<...>` in that cell before `/v0-intake`. Intake copies the sentence into
>   the feature artifact and splits the goal and each constraint into `AC-1`, `AC-2`, …
>   one Gherkin scenario each, with `Kind` and an observable `Then` (`spec-intake` skill). One scenario
>   is a negative or an edge, unless `Negatives: N/A` applies. That scenario counts toward the cap of 8.
>   Out of scope stays a separate list. Intake does not invent a role, goal, or benefit.
> - Surface is `backend`, `bff`, `frontend`, or `vertical slice`. Size is the number of
>   acceptance criteria, at most 8, including that negative or edge. `/v0-plan` fills both.
>   Seeded P0-A stays at 4.
> - Each linked feature artifact records `Milestone: <Pn-name>`,
>   `Milestone file: docs/agents-v0/milestones/<this-file>.md`, and `Story: <story-id>`
>   under its title (`spec-intake` skill) for traceability.
> - Status is prose (planned / in-flight / done); progress and approvals are tracked in each
>   story's `docs/agents-v0/requirements/<feature>.state.json` (`sync-feature-state.sh`).
> - Dependency lists concrete story IDs across the program, comma-separated (`P1-B, P2-A`). A
>   story starts Build only after each story it names has `verify` in `approvedPhases`
>   (`verifyPassed: true`). Bare milestone labels (`P1`) are not valid story dependencies; use `—` when a
>   story has no dependency. `/v0-plan` writes these rows (`program-planning` skill).
> - Rows with placeholder paths (`<...>`) or no path are skipped — a milestone go/no-go
>   passes only when every story row has a concrete, approved artifact.
> - Hardening/readiness milestones: run `/v0-verify` once more with this manifest's linked
>   changes as the integrated scope before the milestone approval.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/plan.md, <this manifest, docs/agents-v0/design/system/context-map.md> | <name> | Approved | <date> |
| milestone | <this manifest, story artifacts> | <name> | Approved | <date> |

> The `plan` row is the `/v0-plan` approval (also recorded in `docs/agents-v0/program.state.json`).
> The `milestone` row is the go/no-go decision after all story artifacts have completed Verify.