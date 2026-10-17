#!/bin/sh
# check-build-plan.sh — the Build plan is real: every AC has a row, every done row names a test that
# exists, and that test was red before it was green (workflow-orchestration.mdc Build gate).
#
# Usage:
#   sh .agents-v0/ci/check-build-plan.sh <feature> [--complete]
#   sh .agents-v0/ci/check-build-plan.sh <feature> --record-red [<report-or-root>...]
# Reads docs/agents-v0/build/<feature>/plan.md, docs/agents-v0/build/<feature>/build-report.md (the command-result
# cards), optional docs/agents-v0/build/<feature>/red-tests.json (captured by --record-red),
# docs/agents-v0/requirements/<feature>.md, and the test sources of the repository.
#   - the plan has exactly the AC-n rows of the requirements artifact (none added, none dropped);
#   - Status is pending, done, or blocked;
#   - a done row names a test, and that name occurs in a test file (src/test, tests, __tests__,
#     *Test.java, *Tests.java, *IT.java, *.test.*, *.spec.*, *_test.*, test_*.py);
#   - a done row has a red card: a command-result card with a non-zero Exit whose Failing test
#     cell contains that test name. When red-tests.json exists, a card Location names a test report
#     (.xml, .trx, .json), or REQUIRE_RED_REPORT=1 is set, the test must also appear as a failed
#     case in the machine test report. "(no-red: <reason>)" in the Test cell waives it for one row
#     (for example a configuration-only unit). REQUIRE_RED=0 turns the check off;
#   - --record-red snapshots failing test identifiers from JUnit/pytest XML, .trx, or go-test.json
#     into docs/agents-v0/build/<feature>/red-tests.json before the green run overwrites them;
#   - --complete (the Build gate): no row is pending, and a blocked row says why in its Test cell.

set -eu

feature="${1:-}"
mode="${2:-}"
[ -n "$feature" ] || { printf 'usage: %s <feature> [--complete | --record-red [<report-or-root>...]]\n' "$0" >&2; exit 1; }
case "$mode" in
  '' | --complete)
    [ $# -le 2 ] || { printf 'FAIL: unknown option %s\n' "$3" >&2; exit 1; }
    ;;
  --record-red)
    shift 2
    ;;
  *)
    printf 'FAIL: unknown option %s\n' "$mode" >&2
    exit 1
    ;;
esac
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
FEATURE="$feature" MODE="$mode" PACKLIB_DIR="$DIR" python3 - "$@" <<'PY'
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib

feature, mode = os.environ["FEATURE"], os.environ["MODE"]
complete = mode == "--complete"
record_red = mode == "--record-red"
require_red = os.environ.get("REQUIRE_RED", "1") != "0"
require_red_report = os.environ.get("REQUIRE_RED_REPORT", "0") == "1"
build_dir = os.path.join("docs", "agents-v0", "build", feature)
plan_path = os.path.join(build_dir, "plan.md")
report_path = os.path.join(build_dir, "build-report.md")
red_json_path = os.path.join(build_dir, "red-tests.json")
req_path = os.path.join("docs", "agents-v0", "requirements", f"{feature}.md")
failures = []


def fail(msg):
    failures.append(msg)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


REPORT_FILE_RE = re.compile(
    r"(^|/)TEST-[^/]+\.xml$|(pytest-report|test-results|junit)\.xml$|\.trx$|(^|/)go-test\.json$",
    re.I,
)


def parse_failed_tests_from_file(path):
    """Return a set of failing test tokens from one JUnit/pytest XML, .trx, or go-test.json file."""
    found = set()
    if not os.path.isfile(path):
        return found
    low = path.lower()
    if low.endswith(".json"):
        text = read(path) or ""
        try:
            doc = json.loads(text)
            if isinstance(doc, dict) and isinstance(doc.get("failed"), list):
                for item in doc["failed"]:
                    if isinstance(item, str) and item.strip():
                        found.add(item.strip())
                return found
        except json.JSONDecodeError:
            pass
        for line in text.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if obj.get("Action") == "fail" and obj.get("Test"):
                tname = str(obj["Test"]).strip()
                found.add(tname)
                if "/" in tname:
                    found.add(tname.split("/", 1)[0])
                pkg = str(obj.get("Package") or "").strip()
                if pkg:
                    found.add(f"{pkg}#{tname}")
        return found
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return found
    if low.endswith(".trx"):
        for el in root.iter():
            if el.tag.endswith("UnitTestResult"):
                outcome = (el.get("outcome") or "").lower()
                tname = (el.get("testName") or "").strip()
                if outcome in ("failed", "error") and tname:
                    found.add(tname)
                    short = tname.split("(", 1)[0].strip()
                    found.add(short)
                    if "." in short:
                        cls, meth = short.rsplit(".", 1)
                        found.add(meth)
                        found.add(f"{cls}#{meth}")
                        found.add(f"{cls.rsplit('.', 1)[-1]}#{meth}")
        return found
    for tc in root.iter():
        if tc.tag != "testcase" and not tc.tag.endswith("}testcase"):
            continue
        has_fail = any(
            ch.tag in ("failure", "error") or ch.tag.endswith("}failure") or ch.tag.endswith("}error")
            for ch in list(tc)
        )
        if not has_fail:
            continue
        name = re.sub(r"\(.*\)$", "", (tc.get("name") or "").strip())
        cls = (tc.get("classname") or "").strip()
        if name:
            found.add(name)
        if cls and name:
            found.add(f"{cls}#{name}")
            found.add(f"{cls}::{name}")
            short_cls = cls.rsplit(".", 1)[-1].rsplit("/", 1)[-1]
            found.add(f"{short_cls}#{name}")
            found.add(f"{short_cls}::{name}")
    return found


def discover_report_files(targets):
    skip = {".git", "node_modules", "docs", ".cursor", ".venv", "venv", "__pycache__"}
    files = []
    for target in (targets or ["."]):
        if os.path.isfile(target):
            files.append(target)
            continue
        if not os.path.isdir(target):
            continue
        for dirpath, dirs, names in os.walk(target):
            dirs[:] = [d for d in dirs if d not in skip]
            for name in names:
                full = os.path.join(dirpath, name)
                norm = full.replace(os.sep, "/")
                if REPORT_FILE_RE.search(norm):
                    files.append(full)
    return sorted(set(files))


if record_red:
    targets = sys.argv[1:]
    report_files = discover_report_files(targets)
    failed_tokens = set()
    used_sources = []
    for rfile in report_files:
        tokens = parse_failed_tests_from_file(rfile)
        if tokens:
            failed_tokens.update(tokens)
            used_sources.append(rfile.replace(os.sep, "/"))
    if not failed_tokens:
        print("FAIL: --record-red found no failing tests in any machine test report (.xml, .trx, go-test.json)", file=sys.stderr)
        raise SystemExit(1)
    os.makedirs(build_dir, exist_ok=True)
    existing = {"failed": [], "sources": []}
    if os.path.isfile(red_json_path):
        try:
            existing = json.loads(read(red_json_path) or "{}")
        except json.JSONDecodeError:
            existing = {"failed": [], "sources": []}
    merged_failed = sorted(set(existing.get("failed") or []) | failed_tokens)
    merged_sources = sorted(set(existing.get("sources") or []) | set(used_sources))
    with open(red_json_path, "w", encoding="utf-8") as handle:
        json.dump({"failed": merged_failed, "sources": merged_sources}, handle, indent=2)
        handle.write("\n")
    print(f"OK: recorded {len(failed_tokens)} failing test token(s) for {feature} in {red_json_path}")
    raise SystemExit(0)


def table(text, need):
    """Rows (dicts keyed by lower-cased header) of the first table whose header has every name in need."""
    header, out = None, []
    for line in (text or "").splitlines():
        if not line.strip().startswith("|"):
            if header is not None and out:
                break
            header = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        low = [c.lower() for c in cells]
        if header is None and all(n in low for n in need):
            header = low
            continue
        if header is None or all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
            continue
        out.append(dict(zip(header, cells)))
    return out


plan_text = read(plan_path)
if plan_text is None:
    print(f"FAIL: {plan_path} is missing (write the plan before the first implementation edit)", file=sys.stderr)
    raise SystemExit(1)
rows = table(plan_text, ["ac", "status", "test"])
if not rows:
    fail(f"{plan_path}: no table with the columns AC, Status, Test")

req_text = read(req_path)
if req_text is not None:
    want = set(re.findall(r"\bAC-\d+\b", req_text))
    have = {r["ac"] for r in rows if re.fullmatch(r"AC-\d+", r.get("ac", ""))}
    for ac in sorted(want - have, key=lambda s: int(s[3:])):
        fail(f"{plan_path}: no row for {ac}")
    for ac in sorted(have - want, key=lambda s: int(s[3:])):
        fail(f"{plan_path}: {ac} is not an acceptance criterion of {req_path}")
seen = set()
for r in rows:
    if r.get("ac") in seen:
        fail(f"{plan_path}: {r['ac']} appears twice")
    seen.add(r.get("ac"))

# Test sources, read once.
SKIP = {"node_modules", "target", ".git", "dist", "build", ".svelte-kit", ".next", "docs", ".cursor", ".claude", ".kilo", ".venv", "venv", "__pycache__", "bin", "obj"}
TEST_FILE = re.compile(r"(Test|Tests|IT)\.java$|(Test|Tests)\.cs$|\.(test|spec)\.[A-Za-z]+$|_test\.[A-Za-z]+$|(^|/)test_[^/]+\.py$")
_pack = packlib.load(packlib.profile_pack())
_test_file = (_pack or {}).get("testFile")
if _test_file:
    TEST_FILE = re.compile(TEST_FILE.pattern + "|" + _test_file)
blob = ""
for dirpath, dirs, names in os.walk("."):
    dirs[:] = [d for d in dirs if d not in SKIP]
    for name in names:
        full = os.path.join(dirpath, name)
        norm = full.replace(os.sep, "/")
        if TEST_FILE.search(norm) or "/src/test/" in norm or "/__tests__/" in norm or "/tests/" in norm:
            text = read(full)
            if text:
                blob += "\n" + text

cards = table(read(report_path), ["command", "exit", "failing test"])
red_cards = [c for c in cards if c.get("exit", "").isdigit() and c.get("exit") != "0"]
red_text = "\n".join(c.get("failing test", "") for c in red_cards)

# Machine-captured red evidence: red-tests.json (from --record-red) or report files cited in red cards.
machine_red_tokens = set()
has_machine_red_source = False
if os.path.isfile(red_json_path):
    has_machine_red_source = True
    machine_red_tokens.update(parse_failed_tests_from_file(red_json_path))
for c in red_cards:
    loc_text = " ".join([c.get("location", ""), c.get("report", "")])
    for candidate in re.findall(r"[\w./\\-]+\.(?:xml|trx|json)\b", loc_text, re.I):
        has_machine_red_source = True
        if not os.path.isfile(candidate):
            fail(f"{report_path}: red card references missing test report {candidate}")
        else:
            tokens = parse_failed_tests_from_file(candidate)
            if not tokens:
                fail(f"{report_path}: red card references {candidate}, which contains no failing test case")
            machine_red_tokens.update(tokens)


def names_in(cell):
    """Candidate test identifiers in a Test cell: the method part after #, and the whole token."""
    cell = re.sub(r"\(no-red:[^)]*\)", "", cell)
    out = []
    for tok in re.findall(r"[A-Za-z_][\w.#:\-/]{3,}", cell):
        out.append(tok)
        for sep in ("#", "::"):
            if sep in tok:
                out.append(tok.rsplit(sep, 1)[1])
    return [t for t in out if len(t) >= 4]


for r in rows:
    ac, status, test = r.get("ac", "?"), r.get("status", "").lower(), r.get("test", "")
    if status not in ("pending", "done", "blocked"):
        fail(f"{plan_path}: {ac} Status must be pending, done, or blocked (got '{r.get('status')}')")
    if complete and status == "pending":
        fail(f"{plan_path}: {ac} is still pending")
    if status == "blocked" and complete and len(re.sub(r"[`\s]", "", test)) < 8:
        fail(f"{plan_path}: {ac} is blocked: say why in the Test cell")
    if status != "done":
        continue
    names = names_in(test)
    if not names:
        fail(f"{plan_path}: {ac} is done but names no test")
        continue
    if not any(n in blob for n in names):
        fail(f"{plan_path}: {ac} names a test that no test file contains: {test}")
    waived = re.search(r"\(no-red:\s*\S{4,}", test)
    if require_red and not waived:
        if not cards:
            fail(f"{plan_path}: {ac} is done but {report_path} has no command-result cards")
        elif not any(n in red_text for n in names):
            fail(f"{plan_path}: {ac} has no red card: no failed attempt names {test} (or write (no-red: <reason>))")
        if has_machine_red_source or require_red_report:
            if not any(n in machine_red_tokens for n in names):
                fail(
                    f"{plan_path}: {ac} has no machine-verified red test report for {test} "
                    f"(run sh .agents-v0/ci/check-build-plan.sh {feature} --record-red after the red run, "
                    "or cite the failing JUnit/TRX/JSON report in the card Location)"
                )

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
done = sum(1 for r in rows if r.get("status", "").lower() == "done")
print(f"OK: build plan for {feature}: {len(rows)} rows, {done} done")
PY
