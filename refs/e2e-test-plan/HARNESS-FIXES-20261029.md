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

## Not changed

- The kit (`templates/`, `scripts/`), the fixtures, `fix-and-resume.md`, `resume-point.sh`, `triage.sh`.
- `fixtures/scripted-answers.tsv` still says no container runtime exists; installing Docker on the VM would contradict it.
