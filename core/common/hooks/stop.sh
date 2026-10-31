#!/bin/sh
# stop.sh — evidence-based reminder; at most one followup per repo per 6 hours.
set -eu
# kitfix-20261031-jn4 (M-1): the hooks run the system tools only. PATH comes from the IDE, which takes it from the
#   login shell and its start-up files, so an agent-written ~/.local/bin/cat or a PATH line in ~/.bashrc would
#   otherwise run inside the hook (Sakura's fake-cat repro). Set before the first command (dirname).
PATH=/usr/bin:/bin
export PATH

. "$(dirname "$0")/lib.sh"

stamp_file=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  gd="$(git rev-parse --git-dir 2>/dev/null)"
  stamp_file="$gd/agents-v0-stop-reminder"
else
  stamp_file=".cursor/hooks/.stop-reminder-stamp"
fi

now="$(date +%s)"
if [ -f "$stamp_file" ]; then
  last="$(cat "$stamp_file" 2>/dev/null || echo 0)"
  if [ "$now" -lt "$((last + 21600))" ]; then
    exit 0
  fi
fi

payload="$(cat || true)"
haystack="$payload"
transcript="$(printf '%s' "$payload" | hook_json_string_field transcript_path)"
[ -n "$transcript" ] || transcript="$(printf '%s' "$payload" | hook_json_string_field transcriptPath)"
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  haystack="$(tail -c 8000 "$transcript" 2>/dev/null || printf '%s' "$payload")"
fi
if printf '%s' "$haystack" | grep -Eqi 'mvn|npm|pnpm|yarn|vitest|jest|gradle|pytest|dotnet (test|build)|go test|run-backend-verify|coverage|docs/agents-v0/build/|docs/agents-v0/verify/'; then
  [ "${KIT_HOOK_FLAVOR:-}" = "antigravity" ] && printf '{"decision":"allow"}\n'
  exit 0
fi

reminder=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  changed="$(git status --porcelain 2>/dev/null | grep -Ev '[[:space:]]([^/]*[/ ])*[^/]*\.(md|mdc|markdown|txt|adoc|json|lock)$' || true)"
  if [ -n "$changed" ]; then
    reminder="Uncommitted code changes detected. Run the project quality gate (docs/agents-v0/project-profile.md), persist Build/Verify evidence with commit: lines, and sync docs."
    printf 'REMINDER: %s\n' "$reminder" >&2
  fi
fi

if [ -n "$reminder" ]; then
  printf '%s' "$now" >"$stamp_file"
  hook_audit_log "stop" "" "reminder" "$reminder"
  # Cursor/Antigravity stop: followup can loop; stderr only unless KIT_STOP_FOLLOWUP=1
  if [ "${KIT_STOP_FOLLOWUP:-0}" = "1" ]; then
    hook_emit_stop_followup "$reminder"
    exit 0
  fi
fi

[ "${KIT_HOOK_FLAVOR:-}" = "antigravity" ] && printf '{"decision":"allow"}\n'
exit 0
