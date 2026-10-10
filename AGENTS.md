# Agentic Delivery Workflow (agents-v0)

Delivery kit for **Cursor**. Always-on instructions live in `.cursor/rules/` after `scripts/install.sh`; this file summarizes the lifecycle for the kit repository and optional reference in target repos.

## Mission

Build and maintain enterprise-grade systems — Spring Boot services, BFFs, and SvelteKit/React frontends — through a gated delivery lifecycle with recorded human approvals.

## Lifecycle and gates

| Phase | Command | Lead agent | Skills | Handoff artifact |
|-------|---------|-----------|--------|------------------|
| Onboard (brownfield) | `/v0-onboard` | codebase-documenter | onboard-discovery | `docs/agents-v0/onboarding/report.md` (`onboard` row), profile, as-is architecture/network |
| Roadmap (greenfield program) | `/v0-roadmap` | program-planner | program-roadmap | `docs/agents-v0/roadmap/<program>.md` (`roadmap` row, `Discovery:` path) |
| Architecture (before backlog) | `/v0-architecture` | solution-architect | program-architecture | `docs/agents-v0/architecture.md` (`architecture` row, names the ARC file) |
| Plan (program, more than one story) | `/v0-plan` | program-planner | program-planning | `docs/agents-v0/milestones/<milestone>.md` (`plan` row; Surface and Size on each story) |
| Intake | `/v0-intake` | requirements-analyst | spec-intake | `docs/agents-v0/requirements/<feature>.md` (Gherkin AC IDs with `Kind`, NFRs, `Delivery approvals`) |
| Design | `/v0-design` | solution-architect, ux-designer | contract-first-design, ux-design | Contracts, ADR, diagrams, UX spec, mockups; ARC record when `Material: yes` |
| Build | `/v0-build` | backend/bff/frontend-engineer | implement-* | Code + tests; `docs/agents-v0/build/<feature>/` with `commit:` in reports |
| Verify | `/v0-verify` | test-engineer → security-reviewer → code-reviewer | quality-gate, vapt-review, pr-review | `docs/agents-v0/verify/<feature>/` reports with `commit:` |
| Local release | `/v0-local-release` | release-manager | local-release | Optional after Verify |
| Release | `/v0-release` | release-manager | release-pr | Merge request ready (GitLab); completion after human-authorized merge |
| Maintain | `/v0-maintain` | maintenance-engineer | bugfix-triage, dependency-upgrade, doc-sync, characterization-tests, migration-safety | `docs/agents-v0/maintain/<id>/note.md` (own approvals, tier); routes to Verify |
| Trivial fixes | `/v0-triage` | maintenance-engineer | bugfix-triage | Classifier-qualified, person-confirmed; abbreviated Verify |
| Resume | `/v0-status` | orchestrator | — | Next phase from approvals + on-disk evidence |

## Non-negotiable conduct

- Reconnaissance → Plan → Execute → Verify → Report in every phase.
- A phase is not complete until its gate passes; stop and wait for explicit user approval before advancing. Never infer approval.
- Approval decisions go in the existing handoff artifact's `Delivery approvals` table (canonical 5-column format: Phase, Artifacts, Approver, Decision, Date).
- Merge-request readiness is intermediate: completion is a human-authorized merge with CI green. On GitLab, after the merge request is approved, run the manual `delivery-approval` job. Commits, pushes, and merge-request creation each need their own authorization.
- Smallest correct diff; no drive-by refactors; no unsolicited files.
- Build gate: code compiles; `mvn clean verify` or the frontend build passes.
- No secrets in code, logs, or client bundles; sanitize log values; never dump environment variables.

## Rule precedence

If project files contradict a rule, **the repository wins**. Kit org rules are the single source of truth in `core/rules/*.mdc` (installed to `.cursor/rules/org/`). Document approved per-repo exceptions in `docs/agents-v0/project-profile.md` and ADRs; port deliberate kit-wide changes back into this repository.

## Reference

- `templates/docs/agents-v0/compliance-matrix.md` — every rule clause mapped to the enforcing agent/skill/hook/gate/CI check. Installed repos copy this to `docs/agents-v0/compliance-matrix.md`.
- `templates/docs/agents-v0/model-routing-matrix.md` — Cursor model IDs for each role (Plan, Build, Review, Explore, Debug, Schemas, Docs, Documenter, Orchestrator, UX Designer). Build (critical) uses the Plan model.
- `templates/docs/agents-v0/user-guide.md` — plain-language guide for non-engineering users.
- `templates/docs/agents-v0/greenfield-onboarding.md` / `templates/docs/agents-v0/brownfield-onboarding.md` — engineer checklists; `scripts/bootstrap-greenfield.sh`, `scripts/audit-brownfield-baseline.sh`.