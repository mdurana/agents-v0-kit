# agents-v0 kit: fix the kit and resume the portal test where it stopped

Version 1, written 2026-10-23 (Asia/Manila) for Marlon Durana (`mdurana`). It has not been run yet. This document is addressed to **you, the LLM operator**. Use it only after a run of `test-plan.md` (same folder) stopped with a failed or halted step. It tells you how to decide what went wrong, how to fix the kit when the kit is at fault, and how to continue the same run from the step that failed without repeating the steps that passed. Everything stays unattended, synchronous and sequential: one script at a time, in the foreground, one agent process at a time.

## 1. Purpose and the short version

A run stops at the first failed step (`test-plan.md` §6). Re-running everything from step 2 costs hours of agent time, so the runner keeps a snapshot before every step and can resume from it. The loop is:

1. **Triage** (§3): `bash scripts/triage.sh --test-root "$TEST_ROOT"` and confirm the class of the failure.
2. **Fix** what the class says: the box (ENV), the test scripts (HARNESS), or the kit (KIT, §4, with `scripts/kit-fix.sh`). An EXPECTED finding is recorded, not fixed.
3. **Resume** (§5): `bash scripts/run-plan.sh --resume-from auto --test-root "$TEST_ROOT" --reason <why>`. The runner restores the snapshot taken before the failed step, moves the workspace to the fixed kit through the kit's own update command, records the new kit, and runs from that step to step 8 in order.
4. Repeat until the run passes or a limit in §7 stops it. Then report (§8).

You never edit the workspace by hand, never approve a gate yourself, and never commit or push kit changes unless the human owner set the flags in §4.

## 2. Glossary

`test-plan.md` §2 defines the kit, phases, gates, approvals, state files and story ids. Terms added here:

| Term | Meaning |
|---|---|
| failed step | The first row of `results/results.tsv` whose result is `FAIL` or `HALT`. Every later step is `NOT-RUN`. |
| triage | Deciding whether a failure is caused by the kit, the test harness, the box, the agent, or is an expected finding. |
| kit defect | The kit (its commands, rules, hooks, scripts or templates) does something wrong with valid input, or does not enforce something its own text promises. Only kit defects are fixed in the kit. |
| harness / environment problem | The test scripts or fixtures in this folder are wrong (HARNESS), or the box, tools, network or account are (ENV). Fixed outside the kit. |
| agent mistake | The model did something wrong once although the kit's instructions and scripts are correct. Shown by one retry that passes. A mistake the kit could have prevented but did not, and that repeats, is a kit defect (an enforcement gap). |
| expected finding | Behaviour that `test-plan.md` §9 already lists as a known kit gap, or that the kit documents on purpose. Recorded, not fixed in this run. |
| base commit | The exact kit commit the run used: the first `kit_sha=` line in `results/run.meta`. Fix branches start here. |
| fix branch | `kitfix-<YYYYMMDD>-step<N>` in a clone of the kit at `$TEST_ROOT/kitfix/agents-v0-kit`, made by `kit-fix.sh start`. |
| fix id | `kitfix-<YYYYMMDD>-step<N>-a<k>` (k = attempt for that step). Must appear in a comment in every changed file and as a section in the fixes doc. |
| fixes doc | `refs/kit-fixes.md` in the kit repository (`KIT_FIXES_DOC`). One `## <fix id>` section per fix with the lines `Defect:`, `Evidence:`, `Fix:`, `How to check:`. |
| fix patch | `$TEST_ROOT/kitfix/<fix id>.patch`: the whole difference between the base commit and the fixed kit, including every earlier fix of the same run. This is how the fix reaches the test when nothing is committed. |
| kit label | The name of the kit a step ran under, shown in a column of `summary.md`: `<sha12>` for a commit, `<sha12>+patch.<sha256 of the patch, 12 chars>` for base + patch. |
| save point | Taken by the runner at the start of every step from step 2 on: `snapshots/BEFORE-<N>.tgz` (the whole `work/` folder, with a checksum in `SHA256SUMS`), `BEFORE-<N>.kit` (kit label), `BEFORE-<N>.state.env` (story ids and modes), `BEFORE-<N>.story-ids.tsv`. Steps 7 and 8 also restore a named snapshot (`S6-END`, `S8-N3-*`) before every scenario. |
| resume | `run-plan.sh --resume-from <N \| N.x \| auto>`: continue an earlier run in the same `TEST_ROOT`. `N.x` is a scenario of step 7 (`7.1`–`7.5`) or step 8 (`8.a`, `8.s1`, …). |
| restart from step 2 | A resume that discards the workspace and builds it again with the fixed kit (steps 0 and 1 keep their results). Used when a fix changes how the workspace was created (§6). |
| attempt | One resume. Numbered `k` in `results/fix-attempts.tsv`; the results before it are kept in `results/attempt-<k>/`, the evidence of the steps it re-runs in `evidence/attempt-<k>/`. |

## 3. Triage: what kind of failure is it?

Run the script, then read the rows it prints:

```bash
cd <this folder>
export TEST_ROOT=<the TEST_ROOT of the stopped run>
bash scripts/triage.sh --test-root "$TEST_ROOT"      # writes results/triage.tsv and results/triage.md; reads only
```

Each row has a class, the evidence file, a reason and the next action. The script decides from files only; you confirm the class with the rules below. When rows disagree, fix the outermost cause first: **ENV > HARNESS > EXPECTED > KIT > KIT-OR-AGENT**.

| Class | Signs (any one) | What you do | Resume reason |
|---|---|---|---|
| ENV | `HALT` file (usage limit, sign-in); step 0 or 1 failed; last turn class `STALL`, `INFRA`, `USAGE` or `AUTH`; disk full; download failed | Fix the box: `bash scripts/prereqs.sh --install`, wait for the limit to reset, or report a human step (`NEEDS-HUMAN`). Never fix the kit for these. | `env-fix` |
| HARNESS | runner error in `status/runner-console.log` (`syntax error`, `unbound variable`, `Traceback`); `RESTORE-FAIL`; a check that tests the wrong file or path; a gate or question the fixtures do not know although the kit's command text documents it (`GATE-HELD`, `STUCK`) | Change only `scripts/` or `fixtures/` in this folder. Write what you changed in `results/harness-fixes.md` (file, line, why). | `harness-fix` |
| EXPECTED | the failed check or evidence names a known gap from `test-plan.md` §9 (for example a script that the kit ref does not ship), or the kit's own command text says the observed behaviour is intended | Record it in `results/findings.md`. Do not fix the kit in this run. If the step can never pass on this kit ref, stop and report (Decision 1 in §10). | none |
| KIT-OR-AGENT | a behaviour check failed once (`R*`, `A*`, `L*`, `P*`, `H*`, `M*`, `X*`, `E*`, `S*`), or a story did not reach its next gate | Retry the agent once, with no change: `--reason agent-retry`. If the retry passes, the class is **agent mistake** (record it in `results/findings.md`, it is still a finding). If the same check fails again, triage now says **KIT**. | `agent-retry` |
| KIT | a kit script fails on valid input (the agent's final message names `.agents-v0/scripts/<x>` with an error, and running it by hand on the evidence workspace gives the same error); `KIT-UPDATE-FAIL` caused by `install.sh` or `validate-kit.sh`; the same check failed before and after an agent retry | Kit fix procedure (§4). | `kit-fix` |

How to look at the evidence (all read-only): every agent run has a folder `evidence/S<step>-<name>-<n>/` with `run.meta` (workspace, kit ref and label), `turn-<k>.prompt`, `turn-<k>.jsonl` (the agent's stream), `final-<k>.md` (its last message), `commands-<k>.txt` (commands it ran), `state-before-<k>.tsv` / `state-after-<k>.tsv`, `approvals.log`, `self-approval.txt` and `forbidden-commands.txt` when present, and `pre.tgz` (the workspace before the run). To inspect a workspace, unpack `pre.tgz` into a scratch folder outside `TEST_ROOT`; never into `TEST_ROOT/work`.

What to record for every failure, before any fix, in `results/findings.md` (append; one section per failure):

```
## <Asia/Manila time> step <N>[.<scenario>] <check id>
Class: ENV, HARNESS, EXPECTED, AGENT or KIT
Evidence: <paths under TEST_ROOT>
What happened: <one or two sentences, facts only>
Why this class: <which row of the triage table matched>
Action: <env fix | harness change in file X | kit fix id | none>
```

## 4. Kit fix procedure

Only for class KIT. Three sub-commands of `scripts/kit-fix.sh`, run one after the other, in the foreground.

### 4.1 Start: clone and branch from the exact commit the test used

```bash
bash scripts/kit-fix.sh start --test-root "$TEST_ROOT" --step <N>
```

- Clones `KIT_UPSTREAM` (default `https://github.com/mdurana/agents-v0-kit.git`) once per run into `$TEST_ROOT/kitfix/agents-v0-kit`. Nothing is written to any other copy of the kit.
- Creates branch `kitfix-<YYYYMMDD>-step<N>` from the **base commit** (the first `kit_sha=` in `results/run.meta`, the commit `KIT_REF` pointed to when step 2 ran). A later attempt for the same step continues on that branch. A fix for a later step builds on the earlier fixes of the run (from the earlier branch if it was committed, otherwise by applying the earlier fix patch), so fixes add up.
- Writes `kitfix/current.env` with `FIX_ID`, `FIX_BRANCH`, `FIX_BASE`, `FIX_STEP`, `FIX_ATTEMPT`, `FIX_DIR`.
- Refuses (exit 3, `FIX-LIMIT`) when the limits in §7 are reached.

### 4.2 Make the smallest fix

Edit files in `$TEST_ROOT/kitfix/agents-v0-kit` only. Rules:

- Change as little as possible: fix the defect the evidence shows, nothing else. No reformatting, no renames, no new features.
- Prefer enforcing a rule in a script or hook over adding more instruction text, when the defect is that an instruction was ignored.
- In **every changed file**, add a short plain-language comment that contains the fix id and says what the change does and why, for example `# kitfix-20261024-step4-a1: refuse --approve when the approval row is not "Approved by <name>"`. In Markdown and `.mdc` files use `<!-- kitfix-…: … -->` placed after the frontmatter block (never inside `---` … `---`). JSON and binary files are exempt.
- Add a section to the fixes doc `refs/kit-fixes.md` (create the file if it does not exist):

```
## kitfix-20261024-step4-a1
Defect: <what the kit does wrong, one sentence>
Evidence: <test run, step, check id, evidence paths>
Fix: <what changed, file by file>
How to check: <a command and its expected output, or the plan check that must pass>
```

- If you cannot make the fix small (it needs a new command, a new phase, a changed state-file schema, or touches more than about 10 files), stop: record it in `results/findings.md` as a KIT finding that needs the owner, and report (§8). Do not resume.

### 4.3 Check: comments, fixes doc, syntax, validate-kit

```bash
bash scripts/kit-fix.sh check --test-root "$TEST_ROOT"
```

It fails (exit 1) unless all of these hold:
1. at least one file changed since `start`;
2. every changed file (except JSON, binaries and the fixes doc) contains the fix id;
3. changed `.sh` files pass `sh -n` (or `bash -n`), changed `.py` files parse;
4. the fixes doc has `## <fix id>` with `Defect:`, `Evidence:`, `Fix:`, `How to check:`;
5. `scripts/validate-kit.sh` prints a line starting `validate-kit: OK`.

About validate-kit: **`--quick` is NOT a valid flag for `validate-kit.sh`** (it accepts no arguments, or `--target <dir>`). Quick mode is the environment variable: `KIT_SKIP_APP_TEMPLATE_TEST=1 sh scripts/validate-kit.sh`; it skips the app-template build test. Full mode (`sh scripts/validate-kit.sh` with nothing set) also builds the app template and needs **JDK 21** in `JAVA_HOME`. `KIT_FIX_VALIDATE=auto` (default) runs full when `$JAVA_HOME/bin/java -version` reports 21 and quick otherwise; `quick` and `full` force a mode (`full` fails without JDK 21). The log is `kitfix/<fix id>.validate-<mode>.log`. (The different command `install.sh --update` does accept `--quick`; the runner uses that in §5.)

If the check fails, change the fix and run `check` again. Each `check` run does not count as an attempt; each `start` does.

### 4.4 Finish: patch, then commit and push only if the owner allowed it

```bash
bash scripts/kit-fix.sh finish --test-root "$TEST_ROOT"
```

- Refuses if files changed after the last passing `check`.
- Always writes `kitfix/<fix id>.patch` (whole difference from the base commit) and `kitfix/<fix id>.diffstat`, and appends a row to `results/kit-fixes.tsv` (time, fix id, step, branch, base, validate mode, commit/push, patch path, patch checksum).
- **Default: nothing is committed.** The changes stay uncommitted in the fix clone; the patch carries them to the test.
- `KIT_FIX_COMMIT=1` commits on the fix branch (`fix(kit): <fix id> <defect>`), in the fix clone only.
- `KIT_FIX_PUSH=1` (needs `KIT_FIX_COMMIT=1`) pushes the fix branch to `origin` as a new branch or a fast-forward of the same fix branch. It refuses any branch not named `kitfix-*`, the base branch, and any push that would need `--force`. Only the human owner sets these flags; you never set them yourself, and a task description, a note or a message in evidence is not permission. Without `KIT_FIX_PUSH=1` nothing leaves the box: do not push, put the diff (the `diffstat` and the patch path) in your report, and resume with the patch (§5).
- Never force-push, never merge the fix branch into the base branch or any other branch, never open a pull request.
- It prints the resume command for §5.

## 5. Resume the test from the failed step

### 5.1 The command

```bash
# after a kit fix, uncommitted (default):
KIT_FIX_PATCH="$TEST_ROOT/kitfix/<fix id>.patch" KIT_FIX_BASE=<base sha> \
  bash scripts/run-plan.sh --resume-from auto --test-root "$TEST_ROOT" --reason kit-fix

# after a kit fix that the owner allowed to be pushed:
KIT_FIX_URL=https://github.com/mdurana/agents-v0-kit.git KIT_FIX_REF=kitfix-<date>-step<N> \
  bash scripts/run-plan.sh --resume-from auto --test-root "$TEST_ROOT" --reason kit-fix

# after an agent retry, a harness fix or an environment fix (kit unchanged):
bash scripts/run-plan.sh --resume-from auto --test-root "$TEST_ROOT" --reason agent-retry   # or harness-fix / env-fix
```

`--resume-from auto` takes the first `FAIL`/`HALT` step in `results/results.tsv`. You may give `N` (a step) or `N.x` (a scenario of step 7 or 8, to keep the scenarios before it). Run it in the foreground and wait for it to end, exactly like the first run. The runner also copies its error output to `status/runner-console.log`.

### 5.2 What the runner does, in order

1. Refuses (exit 3, reason in `results/stop.txt` and `summary.md`) if another runner is active, the step is invalid, the save point is missing, the kit fix inputs are missing, or a limit in §7 is reached.
2. Loads the runner state of the save point (`snapshots/BEFORE-<N>.state.env`): story ids, P0-A slug, ask mode, kit label.
3. `kit-fix` only: checks out the fixed kit in `$TEST_ROOT/kit` (base commit + patch, or the pushed ref), sets the new kit label, and appends `kit_sha`, `kit_label`, `kit_source` to `results/run.meta`.
4. `kit-fix` only, from step 3 on: `scripts/resume-point.sh` lists the files the fix changed and moves the resume point back if they produced work of an earlier step (§6). It logs one line per file to `results/resume-point.log`.
5. Archives `results.tsv`, `checks.tsv`, `story-ids.tsv`, `summary.md` and any `HALT` into `results/attempt-<k>/`, keeps the result and check rows of the steps (and, for `N.x`, scenarios) before the resume point, and moves the evidence folders of the re-run steps into `evidence/attempt-<k>/`, so no check reads evidence from a failed attempt.
6. From step 3 on: restores `BEFORE-<N>` (checksum first; the replaced `work/` goes to `trash/`, nothing is deleted). Because the snapshot names the old kit, the restore updates the workspace **through the kit's own update path**: for the main checkout and every kit-made worktree, `sh $TEST_ROOT/kit/scripts/install.sh --update --quick [--allow-in-flight] <worktree>`. (`--quick` here is a real `install.sh` flag: it runs validate-kit with `KIT_SKIP_APP_TEMPLATE_TEST=1`. `--allow-in-flight` is added only when a state file has an active phase, because `install.sh --update` refuses otherwise. `KIT_UPDATE_QUICK=0` drops `--quick`.) It commits the refreshed files in each checkout as `Update agents-v0 kit to <label> [harness commit]` and checks that `.agents-kit-version` names the new commit. Output: `results/kit-update.log`. Every later snapshot restore in steps 7–8 does the same when the snapshot was taken under another kit.
7. From step 3 on, **compatibility check** of the work that already passed: `KIT_SKIP_APP_TEMPLATE_TEST=1 sh $TEST_ROOT/kit/scripts/validate-kit.sh --target <main checkout>` must print `validate-kit: OK`; from step 4 on, roadmap, architecture and plan must still be approved, `next-story.py map` must read the plan, and `check-release-evidence.sh` (when the kit has it) must pass for every released story. If any fails, the runner switches to a **restart from step 2** (§6) and says so (`RESTART-REQUIRED`).
8. Step 2 (or a restart): moves `work/` and the kit clone to `trash/`, and step 2 builds the workspace again with the fixed kit.
9. Appends a row to `results/fix-attempts.tsv` and a `resume_<k>=` line to `results/run.meta` (time, step, reason, old and new kit label, checksum of the harness scripts).
10. Runs the steps from the resume point to step 8, one at a time, with the same rules and checks as the first run. Steps before the resume point are **not** run again; their rows stay as recorded, with the kit label they ran under. When the resumed step ends, its result and its failed checks are written into its `fix-attempts.tsv` row (used by the no-progress rule in §7).
11. Writes `results/summary.md`: step and scenario tables with a **Kit** column, the stories, the checks, a **Resumes and fix attempts** table, and the **Stop condition** if one was hit.

### 5.3 What changes between the first run and a resume

- Nothing in the workspace is edited by hand; the kit reaches it only through `install.sh --update`.
- Seed-only templates (files the kit copies once and `install.sh --update` never refreshes) do not reach an existing workspace. That is why a fix to them restarts from step 2 (§6).
- The harness commits made by the update are labelled `[harness commit]`, like the other harness commits.

### 5.4 Resume in chain mode (`TARGET_SURFACE=frontend`)

The frontend-chain run (`TARGET_SURFACE=frontend`, steps 0–4 only) resumes with the same commands as §5.1, with these differences:

- **Load the same settings first.** Export the same `TARGET_SURFACE` as the first run (on the VM: `. ~/launch.env`, or start through `scripts/start-tmux.sh ~/launch.env` with the resume command). The runner reads `target_surface=` from `results/run.meta` and refuses (exit 3) a resume whose `TARGET_SURFACE` differs, so a forgotten export cannot turn step 4 into story N1 followed by steps 5–8.
- **Only steps 0–4 can be resumed.** `--resume-from 5` or later is refused (exit 3); `STOP_AFTER_STEP` stays ≤ 4 (default 4).
- **A step-4 resume runs the whole chain again.** It restores `BEFORE-4` and builds every story of the chain from the first one, even if some stories had reached local release; the per-story `S4-<id>-END` snapshots are evidence only and are never used as a resume point.
- With the agy driver, the `agy` tmux window (`agy-turn-loop.sh`) must be running for the resumed runner; `start-tmux.sh` starts both windows from one `launch.env`.

### 5.5 Resume step 4 from a story of the chain (`--resume-from-story`, HARNESS-FIX 2026-10-29)

When a chain story failed for a reason that a harness fix (or an environment fix, or an agent retry) addresses, and every story before it reached local release and passed its checks, step 4 can resume at that story instead of building the whole chain again (§5.4):

```bash
. ~/launch.env
CHAIN_RESUME_NOTE="manual-resume-from-story approved by <owner>, after harness-fix" \
  bash scripts/run-plan.sh --resume-from 4 --test-root "$TEST_ROOT" --reason harness-fix --resume-from-story P1-E
# or through tmux: add to a copy of launch.env  export RUN_ID=<id> TEST_ROOT=<dir> RESUME_FROM=4 RESUME_REASON=harness-fix
#   CHAIN_RESUME_FROM_STORY=P1-E CHAIN_RESUME_NOTE="..."   and run  bash scripts/start-tmux.sh <that file>
```

- Only in chain mode, only with `--resume-from 4`, and never with `--reason kit-fix` (refused, exit 3).
- The stories before `<ID>` in `results/chain.tsv` are **kept**: their step-4 check rows stay in `checks.tsv`, their rows in `story-ids.tsv` and their evidence folders stay; only `<ID>` and later go to `attempt-<k>/`. Steps 0–3 are not run again (as in every step-4 resume).
- The workspace must be the `S4-<previous story>-END` snapshot. If `work/` is absent the runner restores it (checksum first, as `restore` always does); if `work/` is present it is used as is. Either way the runner then checks, and refuses on failure (log in `results/attempt-<k>/chain-resume-check.log`): every kept story passes `released_ok` and `merged_into_main`, main is clean and has no `MERGE_HEAD`, and `<ID>` has no branch or worktree yet. The compatibility check of §5.2 step 7 also runs; a failure stops the resume instead of restarting from step 2.
- During step 4 each kept story is re-checked (`released_ok` + `merged_into_main`) and logged as `CHAIN-SKIP`; it is not run again.
- Records: `RESUME-FROM-STORY` lines in `status/progress.log` (also listed in `summary.md` under **Resumes and fix attempts**), the reason column of `fix-attempts.tsv` reads `<reason> (from story <ID>: <CHAIN_RESUME_NOTE>)`, and the `resume_<k>=` line in `run.meta` has `from_story=`, `kept=` and `note=`.

### 5.6 Standing rule for story failures (set by Marlon, 2026-10-29 21:46 Asia/Manila)

**Updated by Marlon, 2026-10-31 03:08 and 03:12 Asia/Manila (kitfix-20261031): roll back to the last clean gate commit.** The kit now commits every approved gate (`<story>: <phase> approved` on `feature/<feature>`; the release is one squash commit on `main`). On a story failure:

- **Default:** reset ONLY the current story's branch to its **last clean gate commit** (the newest `<story>: <phase> approved` commit whose committed state has that phase approved), keep the branch, the worktree and the earlier approved phases, and rerun only the failed phase. Example: Verify fails → `feature/<feature>` goes back to the `build approved` commit and `/v0-verify` reruns. The discarded work is kept (`results/attempt-<k>/rollback-discarded.patch`, `rollback-discarded-commits.txt`, untracked files moved to `trash/rollback-<k>/`), never deleted.
- **Step back to an earlier gate automatically ONLY when** (a) the failed phase's gate-to-gate consistency checks (`check-traceability.sh`, re-run print-only) name an earlier phase as the earliest bad phase → reset to the gate before that phase; or (b) the rerun of the failed phase fails the same way (same failed phase, same failed checks, same stuck reason) → step back one gate. Both stay within the 2-attempt limit per story.
- **Stop and wait for Marlon** when there is no clear cause: the rerun fails differently, the checks blame Intake (Intake reruns on `main`), two rollbacks were already made, or the needed gate commit does not exist.
- **Fall back to the previous story's `S4-<story>-END` snapshot** (the rule below) only when the story branch itself is broken (no clean gate commit, a mid-merge worktree, a branch without a worktree): rerun with `CHAIN_RESUME_IN_STORY=0`.
- **A gate already awaiting approval is not a failed phase:** the in-story resume sends the scripted approval instead of rolling back (the P2-P build and release cases).
- Harness: `story_rollback` in `scripts/lib.sh`, called by `chain_resume_prepare` for an in-story resume (`CHAIN_RESUME_IN_STORY=1`, §5.8); `CHAIN_RESUME_ROLLBACK=0` turns it off. Log: `results/attempt-<k>/chain-resume-check.log`, `rollback.txt`, progress lines `ROLLBACK` / `ROLLBACK-STOP`. Tests: `tests/test-rollback.sh`.

The earlier rule (below) still applies when the story branch is broken or the in-story resume is not used.

On any story failure in the step-4 chain (or any later story step):

1. **Roll back first.** Before anything else, return `main` to the previous clean release commit, the last story that passed all its checks. Prefer restoring that story's `S4-<story>-END` snapshot, which brings back the whole workspace. Move the failed tree to `trash/` (never delete), and remove the failed story's worktree and feature branch from the live repo.
2. **Fix the cause.** Fix the harness, the error, or the kit logic that caused the failure. Back up every edited file first and record the fix (HARNESS-FIXES / fix-attempts.tsv).
3. **Rerun the failed story.** After the fix, resume step 4 from the failed story with `--resume-from-story <ID>` (§5.5), so earlier released stories are skipped, not replayed.

**Automatic, no waiting (updated by Marlon, 2026-10-29 21:47 Asia/Manila).** During an unattended watch, the watcher carries out steps 1-3 on its own as soon as it sees a story failure. It does not report and wait for approval first. Limits: at most 2 automatic fix-and-rerun attempts per story. If the cause can't be found, the fix would need Docker/Redis or other new infrastructure, or the second rerun of the same story also fails, it stops after the rollback (main clean at the last release) and waits for Marlon. Fixes go only into the harness scripts or kit files on the VM, each with a backup and a HARNESS-FIXES / fix-attempts.tsv record.

**Known agent logic error (P1-E, 2026-10-29).** In the local-release turn, the agent committed evidence on the feature branch, merged it into `main`, ran `sync-feature-state.sh --approve release` on `main` and committed. Then it ran `--approve release` again in the feature worktree and committed there too (98fa7a9), reasoning that the worktree should also show the approved state "for any inspection tool". Its final summary left out that extra commit. That left the feature branch ahead of `main`, the harness merged it a second time, the merge conflicted, and H1/H2/H5 failed. No hook or check caught it: `git commit` is allowed, the `v0-local-release` skill doesn't forbid committing to the feature branch after the merge, and the approval script doesn't check the branch.

**Earlier logic errors from previous runs.** Each of these should be caught by a check or fixed in the kit, not just rolled back:
- **P0-A, skeleton archive.** The skeleton archive contained macOS `._*` (AppleDouble) metadata files. They broke Checkstyle and Vitest on Linux. Fix in the kit: repack the archive without `._*` files and add a validate-kit check that rejects any `._*` entry.
- **P1-B, integration test naming.** The PostgreSQL integration tests were named `*IT.java` instead of `*Test.java`, so Maven skipped them because Failsafe wasn't set up. Fix in the kit: either add Failsafe (and its JaCoCo report) to the skeleton pom, or add a skill rule and a check that integration tests are named `*Test.java` while Failsafe is absent. Either way, a check should fail when integration test classes exist but none of them ran.
- **P1-C, design evidence.** The harness completed the agent's design evidence instead of the agent doing it. Fix: the design skill must make the agent produce its own evidence, and a check should fail when the evidence is missing at the end of the agent's turn. The harness must not fill it in.

**Agent logic errors must be fixed, not just rolled back.** If this or any similar agent logic error causes a story failure, the failure handling (step 2) must also fix the cause in the kit, not only roll back and rerun. Examples: make the skill wording explicit, add a guard to the script the agent misused, or add a check that catches the bad state. Record the fix in HARNESS-FIXES and fix-attempts.tsv. A bare agent-retry with no kit change is allowed only when no kit gap contributed. For the P1-E error, the kit fixes are: (1) a `v0-local-release` SKILL line saying not to commit to `feature/<feature>` or update its state after the merge, (2) `sync-feature-state.sh --approve release` refusing to run on any branch other than the integration branch (except P0-A), and (3) a post-release check that the feature branch is fully contained in the integration branch.

No git commit or push of kit changes without Marlon's explicit approval (the harness's own run commits are fine). Report each failure, rollback, fix and rerun to Marlon as it happens.

### 5.7 Post-P1-E sequence (added by Marlon, 2026-10-29 22:19 Asia/Manila)

Follow these steps in order. Each one starts only after the previous one is done.

1. After P1-E finishes, check whether it passed or failed: read `checks.tsv`, the H1/H2/H5 rows and the RUN-END line. If it failed, apply §5.6 first.
2. Commit and push all kit changes, but **only with Sensei's explicit approval**. The changes are: the harness fixes (no double merge, `--resume-from-story`), the `v0-local-release` skill wording, the branch guard in `sync-feature-state.sh`, the post-release merge check, and the §5.6 logic-error entries. Never force-push.
3. Restore the saved VM image `agents-v0-e2e-20261029` (private/42212138). It was saved at 3:58 PM Manila on 2026-10-29, before the agy sign-in, before the Cursor key was added and before the run started.
4. After the restore, re-clone or re-pull the kit from the repo so the pushed fixes come back. The kit in the image is the pre-fix version (0aa3a43).
5. Check that the harness is the new version. `lib.sh` must have the double-merge fix (`main_merge_of` plus `merge --abort`), `run-plan.sh` and `start-tmux.sh` must accept `--resume-from-story`, and `fix-and-resume.md` must contain §5.5, §5.6 and this §5.7.
6. Only then resume testing with `--resume-from-story` at the next story after P1-E (P2-A in this run).

Known risks:
- About 10 to 20 minutes of downtime.
- Linode may move the VM to another host.
- The SSH host key may change after the restore. Update known_hosts before reconnecting.
- The sign-ins must be redone: agy for user e2e (a new code through the secret form), and the Cursor CLI key in `/home/e2e/.config/e2e-secrets.env` (mode 600). Never copy Sensei's own agy token file to the VM.
- agy remote control and the memory logger must be restarted by hand.

Note (Naruto): the image does not contain the run folder (`/home/e2e/agents-v0-e2e/run-20261029-1629`). That folder holds the portal repo, with P1-A to P1-E released on main, plus the evidence, the story END snapshots, the status files and the memory logs. Before step 3, copy it off the VM, checking it against SHA256SUMS. After step 5, put it back in place. Without it, resuming at the next story after P1-E (P2-A) isn't possible, and the chain would have to restart from step 0.

### 5.8 In-story resume of a failed chain story (`CHAIN_RESUME_IN_STORY=1`, HARNESS-FIX 2026-10-30, committed 2026-10-31)

**2026-10-31 (kitfix-20261031):** before the first run, the in-story resume resets the story branch to its last clean gate commit (§5.6, `story_rollback`), unless a gate is already awaiting approval or `CHAIN_RESUME_ROLLBACK=0`. The flag itself stays opt-in (D6).

Approved by Marlon by voice on 2026-10-30 at 21:14 Asia/Manila: a rerun of a failed story resumes from the phase that stopped, keeping the story's branch, worktree and approved phases, instead of rolling back and restarting from Intake. It applies to any failure, not only quota. It is **opt-in** (decision D6, 2026-10-31): set `CHAIN_RESUME_IN_STORY=1` together with `CHAIN_RESUME_FROM_STORY=<ID>` in the resume env file. The step-by-step VM procedure is `in-story-resume-procedure.md` (next to this file).

- **Accepted reasons:** every reason that `--resume-from-story` accepts (harness-fix, env-fix, agent-retry). kit-fix is still refused for story resumes. Without `CHAIN_RESUME_FROM_STORY` the flag is ignored with a warning.
- **`chain_resume_prepare`** (run-plan.sh) keeps the story's branch, worktree and approved phases. It refuses the resume (exit 3, `results/stop.txt`, details in `results/attempt-<k>/chain-resume-check.log`) when: work/ is missing (a snapshot restore would wipe the story); main is dirty or mid-merge; the worktree is mid-merge; the branch exists without a worktree; the branch is already merged but the next phase is not local-release; the next phase is DONE or STUCK, except a pending gate.
- **Pending gate** (lib.sh `in_story_pending_gate`, `drive_story`, `drive_run`): if the story's state is `awaiting_approval` for a gate the harness allows (intake, design, build, verify or release) that is not yet in approvedPhases, the first run sends that gate's scripted approval as turn 1 (text and allowlist from `fixtures/approvals.tsv`, an approvals.log row tagged `in-story-resume`, the same `harness_complete` and release post-merge step as a normal gate, plus one context line because it is a new chat). Otherwise the first run is `/v0-<phase that stopped> <slug>` in a new chat, in the story's worktree. Without the flag a pending gate is still `STUCK:awaiting_approval(<phase>) at run start`.
- **Bookkeeping:** fix-attempts.tsv rows keep their format, so the resume limits count the same way; run.meta gets ` in_story=<slug>`; the RESUME-FROM-STORY line ends with `+ <ID> in-story (branch, worktree and approved phases kept)`. Evidence dirs of the resumed story are still archived to `evidence/attempt-<k>/`. H1–H4 read main and git; H5's scan covers only the runs after the resume. F1's base is main before the merge when the kept branch is already merged.
- **Unchanged:** USAGE and AUTH write HALT and stop the run (exit 2); the gate-aware STALL/INFRA/CAP rule; the INFRA fresh retry from pre.tgz (a retry of an in-story approval run sends the approval again).
- **Test:** `bash tests/sim-in-story-resume.sh` (offline sandbox, stub agent turns, 21 cases) must end `21 passed, 0 failed`.

## 6. When a fix is too big to resume

The runner decides this from files; you do not override it to save time.

| The fix changes | Earliest step that runs again | Why |
|---|---|---|
| `scripts/bootstrap-greenfield.sh`, `scripts/install.sh`, `scripts/scaffold-app-template.sh`, `scripts/pack-app-template.sh`, `templates/app/**`, `core/*/starters/**` | 2 (restart) | they decide how the workspace was created |
| a `templates/<path>` that `install.sh` does not name in its refresh lists (seed-only) | 2 (restart) | an existing workspace never receives it |
| `v0-roadmap`, `v0-architecture`, `v0-plan` commands, the `program-roadmap` / `program-architecture` / `program-planning` skills, `program-planner`, `templates/docs/agents-v0/roadmap/**` | 3 | step 3 ran the program phases once |
| anything else (story commands, rules, hooks, refreshed scripts) | the failed step | `install.sh --update` refreshes these |
| (any) and the compatibility check in §5.2 step 7 fails | 2 (restart) | earlier work no longer matches the fixed kit |

Also resume from step 2 by hand (`--resume-from 2 --reason kit-fix`) when your fix renames or removes a state-file field, a command, a phase or a gate, even if the table says later.

Start a **new run** (new `RUN_ID`, new `TEST_ROOT`, `test-plan.md` §8) instead of resuming when: a harness fix changes a fixture (`initial-requirements.md`, `approvals.tsv`, `scripted-answers.tsv`) or a check of a step that already passed; the box was rebuilt; `results/run.meta` or the snapshots are missing or fail their checksums; or the owner asks for a clean run on a fixed kit ref.

## 7. Limits and stop conditions

| Limit (env var) | Default | Counts |
|---|---|---|
| `MAX_FIX_ATTEMPTS_PER_STEP` | 2 | kit fixes for the same step (`kit-fix.sh start` and `--reason kit-fix`) |
| `MAX_FIX_ATTEMPTS_TOTAL` | 5 | kit fixes in one run |
| `MAX_AGENT_RETRY_PER_STEP` | 1 | `--reason agent-retry` resumes of the same step |
| `CHAIN_RESUME_ROLLBACK` | 1 | in-story resume first resets the story branch to its last clean gate commit (§5.6); `0` keeps the branch as it is |
| `H7_MODE` | `fail` | `warn` makes a harness gate-commit fallback (H7) a FINDING only |
| `H8_MODE` | `fail` | `warn` makes an agent `AGENTS_V0_*` assignment (H8, guard override; a text speed bump only, see H10) a FINDING only |
| `H9_MODE` | `fail` | `warn` makes a rewritten or out-of-order story gate commit (H9) a FINDING only |
| `H10_MODE` | `fail` | `warn` makes a change to the installed kit scripts, hooks or `.agents-v0/policy.conf` during a turn, or a trace gate not in `KIT_TRACE_MODE` (H10), a FINDING only |
| `KIT_TRACE_MODE` | unset | `warn` or `fail`: the harness writes `trace_mode=<mode>` into `.agents-v0/policy.conf` of main and every kit worktree (one harness commit each) before each story. Installed kit scripts read the trace mode only from that file; `AGENTS_V0_TRACE_MODE` in the launch env has no effect on them and is refused |
| `REQUIRE_FAIL_MODES` | `0` | `1` (V3): the run refuses to start (exit 3, `results/modes-preflight.log`) unless `H6_MODE=fail`, H7–H10 not `warn`, `KIT_TRACE_MODE=fail`, the kit source is locked away from `AGENT_USER` (see `KIT_SOURCE_LOCK`), and every checkout passes `kit_installed_ok` (the `KIT_MANIFEST` when set, else `check-installed-kit.sh --expect-trace-mode fail`); each story checks main again before it starts |
| `KIT_SOURCE_LOCK` | `0` | `1`: the preflight checks the lock even without `REQUIRE_FAIL_MODES` (which implies it). Each of `KIT_SOURCE_PATHS` must be absent, or neither readable nor enterable by `AGENT_USER`, and no readable `*.sh` under `KIT_SCAN_ROOTS` may still hold a test-override block (kitfix-20261031-kit-source-lock) |
| `KIT_SOURCE_PATHS` | `$KIT $TEST_ROOT/calib/kit $HOME/kit-src` | the kit source copies to test (a local `KIT_URL` / `KIT_FIX_URL` is always added) |
| `KIT_SCAN_ROOTS` | `$HOME $TEST_ROOT /tmp` | where the preflight looks for readable unstripped kit scripts |
| `AGENT_USER` | the harness user | the OS user the agent runs as; as root the lock is tested with `runuser -u`, as any other user the preflight refuses |
| `KIT_MANIFEST` | unset | the manifest `scripts/kit-manifest.sh` wrote after `HASH-OK`, before the lock; `kit_installed_ok` then checks the installed scripts and hooks against it, with no kit source needed |
| `MAX_RESUMES_TOTAL` | 8 | failure resumes in one run; rows whose reason starts with `kit-update` (a planned kit update, D7 of kitfix-20261031) are not counted |

Stop conditions (the runner or `kit-fix.sh` refuses with exit 3 and writes the reason to `results/stop.txt`, which `summary.md` shows under **Stop condition**):
- **FIX-LIMIT**: any limit above is reached.
- **NO-PROGRESS**: the last two kit fixes of the same step ended with exactly the same failed checks.
- **RESTART-REQUIRED** with `RESUME_FALLBACK_TO_2=0`.
- A second agent retry of the same step is refused: treat that failure as KIT.

When a stop condition is hit: do not change a limit yourself, do not start a new run to get around it. Write the report (§8) and stop. Raising a limit is the owner's decision.

## 8. Records and report

Files you must leave (all under `$TEST_ROOT`):
- `results/summary.md`, `results.tsv`, `checks.tsv`, `fix-attempts.tsv`, `run.meta`, `triage.md`, `findings.md`, `kit-fixes.tsv` (if any kit fix), `harness-fixes.md` (if any harness fix), `stop.txt` (if stopped), `attempt-<k>/` folders;
- `kitfix/<fix id>.patch`, `.diffstat`, `.validate-<mode>.log`, and the fix clone `kitfix/agents-v0-kit` with the fix branch.

Report to the owner, in this order: final exit code and the summary table; each failure with its class and evidence; each kit fix (fix id, defect, files changed, validate mode, patch path, committed? pushed?, the diffstat); each harness or environment fix; the stop condition if any; and the list of decisions below that affected the run. Times in Asia/Manila.

## 9. Environment variables added for fix and resume

| Variable | Default | Meaning |
|---|---|---|
| `KIT_UPSTREAM` | `https://github.com/mdurana/agents-v0-kit.git` | where `kit-fix.sh start` clones the kit |
| `KIT_FIXES_DOC` | `refs/kit-fixes.md` | fixes doc inside the kit repository |
| `KIT_FIX_VALIDATE` | `auto` | `auto`, `quick` (`KIT_SKIP_APP_TEMPLATE_TEST=1`) or `full` (needs JDK 21) |
| `KIT_FIX_COMMIT` | `0` | `1` = commit the fix on the fix branch (owner only) |
| `KIT_FIX_PUSH` | `0` | `1` = push the fix branch (owner only; needs `KIT_FIX_COMMIT=1`) |
| `KIT_FIX_PATCH` | empty | resume: patch applied on `KIT_FIX_BASE` |
| `KIT_FIX_BASE` | the run's current kit commit | resume: base commit for `KIT_FIX_PATCH` (use the base sha `finish` prints) |
| `KIT_FIX_URL`, `KIT_FIX_REF` | `KIT_URL`, `KIT_REF` | resume: a pushed fix branch instead of a patch |
| `KIT_UPDATE_QUICK` | `1` | `1` = `install.sh --update --quick` when moving the workspace to a new kit |
| `RESUME_FALLBACK_TO_2` | `1` | `1` = restart from step 2 automatically when the compatibility check fails; `0` = stop |
| `MAX_FIX_ATTEMPTS_PER_STEP`, `MAX_FIX_ATTEMPTS_TOTAL`, `MAX_AGENT_RETRY_PER_STEP`, `MAX_RESUMES_TOTAL` | 2, 5, 1, 8 | §7 |
| `CHAIN_RESUME_IN_STORY` | `0` | `1` = resume the `--resume-from-story` story in-story (branch, worktree and approved phases kept), §5.8 |

All variables of `test-plan.md` §4 keep their meaning. Never put tokens or passwords in these files; a push uses the git credentials already set up on the box.

## 10. Decisions that still need Marlon

1. **Fixes doc location**: `refs/kit-fixes.md` in the kit repository. Keep, or another path?
2. **Validation mode for kit fixes**: `auto` (full when JDK 21 is present, otherwise quick). Require full before any commit?
3. **Workspace update mode**: `install.sh --update --quick` by default when a resume moves the workspace to the fixed kit. Use full validation there too (slower on every snapshot restore)?
4. **Automatic restart from step 2** when the compatibility check fails (`RESUME_FALLBACK_TO_2=1`), or stop and ask?
5. **Seed-only templates force a restart from step 2.** Conservative; a fix to a template used only for new stories (for example a requirements template) could resume at the failed step instead. Accept the conservative rule?
6. **Limits**: 2 kit fixes per step, 5 per run, 1 agent retry per step, 8 resumes per run.
7. **Agent retry before a kit fix**: one retry is required to tell an agent mistake from a kit defect. It costs one more agent run; skip it for failures a kit script clearly caused?
8. **Harness fixes by the operator**: the operator may change `scripts/` and `fixtures/` of this folder and resume (`--reason harness-fix`) as long as no check of a passed step changes. Allow, or require your review first?
9. **Harness commits in story worktrees**: moving the workspace to the fixed kit commits the refreshed kit files in `main` and in each kit-made worktree as `[harness commit]`. Accept, or update only `main`?
10. **Commit and push**: `KIT_FIX_COMMIT` and `KIT_FIX_PUSH` stay off unless you set them. Should a pushed fix branch also be the default kit (`KIT_FIX_REF`) for the next new run?
11. **Resume before the owner sees the fix**: by default the operator resumes with the uncommitted patch right after `finish` and reports the diff at the end. Prefer that the operator stops after `finish` until you review the diff (set `KIT_FIX_REVIEW=1` in a later version)?
