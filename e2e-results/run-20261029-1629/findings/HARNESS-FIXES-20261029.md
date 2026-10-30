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

## 2026-10-30 06:40 Asia/Manila — kit update cca2773 -> fc4b642 after P2-D, main only (Option A), approved by Sensei

- Approval: Sensei (mdurana), voice call 06:25: after P2-D passes, update the portal's kit to fc4b642 (branch e2eplan-20261029) the same main-only way as cca2773, then resume from P2-E.
- P2-D passed: H1-H5 and L1 PASS (06:35:12); main 01632f6 (release); snapshot S4-P2-D-END 06:35:13.
- Stop: a watcher stopped the runner (process group of run-plan.sh PID 190339; no agy turn was running) at 06:35:14, right after `STORY step 4 story P2-E` and before any P2-E turn. agy daemon and memlog untouched. P2-E intake evidence dir, the stale RUNNING file and pane captures moved to trash/p2e-stopped-20261030-0635. No P2-E branch or worktree existed; main matched S4-P2-D-END exactly (refs, HEAD, files). tmux session renamed old-run1629-p2d-kit-stop.
- Update: safety copy trash/work-before-kit-fc4b642-20261030-063815; worktrees P2-A..P2-D (and their .git/worktrees admin dirs) moved to trash/released-worktrees-20261030-063815, branches kept; run kit clone checked out at fc4b642 (fetched from ~/kit-src); `kit_update_workspace` on main only. The kit install/update step made the one expected commit on portal main, 7b38309 "Update agents-v0 kit to fc4b642cb947 [harness commit]", which pins the portal to fc4b642; it is not a manual commit. kit-src unchanged (no commit, checkout or pull); fc4b642 stays its only new commit.
- Verified: .agents-kit-version 0.0.1+fc4b642cb947; sync-feature-state.sh equals fc4b642's template; one new commit on main; clean; no MERGE_HEAD; all feature branches unchanged. Snapshot S4-P2-D-END-KIT-fc4b642 (SHA256SUMS, .kit, .state.env); run.meta kit_update_6; fix-attempts row 6 KIT-UPDATED.
- Resume: --resume-from-story P2-E, reason harness-fix, env ~/launch-resume-p2e-kit-fc4b642.env (work/ present, used as is).

## 2026-10-30 18:25 Asia/Manila — Findings noted for later (not fixed; NOT committed), recorded at Sensei's request

- HF-F1 — Quota errors are not classed USAGE. P2-P design turns 1-3 (17:44-17:56) failed with agy `RESOURCE_EXHAUSTED (code 429): Individual quota reached` in `turn-1.agy.stderr`, but `classify` marked them `AGENT-ERROR rc=3`, the runner retried twice, logged STUCK and failed the chain (P2-P H1/H2/H3/L1 FAIL). test-plan.md (USAGE row, line 168) says a usage/quota/rate-limit stderr must write `$TEST_ROOT/HALT` and stop the run (exit 2). Suggested fix: in `scripts/lib.sh` classify (and/or `agy-turn-loop.sh`), match `RESOURCE_EXHAUSTED|code 429|quota reached|rate limit` in `turn-*.agy.stderr` and the AGY_ERROR JSON before AGENT-ERROR, and class it USAGE. Impact this run: one resume used (attempt 8, 18:17:34) after Sensei upgraded the Antigravity subscription; evidence moved to trash/p2p-quota-fail-20261030-1815/evidence/.
- HF-F2 — No check compares the written AC count with the plan. P2-F's milestone table planned 8 acceptance criteria but its requirements doc has only 7; H1-H5 and L1 all passed. Suggested fix: add a step-4 check (e.g. H6) that counts AC rows in `docs/agents-v0/requirements/<story>.md` and compares them with the AC column of the milestone table, FAIL (or FINDING) on a mismatch.
- Status: documentation only. No script changed, the running attempt 8 is unaffected, and no kit or harness commit has been made (awaiting Sensei's approval).
- HF-F3 — A recovered transient 429 fails the turn. P2-P attempt 8 build turn (18:42-19:07) reached its build gate (state awaiting_approval) but agy hit one 429 RESOURCE_EXHAUSTED ("quota will reset after 0s") at 18:48, recovered, and still reported result status ERROR; `agy-turn-loop.sh` (around line 87) treats any non-SUCCESS status as failure, so the runner classed AGENT-ERROR, then STUCK awaiting_approval(build); P2-P H1/H2/H3/L1 FAIL, run ended 19:07 exit=1 with no resumes left. Suggested fix: when the final status is ERROR only because of a recovered 429 and the phase state shows the gate was reached, treat the turn as NORMAL (or retry once as INFRA). Rerunning P2-P also needs MAX_RESUMES_TOTAL raised. Not fixed; awaiting Sensei.

## 2026-10-30 19:21 Asia/Manila — P2-P build: recovered transient agy 429 classed AGENT-ERROR; quota errors not USAGE (fix for HF-F3 and HF-F1), approved by Sensei

- Approval: Sensei (mdurana), chat 2026-10-30 19:14 Asia/Manila: "Fix the driver for recovered 429s, raise the resume limit, and rerun P2-P from the P2-O snapshot."
- Failure: attempt 8 (resumed 18:17) passed P2-P intake and design. Build turn 1 (18:42:51-19:07:49) hit one `API error (attempt 1): RESOURCE_EXHAUSTED (code 429): You have exhausted your capacity on this model. Your quota will reset after 0s.` (transcript step 81, 18:48:12). agy carried on: step 82 agent response 18:48:16, the frontend-engineer sub-agent finished 19:05:14, `npm run verify` exit 0, `sync-feature-state.sh --active-phase build --status awaiting_approval`, and a final answer "The Build phase ... is complete and now at the Build gate" (steps 83-99). agy exited rc=0, but its final `result` event kept `status: ERROR`, `finished_reason: error`, `error:` the 18:48 429 (loop.log: `turn end ... k=1 rc=0 status=ERROR`).
- Cause: `agy-turn-loop.sh` line 87 turns any non-SUCCESS status into rc=1 (`turn-1.done` = 1). `classify` (lib.sh) only looks for quota text in the runner's `turn-<k>.stderr` (empty with the agy driver), the rc=0 NORMAL rule does not apply, the 429 is not a stream-drop pattern, so the turn was AGENT-ERROR -> run end, STUCK awaiting_approval(build), chain FAIL at P2-P (H1/H2/H3/L1), RUN-END exit=1 19:07:59. Same blind spot as HF-F1: the 17:54-17:56 design turns (`Individual quota reached ... Resets in 53h19m58s`, agy rc=3, text only in `turn-1.agy.stderr` and the agy `result.error`) were AGENT-ERROR instead of USAGE.
- Fix (scripts/lib.sh only; backup lib.sh.bak-20261030-p2p-429; bash -n OK): new `agy_quota_kind` reads the agy side files next to the turn (`turn-<k>.agy.jsonl` result.error, `turn-<k>.agy.stderr`) and the transcript ERROR_MESSAGE entries of `turn-<k>.jsonl`. `classify`: a persistent limit (Individual quota reached / Resets in <N>h|d / usage limit / quota reached|exceeded / out of credits / upgrade your subscription) -> USAGE (HALT, test-plan.md USAGE row), checked right after the existing stderr rule; when every error of the turn is a transient 429/RESOURCE_EXHAUSTED, agy produced a later agent response and later steps after the last one, and the final answer is non-empty -> NORMAL (same rule as a turn that recovered from a dropped stream); transient 429 with no recovery -> INFRA (gate-aware rule or fresh retry with backoff). Anything mixed with another error, or no agy files (cursor driver), keeps the old rules. agy-turn-loop.sh unchanged (turn-<k>.done still records rc=1, so turns.tsv shows `rc=1 class=NORMAL` for such a turn).
- Tests (VM, /root/p2p-429/test.sh, test.out): P2-P build-1 turn 1 rc=1: old AGENT-ERROR -> new NORMAL (recovered). P2-P design-1/2/3 turn 1 rc=3 (trash/p2p-quota-fail-20261030-1815/evidence): old AGENT-ERROR -> new USAGE (persistent). Synthetic copy of the build turn cut right after the 429: INFRA (transient). Synthetic recovered 429 plus a 500 error in agy stderr: AGENT-ERROR (unchanged). Regression over all 253 recorded turns in evidence/ and trash evidence copies: only those 4 turns change class.
- Resume limit: MAX_RESUMES_TOTAL=9 (one more resume, approved by Sensei 19:14) set in ~/launch-resume-p2p-429fix.env; run-plan.sh already reads it from the environment (`: "${MAX_RESUMES_TOTAL:=8}"`), so run-plan.sh is unchanged.
- Rollback (done by the watcher before this fix): failed tree in trash/p2p-build-fail-20261030-1915, S4-P2-O-END restored, main 7aaafe2 clean, no P2-P branch/worktree, tmux renamed old-run1629-p2p-build-fail. The P2-P attempt-8 evidence dirs are archived by the runner to evidence/attempt-9/ on resume.
- Rerun: --resume-from-story P2-P, reason harness-fix, env ~/launch-resume-p2p-429fix.env (resume 9 of 9); the runner adds fix-attempts.tsv row 9.
- Status: NOT committed (kit-src working tree only); commit needs Sensei's approval.

- HF-F4 — A recovered transient 5xx fails the turn (the same gap as HF-F3). P2-P attempt 9 local-release turn 1 (20:15:46-20:20:18) ran the release checks (frontend `npm run verify`, backend `./mvnw -B clean verify -Pci-security`, `check-lessons.sh` OK), ran `sync-feature-state.sh --active-phase release --status awaiting_approval`, and ended with a non-empty final answer holding the approval request. agy hit one `API error (attempt 1): UNAVAILABLE (code 503): The service is currently unavailable.` (transcript ERROR_MESSAGE step "1", 20:15:54) and went on to step 41, but its final `result` kept `status: ERROR`, `finished_reason: error`, `error:` that 503 (loop.log `turn end ... k=1 rc=0 status=ERROR`). `agy-turn-loop.sh` line 87 made it rc=1; the 429 fix only knew 429s, so classify gave AGENT-ERROR, then STUCK awaiting_approval(release); P2-P H1/H2/H3/L1 FAIL, H4/H5 PASS, RUN-END exit=1 20:20:19. Fixed below.

## 2026-10-30 20:50 Asia/Manila — P2-P local-release: recovered transient agy 503 classed AGENT-ERROR (fix for HF-F4), approved by Sensei

- Approval: Sensei (mdurana), chat 2026-10-30 20:41 Asia/Manila: extend the driver fix so transient server errors are treated like recovered transient 429s, raise the resume limit to 10, roll back to S4-P2-O-END and rerun P2-P as resume 10.
- Fix (scripts/lib.sh only; backup lib.sh.bak-20261030-p2p-503; bash -n OK; diff /root/p2p-503/fix-p2p-503.diff): `agy_quota_kind` renamed `agy_api_error_kind`. Its transient pattern now also covers transient server errors: `UNAVAILABLE`, `INTERNAL (code 500)`, `DEADLINE_EXCEEDED`, `code 500|502|503|504`, `overloaded`, and `50x Service Unavailable / Internal Server Error / Bad Gateway / Gateway Timeout`. Same rules as for 429: every error transient, a later agent response and later agy steps after the last error, non-empty final answer -> NORMAL; transient with no recovery -> INFRA; persistent quota -> USAGE (HALT), checked first; any other error mixed in -> old rules. Two robustness fixes the 503 turn needed: `step_index` is read as an int or a digit string (this transcript wrote "1"), and only error-looking lines of `turn-<k>.agy.stderr` count as errors (this turn's stderr held only `root agent idle; waiting up to 30m0s for 2 background task(s)`, which used to make the turn "none"). Nothing else changed; agy-turn-loop.sh and run-plan.sh unchanged.
- Tests (VM, /root/p2p-503/test.sh, test.out; v0 = before any agy fix, v1 = 429 fix, v2 = this fix): P2-P attempt-9 local-release turn 1 rc=1: v1 AGENT-ERROR -> v2 NORMAL (recovered). Earlier targets unchanged from v1 (attempt-9 build turn NORMAL; quota design-1/2/3 USAGE). Synthetic 503 with no recovery: INFRA. Synthetic recovered 503 plus `PERMISSION_DENIED (code 403)` in agy stderr: AGENT-ERROR. Synthetic recovered 503 plus persistent quota text: USAGE. The old 429 synthetic "429 + INTERNAL (code 500)" now gives NORMAL (both transient, intended). Regression over all 263 recorded turns in evidence/ and trash evidence copies: 1 turn changes vs v1 (the 503 release turn); 5 vs v0 (that turn plus the 4 from the 429 fix).
- Rollback (fix-and-resume.md 5.6, same as the 19:15 one): results/ and status/ copied and the whole work/ tree (P2-P worktree, feature/p2-p-frontend-shell-dashboard-and-notifications branch, worktree admin dirs) moved to trash/p2p-release-503-20261030-2047 (rollback.log there); S4-P2-O-END.tgz restored (SHA256 OK); main 7aaafe2 clean, no MERGE_HEAD, stamp 0.0.1+fc4b642cb947, no p2-p branch or worktree. Old tmux session renamed old-run1629-p2p-release-503. The attempt-9 P2-P evidence dirs are archived by the runner to evidence/attempt-10/ on resume.
- Resume limit: MAX_RESUMES_TOTAL=10 in ~/launch-resume-p2p-503fix.env (copy of launch-resume-p2p-429fix.env); run-plan.sh unchanged.
- Rerun: --resume-from-story P2-P, reason harness-fix, env ~/launch-resume-p2p-503fix.env (resume 10 of 10); the runner adds fix-attempts.tsv row 10.
- Status: NOT committed (kit-src working tree only); commit needs Sensei's approval.

## 2026-10-30 21:30 Asia/Manila — STAGED (NOT applied, NOT committed): in-story resume of a failed chain story after ANY failure, approved by Sensei

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
