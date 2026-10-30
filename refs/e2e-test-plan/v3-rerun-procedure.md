# V3 rerun procedure: P1-E, P2-A, P2-F and P2-P on kit `kitfix-20261031`

Written 2026-10-31 (Asia/Manila) for the kitfix-20261031 branch, at Marlon's request (04:43; keep-branches 04:47). This is a procedure only: nothing here has been run. **Do not start a VM, a sign-in or an agent run without Marlon's go-ahead for that run.**

What V3 is (kitfix-plan V3, decision D5/D12): a short live rerun of the four chain stories that exposed kit or harness bugs in run-20261029-1629, each started from the END snapshot of the story before it, on the fixed kit and harness. About 1 h of agent time per story, so about 4-5 h in total plus setup.

| Segment | Story | Bug it exposed | Start from (old run snapshot) |
|---|---|---|---|
| 1 | P1-E | merge and branch after release | `S4-P1-D-END` |
| 2 | P2-A | empty intake turn, branch guard, clock at midnight | `S4-P1-E-END` |
| 3 | P2-F | AC count, Redis and S3 without containers | `S4-P2-E-END` |
| 4 | P2-P | frontend, quota and 5xx handling, AC count | `S4-P2-O-END` |

**Caveat (say it in every report):** each segment starts from a workspace whose earlier stories were built by older kits (`0aa3a43`, `cca2773`, `fc4b642`). Four stories on the new kit prove the fixes on those stories. They **cannot** support a single-version claim ("20/20 on one kit and harness"). That needs the full V4 rerun from P1-A.

**Story branches are kept** (Marlon, 2026-10-31 04:47, kitfix-20261031-keep-branches). No step below deletes or renames a `feature/*` or `maintain/*` branch, locally or on a remote. Setting a released worktree aside means moving its folder to trash and pruning the worktree record. The branch stays. The kit hooks block an agent from deleting one.

Short names: box folder `B=/workspace/kit-eval/linode-e2e-20261029`, VM run root `T=/home/e2e/agents-v0-e2e/run-20261029-1629`, `KS=/home/e2e/kit-src` (the kit and harness clone on the VM), `H=$KS/refs/e2e-test-plan`, `MAIN=$T/work/portal`. VM commands run from the box with `cd $B && timeout 60 /workspace/tools/pyvenv/bin/python vm.py run "<cmd>"` (as root). Use `vm.py put <box file> <vm path>` to copy files. Run anything that uses git, tmux or agy as `su - e2e -c '...'`. All times are Asia/Manila.

## 0. Before you start (box, read-only)

1. The branch to test is `kitfix-20261031` at `dd980e6` or later; this procedure was written with the commits after `dd980e6` (guard override, H8/H9 checks, keep-branches). Note the exact commit: `git -C <kitfix worktree> rev-parse HEAD` → `KITSHA`. Use the same commit for every segment.
2. The old run archive is `$B/archive/run-20261029-1629.tar.zst` (2.8 GB). Check it against `$B/archive/SHA256SUMS` (`cd $B/archive && sha256sum -c SHA256SUMS`, only the line for this file). Its `run-20261029-1629/snapshots/` has `S4-P1-D-END`, `S4-P1-E-END`, `S4-P2-E-END` and `S4-P2-O-END` (`.tgz`, `.kit`, `.state.env`), checksummed in `snapshots/SHA256SUMS`.
3. The Gemini quota has reset (the old run stopped on a 53 h quota at P2-P design). Marlon picks the model; by default it is the old run's `gemini-4-argon-medium` for every segment.
4. Offline tests pass on `KITSHA` (box): `sh scripts/validate-kit.sh` and the harness suites `bash refs/e2e-test-plan/tests/{test-classify,test-checks,test-rollback,sim-in-story-resume,test-guards}.sh`.

## 1. Fresh VM (only with Marlon's go-ahead; it costs money)

- Linode **4 GB** shared plan (Marlon's choice D12; the old run used 16 GB), region `sg-sin-2`, from image **`private/42212138`** (`agents-v0-e2e-20261029`, captured 2026-10-29 15:58, before any sign-in). Set a new root password when deploying. The image holds no credentials. See `$B/setup-log.md`.
- **No Docker** (as in the run): P0-A AC-4 stays DEGRADED, and the README Validity block must list it.
- 4 GB is tight. The agent turn runs `MAVEN_OPTS=-Xmx1536m`, the portable PostgreSQL and, for P2-P, Node. Before the first segment, check `free -m`. If there is no swap, add a 4 GB swap file (`fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`). Start a memory sampler (`while :; do printf '%s %s\n' "$(TZ=Asia/Manila date +%T)" "$(free -m | awk '/Mem:/{print $3}')"; sleep 30; done >> /root/memlog-v3.tsv &`), because the old "2.2 GB peak" figure has no log behind it.
- Sign-ins: Marlon signs agy in himself and places the Cursor key in `/home/e2e/.config/e2e-secrets.env` (mode 600), as on 2026-10-29. Never copy a token file from the box or the old VM. Never print the secrets file.

## 2. Put the fixed kit and harness on the VM (no token on the VM)

On the box, from the kitfix worktree: `git bundle create /workspace/kit-eval/kitfix-plan-20261031/kitfix-20261031.bundle kitfix-20261031`. Then:
```
vm.py put /workspace/kit-eval/kitfix-plan-20261031/kitfix-20261031.bundle /tmp/kitfix-20261031.bundle
vm.py run "chmod 644 /tmp/kitfix-20261031.bundle && su - e2e -c 'cd ~/kit-src && git status --porcelain | head -3; git fetch -q /tmp/kitfix-20261031.bundle kitfix-20261031:kitfix-20261031 && git checkout -q kitfix-20261031 && git rev-parse HEAD && git status --porcelain | wc -l'"
```
The printed HEAD must be `KITSHA`, and the status count must be 0. `$KS` is now both the kit source and the harness (`$H`). Never edit files there by hand.

## 3. Restore the segment's start point (once per segment)

Copy the archive to the VM once (`vm.py put $B/archive/run-20261029-1629.tar.zst /home/e2e/run-20261029-1629.tar.zst`; check its sha256 on the VM against the box value). For each segment:

1. If `$T` exists from an earlier segment, **rename it, never delete it**: `mv $T $T.v3-<previous story>-$(TZ=Asia/Manila date +%m%d-%H%M)`. Rename the old tmux session too, never kill it: `tmux rename-session -t e2e old-<story>`.
2. Extract a fresh copy as e2e: `su - e2e -c 'mkdir -p ~/agents-v0-e2e && cd ~/agents-v0-e2e && zstd -dc ~/run-20261029-1629.tar.zst | tar -xf -'` (install `zstd` with apt if it is missing). The run keeps its original path, so the absolute paths in its records still hold.
3. Check the four snapshots: `cd $T/snapshots && grep -E ' S4-(P1-D|P1-E|P2-E|P2-O)-END\.tgz$' SHA256SUMS | sha256sum -c`.
4. Move the old run's END snapshot **of the story you are about to run** aside, so the new one does not overwrite it: `mkdir -p $T/snapshots/old-run && mv $T/snapshots/S4-<ID>-END.* $T/snapshots/old-run/`.
5. Move the old run's leftovers aside (never delete): `d=$T/trash/v3-leftovers-$(TZ=Asia/Manila date +%Y%m%d-%H%M); mkdir -p $d; for f in HALT RUNNING status/pending-turn.json status/runner.pid; do [ -e $T/$f ] && mv $T/$f $d/; done`.
6. Restore the start snapshot with the harness's own function. It checks the checksum and moves the current `work/` into `$T/trash/`. `KIT_LABEL` is set to the snapshot's own label, so `restore` does not update the kit yet (that is step 4, on main only):
```
su - e2e -c 'set -u; PLAN=$HOME/kit-src/refs/e2e-test-plan; export RUN_ID=20261029-1629 TEST_ROOT=$HOME/agents-v0-e2e/run-20261029-1629
  set -a; . $TEST_ROOT/status/launch.env; set +a; export RUN_ID TEST_ROOT; . $PLAN/scripts/env.sh; . $PLAN/scripts/lib.sh
  S=<START, e.g. S4-P1-D-END>; KIT_LABEL="$(cat $SNAP/$S.kit)"; export KIT_LABEL; restore $S && load_state $SNAP/$S.state.env && save_state $TEST_ROOT/status/runner-state.env && git -C $MAIN log --oneline -1 && git -C $MAIN status --porcelain | wc -l'
```
   Main must be clean (count 0). Write down main's HEAD.

## 4. Main-only kit update to KITSHA (as done for `fc4b642` on 2026-10-30 06:39, "Option A")

The kit update goes **only into main**. The released stories' worktrees are set aside first, and their branches are kept. This is the method of `$B/kit-cca2773/` (`remove-released-worktrees.sh`, `kit-update-cca2773.sh`, `compat-checks.sh`, `record-and-snap.sh`), used before the P2-A and P2-E resumes. Copy those scripts into a new folder `$B/v3/`, change only these values, and run them in this order:

1. **Set aside the released worktrees** (`remove-released-worktrees.sh`): list them with `git -C $MAIN worktree list`. For each worktree, check that its branch is fully merged into main and that the worktree is clean. Then copy its git admin folder to `$T/trash/released-worktrees-<time>/admin/`, move the worktree folder into the same trash folder, and run `git -C $MAIN worktree prune -v`. **Branches stay**: the script's last list (`git branch`) must still show every `feature/*` branch. Stop if a branch is missing.
2. **Check out the new kit and update main** (`kit-update-cca2773.sh` with `KIT_FIX_URL=$KS KIT_FIX_REF=refs/heads/kitfix-20261031`, the expected sha set to `KITSHA`). `kit_checkout` moves `$T/kit` to `KITSHA` and appends `kit_sha`/`kit_label`/`kit_source` to `results/run.meta`. `kit_update_workspace` runs `install.sh --update --quick` (and `--allow-in-flight` if a state file is active) on every remaining worktree. Only main is left, and it gets one harness commit, `Update agents-v0 kit to <label> [harness commit]`. Stop if it prints `KIT-UPDATE-FAIL`.
3. **Compatibility checks** (`compat-checks.sh`): `validate-kit.sh --target $MAIN` (with `KIT_SKIP_APP_TEMPLATE_TEST=1`), `check-release-evidence.sh` and `released_ok` for P0-A and every released story, `merged_into_main` for each `feature/<slug>`, the program phases approved, `next-story.py map`, main clean, no MERGE_HEAD, and no branch or worktree for the story you are about to run. Every line must PASS (`ALL=PASS`). If `check-release-evidence.sh` prints `WARN: feature/<slug> not found`, a story branch is missing. That should not happen (branches are kept), so stop and restore the branch from its `Story-Tip` before going on.
4. **Verify the installed kit by hash (required):** every kit script and hook installed in main must be byte-identical to the branch. Run it as e2e, and read it all:
```
su - e2e -c 'M=$HOME/agents-v0-e2e/run-20261029-1629/work/portal; K=$HOME/kit-src; bad=0; n=0
  cmp_dir(){ for f in "$1"/*; do [ -f "$f" ] || continue; b=${f##*/}; n=$((n+1))
      if [ ! -e "$2/$b" ]; then echo "MISSING $2/$b"; bad=1
      elif [ "$(sha256sum < "$f")" != "$(sha256sum < "$2/$b")" ]; then echo "DIFF $2/$b"; bad=1; fi; done
    for g in "$2"/*; do [ -e "$1/${g##*/}" ] || echo "EXTRA $g (not in the kit; check it is pack-scan.sh or a project file)"; done; }
  cmp_dir $K/templates/.agents-v0/scripts $M/.agents-v0/scripts; cmp_dir $K/core/common/hooks $M/.agents/hooks
  echo "kit=$(git -C $K rev-parse --short=12 HEAD) installed=$(cat $M/.agents-kit-version) files=$n"; [ $bad = 0 ] && echo HASH-OK || echo HASH-FAIL'
```
   Go on only on `HASH-OK`, with `.agents-kit-version` naming `KITSHA` (first 12 characters). A `MISSING` line is acceptable only for a script that `install.sh` removes on purpose (`check-delivery-gate-local.sh` when there is no CI). Any other `MISSING` or `DIFF` line is a STOP. Save the output as `$T/results/v3-kit-hash-<ID>.txt`.
5. **Record and snapshot** (`record-and-snap.sh`): snapshot `S4-<START STORY>-END-KIT-<label>`, one `fix-attempts.tsv` row whose note **starts with `kit-update`**, so it is not counted against `MAX_RESUMES_TOTAL` (D7). Also one `kit_update_<k>=… worktrees_set_aside="…"` line in `run.meta`, with a note naming Marlon's approval of V3.

## 5. Launch env file for the segment

Copy `$T/status/launch.env` to `/home/e2e/launch-v3-<id>.env`, then set or add only these lines:
```
export KIT_URL=$HOME/kit-src KIT_REF=<KITSHA>
export RUN_ID=20261029-1629 TEST_ROOT=/home/e2e/agents-v0-e2e/run-20261029-1629
export RESUME_FROM=4 RESUME_REASON=harness-fix CHAIN_RESUME_FROM_STORY=<ID>
export CHAIN_RESUME_IN_STORY=0          # not an in-story resume: the story starts at intake on the new kit
export MAX_RESUMES_TOTAL=<counted rows of results/fix-attempts.tsv, without kit-update rows, + 1>
export AGENT_TZ=Asia/Manila
# fail modes for V3 (item 3, Marlon 2026-10-31): mismatches fail the story instead of being findings
export H6_MODE=fail
export AGENTS_V0_TRACE_MODE=fail
# H7/H8/H9 already default to fail; do not set H7_MODE/H8_MODE/H9_MODE=warn
export CHAIN_RESUME_NOTE="V3 rerun of <ID> on kit <KITSHA short> after a main-only kit update, approved by mdurana <date time>"
```
- `AGENTS_V0_TRACE_MODE` is read by the kit's `check-traceability.sh` **in the agent's own shell**. It must therefore come from the harness's launch environment, which `start-tmux.sh` loads with `set -a` into both the runner and the agy loop, so it reaches every agent command. The agent itself cannot set it: since kitfix-20261031-guard-override the hooks block any agent command that sets an `AGENTS_V0_*` variable, and H8 fails the story if an agent tries.
- Never set `AGENTS_V0_SKIP_BRANCH_GUARD`, `AGENTS_V0_SKIP_COMMIT_CHECK` or `AGENTS_V0_NOW` in a launch env. They are for kit fixtures only.
- `kit-fix` is refused for a story resume, which is why the kit was updated by hand in §4 and the reason here is `harness-fix`, as in resume 7 of the old run.
- Segment 2 (P2-A) only: start the launch so P2-A's approval turns cross 00:00 Asia/Manila, about 23:15.
- Check the file (`grep -n '^export' <file>`): exactly one line for each name above, no secret.

## 6. Launch, and stop after the story

```
vm.py run "su - e2e -c 'cd ~/kit-src/refs/e2e-test-plan && set -a && . ~/.config/e2e-secrets.env && set +a && bash scripts/start-tmux.sh ~/launch-v3-<id>.env'"
```
Within 3 minutes, check (read-only):
- `progress.log` has `RESUME attempt … reason=harness-fix`, `RESUME-FROM-STORY … <ID>`, `CHAIN-SKIP` for every story before `<ID>`, `STORY step 4 story <ID>`, then `TURN-START run=S4-<slug>-intake-1`;
- the runner and the agy loop have the fail modes. Print only these lines, never the whole environment: `for p in $(pgrep -u e2e -f 'scripts/(run-plan|agy-turn-loop)\.sh'); do tr '\0' '\n' < /proc/$p/environ | grep -cE '^(H6_MODE|AGENTS_V0_TRACE_MODE)=fail$'; done` must print `2` for each process. The summary's Limits line shows `H6_MODE=fail` at the end of the run.

**Stop after the story.** The chain goes on to the next story after `<ID>`. The harness has no per-story stop; follow-up: a `CHAIN_STOP_AFTER_STORY` flag. It does check for a `HALT` file before every story and between runs. So for segments 1-3, start a watcher. It writes `HALT` only after `<ID>` has passed every check and its END snapshot is saved (line ` SNAPSHOT S4-<ID>-END `, posted after H1-H9), so `<ID>` itself is never cut short. Before the launch, record where the log ends: `wc -l < $T/status/progress.log > $T/status/v3-start-line`. Save this as `/home/e2e/v3-stop-after.sh` (no secrets):
```
#!/usr/bin/env bash
# v3-stop-after.sh <ID>: write HALT once <ID>'s END snapshot is posted; give up if the run ends first
T=/home/e2e/agents-v0-e2e/run-20261029-1629; ID="$1"; L=$T/status/progress.log; n0=$(cat $T/status/v3-start-line)
while sleep 20; do
  new="$(tail -n +"$((n0 + 1))" "$L")"
  if grep -q " SNAPSHOT S4-$ID-END " <<<"$new"; then
    printf '%s V3 stop after %s (v3-rerun-procedure.md step 6, approved by mdurana)\n' "$(TZ=Asia/Manila date '+%F %T')" "$ID" > "$T/HALT"; exit 0; fi
  grep -q " RUN-END " <<<"$new" && exit 0
done
```
Start it as e2e: `su - e2e -c 'nohup bash ~/v3-stop-after.sh <ID> > ~/v3-stop-after-<ID>.log 2>&1 &'`. The run then ends with `RUN-END exit=2` (halted) before the next story starts, or after its first run. That story's partial work is not part of V3 and stays in the set-aside run root. Segment 4 (P2-P) is the chain's target, so the run ends there by itself and needs no watcher.

Do not kill the runner or agy yourself. A USAGE or AUTH HALT, a refusal (exit 3, `results/stop.txt`) or a failed story is a STOP: report it to Marlon. For a failed story, use the in-story resume (`$B/in-story-resume-procedure.md`; it is now part of the harness as `CHAIN_RESUME_IN_STORY=1`, with no diff to apply) only with his OK.

## 7. Pass bar (per story, from `results/checks.tsv` rows of `<ID>` in this attempt, `summary.md` and `progress.log`)

- **H1-H9, V1 and L1 PASS** for `<ID>`: H6 (AC count) and the T1-T6 traceability checks are in fail mode. H7 means no harness gate-commit fallback. H8 means no `AGENTS_V0_*` override. H9 means the gate commits are intact and in order intake < design < build < verify < release on `feature/<slug>`. For P2-P, also F1 (frontend changed, `npm run verify` passing).
- No `SEMI-SYNTHETIC` build label, no `GATE-COMMIT-MISSING`, no `GATE-CHAIN-BROKEN`, and no `FINDING H6`/`H8`/`H9`. No `TRACE WARN`: in fail mode a traceability gap refuses the approval, so a refusal the agent then fixed is fine if it is explained.
- `check-release-evidence.sh` for `<ID>` prints `OK` with no `WARN: feature/… not found`. `feature/<slug>` exists after the release and is never deleted.
- P2-A: the phase dates survive the midnight crossing, and `/v0-design` before the branch step is refused by the branch guard.
- `results/v3-kit-hash-<ID>.txt` says `HASH-OK`. The README Validity block lists DEGRADED only for `container` (no Docker), and it lists the kits of the kept stories (expected: see the caveat).

## 8. After each segment, and at the end

- Copy `$T/results/`, `$T/evidence/S4-<slug>-*`, `$T/status/progress.log`, `/root/memlog-v3.tsv` and the kit-hash file to the box under `/workspace/kit-eval/v3-<date>/<ID>/`. Then go to §3 for the next segment.
- Report to Marlon for each story: PASS/FAIL per check, the kit and harness commit, the start snapshot, the turns and time, any finding, and the trash paths. Repeat the caveat: four stories on the new kit, not a single-version result.
- After a clean V3, the planned follow-ups are: make `CHAIN_RESUME_IN_STORY=1` the default, keep the fail modes, add `CHAIN_STOP_AFTER_STORY`, and fast-forward `e2eplan-20261029` (only with Marlon's go-ahead; never force-push). Archive, sign out and delete the VM only with his go-ahead, in that order, as on 2026-10-30.
