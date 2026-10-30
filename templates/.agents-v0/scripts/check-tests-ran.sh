#!/bin/sh
# check-tests-ran.sh — after the native build/test command, fail when test classes exist but none
# of them ran, or when an integration test class (*IT.java) has no Surefire or Failsafe report.
# kitfix-20261031-tests-ran: P1-B named its PostgreSQL integration tests *IT.java while the pom had
# no Failsafe, so Maven skipped them silently and the story still "passed".
#
# Usage: sh .agents-v0/scripts/check-tests-ran.sh [<maven module dir> ...]
#   default: every directory under the repo that has a pom.xml and src/test/java (target/ and
#   node_modules/ skipped). Run it after `mvnw verify` (or `mvn verify`), never after `-DskipTests`.
# Exit 0: tests ran (prints OK lines). Exit 1: FAIL lines name the module and the classes.
# Exit 2: usage error. A module with no test classes is reported and passes.
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,12p' "$0"; exit 2
fi

python3 - "$@" <<'PY'
import os, re, sys
import xml.etree.ElementTree as ET

mods = sys.argv[1:]
if not mods:
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in ("target", "node_modules", ".git", "dist")]
        if "pom.xml" in files and os.path.isdir(os.path.join(root, "src", "test", "java")):
            mods.append(os.path.normpath(root))
if not mods:
    print("OK: no Maven module with src/test/java (nothing to check)")
    raise SystemExit(0)

TEST_RE = re.compile(r"(Test|Tests|TestCase|IT)\.java$")
bad = False
for mod in mods:
    src = os.path.join(mod, "src", "test", "java")
    if not os.path.isdir(src):
        print(f"FAIL: {mod}: no src/test/java", file=sys.stderr); bad = True; continue
    classes = {}
    for root, _, files in os.walk(src):
        for f in files:
            if TEST_RE.search(f) and not f.startswith("Abstract"):
                rel = os.path.relpath(os.path.join(root, f), src)[:-5].replace(os.sep, ".")
                classes[rel] = f
    if not classes:
        print(f"OK: {mod}: no test classes")
        continue
    ran, total, per = set(), 0, {"surefire": 0, "failsafe": 0}
    for kind in ("surefire", "failsafe"):
        rdir = os.path.join(mod, "target", f"{kind}-reports")
        if not os.path.isdir(rdir):
            continue
        for f in os.listdir(rdir):
            if not (f.startswith("TEST-") and f.endswith(".xml")):
                continue
            try:
                r = ET.parse(os.path.join(rdir, f)).getroot()
            except ET.ParseError:
                continue
            suites = [r] if r.tag == "testsuite" else r.findall("testsuite")
            for s in suites:
                n = int(s.get("tests", "0") or 0) - int(s.get("skipped", "0") or 0)
                if n > 0:
                    ran.add(s.get("name", ""))
                    total += n
                    per[kind] += n
    if total == 0:
        print(f"FAIL: {mod}: {len(classes)} test class(es) exist but no test ran "
              f"(no non-skipped tests in target/surefire-reports or target/failsafe-reports). "
              f"Run the native verify command (mvnw verify) and check the test naming.", file=sys.stderr)
        bad = True
        continue
    it_missing = sorted(c for c, f in classes.items() if f.endswith("IT.java") and c not in ran)
    other_missing = sorted(c for c, f in classes.items() if not f.endswith("IT.java") and c not in ran)
    if it_missing:
        print(f"FAIL: {mod}: {len(it_missing)} integration test class(es) did not run "
              f"(no Surefire/Failsafe report). Add maven-failsafe-plugin (the kit skeleton has it) "
              f"or fix the naming:", file=sys.stderr)
        for c in it_missing[:10]:
            print(f"  - {c}", file=sys.stderr)
        bad = True
    for c in other_missing[:10]:
        print(f"WARN: {mod}: {c} has no test report (abstract base, filtered, or not a test?)", file=sys.stderr)
    print(f"OK: {mod}: {total} test(s) ran from {len(ran)} class(es) "
          f"(surefire {per['surefire']}, failsafe {per['failsafe']}); {len(classes)} test class(es) on disk")
raise SystemExit(1 if bad else 0)
PY
