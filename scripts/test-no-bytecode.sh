#!/bin/sh
# test-no-bytecode.sh: a test runner started on its own (outside validate-kit, without
# PYTHONDONTWRITEBYTECODE) must leave no __pycache__ in the kit's templates/ or core/ (Kakashi 04:22;
# Sasuke saw test-hook-policy crash on a leftover templates/.agents-v0/scripts/__pycache__).
# Found by running every suite alone in its own fresh clone at 299f3cbe: test-ci-checks.sh (resolve-layout.sh
# imports templates/.agents-v0/scripts/packlib.py), test-hooks.sh and test-hook-policy.py (which import
# core/common/hooks/hook-policy.py), and test-delivery-lifecycle.sh (through test-ci-checks.sh).
# Cheap by design: static checks that each such runner turns bytecode off, plus one live run of
# test-ci-checks.sh in a clean detached clone (git clone --no-checkout, checkout --detach). test-hooks.sh is
# not run live (about 5 minutes). Tier 1: offline, temp folders only.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

# 1. Shell runners: the export is the line straight after `set -eu`.
for r in scripts/test-ci-checks.sh scripts/test-hooks.sh; do
  has "$r exports PYTHONDONTWRITEBYTECODE=1" "$KIT/$r" "export PYTHONDONTWRITEBYTECODE=1"
  after="$(sed -n '/^set -eu$/{n;p;q;}' "$KIT/$r")"
  case "$after" in
    "export PYTHONDONTWRITEBYTECODE=1"|"export PYTHONDONTWRITEBYTECODE=1 "*) pass "$r: the export follows set -eu" ;;
    *) fail "$r: the line after set -eu is '$after', not the export" ;;
  esac
done

# 2. Python runners: every scripts/test-*.py turns bytecode off before it imports kit code.
for p in "$KIT"/scripts/test-*.py; do
  has "${p#"$KIT"/} sets sys.dont_write_bytecode" "$p" "sys.dont_write_bytecode = True"
done

# 3. validate-kit runs this suite (it already exports the variable for everything it runs).
has "validate-kit runs this suite" "$KIT/scripts/validate-kit.sh" "sh scripts/test-no-bytecode.sh"

# 4. Live: test-ci-checks.sh alone, without the variable, in a clean detached clone of the kit at HEAD.
# The runner under test is copied in from this checkout so a working-tree change is what gets judged.
if git -C "$KIT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  c="$T1_TMP/clone"
  git clone -q --no-checkout "$KIT" "$c" && git -C "$c" checkout -q --detach "$(git -C "$KIT" rev-parse HEAD)"
  cp "$KIT/scripts/test-ci-checks.sh" "$c/scripts/test-ci-checks.sh"
  if [ -z "$(cd "$c" && find templates core -name __pycache__)" ]; then pass "live: the clean clone starts with no __pycache__"
  else fail "live: the clean clone already has a __pycache__"; fi
  if (unset PYTHONDONTWRITEBYTECODE; cd "$c" && sh scripts/test-ci-checks.sh) > "$T1_TMP/ci.out" 2>&1; then
    pass "live: test-ci-checks.sh passes alone"
  else fail "live: test-ci-checks.sh failed alone (see its output)"; sed -n '1,20p' "$T1_TMP/ci.out" >&2; fi
  left="$(cd "$c" && find templates core -name __pycache__ | tr '\n' ' ')"
  if [ -z "$left" ]; then pass "live: test-ci-checks.sh alone leaves no __pycache__ under templates/ or core/"
  else fail "live: test-ci-checks.sh alone left __pycache__: $left"; fi
else
  printf 'SKIP: live clean-clone check (the kit at %s is not a git checkout)\n' "$KIT"
fi

t1_done test-no-bytecode
