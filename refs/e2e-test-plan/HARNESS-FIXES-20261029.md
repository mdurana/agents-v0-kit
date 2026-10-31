# Harness fixes — 2026-10-29

Changes to the e2e test harness (`refs/e2e-test-plan`) for three goals Marlon set on 2026-10-29:
the run must reach **the first frontend story** (and stop there), it must **check the kit's lessons memory**
after every story release, and it must **run on a fresh Linode Ubuntu 24.04 VM**. It also fixes the cause of the
2026-10-28 step-4 failure. None of these change the kit itself (`templates/`, `scripts/`); only the plan folder.
Every changed line in the scripts carries a `HARNESS-FIX 2026-10-29` comment in plain words.

Default behaviour without `TARGET_SURFACE` is the same plan (steps 0–8), with three changed defaults:
`TURN_CAP` 1740 → 3600 s, `MAX_RETRY_INFRA` 2 → 4, and retry waits 60/120/240 s instead of a flat 120 s (SF-01, SF-03).

Evidence run: `e2e-agy-memory-20261028-2126` (kit `7c6f92f`, agy 1.4.9, `gemini-4-argon-medium`): steps 0–3 PASS,
step 4 (P1-A `openapi-contract-catalog`) FAIL after 5 build tries: 2 × `CAP` (rc 124 at the 1740 s cap), 3 × `STALL`.

## SC-01 — Frontend-chain scope (`TARGET_SURFACE`)

**Why.** Marlon wants the run to include a frontend story but never go past it. The first frontend story depends on
a chain of backend stories, so "the next story" (step 4) is not enough.

**Fix.**
- `scripts/next-story.py chain <ws> <surface> [<released ids>]`: target = first story in roadmap order whose
  `Surface` cell contains the word `<surface>`; prints every not-yet-released story the target depends on
  (transitively), in roadmap order, then the target. Exit 2 if no story has that surface. `map`/`next` unchanged.
- `scripts/env.sh`: `TARGET_SURFACE` (default empty).
- `scripts/run-plan.sh`: with `TARGET_SURFACE` set, `s4` runs `chain_steps`: one `story_run` (the old `happy_story`
  body, split out unchanged) per chain row, checks H1–H5 each, `story-ids.tsv` rows `C1…Cn`, `T1`; the chain stops at
  the first failed story. `STOP_AFTER_STEP` defaults to 4; a value above 4, or `--resume-from` 5+, exits 3.
  `run.meta` and `summary.md` record the scope. Check **C0** fails when the plan has no story with that surface.
- **F1** (target only): the target's merge changed a file under `app/frontend/`, and its verify/build evidence has a
  line naming `npm run verify` with PASS (or exit 0).

**How to check.** On a copy of the 2026-10-28 workspace:
`python3 scripts/next-story.py chain <copy>/work/portal frontend P0-A | cut -f2` prints
`P1-A P1-B P1-C P2-A P2-C P2-O` (one per line); with surface `mobile` it exits 2; `next` and `map` give the same
output as before. `TARGET_SURFACE=frontend STOP_AFTER_STEP=5 bash scripts/run-plan.sh` exits 3 at once.

## SC-02 — Lessons check L1 / L1-END

**Why.** Kit `7c6f92f` adds file-based memory (`docs/agents-v0/lessons.md`, `lessons-archive.md`) written at the
local-release gate. Nothing in the e2e checked it.

**Fix.** `run-plan.sh` `lessons_chk`, active when `LESSONS_CHECK=1` (default 1 in chain mode, 0 otherwise). After
every story release (P0-A in step 3, every chain story in step 4), in `$MAIN`:
`sh .agents-v0/scripts/check-lessons.sh --phase-result docs/agents-v0/requirements/<slug>.phase-result.md --approval-text '<release text>'`
where `<release text>` is the text the runner sent at that release gate, read from `fixtures/approvals.tsv`
(`Approved by mdurana. Accept P-1 if proposed; reject any other proposed lessons.`). The script checks that
`lessons.md` holds exactly the lessons that text accepted. Non-zero exit = check FAIL, the step fails.
At the end of the chain, **L1-END**: `sh .agents-v0/scripts/check-lessons.sh` (no options) must exit 0.

**How to check.** On a copy of the 2026-10-28 workspace, the L1 command for P0-A exits 0; editing
`lessons.md` to add an entry that the approval did not accept makes it exit non-zero.

## SF-01 — Longer turn cap

**Why.** P1-A build tries 1 and 2 ended `CAP` (rc 124) at `TURN_CAP=1740` while the agent was still building.
**Fix.** `TURN_CAP` default 3600 s; new `AGY_TURN_TIMEOUT` default 3540 s (used by `agy-turn-loop.sh`), 60 s below the
cap so agy ends first and its transcript is still collected.
**How to check.** `bash -c '. scripts/env.sh; echo $TURN_CAP $AGY_TURN_TIMEOUT'` prints `3600 3540`.

## SF-02 — Gate-aware end of turn

**Why.** Tries 4 and 5 had already set the story to `build/awaiting_approval` (see `state-after-1.tsv` of
`S4-p1-a-openapi-contract-catalog-build-4` and `-5`) when the model stream dropped. The runner classed the turns
`STALL`, threw the work away, retried from scratch, and the step failed.
**Fix.** `lib.sh` `gate_pending` + `drive_run`: after `STALL`, `INFRA` or `CAP`, if exactly one state file went to
`awaiting_approval` in that turn, its gate is allowed and not yet approved in this run, the runner posts `GATE-AWARE`,
treats the turn as `NORMAL` and sends the scripted approval. The self-approval and forbidden-command checks still run.
**How to check.** Unit test (no agent): build a fake `RUN` with `state-before-1.tsv` / `state-after-1.tsv` copied from
`S4-…-build-4`, `allowed="… build …"`, `sent=""`; `gate_pending 1` returns 0 and sets `gfile`; with `sent` holding
that gate, or without `build` in `allowed`, it returns 1. With `S4-…-build-3` (no state change) it returns 1.

## SF-03 — Stream drops are INFRA, with backoff and 4 retries

**Why.** agy reported the drops only inside the turn's stream (`"error":"The stream was interrupted…"`,
`API error … streamGenerateContent: EOF`) with rc 1 and empty stderr, so `classify` returned `AGENT-ERROR` (no retry).
**Fix.** `classify`: a failed turn (rc ≠ 0, no NORMAL result) whose stream or stderr matches
`stream was interrupted|streamGenerateContent…EOF|API error…EOF|unexpected EOF` is `INFRA`. A turn that recovered
(rc 0 with a result) stays `NORMAL` because that rule is checked first. `MAX_RETRY_INFRA` default 4; waits from
`INFRA_BACKOFF` (`60 120 240`, last value repeats).
**How to check.** `classify 1 <empty stderr> <S4-…-build-4/turn-1.resp.jsonl> 0` prints `INFRA`;
`classify 0 … <a NORMAL jsonl> 0` prints `NORMAL`; `infra_backoff 1..5` prints `60 120 240 240 240`.

## SF-04 — Stop the agy turn after a stall or cap

**Why.** With the agy driver the agent runs in `agy-turn-loop.sh`; killing the runner's turn process left agy running,
and the next turn waited behind it.
**Fix.** `agy-turn-loop.sh` runs each agy turn in its own process group (`setsid`) and writes its pid to
`$TEST_ROOT/agy-driver/agy-turn.pid`; `lib.sh` `agy_stop_turn` stops that group after `STALL` or a cap (rc 124/137)
and posts `AGY-STOP`.
**How to check.** `bash -n`; with a fake pid file pointing at a `sleep` started under `setsid`, `agy_stop_turn` ends it.

## VM-01 — agy path

**Why.** `agy-turn-loop.sh` defaulted to `/home/box/.local/bin/agy` (Marlon's box only); `env.sh` fell back to
`~/.antigravity/bin/agy`. The official installer puts agy in `~/.local/bin`, often not on a tmux window's `PATH`.
**Fix.** `agy-turn-loop.sh` is now in `scripts/` (it lived only in the 2026-10-28 run root) and uses
`AGY_BIN` → `agy` on `PATH` → `~/.local/bin/agy`; it exits 2 with a clear message when agy is missing.
`env.sh` `AGY_BIN` also tries `~/.local/bin/agy`. `prereqs.sh` reports `agy-bin PRESENT <path> <version>` or `HUMAN`
for the Antigravity driver.
**How to check.** `grep -n /home/box scripts/*` finds nothing; `prereqs.sh --check` shows an `agy-bin` row.

## VM-02 — JDK/Node/PG for agy's shell commands

**Why.** agy's shell commands run through `agy-ws-exec.sh`, which inherits the loop's environment and fell back to a
macOS JDK path (`/Library/Java/...`). On the box, `~/.bashrc` set `JAVA_HOME`; a tmux window on a VM reads no
`.bashrc`, and `tools.env` set `TOOLS_PATH` but nothing put it on `PATH`.
**Fix.** `env.sh` and `agy-turn-loop.sh` put `$TOOLS_PATH` on `PATH` after loading `tools.env` (which exports
`JAVA_HOME`). `agy-ws-exec.sh`: keep `JAVA_HOME` if set; else load `tools.env`; else the macOS path only if it exists;
else derive from `java` on `PATH`.
**How to check.** `env -i HOME=$HOME PATH=/usr/bin:/bin bash -c '. scripts/env.sh; echo $PATH; echo $JAVA_HOME'`
shows the tools dirs first once `tools.env` exists.

## VM-03 — One launch for runner and agy loop

**Why.** The agy window was started by hand without the launch settings (`AGY_MODEL`, `AGY_TURN_TIMEOUT`, `TEST_ROOT`
empty) and found the runner with `pgrep`.
**Fix.** `scripts/start-tmux.sh <launch.env> [session]`: fixes `RUN_ID`/`TEST_ROOT` once, starts window `runner`
(`run-plan.sh`, pid in `status/runner.pid`) and, for the agy driver, window `agy` (`agy-turn-loop.sh` for that pid),
both from the same `launch.env`; copies `launch.env` to `status/`.
**How to check.** `bash -n scripts/start-tmux.sh`; with a fake `run-plan.sh` it starts both windows (not run against
a real agent).

## VM-04 — Private kit repo without credentials (docs + comment)

**Why.** `github.com/mdurana/agents-v0-kit` is private; an anonymous clone fails, and the VM gets no GitHub credential.
**Fix.** No code change needed: every clone takes `KIT_URL` as a git bundle file or a local clone made from one
(tested: clone of a bundle, fetch/checkout of `7c6f92f`). Documented in `env.sh` and `test-plan.md` §12.

## VM-05 — Ubuntu 24.04 notes (docs)

PyYAML must come from apt (`python3-yaml`): Ubuntu 24.04 refuses `pip install --user` (PEP 668); the `prereqs.sh` hint
says so. No browser is needed (frontend verify is vitest + jsdom). agy's `trustedWorkspaces` must include the run's
folder (the box trusts only `/workspace`). Sign in to agy only after any machine image is captured.

## CL-01 — CLI versions recorded

`agy-turn-loop.sh` appends `agy --version` and `agent --version` at loop start and end to
`$TEST_ROOT/agy-driver/cli-versions.txt` (agy updates itself).

## SV-01 — `scripts/setup-vm.sh`: prepare a fresh Linode VM (new script)

**Why.** Setting up the Linode shared 16 GB VM (Ubuntu 24.04, sg-sin-2) by hand from §12 was error-prone, and the
captured image must stay under the Linode image limit (6 GB; the script keeps 5.4 GB) and hold no credential.
**Decision (Marlon).** Native tools only: no Docker, Podman, Testcontainers or Redis; portable PostgreSQL 17 under
`$PG_HOME` (prereqs.sh zonky path); P0-A AC-4 stays DEGRADED.
**Fix.** `setup-vm.sh` (root; `set -eu`; idempotent; `--dry-run` prints every action):
- setup: apt packages (`git jq python3 python3-yaml python3-docx curl xz-utils tmux rsync unzip`), timezone
  Asia/Manila, user `e2e`; kit from a git bundle / local repo / https with `GITHUB_TOKEN_E2E_VM` (environment only:
  passed to git as `GIT_CONFIG_*` for the one clone/fetch, never on disk, in argv or in a log; `origin` stays
  token-free); then as `e2e`: latest agy and Cursor CLI from their official installers, agy `trustedWorkspaces`,
  `prereqs.sh --install` / `--check`, `~/.profile` block, `~/launch.env`, `~/setup-vm/versions.txt`.
- `--pre-image [--defer-odc]`: removes apt/npm/pip/maven caches, old Cursor CLI versions, agy logs, logs, `/tmp` and
  shell history; checks for sign-in files; prints `df -h /`; exits 3 with a banner if used > 5.4 GB.
- `--after-image`: installs the deferred OWASP data.
- No sign-in of any kind; no secret in the script.
**prereqs.sh.** `ODC_DEFER=1` reports `odc-data DEFERRED` (new status, does not fail the check) instead of
installing the OWASP data.
**How to check.** `bash -n` and shellcheck clean; `--dry-run` of all three modes on Marlon's box (no root, no apt);
cleanup and credential-scan snippets run on a fake home. Not run on a real VM.

## CR-01 — Resume in chain mode keeps the scope (`run-plan.sh`, `fix-and-resume.md` 5.4)

**Why.** A resume that forgot `TARGET_SURFACE=frontend` would build story N1 at step 4 and continue to steps 5–8.
**Fix.** On `--resume-from`, the runner compares `TARGET_SURFACE` with `target_surface=` in `results/run.meta` and
refuses (exit 3) when they differ. `fix-and-resume.md` 5.4 explains chain-mode resume (same `launch.env`, steps 0–4
only, a step-4 resume reruns the whole chain from `BEFORE-4`, `S4-<id>-END` snapshots are not resume points).
**How to check.** Unit tests: resume without / with another `TARGET_SURFACE` exits 3; `--resume-from 6` exits 3.

## PE-01 — No double merge at release; `merge --abort` after a failed merge (`lib.sh`)

**Why.** P1-E: the agent merged `feature/<slug>` into `main` itself, then made one more commit on the feature branch
(98fa7a9). The branch tip was no longer an ancestor of `main`, so `harness_complete` ran a second `git merge --no-ff`;
it conflicted in the story's state.json and left `main` half-merged (`MERGE_HEAD`, a `UU` file).
**Fix.** New `main_merge_of <branch>`: the merge commit on `main`'s first-parent history that already merged the branch
(or names it). At release, `harness_complete` does not merge when `main` already has that merge, or is mid-merge; it writes
a `FINDING` to `harness-complete.log` (with the branch-only commits) instead. A merge that fails is undone with
`git merge --abort`, so `main` is never left half-merged. The kit side of this error is `kitfix-20261029-step4-p1e`
in `refs/kit-fixes.md`.
**How to check.** `bash -n scripts/lib.sh`; on a repo where `feature/x` was merged and then got one more commit,
`harness_complete` logs `FINDING release: main already has merge commit … NOT merging again` and `main` is unchanged. (Patched on the VM after P1-E; the scenario was not replayed on the box.)

## PE-02 — Resume step 4 from a chain story (`--resume-from-story`, `run-plan.sh`, `start-tmux.sh`, `fix-and-resume.md` 5.5)

**Why.** After the P1-E failure, P1-A…P1-D were released and passed; rebuilding the whole chain from `BEFORE-4` (CR-01)
would redo them.
**Fix.** `run-plan.sh --resume-from 4 --reason <harness-fix|env-fix|agent-retry> --resume-from-story <ID>` (or
`CHAIN_RESUME_FROM_STORY`, with `CHAIN_RESUME_NOTE`): chain mode only, never with `kit-fix`. Earlier stories are kept and
re-checked (`CHAIN-SKIP`); the workspace must be the `S4-<previous>-END` snapshot and pass the resume checks.
`start-tmux.sh` passes the same settings from `launch.env`. Details and records: `fix-and-resume.md` §5.5.
**How to check.** `bash -n scripts/run-plan.sh scripts/start-tmux.sh`; `--resume-from-story` without `TARGET_SURFACE`,
with `--resume-from` other than 4, or with `--reason kit-fix` exits 3. (Refusal lines checked by reading; on the box, runs without an earlier `--test-root` exit 3 at the earlier test-root check first.)

## FR-01 — `fix-and-resume.md` §5.6 and §5.7 (docs)

§5.6: Marlon's standing rule for story failures (roll back, fix the cause, rerun the failed story; automatic during an
unattended watch, at most 2 attempts per story), the P1-E agent logic error and the earlier ones (P0-A `._*` files,
P1-B `*IT.java`, P1-C design evidence), and the rule that an agent logic error is fixed in the kit, not only rolled back.
§5.7: the post-P1-E sequence (commit and push only with Sensei's approval, restore image, re-pull the kit, check the
harness, then resume with `--resume-from-story` at the next story after P1-E, P2-A in this run).


- The kit (`templates/`, `scripts/`), the fixtures, `resume-point.sh`, `triage.sh`. (`fix-and-resume.md` gained 5.4, see CR-01, and 5.5–5.7, see PE-02 and FR-01.) The kit fix for the P1-E error is recorded separately as `kitfix-20261029-step4-p1e` in `refs/kit-fixes.md`.
- `fixtures/scripted-answers.tsv` still says no container runtime exists; installing Docker on the VM would contradict it.

## 2026-10-30 01:15 Asia/Manila — P2-A H2 FAIL, automatic fix 1 of 2 (§5.6, watcher)

- Failure: step 4 chain stopped at P2-A (6 of 20) at 01:01. H2 FAIL: `feature/p2-a-bff-oidc-fail-closed-session-auth` never existed; design, build, verify and release all committed straight onto `main` (588a77a, 82649b1). H1, H3, H4, H5, L1 passed.
- Cause: intake turn 2 ("Approved by mdurana") ended with rc=0 and an EMPTY final result right after `sync-feature-state.sh --approve intake`, before the kit's branch-authorisation question and `feature-worktree.sh` (intake step 7). The harness classed it NORMAL, so the intake run ended NORMAL-END with no worktree, and design/build ran on main. Only empty-result turn in the whole run (1 of 65).
- Harness fix (scripts/lib.sh, classify; backup lib.sh.bak-20261030-p2a): a turn with rc=0 whose last `result` event has empty text is INFRA (gate-aware approval or fresh retry from pre.tgz), not NORMAL. Tested: failed turn -> INFRA, all 64 other turns -> NORMAL; bash -n OK.
- Kit gap (agent logic, fixed in kit-src working tree, NOT committed, not in this run's kit cca2773): v0-design and v0-build only stopped when a feature worktree existed elsewhere; they did not stop when none existed. Both now say to stop and not work on the integration branch when no `feature/<feature>` worktree exists (backups *.bak-20261030-p2a). Needs Marlon's approval to commit.
- Rollback: work/ moved to trash/work-p2a-failed-20261030-0115 (with results/ and status/ copies); restored S4-P1-E-END-KIT-cca2773 (SHA256 OK); main 22c944f clean, no MERGE_HEAD, no p2-a branch/worktree. Old tmux session renamed old-run1629-p2a-failed-1.
- Rerun: --resume-from-story P2-A, reason harness-fix, env ~/launch-resume-p2a-fix1.env.

## 2026-10-30 02:50 Asia/Manila — P2-A H3 FAIL, automatic fix 2 of 2 (§5.6, watcher; last automatic attempt)

- Failure: step 4 chain stopped at P2-A (6 of 20) at 02:11 after rerun 1. Only H3 FAILED (phaseDates not non-decreasing); H1, H2, H4, H5, L1 passed. State: intake/design/build 2026-10-29, verify 2026-10-30, release 2026-10-29.
- Cause (clock mismatch, not a real ordering error): the kit's `sync-feature-state.sh` dates `--approve` calls with UTC (`time.gmtime()`), while the agent ran with TZ=Asia/Manila and wrote local dates in the decision table (Verify/Release rows 2026-10-30). Between 00:00 and 08:00 Manila the two clocks differ by a day, so the release approval (UTC 10-29) came out earlier than the verify date taken from the table (local 10-30). Earlier stories ran before midnight, so they never hit it.
- Harness fix: agent turns now run with `TZ="${AGENT_TZ:-UTC}"` (scripts/lib.sh run_turn env; scripts/agy-turn-loop.sh agy -p env), the same clock the run's kit uses for approval dates. Harness log times stay Asia/Manila. Backups *.bak-20261030-p2a-2; bash -n OK. H3 itself is unchanged.
- Kit gap (fixed in kit-src working tree, NOT committed, not in this run's kit cca2773): templates/.agents-v0/scripts/sync-feature-state.sh now dates approvals with the local clock (`time.localtime()`), the same clock as the decision-table dates. Python block compiles. Needs Marlon's approval to commit.
- Rollback: work/ moved to trash/work-p2a-failed-20261030-0246 (with results/ and status/ copies); restored S4-P1-E-END-KIT-cca2773 (SHA256 OK); main 22c944f clean, no MERGE_HEAD, no p2-a branch/worktree. Old tmux session renamed old-run1629-p2a-failed-2.
- Rerun: --resume-from-story P2-A, reason harness-fix, env ~/launch-resume-p2a-fix2.env. If P2-A fails again, stop after rollback and wait for Marlon.


## 2026-10-30 21:30 Asia/Manila — in-story resume (committed on kitfix-20261031, 2026-10-31, opt-in): in-story resume of a failed chain story after ANY failure, approved by Sensei

- Approval: Sensei (mdurana), voice, 2026-10-30 21:14 Asia/Manila: every rerun of a failed story resumes from the phase that stopped, keeping the story's branch, worktree and approved phases, instead of rolling back and restarting from intake; for any failure type, not only quota. USAGE (lasting quota) stays HALT and stops the run.
- Status: STAGED only. It was prepared while attempt 10 was running (runner PID 723589), so scripts/run-plan.sh and scripts/lib.sh were NOT changed. Apply only when no runner is alive, per in-story-resume-procedure.md §7: backups `scripts/run-plan.sh.bak-20261030-instory` and `scripts/lib.sh.bak-20261030-instory`, hash checks. NOT committed; a commit needs Sensei's approval.
- Diff: `/root/in-story-resume/in-story-resume-any-failure.diff` (VM) = `/workspace/kit-eval/linode-e2e-20261029/in-story-resume-any-failure.diff` (box). Base: run-plan.sh 6a6a22b2…f7b4 → 8b1eea21…815f; lib.sh 667df2e2…b202 → f7cbc305…324d. It supersedes harness-in-story-resume.diff (run-plan.sh only, opt-in quota case), which is kept.
- run-plan.sh:
  - flag `CHAIN_RESUME_IN_STORY=1` (ignored with a warning without CHAIN_RESUME_FROM_STORY), for any resume reason --resume-from-story accepts;
  - `chain_resume_prepare` keeps the story's branch and worktree, and refuses on: work/ missing (no snapshot restore), main dirty or mid-merge, worktree mid-merge, branch without worktree, branch merged but next phase not local-release, next phase DONE/STUCK (except a pending gate). On success it sets CRS_IN_STORY_SLUG;
  - run.meta ` in_story=<slug>`; the RESUME-FROM-STORY line notes "in-story";
  - `story_run`: F1 base is main before the merge if the kept branch is already merged.
- lib.sh:
  - new `in_story_pending_gate`;
  - `drive_story`: on the first run of the in-story story only, a gate already awaiting_approval (allowed, not yet approved) is approved instead of `STUCK:awaiting_approval(<phase>) at run start`;
  - `drive_run`: turn 1 sends approval_for(<gate>) text plus one context line, with the gate's allowlist, an approvals.log row tagged in-story-resume, harness_complete, and the release post-merge step.
- Unchanged: classify, USAGE/AUTH → HALT, the gate-aware rule, the INFRA retry from pre.tgz, fix-attempts.tsv row format and limits, agy-turn-loop.sh, start-tmux.sh.
- Tests (VM /root/in-story-resume; box in-story-resume/tests):
  - `bash -n` OK on both files;
  - `patch --dry-run` against the live files clean; applied copies equal the staged files;
  - apply-in-story-diff.sh on copies: pristine/old-diff/already-applied OK, refuses while the live runner is alive;
  - read-only probe of live P2-P at 21:21 → `OK in-story resume would continue at /v0-build`;
  - sandbox simulation: 21/21 PASS (staged), 2/2 PASS (live files, old behaviour).
- Committed 2026-10-31 on kitfix-20261031 as the staged diff, unchanged (it applied cleanly to 33cbd7f: run-plan.sh 6a6a22b2…f7b4, lib.sh 667df2e2…b202). Flag stays opt-in (D6). The sandbox simulation is now `tests/sim-in-story-resume.sh` (21/21 PASS on the box). The procedure is `in-story-resume-procedure.md`; the behaviour is in `fix-and-resume.md` §5.8.

## 2026-10-31 — classify by outcome (kitfix-20261031, fix 3)

- Source: review of run 20261029-1629. P2-P build (run 8) and release (run 9) reached their gate after a 429/503 that agy recovered from, yet agy reported status ERROR, the turn became AGENT-ERROR, the run STUCK, and the work was thrown away. The P2-P design ran 3 times in 77 s against a lasting quota.
- lib.sh `drive_run`: AGENT-ERROR joins the gate-aware rule. If the state reached an allowed, unsent gate, the scripted approval is sent (GATE-AWARE) and a FINDING keeps the error visible.
- lib.sh `classify`: the lasting-quota regex also matches a reset in minutes (`Resets in 45m`), "try again in/after N min/hours" and daily/weekly/monthly limits. "quota will reset after 0s" stays transient.
- lib.sh `drive_story`: 2 AGENT-ERROR runs in a row → STUCK, even when the state still changed (one retry instead of two).
- run-plan.sh (D7): `MAX_RESUMES_TOTAL` counts failure resumes only; `kit-update` rows do not count. `nres` still numbers the attempt.
- Test: `tests/test-classify.sh` (synthetic cases, drive_story stubs, replay of the saved P2-A intake / P2-P build / P2-P release turns and fix-attempts.tsv from the results branch; skips the replay when that branch is not reachable).

## 2026-10-31 — discriminating checks (kitfix-20261031, fixes 1e, 4a–4e, 2d)

- H1 (`released_ok`): new `story_on_branch` — `feature/<slug>` exists, `main` has its merge, and no first-parent `main` commit since `STORY_H0` touches `app/` apart from that merge. Run 3 (P2-A) built on `main` and still passed H1.
- H3: `phases_in_order` compares `phaseTimes` as instants (fallback: `phaseDates`) and checks the gates' approvals.log SENT order.
- H6 (new, D8 warn first): `### AC-<n>` count vs the milestone `Size` (next-story.py column 5); a recorded `Plan deviation:` or `## Proposed split` excuses it; FINDING by default, FAIL with `H6_MODE=fail`.
- V1 (new): `native_verify` re-runs the project's verify in `$MAIN` after release (plus `check-tests-ran.sh`); `NATIVE_VERIFY=0` skips.
- drive_story: a non-P0-A story past intake with no `feature/<slug>` worktree is STUCK before design/build/verify instead of running on `main`.
- summary.md: Validity block; `results/story-versions.tsv` records kit and harness version per story.
- `AGENT_TZ` default `Asia/Manila` (lib.sh run_turn, agy-turn-loop.sh).
- Test: `tests/test-checks.sh` (25 cases).

## 2026-10-31 — commit on every approved gate, squash release, rollback to the last clean gate commit (kitfix-20261031; Marlon 03:05, 03:08, 03:12 Asia/Manila)

- fixtures/approvals.tsv: every gate's allowlist has `Shell(git:commit*)` (program phases also `Shell(git:tag*)`); gate texts say "commit it"; the branch text is "Branch authorized, commit the intake".
- lib.sh `harness_complete`: the "commit pending files" fallback stays but now covers every gate (and the intake commit after the branch turn, `branch-commit`); when it triggers it writes `GATE-COMMIT-MISSING`, a SEMI label and a FINDING. Its release fallback squash-merges a feature branch (trailers `Story-Branch` / `Story-Tip`), `--no-ff` only for a maintenance branch; a failed squash is reset with `git reset --merge`.
- run-plan.sh: new check **H7** "every approved gate committed by the agent" (FAIL by default, `H7_MODE=warn`); H2 accepts a squash commit.
- lib.sh: `squash_of`, squash-aware `merged_into_main` (the branch must still end at `Story-Tip`) and `main_merge_of`, so H1/H2, the in-story F1 base and the release fallback understand squash releases.
- lib.sh `story_rollback` (+ `gate_commits`, `trace_bad_phase`) and its call in `chain_resume_prepare`: reset to the last clean gate commit of the current story; step back only when a consistency check of the failed phase names an earlier phase or the rerun fails the same way; otherwise stop (ROLLBACK-STOP) and wait for Marlon (fix-and-resume.md §5.6).
- Kit side (same commit): `check-traceability.sh` honours `AGENTS_V0_TRACE_NO_WRITE=1` (print only) for the harness re-run.
- Tests: new `tests/test-rollback.sh` (22 cases); `tests/sim-in-story-resume.sh` fixture commits are gate commits and T13 expects the squash fallback + GATE-COMMIT-MISSING (22 cases).

## 2026-10-31 04:05 Asia/Manila — run README, real quota fixtures, no unattended --amend (kitfix-20261031 follow-up, approved by Marlon)

- run-plan.sh `write_run_readme` (called by `write_summary`): the run `README.md` gets the Validity block (DEGRADED prereqs, SEMI-SYNTHETIC labels by kind, H6 warnings, kit and harness versions per story) between `agents-v0-validity` marker lines; only that part is replaced, hand-written text is kept, a missing README is created. Also fixed: an empty value in the Validity block printed nothing instead of `none` (`orn`).
- tests/fixtures/p2p-quota-20261030: the two real P2-P design turns that hit "Individual quota reached … Resets in 53h" (30 Oct 17:54 and 17:55 Asia/Manila), sanitized by `sanitize.py` (ids, host paths, tool parameters and the prompt preamble removed; about 3.5 KB). `tests/test-classify.sh` section D replays them: USAGE with rc 0 and 1, `agy_api_error_kind` persistent.
- Kit hooks (same commit, kitfix-20261031-no-amend): the unattended allowlist never allows `git commit --amend`.
- Tests: `tests/test-checks.sh` (30 cases), `tests/test-classify.sh` (32 cases).

## 2026-10-31 04:43 Asia/Manila — guard override and gate-chain checks, keep story branches (kitfix-20261031, second review of dd980e6, approved by Marlon; keep-branches 04:47)

- lib.sh `guard_override_scan` (run after every turn): an `AGENTS_V0_*` assignment (`PAT_GUARD_OVERRIDE`, the same rule as the kit hook) in the turn's `commands-<k>.txt` or in a non-markdown file the turn added or changed in the workspace → `guard-override.txt` + FINDING. New check **H8** "no guard override" (FAIL; `H8_MODE=warn`). The harness's own settings are not seen: it sets them in its own process, outside the agent's turn.
- lib.sh `gate_chain` / `gate_chain_check` (before and after every turn) / `gate_chain_ok`: the story's gate commits on `feature/<slug>` must survive each turn and be in order → `GATE-CHAIN-BROKEN` + FINDING. New check **H9** "gate commits intact and in order" (FAIL; `H9_MODE=warn`); the end-of-story chain is saved in `results/gate-chain-<slug>.tsv`.
- Kit hooks (same commit): `AGENTS_V0_*` assignments blocked, `git tag -f` blocked, `git reset <commit>` / `update-ref` ask, story-branch deletion blocked, every segment of an unattended compound command must match the allowlist (the printed gate command `git add -A && git commit ...` now passes; it was denied before, which would have forced the harness fallback and an H7 FAIL in the V3 rerun).
- Keep-branches (Marlon 04:47): no harness or kit step deletes a story branch (checked); story branches are kept after release.
- Tests: new `tests/test-guards.sh` (21 cases; mutation checks: without the ancestry test 3 cases fail, without the pattern 8 fail).

- V3 rerun procedure (P1-E, P2-A, P2-F, P2-P from the old run's END snapshots, main-only kit update with a hash check of the installed kit, `H6_MODE=fail`, `AGENTS_V0_TRACE_MODE=fail`, stop-after-story watcher, pass bar, single-version caveat, branches kept): `refs/e2e-test-plan/v3-rerun-procedure.md`.

## 2026-10-31 09:49 Asia/Manila — installed kit without AGENTS_V0_* overrides; H10; harness-owned trace mode (kitfix-20261031-installed-no-overrides, approved by Marlon)

- External review: H8 and the hook rule match text, so a split name (`V=AGENTS_V0_SKIP_BRANCH; env "${V}_GUARD=1" ...`) or a base64-decoded env file loaded with `set -a` got past both. The kit now removes the override code from installed scripts (see `refs/kit-fixes.md`), so those tricks have no effect. H8 stays, as a speed bump only.
- New **H10** (lib.sh `kit_integrity`, `kit_integrity_check`, `kit_policy_ok`): content hashes of `.agents-v0/scripts/*`, `.agents-v0/hooks/*`, `.agents/hooks/*`, `.cursor/hooks/*`, the hooks.json files and `.agents-v0/policy.conf` in main and the turn's workspace, before and after every turn (`kit-tamper.txt` + FINDING). The story check also needs every `trace.json` gate in `KIT_TRACE_MODE`. FAIL by default; `H10_MODE=warn`.
- `KIT_TRACE_MODE=warn|fail` (launch env): `kit_policy_apply` writes `.agents-v0/policy.conf` in main and every kit worktree, with a harness commit, before each story. `AGENTS_V0_TRACE_MODE` in the launch env is refused (it no longer reaches installed scripts).
- `REQUIRE_FAIL_MODES=1` (`modes_preflight`, before RUN-START): refuses to start unless H6=fail, H7–H10 not warn, `KIT_TRACE_MODE=fail` and every checkout passes `check-installed-kit.sh --expect-trace-mode fail`; each story checks main again first. The `MODES` line in progress.log and the Limits line record the modes.
- `trace_bad_phase` passes `--no-write` (installed copies) and keeps the old env for older copies.
- Tests: `tests/test-guards.sh` now 42 cases (H10 edits, policy removal, `--test-overrides` reinstall, trace.json mode, preflight). Mutation: with the hash comparison disabled, 9 cases fail.


## 2026-10-31 10:35 Asia/Manila — kit source locked away from the agent user; manifest check (kitfix-20261031-kit-source-lock, approved by Marlon)

- **Why (external review, item 1):** the agent runs as the same OS user as the harness (e2e). Any readable kit source (`~/kit-src`, `$T/kit`, `$T/calib/kit`, old installs in `trash/`, a previous run root) keeps the test-override blocks, so a split-name override aimed at it skips the branch guard, whatever the hooks match. The hooks now block running such a copy in unattended mode (`refs/kit-fixes.md`), but that is a text check.
- **`kit_source_locked` (lib.sh):** run by `modes_preflight` when `REQUIRE_FAIL_MODES=1` (or `KIT_SOURCE_LOCK=1`).
  - Every path in `KIT_SOURCE_PATHS` (default `$KIT $TEST_ROOT/calib/kit $HOME/kit-src`, plus a local `KIT_URL`/`KIT_FIX_URL`) must be absent, or neither readable nor enterable by `AGENT_USER`.
  - No readable `*.sh` under `KIT_SCAN_ROOTS` (default `$HOME $TEST_ROOT /tmp`) may still hold a test-override block.
  - It tests as `AGENT_USER` directly when the harness is that user, with `runuser -u` as root, and refuses otherwise.
  - Lines `LOCK ok|absent|READABLE …` and `LOCK scan ok` go to `modes-preflight.log`. The `MODES` line now ends `lock=checked OK|REFUSED`.
- **`scripts/kit-manifest.sh <checkout> <file> [<kit>]`:** written after `check-installed-kit.sh` says HASH-OK, before the lock. It lists the hashes of the installed scripts and hooks; policy.conf is excluded because the harness writes it.
- **`kit_installed_ok`:** with `KIT_MANIFEST` it compares main and every worktree against the manifest, finds no marker, and needs `trace_mode=fail`. Without it, it runs `check-installed-kit.sh` as before. The preflight and the story start both use it, so a run with the source locked needs no kit source.
- **Procedure:** `v3-rerun-procedure.md` §4 steps 6–8 (manifest, harness copy to `~/harness-v3`, lock as root), §5 (`KIT_MANIFEST`, `AGENT_USER`), §6 (launch from `~/harness-v3`; check the `LOCK` and `MANIFEST-OK` lines), §8 (unlock before the next segment). When the harness itself needs the source: read-only checks as root against the locked copy; installs go unlock → install as e2e → lock again, with no agent running.
- **Tests:** `tests/test-guards.sh` is now 54 cases. They cover a readable source refused, a mode-000 source accepted, a moved-away source accepted, a readable unstripped copy in trash refused, `KIT_SOURCE_LOCK=1` alone, an agent user that cannot be tested refused, the manifest written, a preflight on the manifest with the source unreadable, manifest drift refused, `trace_mode=warn` refused, a missing manifest refused, and the harness's own `*.sh` free of the marker string.
- **Mutation checks:** with `kit_source_locked` always passing, 3 cases fail. With the manifest comparison off, 1 case fails.
- **Not checked:** compressed archives (the procedure makes the old snapshots root-only) and the project's git history.
