#!/bin/sh
# check-gate-metrics.sh — read machine output for one module instead of trusting
# numbers an agent wrote into a report (workflow-orchestration.mdc Verify gate).
#
# Usage: sh .agents-v0/ci/check-gate-metrics.sh <module-root>
#   <module-root>  the service root. A bound Pack reads coverage.path, testsReport.path,
#   and cve.path from that pack's pack.json. The format selects the reader
#   (jacoco, cobertura, go-cover, jest-summary, junit, trx, go-json).
#   An empty Pack uses a module marker when one is present (pom.xml or target/,
#   *.csproj, go.mod, pyproject.toml, package.json). No marker does not assume Java.
#
# Reports may also be under ci-artifacts/gate/<module-root>/, where
# collect-gate-reports.sh publishes them for a later CI job.
#
# Environment:
#   ALLOW_NO_TESTS=1       do not fail when no test report exists (module with no tests)
#   MIN_LINE_PCT=<n>       fail when bundle line coverage is below n (default: Whole-module lines from
#                          docs/agents-v0/quality-gates.md, or unset: report only).
#                          Pack java's JaCoCo check goal is a fixed 0.80. coverage_ratchet does not
#                          change it; check-coverage-ratchet.sh compares a number only when
#                          LINE_COVERAGE_PCT or JACOCO_LINE_PCT is set.
#   DIFF_BASE=<git-rev>    also measure coverage of Java lines added since merge-base(DIFF_BASE, HEAD)
#   MIN_DIFF_LINE_PCT=<n>  diff coverage minimum (default: Changed lines from
#                          docs/agents-v0/quality-gates.md, or 80)
#   QUALITY_GATES_FILE=<f> path to quality-gates.md (default docs/agents-v0/quality-gates.md)
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


def quality_gates_thresholds():
    """Thresholds from the Coverage table of docs/agents-v0/quality-gates.md (QUALITY_GATES_FILE)."""
    path = env("QUALITY_GATES_FILE") or os.path.join("docs", "agents-v0", "quality-gates.md")
    if not os.path.isfile(path):
        return {}
    thresholds = {}
    in_coverage = False
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("#"):
                in_coverage = "coverage" in stripped.lower()
                continue
            if in_coverage and stripped.startswith("|"):
                cells = [c.strip() for c in stripped.strip("|").split("|")]
                if len(cells) >= 2:
                    area = cells[0].lower()
                    val = cells[1].rstrip("%").strip()
                    if re.fullmatch(r"\d+(?:\.\d+)?", val):
                        num = float(val)
                        if "changed line" in area or "diff" in area:
                            thresholds["diff_line_pct"] = num
                        elif "whole-module" in area or "bundle line" in area:
                            thresholds["min_line_pct"] = num
                        elif "backend line" in area:
                            thresholds["backend_line_pct"] = num
                        elif "frontend" in area:
                            thresholds["frontend_line_pct"] = num
    return thresholds


def module_kind(path):
    """A marker selects a known reader. No marker does not assume Java."""
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
    return ""


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
    qg = quality_gates_thresholds()
    minimum = number("MIN_LINE_PCT", qg.get("min_line_pct"))
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


def resolve_merge_base(base):
    """Resolve merge-base(base, HEAD). If base == HEAD (e.g. working directly on main), fall back to feature baseCommit, build-report commit^, or pre-doc parent."""
    merge_base = subprocess.run(
        ["git", "-C", root, "merge-base", base, "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    head_sha = subprocess.run(
        ["git", "-C", root, "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    if merge_base and merge_base == head_sha:
        top = subprocess.run(
            ["git", "-C", root, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=False,
        ).stdout.strip() or os.getcwd()

        def rev_commit(rev):
            if not rev:
                return ""
            r = subprocess.run(
                ["git", "-C", root, "rev-parse", "--verify", "-q", f"{rev}^{{commit}}"],
                capture_output=True, text=True, check=False,
            )
            return r.stdout.strip() if r.returncode == 0 else ""

        def report_commit_for(slug):
            if not slug:
                return ""
            for base_dir in (top, os.getcwd()):
                for rel in (
                    os.path.join("docs", "agents-v0", "build", slug, "build-report.md"),
                    os.path.join("docs", "agents-v0", "verify", slug, "test-report.md"),
                ):
                    p = os.path.join(base_dir, rel)
                    if os.path.isfile(p):
                        try:
                            m = re.search(r"^commit:\s*([0-9a-f]{7,40})\b", open(p, encoding="utf-8").read(), re.I | re.M)
                            if m:
                                sha = rev_commit(m.group(1))
                                if sha:
                                    return sha
                        except OSError:
                            pass
            return ""

        candidates = []
        for pattern in (
            os.path.join(top, "docs", "agents-v0", "requirements", "*.state.json"),
            os.path.join(top, "docs", "agents-v0", "maintain", "*", "state.json"),
            os.path.join(os.getcwd(), "docs", "agents-v0", "requirements", "*.state.json"),
            os.path.join(os.getcwd(), "docs", "agents-v0", "maintain", "*", "state.json"),
        ):
            for sf in glob.glob(pattern):
                if os.path.isfile(sf):
                    candidates.append(os.path.abspath(sf))
        seen_sf = set()
        ordered_sf = []
        for sf in sorted(candidates, key=lambda p: os.path.getmtime(p), reverse=True):
            if sf not in seen_sf:
                seen_sf.add(sf)
                ordered_sf.append(sf)
        active_first = []
        inactive = []
        for sf in ordered_sf:
            try:
                st = json.load(open(sf, encoding="utf-8"))
            except (OSError, ValueError):
                continue
            (active_first if (st.get("activePhase") or "") else inactive).append(st)
        for st in active_first + inactive:
            slug = (st.get("feature") or "").strip()
            rep_sha = report_commit_for(slug)
            bc = rev_commit((st.get("baseCommit") or "").strip())
            if bc and bc != head_sha:
                if rep_sha:
                    mb_rep = subprocess.run(
                        ["git", "-C", root, "merge-base", bc, rep_sha],
                        capture_output=True, text=True, check=False,
                    )
                    if mb_rep.returncode == 0 and mb_rep.stdout.strip() == bc and bc != rep_sha:
                        return bc
                else:
                    alt = subprocess.run(
                        ["git", "-C", root, "merge-base", bc, "HEAD"],
                        capture_output=True, text=True, check=False,
                    )
                    if alt.returncode == 0 and alt.stdout.strip() and alt.stdout.strip() != head_sha:
                        return alt.stdout.strip()
            if rep_sha:
                rep_parent = rev_commit(f"{rep_sha}^")
                if rep_parent:
                    return rep_parent
        for base_dir in (top, os.getcwd()):
            for pattern in (
                os.path.join(base_dir, "docs", "agents-v0", "build", "*", "build-report.md"),
                os.path.join(base_dir, "docs", "agents-v0", "verify", "*", "test-report.md"),
            ):
                for rp in sorted(glob.glob(pattern), key=lambda p: os.path.getmtime(p), reverse=True):
                    try:
                        m = re.search(r"^commit:\s*([0-9a-f]{7,40})\b", open(rp, encoding="utf-8").read(), re.I | re.M)
                        if m:
                            sha = rev_commit(m.group(1))
                            parent = rev_commit(f"{sha}^") if sha else ""
                            if parent:
                                return parent
                    except OSError:
                        pass
        if not re.fullmatch(r"[0-9a-f]{7,40}", base, re.I):
            revs = subprocess.run(
                ["git", "-C", root, "rev-list", "--max-count=10", "HEAD"],
                capture_output=True, text=True, check=False,
            )
            if revs.returncode == 0:
                doc_re = re.compile(r"^(docs/|.*\.(md|mdc|txt|adoc)$)")
                for c in revs.stdout.splitlines():
                    c = c.strip()
                    if not c:
                        continue
                    dt = subprocess.run(
                        ["git", "-C", root, "diff-tree", "--no-commit-id", "--name-only", "-r", c],
                        capture_output=True, text=True, check=False,
                    )
                    files = [f.strip() for f in dt.stdout.splitlines() if f.strip()]
                    if any(not doc_re.match(f) for f in files):
                        p = rev_commit(f"{c}^")
                        if p:
                            return p
                        break
            parent = rev_commit("HEAD~1")
            if parent:
                return parent
    return merge_base


def git_added(glob_pattern, base):
    """Lines added since DIFF_BASE for one pathspec. Empty dict when the diff cannot be read."""
    try:
        merge_base = resolve_merge_base(base)
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
    qg = quality_gates_thresholds()
    default_diff = qg.get("diff_line_pct", 80.0)
    minimum = number("MIN_DIFF_LINE_PCT", default_diff)
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


def node_lines(base=None):
    base = base or root
    lcov = os.path.join(base, "coverage", "lcov.info")
    if os.path.isfile(lcov):
        return lcov_lines(lcov)
    final = os.path.join(base, "coverage", "coverage-final.json")
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


def cve_names(data):
    """HIGH/CRITICAL names from OWASP, top-level vulnerabilities list/dict (npm audit), or .NET vulnerable package JSON."""
    found = []
    raw_vulns = data.get("vulnerabilities")
    if isinstance(raw_vulns, dict):
        entries = [v for v in raw_vulns.values() if isinstance(v, dict)]
    elif isinstance(raw_vulns, list):
        entries = list(raw_vulns)
    else:
        entries = []
    for dep in data.get("dependencies") or []:
        if isinstance(dep, dict):
            entries.extend(dep.get("vulnerabilities") or [])
            for v in dep.get("vulns") or []:
                if isinstance(v, dict):
                    entries.append({
                        "name": v.get("id") or v.get("name") or dep.get("name") or "?",
                        "severity": v.get("severity") or "HIGH",
                    })
    for proj in data.get("projects") or []:
        for fw in (proj.get("frameworks") if isinstance(proj, dict) else None) or []:
            if not isinstance(fw, dict):
                continue
            for key in ("topLevelPackages", "transitivePackages"):
                for pkg in fw.get(key) or []:
                    if not isinstance(pkg, dict):
                        continue
                    for v in pkg.get("vulnerabilities") or []:
                        if isinstance(v, dict):
                            entries.append({
                                "name": v.get("name") or v.get("id") or pkg.get("id") or v.get("advisoryUrl") or "?",
                                "severity": v.get("severity", ""),
                            })
    for vuln in entries:
        if isinstance(vuln, dict) and str(vuln.get("severity", "")).upper() in ("HIGH", "CRITICAL"):
            found.append(str(vuln.get("name") or vuln.get("id") or vuln.get("advisoryUrl") or "?"))
    return found


def record_cve(path):
    """HIGH/CRITICAL findings. See cve_names for the two accepted shapes."""
    if not os.path.isfile(path):
        if env("REQUIRE_CVE_REPORT") == "1":
            failures.append(f"missing {os.path.basename(path)} (REQUIRE_CVE_REPORT=1)")
        else:
            print(f"cve: SKIP (no {os.path.basename(path)})")
        return
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    found = cve_names(data)
    summary["highCriticalCves"] = sorted(set(found))
    print(f"cve: {len(set(found))} unsuppressed HIGH/CRITICAL")
    if found:
        failures.append("unsuppressed HIGH/CRITICAL CVEs: " + ", ".join(sorted(set(found))))


SCHEMA_PATH_RE = re.compile(
    r"(^|/)(db/migrations?|db/changelog|alembic/versions|migrations)/|schema\.prisma$|\.sql$",
    re.I,
)
TARGET_DB_TEST_RE = re.compile(
    r"(testcontainers|@Testcontainers|PostgreSQLContainer|SqlServerContainer|MySQLContainer|"
    r"MariaDBContainer|OracleContainer|JdbcDatabaseContainer|DockerComposeContainer|ComposeContainer|"
    r"@ServiceConnection|tc:postgresql|jdbc:postgresql:|jdbc:sqlserver:|UseNpgsql|NpgsqlConnection|"
    r"UseSqlServer|SqlConnection|psycopg|asyncpg|pgx|postgres://|postgresql://|sqlserver://)",
    re.I,
)
TEST_SOURCE_RE = re.compile(
    r"(Test|Tests|IT)\.java$|(Test|Tests)\.cs$|\.(test|spec)\.[A-Za-z]+$|_test\.[A-Za-z]+$|(^|/)test_[^/]+\.py$",
    re.I,
)


def check_schema_target_db():
    """If the diff touches a migration or SQL file, tests must run against the target DB (not H2/in-memory only)."""
    base = env("DIFF_BASE")
    if not base or env("ALLOW_INMEMORY_MIGRATION_TEST") == "1":
        return
    try:
        merge_base = resolve_merge_base(base)
        changed = subprocess.run(
            ["git", "-C", root, "diff", "--name-only", "--relative", merge_base, "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.splitlines()
    except (subprocess.CalledProcessError, OSError):
        return
    schema_files = [p.strip() for p in changed if p.strip() and SCHEMA_PATH_RE.search(p.replace("\\", "/"))]
    if not schema_files:
        return
    skip = {".git", "node_modules", "target", "dist", "build", "bin", "obj", ".venv", "venv", "__pycache__"}
    has_target_db = False
    for dirpath, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip]
        for name in names:
            full = os.path.join(dirpath, name)
            norm = full.replace(os.sep, "/")
            if (
                TEST_SOURCE_RE.search(norm)
                or "/src/test/" in norm
                or "/tests/" in norm
                or "/__tests__/" in norm
                or re.search(r"(^|/)(docker-)?compose[^/]*\.ya?ml$", norm, re.I)
            ):
                try:
                    with open(full, encoding="utf-8", errors="replace") as handle:
                        text = handle.read()
                except OSError:
                    continue
                if TARGET_DB_TEST_RE.search(text):
                    has_target_db = True
                    break
        if has_target_db:
            break
    summary["schemaChangedFiles"] = schema_files
    summary["schemaTargetDbVerified"] = has_target_db
    if not has_target_db:
        failures.append(
            f"schema/migration files changed ({', '.join(schema_files[:3])}) "
            "but no target-database test (Testcontainers or Compose) was found; "
            "H2 or in-memory substitutes do not satisfy schema verification"
        )
    else:
        print(f"schema: target database test verified for {len(schema_files)} migration/SQL file(s)")


def mutation_ratchet_minimum():
    """Optional mutation minimum from MIN_MUTATION_PCT or the mutation_ratchet table in project-profile.md."""
    explicit = number("MIN_MUTATION_PCT")
    if explicit is not None:
        return explicit
    path = env("KNOWN_FAILURES_PROFILE") or os.path.join("docs", "agents-v0", "project-profile.md")
    if not os.path.isfile(path):
        return None
    in_section = False
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("#"):
                in_section = "mutation_ratchet" in stripped
                continue
            if in_section and stripped.startswith("|"):
                cells = [cell.strip().rstrip("%") for cell in stripped.strip("|").split("|")]
                if len(cells) >= 2 and re.fullmatch(r"\d+(?:\.\d+)?", cells[1]):
                    return float(cells[1])
    return None


def parse_mutation_pct(path):
    if not path or not os.path.isfile(path):
        return None
    low = path.lower()
    if low.endswith(".xml"):
        try:
            top = ET.parse(path).getroot()
        except ET.ParseError:
            return None
        killed = total = 0
        for mut in top.iter():
            if mut.tag == "mutation" or mut.tag.endswith("}mutation"):
                status = (mut.get("status") or "").upper()
                if status in ("MEMORY_ERROR", "RUN_ERROR", "NON_VIABLE"):
                    continue
                total += 1
                if (mut.get("detected") or "").lower() == "true" or status in ("KILLED", "TIMED_OUT"):
                    killed += 1
        return None if total == 0 else 100.0 * killed / total
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    if isinstance(data.get("mutationScore"), (int, float)):
        return float(data["mutationScore"])
    if isinstance(data.get("killed"), (int, float)) and isinstance(data.get("total"), (int, float)) and data["total"] > 0:
        return 100.0 * float(data["killed"]) / float(data["total"])
    files = data.get("files")
    if isinstance(files, dict):
        killed = total = 0
        for fobj in files.values():
            if not isinstance(fobj, dict):
                continue
            for mut in fobj.get("mutants") or []:
                if not isinstance(mut, dict):
                    continue
                st = (mut.get("status") or "").lower()
                if st in ("ignored", "compileerror", "runtimeerror"):
                    continue
                total += 1
                if st in ("killed", "timeout"):
                    killed += 1
        return None if total == 0 else 100.0 * killed / total
    return None


def check_mutation():
    """Optional mutation score check when MUTATION_REPORT, pack mutation.path, or mutation_ratchet is configured."""
    mut_spec = (bound_pack or {}).get("mutation") if isinstance((bound_pack or {}).get("mutation"), dict) else {}
    rel = env("MUTATION_REPORT") or mut_spec.get("path") or ""
    candidates = files_for(rel) if rel else []
    report_file = candidates[0] if candidates else (rel if rel and os.path.isfile(rel) else "")
    if not report_file:
        for default_rel in (
            os.path.join("target", "pit-reports", "mutations.xml"),
            os.path.join("reports", "mutation", "mutation.json"),
            "mutation.json",
        ):
            found = files_for(default_rel)
            if found:
                report_file = found[0]
                break
    minimum = mutation_ratchet_minimum()
    pct = parse_mutation_pct(report_file) if report_file else None
    if pct is not None:
        summary["mutationPct"] = round(pct, 2)
        print(f"mutation: score {pct:.2f}%")
        if minimum is not None and pct < minimum:
            failures.append(f"mutation score {pct:.2f}% < {minimum:g}%")
    elif minimum is not None:
        failures.append(f"mutation minimum {minimum:g}% is set but no mutation report was found")


def finish():
    if summary.get("kind") not in (None, "", "missing"):
        check_schema_target_db()
        check_mutation()
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

def files_for(relpath):
    """Pack paths are relative to the module. CI may have copied them under ci-artifacts/gate/."""
    if not relpath:
        return []
    bases = [root]
    rel_root = os.path.relpath(os.path.abspath(root), os.getcwd())
    if not rel_root.startswith(".."):
        bases.append(os.path.join(os.getcwd(), "ci-artifacts", "gate", rel_root))
    ci_gate_abs = os.path.abspath(os.path.join(os.getcwd(), "ci-artifacts", "gate"))
    found = []
    seen_rel = set()
    for idx, base in enumerate(bases):
        base_abs = os.path.abspath(base)
        pattern = os.path.join(base, relpath)
        for match in glob.glob(pattern, recursive=True):
            if os.path.isfile(match):
                match_abs = os.path.abspath(match)
                if idx == 0 and (match_abs == ci_gate_abs or match_abs.startswith(ci_gate_abs + os.sep)):
                    continue
                rel = os.path.relpath(match_abs, base_abs)
                if rel not in seen_rel:
                    seen_rel.add(rel)
                    found.append(match)
        if idx == 0 and found:
            break
    return found


def jacoco_report(path):
    if not os.path.isfile(path):
        return None, None
    report = ET.parse(path).getroot()
    line_pct = None
    for counter in report.findall("counter"):
        if counter.get("type") == "LINE":
            missed, covered = int(counter.get("missed") or 0), int(counter.get("covered") or 0)
            line_pct = 100.0 * covered / (missed + covered) if missed + covered else 100.0
    tracked = {}
    for package in report.iter("package"):
        for source in package.findall("sourcefile"):
            key = (package.get("name") or "") + "/" + (source.get("name") or "")
            tracked[key] = {int(ln.get("nr")): int(ln.get("ci", 0)) > 0 for ln in source.findall("line")}
    return line_pct, tracked


def measure_manifest(data):
    """Read the files and formats named on the bound pack. Do not remap them to another language."""
    sys.path.insert(0, os.environ.get("PACKLIB_DIR") or "")
    import packlib
    coverage = data.get("coverage") or {}
    report = data.get("testsReport") or {}
    cov_fmt = coverage.get("format") or ""
    rep_fmt = report.get("format") or ""
    pack_id = data.get("id") or "?"
    if cov_fmt not in packlib.COVERAGE_FORMATS:
        failures.append(f"Pack {pack_id} coverage format {cov_fmt or '(empty)'} is not measured")
    if rep_fmt not in packlib.TEST_FORMATS:
        failures.append(f"Pack {pack_id} test report format {rep_fmt or '(empty)'} is not measured")
    if failures:
        return
    test_files = files_for(report.get("path") or "")
    if rep_fmt in ("junit", "pytest"):
        record_tests(*junit_totals(test_files))
    elif rep_fmt == "trx":
        record_tests(*trx_totals(test_files))
    else:
        record_tests(*go_json_totals(test_files[0] if test_files else os.path.join(root, report.get("path") or "")))
    cov_files = files_for(coverage.get("path") or "")
    cov_file = cov_files[0] if cov_files else os.path.join(root, coverage.get("path") or "")
    tracked = None
    if cov_fmt == "jacoco":
        pct, tracked = jacoco_report(cov_file)
    elif cov_fmt == "cobertura":
        pct = cobertura_pct(cov_file)
        tracked = cobertura_lines(cov_file)
    elif cov_fmt == "go-cover":
        pct = gocover_pct(cov_file)
        tracked = go_lines(cov_file)
    else:
        pct = jest_pct(cov_file)
        tracked = node_lines(os.path.dirname(os.path.dirname(cov_file)) if cov_files else root)
    record_coverage(pct, coverage.get("path") or cov_fmt)
    spec = data.get("diffCoverage") or {}
    score_diff(tracked, spec.get("glob") or "*", spec.get("sourceRoot") or "")
    cve_rel = (data.get("cve") or {}).get("path") or ""
    if cve_rel:
        cve_files = files_for(cve_rel)
        cve_candidate = cve_files[0] if cve_files else os.path.join(root, cve_rel)
        root_abs = os.path.abspath(root)
        ci_gate_abs = os.path.abspath(os.path.join(os.getcwd(), "ci-artifacts", "gate"))
        live_build_files = [
            f for f in (test_files + cov_files)
            if os.path.isfile(f)
            and os.path.abspath(f).startswith(root_abs + os.sep)
            and not os.path.abspath(f).startswith(ci_gate_abs + os.sep)
        ]
        root_cve_files = [
            f for f in glob.glob(os.path.join(root, cve_rel), recursive=True)
            if os.path.isfile(f) and not os.path.abspath(f).startswith(ci_gate_abs + os.sep)
        ]
        if (
            live_build_files
            and os.path.isfile(cve_candidate)
            and os.path.abspath(cve_candidate).startswith(ci_gate_abs + os.sep)
            and not root_cve_files
        ):
            newest_live = max(os.path.getmtime(f) for f in live_build_files)
            if pack_id == "java" or os.path.getmtime(cve_candidate) + 1.0 < newest_live:
                cve_candidate = os.path.join(root, cve_rel)
        record_cve(cve_candidate)
    else:
        print("cve: SKIP (pack has no cve.path)")


def kind_from_pack():
    """A bound Pack selects its own report paths. An empty Pack leaves marker detection alone."""
    for candidate in (
        os.environ.get("PACKLIB_DIR") or "",
        os.path.join(os.getcwd(), ".agents-v0", "ci"),
    ):
        if candidate and os.path.isfile(os.path.join(candidate, "packlib.py")):
            sys.path.insert(0, candidate)
            break
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
    summary["pack"] = pack_id
    return "manifest"


kind = kind_from_pack()
if not kind:
    kind = module_kind(root)
summary["kind"] = kind
if kind == "missing":
    finish()
if kind == "manifest":
    measure_manifest(bound_pack)
    finish()
if not kind:
    failures.append("no Pack and no module marker; gate metrics does not assume a language")
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
        qg = quality_gates_thresholds()
        minimum = number("MIN_LINE_PCT", qg.get("min_line_pct"))
        if minimum is not None and line_pct < minimum:
            failures.append(f"bundle line coverage {line_pct:.2f}% < {minimum:g}%")
else:
    print("coverage: SKIP (no target/site/jacoco/jacoco.xml)")
    if env("DIFF_BASE"):
        failures.append("DIFF_BASE is set but target/site/jacoco/jacoco.xml is missing")

# Diff coverage: Java lines added since the merge base, the "changed code" minimum.
base = env("DIFF_BASE")
if base and os.path.isfile(jacoco):
    qg = quality_gates_thresholds()
    default_diff = qg.get("diff_line_pct", 80.0)
    minimum = number("MIN_DIFF_LINE_PCT", default_diff)
    try:
        merge_base = resolve_merge_base(base)
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
    found = cve_names(data)
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
