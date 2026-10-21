# Agentic Delivery Workflow (agents-v0)

Local-first, IDE-portable delivery kit (**Cursor**, **Claude Code**, **Antigravity**, **Windsurf**, **VS Code Copilot**). Always-on instructions live in `AGENTS.md` and `.cursor/rules/` after `scripts/install.sh`.

## Mission

Build and maintain enterprise-grade systems — one backend pack the program names, plus the UI pack when the manifest records one — through a human-gated delivery lifecycle backed by **phase skills (`SKILL.md`), structured JSON state (`state.json`), and native stack verification (`pack.json`)**. Example packs live under `core/` (`java`, `dotnet`, `node`, `python`, `go`, and `ui/react`). The bundled skeleton is the `java` example. A project pack is any id with a complete pack (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, and a UI manifest when `ui` names an id).

## Lifecycle and gates

| Phase | Command | Lead agent | Skills | Handoff & State |
|-------|---------|-----------|--------|-----------------|
| Onboard (brownfield) | `/v0-onboard` | codebase-documenter | onboard-discovery | `docs/agents-v0/onboarding/report.md`, `docs/agents-v0/onboarding/state.json`, profile, as-is architecture/network |
| Roadmap (greenfield program) | `/v0-roadmap` | program-planner | program-roadmap | `docs/agents-v0/roadmap/<program>.md`, `docs/agents-v0/program.state.json` |
| Architecture (before backlog) | `/v0-architecture` | solution-architect | program-architecture | `docs/agents-v0/architecture.md`, `docs/agents-v0/design/system/arc-record.md` |
| Plan (program, more than one story) | `/v0-plan` | program-planner | program-planning | `docs/agents-v0/milestones/plan.md`, `docs/agents-v0/milestones/<milestone>.md` |
| Intake | `/v0-intake` | requirements-analyst | spec-intake | `docs/agents-v0/requirements/<feature>.md`, `<feature>.state.json` (Gherkin AC IDs with `Kind`, NFRs) |
| Design | `/v0-design` | solution-architect, ux-designer | contract-first-design, ux-design | `docs/agents-v0/design/<feature>/` (contracts, ADR, diagrams, UX spec, mockups, `review.md`); ARC record when `Material: yes` |
| Build | `/v0-build` | backend/bff/frontend-engineer | implement-* | Code + tests; `docs/agents-v0/build/<feature>/plan.md` & `build-report.md` |
| Verify | `/v0-verify` | test-engineer, then security-reviewer and code-reviewer together | quality-gate, vapt-review, pr-review | `docs/agents-v0/verify/<feature>/` (`quality-gate.md`, `vapt-checklist.md`, `code-review.md`) + `verifyPassed` in `<feature>.state.json` |
| Local release (primary) | `/v0-local-release` | release-manager | local-release | Native stack verify + user-authorized local branch merge (`git merge --no-ff`) + `release` in `<feature>.state.json` |
| Remote release (optional) | `/v0-release` | release-manager | release-pr | Merge request ready (GitLab); completion after human-authorized merge |
| Maintain | `/v0-maintain` | maintenance-engineer | bugfix-triage, dependency-upgrade, doc-sync, characterization-tests, migration-safety | `docs/agents-v0/maintain/<id>/note.md` & `state.json`; routes to Verify |
| Trivial fixes | `/v0-triage` | maintenance-engineer | doc-sync, dependency-upgrade | User-confirmed doc/version fix (`tier: "trivial"`); abbreviated Verify |
| Deliver (one story) | `/v0-deliver` | orchestrator | — | Follows each phase command and stops at every gate that applies. P0-A starts at Build and stops once, at Release |
| Export (on request) | `/v0-export` | — | jira-export | `docs/agents-v0/backlog/tickets.csv` (documentation only, approves nothing) |
| Briefing (on request) | `/v0-deck` | — | leadership-deck | `docs/agents-v0/presentations/<name>.md` (documentation only, approves nothing) |
| Resume | `/v0-status` | orchestrator | — | Next phase from `<feature>.state.json` + on-disk evidence |

## Non-negotiable conduct

- Reconnaissance → Plan → Execute → Verify → Report in every phase.
- A phase is not complete until its gate passes; stop (`--status awaiting_approval`) and wait for explicit user approval before advancing. Never infer approval.
- Record workflow state and approvals via `.agents-v0/scripts/sync-feature-state.sh` (`<feature>.state.json`, `maintain/<id>/state.json`, `onboarding/state.json`, `program.state.json`).
- Commits, local merges, pushes, and merge-request creation each need explicit human authorization.
- Smallest correct diff; no drive-by refactors; no unsolicited files.
- Build & Verify gate: the profile Backend verify command (`.agents-v0/scripts/run-backend-verify.sh`, e.g. `./mvnw -B clean verify -Pci-security` or `dotnet test`) and Frontend verify command pass.
- No secrets in code, logs, or client bundles; sanitize log values; never dump environment variables.

## Rule precedence

If project files contradict a rule, **the repository wins**. Kit org rules live in `core/common/rules/*.mdc` plus the selected pack under `core/<pack>/rules/` (installed to `.cursor/rules/org/`). Document approved per-repo exceptions in `docs/agents-v0/project-profile.md` and ADRs; port deliberate kit-wide changes back into this repository.

## Reference

- `templates/docs/agents-v0/agents-v0-kit.md` — full architecture, state file schema, and workflow reference.
- `templates/docs/agents-v0/model-routing-matrix.md` — model IDs for each role (Plan, Build, Review, Explore, Debug, Schemas, Docs, Documenter, Orchestrator, UX Designer). Build (critical) uses the Plan model.
- `templates/docs/agents-v0/user-guide.md` — plain-language guide for non-engineering users.
- `templates/docs/agents-v0/greenfield-onboarding.md` / `brownfield-onboarding.md` — checklists; `bootstrap-greenfield.sh --scaffold-app`, `audit-brownfield-baseline.sh`.
- `templates/docs/agents-v0/snippets/` — Design fill-ins (OpenAPI CRUD, sync-vs-async ADR, one-screen UX).
