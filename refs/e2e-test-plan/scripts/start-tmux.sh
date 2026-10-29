#!/usr/bin/env bash
# start-tmux.sh — start an unattended run in tmux so it survives SSH disconnects (HARNESS-FIX 2026-10-29, VM-03).
#   bash scripts/start-tmux.sh <launch.env> [<tmux session name, default e2e>]
# <launch.env> holds only `export NAME=value` lines (no secrets), e.g. AGENT_DRIVER, AGY_MODEL, TARGET_SURFACE, KIT_URL.
# Plain words: on Marlon's box the runner and the agy loop were started by hand, and the agy window did not load the
# launch settings, so it ran with an empty model, the wrong agy path and no JDK. This script starts both windows from
# the SAME settings file:
#   window "runner": scripts/run-plan.sh, output also in $TEST_ROOT/status/runner-tty.log; its pid in status/runner.pid
#   window "agy"   : scripts/agy-turn-loop.sh for that runner (only when the driver is antigravity)
# RUN_ID and TEST_ROOT are fixed once here and passed to both windows, so they always agree.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; PLAN="$(cd "$HERE/.." && pwd)"
# shellcheck source=/dev/null
load(){ set -a; . "$1"; set +a; export RUN_ID TEST_ROOT; . "$HERE/env.sh"; }
case "${1:-}" in
  --runner) load "$2"; mkdir -p "$TEST_ROOT/status"; cd "$PLAN"
            bash "$HERE/run-plan.sh" > >(tee -a "$TEST_ROOT/status/runner-tty.log") 2>&1 & echo $! > "$TEST_ROOT/status/runner.pid"
            wait $! ; rc=$?; echo "run-plan.sh exit=$rc" | tee -a "$TEST_ROOT/status/runner-tty.log"; exit "$rc";;
  --loop)   load "$2"; for _ in $(seq 1 60); do [ -s "$TEST_ROOT/status/runner.pid" ] && break; sleep 1; done
            [ -s "$TEST_ROOT/status/runner.pid" ] || { echo "runner.pid not found under $TEST_ROOT/status" >&2; exit 2; }
            exec bash "$HERE/agy-turn-loop.sh" "$TEST_ROOT" "$PLAN" "$(cat "$TEST_ROOT/status/runner.pid")";;
esac
[ -f "${1:-}" ] || { echo "usage: $0 <launch.env> [session]" >&2; exit 64; }
ENVF="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; S="${2:-e2e}"
command -v tmux >/dev/null || { echo "tmux not installed" >&2; exit 2; }
set -a
# shellcheck source=/dev/null
. "$ENVF"
set +a
: "${RUN_ID:=$(TZ=Asia/Manila date +%Y%m%d-%H%M)}"; : "${TEST_ROOT:=$HOME/agents-v0-e2e/run-$RUN_ID}"; export RUN_ID TEST_ROOT
. "$HERE/env.sh"
[ ! -e "$TEST_ROOT/work" ] || { echo "TEST_ROOT $TEST_ROOT already has a workspace" >&2; exit 2; }
tmux has-session -t "$S" 2>/dev/null && { echo "tmux session $S already exists" >&2; exit 2; }
mkdir -p "$TEST_ROOT/status"; cp "$ENVF" "$TEST_ROOT/status/launch.env"
tmux new-session -d -s "$S" -n runner -e RUN_ID="$RUN_ID" -e TEST_ROOT="$TEST_ROOT" "bash '$HERE/start-tmux.sh' --runner '$ENVF'; exec bash"
if [ "$(resolve_driver)" = antigravity ]; then
  tmux new-window -t "$S" -n agy -e RUN_ID="$RUN_ID" -e TEST_ROOT="$TEST_ROOT" "bash '$HERE/start-tmux.sh' --loop '$ENVF'; exec bash"
fi
echo "started: tmux session $S, TEST_ROOT=$TEST_ROOT, driver=$(resolve_driver). Follow: tail -f $TEST_ROOT/status/progress.log"
