# Iruka's Independent Design Review: /v0-intake Redesign

**Date:** 2026-11-05 (Manila UTC+8)  
**Reviewer:** Iruka (Independent Reviewer, Team 7c)  
**Target:** [`kit-eval/proposals/sai-intake-design-20261105.md`](sai-intake-design-20261105.md)  
**Verdict:** **APPROVE**

---

## 1. Evaluation against Design Principles

1. **Extension of Guard + External Approval to Story Scope (`<feature>`):**
   `DIA` cleanly generalizes `guard-common.sh` from singleton repository commands (`onboard`, `roadmap`, `architecture`, `plan`, `scaffold`) to parameterized per-story commands (`approve intake <feature>`), storing the external approval record at `~/.agents-v0-approvals/<repo-id>/intake-<feature>.json`. This design lays the foundation for all subsequent story phases (`design`, `build`, `verify`, `release`).
2. **Deterministic Gherkin & Security-Trigger Validation (`DI3`):**
   Moving Gherkin AC validation (`AC-1`..`AC-8`, `Kind: happy | negative | edge`, Given/When/Then presence, vague `Then` rejection, security-trigger negative-case enforcement, single-surface vs vertical-slice rule, and `Open questions: none`) into `guard-intake.sh ready <feature>` eliminates the risk of vague or incomplete requirements slipping into `/v0-design`.
3. **Atomic Worktree Handoff & Safe Staging (`DI5`):**
   Previously, `/v0-intake` required manual coordination between `sync-feature-state.sh --approve intake`, `feature-worktree.sh <feature>`, and `git add -A` in the new worktree. Having `guard-intake.sh commit <feature>` verify Sensei's external approval, write the `Delivery approvals` row, invoke `feature-worktree.sh <feature>`, relocate untracked intake artifacts, stage only the three intake files (`<feature>.md`, `<feature>.state.json`, `<feature>.phase-result.md`), scan for secrets, and create the `<story-id>: intake approved` commit on `feature/<feature>` eliminates both `git add -A` pollution and split-turn branch drift.
4. **Least-Privilege Subagent (`DI4`):**
   Removing `- shell` from `core/common/agents/requirements-analyst.md` aligns `requirements-analyst` with `roadmap-strategist`, `system-architect`, `milestone-planner`, and `platform-engineer`.

---

## 2. Risk Assessment & Verification Notes

1. **Legacy Test Suite Compatibility:**
   Existing kit tests (`scripts/test-command-flows.sh`, `scripts/test-gate-commit.sh`, `scripts/test-design-build.sh`) invoke `sync-feature-state.sh "$ORD" --approve intake` directly on minimal fixtures without running `guard-intake.sh ready`. Requiring `gc_approval_ok intake <feature>` in `sync-feature-state.sh` whenever `guard-intake.sh` created `<feature>.phase-result.md` (or when `guard-intake.sh commit` runs) guarantees strict external approval in the guard workflow while keeping legacy unit fixtures green.
2. **Validate-Kit Contract Preservation:**
   `scripts/validate-kit.sh` checks that `core/common/commands/v0-intake.md` references `docs/agents-v0/requirements/<feature>.md`, `docs/agents-v0/lessons.md`, `kitfix-20261031-gate-commit`, `explicit.*approval`, and the branch-authorisation wording (`Do not run the script in the same turn as the Intake approval`). `guard-intake.sh steps` and `v0-intake.md` must preserve these exact invariants while removing all forbidden internal script names (`sync-feature-state.sh`, `check-gate-commit.sh`, `git add -A`).

---

## 3. Conclusion

The `/v0-intake` redesign specification is comprehensive, backward-compatible with existing kit invariants, and establishes the parameterized `<feature>` approval pattern for the entire story pipeline. **Verdict: APPROVE.** Ready for Jiraiya's oversight pass.
