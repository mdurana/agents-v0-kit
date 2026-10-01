#!/bin/sh
# test-hooks.sh — end-to-end tests for the hook wrappers (pre-shell, pre-edit)
# under sh and dash, plus hook-policy.py unit tests. Runs in a scratch directory so
# audit logs never land in the kit repo.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$KIT/core/hooks"
fail=0

err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

command -v python3 >/dev/null 2>&1 || { err "python3 not found"; exit 1; }
command -v dash >/dev/null 2>&1 && DASH=dash || DASH=sh

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

# run_hook <script> <flavor> <json-payload> <want: block|ask|allow> <label>
run_hook() {
  script="$1"; flavor="$2"; payload="$3"; want="$4"; label="$5"
  for SH in sh "$DASH"; do
    set +e
    out="$(printf '%s' "$payload" | KIT_HOOK_FLAVOR="$flavor" "$SH" "$HOOKS/$script" 2>&1)"
    rc=$?
    set -e
    case "$want" in
      block) [ "$rc" = "2" ] || err "$SH $script ($flavor): expected block for $label (rc=$rc)" ;;
      ask)
        { [ "$rc" = "0" ] && printf '%s' "$out" | grep -Eq '"(permission|permissionDecision)": "ask"'; } \
          || err "$SH $script ($flavor): expected ask for $label (rc=$rc)"
        ;;
      allow)
        { [ "$rc" = "0" ] && ! printf '%s' "$out" | grep -Eq 'BLOCK:|"ask"'; } \
          || err "$SH $script ($flavor): expected allow for $label (rc=$rc)"
        ;;
    esac
  done
}

shell_case() { run_hook pre-shell.sh cursor "{\"command\":$(json_str "$1")}" "$2" "\`$1\`"; }

shell_case 'git push origin main --force' block
shell_case 'git -c credential.helper= push --force' block
shell_case 'echo $(git push --force)' block
shell_case 'git commit -m x' ask
shell_case 'cat .env' block
shell_case 'cat .env.example' allow
shell_case 'rm -rf dir' block
shell_case 'rm -f build.log' allow
shell_case 'docker rm -f my-container' allow
shell_case 'echo x > .cursor/hooks.json' block
shell_case 'ls' allow

run_hook pre-edit.sh cursor '{"tool_input":{"file_path":".cursor/hooks.json"}}' block "edit .cursor/hooks.json"
run_hook pre-edit.sh cursor '{"tool_input":{"file_path":"docs/requirements/f.md"}}' allow "cursor edit requirements (ask not enforced)"
run_hook pre-edit.sh cursor '{"tool_input":{"file_path":"src/Main.java"}}' allow "edit src"

# Cursor permission hooks must emit explicit allow JSON (failClosed).
for SH in sh "$DASH"; do
  out="$(printf '%s' '{"tool_input":{"file_path":"src/Main.java"}}' | KIT_HOOK_FLAVOR=cursor "$SH" "$HOOKS/pre-edit.sh" 2>&1)" || true
  printf '%s' "$out" | grep -Fq '"permission": "allow"' \
    || err "$SH pre-edit.sh (cursor): missing permission allow JSON"
done

python3 "$KIT/scripts/test-hook-policy.py" || fail=1

if [ "$fail" -eq 1 ]; then
  printf 'test-hooks: FAILED\n' >&2
  exit 1
fi
printf 'test-hooks: OK\n'
