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

Short names: box folder `B=/workspace/kit-eval/linode-e2e-20261029`, VM run root `T=/home/e2e/agents-v0-e2e/run-20261029-1629`, `KS=/home/e2e/kit-src` (the kit and harness clone on the VM), `H=$KS/refs/e2e-test-plan`, `MAIN=$T/work/portal`, `HV=/opt/harness-v3` (the root-owned harness copy the run starts from once the kit source is locked, §4 step 7), `E=/opt/harness-v3-env` (root-owned: the launch env file, the secrets copy and the escalation and startup-file records, §4 step 9), `L=/root/kit-locked` (where the kit source goes, root only). VM commands run from the box with `cd $B && timeout 60 /workspace/tools/pyvenv/bin/python vm.py run "<cmd>"` (as root). Use `vm.py put <box file> <vm path>` to copy files. Run anything that uses git, tmux or agy as `su - e2e -c '...'`. All times are Asia/Manila.

## 0. Before you start (box, read-only)

1. The branch to test is `kitfix-20261031` at the commit after `6930df2` whose message ends `Approved by Marlon 2026-10-31 13:40 Asia/Manila` (tools-root, state-file, ws-exec), or later (`git log --oneline --grep '13:40 Asia/Manila' kitfix-20261031`). This procedure needs all six of the latest fixes: installed scripts read no `AGENTS_V0_*` override and the trace mode comes from `.agents-v0/policy.conf` (`7bb4d31`); the kit-source lock, `kit-manifest.sh` and `KIT_MANIFEST` (`8f33ed3`, §4 steps 6–8); the bundle and kit-repository checks behind `LOCK git scan ok` (`251bd72`, §2, §4 step 8, §6); the root-owned `/opt/harness-v3` copy, `harness_locked` (`HARNESS ok`), the `MODES-EARLY` preflight with refused launches not counted, and the escalation blocks (`a31b0f6`, §4 step 7, §5, §6); the escalation check, the startup-file record and the clean `env -i runuser` launch (`6930df2`, §4 step 9, §5, §6); and the root-owned toolchain and agy, the state file read without `eval` and the fail-closed turn wrapper (the 13:40 commit, §4 step 10, §5). Earlier commits on the branch add guard override, H8/H9 and keep-branches. Note the exact commit: `git -C <kitfix worktree> rev-parse HEAD` → `KITSHA`. Use the same commit for every segment.
2. The old run archive is `$B/archive/run-20261029-1629.tar.zst` (2.8 GB). Check it against `$B/archive/SHA256SUMS` (`cd $B/archive && sha256sum -c SHA256SUMS`, only the line for this file). Its `run-20261029-1629/snapshots/` has `S4-P1-D-END`, `S4-P1-E-END`, `S4-P2-E-END` and `S4-P2-O-END` (`.tgz`, `.kit`, `.state.env`), checksummed in `snapshots/SHA256SUMS`.
3. The Gemini quota has reset (the old run stopped on a 53 h quota at P2-P design). Marlon picks the model; by default it is the old run's `gemini-4-argon-medium` for every segment.
4. Offline tests pass on `KITSHA` (box): `sh scripts/validate-kit.sh` and the harness suites `bash refs/e2e-test-plan/tests/{test-classify,test-checks,test-rollback,sim-in-story-resume,test-guards}.sh`.

## 1. Fresh VM (only with Marlon's go-ahead; it costs money)

- Linode **4 GB** shared plan (Marlon's choice D12; the old run used 16 GB), region `sg-sin-2`, from image **`private/42212138`** (`agents-v0-e2e-20261029`, captured 2026-10-29 15:58, before any sign-in). Set a new root password when deploying. The image holds no credentials. See `$B/setup-log.md`.
- **No Docker** (as in the run): P0-A AC-4 stays DEGRADED, and the README Validity block must list it. On the V3 VM, e2e must also have no Docker access at all (no `docker` group, no Docker socket, nothing on 2375/2376) and no way to become root; §4 step 9 checks this as root.
- **Supervised vs unattended (Marlon 2026-10-31 13:25).** The no-Docker and no-sudo rules of this procedure are for **unattended** agent runs: this VM, where nobody watches the agent and every approval is scripted. They are not rules for people using the kit. A developer working with the kit in a supervised environment may use Docker, and sudo on their own machine, as usual. The kit hooks only see the agent's own tool calls, never what a person types in a terminal. What the hooks do to an *agent* command, by mode:
  - **Both modes:** `sudo`, `doas` and `run0` (in any spelling) are blocked. So is pointing a client at the Docker API over TCP on `localhost:2375` / `127.0.0.1:2375`. When the agent needs root, it asks and the person runs the command.
  - **Both modes, allowed:** the `docker`, `docker compose` and `podman` commands. The kit's local container run and Testcontainers use them. On this VM they fail only because Docker is not installed.
  - **Unattended only:** `su` and `pkexec` are blocked. Attended, the hook allows them, and the operating system asks the person for the password.
- 4 GB is tight. The agent turn runs `MAVEN_OPTS=-Xmx1536m`, the portable PostgreSQL and, for P2-P, Node. Before the first segment, check `free -m`. If there is no swap, add a 4 GB swap file (`fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`). Start a memory sampler (`while :; do printf '%s %s\n' "$(TZ=Asia/Manila date +%T)" "$(free -m | awk '/Mem:/{print $3}')"; sleep 30; done >> /root/memlog-v3.tsv &`), because the old "2.2 GB peak" figure has no log behind it.
- Sign-ins: Marlon signs agy in himself and places the Cursor key in `/home/e2e/.config/e2e-secrets.env` (mode 600), as on 2026-10-29. Never copy a token file from the box or the old VM. Never print the secrets file.

## 2. Put the fixed kit and harness on the VM (no token on the VM)

On the box, from the kitfix worktree: `git bundle create /workspace/kit-eval/kitfix-plan-20261031/kitfix-20261031.bundle kitfix-20261031`. Then:
```
vm.py put /workspace/kit-eval/kitfix-plan-20261031/kitfix-20261031.bundle /tmp/kitfix-20261031.bundle
vm.py run "chmod 644 /tmp/kitfix-20261031.bundle && su - e2e -c 'cd ~/kit-src && git status --porcelain | head -3; git fetch -q /tmp/kitfix-20261031.bundle kitfix-20261031:kitfix-20261031 && git checkout -q kitfix-20261031 && git rev-parse HEAD && git status --porcelain | wc -l'; install -d -m 700 -o root -g root /root/kit-incoming && mv /tmp/kitfix-20261031.bundle /root/kit-incoming/ && chown root:root /root/kit-incoming/kitfix-20261031.bundle && chmod 600 /root/kit-incoming/kitfix-20261031.bundle && ls -la /root/kit-incoming"
```
The printed HEAD must be `KITSHA`, and the status count must be 0. **The bundle holds the whole kit, test-override blocks included (kitfix-20261031-kit-git-source).** It is readable by e2e only for the one fetch above, with no agent running. The same command moves it into the root-only `/root/kit-incoming/` (moved, never deleted), and the lock (§4 step 8) moves that folder into `$L`. Never leave a bundle, clone or mirror of the kit in `/tmp` or in e2e's home: the preflight refuses to start if e2e can read one (§5). `$KS` is now both the kit source and the harness (`$H`). Never edit files there by hand.

## 3. Restore the segment's start point (once per segment)

Copy the archive to the VM once (`vm.py put $B/archive/run-20261029-1629.tar.zst /home/e2e/run-20261029-1629.tar.zst`; check its sha256 on the VM against the box value). For each segment:

1. If `$T` exists from an earlier segment, **rename it, never delete it**: `mv $T $T.v3-<previous story>-$(TZ=Asia/Manila date +%m%d-%H%M)`. Rename the old tmux session too, never kill it: `tmux -L e2e-harness rename-session -t e2e old-<story>` as e2e (plain `tmux rename-session -t e2e old-<story>` for a session started before kitfix-20261031-launch-env).
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
4. **Verify the installed kit by hash (required):** every kit script and hook installed in main must be byte-identical to the branch, with the test-only override code removed. The kit's own checker does this read-only, comparing against the stripped kit files:
```
su - e2e -c 'M=$HOME/agents-v0-e2e/run-20261029-1629/work/portal; sh $HOME/kit-src/scripts/check-installed-kit.sh $M; echo "installed=$(cat $M/.agents-kit-version)"' | tee /tmp/v3-kit-hash.txt
```
   Go on only on `HASH-OK files=<n> …`, with `.agents-kit-version` naming `KITSHA` (first 12 characters). Any `DIFF`, `MISSING`, `TEST-OVERRIDES-INSTALLED`, `ENV-READ` or `MARKER-LEFT` line is a STOP. Copy the output to `$T/results/v3-kit-hash-<ID>.txt`. The trace mode is checked by the harness at launch (§5, §6).
5. **Record and snapshot** (`record-and-snap.sh`): snapshot `S4-<START STORY>-END-KIT-<label>`, one `fix-attempts.tsv` row whose note **starts with `kit-update`**, so it is not counted against `MAX_RESUMES_TOTAL` (D7). Also one `kit_update_<k>=… worktrees_set_aside="…"` line in `run.meta`, with a note naming Marlon's approval of V3.

**Install first, then lock (kitfix-20261031-kit-source-lock).** Steps 1–5 need the kit source and run as e2e. The agent also runs as e2e, and the kit source (`templates/.agents-v0/scripts`) still holds the test-override blocks that `install.sh` strips. A copy the agent can read could be run with a split-name override, whatever the hooks match. So after step 5, every kit copy goes where e2e cannot read it, and the harness refuses to start until that is true (`kit_source_locked` in the preflight).

6. **Write the manifest of the verified install** (as e2e, while the source is still readable). It is the hash list the harness checks main against once the source is locked:
```
su - e2e -c 'T=$HOME/agents-v0-e2e/run-20261029-1629; bash $HOME/kit-src/refs/e2e-test-plan/scripts/kit-manifest.sh $T/work/portal $T/results/kit-manifest-<ID>.tsv $HOME/kit-src'
```
   It writes only after `check-installed-kit.sh` says `HASH-OK`, and prints `kit-manifest: <n> files -> …`. Anything else is a STOP.
7. **Copy the harness out of the kit source, owned by root** (as root; kitfix-20261031-harness-lock). The harness (`refs/e2e-test-plan`) holds no kit script. The runner and the agent both run as e2e, so a harness copy e2e owns could be edited by the agent (for example `fixtures/approvals.tsv`, `scripts/agy-ws-exec.sh` or `scripts/lib.sh`) and would take effect at the next turn or launch. So the copy goes to `/opt/harness-v3`, owned by root and not writable by e2e; e2e can still read and run it:
```
vm.py run 'set -eu; HV=/opt/harness-v3; [ ! -e $HV ] || mv $HV $HV.old-$(TZ=Asia/Manila date +%m%d-%H%M)
  cp -r /home/e2e/kit-src/refs/e2e-test-plan $HV; git -C /home/e2e/kit-src rev-parse --short=12 HEAD > $HV/HARNESS-FROM
  echo "V3 harness copy: the preflight runs v3_launch_ok (kitfix-20261031-launch-env)" > $HV/V3-REQUIRED
  chown -R root:root $HV; chmod -R go-w,a+rX $HV; ls -ld /opt $HV $HV/scripts
  su - e2e -c "test ! -w /opt/harness-v3/scripts/lib.sh && test ! -w /opt/harness-v3/fixtures && echo HARNESS-RO"'
```
   It must print `HARNESS-RO`. `V3-REQUIRED` marks the copy as V3. With it, every launch from this copy needs `REQUIRE_FAIL_MODES=1` and passes `v3_launch_ok` (§5), whatever the env file says. The e2e user cannot remove the marker, because the folder is root's. `/opt` must be owned by root and not writable by e2e (the default), so e2e cannot rename the copy away and put its own in its place. Old copies stay as `/opt/harness-v3.old-<time>` (nothing is deleted). The run starts from `$HV` (§6). The harness process itself still runs as e2e, not as root with the agent under `runuser -u e2e`: a root runner would run agent-written code (`./mvnw verify`, the kit scripts, `npm`) as root and leave root-owned files in the project, which needs its own audit and a VM test first (follow-up). So the runtime state under `$T` (`status/`, `results/`, `evidence/`, `run-*/`) stays writable by e2e; see the limits in §5.
8. **Lock the kit source (as root).** Move every kit copy e2e could read into `$L` (mode 700, owned by root). Moving keeps everything and deletes nothing, and e2e cannot `chmod` it back:
```
vm.py run 'set -eu; T=/home/e2e/agents-v0-e2e/run-20261029-1629; L=/root/kit-locked/$(TZ=Asia/Manila date +%Y%m%d-%H%M); install -d -m 700 -o root -g root /root/kit-locked "$L"
  mv /home/e2e/kit-src "$L/kit-src"; [ ! -e $T/kit ] || mv $T/kit "$L/run-kit"; [ ! -e $T/calib ] || mv $T/calib "$L/calib"
  mkdir -p "$L/trash"; for f in $T/trash/* $T/snapshots/old-run /home/e2e/agents-v0-e2e/run-20261029-1629.v3-* /home/e2e/run-20261029-1629.tar.zst; do [ ! -e "$f" ] || mv "$f" "$L/trash/"; done
  for f in $T/snapshots/*.tgz; do chown root:root "$f"; chmod 600 "$f"; done   # old installs inside; the harness only tests that they exist
  [ ! -e /root/kit-incoming ] || mv /root/kit-incoming "$L/incoming"   # the delivery bundle (§2)
  mkdir -p "$L/bundles"; find /tmp /home/e2e -xdev -type f -name "*.bundle" -print 2>/dev/null | while IFS= read -r f; do mv --backup=numbered "$f" "$L/bundles/"; done
  ls -la "$L" "$L/trash" "$L/bundles"'
```
   **Bundles, clones and mirrors (kitfix-20261031-kit-git-source):** a git bundle, clone or mirror of the kit holds the unstripped scripts in its objects, where the `*.sh` scan cannot see them, and `git clone`/`git fetch`/`git show` would bring them back. So the lock also moves the delivery bundle (`/root/kit-incoming`, §2) and any other `*.bundle` under `/tmp` and `/home/e2e` into `$L`. `~/kit-src` and `$T/kit` are kit clones and are moved above. If you made any other kit clone or mirror for delivery (for example a `kit-mirror.git`), move it into `$L/trash/` too. Never delete one.
   The old snapshot archives stay in place but become root-only: a chain resume in V3 restores nothing (main was updated in place in step 2) and only checks that the previous END snapshot exists. New snapshots the run writes are e2e's, as before. Check the lock as e2e: `su - e2e -c 'test ! -r ~/kit-src && test ! -e ~/kit-src && echo LOCKED'`. The launch preflight (§6) checks it again, together with a scan of `$HOME`, `$T` and `/tmp` (plus any `KIT_SCAN_ROOTS`) for any readable `*.sh` that still has a test-override block, any readable `*.bundle`, and any readable git repository or bare repository whose objects hold the kit.
   **When the harness itself needs the kit source** (a kit update, `install.sh --update`, `validate-kit.sh --target`, a kit-fix resume, `check-installed-kit.sh`):
   - **Read-only checks:** run them as root against the locked copy, with no run going, e.g. `sh $L/kit-src/scripts/check-installed-kit.sh --expect-trace-mode fail $MAIN`.
   - **Anything that writes into the project** (install, update), so the files stay e2e's:
     1. stop the run (`HALT`, wait for `HALTED`);
     2. as root, move `$L/kit-src` back to `/home/e2e/kit-src`;
     3. as e2e, do steps 2–6 again, and step 7 as root;
     4. as root, lock again (step 8) and record again (step 9);
     5. launch again. The preflight refuses if a copy is left readable.
   - **Never** give e2e read access to the locked folder while an agent can run.

9. **Escalation check, startup-file record and secrets copy (as root; kitfix-20261031-escalation-none, kitfix-20261031-launch-env).** Run it after step 8, and again before every relaunch. It writes the records to the root-owned `$E`, where the preflight checks them:
```
vm.py run 'set -eu; E=/opt/harness-v3-env; HV=/opt/harness-v3; t=$(TZ=Asia/Manila date +%m%d-%H%M)
  install -d -m 755 -o root -g root $E; for f in $E/escalation-check.txt $E/e2e-home.sha256; do [ ! -e $f ] || mv $f $f.old-$t; done
  bash $HV/scripts/escalation-check.sh --record $E/escalation-check.txt e2e
  bash $HV/scripts/home-hash.sh --record $E/e2e-home.sha256 /home/e2e
  install -o root -g e2e -m 640 /home/e2e/.config/e2e-secrets.env $E/e2e-secrets.env; ls -la $E'
```
   - The last escalation line must be `ESCALATION-NONE user=e2e … mode=full`. These checks run:
     - `sudo -l -U e2e` lists no rule;
     - `id -nG e2e` has none of `sudo`, `wheel`, `admin`, `docker` or `lxd`;
     - no line of `/etc/doas.conf` (if present) names e2e or its groups;
     - no polkit rule (`rules.d`, `localauthority`) names e2e or its groups;
     - there is no `/var/run/docker.sock`, `/run/docker.sock` or `/run/user/<uid>/docker.sock`;
     - nothing listens on TCP 2375 or 2376.
   - **Any `ESC … HIT` line, or `ESCALATION-FOUND`, is a STOP: do not launch.** Report the line to Marlon. Never remove the access yourself.
   - `HOME-HASH recorded <n> files` lists e2e's startup files with their sha256: `.profile`, `.bashrc`, `.bash_profile`, `.tmux.conf`, `.gitconfig`, `.config/e2e-secrets.env`, `.local/agents-v0-tools/tools.env` and the others in `home-hash.sh`. Absent files are recorded as absent.
   - The secrets copy is root-owned. e2e can read it (the run needs the key) but cannot change it.
   - At launch, the preflight needs both records root-owned and newer than `$HV/HARNESS-FROM`. It needs `ESCALATION-NONE` for e2e, the live part of the escalation check (groups, sockets, listeners) passing again, and e2e's startup files matching the record.

10. **Root-owned toolchain and agy (as root, once, before the first segment; kitfix-20261031-tools-root).** `setup-vm.sh` installs the JDK, Node, PostgreSQL, `tools.env` and agy in e2e's home, where e2e (and so the agent) can change them. Copy them to `/opt/agents-v0-tools`, owned by root, **before any agent has run on this VM**. Never copy them again from e2e's home later: after a turn, what is there may have been changed.
```
vm.py run 'set -eu; O=/opt/agents-v0-tools; S=/home/e2e/.local/agents-v0-tools; t=$(TZ=Asia/Manila date +%m%d-%H%M)
  [ ! -e $O ] || mv $O $O.old-$t
  install -d -m 755 -o root -g root $O; cp -a $S/. $O/; install -d -m 755 $O/bin
  install -m 755 "$(readlink -f /home/e2e/.local/bin/agy)" $O/bin/agy
  sed -i -e "s#$S#$O#g" -e "s#/home/e2e/.local/bin#$O/bin#g" $O/tools.env
  chown -R root:root $O; chmod -R go-w,a+rX $O
  ! grep -n /home/e2e $O/tools.env; cat $O/tools.env
  runuser -u e2e -- env -i HOME=/home/e2e PATH=/usr/bin:/bin $O/bin/agy --version'
```
   - `tools.env` in `/opt` must name only `/opt/agents-v0-tools` paths (the `grep` prints nothing), and `agy --version` must work as e2e. If agy is a launcher that needs files next to it, it fails here: STOP and report to Marlon (do not point `AGY_BIN` back at e2e's home).
   - The env file (§5) sets `TOOLS_DIR=/opt/agents-v0-tools` and `AGY_BIN=/opt/agents-v0-tools/bin/agy`. agy's sign-in and settings stay in `~/.gemini` (e2e's).
   - In V3 or unattended mode (`V3-REQUIRED` or `REQUIRE_FAIL_MODES=1`), `env.sh`, the runner's step 1, `agy-turn-loop.sh` and `agy-ws-exec.sh` load no `tools.env` that e2e can write, and the turn loop refuses an `AGY_BIN` that is unset, under `$HOME` or writable (no `PATH` or `~/.local/bin/agy` fallback).

## 5. Launch env file for the segment

**The env file is root's (kitfix-20261031-launch-env).** e2e can write its own home, so a launch env, secrets file or dotfile there could switch off a check at the next relaunch, for example with `REQUIRE_FAIL_MODES=0`, a narrower `KIT_SCAN_ROOTS`, another `PLAN_DIR` or a `PATH` with a fake `git`. Write the file as root to `$E/launch-v3-<id>.env` (owner root, mode 644). Never copy `$T/status/launch.env` (e2e could have changed it): copy from it only the driver lines `AGENT_DRIVER`, `AGENT_MODEL`, `AGY_MODEL`, `TARGET_SURFACE` and `LANG`, after reading them. Then add exactly these lines:
```
export KIT_URL=$HOME/kit-src KIT_REF=<KITSHA>
export RUN_ID=20261029-1629 TEST_ROOT=/home/e2e/agents-v0-e2e/run-20261029-1629
export RESUME_FROM=4 RESUME_REASON=harness-fix CHAIN_RESUME_FROM_STORY=<ID>
export CHAIN_RESUME_IN_STORY=0          # not an in-story resume: the story starts at intake on the new kit
export MAX_RESUMES_TOTAL=<counted rows of results/fix-attempts.tsv, without kit-update and REFUSED rows, + 1>
export AGENT_TZ=Asia/Manila
# fail modes for V3 (item 3, Marlon 2026-10-31): mismatches fail the story instead of being findings
export H6_MODE=fail
export KIT_TRACE_MODE=fail          # the harness writes trace_mode=fail into .agents-v0/policy.conf (main + worktrees)
export REQUIRE_FAIL_MODES=1         # refuse to start unless every mode is fail, the kit source is locked and main matches the manifest
export KIT_MANIFEST=/home/e2e/agents-v0-e2e/run-20261029-1629/results/kit-manifest-<ID>.tsv   # §4 step 6
export AGENT_USER=e2e               # the user the agent runs as; the lock and the harness lock are tested as that user
export TOOLS_DIR=/opt/agents-v0-tools AGY_BIN=/opt/agents-v0-tools/bin/agy   # §4 step 10: root-owned, never e2e's home
export CONFIG_MODE=<config_mode> ASK_MODE=<ask_mode>   # the old run's calibration (results/calibration.txt in the fresh §3 copy); pins them
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin   # system folders only; env.sh puts the root-owned TOOLS_PATH first
# do NOT set KIT_SCAN_ROOTS, KIT_SOURCE_PATHS or HARNESS_LOCK_PATHS unless you add places: on V3 they must keep their defaults
# H7/H8/H9/H10 already default to fail; do not set H7_MODE/H8_MODE/H9_MODE/H10_MODE=warn
# do NOT set AGENTS_V0_TRACE_MODE: installed scripts ignore it, and the preflight refuses it
export CHAIN_RESUME_NOTE="V3 rerun of <ID> on kit <KITSHA short> after a main-only kit update, approved by mdurana <date time>"
```
- **How the trace mode reaches the kit (kitfix-20261031-installed-no-overrides):** the installed `check-traceability.sh` no longer reads any environment variable. It reads `trace_mode` only from `.agents-v0/policy.conf` in the checkout. Before each story, the harness (`kit_policy_apply`) writes that file from `KIT_TRACE_MODE` into main and every kit worktree, with one `[harness commit]` each. The agent cannot change it through the environment at all. The hooks block agent writes to the file, and H10 fails the story if the file, an installed script or a hook changed during a turn.
- `H6_MODE`, `H7_MODE` … `H10_MODE` are read only by the runner process, which the agent cannot reach. Never set the kit's test-only variables (`AGENTS_V0_SKIP_BRANCH_GUARD`, `AGENTS_V0_SKIP_COMMIT_CHECK`, `AGENTS_V0_NOW`, `AGENTS_V0_TZ`) in a launch env. Installed scripts ignore them anyway.
- **Kit source lock (kitfix-20261031-kit-source-lock):** with `REQUIRE_FAIL_MODES=1` (or `KIT_SOURCE_LOCK=1` on its own), the preflight (`kit_source_locked`) needs:
  - each of `$T/kit`, `$T/calib/kit`, `~/kit-src` and a local `KIT_URL`/`KIT_FIX_URL` to be absent, or neither readable nor enterable by `AGENT_USER`;
  - no readable `*.sh` with a test-override block under the scan roots;
  - no readable `*.bundle` under the scan roots (`LOCK READABLE git bundle for e2e: <path>`);
  - no readable git repository or bare repository under the scan roots whose objects hold the kit: a known kit root commit (`KIT_ROOT_COMMITS`, default `550da9d…` "agents-v0 version 0.0.1" and `fc4b642…`), or `templates/.agents-v0/scripts/sync-feature-state.sh` at HEAD, FETCH_HEAD or any branch or tag tip (`LOCK READABLE kit git repository for e2e: <git dir>`). The project's own repository passes: it holds the installed kit, never `templates/`, and its root is its own. When all is clean the log has `LOCK git scan ok: no readable *.bundle, <n> git dirs checked, none holds the kit`.

  **Scan roots:** `KIT_SCAN_ROOTS` (default `$HOME $TEST_ROOT /tmp`, i.e. `/home/e2e`, `$T` and `/tmp`). Set it only to add places (keep the defaults in the list), never to skip one. Set `KIT_SOURCE_PATHS` the same way. The scan is cheap: one `find` per root for each kind (build folders such as `node_modules`, `.m2`, `target` and `.npm` are skipped; at most 50 bundles and 500 git dirs), and two git calls per repository.
  
  With `KIT_MANIFEST` set, main and every worktree are compared with the manifest (`kit_installed_ok`), so the run needs no kit source. `KIT_URL` stays in the file for the record only. The run checks out no kit (`harness-fix`, not `kit-fix`).
- **Harness lock (kitfix-20261031-harness-lock):** with `REQUIRE_FAIL_MODES=1` (or `HARNESS_LOCK=1` on its own), the preflight (`harness_locked`) refuses unless `AGENT_USER` can write no file or folder in the harness (`$PLAN_DIR`, i.e. `/opt/harness-v3`: `scripts/`, `fixtures/`, the turn wrapper and the allowlist code) and no parent folder up to `/` lets that user rename it away (`HARNESS WRITABLE by e2e: …` or `HARNESS REPLACEABLE by e2e: …`). When clean, the log has `HARNESS ok /opt/harness-v3 (owner root, not writable or replaceable by e2e)`. `HARNESS_LOCK_PATHS` replaces the folders checked (tests only; never set it in a launch env). On top of that:
  - the runner hashes `scripts/` and `fixtures/` before and after every turn; any change is a `FINDING H10` and a `kit-tamper.txt` line;
  - the turn wrapper (`agy-ws-exec.sh`) refuses a command when `status/pending-turn.json` holds a different allowlist from the one the turn loop started agy with, and `agy-ipc-turn.sh` records any change to that file during a turn (`run-<k>/pending-tamper-<k>.txt`, also H10);
  - in unattended mode the hooks block agent writes to the harness (`/opt/harness-v3`, `~/harness-v3`, `$PLAN_DIR`), to `$T` outside `work/` (status and control files, results, evidence, run folders), and any setting or unsetting of `AGY_ALLOW_TOOLS` or `CURSOR_CONFIG_DIR` (a speed bump: the hooks only see commands they can parse).
- **Limits of the harness lock:** the runtime state under `$T` (outside `work/`) is still writable by e2e, because the runner is e2e. An agent that gets past the hooks could still fake a turn reply (`run-*/turn-<k>.done` and its response), edit `results/` or `status/` files, or forge evidence. H10 and the hashes catch changes to the harness itself and to the control file, not those. Closing that needs the runner as root with the agent under `runuser -u e2e` (follow-up, see step 7).
- **V3 launch checks (kitfix-20261031-launch-env; `v3_launch_ok`, run at every launch from a copy with `V3-REQUIRED`, even if the env file says `REQUIRE_FAIL_MODES=0`):** the preflight refuses (`V3 REFUSED …` in `modes-preflight.log`) unless:
  - `REQUIRE_FAIL_MODES=1`;
  - `PLAN_DIR` is the harness copy the run started from;
  - `HOME` is e2e's home;
  - `KIT_SCAN_ROOTS`, `KIT_SOURCE_PATHS` and `HARNESS_LOCK_PATHS` still hold all their defaults (they may only add places);
  - the tools the preflight runs (`git`, `find`, `stat`, `sha256sum`, `python3`, `jq`, `bash`, `tmux` and others) resolve to files e2e cannot write, in folders e2e cannot write;
  - e2e's startup files match `$E/e2e-home.sha256`;
  - `escalation_none_ok` passes (the step 9 record plus a live re-check);
  - (kitfix-20261031-tools-root) `TOOLS_DIR`, `AGY_BIN`, the launch env file and every `PATH` folder before the first system folder are out of e2e's reach: neither the file nor any parent folder up to `/` is writable by e2e (`V3 REFUSED TOOLS_DIR: …`, `V3 REFUSED AGY_BIN …`, `V3 REFUSED launch env file …`, `V3 REFUSED PATH …`). `AGY_BIN` must also be an absolute path outside `$HOME`, and `env.sh` must not have skipped a writable `tools.env` (`V3 REFUSED … was not sourced`).

  Clean: `V3 launch ok: …`, `V3 HOME-HASH-OK <n> files …` and `ESCALATION ok: …`. During the run, the per-turn harness hash (H10) also covers those startup files, so one written in a turn is a finding. `ESCALATION_CHECK=1` runs the escalation part without a V3 copy. `start-tmux.sh` starts its own tmux server (`tmux -L e2e-harness -f /dev/null`, which reads no `~/.tmux.conf`), so watch it with `tmux -L e2e-harness ls` / `attach -t e2e`.
- **The state file is data, not code (kitfix-20261031-state-file):** `load_state` (used for `status/runner-state.env` and the snapshot `.state.env` files, which e2e can write) no longer runs `eval`. It accepts only `NAME=value` lines whose name is in `STATE_VARS` (story ids, slugs, kit label and sha, the calibration modes) and whose value is a plain `printf %q` word. Anything else is skipped and logged as `STATE-SKIP` in `progress.log`, so it can never set `REQUIRE_FAIL_MODES`, a `*_MODE`, `NATIVE_VERIFY`, `MAX_RESUMES_TOTAL`, the lock and scan paths or `PATH`. `CONFIG_MODE` takes only `perturn` or `global`, `ASK_MODE` only `allowlist`, `harness` or `auto`, and a value the env file sets wins (`STATE-KEEP` when the file differs). A `STATE-SKIP` line in a V3 log means the state file was changed: report it.
- **The turn wrapper fails closed (kitfix-20261031-ws-exec):** `agy-ws-exec.sh` refuses (`HOOK DENIED (…)`, exit 2, logged in `agy-driver/ws-exec-denied.log`) a `--ws` without `.agents/hooks/pre-shell.sh`, a workspace outside `$TEST_ROOT/work`, a `--test-root` other than `TEST_ROOT`, a turn without `AGY_ALLOW_TOOLS` or `AGY_TURN_WS` (the turn loop now sets both), and a `pending-turn.json` whose allowlist or workspace differs from the turn's. In unattended mode the hooks also block `env -i`, `typeset`/`declare`/`export`/`readonly`/`local` on `AGY_ALLOW_TOOLS`, `CURSOR_CONFIG_DIR`, `AGY_TURN_WS` or `TEST_ROOT`, `unset` of a `$`-built name, and an `agy-ws-exec.sh` call whose `--ws` is outside `work/` or whose `--test-root` differs; for an allowed call they check the quoted command inside it as if run directly.
- **Limits of the launch checks:**
  - The JDK, Node, PostgreSQL and agy binaries are root-owned in `/opt/agents-v0-tools` (§4 step 10), but agy's settings and sign-in in `~/.gemini` are still e2e's. Whether agy's self-update works from a root-owned folder is untested; if it tries and fails, that is a finding, not a reason to point `AGY_BIN` back at e2e's home.
  - The runner can still be changed while it runs: a dotfile changed during a segment shows up as an H10 finding or at the next launch, not at once.
  - `CONFIG_MODE` and `ASK_MODE` can still be changed in the state file within their allowed values unless the env file sets them (it does, above).
  - The hooks only see commands they can parse: an indirect `env -u "$X"` is not caught.
- **A refused launch is not counted (kitfix-20261031-preflight-first):** the modes, lock, harness-lock and manifest checks now run first (`MODES-EARLY … OK` in `progress.log`), before any resume bookkeeping. A launch they refuse writes no `fix-attempts.tsv` row, archives nothing and creates no `attempt-<n>` folder, so you can fix the env file and launch again without raising `MAX_RESUMES_TOTAL`. If a later check still refuses after the row was written, that row is marked `REFUSED` (column 6) and is not counted.
- `kit-fix` is refused for a story resume, which is why the kit was updated by hand in §4 and the reason here is `harness-fix`, as in resume 7 of the old run.
- Segment 2 (P2-A) only: start the launch so P2-A's approval turns cross 00:00 Asia/Manila, about 23:15.
- Check the file (`grep -n '^export' <file>`): exactly one line for each name above, no secret.

## 6. Launch, and stop after the story

```
vm.py run "cd /opt/harness-v3 && env -i HOME=/home/e2e USER=e2e LOGNAME=e2e SHELL=/bin/bash LANG=C.UTF-8 PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin runuser -u e2e -- /bin/bash --noprofile --norc -c 'set -a; . /opt/harness-v3-env/e2e-secrets.env; set +a; exec /bin/bash --noprofile --norc /opt/harness-v3/scripts/start-tmux.sh /opt/harness-v3-env/launch-v3-<id>.env'"
```
This starts the run as e2e from a clean environment. No login shell runs, and no file e2e can write is sourced before the preflight: no `~/.profile`, `~/.bashrc`, `~/.tmux.conf`, old env file or secrets file in e2e's home. `tools.env` is read only from the root-owned `/opt/agents-v0-tools` (§4 step 10). Never launch with `su - e2e -c` once an agent has run: that is a login shell, and it re-sources e2e's dotfiles.
Within 3 minutes, check (read-only):
- `progress.log` has `RESUME attempt … reason=harness-fix`, `RESUME-FROM-STORY … <ID>`, `CHAIN-SKIP` for every story before `<ID>`, `STORY step 4 story <ID>`, then `TURN-START run=S4-<slug>-intake-1`;
- **the modes were verified before anything ran:** `progress.log` has `MODES-EARLY … OK (before any resume bookkeeping)` before the `RESUME attempt` line, and `MODES H6=fail H7=fail H8=fail H9=fail H10=fail trace=fail require_fail=1 lock=checked OK` before `RUN-START`. `results/modes-preflight.log` must have:
  - a `LOCK ok …` or `LOCK absent …` line for every kit source path;
  - `LOCK scan ok: …` and `LOCK git scan ok: …` (no `LOCK READABLE …` line);
  - `HARNESS ok /opt/harness-v3 (owner root, not writable or replaceable by e2e)` (no `HARNESS WRITABLE` or `HARNESS REPLACEABLE` line);
  - no `STATE-SKIP` line in `progress.log` (one means a state file was changed: STOP and report it);
  - `V3 launch ok: …` (it names `TOOLS_DIR`, `AGY_BIN`, the env file and `PATH` as out of reach), `V3 HOME-HASH-OK <n> files …`, `ESCALATION live: ESCALATION-NONE user=e2e … mode=live …` and `ESCALATION ok: …` (no `V3 REFUSED`, `HOME-CHANGED`/`HOME-ADDED`/`HOME-REMOVED` or `ESC … HIT` line);
  - an `OK portal: MANIFEST-OK files=<n> trace_mode=fail kit=<KITSHA short> …` line for main, and one for any kept worktree. If the preflight refused, the run stopped with exit 3 and `STOP modes refused …` in `results/stop.txt`: read `modes-preflight.log`, fix the env file, the install or the harness copy, and launch again (the refused launch counted nothing). Do not lower a mode;
- `POLICY trace_mode=fail in portal (…)` in `progress.log` at the first launch (later launches find the file already set), and `cat $MAIN/.agents-v0/policy.conf` shows `trace_mode=fail`. The summary's Limits line shows the modes at the end of the run.

**Stop after the story.** The chain goes on to the next story after `<ID>`. The harness has no per-story stop; follow-up: a `CHAIN_STOP_AFTER_STORY` flag. It does check for a `HALT` file before every story and between runs. So for segments 1-3, start a watcher. It writes `HALT` only after `<ID>` has passed every check and its END snapshot is saved (line ` SNAPSHOT S4-<ID>-END `, posted after H1-H10), so `<ID>` itself is never cut short. Before the launch, record where the log ends: `wc -l < $T/status/progress.log > $T/status/v3-start-line`. Save this as root as `/opt/harness-v3-env/v3-stop-after.sh` (owner root, mode 755, no secrets; e2e must not be able to change it):
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
Start it as e2e from a clean environment, as for the launch: `vm.py run "env -i HOME=/home/e2e USER=e2e LOGNAME=e2e PATH=/usr/local/bin:/usr/bin:/bin runuser -u e2e -- /bin/bash --noprofile --norc -c 'nohup /bin/bash /opt/harness-v3-env/v3-stop-after.sh <ID> > /home/e2e/v3-stop-after-<ID>.log 2>&1 &'"`. The run then ends with `RUN-END exit=2` (halted) before the next story starts, or after its first run. That story's partial work is not part of V3 and stays in the set-aside run root. Segment 4 (P2-P) is the chain's target, so the run ends there by itself and needs no watcher.

Do not kill the runner or agy yourself. A USAGE or AUTH HALT, a refusal (exit 3, `results/stop.txt`) or a failed story is a STOP: report it to Marlon. For a failed story, use the in-story resume (`$B/in-story-resume-procedure.md`; it is now part of the harness as `CHAIN_RESUME_IN_STORY=1`, with no diff to apply) only with his OK.

## 7. Pass bar (per story, from `results/checks.tsv` rows of `<ID>` in this attempt, `summary.md` and `progress.log`)

- **H1-H10, V1 and L1 PASS** for `<ID>`: H6 (AC count) and the T1-T6 traceability checks are in fail mode. H7 means no harness gate-commit fallback. H8 means no `AGENTS_V0_*` override typed by the agent (a text speed bump only). H9 means the gate commits are intact and in order intake < design < build < verify < release on `feature/<slug>`. H10 means the installed kit, hooks and `policy.conf` were not changed during any turn, and every gate in `<slug>.trace.json` was recorded in `fail` mode. For P2-P, also F1 (frontend changed, `npm run verify` passing).
- No `SEMI-SYNTHETIC` build label, no `GATE-COMMIT-MISSING`, no `GATE-CHAIN-BROKEN`, no `kit-tamper.txt`, and no `FINDING H6`/`H8`/`H9`/`H10`. No `TRACE WARN`: in fail mode a traceability gap refuses the approval, so a refusal the agent then fixed is fine if it is explained.
- `check-release-evidence.sh` for `<ID>` prints `OK` with no `WARN: feature/… not found`. `feature/<slug>` exists after the release and is never deleted.
- P2-A: the phase dates survive the midnight crossing, and `/v0-design` before the branch step is refused by the branch guard.
- `results/v3-kit-hash-<ID>.txt` says `HASH-OK`, `results/kit-manifest-<ID>.tsv` exists, and `modes-preflight.log` shows the lock (`LOCK ok`/`LOCK absent`, `LOCK scan ok`, `LOCK git scan ok`), `HARNESS ok`, `V3 launch ok`, `ESCALATION ok` and `MANIFEST-OK`. `$E/escalation-check.txt` of the segment ends with `ESCALATION-NONE user=e2e … mode=full`. The README Validity block lists DEGRADED only for `container` (no Docker), and it lists the kits of the kept stories (expected: see the caveat).

## 8. After each segment, and at the end

- Copy `$T/results/`, `$T/evidence/S4-<slug>-*`, `$T/status/progress.log`, `/root/memlog-v3.tsv` and the kit-hash file to the box under `/workspace/kit-eval/v3-<date>/<ID>/`.
- **Before anything else for the next segment, as root, check e2e's startup files against the record:** `bash /opt/harness-v3/scripts/home-hash.sh --check /opt/harness-v3-env/e2e-home.sha256 /home/e2e` must print `HOME-HASH-OK`. §2–§4 run `su - e2e -c` (a login shell that sources these files) before the next lock. So any `HOME-CHANGED`, `HOME-ADDED` or `HOME-REMOVED` line is a STOP. Report it to Marlon, and don't run any `su - e2e` command until he decides.
- Before §3 of the next segment, as root, move `$L/<time>/kit-src` back to `/home/e2e/kit-src` (owner e2e: `chown -R e2e:e2e`), and the archive `run-20261029-1629.tar.zst` back to `/home/e2e/`. §3 and §4 need them. Then go to §3 for the next segment, and do §4 steps 2–9 again (not step 10: keep the `/opt/agents-v0-tools` made before the first segment, never copy it again from e2e's home). Step 7 makes a fresh root-owned `/opt/harness-v3` from the kit source of that segment (the old copy is renamed, not deleted). Step 8 locks the kit source again before the launch. Step 9 records the escalation check and the startup files again, newer than the new copy. Write the next segment's env file as root in `$E` (§5), and launch with the clean-environment command of §6.
- Report to Marlon for each story: PASS/FAIL per check, the kit and harness commit, the start snapshot, the turns and time, any finding, and the trash paths. Repeat the caveat: four stories on the new kit, not a single-version result.
- After a clean V3, the planned follow-ups are: make `CHAIN_RESUME_IN_STORY=1` the default, keep the fail modes, add `CHAIN_STOP_AFTER_STORY`, and fast-forward `e2eplan-20261029` (only with Marlon's go-ahead; never force-push). Archive, sign out and delete the VM only with his go-ahead, in that order, as on 2026-10-30.
