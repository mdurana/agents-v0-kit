#!/usr/bin/env bash
# agy-ws-exec.sh — Execute a shell command inside the active Antigravity IPC turn's workspace,
# enforcing the workspace's .agents/hooks/pre-shell.sh with AGY_ALLOW_TOOLS from pending-turn.json.
set -eu
export PATH="/opt/local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="core.excludesfile"
export GIT_CONFIG_VALUE_0=""

HERE="$(cd "$(dirname "$0")" && pwd)"
TR="${TEST_ROOT:-}"
WS_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --test-root) TR="$2"; shift 2 ;;
    --ws) WS_OVERRIDE="$2"; shift 2 ;;
    *) break ;;
  esac
done

[ -n "$TR" ] || { echo "error: TEST_ROOT or --test-root required" >&2; exit 2; }
PENDING="$TR/status/pending-turn.json"
[ -f "$PENDING" ] || { echo "error: no pending turn at $PENDING" >&2; exit 1; }

WS="$(jq -r .workspace "$PENDING")"
ALLOW="$(jq -r .allow "$PENDING")"
[ -n "$WS_OVERRIDE" ] && WS="$WS_OVERRIDE"

CMD="$*"
[ -n "$CMD" ] || { echo "error: command required" >&2; exit 2; }

if [ -f "$WS/.agents/hooks/pre-shell.sh" ]; then
  HOOK_OUT="$(printf '{"command": %s}' "$(printf '%s' "$CMD" | jq -Rs .)" |
    env KIT_HOOK_FLAVOR=antigravity AGY_ALLOW_TOOLS="$ALLOW" sh "$WS/.agents/hooks/pre-shell.sh")" || {
    rc=$?
    echo "HOOK DENIED (rc=$rc): $HOOK_OUT" >&2
    exit "$rc"
  }
  DEC="$(printf '%s' "$HOOK_OUT" | jq -r '.decision // .permission // "allow"')"
  if [ "$DEC" != "allow" ]; then
    echo "HOOK BLOCKED ($DEC): $HOOK_OUT" >&2
    exit 2
  fi
fi

cd "$WS"
export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home}"
export TESTCONTAINERS_RYUK_DISABLED=true
export MAVEN_OPTS="-Xmx1536m"
eval "$CMD"
