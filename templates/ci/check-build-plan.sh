#!/bin/sh
# check-build-plan.sh — the Build plan is real: every AC has a row, every done row names a test that
# exists, and that test was red before it was green (workflow-orchestration.mdc Build gate).
#
# Usage: sh ci/check-build-plan.sh <feature> [--complete]
# Reads docs/build/<feature>/plan.md, docs/build/<feature>/build-report.md (the command-result
# cards), docs/requirements/<feature>.md, and the test sources of the repository.
#   - the plan has exactly the AC-n rows of the requirements artifact (none added, none dropped);
#   - Status is pending, done, or blocked;
#   - a done row names a test, and that name occurs in a test file (src/test, tests, __tests__,
#     *Test.java, *Tests.java, *IT.java, *.test.*, *.spec.*, *_test.*, test_*.py);
#   - a done row has a red card: a command-result card with a non-zero Exit whose Failing test
#     cell contains that test name. "(no-red: <reason>)" in the Test cell waives it for one row
#     (for example a configuration-only unit). REQUIRE_RED=0 turns the check off;
#   - --complete (the Build gate): no row is pending, and a blocked row says why in its Test cell.

set -eu

feature="${1:-}"
mode="${2:-}"
[ -n "$feature" ] || { printf 'usage: %s <feature> [--complete]\n' "$0" >&2; exit 1; }
case "$mode" in '' | --complete) ;; *) printf 'FAIL: unknown option %s\n' "$mode" >&2; exit 1 ;; esac
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

FEATURE="$feature" MODE="$mode" python3 - <<'PY'
import os
import re
import sys

feature, complete = os.environ["FEATURE"], os.environ["MODE"] == "--complete"
require_red = os.environ.get("REQUIRE_RED", "1") != "0"
plan_path = os.path.join("docs", "build", feature, "plan.md")
report_path = os.path.join("docs", "build", feature, "build-report.md")
req_path = os.path.join("docs", "requirements", f"{feature}.md")
failures = []


def fail(msg):
    failures.append(msg)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


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
SKIP = {"node_modules", "target", ".git", "dist", "build", ".svelte-kit", ".next", "docs", ".cursor", ".claude", ".kilo"}
TEST_FILE = re.compile(r"(Test|Tests|IT)\.java$|\.(test|spec)\.[A-Za-z]+$|_test\.[A-Za-z]+$|(^|/)test_[^/]+\.py$")
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
red_text = "\n".join(c.get("failing test", "") for c in cards if c.get("exit", "").isdigit() and c.get("exit") != "0")


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

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
done = sum(1 for r in rows if r.get("status", "").lower() == "done")
print(f"OK: build plan for {feature}: {len(rows)} rows, {done} done")
PY
