# Agentic Delivery Workflow Kit (agents-v0)

A **vendor-neutral** agentic delivery kit for **Cursor AI**, **Kilo Code**, and **Claude Code**. One vendor-neutral core (`core/`), three per-tool adapters installed by `scripts/install.sh`, one shared set of gates, approvals, evidence contracts, and CI checks.

The kit helps agents build and maintain enterprise-grade systems — Spring Boot services, BFFs, SvelteKit/React frontends — through a gated lifecycle: **Intake → Design → Build → Verify → Release**, with **Maintain** feeding back into Verify. Every gate stops for explicit user approval; approval is never inferred; evidence is persisted and checked by CI at merge. The default host is on-prem GitLab (`.gitlab-ci.yml`, `glab mr create`). GitHub Actions and `gh` remain the other supported host.

A feature’s progress is `docs/requirements/<feature>.state.json` (`scripts/sync-feature-state.sh`). `lastApprovedPhase` comes only from an `Approved` row. `activePhase` plus `activeStatus` (`in_progress`, `awaiting_approval`, or `blocked`) is the phase in flight. `/status <feature>` reads that file: `in_progress` or `blocked` runs the same phase again from files already on disk; `awaiting_approval` waits and does not start the next phase. The user names the feature. The newest state file is not assumed to be the one they mean.

Different features may proceed in one checkout only while each writes its own `docs/requirements/<feature>.md`, state file, and `docs/design/<feature>/`. Build, verify, release, and maintain stop when `git status` shows another feature’s code or a shared-file edit that is not this feature’s approved diff. Shared files include `docs/project-profile.md`, `openapi/api-v1.yaml`, `docs/architecture.md`, `docs/network.md`, `README.md`, and build or CI files. Ordinary feature work does not rewrite `docs/project-profile.md`. Creating a branch needs explicit user authorization.

## Layout


| Path                 | Purpose                                                                                                                                                                                                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md`          | Always-on instructions (loaded natively by Kilo Code; seeded as `CLAUDE.md` for Claude Code; Cursor gets the full rules via `.cursor/rules/`)                                                                                                                                           |
| `core/rules/*.mdc`   | Org delivery rules (+ `ux-design`) — single source of truth; installed per tool adapter                                                                                                                                                                                                 |
| `core/agents/*.md`   | 15 subagents (phase leads + explore/debug/schema/docs helpers) with tri-platform `model:` frontmatter                                                                                                                                                                                   |
| `core/commands/*.md` | 10 entry points (`/intake` … `/deliver`, `/onboard`, `/status`, `/triage`) with `description` frontmatter                                                                                                                                                                               |
| `core/skills/`       | 18 playbooks in the standard `SKILL.md` format (identical for all three tools)                                                                                                                                                                                                          |
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

Milestone programs (P0 Platform Skeleton, P1 Contracts & Data Models, P2 MVP/Core Features, P3 Features 1..N, P4 Hardening, P5 Release Readiness) are manifest-driven: `docs/milestones/<milestone>.md` groups user stories → feature chains, each story running the standard gated chain with approvals in its own artifact. Story artifacts record `Milestone:` / `Story:` traceability links (`spec-intake` skill). The milestone go/no-go is a `milestone` row in the manifest's canonical `Delivery approvals` table, verified at merge by `ci/check-approvals.sh` (milestone row) + `ci/check-milestone.sh` (every story's approvals + evidence). Template: `templates/docs/milestones/_template.md`.

## Validate the kit

```bash
./scripts/validate-kit.sh                       # validate the kit itself (no arguments)
./scripts/validate-kit.sh --target /path/to/target   # also validate an installed target
```

Kit checks: rule frontmatter, cross-references, all seven commands, tri-platform agent model fields against the routing matrix, adapter configs, `AGENTS.md`, required template artifacts, docs↔templates parity, hook classifications, evidence contracts (Build/Verify), and shell syntax. Target checks: adapter trees per installed tool, entry files (`README.md`, `AGENTS.md`, `CLAUDE.md`), CI scripts and exec bits, seeded docs, the merge-request and pull-request template evidence contract, and the `!docs/build/` ignore negations. Unexpected arguments are rejected with a usage error; a nonexistent `--target` fails immediately. Model availability in each tool is not verified.

On a target GitLab project, scope `GITLAB_TOKEN` (`read_api`, masked) to the `delivery-approval` environment, replace `@your-team` in `CODEOWNERS`, and set `ENABLE_GITLAB_SAST=1` only when that GitLab provides the SAST template. See [docs/greenfield-onboarding.md](docs/greenfield-onboarding.md).

## Compliance

See `docs/compliance-matrix.md` — every rule clause mapped to the enforcing agent, skill, hook, gate, or CI check. Hook rows apply to Cursor and Claude Code; Kilo Code enforces the same contract via `kilo.json` permissions and CI.