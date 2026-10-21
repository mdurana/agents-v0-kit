# Agentic Delivery Workflow (agents-v0)

Delivery kit for **Cursor**. Always-on instructions live in `.cursor/rules/` after `scripts/install.sh`; this file summarizes the lifecycle for the kit repository and is not installed into target repos.

## Mission

Build and maintain enterprise-grade systems — one backend pack the program names, plus the UI pack when the manifest records one — through a gated delivery lifecycle with recorded human approvals. Example packs live under `core/` (`java`, `dotnet`, `node`, `python`, `go`, and `ui/react`). The bundled skeleton is the `java` example. A project pack is any id with a complete pack (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, and a UI manifest when `ui` names an id).

## Lifecycle and gates

| Phase | Command | Lead agent | Skills | Handoff artifact |
|-------|---------|-----------|--------|------------------|
| Onboard (brownfield) | `/v0-onboard` | codebase-documenter | onboard-discovery | `docs/agents-v0/onboarding/report.md` (`onboard` row), profile, as-is architecture/network |
| Roadmap (greenfield program) | `/v0-roadmap` | program-planner | program-roadmap | `docs/agents-v0/roadmap/<program>.md` (`roadmap` row, `Discovery:` path) |
| Architecture (before backlog) | `/v0-architecture` | solution-architect | program-architecture | `docs/agents-v0/architecture.md` (`architecture` row, names the ARC file) |
| Plan (program, more than one story) | `/v0-plan` | program-planner | program-planning | `docs/agents-v0/milestones/plan.md` (milestone table and story flowchart); `docs/agents-v0/milestones/<milestone>.md` (`plan` row; Surface and Size on each story) |
| Intake | `/v0-intake` | requirements-analyst | spec-intake | `docs/agents-v0/requirements/<feature>.md` (Gherkin AC IDs with `Kind`, NFRs, `Delivery approvals`) |
| Design | `/v0-design` | solution-architect, ux-designer | contract-first-design, ux-design | Contracts, ADR, diagrams, UX spec, mockups; ARC record when `Material: yes` |
| Build | `/v0-build` | backend/bff/frontend-engineer | implement-* | Code + tests; `docs/agents-v0/build/<feature>/` with `commit:` in reports |
| Verify | `/v0-verify` | test-engineer, then security-reviewer and code-reviewer together | quality-gate, vapt-review, pr-review | `docs/agents-v0/verify/<feature>/` reports with `commit:` |
| Local release | `/v0-local-release` | release-manager | local-release | Optional after Verify |
| Release | `/v0-release` | release-manager | release-pr | Merge request ready (GitLab); completion after human-authorized merge |
| Maintain | `/v0-maintain` | maintenance-engineer | bugfix-triage, dependency-upgrade, doc-sync, characterization-tests, migration-safety | `docs/agents-v0/maintain/<id>/note.md` (own approvals, tier); routes to Verify |
| Trivial fixes | `/v0-triage` | maintenance-engineer | bugfix-triage | Classifier-qualified, person-confirmed; abbreviated Verify |
| Deliver (one story) | `/v0-deliver` | orchestrator | — | Follows each phase command and stops at every gate that applies. P0-A starts at Build and stops once, at Release. The feature's state file |
| Export (on request) | `/v0-export` | — | jira-export | `docs/agents-v0/backlog/tickets.csv` (documentation only, approves nothing) |
| Briefing (on request) | `/v0-deck` | — | leadership-deck | `docs/agents-v0/presentations/<name>.md` (documentation only, approves nothing) |
| Resume | `/v0-status` | orchestrator | — | Next phase from approvals + on-disk evidence |

## Non-negotiable conduct

- Reconnaissance → Plan → Execute → Verify → Report in every phase.
- A phase is not complete until its gate passes; stop and wait for explicit user approval before advancing. Never infer approval.
- Approval decisions go in the existing handoff artifact's `Delivery approvals` table (canonical 5-column format: Phase, Artifacts, Approver, Decision, Date).
- Merge-request readiness is intermediate: completion is a human-authorized merge with CI green. On GitLab, after the merge request is approved, run the manual `delivery-approval` job. Commits, pushes, and merge-request creation each need their own authorization.
- Smallest correct diff; no drive-by refactors; no unsolicited files.
- Build gate: the profile Backend verify command passes (Pack `java`: `./mvnw -B clean verify -Pci-security` from the backend root), or the frontend verify command.
- No secrets in code, logs, or client bundles; sanitize log values; never dump environment variables.

## Rule precedence

If project files contradict a rule, **the repository wins**. Kit org rules live in `core/common/rules/*.mdc` plus the selected pack under `core/<pack>/rules/` (installed to `.cursor/rules/org/`). Document approved per-repo exceptions in `docs/agents-v0/project-profile.md` and ADRs; port deliberate kit-wide changes back into this repository.

## Cursor Cloud specific instructions

The default image already provides JDK 21, Node 22 (npm on the login-shell PATH), Python 3, PyYAML, git, and ripgrep. `install` adds shellcheck and Ubuntu PostgreSQL 16, runs `npm ci` in `templates/app/frontend`, and packages the API with `templates/app/backend/mvnw -B -DskipTests package`. `start` brings up PostgreSQL, the API jar on port 8080, and Vite on port 5173. The local database is user `app`, password `app`, database `app` on `127.0.0.1:5432` (the compose file still names `postgres:15`; this image's server is 16, and the baseline migration applies on it).

- Kit check: `sh scripts/validate-kit.sh` (the command in `.gitlab-ci.yml`). It runs shellcheck when that binary is present and `scripts/test-app-template.sh`.
- `/bin/sh` is dash. `templates/.gitlab-ci.yml` uses `set -o pipefail`, and `scripts/test-ci-checks.sh` executes that build script with `sh`, so that one assertion fails here. The same script exits 0 under bash and writes `ci-artifacts/gate/services/orders/`.
- API: `curl -s http://127.0.0.1:8080/health` (`/ready` and `/live` too). UI: `http://127.0.0.1:5173/` shows "Platform skeleton is running."
- Frontend, from `templates/app/frontend`: `npm test` and `npm run build`.
- `./mvnw -B clean verify -Pci-security` calls the NVD API. Set `NVD_API_KEY` before relying on that profile.

## Reference

- `templates/docs/agents-v0/model-routing-matrix.md` — Cursor model IDs for each role (Plan, Build, Review, Explore, Debug, Schemas, Docs, Documenter, Orchestrator, UX Designer). Build (critical) uses the Plan model.
- `templates/docs/agents-v0/user-guide.md` — plain-language guide for non-engineering users.
- `templates/docs/agents-v0/greenfield-onboarding.md` / `brownfield-onboarding.md` — checklists; `bootstrap-greenfield.sh --scaffold-app`, `audit-brownfield-baseline.sh`.
- `templates/docs/agents-v0/snippets/` — Design fill-ins (OpenAPI CRUD, sync-vs-async ADR, one-screen UX).