#!/usr/bin/env bash
# env.sh — every setting of the plan. Source it; override any variable by exporting it first.
# No personal paths are hard-coded: everything derives from $HOME and $PLAN_DIR unless you export a value.
PLAN_DIR="${PLAN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${RUN_ID:=$(TZ=Asia/Manila date +%Y%m%d-%H%M)}"
: "${TEST_ROOT:=$HOME/agents-v0-e2e/run-$RUN_ID}"      # everything this run writes lives here (must not exist yet)
: "${KIT_URL:=https://github.com/mdurana/agents-v0-kit.git}"  # or a local clone path (read only)
#   The kit repo is private. HARNESS-FIX 2026-10-29 (VM): a machine without GitHub credentials (the Linode VM) uses a
#   git bundle made on a machine that has them: `git bundle create kit.bundle <branch>` there, copy it over, then
#   KIT_URL=/path/kit.bundle (or `git clone kit.bundle ~/kit-src` and KIT_URL=$HOME/kit-src). Both work for every clone below.
: "${KIT_REF:=tech-stacks-v4}"                         # branch, tag or commit; alternative: kitfix-20261022
: "${TOOLS_DIR:=$HOME/.local/agents-v0-tools}"         # user-folder installs (no root)
mkdir -p "$TOOLS_DIR" 2>/dev/null || TOOLS_DIR="$TEST_ROOT/tools"
: "${AGENT_DRIVER:=auto}"                              # auto | antigravity | cursor
: "${AGENT_BIN:=$(command -v agent 2>/dev/null || echo "$HOME/.local/bin/agent")}"
: "${AGY_BIN:=$(command -v agy 2>/dev/null || { [ -x "$HOME/.local/bin/agy" ] && echo "$HOME/.local/bin/agy"; } || echo "$HOME/.antigravity/bin/agy")}"
# HARNESS-FIX 2026-10-29 (VM): the official agy installer puts agy in ~/.local/bin, which a tmux window may not have on
#   PATH. AGY_BIN now also finds it there, and agy-turn-loop.sh uses AGY_BIN instead of a fixed /home/box path.
: "${AGY_MODEL:=}"                                      # model passed to agy by agy-turn-loop.sh (empty = agy default)
: "${AGENT_TURN_CMD:=bash $PLAN_DIR/scripts/agy-ipc-turn.sh}"  # Antigravity IPC turn bridge (subagent transcript -> stream-json)
: "${AGENT_MODEL:=grok-4.7-high}"
# resolve_driver: the ONE rule for AGENT_DRIVER=auto, used by both prereqs.sh and lib.sh (HARNESS-FIX 2026-10-28).
#   Before this fix, prereqs.sh picked Antigravity whenever AGENT_TURN_CMD was set (env.sh always sets it), while
#   lib.sh picked Cursor whenever the Cursor CLI was installed. On a machine with both, step 1 checked Antigravity
#   and the run then drove Cursor. Rule: an explicit AGENT_DRIVER wins; else Cursor if its CLI is installed;
#   else Antigravity. Set AGENT_DRIVER=antigravity to use Antigravity on a machine that also has Cursor CLI.
resolve_driver() {
  if [ "${AGENT_DRIVER:-auto}" != auto ]; then echo "$AGENT_DRIVER"
  elif [ -x "${AGENT_BIN:-}" ]; then echo cursor
  else echo antigravity; fi
}
: "${APPROVER:=mdurana}"
: "${PACK:=java}"                                      # stack pack the scripted architecture answer names
: "${PROFILE:=app}"                                    # bootstrap-greenfield.sh --profile
: "${ONBOARD_MODE:=bootstrap}"                         # bootstrap = greenfield install only; agent = also run /v0-onboard
: "${PG_HOME:=}"                                       # portable PostgreSQL 17; empty = auto-detect / install
: "${ODC_SRC:=}"                                       # optional prebuilt OWASP dependency-check data dir (has odc.mv.db)
: "${M2_REPO:=$HOME/.m2/repository}"
: "${ODC_DST:=$M2_REPO/org/owasp/dependency-check-data/9.0}"   # where dependency-check-maven 10.0.4 reads its DB
: "${ODC_FEED:=https://dependency-check.github.io/DependencyCheck_Builder/nvd_cache/}"  # keyless NVD mirror
: "${TURN_CAP:=3600}"            # seconds per agent turn (60 min)
# HARNESS-FIX 2026-10-29 (step 4): build turns of P1-A hit the old 1740 s cap twice (CAP, rc=124) while the agent was
#   still working. TURN_CAP is now 3600 s, and agy's own per-turn limit (AGY_TURN_TIMEOUT, used by agy-turn-loop.sh)
#   is 60 s shorter, so agy stops first and its transcript is still collected.
: "${AGY_TURN_TIMEOUT:=3540}"    # seconds agy-turn-loop.sh lets one agy turn run (keep < TURN_CAP)
: "${RUN_TIMEOUT:=7200}"         # seconds per agent run (all turns); P0-A uses RUN_TIMEOUT_P0A
: "${RUN_TIMEOUT_P0A:=14400}"
: "${STALL_SEC:=900}"            # no new output for this long = stalled turn
: "${HEARTBEAT_SEC:=1500}"       # status line at least this often (must stay <= 1800)
: "${POLL_SEC:=30}"
: "${MAX_TURNS:=12}"             # turns per run (prompt + scripted replies)
: "${MAX_ANSWERS:=3}"            # scripted answers per run
: "${MAX_RETRY_INFRA:=4}"        # fresh retries after a stall / infra error
# HARNESS-FIX 2026-10-29 (step 4): agy model streams drop ("The stream was interrupted", "streamGenerateContent: EOF").
#   Those are now INFRA (see classify in lib.sh) and retried up to 4 times with waits of 60, 120, 240, 240 s.
: "${INFRA_BACKOFF:=60 120 240}" # seconds to wait before retry 1, 2, 3...; the last value repeats
: "${MAX_RUNS_PER_STORY:=10}"    # phase runs per story before "stuck"
: "${ASK_MODE:=auto}"            # auto (from calibration) | allowlist | harness
: "${CONTINUE_AFTER_PROBE_FAIL:=0}"   # 1 = step 8 still runs when a step-7 probe failed
: "${JAIL_CMD:=}"                # optional wrapper: $JAIL_CMD <run-dir> <workspace> <agent argv...>
: "${STATUS_HOOK:=}"             # optional command that receives each status line on stdin
: "${REAL_DIRS:=}"               # space-separated repos that must stay byte-identical (checked every step)
: "${CURSOR_API_KEY:=}"          # preferred non-interactive auth for the agent CLI (never written to disk by the runner)
# HARNESS-FIX 2026-10-29 (frontend-chain scope): TARGET_SURFACE=frontend makes step 4 build the first story whose
#   Surface is "frontend", together with every story it depends on, in roadmap order, and the run stops after step 4.
#   Empty (the default) = the full plan, steps 0-8, exactly as before.
: "${TARGET_SURFACE:=}"
# LESSONS_CHECK=1 runs check L1 (check-lessons.sh) after every story release. Default: on in chain mode, else off.
if [ -n "$TARGET_SURFACE" ]; then : "${LESSONS_CHECK:=1}"; else : "${LESSONS_CHECK:=0}"; fi
export PLAN_DIR RUN_ID TEST_ROOT KIT_URL KIT_REF TOOLS_DIR AGENT_DRIVER AGENT_BIN AGY_BIN AGENT_TURN_CMD AGENT_MODEL APPROVER PACK PROFILE ONBOARD_MODE \
  PG_HOME ODC_SRC M2_REPO ODC_DST ODC_FEED TURN_CAP RUN_TIMEOUT RUN_TIMEOUT_P0A STALL_SEC HEARTBEAT_SEC POLL_SEC \
  MAX_TURNS MAX_ANSWERS MAX_RETRY_INFRA MAX_RUNS_PER_STORY ASK_MODE CONTINUE_AFTER_PROBE_FAIL JAIL_CMD STATUS_HOOK REAL_DIRS \
  AGY_MODEL AGY_TURN_TIMEOUT INFRA_BACKOFF TARGET_SURFACE LESSONS_CHECK
[ -z "$CURSOR_API_KEY" ] || export CURSOR_API_KEY
# Derived layout (do not change)
WORK="$TEST_ROOT/work"; MAIN="$WORK/portal"; KIT="$TEST_ROOT/kit"
EVID="$TEST_ROOT/evidence"; SNAP="$TEST_ROOT/snapshots"; RES="$TEST_ROOT/results"; STATUS_LOG="$TEST_ROOT/status/progress.log"
DISCOVERY_REL="user-requirements/Finance-Back-Office-Portal-Discovery-Requirements.md"
export WORK MAIN KIT EVID SNAP RES STATUS_LOG DISCOVERY_REL
[ -f "$TOOLS_DIR/tools.env" ] && . "$TOOLS_DIR/tools.env"
# HARNESS-FIX 2026-10-29 (VM): tools.env sets JAVA_HOME and TOOLS_PATH but not PATH. On Marlon's box ~/.bashrc set
#   JAVA_HOME, so it worked by accident; on a fresh VM nothing does. Put the user-folder tools first on PATH so every
#   process started from here (runner, agy-turn-loop.sh, agy and its shell commands) finds JDK 21, Node 22 and PG 17.
[ -z "${TOOLS_PATH:-}" ] || case ":$PATH:" in *":$TOOLS_PATH:"*) ;; *) export PATH="$TOOLS_PATH:$PATH";; esac
true
