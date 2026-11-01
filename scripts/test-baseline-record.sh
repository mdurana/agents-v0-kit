#!/bin/sh
# test-baseline-record.sh: JO-15a, the baseline audit record (onboard fix design, revision 6).
# audit-brownfield-baseline.sh --record saves a short summary to docs/agents-v0/discovery/baseline-audit.txt:
# result, exit code, commands run (redacted), commit, time with its offset, and on a red result the
# failing test names (names only, never build output; Sensei 2A, SOC-8). Without --record it writes nothing.
# Cases: E18 (pass, fail, no build), E19 (no --record writes nothing; the two copies match), N25 (no token
# in the record), N58 record half (failing test names). Tier 1: offline, on an installed copy.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

AUDIT=.agents-v0/scripts/audit-brownfield-baseline.sh
REC=docs/agents-v0/discovery/baseline-audit.txt
# A fake token built at run time, so no token-shaped text sits in the kit.
TOK="ghp_$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)$(printf 'r7%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
PIPTOK="pp$(printf 'Zk%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17)"

# --- the two copies -----------------------------------------------------------
if cmp -s "$KIT/scripts/audit-brownfield-baseline.sh" "$KIT/templates/.agents-v0/scripts/audit-brownfield-baseline.sh"; then
  pass "E19: scripts/ and templates/ copies of the audit are identical"
else
  fail "E19: scripts/ and templates/ copies of the audit are identical"
fi
has "E19: validate-kit compares the two audit copies" "$KIT/scripts/validate-kit.sh" "cmp -s scripts/audit-brownfield-baseline.sh templates/.agents-v0/scripts/audit-brownfield-baseline.sh"
lacks "header no longer says to run the audit before build or maintain" "$KIT/templates/.agents-v0/scripts/audit-brownfield-baseline.sh" "Use before /v0-build or /v0-maintain"

# --- fixture: a brownfield repo with a fake build --------------------------------
r="$(t1_repo brown --commit)"
t1_install "$r" || fail "install into the fixture (see $T1_TMP/install.log)"
python3 - "$r/docs/agents-v0/project-profile.md" "$PIPTOK" <<'PY'
import re, sys
p, tok = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
t = re.sub(r"^\| Backend verify \|.*$", "| Backend verify | sh fake-build.sh --mirror https://ci:%s@mirror.example/simple |" % tok, t, count=1, flags=re.M)
t = re.sub(r"^\| Timezone \|.*$", "| Timezone | Asia/Manila |", t, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(t)
PY
cat > "$r/fake-build.sh" <<FAKE
#!/bin/sh
mode="\$(cat .fake-mode 2>/dev/null || echo pass)"
echo "BUILD-OUTPUT-MARKER compiling 12 files"
echo "Downloading with token $TOK"
echo "acme-sdk @ git+https://ci:$PIPTOK@git.example/acme-sdk.git"
[ "\$mode" = pass ] && { echo "BUILD SUCCESS"; exit 0; }
echo "FAILED tests/test_orders.py::test_create_order - AssertionError: expected 3"
echo "--- FAIL: TestInventoryReserve (0.01s)"
echo "[ERROR]   OrderServiceTest.createsOrder:42 expected:<1> but was:<2>"
echo "[ERROR] Tests run: 9, Failures: 1, Errors: 0, Skipped: 0"
echo "PaymentTest > refundsTwice() FAILED"
echo "  Failed Acme.Billing.InvoiceTests.TotalsRound [12 ms]"
echo "--- FAIL: Test$TOK (0.00s)"
mkdir -p target/surefire-reports
cat > target/surefire-reports/TEST-com.acme.LedgerTest.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.acme.LedgerTest" tests="2" failures="1">
  <testcase classname="com.acme.LedgerTest" name="balances"><failure message="XML-FAILURE-MESSAGE">stack</failure></testcase>
  <testcase classname="com.acme.LedgerTest" name="opens"/>
</testsuite>
XML
exit 1
FAKE
printf '%s\n' target/ .fake-mode > "$r/.gitignore"
G "$r" add -A >/dev/null 2>&1 && G "$r" commit -qm "brownfield fixture" >/dev/null 2>&1 || fail "fixture commit"
head="$(G "$r" rev-parse HEAD)"

# --- E19: without --record nothing is written ------------------------------------
echo pass > "$r/.fake-mode"
t1_snapshot "$r" "$T1_TMP/before.txt"
expect_pass "E19: audit without --record passes on a green build" "$r" sh "$AUDIT"
t1_snapshot "$r" "$T1_TMP/after.txt"
if cmp -s "$T1_TMP/before.txt" "$T1_TMP/after.txt"; then pass "E19: audit without --record leaves the repo byte-identical"; else fail "E19: audit without --record leaves the repo byte-identical"; fi
echo fail > "$r/.fake-mode"
expect_fail "E19: audit without --record still fails on a red build" "$r" sh "$AUDIT"
[ ! -e "$r/$REC" ] && pass "E19: a red run without --record writes no record" || fail "E19: a red run without --record writes no record"

# --- E18: green run with --record ------------------------------------------------
echo pass > "$r/.fake-mode"
expect_pass "E18: audit --record exits 0 on a green build" "$r" sh "$AUDIT" --record
has "E18: the build output still reaches the screen" "$T1_TMP/out.txt" "BUILD-OUTPUT-MARKER"
has "E18 pass: record says PASSED" "$r/$REC" "result: PASSED"
has "E18 pass: record has exit 0" "$r/$REC" "exit: 0"
has "E18 pass: record has the full commit" "$r/$REC" "commit: $head"
has "E18 pass: record names the command run" "$r/$REC" "command: Backend verify: sh fake-build.sh --mirror https://***@mirror.example/simple"
if grep -Eq '^time: 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+0800 \(Asia/Manila\)$' "$r/$REC"; then pass "E18 pass: record time carries the project zone offset"; else fail "E18 pass: record time carries the project zone offset"; fi
lacks "E18 pass: no failing-test lines on a green run" "$r/$REC" "failing-test:"
lacks "E18 pass: record holds no build output" "$r/$REC" "BUILD-OUTPUT-MARKER"

# --- E18 / N58 / N25: red run with --record --------------------------------------
echo fail > "$r/.fake-mode"
if (cd "$r" && sh "$AUDIT" --record) > "$T1_TMP/out.txt" 2>&1; then rc=0; else rc=$?; fi
[ "$rc" = 1 ] && pass "E18 fail: audit --record keeps exit 1 on a red build" || fail "E18 fail: audit --record keeps exit 1 on a red build (got $rc)"
has "E18 fail: record says FAILED" "$r/$REC" "result: FAILED"
has "E18 fail: record has exit 1" "$r/$REC" "exit: 1"
for n in tests/test_orders.py::test_create_order TestInventoryReserve OrderServiceTest.createsOrder \
         "PaymentTest.refundsTwice()" Acme.Billing.InvoiceTests.TotalsRound com.acme.LedgerTest.balances; do
  has "N58: record lists failing test $n" "$r/$REC" "failing-test: $n"
done
lacks "N58: passing tests are not listed" "$r/$REC" "com.acme.LedgerTest.opens"
lacks "N58: names only, no assertion text" "$r/$REC" "AssertionError"
lacks "N58: names only, no maven message" "$r/$REC" "but was"
lacks "N58: names only, no XML failure message" "$r/$REC" "XML-FAILURE-MESSAGE"
lacks "N25: record holds no build output" "$r/$REC" "BUILD-OUTPUT-MARKER"
lacks "N25: the planted token is not in the record" "$r/$REC" "$TOK"
lacks "N25: the pip token URL is not in the record" "$r/$REC" "$PIPTOK"
has "N25: a token-shaped test name is withheld and counted" "$r/$REC" "failing-tests-withheld: 1"
[ "$(grep -c '' "$r/$REC")" -le 40 ] && pass "N25: the record is a short summary" || fail "N25: the record is a short summary"

# --- E18: no build found ---------------------------------------------------------
n="$(t1_repo nobuild --commit)"
t1_install "$n" || fail "install into the no-build fixture"
if (cd "$n" && sh "$AUDIT" --record) > "$T1_TMP/out.txt" 2>&1; then rc=0; else rc=$?; fi
[ "$rc" = 2 ] && pass "E18 no build: audit --record keeps exit 2" || fail "E18 no build: audit --record keeps exit 2 (got $rc)"
has "E18 no build: record says NO-BUILD" "$n/$REC" "result: NO-BUILD"
has "E18 no build: record has exit 2" "$n/$REC" "exit: 2"
has "E18 no build: record says no command ran" "$n/$REC" "command: none"

# --- arguments and write failures ------------------------------------------------
expect_fail "an unknown option is refused" "$r" sh "$AUDIT" --recrod
has "an unknown option is named as unknown" "$T1_TMP/out.txt" "unknown option: --recrod"
echo pass > "$r/.fake-mode"
expect_pass "--record after the target path works" "$T1_TMP" sh "$r/$AUDIT" "$r" --record
has "--record after the target writes into the target" "$r/$REC" "result: PASSED"
w="$(t1_repo blocked --commit)"
t1_install "$w" || fail "install into the blocked fixture"
cp "$r/docs/agents-v0/project-profile.md" "$w/docs/agents-v0/project-profile.md"; cp "$r/fake-build.sh" "$w/"
rmdir "$w/docs/agents-v0/discovery" 2>/dev/null || :
[ -d "$w/docs/agents-v0/discovery" ] || : > "$w/docs/agents-v0/discovery"
if (cd "$w" && sh "$AUDIT" --record) > "$T1_TMP/out.txt" 2>&1; then rc=0; else rc=$?; fi
if [ -f "$w/docs/agents-v0/discovery" ]; then
  [ "$rc" = 3 ] && pass "a record that cannot be written stops with exit 3" || fail "a record that cannot be written stops with exit 3 (got $rc)"
  has "the write failure is explained" "$T1_TMP/out.txt" "could not write"
else
  pass "write-failure case skipped: the install keeps a discovery folder with files"
fi

t1_done test-baseline-record
