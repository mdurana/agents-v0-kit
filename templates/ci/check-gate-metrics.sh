#!/bin/sh
# check-gate-metrics.sh — read machine output for one Maven module instead of trusting
# numbers an agent wrote into a report (workflow-orchestration.mdc Verify gate).
#
# Usage: sh ci/check-gate-metrics.sh <module-root>
#   <module-root>  directory that holds pom.xml and target/ (e.g. backend, services/order)
#
# Reads, under <module-root>/target:
#   surefire-reports/TEST-*.xml, failsafe-reports/TEST-*.xml  executed tests, failures, errors
#   site/jacoco/jacoco.xml                                    line coverage, optional diff coverage
#   dependency-check-report.json                              unsuppressed HIGH/CRITICAL CVEs
#
# Environment:
#   ALLOW_NO_TESTS=1       do not fail when no test report exists (module with no tests)
#   MIN_LINE_PCT=<n>       fail when bundle line coverage is below n (unset: report only;
#                          the JaCoCo check goal and docs/project-profile.md coverage_ratchet own it)
#   DIFF_BASE=<git-rev>    also measure coverage of Java lines added since merge-base(DIFF_BASE, HEAD)
#   MIN_DIFF_LINE_PCT=<n>  diff coverage minimum (default 80)
#   REQUIRE_CVE_REPORT=1   fail when dependency-check-report.json is missing
#   GATE_METRICS_OUT=<f>   JSON summary path (default <module-root>/target/gate-metrics.json)
#   GATE_REPORT_ONLY=1     measure and write the summary, but exit 0 (brownfield onboarding baseline)
#
# Exit 0 when every measured gate passes; 1 otherwise.

set -eu

root="${1:-}"
if [ -z "$root" ]; then
  printf 'usage: %s <module-root>\n' "$0" >&2
  exit 1
fi
[ -d "$root" ] || { printf 'FAIL: module root not found: %s\n' "$root" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

GATE_ROOT="$root" python3 - <<'PY'
import glob
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

root = os.environ["GATE_ROOT"]
env = os.environ.get
failures = []
summary = {"root": root}


def number(name, default=None):
    raw = env(name)
    if raw in (None, ""):
        return default
    try:
        return float(raw)
    except ValueError:
        print(f"FAIL: {name} is not a number: {raw}", file=sys.stderr)
        raise SystemExit(1)


# Executed tests: a green build with zero executed tests is not evidence.
reports = glob.glob(os.path.join(root, "target", "surefire-reports", "TEST-*.xml"))
reports += glob.glob(os.path.join(root, "target", "failsafe-reports", "TEST-*.xml"))
tests = fails = errors = skipped = 0
for path in reports:
    try:
        top = ET.parse(path).getroot()
    except ET.ParseError:
        failures.append(f"unreadable test report: {path}")
        continue
    suites = [top] if top.tag == "testsuite" else list(top.iter("testsuite"))
    for suite in suites:
        tests += int(suite.get("tests", 0))
        fails += int(suite.get("failures", 0))
        errors += int(suite.get("errors", 0))
        skipped += int(suite.get("skipped", 0))
summary["tests"] = {"run": tests, "failures": fails, "errors": errors, "skipped": skipped}
if (not reports or tests == 0) and env("ALLOW_NO_TESTS") != "1":
    failures.append("no executed tests under target/surefire-reports or target/failsafe-reports (ALLOW_NO_TESTS=1 for a module with no tests)")
if fails + errors > 0:
    failures.append(f"test failures={fails} errors={errors}")
print(f"tests: run={tests} failures={fails} errors={errors} skipped={skipped}")

# Coverage.
jacoco = os.path.join(root, "target", "site", "jacoco", "jacoco.xml")
tracked = {}
line_pct = None
if os.path.isfile(jacoco):
    report = ET.parse(jacoco).getroot()
    for counter in report.findall("counter"):
        if counter.get("type") == "LINE":
            missed, covered = int(counter.get("missed")), int(counter.get("covered"))
            line_pct = 100.0 * covered / (missed + covered) if missed + covered else 100.0
    for package in report.iter("package"):
        for source in package.findall("sourcefile"):
            key = package.get("name") + "/" + source.get("name")
            tracked[key] = {int(ln.get("nr")): int(ln.get("ci", 0)) > 0 for ln in source.findall("line")}
    summary["lineCoveragePct"] = None if line_pct is None else round(line_pct, 2)
    if line_pct is not None:
        print(f"coverage: bundle lines {line_pct:.2f}%")
        minimum = number("MIN_LINE_PCT")
        if minimum is not None and line_pct < minimum:
            failures.append(f"bundle line coverage {line_pct:.2f}% < {minimum:g}%")
else:
    print("coverage: SKIP (no target/site/jacoco/jacoco.xml)")
    if env("DIFF_BASE"):
        failures.append("DIFF_BASE is set but target/site/jacoco/jacoco.xml is missing")

# Diff coverage: Java lines added since the merge base, the "changed code" minimum.
base = env("DIFF_BASE")
if base and os.path.isfile(jacoco):
    minimum = number("MIN_DIFF_LINE_PCT", 80.0)
    try:
        merge_base = subprocess.run(
            ["git", "-C", root, "merge-base", base, "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        diff = subprocess.run(
            ["git", "-C", root, "diff", "-U0", "--relative", merge_base, "HEAD", "--", "*.java"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, OSError) as exc:
        failures.append(f"DIFF_BASE {base} could not be diffed: {exc}")
        diff = ""
    added, current = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            target = line[4:]
            current = target[2:] if target.startswith("b/") else None
            continue
        hunk = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if hunk and current:
            start = int(hunk.group(1))
            count = int(hunk.group(2)) if hunk.group(2) is not None else 1
            added.setdefault(current, set()).update(range(start, start + count))
    covered_n = missed_n = 0
    for path, numbers in added.items():
        if "src/main/java/" not in path:
            continue
        lines = tracked.get(path.split("src/main/java/", 1)[1])
        if lines is None:
            continue
        for n in numbers:
            if n in lines:
                if lines[n]:
                    covered_n += 1
                else:
                    missed_n += 1
    total = covered_n + missed_n
    if total:
        diff_pct = 100.0 * covered_n / total
        summary["diffCoveragePct"] = round(diff_pct, 2)
        print(f"coverage: changed lines {covered_n}/{total} = {diff_pct:.2f}% (minimum {minimum:g}%)")
        if diff_pct < minimum:
            failures.append(f"diff coverage {diff_pct:.2f}% < {minimum:g}%")
    else:
        print("coverage: no measurable changed Java lines since the merge base")

# CVEs: unsuppressed HIGH or CRITICAL findings.
dependency_report = os.path.join(root, "target", "dependency-check-report.json")
if os.path.isfile(dependency_report):
    with open(dependency_report, encoding="utf-8") as handle:
        data = json.load(handle)
    found = []
    for dep in data.get("dependencies", []):
        for vuln in dep.get("vulnerabilities") or []:
            if str(vuln.get("severity", "")).upper() in ("HIGH", "CRITICAL"):
                found.append(str(vuln.get("name", "?")))
    summary["highCriticalCves"] = sorted(set(found))
    print(f"cve: {len(set(found))} unsuppressed HIGH/CRITICAL")
    if found:
        failures.append("unsuppressed HIGH/CRITICAL CVEs: " + ", ".join(sorted(set(found))))
elif env("REQUIRE_CVE_REPORT") == "1":
    failures.append("missing target/dependency-check-report.json (run the ci-security profile with the JSON format)")
else:
    print("cve: SKIP (no target/dependency-check-report.json)")

out = env("GATE_METRICS_OUT") or os.path.join(root, "target", "gate-metrics.json")
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
summary["failures"] = failures
with open(out, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)
    handle.write("\n")

if failures:
    report_only = env("GATE_REPORT_ONLY") == "1"
    for item in failures:
        print(f"{'WARN' if report_only else 'FAIL'}: {item}", file=sys.stderr)
    if report_only:
        print(f"REPORT-ONLY: measured {root}; no gate applied (summary: {out})")
        raise SystemExit(0)
    raise SystemExit(1)
print(f"OK: gate metrics for {root} (summary: {out})")
PY
