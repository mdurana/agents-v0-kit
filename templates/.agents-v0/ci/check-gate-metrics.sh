#!/bin/sh
# check-gate-metrics.sh — read machine output for one module instead of trusting
# numbers an agent wrote into a report (workflow-orchestration.mdc Verify gate).
#
# Usage: sh .agents-v0/ci/check-gate-metrics.sh <module-root>
#   <module-root>  the service root. A pom.xml or target/ directory uses the Java
#   reports below. Otherwise a *.csproj, go.mod, pyproject.toml, or package.json
#   selects the dotnet, go, python, or node reports named in that pack's PACK.md.
#
# Java, under <module-root>/target:
#   surefire-reports/TEST-*.xml, failsafe-reports/TEST-*.xml  executed tests, failures, errors
#   site/jacoco/jacoco.xml                                    line coverage, optional diff coverage
#   dependency-check-report.json                              unsuppressed HIGH/CRITICAL CVEs
#
# Environment:
#   ALLOW_NO_TESTS=1       do not fail when no test report exists (module with no tests)
#   MIN_LINE_PCT=<n>       fail when bundle line coverage is below n (unset: report only;
#                          the JaCoCo check goal and docs/agents-v0/project-profile.md coverage_ratchet own it)
#   DIFF_BASE=<git-rev>    also measure coverage of Java lines added since merge-base(DIFF_BASE, HEAD)
#   MIN_DIFF_LINE_PCT=<n>  diff coverage minimum (default 80)
#   REQUIRE_CVE_REPORT=1   fail when dependency-check-report.json is missing
#   /v0-verify sets DIFF_BASE and REQUIRE_CVE_REPORT together. It omits both only while a
#   later story named in Out of scope, whose job is the quality gate, has no Verify
#   approval. The seeded P0 skeleton does not use that skip. The test report quotes the
#   story id. Unset, diff coverage and a missing CVE report are not failures.
#   GATE_METRICS_OUT=<f>   JSON summary path (default <module-root>/target/gate-metrics.json)
#   GATE_REPORT_ONLY=1     measure and write the summary, but exit 0 (brownfield onboarding baseline)
#   KNOWN_FAILURES_PROFILE=<f>  profile that holds the known_failures table (default
#                          docs/agents-v0/project-profile.md, relative to the working directory).
#                          Test failures up to its Allowed failure count are reported, not failed.
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

DIR="$(cd "$(dirname "$0")" && pwd)"
GATE_ROOT="$root" PACKLIB_DIR="$DIR" python3 - <<'PY'
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


def known_failures_budget():
    """Allowed failure count from the known_failures table of the project profile (0 when none)."""
    path = env("KNOWN_FAILURES_PROFILE") or os.path.join("docs", "agents-v0", "project-profile.md")
    if not os.path.isfile(path):
        return 0
    in_section = False
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("#"):
                in_section = "known_failures" in stripped
                continue
            if in_section and stripped.startswith("|"):
                cells = [cell.strip() for cell in stripped.strip("|").split("|")]
                if cells and cells[0].isdigit() and int(cells[0]) > 0:
                    return int(cells[0])
    return 0


def module_kind(path):
    """Java when this root already looks like a Maven module. Other packs only when it does not."""
    if os.path.isdir(os.path.join(path, "target")) or os.path.isfile(os.path.join(path, "pom.xml")):
        return "java"
    if glob.glob(os.path.join(path, "*.csproj")) or glob.glob(os.path.join(path, "*.sln")):
        return "dotnet"
    if os.path.isfile(os.path.join(path, "go.mod")):
        return "go"
    if os.path.isfile(os.path.join(path, "pyproject.toml")) or os.path.isfile(os.path.join(path, "pytest.ini")):
        return "python"
    if os.path.isfile(os.path.join(path, "package.json")):
        return "node"
    return "java"


def junit_totals(paths):
    tests = fails = errors = skipped = 0
    used = False
    for path in paths:
        if not os.path.isfile(path):
            continue
        used = True
        try:
            top = ET.parse(path).getroot()
        except ET.ParseError:
            failures.append(f"unreadable test report: {path}")
            continue
        suites = [top] if top.tag == "testsuite" or top.tag.endswith("testsuite") else [
            node for node in top.iter() if node.tag == "testsuite" or node.tag.endswith("testsuite")
        ]
        for suite in suites:
            tests += int(suite.get("tests", 0))
            fails += int(suite.get("failures", 0))
            errors += int(suite.get("errors", 0))
            skipped += int(suite.get("skipped", 0))
    return tests, fails, errors, skipped, used


def record_tests(tests, fails, errors, skipped, used):
    summary["tests"] = {"run": tests, "failures": fails, "errors": errors, "skipped": skipped}
    if (not used or tests == 0) and env("ALLOW_NO_TESTS") != "1":
        failures.append("no executed tests (ALLOW_NO_TESTS=1 for a module with no tests)")
    if fails + errors > 0:
        budget = known_failures_budget()
        if fails + errors <= budget:
            summary["known_failures_budget"] = budget
            print(f"tests: {fails + errors} failure(s) within the documented known_failures budget ({budget})")
        else:
            failures.append(f"test failures={fails} errors={errors}")
    print(f"tests: run={tests} failures={fails} errors={errors} skipped={skipped}")


def record_coverage(pct, missing_name):
    if pct is None:
        print(f"coverage: SKIP (no {missing_name})")
        if env("DIFF_BASE"):
            failures.append(f"DIFF_BASE is set but {missing_name} is missing")
        return
    summary["lineCoveragePct"] = round(pct, 2)
    print(f"coverage: bundle lines {pct:.2f}%")
    minimum = number("MIN_LINE_PCT")
    if minimum is not None and pct < minimum:
        failures.append(f"bundle line coverage {pct:.2f}% < {minimum:g}%")


def cobertura_pct(path):
    if not path or not os.path.isfile(path):
        return None
    rate = ET.parse(path).getroot().get("line-rate")
    return None if rate is None else float(rate) * 100.0


def jest_pct(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    pct = (data.get("total") or {}).get("lines", {}).get("pct")
    return float(pct) if isinstance(pct, (int, float)) else None


def gocover_pct(path):
    if not os.path.isfile(path):
        return None
    covered = total = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) != 3 or parts[0].startswith("mode:"):
                continue
            stmts, hits = int(parts[1]), int(parts[2])
            total += stmts
            if hits > 0:
                covered += stmts
    return None if total == 0 else 100.0 * covered / total


def trx_totals(paths):
    tests = fails = errors = 0
    used = False
    for path in paths:
        used = True
        try:
            tree = ET.parse(path)
        except ET.ParseError:
            failures.append(f"unreadable test report: {path}")
            continue
        for el in tree.iter():
            if el.tag.endswith("Counters"):
                tests += int(el.get("executed") or el.get("total") or 0)
                fails += int(el.get("failed") or 0)
                errors += int(el.get("error") or 0)
    return tests, fails, errors, 0, used


def go_json_totals(path):
    if not os.path.isfile(path):
        return 0, 0, 0, 0, False
    tests = fails = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not obj.get("Test"):
                continue
            if obj.get("Action") == "pass":
                tests += 1
            elif obj.get("Action") == "fail":
                tests += 1
                fails += 1
    return tests, fails, 0, 0, True


def git_added(glob_pattern, base):
    """Lines added since DIFF_BASE for one pathspec. Empty dict when the diff cannot be read."""
    try:
        merge_base = subprocess.run(
            ["git", "-C", root, "merge-base", base, "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        diff = subprocess.run(
            ["git", "-C", root, "diff", "-U0", "--relative", merge_base, "HEAD", "--", glob_pattern],
            capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, OSError) as exc:
        failures.append(f"DIFF_BASE {base} could not be diffed: {exc}")
        return {}
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
            added.setdefault(current.replace("\\", "/"), set()).update(range(start, start + count))
    return added


def lookup_lines(tracked, path, source_root):
    norm = path.replace("\\", "/")
    if source_root and source_root.strip("/") not in norm:
        return None
    if norm in tracked:
        return tracked[norm]
    tail = norm.split(source_root.strip("/") + "/", 1)[-1] if source_root else norm
    for key, lines in tracked.items():
        key_norm = key.replace("\\", "/")
        if key_norm == tail or norm.endswith("/" + key_norm) or key_norm.endswith("/" + tail):
            return lines
    return None


def score_diff(tracked, glob_pattern, source_root):
    """Changed-line coverage. No DIFF_BASE means the gate does not apply."""
    base = env("DIFF_BASE")
    if not base:
        return
    if tracked is None:
        failures.append("DIFF_BASE is set but the coverage report has no line data")
        return
    minimum = number("MIN_DIFF_LINE_PCT", 80.0)
    added = git_added(glob_pattern, base)
    covered_n = missed_n = 0
    for path, numbers in added.items():
        lines = lookup_lines(tracked, path, source_root)
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
        print("coverage: no measurable changed lines since the merge base")


def cobertura_lines(path):
    if not os.path.isfile(path):
        return None
    tracked = {}
    for cls in ET.parse(path).iter():
        if cls.tag != "class" and not cls.tag.endswith("}class"):
            continue
        filename = (cls.get("filename") or "").replace("\\", "/")
        lines = {}
        for ln in list(cls):
            if ln.tag != "line" and not ln.tag.endswith("}line"):
                for nested in ln.iter():
                    if nested.tag == "line" or nested.tag.endswith("}line"):
                        number = nested.get("number")
                        if number and number.isdigit():
                            hits = nested.get("hits")
                            lines[int(number)] = hits is None or int(float(hits)) > 0
                continue
            number = ln.get("number")
            if number and number.isdigit():
                hits = ln.get("hits")
                lines[int(number)] = hits is None or int(float(hits)) > 0
        if filename and lines:
            tracked[filename] = lines
    return tracked


def go_lines(path):
    if not os.path.isfile(path):
        return None
    tracked = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("mode:") or ":" not in line:
                continue
            match = re.match(r"(.+):(\d+)\.\d+,(\d+)\.\d+ \d+ (\d+)", line.strip())
            if not match:
                continue
            file, start, end, count = match.group(1), int(match.group(2)), int(match.group(3)), int(match.group(4))
            bucket = tracked.setdefault(file.replace("\\", "/"), {})
            for n in range(start, end + 1):
                bucket[n] = bucket.get(n, False) or count > 0
    return tracked


def lcov_lines(path):
    if not os.path.isfile(path):
        return None
    tracked, current = {}, None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("SF:"):
                current = line[3:].strip().replace("\\", "/")
                tracked.setdefault(current, {})
            elif line.startswith("DA:") and current:
                number, hits = line[3:].split(",")[:2]
                tracked[current][int(number)] = int(hits) > 0
    return tracked


def node_lines():
    lcov = os.path.join(root, "coverage", "lcov.info")
    if os.path.isfile(lcov):
        return lcov_lines(lcov)
    final = os.path.join(root, "coverage", "coverage-final.json")
    if not os.path.isfile(final):
        return None
    tracked = {}
    with open(final, encoding="utf-8") as handle:
        data = json.load(handle)
    for path, info in data.items():
        lines = {}
        counts = info.get("s") or {}
        for key, span in (info.get("statementMap") or {}).items():
            start = (span.get("start") or {}).get("line")
            end = (span.get("end") or {}).get("line") or start
            if not start:
                continue
            hit = int(counts.get(key) or 0) > 0
            for n in range(int(start), int(end) + 1):
                lines[n] = lines.get(n, False) or hit
        if lines:
            tracked[path.replace("\\", "/")] = lines
    return tracked


def alt_diff(kind):
    spec = (bound_pack or {}).get("diffCoverage") or {}
    glob_pattern = spec.get("glob") or {
        "dotnet": "*.cs", "python": "*.py", "node": "*.ts", "go": "*.go",
    }.get(kind, "*")
    source_root = spec.get("sourceRoot") or ""
    if kind == "dotnet":
        reports = glob.glob(os.path.join(root, "**", "coverage.cobertura.xml"), recursive=True)
        tracked = cobertura_lines(reports[0]) if reports else None
    elif kind == "python":
        tracked = cobertura_lines(os.path.join(root, "coverage.xml"))
    elif kind == "node":
        tracked = node_lines()
    elif kind == "go":
        tracked = go_lines(os.path.join(root, "coverage.out"))
    else:
        tracked = None
    score_diff(tracked, glob_pattern, source_root)


def measure_alt(kind):
    if kind == "dotnet":
        trx = glob.glob(os.path.join(root, "TestResults", "**", "*.trx"), recursive=True)
        trx += glob.glob(os.path.join(root, "*.trx"))
        record_tests(*trx_totals(trx))
        cobertura = glob.glob(os.path.join(root, "**", "coverage.cobertura.xml"), recursive=True)
        record_coverage(cobertura_pct(cobertura[0]) if cobertura else None, "coverage.cobertura.xml")
    elif kind == "python":
        reports = [path for path in (
            os.path.join(root, "pytest-report.xml"),
            os.path.join(root, "test-results.xml"),
            os.path.join(root, "junit.xml"),
        ) if os.path.isfile(path)]
        record_tests(*junit_totals(reports))
        record_coverage(cobertura_pct(os.path.join(root, "coverage.xml")), "coverage.xml")
    elif kind == "node":
        reports = [path for path in (
            os.path.join(root, "junit.xml"),
            os.path.join(root, "test-results.xml"),
            os.path.join(root, "reports", "junit.xml"),
        ) if os.path.isfile(path)]
        record_tests(*junit_totals(reports))
        record_coverage(jest_pct(os.path.join(root, "coverage", "coverage-summary.json")), "coverage/coverage-summary.json")
    elif kind == "go":
        record_tests(*go_json_totals(os.path.join(root, "go-test.json")))
        record_coverage(gocover_pct(os.path.join(root, "coverage.out")), "coverage.out")
    else:
        failures.append(f"unknown pack {kind}")
    alt_diff(kind)
    record_cve(os.path.join(root, "cve-report.json"))


def record_cve(path):
    """Same HIGH/CRITICAL shape as target/dependency-check-report.json."""
    if not os.path.isfile(path):
        if env("REQUIRE_CVE_REPORT") == "1":
            failures.append(f"missing {os.path.basename(path)} (REQUIRE_CVE_REPORT=1)")
        else:
            print(f"cve: SKIP (no {os.path.basename(path)})")
        return
    with open(path, encoding="utf-8") as handle:
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


def finish():
    out = env("GATE_METRICS_OUT") or os.path.join(root, "target", "gate-metrics.json")
    if not os.path.isdir(os.path.join(root, "target")):
        out = env("GATE_METRICS_OUT") or os.path.join(root, "gate-metrics.json")
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
    raise SystemExit(0)


bound_pack = {}


def kind_from_pack():
    """A bound Pack selects the report format. An empty Pack leaves detection alone."""
    sys.path.insert(0, os.environ["PACKLIB_DIR"])
    import packlib
    pack_id = packlib.profile_pack()
    if not pack_id:
        return ""
    data = packlib.load(pack_id)
    if data is None or packlib.errors_of(data, "backend"):
        failures.append(f"Pack {pack_id} has no complete manifest")
        return "missing"
    global bound_pack
    bound_pack = data
    report = (data.get("testsReport") or {}).get("format")
    coverage = (data.get("coverage") or {}).get("format")
    summary["pack"] = pack_id
    if coverage == "jacoco":
        return "java"
    if coverage == "go-cover" or report == "go-json":
        return "go"
    if coverage == "jest-summary":
        return "node"
    if report == "trx":
        return "dotnet"
    if coverage == "cobertura" or report in ("junit", "pytest"):
        return "python"
    failures.append(f"Pack {pack_id} coverage format {coverage} is not measured")
    return "missing"


kind = kind_from_pack() or module_kind(root)
summary["kind"] = kind
if kind == "missing":
    finish()
if kind != "java":
    measure_alt(kind)
    finish()


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
    budget = known_failures_budget()
    if fails + errors <= budget:
        summary["known_failures_budget"] = budget
        print(f"tests: {fails + errors} failure(s) within the documented known_failures budget ({budget})")
    else:
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

finish()
PY
