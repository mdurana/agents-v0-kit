# Agentic Delivery Workflow (agents-v0)

Vendor-neutral delivery kit for **Cursor**, **Kilo Code**, and **Claude Code**. This file is the always-on instruction layer; the full rules, agents, commands, and skills are installed per tool by `scripts/install.sh`.

## Mission

Build and maintain enterprise-grade systems — Spring Boot services, BFFs, and SvelteKit/React frontends — through a gated delivery lifecycle with recorded human approvals.

## Lifecycle and gates

| Phase | Command | Lead agent | Skills | Handoff artifact |
|-------|---------|-----------|--------|------------------|
| Onboard (brownfield) | `/onboard` | orchestrator | — | `docs/project-profile.md`, as-is architecture/network |
| Intake | `/intake` | requirements-analyst | spec-intake | `docs/requirements/<feature>.md` (AC IDs, NFRs, regulations, `Delivery approvals`) |
| Design | `/design` | solution-architect, ux-designer | contract-first-design, ux-design | Contracts, ADR, diagrams, `docs/design/<feature>/ux-spec.md`, `docs/design/<feature>/mockups/` |
| Build | `/build` | backend/bff/frontend-engineer | implement-* | Code + tests; `docs/build/<feature>/` with `commit:` in reports |
| Verify | `/verify` | test-engineer → security-reviewer → code-reviewer | quality-gate, vapt-review, pr-review | `docs/verify/<feature>/` reports with `commit:` |
| Release | `/release` | release-manager | release-pr | Merge request ready (GitLab); completion after human-authorized merge |
| Maintain | `/maintain` | maintenance-engineer | bugfix-triage, dependency-upgrade, doc-sync, characterization-tests, migration-safety | Fix/upgrade; routes back to Verify |
| Trivial fixes | `/triage` | maintenance-engineer | bugfix-triage | Abbreviated maintain path; record `tier: trivial` |
| Resume | `/status` | orchestrator | — | Next phase from approvals + on-disk evidence |

## Non-negotiable conduct

- Reconnaissance → Plan → Execute → Verify → Report in every phase.
- A phase is not complete until its gate passes; stop and wait for explicit user approval before advancing. Never infer approval.
- Approval decisions go in the existing handoff artifact's `Delivery approvals` table (canonical 5-column format: Phase, Artifacts, Approver, Decision, Date).
- Merge-request readiness is intermediate: completion is a human-authorized merge with CI green. On GitLab, after the merge request is approved, run the manual `delivery-approval` job (`GITLAB_TOKEN` is `read_api`, masked, and scoped to that job's environment). Commits, pushes, and merge-request creation each need their own authorization. GitHub uses a pull request and `gh` instead of `glab`.
- Smallest correct diff; no drive-by refactors; no unsolicited files.
- Build gate: code compiles; `mvn clean verify` or the frontend build passes.
- No secrets in code, logs, or client bundles; sanitize log values; never dump environment variables.

## Rule precedence

If project files contradict a rule, **the repository wins**. Kit org rules are the single source of truth in `core/rules/*.mdc` (installed to `.cursor/rules/org/`, `.kilo/rules/`, `.claude/rules/`). Document approved per-repo exceptions in `docs/project-profile.md` and ADRs; port deliberate kit-wide changes back into this repository.

## Reference

- `docs/compliance-matrix.md` — every rule clause mapped to the enforcing agent/skill/hook/gate/CI check.
- `docs/model-routing-matrix.md` — per-tool model IDs for each role (Plan / Build / Review / Debug / Docs).
- `docs/user-guide.md` — plain-language guide for non-engineering users.
- `docs/greenfield-onboarding.md` / `docs/brownfield-onboarding.md` — engineer checklists; `scripts/bootstrap-greenfield.sh`, `scripts/audit-brownfield-baseline.sh`.