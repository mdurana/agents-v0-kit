#!/bin/sh
# test-tests-ran.sh — kitfix-20261031-tests-ran: check-tests-ran.sh fails when test classes exist but
# none ran, or when an *IT.java class has no Surefire/Failsafe report (P1-B). Synthetic reports, no
# Maven or network. Run by validate-kit.sh.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
CK="$KIT/templates/.agents-v0/scripts/check-tests-ran.sh"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0
pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
mod() { m="$tmp/$1/app/backend"; mkdir -p "$m/src/test/java/com/x" "$m/target"; printf '<project/>\n' > "$m/pom.xml"
  for c in $2; do printf 'package com.x; class %s {}\n' "$c" > "$m/src/test/java/com/x/$c.java"; done; printf '%s\n' "$m"; }
report() { mkdir -p "$1/target/$2-reports"; printf '<?xml version="1.0"?>\n<testsuite name="com.x.%s" tests="%s" skipped="%s" failures="0" errors="0"/>\n' "$3" "$4" "${5:-0}" > "$1/target/$2-reports/TEST-com.x.$3.xml"; }
run() { want="$1"; desc="$2"; dir="$3"; if (cd "$dir" && sh "$CK") >"$tmp/out" 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (wanted exit $want, got $got: $(tr '\n' ' ' < "$tmp/out"))"; fi; }

m="$(mod all-ran 'OrderTest OrderRepositoryIT')"; report "$m" surefire OrderTest 3; report "$m" failsafe OrderRepositoryIT 2
run 0 "unit and integration tests both ran" "$tmp/all-ran"
grep -Fq 'surefire 3, failsafe 2' "$tmp/out" && pass "the OK line counts surefire and failsafe" || fail "the OK line counts surefire and failsafe"

m="$(mod it-skipped 'OrderTest OrderRepositoryIT')"; report "$m" surefire OrderTest 3
run 1 "an *IT class with no report fails (P1-B: no Failsafe)" "$tmp/it-skipped"
grep -Fq 'com.x.OrderRepositoryIT' "$tmp/out" && pass "the failure names the IT class" || fail "the failure names the IT class"

mod none-ran 'OrderTest' >/dev/null
run 1 "test classes but no reports at all fails (tests exist but none ran)" "$tmp/none-ran"
grep -Fq 'exist but no test ran' "$tmp/out" && pass "the failure says no test ran" || fail "the failure says no test ran"

m="$(mod all-skipped 'OrderTest')"; report "$m" surefire OrderTest 4 4
run 1 "reports with every test skipped (-DskipTests style) fail" "$tmp/all-skipped"

mkdir -p "$tmp/no-tests/app/backend/src/test/java"; printf '<project/>\n' > "$tmp/no-tests/app/backend/pom.xml"
run 0 "a module with no test classes passes" "$tmp/no-tests"
mkdir -p "$tmp/no-maven"
run 0 "a repo with no Maven module passes" "$tmp/no-maven"

if [ "$status" -ne 0 ]; then echo "test-tests-ran: FAILED" >&2; exit 1; fi
echo "test-tests-ran: OK"
