# Agentic Delivery Workflow Kit (agents-v0)

A **vendor-neutral** agentic delivery kit for **Cursor AI**, **Kilo Code**, and **Claude Code**. One vendor-neutral core (`core/`), three per-tool adapters installed by `scripts/install.sh`, one shared set of gates, approvals, evidence contracts, and CI checks.

The kit helps agents build and maintain enterprise-grade systems — Spring Boot services, BFFs, SvelteKit/React frontends — through a gated lifecycle: **Intake → Design → Build → Verify → Release**, with **Maintain** feeding back into Verify. Every gate stops for explicit user approval; approval is never inferred; evidence is persisted and checked by CI at merge. The default host is on-prem GitLab (`.gitlab-ci.yml`, `glab mr create`). GitHub Actions and `gh` remain the other supported host.

A feature’s progress is `docs/requirements/<feature>.state.json` (`scripts/sync-feature-state.sh`). `lastApprovedPhase` comes only from an `Approved` row. `activePhase` plus `activeStatus` (`in_progress`, `awaiting_approval`, or `blocked`) is the phase in flight. `/status <feature>` reads that file: `in_progress` or `blocked` runs the same phase again from files already on disk; `awaiting_approval` waits and does not start the next phase. The user names the feature. The newest state file is not assumed to be the one they mean.

Different features may proceed in one checkout only while each writes its own `docs/requirements/<feature>.md`, state file, and `docs/design/<feature>/`. Design writes the feature contract draft at `docs/design/<feature>/openapi.yaml`. Build merges that approved draft into the org catalog (`openapi/api-v1.yaml` unless the profile names another file). Build, verify, release, and maintain stop when `git status` shows another feature’s code or a shared-file edit that is not this feature’s approved diff. Shared files include `docs/project-profile.md`, the org catalog, `docs/architecture.md`, `docs/network.md`, `README.md`, and build or CI files. The feature draft is not a shared file. Ordinary feature work does not rewrite `docs/project-profile.md`. Creating a branch needs explicit user authorization.

## Layout


| Path                 | Purpose                                                                                                                                                                                                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md`          | Always-on instructions (loaded natively by Kilo Code; seeded as `CLAUDE.md` for Claude Code; Cursor gets the full rules via `.cursor/rules/`)                                                                                                                                           |
| `core/rules/*.mdc`   | Org delivery rules (+ `ux-design`) — single source of truth; installed per tool adapter                                                                                                                                                                                                 |
| `core/agents/*.md`   | 19 subagents (program planner, codebase documenter, design reviewer, phase leads + explore/debug/schema/docs helpers) with tri-platform `model:` frontmatter                                                                                                                                                                                   |
| `core/commands/*.md` | 11 entry points (`/plan`, `/intake` … `/deliver`, `/onboard`, `/status`, `/triage`) with `description` frontmatter                                                                                                                                                                               |
| `core/skills/`       | 23 playbooks in the standard `SKILL.md` format (identical for all three tools)                                                                                                                                                                                                          |
| `core/hooks/`        | Shared guardrails: `pre-shell.sh`, `pre-edit.sh`, `pre-mcp.sh`, `session-start.sh`, `after-edit.sh`, `stop.sh`, `hook-policy.py`, `mcp-policy.json` (per-server MCP allow/ask/block, seeded once)                                                                                       |
| `core/adapters/`     | Per-tool configs: `cursor/hooks.json`, `claude/settings.json`, `kilo/kilo.json`                                                                                                                                                                                                         |
| `docs/`              | `compliance-matrix.md`, `model-routing-matrix.md` (per-tool model columns), `user-guide.md`                                                                                                                                                                                             |
| `templates/`         | Project starters: GitLab CI (`.gitlab-ci.yml`) and merge request template (default host), GitHub workflow examples, docs, Maven quality snippets, OpenAPI, `docker-compose.yml` + `docker/` Dockerfile starters, `scripts/run-local-container.sh` (Podman/Docker Compose), ignore files |
| `scripts/`           | `install.sh`, `validate-kit.sh`, `bootstrap-greenfield.sh`, `audit-brownfield-baseline.sh`                                                                                                                                                                                              |




## What each tool gets


| Concern                          | Cursor                                   | Kilo Code                                                  | Claude Code                                                                     |
| -------------------------------- | ---------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Always-on rules                  | `.cursor/rules/*.mdc` (`alwaysApply`)    | `AGENTS.md` + `.kilo/rules/` via `instructions`            | `CLAUDE.md` + `@.claude/rules/` imports                                         |
| Phase commands                   | `.cursor/commands/`                      | `.kilo/command/`                                           | `.claude/commands/`                                                             |
| Subagents                        | `.cursor/agents/` (`model:`)             | `.kilo/agent/` (`mode: subagent`, `model: provider/model`) | `.claude/agents/` (`model: sonnet/sonnet/...`)                                    |
| Skills                           | `.cursor/skills/`                        | `.kilo/skills/`                                            | `.claude/skills/`                                                               |
| Git/secret guardrails            | `hooks.json` + `pre-shell.sh` (deny/ask) | `kilo.json` `permission.bash` (deny/ask patterns)          | `settings.json` PreToolUse + `pre-shell.sh` (deny/ask via `permissionDecision`) |
| Agent context ignores            | `.cursorignore`                          | `.kiloignore`                                              | `.claudeignore`                                                                 |
| Edit warnings / stop reminder    | `after-edit.sh` / `stop.sh` hooks        | CI checks + gate commands                                  | `PostToolUse` / `Stop` hooks                                                    |
| Session context / MCP guardrails | `session-start.sh`, `pre-mcp.sh`         | —                                                          | `SessionStart` / `mcp__*` PreToolUse                                            |




## Onboarding


| Scenario                       | Script / doc                                                                                                                                                                                               |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **New repo (greenfield)**      | Scaffold into `backend/`, `frontend/`, or `bff/` (no application `src/` at the repo root), then `./scripts/bootstrap-greenfield.sh --tool cursor --profile service` (or `ui`, or `app`) `/path/to/target-repo` — see [docs/greenfield-onboarding.md](docs/greenfield-onboarding.md) |
| **Existing repo (brownfield)** | `./scripts/install.sh` then `./scripts/audit-brownfield-baseline.sh /path/to/target-repo` — see [docs/brownfield-onboarding.md](docs/brownfield-onboarding.md)                                             |




## Install

```bash
# install for one tool or all three (default: all; minimal templates)
./scripts/install.sh --tool cursor /path/to/target-repo
# greenfield / full starters (maven, docker, openapi, …):
./scripts/install.sh --tool cursor --with-starters /path/to/target-repo
./scripts/install.sh --tool kilo /path/to/target-repo
./scripts/install.sh --tool claude /path/to/target-repo
./scripts/install.sh --tool all /path/to/target-repo

# after kit changes: sync docs -> templates/, validate, refresh kit-managed files
./scripts/install.sh --update /path/to/target-repo
```

Seeded only when missing (never clobbered): `README.md`, `AGENTS.md`, `CLAUDE.md`, `.kilo/kilo.json`, `.claude/settings.json`, and all project templates. Always refreshed on `--update`: rules, agents, commands, skills, hooks, adapter configs, reference docs, `ci/*.sh`.

## Model routing

The kit routes by **role** — Plan / Build / Review / Explore / Debug / Schemas / Docs — with one row per platform in `docs/model-routing-matrix.md`. Agent frontmatter carries all three IDs; adapters emit the tool's own. Provider-qualified Kilo IDs are examples: adapt them to your `kilo.json` providers.

## Milestone delivery

Milestone programs (P0 Platform Skeleton, P1 Contracts & Data Models, P2 MVP/Core Features, P3 Features 1..N, P4 Hardening, P5 Release Readiness) are manifest-driven: `docs/milestones/<milestone>.md` groups user stories → feature chains, each story running the standard gated chain with approvals in its own artifact. Story artifacts record `Milestone:` / `Story:` traceability links (`spec-intake` skill). The milestone go/no-go is a `milestone` row in the manifest's canonical `Delivery approvals` table, verified at merge by `ci/check-approvals.sh` (milestone row) + `ci/check-milestone.sh` (every story's approvals + evidence). A P4 manifest that names `docs/design/system/slo-evidence.md` also requires that file at `verify` and `release`: each filled SLO row is measured or waived. Template: `templates/docs/milestones/_template.md`.

## Complex programs

| Need | What the kit provides |
|------|-----------------------|
| Decompose a large goal | `/plan` (`program-planner`, `program-planning`): context map, milestone manifests, story graph. Approval is a `plan` row; `ci/check-milestone.sh` fails a story that starts Build before the stories it depends on have a Verify approval |
| Several services in one repo | `Service roots` in the profile Layout (or `services/*/` auto-detected), one catalog per service, CI builds and measures each root |
| Parallel features | `scripts/feature-worktree.sh <feature>`: one worktree and branch per feature (needs explicit authorization; hooks ask) |
| Numbers that are not self-reported | `ci/check-gate-metrics.sh` reads JaCoCo, Surefire, and OWASP output: executed tests, diff coverage on merge requests, unsuppressed HIGH/CRITICAL CVEs. `ci/check-event-schemas.sh` rejects non-additive event schema changes. Testcontainers, Playwright, and k6 jobs are in the CI templates |
| Fewer approval stops | Batch approval of Intake and Design for named, low-risk stories (`workflow-orchestration.mdc`) |
| Bounded effort | `Phase attempt budget` (default 8 failed attempts per phase) checked by `scripts/check-attempt-budget.sh` |
| Messaging, E2E, deploy | Skills `implement-messaging`, `e2e-perf-testing`, `release-deploy` (profile **Deploy** table) |
| Reviewer independence, critical units | Review role on a stronger model than Build; security-trigger and saga units run on the Plan-role model (`docs/model-routing-matrix.md`) |
| Document an existing codebase | `/onboard` (`codebase-documenter`, `onboard-discovery`): baseline numbers, layout-aware inventories in `docs/discovery/` (endpoints, entities, messaging, config key names, security baseline), cited module documents, as-is architecture and flows. `scripts/check-onboarding-docs.sh` rejects a citation that does not resolve. Approval is an `onboard` row in `docs/onboarding/report.md` that `/intake` and `/plan` wait for |
| Fixes, patches, upgrades, hotfixes | `/maintain` and `/triage` keep a maintenance note (`docs/maintain/<id>/note.md`) with its own tier, approvals, and evidence; the MR says `Maintain-Note:`. `ci/classify-change.sh` reads the diff to decide whether the Trivial lane applies (docs-only or version-only, no security surface, schema, or major bump) and a person confirms it. Trivial gets an abbreviated Verify; emergency may merge first and owes Verify by a due date. A feature artifact is no longer accepted for a code change that carries no build or verify evidence |
| Design you can verify, Build you can check | `/design` writes `design.md` (every AC traced, an authorization row per operation, data, failure modes, rollout) beside the contract draft; `ci/check-openapi.sh` lints it and tests it against the catalog, `design-reviewer` reviews it, and the approved design is pinned (`design.lock`). A later change needs an Approved amendment row. `/build` proves the catalog merge, a real plan (each done row names an existing test with a red card first), no new unannotated endpoint, and frontend calls that match the catalog. `maven/contract-conformance.xml` boots the service and diffs both ways |
| Release you can trust | `/deliver` is a thin chain over the phase commands (and `Re-opened` marks a phase sent back). `/release` dry-runs `ci/check-delivery-linkage.sh` locally, renders the MR description from the evidence (`scripts/render-mr-body.sh`), caps the CI fix loop at three rounds, records the approving GitLab username, and keeps deploy records off the default branch. `glab mr merge` and `glab mr approve` are blocked in the hooks (and `git tag`, `glab ci trigger`, and `glab mr create` ask). `scripts/release-notes.sh` builds the changelog and milestone notes from approved stories |
| Measure the kit | `docs/benchmark/reference-project.md` and `scripts/delivery-metrics.sh` (Delivery effort) |

## Validate the kit

```bash
./scripts/validate-kit.sh                       # validate the kit itself (no arguments)
./scripts/validate-kit.sh --target /path/to/target   # also validate an installed target
```

Kit checks: rule frontmatter, cross-references, all eleven commands, README counts, tri-platform agent model fields against the routing matrix, adapter configs, `AGENTS.md`, required template artifacts, docs↔templates parity, hook classifications, evidence contracts (Build/Verify), and shell syntax. Target checks: adapter trees per installed tool, entry files (`README.md`, `AGENTS.md`, `CLAUDE.md`), CI scripts and exec bits, seeded docs, the merge-request and pull-request template evidence contract, and the `!docs/build/` ignore negations. Unexpected arguments are rejected with a usage error; a nonexistent `--target` fails immediately. Model availability in each tool is not verified.

On a target GitLab project, scope `GITLAB_TOKEN` (`read_api`, masked) to the `delivery-approval` environment, replace `@your-team` in `CODEOWNERS`, and set `ENABLE_GITLAB_SAST=1` only when that GitLab provides the SAST template. See [docs/greenfield-onboarding.md](docs/greenfield-onboarding.md).

## Compliance

See `docs/compliance-matrix.md` — every rule clause mapped to the enforcing agent, skill, hook, gate, or CI check. Hook rows apply to Cursor and Claude Code; Kilo Code enforces the same contract via `kilo.json` permissions and CI.