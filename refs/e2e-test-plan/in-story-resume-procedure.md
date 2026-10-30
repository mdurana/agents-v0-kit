# Procedure: resume a failed chain story IN-STORY (from the phase that stopped), after ANY failure

STATUS: committed on kitfix-20261031 (2026-10-31, opt-in, fix-and-resume.md §5.8). Written as STAGED, NOT APPLIED for run-20261029-1629; the VM paths and hashes below are from that run. Approved by Marlon ("Sensei") by voice on 2026-10-30 at 21:14 Asia/Manila: every rerun of a failed story resumes from the phase that stopped, keeping the story's branch, worktree and approved phases, instead of rolling back and restarting from intake. This applies to any failure, not only quota.
Written 2026-10-30, 21:15–21:45 Asia/Manila, for run-20261029-1629 (Linode VM, user e2e, agy 1.4.11). While it was written, the live run (attempt 10, runner PID 723589, agy loop PID 723587, story P2-P) was only read. The live scripts were not touched.
Supersedes the generic parts of `quota-switch-procedure.md`, which now points here. The quota/credits case is §6 below.

Run every VM command from the box like this:
`cd /workspace/kit-eval/linode-e2e-20261029 && timeout 60 /workspace/tools/pyvenv/bin/python vm.py run "<cmd>"` (runs as root). Use `vm.py put <box file> <vm path>` to copy files. Use `su - e2e -c '...'` (or `su e2e -s /bin/bash -c 'bash -s ...' < file`) for anything git, tmux or agy, because git as root fails with "dubious ownership".
Short names: `T=/home/e2e/agents-v0-e2e/run-20261029-1629`, `H=/home/e2e/kit-src/refs/e2e-test-plan`, `R=/root/in-story-resume` (staging folder on the VM, root only), `ID=<failed chain story id, e.g. P2-P>`, `SLUG=<its slug from $T/results/chain.tsv>`, `WT=$T/work/portal-$SLUG`.

## 0. What the staged change does (in-story-resume-any-failure.diff)

**Files.**
- Box: `/workspace/kit-eval/linode-e2e-20261029/in-story-resume-any-failure.diff`, 157 lines, sha256 `36abac75…e73d324d`. It changes `scripts/run-plan.sh` and `scripts/lib.sh`.
- VM copies: `$R/in-story-resume-any-failure.diff`, `$R/proposed/scripts/{run-plan.sh,lib.sh}`, `$R/tests/` (probe-live.sh, sim.sh, apply-in-story-diff.sh).
- The diff is made against the live files as of 21:15:
  - run-plan.sh `6a6a22b2…f7b4`; after the diff `8b1eea21…815f`.
  - lib.sh `667df2e2…b202`; after the diff `f7cbc305…324d`.
- It supersedes `harness-in-story-resume.diff` (run-plan.sh only). That file is kept. Do not apply both; `apply-in-story-diff.sh` reverses the old one if it finds it applied.

**Behaviour.**
- The new env flag `CHAIN_RESUME_IN_STORY=1` stays opt-in. Every resume env file from now on sets it.
  - It works with every reason that `--resume-from-story` accepts: harness-fix, env-fix and agent-retry. kit-fix is refused for story resumes, as before.
  - If it is set without `CHAIN_RESUME_FROM_STORY`, it is ignored with a warning, so it is harmless in any env file.
- `chain_resume_prepare` (run-plan.sh) keeps the story's branch, worktree and approved phases. It refuses the resume (exit 3, `results/stop.txt`, details in `results/attempt-<k>/chain-resume-check.log`) when:
  - work/ is missing (a snapshot restore would wipe the story);
  - main is dirty or mid-merge;
  - the worktree is mid-merge;
  - the branch exists without a worktree;
  - the branch is already merged but the next phase is not local-release;
  - the next phase is DONE or STUCK, except for the pending-gate case below.
- Pending gate (new, lib.sh `in_story_pending_gate`, `drive_story`, `drive_run`): if the story's state is `awaiting_approval` for a gate the harness allows (intake, design, build, verify or release) that is not yet in approvedPhases, the first run sends that gate's scripted approval as turn 1.
  - The approval text comes from `fixtures/approvals.tsv`, with the gate's allowlist, an approvals.log row tagged `in-story-resume`, and the same `harness_complete` and release post-merge step as a normal gate.
  - One extra context line is added, because the approval goes into a new chat.
  - This only happens on the first run of the in-story story. Without the flag it is still `STUCK:awaiting_approval(<phase>) at run start`, exactly as before.
- Otherwise the first run is `/v0-<phase that stopped> <slug>` in a new chat, in the story's worktree.
- Bookkeeping:
  - fix-attempts.tsv rows have the same format as before (`<reason> (from story <ID>: <note>)`), so the `nres`, per-step and agent-retry limits count the same way.
  - run.meta gets ` in_story=<slug>`.
  - The progress.log RESUME-FROM-STORY line ends with `+ <ID> in-story (branch, worktree and approved phases kept)`.
  - Evidence dirs of the resumed story are still archived to `evidence/attempt-<k>/` (unchanged). The checks H1–H4 read main and git, not evidence. H5's self-approval/forbidden-command scan covers only the runs after the resume.
- `story_run`: if the kept branch is already merged (resume at local-release), F1's base `STORY_H0` is main before that merge.
- Unchanged: USAGE/AUTH, which still write HALT and stop the run (exit 2); `classify`; the gate-aware STALL/INFRA/CAP rule; the INFRA fresh retry from pre.tgz (a retry of an in-story approval run sends the approval again); agy-turn-loop.sh and start-tmux.sh.

**Limits.**
- `nres` = rows in `$T/results/fix-attempts.tsv`. `MAX_RESUMES_TOTAL` must be greater than that (10 rows now, so 11 for the next resume).
- `agent-retry` is limited to `MAX_AGENT_RETRY_PER_STEP=1` per step. All chain story resumes are step 4, so only one agent-retry is possible in this run without Marlon raising that limit.
- harness-fix and env-fix have no per-step limit.

## 1. Confirm that the run has stopped and nothing is alive (read-only)
```
vm.py run "T=/home/e2e/agents-v0-e2e/run-20261029-1629; cat \$T/HALT 2>/dev/null; grep -E ' (HALT|STUCK|FAIL|RUN-END|STEP-END|RETRY) ' \$T/status/progress.log | tail -6; tail -3 \$T/agy-driver/loop.log; ls -la \$T/RUNNING \$T/status/pending-turn.json 2>&1; pgrep -af '^bash [^ ]*/scripts/(run-plan|agy-turn-loop)\.sh'; pgrep -u e2e -af 'agy .*--output-format'; echo pgrep-done"
```
Go on only if:
- progress.log ends with `RUN-END … exit=1` (FAIL/STUCK) or `exit=2` (HALT);
- no `run-plan.sh`, `agy-turn-loop.sh` or agy turn process is listed.

Then classify the stop and pick the resume reason, following fix-and-resume.md §3:

| Stop | Reason | Model |
|---|---|---|
| HALT `USAGE in …` with a lasting quota/credits message | env-fix | **§6: switch to claude-sonnet-5-5-medium** |
| INFRA-GIVEUP, a network/agy outage, or a disk problem (fixed) | env-fix | keep current |
| Harness bug, fixed with Marlon's approval (its own diff applied *after* this one) | harness-fix | keep current |
| Agent mistake, not a kit defect (AGENT-ERROR, STUCK "no state progress", MAX-TURNS) | agent-retry (only 1 left in step 4) | keep current |

STOP and report to Marlon (do not kill, sign in or fix on your own) if:
- any harness process is still alive. Never kill the runner yourself.
- HALT says `AUTH`. Do not sign in or out.
- the failure is a kit defect (kit-fix). `--resume-from-story` refuses kit-fix, and an in-story resume cannot pick up a kit change mid-story.
- the reason is agent-retry and fix-attempts.tsv already has an agent-retry row for step 4.
- the cause is unclear.

## 2. Record the stop point (read-only)
```
vm.py put in-story-resume/tests/stop-point.sh /root/in-story-resume/tests/stop-point.sh    # if not there yet
vm.py run "su e2e -s /bin/bash -c 'cd /tmp && bash -s P2-P' < /root/in-story-resume/tests/stop-point.sh | tee /root/in-story-resume/stop-point-\$(TZ=Asia/Manila date +%Y%m%d-%H%M).txt"
```
(Replace `P2-P` with the failed story, normally the story named in the last `STORY step 4 story …` line of progress.log.) Write down `activePhase`/`activeStatus`, the last run id and turn, and the fix-attempts row count N.

## 3. Safety copy of the work tree (a copy; nothing moves)
```
vm.py run "su - e2e -c 'T=~/agents-v0-e2e/run-20261029-1629; d=\$T/trash/work-before-instory-resume-\$(TZ=Asia/Manila date +%Y%m%d-%H%M); mkdir -p \$d && tar -C \$T --exclude=node_modules --exclude=target -czf \$d/work.tgz work && sha256sum \$d/work.tgz > \$d/SHA256SUMS && ls -la \$d; df -h /home | tail -1'"
```
STOP if tar fails or the disk is nearly full.

## 4. Decide whether an in-story resume is possible
Continue only if all of these hold (the harness checks them again in `chain_resume_prepare` and refuses with exit 3 if not):
- `activeStatus` is one of:
  - `in_progress` or `blocked`;
  - empty (the next phase follows `lastApprovedPhase`);
  - `awaiting_approval` for intake, design, build, verify or release, with that phase not yet in approvedPhases (the scripted approval is sent first).
- `release` is not in approvedPhases. A released story is DONE: H-check failures after release need the §5.6 rollback, which is not an in-story resume.
- main is clean and has no MERGE_HEAD.
- The worktree has no MERGE_HEAD. If the branch exists, its worktree exists too.
- work/ is in place.

STOP and report to Marlon if any of these fails. Do not roll back on your own: a rollback is a restart, and he ordered resumes. The fallback to offer is the story-level resume with rollback (fix-and-resume.md §5.6 + §5.5, as for attempts 8–10), which reruns the story from intake.

## 5. Move leftovers aside (move to trash, never delete) and rename the old tmux session
```
vm.py run "su - e2e -c 'T=~/agents-v0-e2e/run-20261029-1629; d=\$T/trash/instory-resume-leftovers-\$(TZ=Asia/Manila date +%Y%m%d-%H%M); mkdir -p \$d; [ -e \$T/HALT ] && cp -p \$T/HALT \$d/HALT.copy; for f in HALT RUNNING status/pending-turn.json; do [ -e \$T/\$f ] && mv \$T/\$f \$d/\$(basename \$f) && echo moved \$f; done; ls -la \$d; tmux has-session -t e2e 2>/dev/null && tmux rename-session -t e2e old-run1629-\$(TZ=Asia/Manila date +%m%d-%H%M); tmux ls'"
```
- HALT is moved, so the runner has nothing to move into results/attempt-<k>. The halt record stays in progress.log and in this trash folder.
- RUNNING is normally removed by the runner's EXIT trap. It is moved here only if it was left over, and §1 already showed that no runner is alive.
- The old tmux session is renamed, never killed. start-tmux.sh refuses to start while a session named `e2e` exists.
- STOP if any `mv` fails.

## 6. Quota/credits stops only: switch the model to Claude Sonnet 5.5 (other failures: skip to §7)
Background (quota-switch-procedure.md §0):
- agy takes `--model` per turn from `AGY_MODEL` in the env file. Do not edit `~/.gemini/antigravity-cli/settings.json` and do not pass `--settings`.
- The id to use is `claude-sonnet-5-5-medium`.

Tiny test prompt (uses a little Claude quota):
```
vm.py run "su - e2e -c 'cd /tmp && timeout 120 agy --model claude-sonnet-5-5-medium --output-format stream-json -p \"Reply with exactly: sonnet-ok\" 2>&1 | grep -oE \"sonnet-ok|quota[^\\\"]{0,80}|RESOURCE_EXHAUSTED|credits[^\\\"]{0,60}\" | head -3'"
```
Go on only if it prints `sonnet-ok`. STOP if it shows quota, credits or RESOURCE_EXHAUSTED (Claude is out too). Do not try other models without Marlon's OK.
If the current env file already has `AGY_MODEL=claude-sonnet-5-5-medium` and Sonnet itself hit the quota, STOP and report.

## 7. Apply the staged harness change (only if not applied yet; only with no runner alive)
```
vm.py put in-story-resume-any-failure.diff /root/in-story-resume/in-story-resume-any-failure.diff
vm.py put harness-in-story-resume.diff /root/in-story-resume/harness-in-story-resume.diff
vm.py put in-story-resume/tests/apply-in-story-diff.sh /root/in-story-resume/tests/apply-in-story-diff.sh
vm.py run "R=/root/in-story-resume; sha256sum \$R/in-story-resume-any-failure.diff; cp \$R/in-story-resume-any-failure.diff \$R/harness-in-story-resume.diff /tmp/ && chmod 644 /tmp/in-story-resume-any-failure.diff /tmp/harness-in-story-resume.diff && su e2e -s /bin/bash -c 'bash -s /home/e2e/kit-src/refs/e2e-test-plan /tmp/in-story-resume-any-failure.diff /tmp/harness-in-story-resume.diff' < \$R/tests/apply-in-story-diff.sh | tee \$R/apply-\$(TZ=Asia/Manila date +%Y%m%d-%H%M).log"
```
What the script does:
- It refuses while a runner or agy loop is alive.
- It prints `ALREADY-APPLIED` (and does nothing) if both files already have the post-diff hashes.
- It refuses (`STOP`) if either file is neither the 21:15 live version nor, for run-plan.sh, the old-diff version. That means another fix changed it, and the diff must be re-made.
- It backs up to `scripts/run-plan.sh.bak-20261030-instory` and `scripts/lib.sh.bak-20261030-instory`. An existing backup is kept, never overwritten.
- If the old diff is applied, it reverses it first. Then it does a dry run, applies the diff, runs `bash -n` and checks the hashes.

Go on only on `APPLIED OK (hashes match)` or `ALREADY-APPLIED`. To undo, copy the `.bak-20261030-instory` files back.
- If this failure also needs its own harness fix (reason harness-fix), apply this diff first, then that fix. Record both in HARNESS-FIXES-20261029.md.
- After applying, update the HF section "STAGED 2026-10-30 … in-story resume" in `$H/HARNESS-FIXES-20261029.md`: change "NOT applied" to the apply time and hashes. Leave "NOT committed". No git commit or push.

Dry check (read-only) with the now-live lib.sh. It must print `OK   in-story resume would continue at /v0-<stopped phase>`, or `OK   in-story resume: <gate> already awaiting approval`:
```
vm.py run "su e2e -s /bin/bash -c 'cd /tmp && bash -s /home/e2e/kit-src/refs/e2e-test-plan/scripts' < /root/in-story-resume/tests/probe-live.sh"
```
(probe-live.sh has `CRS=P2-P` built in; for another story, edit that line in a copy.) STOP if it prints FAIL, or a phase different from the one recorded in §2.

## 8. Write the new env file
Copy the most recent launch env file. Change only these: the limit (to N+1, where N is the row count from §2), the reason, the story, the in-story flag and the note. For quota stops, also change the model line.
```
vm.py run "su - e2e -c 'cd ~ && SRC=\$(ls -t launch*.env | head -1) && N=\$(grep -c . ~/agents-v0-e2e/run-20261029-1629/results/fix-attempts.tsv) && NEW=launch-resume-p2p-instory-\$(TZ=Asia/Manila date +%m%d-%H%M).env && test ! -e \$NEW && echo src=\$SRC rows=\$N new=\$NEW && sed -e \"s/^export MAX_RESUMES_TOTAL=.*/export MAX_RESUMES_TOTAL=\$((N+1))/\" -e \"s/RESUME_REASON=[a-z-]*/RESUME_REASON=<REASON>/\" -e \"s/CHAIN_RESUME_FROM_STORY=[A-Z0-9-]*/CHAIN_RESUME_FROM_STORY=<ID>/\" -e \"/^export CHAIN_RESUME_NOTE=/d\" -e \"/^export CHAIN_RESUME_IN_STORY=/d\" \$SRC > \$NEW && cat >> \$NEW <<EOT
# --- resume \$((N+1)): in-story resume of <ID> after <failure> (in-story-resume-procedure.md); approved by Sensei (voice 2026-10-30 21:14) ---
export CHAIN_RESUME_IN_STORY=1
export CHAIN_RESUME_NOTE=\"<REASON>: <one-line failure summary>; in-story resume of <ID> from <phase> (branch, worktree, approved phases kept) per Sensei voice approval 2026-10-30 21:14; resume limit \$N -> \$((N+1))\"
EOT
grep -nE \"^export\" \$NEW'"
```
Replace `<REASON>` (env-fix, harness-fix or agent-retry), `<ID>`, `<failure>`, `<phase>` and the summary before running. Keep the note on one line, with no tab and no double quote inside.

**Quota stops only:** add `-e "s/AGENT_MODEL=[^ ]* AGY_MODEL=[^ ]*/AGENT_MODEL=claude-sonnet-5-5-medium AGY_MODEL=claude-sonnet-5-5-medium/"` to the sed, and mention `model gemini-4-argon-medium -> claude-sonnet-5-5-medium` in the note. For every other failure the model line is copied unchanged (if an earlier resume already switched to Sonnet, it stays Sonnet).

Check the printed lines, and STOP if any is wrong:
- exactly one `MAX_RESUMES_TOTAL=<N+1>`;
- `RESUME_FROM=4 RESUME_REASON=<reason> CHAIN_RESUME_FROM_STORY=<ID>`;
- `CHAIN_RESUME_IN_STORY=1`;
- one `CHAIN_RESUME_NOTE` line;
- an `AGENT_MODEL`/`AGY_MODEL` pair that is the same as before (or Sonnet for quota);
- `RUN_ID=20261029-1629 TEST_ROOT=…run-20261029-1629`;
- `TARGET_SURFACE=frontend STOP_AFTER_STEP=4`;
- no secret.

Edit the `# READY` comment lines at the top (date, reason). This is cosmetic.

## 9. Launch
```
vm.py run "su - e2e -c 'cd ~/kit-src/refs/e2e-test-plan && set -a && . ~/.config/e2e-secrets.env && set +a && bash scripts/start-tmux.sh ~/<new env file>'"
```
start-tmux.sh turns `RESUME_FROM`/`RESUME_REASON` into `--resume-from 4 --test-root $T --reason <reason>`. run-plan.sh reads `CHAIN_RESUME_FROM_STORY` and `CHAIN_RESUME_IN_STORY` from the environment. Never print the secrets file.

## 10. Check within the first 3 minutes (read-only)
```
vm.py run "T=/home/e2e/agents-v0-e2e/run-20261029-1629; k=\$(grep -c . \$T/results/fix-attempts.tsv); grep -E 'RESUME|RUN-START|CHAIN-SKIP|STORY|STOP|IN-STORY-GATE|TURN-START' \$T/status/progress.log | tail -8 | cut -c1-260; cat \$T/results/attempt-\$k/chain-resume-check.log; grep 'loop start' \$T/agy-driver/loop.log | tail -1; tail -3 \$T/agy-driver/loop.log; tail -1 \$T/results/fix-attempts.tsv | cut -c1-200; tail -1 \$T/results/run.meta | grep -o 'in_story=[^ ]*'"
```
Expected:
- `RESUME attempt <N+1> from step 4 reason=<reason>`.
- `RESUME-FROM-STORY … + <ID> in-story (branch, worktree and approved phases kept)`, and run.meta `in_story=<slug>`.
- chain-resume-check.log: `IN-STORY <slug> branch=<sha> worktree=<WT> … next=<phase>`, then `OK   in-story resume continues at /v0-<stopped phase>` (or `OK   in-story resume: <gate> already awaiting approval…`). No FAIL line.
- `CHAIN-SKIP` for every kept story before `<ID>`, then `STORY step 4 story <ID>`.
- First `TURN-START run=S4-<slug>-<stopped phase>-1 turn=1 ws=<WT>`. The phase must be the stopped one, **not intake** (unless the story really stopped in intake), and ws must be the story worktree, not work/portal.
- If a gate was pending: `IN-STORY-GATE run=S4-<slug>-<phase>-1 <phase> was awaiting approval at resume start`, and the run's approvals.log has a `turn-1 SENT gate=<phase> … in-story-resume` row.
- Quota branch: loop.log shows `loop start … model_arg=claude-sonnet-5-5-medium`. Other failures: the same model_arg as before.
- After the first turn: `TURN-END … class=NORMAL`.

STOP conditions (report to Marlon; do not kill anything without his OK; do not retry with other flags):
- `STOP …` / `resume refused` (exit 3): read `$T/results/stop.txt` and `attempt-<k>/chain-resume-check.log`. For `FIX-LIMIT`, the limit in the env file is wrong.
- The first turn is intake for a story that had already passed intake, or the run is in work/portal instead of the worktree.
- `STUCK … awaiting_approval … at run start` for the in-story story. The diff is not applied, or the flag is not set.
- The first turn is classed AGENT-ERROR, or loop.log shows `no transcript for conv` (with Sonnet, the stream format may differ). Report with the tails of the turn's `.agy.stderr`/`.agy.jsonl`.
- USAGE again (HALT): quota is out on this model too. Report and stop.

## 11. Report to Marlon
Send: the stop type and time, the stop point (phase/run/turn), the resume reason, the model (unchanged, or the switch to claude-sonnet-5-5-medium), the env file, the resume limit N → N+1, the attempt number, the phase the story resumed at (and whether a pending gate approval was sent), the trash paths (safety copy, leftovers) and the harness hashes. Give all times in Asia/Manila.

## Tests done while staging (2026-10-30 ~21:20 Asia/Manila; details in in-story-resume/tests/ on the box and in /root/in-story-resume on the VM)
- `bash -n` OK on both changed files.
- `patch --dry-run` against the live files: clean. Applied to copies, the result equals `$R/proposed`. Reverse dry run: clean.
- apply-in-story-diff.sh, run on copies:
  - pristine → `APPLIED OK`;
  - old diff applied → old diff reversed, then `APPLIED OK`;
  - already applied → `ALREADY-APPLIED`;
  - with the live runner alive → `STOP` (nothing changed).
- Read-only probe of the live P2-P state at 21:21: build in_progress, approvedPhases [intake, design]; next=build → `OK   in-story resume would continue at /v0-build`; no pending gate; main 7aaafe2 clean, no MERGE_HEAD; branch not merged; 10 fix-attempts rows.
- Sandbox simulation (`$R/sim`, 21 checks on the staged files, all PASS; 2 checks on the live files confirm the old behaviour):
  - flag off still refuses a kept branch;
  - flag on accepts in_progress and a pending gate;
  - flag on refuses an already-approved pending gate, a worktree MERGE_HEAD, a missing work/ (no restore) and a dirty main;
  - without in-story, a pending gate is still STUCK;
  - in-story with a pending build gate: turn 1 = `Approved by mdurana, commit it` with `Shell(git:commit*)`, an approvals.log row, the self-approval guard satisfied, harness_complete committed the pending files, then verify → local-release → DONE;
  - in-story with design in_progress: turn 1 = `/v0-design`;
  - in-story with a pending gate and a USAGE first turn: HALT, 1 turn, story stops;
  - in-story with a pending gate and an INFRA first turn: retry from pre.tgz re-sends the approval;
  - in-story with a pending release gate: release text + merge allowlist, harness_complete merged the branch, DONE.
