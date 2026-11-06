# Jiraiya's Oversight Pass: /v0-intake Redesign

**Date:** 2026-11-05 (Manila UTC+8)  
**Author:** Jiraiya (Team 7c Oversight)  
**Target:** [`kit-eval/proposals/sai-intake-design-20261105.md`](sai-intake-design-20261105.md) & [`kit-eval/proposals/iruka-review-intake-design-20261105.md`](iruka-review-intake-design-20261105.md)  
**Verdict:** **PASS WITH RECOMMENDATIONS**

---

## 1. Oversight Observations

1. **Transition from Singleton Program Gates to Parameterized Story Gates:**
   `/v0-intake` is the bridge between the integration branch (`main`) and per-story feature worktrees (`feature/<feature>`). Parameterizing `gate-rules` and `guard-common.sh` with `<feature>` (`approve intake <feature>` $\to$ `intake-<feature>.json`) is the right architectural move: it avoids polluting `gate-rules` with dynamic per-story sections while keeping every story's external approval cryptographically bound to its own `baseCommit` in `docs/agents-v0/requirements/<feature>.state.json`.
2. **Worktree Boundary Safety:**
   Historically, the riskiest moment in `/v0-intake` was the handoff from drafting untracked files on `main` to committing the Intake gate on `feature/<feature>`. Having `guard-intake.sh commit <feature>` orchestrate `feature-worktree.sh <feature>`, verify the files moved to the worktree, stage only the three intake paths inside the worktree, scan staged diff for secrets, and commit `<story-id>: intake approved` closes the exact failure mode seen in earlier runs (`kitfix-20261031-branch-guard` and `kitfix-20261031-gate-commit`).
3. **Subagent Containment:**
   Stripping `- shell` from `requirements-analyst.md` ensures the subagent cannot invoke `sync-feature-state.sh`, `feature-worktree.sh`, or `git` during spec drafting.

---

## 2. Mandatory Recommendations

- **Recommendation 1 (Path Traversal & Slug Sanitization on `<feature>`):**
  Because `<feature>` is interpolated into file paths (`docs/agents-v0/requirements/<feature>.md` and `~/.agents-v0-approvals/<repo-id>/intake-<feature>.json`), both `guard-intake.sh` and `guard-common.sh` must validate `<feature>` against `^[a-z0-9][a-z0-9-]*$` before any path resolution or substitution, rejecting `/`, `..`, uppercase characters, or leading hyphens.
- **Recommendation 2 (Idempotent Worktree Commit Handling):**
  In `guard-intake.sh commit <feature>`, handle both cases cleanly: (a) `guard-intake.sh commit <feature>` is invoked from the integration branch checkout (it runs `feature-worktree.sh <feature>` and then commits inside the worktree), or (b) the `feature/<feature>` worktree already exists and `guard-intake.sh commit <feature>` is invoked from either checkout. In both cases, the commit must land on branch `feature/<feature>` inside the worktree and leave the integration branch clean.
- **Recommendation 3 (Security-Trigger Refusal Enforcement in `ready`):**
  Ensure `guard-intake.sh ready <feature>` parses the `## Security-review triggers` table/list and verifies that if any trigger is marked `yes` (or `true`), `Negatives: N/A` is rejected and at least one `Kind: negative` AC uses refusal language (`refused`, `rejected`, `denied`, `401`, `403`, `400`, `422`, or `error`).

---

## 3. Verdict

**PASS WITH RECOMMENDATIONS.**  
All three recommendations are incorporated into `DI1`, `DI3`, `DIA`, and `DI5`. Ready to present to Sensei for approval to begin implementation.
