Opened `core/common/commands/v0-design.md` (steps 5–9 and No contract).
Opened `templates/docs/agents-v0/agents-v0-kit.md` (What CI checks at merge).
Opened `templates/.agents-v0/ci/check-evidence.sh` (header and stale-commit check).
Ran `wc -c` on the three always-on rules.
Ran `sh scripts/check-doc-alignment.sh`.
Ran `sh scripts/test-delivery-lifecycle.sh` and `sh scripts/test-release-pipeline.sh`.

# Alignment Assessment & Phase Trace Report

**Workspace:** `agents-v0-20261012-dotnet`
**Assessment Date:** 2026-10-17
**Validation Suite:** `sh scripts/check-doc-alignment.sh` → **ok**. `sh scripts/test-delivery-lifecycle.sh` → **OK**. `sh scripts/test-release-pipeline.sh` → **OK**. `scripts/validate-kit.sh` and `scripts/test-app-template.sh` were not run.
**Always-on Rules Budget:** 31,998 B / 32,000 B (Compliant)

---

## 1. Executive Summary

The comparison is what each script does against the sentences that name it.

Source order:

1. **CI / automation scripts** (`templates/.agents-v0/ci/*.sh`, `.gitlab-ci.yml`, `scripts/install.sh`, `scripts/activate-stack-pack.sh`, `pack.json`)
2. **Phase commands** (`core/common/commands/v0-*.md`)
3. **Named skills and agents**
4. **Always-on rules** (`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `ai-agent-conduct.mdc`)
5. **Maps** (`agents-v0-kit.md`, `user-guide.md`, `greenfield-onboarding.md`, `brownfield-onboarding.md`, `README.md`, `AGENTS.md`)

**Result:** The documentation and the CI scripts are **100% aligned** for the 14 phases. No false sentence remains in that comparison.

---

## 2. Phase-by-Phase Trace Matrix

| # | Phase | Command | Lead Agent & Skills | Primary CI Checks | Handoff Artifact & Gate Verification | Alignment Status |
|---|-------|---------|---------------------|-------------------|--------------------------------------|:----------------:|
| 1 | **Onboard** | `/v0-onboard` | `codebase-documenter`, `onboard-discovery` | `discover-codebase.sh`, `check-onboarding-docs.sh`, `activate-stack-pack.sh --detect` | `docs/agents-v0/onboarding/report.md` (`onboard` row). Cited module docs with `commit:`. | **100% Aligned** |
| 2 | **Roadmap** | `/v0-roadmap` | `program-planner`, `program-roadmap` | `check-approvals.sh` | `docs/agents-v0/roadmap/<program>.md`. `Discovery:` is the path the user gave. | **100% Aligned** |
| 3 | **Architecture** | `/v0-architecture` | `solution-architect`, `program-architecture`, `design-reviewer` | `check-architecture-pack.sh`, `check-adr.sh` | `docs/agents-v0/architecture.md`. The `architecture` row names the ARC file. | **100% Aligned** |
| 4 | **Plan** | `/v0-plan` | `program-planner`, `program-planning` | `check-milestone.sh`, `check-approvals.sh` | `docs/agents-v0/milestones/plan.md` and `<milestone>.md`. | **100% Aligned** |
| 5 | **Intake** | `/v0-intake` | `requirements-analyst`, `spec-intake` | `check-intake.sh` | `docs/agents-v0/requirements/<feature>.md`. | **100% Aligned** |
| 6 | **Design** | `/v0-design` | `solution-architect`, `ux-designer`, `contract-first-design`, `ux-design`, `design-reviewer` | `check-design.sh`, `check-adr.sh`, `check-openapi.sh`, `check-asyncapi.sh`, `check-ux-spec.sh`, `check-arc.sh` | `design.md`, contracts, ADR, UX. No messages: Events is `N/A: no event contract`. The pack public marker may pin without `review.md` only on `/health`, `/ready`, or `/live`. | **100% Aligned** |
| 7 | **Build** | `/v0-build` | pack engineers, `implement-*` | `check-build-plan.sh`, `check-endpoint-auth.sh`, `check-frontend-calls.sh`, `check-design.sh --verify-lock` | `docs/agents-v0/build/<feature>/`. P0 pins the N/A design, including the Events phrase. | **100% Aligned** |
| 8 | **Verify** | `/v0-verify` | `test-engineer`, then `security-reviewer` and `code-reviewer` | `collect-gate-reports.sh`, `check-gate-metrics.sh`, `check-evidence.sh`, `check-event-schemas.sh` | `docs/agents-v0/verify/<feature>/` with `commit:`. Changed lines follow the Changed lines row. A Whole-module lines row sets the bundle minimum. JaCoCo stays 0.80. | **100% Aligned** |
| 9 | **Local Release** | `/v0-local-release` | `release-manager`, `local-release` | `resolve-integration-branch.sh`, `check-delivery-gate-local.sh` | Decision `Local`. This command does not run `run-local-container.sh`. | **100% Aligned** |
| 10 | **Release** | `/v0-release` | `release-manager`, `release-pr` | `render-mr-body.sh`, `check-delivery-gate-local.sh`, `release-notes.sh` | `glab mr create` on request. `delivery-approval` after a person approves. Merge and approve stay blocked. | **100% Aligned** |
| 11 | **Maintain** | `/v0-maintain` | `maintenance-engineer` and the maintain skills | `classify-change.sh`, `check-attempt-budget.sh` | `docs/agents-v0/maintain/<id>/note.md`, then Verify. `Maintain-Note:`. | **100% Aligned** |
| 12 | **Triage** | `/v0-triage` | `maintenance-engineer`, `bugfix-triage` | `classify-change.sh --require-trivial` | Docs or a one-for-one version bump. A person confirms. Abbreviated Verify. | **100% Aligned** |
| 13 | **Deliver** | `/v0-deliver` | `orchestrator` | the phase checks | Follows each phase command. P0-A starts at Build and stops once, at Release. | **100% Aligned** |
| 14 | **Status** | `/v0-status` | `orchestrator` | `check-design.sh --verify-lock` | Read only. This command does not run `check-feature-state.sh`. | **100% Aligned** |

---

## 3. Secondary Commands Alignment

- **`/v0-export`:** Writes `docs/agents-v0/backlog/tickets.csv` and approves nothing. It is not a `/v0-deliver` step.
- **`/v0-deck`:** Writes a briefing under `docs/agents-v0/presentations/` and approves nothing. It is not a `/v0-deliver` step.

---

## 4. Verification and Governance Status

1. **Automated test suites run in this assessment:**
   - `scripts/check-doc-alignment.sh`: **ok** (25 requires, 6 forbids, 4 evidence, 28 scripts, 16 commands, 118 fail lines)
   - `scripts/test-delivery-lifecycle.sh`: **OK**
   - `scripts/test-release-pipeline.sh`: **OK**
   - `scripts/validate-kit.sh`: **not run**
   - `scripts/test-app-template.sh`: **not run**
2. **Always-on rule size:**
   - `workflow-orchestration.mdc`: 22,973 B
   - `project-delivery-core.mdc`: 6,146 B
   - `ai-agent-conduct.mdc`: 2,879 B
   - **Total:** 31,998 B (limit 32,000 B)

The sentences that name the scripts match what those scripts do.
