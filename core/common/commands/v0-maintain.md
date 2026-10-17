---
description: Maintain phase. Bug fix, CVE or dependency upgrade, doc drift, refactor — each recorded in a maintenance note with its own tier, approvals, and evidence; routes to Verify.
---

# /v0-maintain

You are entering the **Maintain** phase of the delivery lifecycle (`workflow-orchestration.mdc`). Every maintenance change has its own record, `docs/agents-v0/maintain/<id>/note.md`, and its own evidence. It never borrows a feature artifact's approvals.

## Resume
Choose `<id>`: the issue key or a slug (lowercase letters, digits, hyphens). Ask when it is unclear. Copy `docs/agents-v0/maintain/_note.template.md` to `docs/agents-v0/maintain/<id>/note.md` when it is absent, then run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/<id>/note.md --active-phase maintain --status in_progress`. If the phase is already `in_progress` or `blocked`, continue from files on disk. On a red baseline, a spent attempt budget, or a missing prerequisite, re-run with `--status blocked --reason "<one line>"` and stop. When the result is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this change's diff, record `--status blocked --reason "<paths>"` and stop. Do not rewrite `docs/agents-v0/project-profile.md` unless this change is itself a layout, command, or ratchet update.

## Instructions
1. **Tier.** Fill `Type`, `Trigger`, and `Tier` in the note. The default is `standard`. `/v0-triage` is the way into `trivial`. A production incident is `emergency`. A person must confirm `trivial` and `emergency` in chat; record "Tier confirmed by". A change that needs more than `MAINTAIN_MAX_LINES` (default 800) source lines is a feature: stop and use `/v0-intake`.
2. **Acceptance.** Write what "done" means in the note: for a bug, expected versus actual and the test that reproduces it; for a CVE, the IDs and the scan command; for an upgrade, each dependency from → to.
3. **Baseline first.** On Intel macOS, run `sh .agents-v0/scripts/host-tools-macports.sh` first. Exit 2 means a host tool is missing: stop and ask the user to approve `--install` (`docs/agents-v0/gold-standards.md`). Then run the full verify command from `docs/agents-v0/project-profile.md` (`Service verify` with the `Service root:` when the profile lists `Service roots`) before the first edit. If it is red, stop unless `known_failures` allows it and the failures are not in this change's area.
4. Launch the `maintenance-engineer` subagent. When the change fixes authentication, authorization, uploads, a public route, or a saga or consumer, launch it with the Plan-role model (`docs/agents-v0/model-routing-matrix.md` Critical units). When `.cursor/model-config.json` exists, that ID is its `plan` value.
   - **Helpers.** If `docs/agents-v0/maintain/<id>/helper-brief.md` exists, launch the helper it names (`explore-researcher`, `debug-investigator`, or `docs-author`) from this session. Pass the result into a second launch of `maintenance-engineer`. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents).
5. Select the skill:
   - Bug fix → `bugfix-triage` (the reproducing test is written and fails before the fix).
   - Dependency/CVE → `dependency-upgrade`.
   - Doc drift → `doc-sync`.
   - Brownfield refactor without spec change → `characterization-tests` before behavior edits.
   - Schema/migration change → `migration-safety` (expand/contract; no destructive flyway in same release as contract break).
6. Apply the **smallest correct diff**; no drive-by refactors.
7. **Attempts.** Use the profile's fast verify command when that cell is a real command. Append a command-result card per attempt to `docs/agents-v0/build/<id>/build-report.md` (Command, Exit, Attempt, Failing test, Location). Run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<id>/build-report.md` before each new attempt; when it exits 1, record `blocked` (attempt budget exhausted) and stop. Then run the full verify command once.
8. **Classify the result.** Run `sh .agents-v0/ci/classify-change.sh <base>` and paste the output under "Security surface" in the note. A security surface or a schema change means the full Verify with the VAPT checklist. A `trivial` note whose change is not eligible stops here: change the tier to `standard` (a person confirms).
9. Do not commit or push without explicit user approval.
10. **Stop** and present the result. Write `docs/agents-v0/maintain/<id>/phase-result.md` (`phase`, `status`, `artifacts`, `blockers`). After explicit approval, record the `maintain` row in the note (Decision: `Approved`, approver as a GitLab username such as `@ada` because CI may bind the merge request approval to it, date, the note and `docs/agents-v0/build/<id>/` evidence paths). Then run `/v0-verify <id>`: the abbreviated Verify for `trivial`, the full Verify for `standard`. For `emergency`, the change may merge on the `maintain` row; set "Follow-up verify due" and run the full Verify by that date. Put `Maintain-Note: docs/agents-v0/maintain/<id>/note.md` in the merge request.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, the pack VAPT rule (`vapt.mdc`), `vapt-webapp.mdc`, `security-baseline.mdc` §9, `quality-and-testing.mdc`, `architecture-and-diagrams.mdc`.
