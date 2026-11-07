---
description: Resume delivery — read the JSON state files and on-disk artifacts via stories-status.sh, then report the current phase and deterministic next command.
---

# /v0-status

<!-- MEM-01: status now starts from one read-only view of every story in every worktree. Before this, /v0-status only saw the checkout it ran in, so a story in flight in ../<repo>-<feature> looked idle or missing from main. -->
`/v0-status` is a strictly read-only inspection command backed by `sh .agents-v0/scripts/stories-status.sh` and `sh .agents-v0/scripts/stories-status.sh --story <slug>`.

## Steps

<!-- BEGIN generated: sh .agents-v0/scripts/stories-status.sh steps (scripts/generate-status-steps.sh); do not edit -->
1. **Cross-worktree overview (`stories-status.sh`, read-only):** Run `sh .agents-v0/scripts/stories-status.sh`. It reads `docs/agents-v0/program.state.json`, `docs/agents-v0/onboarding/state.json`, `docs/agents-v0/requirements/*.state.json`, and `docs/agents-v0/maintain/*/state.json` across the main checkout and every worktree from `git worktree list`, and prints one row per workstream (`story`, `kind`, `branch`, `worktree`, `activePhase`, `activeStatus`, `lastApprovedPhase`, `verifyPassed`, `reopenCount`, `tier`, `blockedReason`, `lastCommit`, `note`, and deterministic `nextCommand` in `--json`). It is strictly read-only and writes nothing; do not save its output to a file or repair a malformed state file automatically.
2. **Select the target workstream (`workflow-orchestration.mdc` Parallel Features):**
   - If the user named a `<feature>`, `<id>`, `program`, or `onboarding`, run `sh .agents-v0/scripts/stories-status.sh --story <slug>` (and `--json` when full JSON fields are needed).
   - If no workstream was named and exactly one open workstream exists in the table, inspect it with `sh .agents-v0/scripts/stories-status.sh --story <slug>`.
   - If multiple workstreams are open and none was named, present the `stories-status.sh` table and ask the user which `<feature>`, `<id>`, `program`, or `onboarding` workstream to inspect. Never guess or pick the newest state file.
   - If no state files exist at all, ask whether this is an existing repository (`/v0-onboard`), a new greenfield program (`/v0-roadmap`), or a trivial docs/patch edit (`/v0-triage <id>`).
3. **Inspect detailed state, release evidence & post-Verify drift (`--story <slug>`):**
   - `sh .agents-v0/scripts/stories-status.sh --story <slug>` reports `story`, `kind`, `tier`, `branch`, `worktree`, `stateFile`, `artifact`, `approvedPhases`, `lastApprovedPhase`, `activePhase`, `activeStatus`, `verifyPassed`, `reopenCount`, `baseCommit`, `blockedReason`, `note`, and `nextCommand`.
   - When `kind` is `feature` and `release` is in `approvedPhases`, `stories-status.sh` cross-checks `sh .agents-v0/scripts/check-release-evidence.sh docs/agents-v0/requirements/<feature>.md`. If `Release evidence OK: False` (`note` contains `unsupported by evidence`), report the state as **unsupported by evidence**, do not call the story complete, do not name a next story, and ask the user to restore `docs/agents-v0/requirements/<feature>.state.json` from version control (the kit cannot re-open a released story). When `docs/agents-v0/project-profile.md` has a configured **Deploy** table and no deploy record is on disk, report `release-deploy` as the next step.
   - When `note` reports an **uncommitted gate** (`uncommitted gate (<phase>): run sh .agents-v0/scripts/guard-<phase>.sh commit ...`), report that external TTY approval is already recorded on disk and the gate commit is the immediate next command before any new phase starts.
   - When `note` reports **post-Verify source drift** (`post-Verify source drift: re-run /v0-verify <slug>`), advise re-running `/v0-verify <slug>` before `/v0-local-release`.
4. **Report & stop (strictly read-only):** Report the state summary, any `blockedReason` or `note`, and the deterministic `Next:` command from `stories-status.sh --story <slug>`. Ignore `docs/agents-v0/backlog/tickets.csv` and `docs/agents-v0/presentations/`, and never name `/v0-export` or `/v0-deck` as the next command. Do not mutate any file or advance any phase during `/v0-status`.
<!-- END generated -->
