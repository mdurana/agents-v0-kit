---
description: Resume delivery — read the phase in flight and the approvals table, check the design lock and stale evidence, then report the next command.
---

# /status

Use the feature, maintenance id, or onboarding the user names. When they name none, list every open state file and ask: `docs/requirements/*.state.json` (features), `docs/maintain/*/state.json` (fixes, patches, upgrades, hotfixes), and `docs/onboarding/state.json`. Do not assume the newest one is the one they mean (`workflow-orchestration.mdc` Parallel features).

Read that feature's `docs/requirements/<feature>.md` and `docs/requirements/<feature>.state.json`, or the maintenance note `docs/maintain/<id>/note.md` and its `state.json`, or `docs/onboarding/report.md` and its `state.json`, or the milestone manifest. Do not advance a phase or infer approval. Follow `workflow-orchestration.mdc` Phase resume.

1. **Change tier** if recorded (a maintenance note records `Tier:` trivial, standard, or emergency); else infer Trivial / Standard / Major from scope.
2. **Active phase.** Read `activePhase`, `activeStatus`, and `blockedReason`.
   - `in_progress` or `blocked`: the next command is that same phase (`/onboard`, `/intake`, `/design`, `/build`, `/verify`, `/release`, or `/maintain`). Report files already on disk and what is still missing. Re-entering that command continues from those files. It does not recreate them and does not add an `Approved` row. Include `blockedReason` when status is `blocked`.
   - `awaiting_approval`: stop and ask for approval of `activePhase`. Do not start the next phase.
   - No active phase: name the next command from `lastApprovedPhase` (empty → `/intake`; `intake` → `/design`; `design` → `/build`; `build` → `/verify`; `verify` → `/release`; `release` → `/maintain` when a later change is requested). For a maintenance note: `maintain` → `/verify <id>`; `verify` → `/release` (a trivial or standard note) and an emergency note owes its full Verify by `Follow-up verify due`. For onboarding: `onboard` → `/intake` or `/plan`.
3. **Re-opened phases.** A row whose Decision is `Re-opened` was sent back; it is open until the user approves it again. Name it and the Critical list that reopened it (`docs/requirements/<feature>.phase-result.md`).
4. **Delivery approvals** — last completed phase and whether each recorded evidence path exists on disk.
5. **Design lock.** When `docs/design/<feature>/design.lock` exists, run `sh ci/check-design.sh <feature> --verify-lock` and report a drifted design: the next step is an amendment (`/design` Amending an approved design), not a Build edit.
6. **`commit:`** lines in Build/Verify reports (or `docs/onboarding/` documents) vs current `HEAD`: warn when non-doc files changed since (stale evidence), and say which phase must be re-run.
7. When a gate was just approved, run `scripts/sync-feature-state.sh` on the artifact (feature artifact, maintenance note, or onboarding report; if seeded) with no active-phase flags, and note its state file. That refreshes `lastApprovedPhase` and clears `awaiting_approval` for the phase that was just approved.
