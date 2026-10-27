#!/usr/bin/env bash
# env.sh — every setting of the plan. Source it; override any variable by exporting it first.
# No personal paths are hard-coded: everything derives from $HOME and $PLAN_DIR unless you export a value.
PLAN_DIR="${PLAN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${RUN_ID:=$(TZ=Asia/Manila date +%Y%m%d-%H%M)}"
: "${TEST_ROOT:=$HOME/agents-v0-e2e/run-$RUN_ID}"      # everything this run writes lives here (must not exist yet)
: "${KIT_URL:=https://github.com/mdurana/agents-v0-kit.git}"  # or a local clone path (read only)
: "${KIT_REF:=tech-stacks-v4}"                         # branch, tag or commit; alternative: kitfix-20261022
: "${TOOLS_DIR:=$HOME/.local/agents-v0-tools}"         # user-folder installs (no root)
mkdir -p "$TOOLS_DIR" 2>/dev/null || TOOLS_DIR="$TEST_ROOT/tools"
: "${AGENT_DRIVER:=auto}"                              # auto | antigravity | cursor
: "${AGENT_BIN:=$(command -v agent 2>/dev/null || echo "$HOME/.local/bin/agent")}"
: "${AGY_BIN:=$(command -v agy 2>/dev/null || echo "$HOME/.antigravity/bin/agy")}"
: "${AGENT_TURN_CMD:=bash $PLAN_DIR/scripts/agy-ipc-turn.sh}"  # Antigravity IPC turn bridge (subagent transcript -> stream-json)
: "${AGENT_MODEL:=grok-4.7-high}"
: "${APPROVER:=mdurana}"
: "${PACK:=java}"                                      # stack pack the scripted architecture answer names
: "${PROFILE:=app}"                                    # bootstrap-greenfield.sh --profile
: "${ONBOARD_MODE:=bootstrap}"                         # bootstrap = greenfield install only; agent = also run /v0-onboard
: "${PG_HOME:=}"                                       # portable PostgreSQL 17; empty = auto-detect / install
: "${ODC_SRC:=}"                                       # optional prebuilt OWASP dependency-check data dir (has odc.mv.db)
: "${M2_REPO:=$HOME/.m2/repository}"
: "${ODC_DST:=$M2_REPO/org/owasp/dependency-check-data/9.0}"   # where dependency-check-maven 10.0.4 reads its DB
: "${ODC_FEED:=https://dependency-check.github.io/DependencyCheck_Builder/nvd_cache/}"  # keyless NVD mirror
: "${TURN_CAP:=1740}"            # seconds per agent turn (29 min)
: "${RUN_TIMEOUT:=7200}"         # seconds per agent run (all turns); P0-A uses RUN_TIMEOUT_P0A
: "${RUN_TIMEOUT_P0A:=14400}"
: "${STALL_SEC:=900}"            # no new output for this long = stalled turn
: "${HEARTBEAT_SEC:=1500}"       # status line at least this often (must stay <= 1800)
: "${POLL_SEC:=30}"
: "${MAX_TURNS:=12}"             # turns per run (prompt + scripted replies)
: "${MAX_ANSWERS:=3}"            # scripted answers per run
: "${MAX_RETRY_INFRA:=2}"        # fresh retries after a stall / infra error
: "${MAX_RUNS_PER_STORY:=10}"    # phase runs per story before "stuck"
: "${ASK_MODE:=auto}"            # auto (from calibration) | allowlist | harness
: "${CONTINUE_AFTER_PROBE_FAIL:=0}"   # 1 = step 8 still runs when a step-7 probe failed
: "${JAIL_CMD:=}"                # optional wrapper: $JAIL_CMD <run-dir> <workspace> <agent argv...>
: "${STATUS_HOOK:=}"             # optional command that receives each status line on stdin
: "${REAL_DIRS:=}"               # space-separated repos that must stay byte-identical (checked every step)
: "${CURSOR_API_KEY:=}"          # preferred non-interactive auth for the agent CLI (never written to disk by the runner)
export PLAN_DIR RUN_ID TEST_ROOT KIT_URL KIT_REF TOOLS_DIR AGENT_DRIVER AGENT_BIN AGY_BIN AGENT_TURN_CMD AGENT_MODEL APPROVER PACK PROFILE ONBOARD_MODE \
  PG_HOME ODC_SRC M2_REPO ODC_DST ODC_FEED TURN_CAP RUN_TIMEOUT RUN_TIMEOUT_P0A STALL_SEC HEARTBEAT_SEC POLL_SEC \
  MAX_TURNS MAX_ANSWERS MAX_RETRY_INFRA MAX_RUNS_PER_STORY ASK_MODE CONTINUE_AFTER_PROBE_FAIL JAIL_CMD STATUS_HOOK REAL_DIRS
[ -z "$CURSOR_API_KEY" ] || export CURSOR_API_KEY
# Derived layout (do not change)
WORK="$TEST_ROOT/work"; MAIN="$WORK/portal"; KIT="$TEST_ROOT/kit"
EVID="$TEST_ROOT/evidence"; SNAP="$TEST_ROOT/snapshots"; RES="$TEST_ROOT/results"; STATUS_LOG="$TEST_ROOT/status/progress.log"
DISCOVERY_REL="user-requirements/Finance-Back-Office-Portal-Discovery-Requirements.md"
export WORK MAIN KIT EVID SNAP RES STATUS_LOG DISCOVERY_REL
[ -f "$TOOLS_DIR/tools.env" ] && . "$TOOLS_DIR/tools.env"
true
