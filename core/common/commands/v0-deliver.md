---
description: Run one story through the lifecycle by following each phase command in order via guard-deliver.sh, stopping at every gate for explicit user approval; resumes from the state file across worktrees.
---

# /v0-deliver

Run **one story** through **Intake → Design → Build → Verify → Local Release (`/v0-local-release`)** (or **Maintain → Verify → Local Release** when `--maintain` is passed) via the deterministic phase dispatcher `sh .agents-v0/scripts/guard-deliver.sh`. A new greenfield program starts with `/v0-roadmap`, `/v0-architecture`, `/v0-plan`, and `/v0-scaffold` (for the `P0-A` platform skeleton on the integration branch) before feature stories start at `/v0-intake` or `/v0-deliver`. `/v0-export` and `/v0-deck` are not steps in this pipeline.

## Steps

<!-- BEGIN generated: sh .agents-v0/scripts/guard-deliver.sh steps (scripts/generate-deliver-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-deliver.sh check <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]`. It validates the `<feature>` slug, blocks `p0-a*` (redirecting to `/v0-scaffold`), routes `--tier trivial` to `/v0-triage` and `--tier emergency` (without `--maintain`) to `/v0-maintain <id> --tier emergency`, checks brownfield `onboard` approval (`docs/agents-v0/onboarding/state.json` + `baseline-status.json`), checks cross-story uncommitted collisions, resolves the linked worktree (`feature/<feature>` or `maintain/<id>`), refuses if the story is already released, and delegates prerequisite checks to the active/next phase guard (`intake` → `design` → `build` → `verify` → `local-release`, or `maintain` → `verify` → `local-release`). If a phase is at `awaiting_approval` without Sensei's external approval record, it refuses and prints the exact external `approve` command. When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-deliver.sh start <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]`. When the prior phase was externally approved by Sensei in his own terminal (or `Contract: None` design is ready), `start` automatically executes `guard-<prev_phase>.sh commit <feature>` inside the resolved worktree before starting the next phase. It then delegates `start` to the active phase guard (`guard-intake.sh`, `guard-design.sh`, `guard-build.sh`, `guard-verify.sh`, `guard-local-release.sh`, or `guard-maintain.sh`) in the story's worktree and sets `"deliverGuardManaged": true` in the state file.
3. Read `docs/agents-v0/lessons.md`, optionally consult the shell-less `orchestrator` subagent for routing/status advice, and execute the active phase's work in the resolved worktree by following that phase's command (`/v0-intake`, `/v0-design`, `/v0-build`, `/v0-verify`, `/v0-local-release`, or `/v0-maintain`) and launching its shell-less specialist subagents (`requirements-analyst`, `schema-author`, `solution-architect`, `ux-designer`, `design-reviewer`, `backend-engineer`, `bff-engineer`, `frontend-engineer`, `test-engineer`, `security-reviewer`, `code-reviewer`, `release-manager`, `maintenance-engineer`).
4. If a subagent writes a `helper-brief.md` or `failure-brief.md` or hits a phase blocker, run `sh .agents-v0/scripts/guard-deliver.sh block <feature> "<plain reason>" [--maintain]` (which delegates to the active phase guard's `block` subcommand with SHA-256 brief deduplication). Launch the requested shell-less helper (`explore-researcher`, `schema-author`, `debug-investigator`, `docs-author`), pass its findings back, remove the brief, and resume via Step 2; otherwise stop and escalate to Sensei.
5. When the active phase's artifacts and verification evidence are complete, run `sh .agents-v0/scripts/guard-deliver.sh ready <feature> [--maintain]`. It delegates validation to `guard-<active_phase>.sh ready <feature>` inside the story's worktree:
   - **`Contract: None` in Design:** When the story qualifies for the `Contract: None` shortcut, `ready` auto-commits `"<story>: design (Contract: None)"` on `feature/<feature>` and prints `Next: sh .agents-v0/scripts/guard-deliver.sh start <feature>`; loop immediately back to Step 2 to start `build`.
   - **Verify Critical bounce:** When `verify` finds any Open `Critical` issue, `ready` automatically bounces the story to `build` (`--reopen build` or `--reopen maintain`) and exits non-zero; report the bounce and stop.
   - **Standard phase gate:** Otherwise `ready` sets `activeStatus` to `awaiting_approval` and prints Sensei's external approval command. When it prints `REFUSED`, fix what it names and run `ready` again.
6. Stop at the gate. Present the phase summary and artifacts to Sensei and wait for explicit approval. Next: Sensei reviews the phase deliverables and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve <phase> <feature> (or: sh .agents-v0/scripts/guard-common.sh approve deliver <feature>). Never run `approve` yourself; the agent cannot approve any gate.
7. After Sensei runs `approve` in his own terminal outside Cursor, either run `sh .agents-v0/scripts/guard-deliver.sh commit <feature> [--maintain]` (which verifies Sensei's external approval record, delegates the safe-staged gate commit to `guard-<phase>.sh commit <feature>` in the worktree, and prints `Next: sh .agents-v0/scripts/guard-deliver.sh start <feature>` or `COMPLETE` after `local-release`) or re-run `/v0-deliver <feature>` (where Step 2 automatically commits the approved gate and starts the next phase).
<!-- END generated -->

## Tier routing
- **Trivial** — use `/v0-triage` or `/v0-maintain <id> --tier trivial` (`guard-deliver.sh` refuses `trivial` tier).
- **Emergency** — start at `/v0-maintain <id> --tier emergency` with a rollback plan and `Follow-up verify due`, then `/v0-local-release <id> --maintain` (or `/v0-deliver <id> --maintain`). Full `/v0-verify <id> --maintain` is owed by that date.
- **Major** — the full pipeline; Design includes `system-design`, threat-model notes, and `docs/agents-v0/design/system/arc-record.md` when `Material: yes`.
- **Standard** — the default gated pipeline below.

## Pipeline & Gate Commit Contract (`kitfix-20261031-gate-commit`)
| Step | Phase Command | Worktree / Branch | Stops at |
|------|---------------|-------------------|----------|
| 1 | `/v0-intake` (`guard-intake.sh`) | Integration branch → provisions `feature/<feature>` on commit | Intake gate (`approve intake <feature>` or `approve deliver <feature>`) |
| 2 | `/v0-design` (`guard-design.sh`) | `feature/<feature>` worktree | Design gate (auto-committed & skipped for `Contract: None`) |
| 3 | `/v0-build` (`guard-build.sh`) | `feature/<feature>` worktree | Build gate (`approve build <feature>` or `approve deliver <feature>`) |
| 4 | `/v0-verify` (`guard-verify.sh`) | `feature/<feature>` (or `maintain/<id>`) worktree | Verify gate (auto-bounces to `build`/`maintain` on Open `Critical`) |
| 5 | `/v0-local-release` (`guard-local-release.sh`) | `feature/<feature>` (or `maintain/<id>`) → squash-merges to integration branch | Release gate (`approve local-release <feature>` or `approve deliver <feature>`) |

- **STOP at every human gate.** Present the phase summary, run `sh .agents-v0/scripts/guard-deliver.sh ready <feature> [--maintain]`, and wait for Sensei's explicit approval in his own terminal outside Cursor (`sh .agents-v0/scripts/guard-common.sh approve <phase> <feature>` or `sh .agents-v0/scripts/guard-common.sh approve deliver <feature>`). Never auto-advance across a human gate.
- **Seamless resume after external approval:** When Sensei runs `approve` in his external terminal and then re-runs `/v0-deliver <feature>`, `guard-deliver.sh start <feature>` detects the verified external approval record, automatically executes `guard-<prev_phase>.sh commit <feature>` in the story's worktree (`kitfix-20261031-gate-commit`), and immediately starts the next phase.
- **P0-A** runs exclusively via `/v0-scaffold` on the integration branch before feature stories start at `/v0-intake`.

## Conduct
Per `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report at each phase. Read `docs/agents-v0/lessons.md` at the start of every phase. No commits, merges, or pushes without explicit user approval. Follow `workflow-orchestration.mdc`.
