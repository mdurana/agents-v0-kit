#!/usr/bin/env bash
# agy-step-turn.sh — Complete the active Antigravity IPC turn and wait synchronously for the next pending turn (or RUN-END).
set -eu
export PATH="/opt/local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
TR="${TEST_ROOT:-}"
if [ "${1:-}" = "--test-root" ]; then
  TR="$2"
  shift 2
fi
[ -n "$TR" ] || { echo "error: TEST_ROOT or --test-root required" >&2; exit 2; }

PENDING="$TR/status/pending-turn.json"
TEXT="${1:-}"
CMD="${2:-}"
ARGS=(--test-root "$TR" --text "$TEXT")
[ -n "$CMD" ] && ARGS+=(--cmd "$CMD")

bash "$HERE/agy-complete-turn.sh" "${ARGS[@]}"

for _ in $(seq 1 90); do
  if [ ! -e "$TR/RUNNING" ] && grep -q "RUN-END" "$TR/status/progress.log" 2>/dev/null; then
    echo "=== RUN FINISHED ==="
    tail -n 20 "$TR/status/progress.log"
    exit 0
  fi
  if [ -s "$PENDING" ]; then
    echo "=== RECENT PROGRESS ==="
    tail -n 10 "$TR/status/progress.log"
    echo "=== NEXT PENDING TURN ==="
    cat "$PENDING"
    exit 0
  fi
  sleep 1
done

echo "=== STILL PROCESSING BETWEEN TURNS ==="
tail -n 15 "$TR/status/progress.log"
