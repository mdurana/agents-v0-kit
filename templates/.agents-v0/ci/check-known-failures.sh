#!/bin/sh
# check-known-failures.sh — fail if verify log shows failures beyond documented known_failures.
#
# Usage: sh .agents-v0/ci/check-known-failures.sh [--require-failures] <verify-log-file>
# Parses test runner failure counts (Maven Surefire/JUnit, dotnet test, pytest, Jest/Vitest,
# Go test); compares to docs/agents-v0/project-profile.md known_failures table when present.
# Run it from the repository root (the profile path is relative).
#
# --require-failures  use after a verify command that exited non-zero: a log with no test failure
#                     is a compile or plugin error, not a known failure, so it fails here.
#
# Exit 0 when no failures or documented allow-list matches; 1 otherwise.

set -eu
require=0
if [ "${1:-}" = "--require-failures" ]; then
  require=1
  shift
fi
log="${1:-}"
profile="docs/agents-v0/project-profile.md"
[ -f "$log" ] || { printf 'FAIL: verify log not found: %s\n' "$log" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

REQUIRE="$require" LOG_FILE="$log" PROFILE_FILE="$profile" python3 - <<'PY'
import os
import re
import sys

require = os.environ["REQUIRE"] == "1"
log_path = os.environ["LOG_FILE"]
profile = os.environ["PROFILE_FILE"]

with open(log_path, encoding="utf-8", errors="replace") as handle:
    lines = handle.read().splitlines()

fail_count = 0
error_count = 0
matched_line = ""

# 1. Maven Surefire / JUnit summary: "Tests run: X, Failures: Y, Errors: Z"
for ln in lines:
    m = re.search(r"Tests run:\s*\d+,\s*Failures:\s*(\d+),\s*Errors:\s*(\d+)", ln)
    if m and (int(m.group(1)) > 0 or int(m.group(2)) > 0):
        fail_count = int(m.group(1))
        error_count = int(m.group(2))
        matched_line = ln

# 2. dotnet test summary: "Failed! - Failed: X, Passed: Y" or "Failed: X"
if fail_count + error_count == 0:
    for ln in lines:
        m = re.search(r"(?:Failed!\s*-\s*)?\bFailed:\s*([1-9]\d*)\b", ln)
        if m:
            fail_count = int(m.group(1))
            matched_line = ln

# 3. pytest summary: "=== 2 failed, 5 passed in 0.12s ===" or "1 failed, 2 errors"
if fail_count + error_count == 0:
    for ln in lines:
        if "===" in ln or "passed" in ln or "failed" in ln or "error" in ln:
            f_m = re.search(r"\b([1-9]\d*)\s+failed\b", ln)
            e_m = re.search(r"\b([1-9]\d*)\s+errors?\b", ln)
            if f_m or e_m:
                fail_count = int(f_m.group(1)) if f_m else 0
                error_count = int(e_m.group(1)) if e_m else 0
                matched_line = ln

# 4. Jest / Vitest summary: "Tests: 2 failed, 3 passed"
if fail_count + error_count == 0:
    for ln in lines:
        m = re.search(r"Tests:\s*([1-9]\d*)\s+failed\b", ln)
        if m:
            fail_count = int(m.group(1))
            matched_line = ln

# 5. Go test output: "--- FAIL: TestName" or `"Action":"fail","Package":...,"Test":"..."`
if fail_count + error_count == 0:
    go_fails = [
        ln for ln in lines
        if re.match(r"^\s*--- FAIL:\s+\S+", ln)
        or ('"Action":"fail"' in ln and '"Test":' in ln)
    ]
    if go_fails:
        fail_count = len(go_fails)
        matched_line = go_fails[-1]

total = fail_count + error_count
if total == 0:
    if require:
        print(
            "FAIL: verify exited non-zero and the log shows no test failure (build or plugin error, not a known failure)",
            file=sys.stderr,
        )
        raise SystemExit(1)
    print("OK: no test failures detected in log")
    raise SystemExit(0)

allowed = 0
if os.path.isfile(profile):
    in_section = False
    with open(profile, encoding="utf-8", errors="replace") as handle:
        for ln in handle:
            s = ln.strip()
            if s.startswith("#"):
                in_section = "known_failures" in s
                continue
            if in_section and s.startswith("|"):
                cells = [c.strip() for c in s.strip("|").split("|")]
                if cells and cells[0].isdigit() and int(cells[0]) > 0:
                    allowed = int(cells[0])
                    break

if allowed > 0:
    if total <= allowed:
        print(f"OK: failures ({total}) within documented known_failures budget ({allowed})")
        raise SystemExit(0)
    print(f"WARN: failures ({total}) exceed known_failures budget ({allowed}) — review required", file=sys.stderr)
    raise SystemExit(1)

print(
    f"FAIL: test failures in log (failures={fail_count} errors={error_count}) and no known_failures table in {profile}",
    file=sys.stderr,
)
if matched_line:
    print(matched_line, file=sys.stderr)
raise SystemExit(1)
PY
