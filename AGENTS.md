# Agentic Delivery Workflow (agents-v0)

Delivery kit for **Cursor**. Always-on instructions live in `.cursor/rules/` after `scripts/install.sh`; this file summarizes the lifecycle for the kit repository and optional reference in target repos.

## Mission

Build and maintain enterprise-grade systems — Spring Boot services, BFFs, and SvelteKit/React frontends — through a gated delivery lifecycle with recorded human approvals.

## Lifecycle and gates

| Phase | Command | Lead agent | Skills | Handoff artifact |
|-------|---------|-----------|--------|------------------|
| Onboard (brownfield) | `/onboard` | codebase-documenter | onboard-discovery | `docs/onboarding/report.md` (`onboard` row), profile, as-is architecture/network |
| Plan (program, more than one story) | `/plan` | program-planner | system-design, program-planning | `docs/design/system/context-map.md`, `docs/milestones/<milestone>.md` (`plan` row in `Delivery approvals`) |
| Intake | `/intake` | requirements-analyst | spec-intake | `docs/requirements/<feature>.md` (AC IDs, NFRs, regulations, `Delivery approvals`) |
| Design | `/design` | solution-architect, ux-designer | contract-first-design, ux-design | Contracts, ADR, diagrams, `docs/design/<feature>/ux-spec.md`, `docs/design/<feature>/mockups/` |
| Build | `/build` | backend/bff/frontend-engineer | implement-* | Code + tests; `docs/build/<feature>/` with `commit:` in reports |
| Verify | `/verify` | test-engineer → security-reviewer → code-reviewer | quality-gate, vapt-review, pr-review | `docs/verify/<feature>/` reports with `commit:` |
| Release | `/release` | release-manager | release-pr | Merge request ready (GitLab); completion after human-authorized merge |
| Maintain | `/maintain` | maintenance-engineer | bugfix-triage, dependency-upgrade, doc-sync, characterization-tests, migration-safety | `docs/maintain/<id>/note.md` (own approvals, tier); routes to Verify |
| Trivial fixes | `/triage` | maintenance-engineer | bugfix-triage | Classifier-qualified, person-confirmed; abbreviated Verify |
| Resume | `/status` | orchestrator | — | Next phase from approvals + on-disk evidence |

## Non-negotiable conduct

- Reconnaissance → Plan → Execute → Verify → Report in every phase.
- A phase is not complete until its gate passes; stop and wait for explicit user approval before advancing. Never infer approval.
- Approval decisions go in the existing handoff artifact's `Delivery approvals` table (canonical 5-column format: Phase, Artifacts, Approver, Decision, Date).
- Merge-request readiness is intermediate: completion is a human-authorized merge with CI green. On GitLab, after the merge request is approved, run the manual `delivery-approval` job (`GITLAB_TOKEN` is `read_api`, masked, and scoped to that job's environment). Commits, pushes, and merge-request creation each need their own authorization.
- Smallest correct diff; no drive-by refactors; no unsolicited files.
- Build gate: code compiles; `mvn clean verify` or the frontend build passes.
- No secrets in code, logs, or client bundles; sanitize log values; never dump environment variables.

## Rule precedence

If project files contradict a rule, **the repository wins**. Kit org rules are the single source of truth in `core/rules/*.mdc` (installed to `.cursor/rules/org/`). Document approved per-repo exceptions in `docs/project-profile.md` and ADRs; port deliberate kit-wide changes back into this repository.

## Reference

- `docs/compliance-matrix.md` — every rule clause mapped to the enforcing agent/skill/hook/gate/CI check.
- `docs/model-routing-matrix.md` — Cursor model IDs for each role (Plan / Build / Review / Debug / Docs).
- `docs/user-guide.md` — plain-language guide for non-engineering users.
- `docs/greenfield-onboarding.md` / `docs/brownfield-onboarding.md` — engineer checklists; `scripts/bootstrap-greenfield.sh`, `scripts/audit-brownfield-baseline.sh`.