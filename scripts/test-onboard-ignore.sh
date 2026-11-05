#!/bin/sh
# test-onboard-ignore.sh (V5-4B, Design: D8): verifies that templates/.gitignore, root .gitignore, and
# install.sh brownfield .gitignore migration ignore local runtime files (__pycache__/, .cursor/hooks/audit.jsonl,
# .agents/hooks/audit.jsonl, docs/agents-v0/onboarding/state.json.lock, docs/agents-v0/**/*.lock) so they never
# dirty git status or trigger uncommitted warnings during guard-onboard.sh commit.
# Run: sh scripts/test-onboard-ignore.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-onboard-ignore.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi

# --- 1. Template & root .gitignore static checks -----------------------------------------------------------------
for line in \
  'docs/agents-v0/onboarding/state.json.lock' \
  'docs/agents-v0/**/*.lock' \
  '.cursor/hooks/audit.jsonl' \
  '.agents/hooks/audit.jsonl' \
  '__pycache__/'; do
  grep -Fqx "$line" "$ROOT/templates/.gitignore"
  check $? "templates/.gitignore lists $line"
  grep -Fqx "$line" "$ROOT/.gitignore"
  check $? "root .gitignore lists $line"
done

# --- 2. Greenfield git check-ignore verification -----------------------------------------------------------------
gf="$tmp/greenfield"
mkdir -p "$gf" && git -C "$gf" init -q -b main
cp "$ROOT/templates/.gitignore" "$gf/.gitignore"
git -C "$gf" add .gitignore && git -C "$gf" commit -qm "init with template gitignore"

mkdir -p "$gf/.cursor/hooks/__pycache__" "$gf/.agents/hooks" "$gf/docs/agents-v0/onboarding"
printf '{"event":"test"}\n' > "$gf/.cursor/hooks/audit.jsonl"
printf '{"event":"test"}\n' > "$gf/.agents/hooks/audit.jsonl"
printf 'bytecode\n' > "$gf/.cursor/hooks/__pycache__/hook-policy.cpython-311.pyc"
: > "$gf/docs/agents-v0/onboarding/state.json.lock"
: > "$gf/docs/agents-v0/onboarding/other.lock"

for path in \
  '.cursor/hooks/audit.jsonl' \
  '.agents/hooks/audit.jsonl' \
  '.cursor/hooks/__pycache__/hook-policy.cpython-311.pyc' \
  'docs/agents-v0/onboarding/state.json.lock' \
  'docs/agents-v0/onboarding/other.lock'; do
  git -C "$gf" check-ignore -q "$path"
  check $? "greenfield: git check-ignore matches $path"
done

dirty="$(git -C "$gf" status --porcelain --untracked-files=all)"
[ -z "$dirty" ]; check $? "greenfield: git status --porcelain is completely clean with runtime artifacts on disk" "$dirty"

# --- 3. Brownfield .gitignore migration (ignore_hook_python in install.sh) ---------------------------------------
bf="$tmp/brownfield"
mkdir -p "$bf" && git -C "$bf" init -q -b main
printf 'node_modules/\ntarget/\n' > "$bf/.gitignore"
git -C "$bf" add .gitignore && git -C "$bf" commit -qm "brownfield init"

# Extract and invoke ignore_hook_python from scripts/install.sh directly
run_migrate() {
  sh -c '
    eval "$(sed -n "/^ignore_hook_python()/,/^}/p" "$1")"
    ignore_hook_python "$2"
  ' -- "$ROOT/scripts/install.sh" "$1"
}

out1="$(run_migrate "$bf" 2>&1)"
check $? "brownfield: migration exits 0" "$out1"
printf '%s' "$out1" | grep -q '^MIGRATED (project-owned file edited): \.gitignore gained'; check $? "brownfield: prints MIGRATED notice on first run" "$out1"
grep -qx 'node_modules/' "$bf/.gitignore" && grep -qx 'target/' "$bf/.gitignore"
check $? "brownfield: preserves existing project .gitignore lines"

for line in \
  '.cursor/hooks/hook-python' \
  '.agents/hooks/hook-python' \
  '.cursor/hooks/audit.jsonl' \
  '.agents/hooks/audit.jsonl' \
  'docs/agents-v0/onboarding/state.json.lock' \
  'docs/agents-v0/**/*.lock' \
  '__pycache__/'; do
  grep -Fqx "$line" "$bf/.gitignore"
  check $? "brownfield: .gitignore gained $line"
done

# Idempotence check: second run adds nothing
before_lines="$(wc -l < "$bf/.gitignore" | tr -d ' ')"
out2="$(run_migrate "$bf" 2>&1)"
after_lines="$(wc -l < "$bf/.gitignore" | tr -d ' ')"
[ -z "$out2" ] && [ "$before_lines" = "$after_lines" ]
check $? "brownfield: second migration run is a no-op (no duplicate lines)" "$out2"

# Check that git check-ignore works in the migrated brownfield repo
mkdir -p "$bf/.cursor/hooks/__pycache__" "$bf/.agents/hooks" "$bf/docs/agents-v0/onboarding"
printf '{"event":"test"}\n' > "$bf/.cursor/hooks/audit.jsonl"
printf '{"event":"test"}\n' > "$bf/.agents/hooks/audit.jsonl"
printf 'bytecode\n' > "$bf/.cursor/hooks/__pycache__/hook-policy.cpython-311.pyc"
: > "$bf/docs/agents-v0/onboarding/state.json.lock"

git -C "$bf" add .gitignore && git -C "$bf" commit -qm "commit migrated gitignore"
bf_dirty="$(git -C "$bf" status --porcelain --untracked-files=all)"
[ -z "$bf_dirty" ]; check $? "brownfield: git status --porcelain is clean after migration with runtime files present" "$bf_dirty"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
