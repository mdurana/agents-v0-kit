#!/bin/sh
# test-agy-remote-writes.sh — N64 (onboard fix, Sasuke): on Antigravity, gh / glab writes and git push are denied
# for an agent in every mode (N11C), through agy's real entry point. The hooks are copied into a scratch project's
# .agents/hooks, and each payload is an agy-style PreToolUse run_command, run through the exact command line in
# core/common/adapters/antigravity/hooks.json (KIT_HOOK_FLAVOR=antigravity /bin/sh -c '... pre-shell.sh ...').
# agy has no failClosed, so a hook-error variant (a hook-policy.py that crashes) must also come back as a deny.
# No agent, no model call, no network: the commands are judged, never run. The scratch folder is this run's own.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0; n=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
command -v python3 >/dev/null 2>&1 || { err "python3 not found"; exit 1; }

scratch="$(mktemp -d)"
trap 'rc=$?; rm -rf "$scratch"; exit $rc' EXIT INT TERM

AGY_CMD="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))["agents-v0-delivery"]
for m in d["PreToolUse"]:
    if m["matcher"] == "run_command":
        print(m["hooks"][0]["command"]); break
' "$KIT/core/common/adapters/antigravity/hooks.json")"
case "$AGY_CMD" in *KIT_HOOK_FLAVOR=antigravity*pre-shell.sh*) ;; *) err "agy hooks.json run_command entry not found ($AGY_CMD)"; exit 1 ;; esac

mkproj() {  # <dir> <hooks source>
  mkdir -p "$1/.agents"; cp -R "$2" "$1/.agents/hooks"
  git init -q -b main "$1"
}
mkproj "$scratch/proj" "$KIT/core/common/hooks"
# Hook-error variant: hook-policy.py crashes before it judges anything.
mkproj "$scratch/broken" "$KIT/core/common/hooks"
printf 'import sys\nsys.exit(3)\n' > "$scratch/broken/.agents/hooks/hook-policy.py"

payload() { python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":"run_command","args":{"CommandLine":sys.argv[1],"Cwd":sys.argv[2]}}}))' "$1" "$2"; }

# run_agy <project> <want deny|allow> <label> <command> [VAR=value ...]
run_agy() {
  proj="$1"; want="$2"; label="$3"; cmd="$4"; shift 4
  n=$((n + 1))
  set +e
  out="$(cd "$proj" && payload "$cmd" "$proj" | env "$@" /bin/sh -c "$AGY_CMD" 2>&1)"
  rc=$?
  set -e
  case "$want" in
    deny) { [ "$rc" = 2 ] && printf '%s' "$out" | grep -q '"deny"'; } || err "N64 $label: expected deny (rc=2), got rc=$rc: $cmd" ;;
    allow) { [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '"allow"'; } || err "N64 $label: expected allow (rc=0), got rc=$rc: $cmd" ;;
  esac
  if [ "$want" = deny ] && ! printf '%s' "$out" | grep -q 'own terminal\|fail-closed\|failed to run\|no verdict\|guardrail'; then
    err "N64 $label: the deny does not tell the agent who runs it ($out)"
  fi
}

ALLOW_ALL='AGY_ALLOW_TOOLS=Shell(gh:*),Shell(glab:*),Shell(git:*)'
for cmd in \
  'gh pr merge 12 --squash' \
  'gh pr create --fill' \
  'gh pr review 12 --approve' \
  'gh api -X DELETE repos/o/r' \
  'gh api repos/o/r/issues -f title=x' \
  'env GH_TOKEN=x gh api --method=PATCH repos/o/r' \
  '/usr/bin/gh repo delete o/r --yes' \
  'gh release create v1.0.0' \
  'glab mr create --fill' \
  'glab mr merge 12' \
  'glab api -X POST projects/1/issues' \
  'git push' \
  'git push origin main' \
  'git -C . push --mirror backup' \
  "sh -c 'git push origin main'" \
  'git -c alias.p=push p origin main'; do
  run_agy "$scratch/proj" deny "supervised" "$cmd" KIT_HOOK_FLAVOR=antigravity
  run_agy "$scratch/proj" deny "unattended with an allow-list" "$cmd" KIT_HOOK_FLAVOR=antigravity "$ALLOW_ALL"
  run_agy "$scratch/broken" deny "hook-policy.py crashes (fail closed)" "$cmd" KIT_HOOK_FLAVOR=antigravity
done
for cmd in 'gh pr view 12' 'gh pr list' 'gh api repos/o/r/pulls' 'glab mr view 12' 'git status'; do
  run_agy "$scratch/proj" allow "read-only" "$cmd" KIT_HOOK_FLAVOR=antigravity
done

if [ "$fail" = 0 ]; then printf 'test-agy-remote-writes: OK (%s cases)\n' "$n"; exit 0; fi
printf 'test-agy-remote-writes: FAILED\n' >&2; exit 1
