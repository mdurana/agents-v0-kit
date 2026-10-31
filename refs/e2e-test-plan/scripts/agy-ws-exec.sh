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
# kitfix-20261031-harness-lock (Sonnet review 12:31, finding 2): pending-turn.json is in the run root, which the agent's
#   OS user can write. agy-turn-loop.sh starts each agy turn with the request's allowlist in AGY_ALLOW_TOOLS, and every
#   command agy runs inherits it, so a file that no longer matches it was changed during the turn: refuse. (The hooks
#   block an agent command that sets or unsets AGY_ALLOW_TOOLS; this is a speed bump, the procedure is the fence.)
if [ -n "${AGY_ALLOW_TOOLS+x}" ] && [ "$AGY_ALLOW_TOOLS" != "$ALLOW" ]; then
  printf '%s allowlist mismatch: env=%s file=%s cmd=%s\n' "$(TZ=Asia/Manila date '+%F %T')" "$AGY_ALLOW_TOOLS" "$ALLOW" "$*" \
    >> "$TR/agy-driver/ws-exec-denied.log" 2>/dev/null || :
  echo "HOOK DENIED (allowlist mismatch): status/pending-turn.json does not match the allowlist this turn started with" >&2
  exit 2
fi

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
# HARNESS-FIX 2026-10-29 (VM-02): JAVA_HOME used to fall back to a macOS-only path, so on Linux a command run without
#   JAVA_HOME (e.g. ./mvnw on a fresh VM) failed. Now: keep JAVA_HOME if set; else load the harness's tools.env; else
#   use the macOS JDK path only if it exists; else derive it from `java` on PATH (Linux).
if [ -z "${JAVA_HOME:-}" ] && [ -f "${TOOLS_DIR:-$HOME/.local/agents-v0-tools}/tools.env" ]; then
  . "${TOOLS_DIR:-$HOME/.local/agents-v0-tools}/tools.env"; [ -z "${TOOLS_PATH:-}" ] || PATH="$TOOLS_PATH:$PATH"
fi
if [ -z "${JAVA_HOME:-}" ] && [ -d /Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home ]; then
  JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home
fi
if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1 && readlink -f "$(command -v java)" >/dev/null 2>&1; then
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
[ -z "${JAVA_HOME:-}" ] || export JAVA_HOME
export PATH
export TESTCONTAINERS_RYUK_DISABLED=true
export MAVEN_OPTS="-Xmx1536m"
eval "$CMD"
