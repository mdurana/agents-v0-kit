#!/bin/sh
# test-installed-overrides.sh — kitfix-20261031-installed-no-overrides. An installed copy of the kit scripts
# carries no AGENTS_V0_* override code, so the tricks a text-matching hook cannot see (a split variable
# name, an env file decoded from base64 and loaded with `set -a`) change nothing: the branch guard still
# fires, the gate-commit check still runs, the clock is not pinned, and the trace mode is the one in
# .agents-v0/policy.conf. Each probe is also run on a --test-overrides copy (the kit's own test copy),
# where the same override does work, so the probe itself is shown to be live. Run by validate-kit.sh.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0; n=0
pass() { n=$((n + 1)); printf 'ok: %s\n' "$1"; }
fail() { n=$((n + 1)); printf 'FAIL: %s\n' "$1" >&2; status=1; }
G() { d="$1"; shift; git -C "$d" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }
# run <dir> <shell text>: run the text with sh -c in <dir>, as an agent would type it; output in $tmp/out.txt
run() { (cd "$1" && sh -c "$2") > "$tmp/out.txt" 2>&1; }
ORD=docs/agents-v0/requirements/orders.md
# The overrides as an agent would hide them from a text check: the name is split, and the env file is
# decoded from base64 at run time (the encoded text holds no AGENTS_V0_ string).
ENVB64="$(printf 'AGENTS_V0_SKIP_BRANCH_GUARD=1\nAGENTS_V0_SKIP_COMMIT_CHECK=1\nAGENTS_V0_NOW=2001-02-03T04:05:06+00:00\nAGENTS_V0_TZ=Pacific/Kiritimati\nAGENTS_V0_TRACE_MODE=warn\nAGENTS_V0_TRACE_NO_WRITE=1\n' | base64 | tr -d '\n')"
case "$ENVB64" in *AGENTS_V0_*) echo "base64 text still names the variables" >&2; exit 1 ;; esac
SPLIT='V=AGENTS_V0_SKIP_BRANCH; env "${V}_GUARD=1"'
B64='printf %s "'"$ENVB64"'" | base64 -d > ./.ov.env; set -a; . ./.ov.env; set +a;'

mk() { # mk <dir> [install flags]: a project with one feature story past intake, all committed on main
  d="$1"; shift; mkdir -p "$d"; git -C "$d" init -q -b main
  sh "$KIT/scripts/install.sh" "$@" "$d" > "$tmp/install.log" 2>&1 || { cat "$tmp/install.log" >&2; exit 1; }
  mkdir -p "$d/docs/agents-v0/requirements" "$d/docs/agents-v0/design/orders"
  cat > "$d/$ORD" <<'EOF'
# Orders
As a clerk, I want to place an order, so that stock is reserved.

### AC-1 place an order
### AC-2 cancel an order

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/orders.md | mdurana | Approved | - |
EOF
  printf '# Design: orders\n\n## Traceability\n\n| AC | Element |\n|---|---|\n| AC-1 | createOrder |\n' > "$d/docs/agents-v0/design/orders/design.md"
  printf '.ov.env\n' >> "$d/.gitignore"
  G "$d" add -A; G "$d" commit -qm base
}
inst="$tmp/installed"; mk "$inst"
ctl="$tmp/testcopy"; mk "$ctl" --test-overrides

# 0. what was installed
if sh "$KIT/scripts/check-installed-kit.sh" "$inst" > "$tmp/out.txt" 2>&1; then pass "installed copy: check-installed-kit.sh says HASH-OK"; else fail "installed copy: HASH-OK"; cat "$tmp/out.txt" >&2; fi
if grep -n 'AGENTS_V0_' "$inst"/.agents-v0/scripts/sync-feature-state.sh "$inst"/.agents-v0/scripts/check-gate-commit.sh "$inst"/.agents-v0/scripts/check-traceability.sh | grep -v ':[[:space:]]*#' >/dev/null; then
  fail "installed copy: no script line reads AGENTS_V0_*"; else pass "installed copy: no script line reads AGENTS_V0_*"; fi
if sh "$KIT/scripts/check-installed-kit.sh" "$ctl" > "$tmp/out.txt" 2>&1; then fail "test copy is flagged by check-installed-kit.sh"
else grep -q '^TEST-OVERRIDES-INSTALLED .agents-v0/scripts/sync-feature-state.sh' "$tmp/out.txt" && pass "test copy is flagged TEST-OVERRIDES-INSTALLED" || fail "test copy flag text"; fi

# 1. branch guard: design in_progress on main
for how in split b64; do
  [ "$how" = split ] && pre="$SPLIT" || pre="$B64"
  if run "$inst" "$pre sh .agents-v0/scripts/sync-feature-state.sh $ORD --active-phase design --status in_progress"; then
    fail "installed + $how: the branch guard still refuses design on main"; sed 's/^/    /' "$tmp/out.txt" >&2
  else grep -q 'runs only on feature/orders' "$tmp/out.txt" && pass "installed + $how: the branch guard still refuses design on main" \
    || { fail "installed + $how: guard message"; sed 's/^/    /' "$tmp/out.txt" >&2; }; fi
  if run "$ctl" "$pre sh .agents-v0/scripts/sync-feature-state.sh $ORD --active-phase design --status in_progress"; then
    pass "test copy + $how: the same override skips the guard (probe is live)"
    run "$ctl" "$pre sh .agents-v0/scripts/sync-feature-state.sh $ORD --clear-active" || :
  else fail "test copy + $how: the override should skip the guard"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
done
G "$ctl" checkout -q -- . 2>/dev/null || :

# 2. clock: approve intake with a pinned clock and time zone in the env
for how in split b64; do
  [ "$how" = split ] && pre='A=AGENTS_V0; env "${A}_NOW=2001-02-03T04:05:06+00:00" "${A}_TZ=Pacific/Kiritimati"' || pre="$B64"
  for d in "$inst" "$ctl"; do G "$d" checkout -q -- . 2>/dev/null || :; rm -f "$d/docs/agents-v0/requirements/orders.state.json"; done
  run "$inst" "$pre sh .agents-v0/scripts/sync-feature-state.sh --approve intake $ORD" || { fail "installed + $how: approve intake"; sed 's/^/    /' "$tmp/out.txt" >&2; }
  got="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phaseTimes"]["intake"])' "$inst/docs/agents-v0/requirements/orders.state.json" 2>/dev/null || echo none)"
  case "$got" in 2001-*|*+14:00|none) fail "installed + $how: the clock is not pinned (phaseTimes.intake=$got)";; *) pass "installed + $how: the clock is not pinned (phaseTimes.intake=$got)";; esac
  run "$ctl" "$pre sh .agents-v0/scripts/sync-feature-state.sh --approve intake $ORD" || :
  got="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phaseTimes"]["intake"])' "$ctl/docs/agents-v0/requirements/orders.state.json" 2>/dev/null || echo none)"
  [ "$got" = 2001-02-03T18:05:06+14:00 ] && pass "test copy + $how: the same override pins the clock (probe is live)" || fail "test copy + $how: clock pin ($got)"
done

# 3. gate-commit check: the approved intake is not committed yet, so the next phase is refused
printf 'x\n' > "$inst/dirty.txt"; printf 'x\n' > "$ctl/dirty.txt"
for how in split b64; do
  [ "$how" = split ] && pre='V=AGENTS_V0_SKIP_COMMIT; env "${V}_CHECK=1"' || pre="$B64"
  if run "$inst" "$pre sh .agents-v0/scripts/check-gate-commit.sh $ORD"; then fail "installed + $how: the gate-commit check still runs"; sed 's/^/    /' "$tmp/out.txt" >&2
  else pass "installed + $how: the gate-commit check still runs (uncommitted intake gate refused)"; fi
  run "$ctl" "$pre sh .agents-v0/scripts/check-gate-commit.sh $ORD" && grep -q 'skipped' "$tmp/out.txt" \
    && pass "test copy + $how: the same override skips the check (probe is live)" || fail "test copy + $how: override should skip"
done
rm -f "$inst/dirty.txt" "$ctl/dirty.txt"

# 4. trace mode: policy.conf says fail; the env says warn
for d in "$inst" "$ctl"; do printf 'trace_mode=fail\n' > "$d/.agents-v0/policy.conf"; done
run "$inst" "sh .agents-v0/scripts/check-traceability.sh --print-mode" && grep -q '^trace_mode=fail source=policy.conf' "$tmp/out.txt" \
  && pass "installed: --print-mode reports fail from policy.conf" || fail "installed: --print-mode"
for how in split b64; do
  [ "$how" = split ] && pre='M=AGENTS_V0_TRACE; env "${M}_MODE=warn"' || pre="$B64"
  if run "$inst" "$pre sh .agents-v0/scripts/check-traceability.sh design $ORD"; then fail "installed + $how: trace mode stays fail (AC-2 missing refuses)"; sed 's/^/    /' "$tmp/out.txt" >&2
  else grep -q 'TRACE FAIL T1-design-covers-acs' "$tmp/out.txt" && pass "installed + $how: trace mode stays fail (AC-2 missing refuses)" || { fail "installed + $how: TRACE FAIL line"; sed 's/^/    /' "$tmp/out.txt" >&2; }; fi
  run "$inst" "$pre sh .agents-v0/scripts/check-traceability.sh --print-mode" && grep -q '^trace_mode=fail' "$tmp/out.txt" \
    && pass "installed + $how: --print-mode still says fail" || fail "installed + $how: --print-mode"
  run "$ctl" "$pre sh .agents-v0/scripts/check-traceability.sh design $ORD" && pass "test copy + $how: the same override weakens to warn (probe is live)" \
    || fail "test copy + $how: override should weaken to warn"
done
printf 'trace_mode=off\n' > "$inst/.agents-v0/policy.conf"
run "$inst" "sh .agents-v0/scripts/check-traceability.sh --print-mode" && grep -q '^trace_mode=fail' "$tmp/out.txt" \
  && pass "installed: an unknown trace_mode value counts as fail" || fail "installed: unknown value fails closed"
printf 'trace_mode=fail\n' > "$inst/.agents-v0/policy.conf"
if sh "$KIT/scripts/check-installed-kit.sh" --expect-trace-mode fail "$inst" > "$tmp/out.txt" 2>&1; then pass "check-installed-kit.sh --expect-trace-mode fail: HASH-OK"; else fail "expect fail mode"; cat "$tmp/out.txt" >&2; fi
mkdir -p "$tmp/aside"; mv "$inst/.agents-v0/policy.conf" "$tmp/aside/policy.conf"
if sh "$KIT/scripts/check-installed-kit.sh" --expect-trace-mode fail "$inst" > "$tmp/out.txt" 2>&1; then fail "a missing policy.conf is caught"
else grep -q '^TRACE-MODE warn (expected fail' "$tmp/out.txt" && pass "a missing policy.conf is caught (TRACE-MODE warn, expected fail)" || fail "missing policy text"; fi
mv "$tmp/aside/policy.conf" "$inst/.agents-v0/policy.conf"

# 5. removing a gate script does not switch its check off
mv "$inst/.agents-v0/scripts/check-gate-commit.sh" "$tmp/aside/"
if run "$inst" "sh .agents-v0/scripts/sync-feature-state.sh $ORD --clear-active"; then fail "installed: a missing check-gate-commit.sh is refused"
else grep -q 'check-gate-commit.sh is missing' "$tmp/out.txt" && pass "installed: a missing check-gate-commit.sh is refused" || fail "missing script message"; fi
sh "$KIT/scripts/check-installed-kit.sh" "$inst" > "$tmp/out.txt" 2>&1 || :
grep -q '^MISSING .agents-v0/scripts/check-gate-commit.sh' "$tmp/out.txt" && pass "check-installed-kit.sh reports the missing script" || fail "MISSING line"
mv "$tmp/aside/check-gate-commit.sh" "$inst/.agents-v0/scripts/"
printf '# tampered\n' >> "$inst/.agents-v0/scripts/check-traceability.sh"
sh "$KIT/scripts/check-installed-kit.sh" "$inst" > "$tmp/out.txt" 2>&1 || :
grep -q '^DIFF .agents-v0/scripts/check-traceability.sh' "$tmp/out.txt" && pass "check-installed-kit.sh reports an edited script (DIFF)" || fail "DIFF line"

# 6. --update strips a copy that still had the overrides
(cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update --quick --allow-in-flight "$ctl") > "$tmp/out.txt" 2>&1 || { fail "install.sh --update of the test copy"; sed 's/^/    /' "$tmp/out.txt" >&2; }
if sh "$KIT/scripts/check-installed-kit.sh" "$ctl" > "$tmp/out.txt" 2>&1; then pass "install.sh --update removes the overrides (HASH-OK)"; else fail "--update strips"; cat "$tmp/out.txt" >&2; fi
if run "$ctl" "$SPLIT sh .agents-v0/scripts/sync-feature-state.sh $ORD --active-phase design --status in_progress"; then fail "after --update: the split-name override has no effect"
else pass "after --update: the split-name override has no effect"; fi

# 7. strip-test-overrides.sh refuses unbalanced markers
printf 'a\n# >>> kit-test-override\nb\n' > "$tmp/bad.sh"
if sh "$KIT/scripts/strip-test-overrides.sh" "$tmp/bad.sh" >/dev/null 2>&1; then fail "unbalanced markers are refused"; else pass "unbalanced markers are refused"; fi

[ "$status" -eq 0 ] && echo "test-installed-overrides: OK ($n checks)" || { echo "test-installed-overrides: FAILED" >&2; exit 1; }
