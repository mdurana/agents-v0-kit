---
description: Resume delivery — read the phase in flight and the approvals table, then report the next command.
---

# /status

Use the feature the user names. When they do not name one, list `docs/requirements/*.state.json` and ask. Do not assume the newest state file is the feature they mean (`workflow-orchestration.mdc` Parallel features).

Read that feature's `docs/requirements/<feature>.md`, `docs/requirements/<feature>.state.json` when present, or the milestone manifest. Do not advance a phase or infer approval. Follow `workflow-orchestration.mdc` Phase resume.

1. **Change tier** if recorded; else infer Trivial / Standard / Major from scope.
2. **Active phase.** Read `activePhase`, `activeStatus`, and `blockedReason`.
   - `in_progress` or `blocked`: the next command is that same phase (`/intake`, `/design`, `/build`, `/verify`, `/release`, or `/maintain`). Report files already on disk and what is still missing. Re-entering that command continues from those files. It does not recreate them and does not add an `Approved` row. Include `blockedReason` when status is `blocked`.
   - `awaiting_approval`: stop and ask for approval of `activePhase`. Do not start the next phase.
   - No active phase: name the next command from `lastApprovedPhase` (empty → `/intake`; `intake` → `/design`; `design` → `/build`; `build` → `/verify`; `verify` → `/release`; `release` → `/maintain` when a later change is requested).
3. **Delivery approvals** — last completed phase and whether each recorded evidence path exists on disk.
4. **`commit:`** lines in Build/Verify reports vs current `HEAD` (warn if stale).
5. When a gate was just approved, run `scripts/sync-feature-state.sh` on the feature artifact (if seeded) with no active-phase flags, and note `docs/requirements/<feature>.state.json`. That refreshes `lastApprovedPhase` and clears `awaiting_approval` for the phase that was just approved.
