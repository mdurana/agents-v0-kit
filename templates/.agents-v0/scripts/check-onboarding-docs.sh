#!/bin/sh
# check-onboarding-docs.sh — the onboarding documents cite real code (onboard-discovery).
#
# Usage: sh .agents-v0/scripts/check-onboarding-docs.sh [<path>...]
# With no argument it checks docs/agents-v0/onboarding/ (the report must exist), docs/agents-v0/architecture.md,
# docs/agents-v0/network.md, docs/agents-v0/design/system/context-map.md, docs/agents-v0/diagrams/, and
# docs/agents-v0/adr/0000-inherited-decisions.md, whichever exist.
#
# A citation is a backticked `path/to/File.ext:LINE` or `path/to/File.ext:START-END`.
# Fails when:
#   - a cited file does not exist, or a cited line is past the end of the file;
#   - a TEMPLATE: marker is still in a document (a sample row was never replaced);
#   - a document under docs/agents-v0/onboarding/ (not _*.template.md) has no `commit: <sha>` line;
#   - docs/agents-v0/onboarding/report.md is missing in the default run;
#   - UNVERIFIED markers exceed MAX_UNVERIFIED (unset: counted and reported only).
# An UNVERIFIED marker is an honest unknown; it should also appear in the report's open questions.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

if [ "$#" -eq 0 ]; then
  [ -f docs/agents-v0/onboarding/report.md ] || { printf 'FAIL: docs/agents-v0/onboarding/report.md is missing (copy docs/agents-v0/onboarding/_report.template.md)\n' >&2; exit 1; }
  set -- docs/agents-v0/onboarding docs/agents-v0/architecture.md docs/agents-v0/network.md docs/agents-v0/design/system/context-map.md docs/agents-v0/diagrams docs/agents-v0/adr/0000-inherited-decisions.md
  present=""
  for path in "$@"; do
    if [ -e "$path" ]; then
      present="$present $path"
    fi
  done
  # shellcheck disable=SC2086
  set -- $present
else
  for path in "$@"; do
    if [ ! -e "$path" ]; then
      printf 'FAIL: %s is missing\n' "$path" >&2
      exit 1
    fi
  done
fi

CHECK_PATHS="$(printf '%s\n' "$@")" python3 - <<'PY'
import os
import re
import sys

EXT = ("java|kt|cs|rs|rb|php|swift|scala|c|cpp|h|hpp|ts|tsx|js|jsx|svelte|vue|py|go|xml|csproj|sln|yml|yaml|json|properties|sql|gradle|kts|md|sh|html|css|toml|tf|conf")
CITE = re.compile(r"`([A-Za-z0-9_./@+\-]+\.(?:%s)):(\d+)(?:-(\d+))?`" % EXT)
failures, unverified, checked, cites = [], 0, 0, 0
line_counts = {}


def line_count(path):
    if path not in line_counts:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                line_counts[path] = sum(1 for _ in handle)
        except OSError:
            line_counts[path] = None
    return line_counts[path]


docs = []
for raw in os.environ["CHECK_PATHS"].splitlines():
    if not raw:
        continue
    if os.path.isdir(raw):
        for dirpath, _dirs, names in os.walk(raw):
            for name in sorted(names):
                if name.endswith(".md") and not (name.startswith("_") and name.endswith(".template.md")):
                    docs.append(os.path.join(dirpath, name))
    elif os.path.isfile(raw):
        docs.append(raw)

def count_unverified_statements(body):
    count = 0
    in_comment = False
    for line in body.splitlines():
        s = line.strip()
        if "<!--" in s:
            if "-->" not in s:
                in_comment = True
            continue
        if in_comment:
            if "-->" in s:
                in_comment = False
            continue
        if not s or s.startswith(("#", ">")):
            continue
        if re.match(r"^Owner:\s*UNVERIFIED\b", s, re.I):
            continue
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            # Module table in report.md: | Module | Document | Owner | Confidence |
            if len(cells) == 4 and cells[1].startswith("docs/") and cells[2].upper() == "UNVERIFIED":
                continue
            # Open questions table in report.md: | # | Question or unknown | Where it matters | Owner |
            if len(cells) == 4 and cells[0].isdigit() and cells[3].upper() == "UNVERIFIED":
                cells = cells[:3]
                s = "| " + " | ".join(cells) + " |"
        count += len(re.findall(r"\bUNVERIFIED\b", s))
    return count


def report_open_question_rows(body):
    in_oq = False
    rows = 0
    for line in body.splitlines():
        s = line.strip()
        if re.match(r"^#+\s*(open questions|unverified)", s, re.I):
            in_oq = True
            continue
        if in_oq and re.match(r"^#+\s", s):
            break
        if not in_oq or not s or "<!--" in s:
            continue
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if not cells or cells[0].lower() in ("#", "") or set(cells[0]) <= set("-: "):
                continue
            if any(c for c in cells[1:]):
                rows += 1
        elif s.startswith(("- ", "* ")) and len(s) > 3:
            rows += 1
    return rows


report_body = None
non_report_unverified = 0
for doc in sorted(set(docs)):
    checked += 1
    norm_doc = doc.replace(os.sep, "/")
    with open(doc, encoding="utf-8", errors="replace") as handle:
        body = handle.read()
    if norm_doc == "docs/agents-v0/onboarding/report.md" or norm_doc.endswith("/docs/agents-v0/onboarding/report.md"):
        report_body = body
    content_lines = [ln for ln in body.splitlines() if not ln.lstrip().startswith(">")]
    if any("TEMPLATE:" in ln for ln in content_lines):
        failures.append(f"{doc}: a TEMPLATE: marker is still present (replace or delete the sample row)")
    doc_unv = count_unverified_statements(body)
    unverified += doc_unv
    if norm_doc != "docs/agents-v0/onboarding/report.md" and not norm_doc.endswith("/docs/agents-v0/onboarding/report.md"):
        non_report_unverified += doc_unv
    if norm_doc.startswith("docs/agents-v0/onboarding/") and not re.search(r"^commit:\s*[0-9a-f]{7,40}\b", body, re.M):
        failures.append(f"{doc}: no `commit: <sha>` line (the commit this document describes)")
    cite_body = re.sub(r"<!--.*?-->", "", "\n".join(content_lines), flags=re.S)
    for m in CITE.finditer(cite_body):
        cites += 1
        path, start = m.group(1), int(m.group(2))
        end = int(m.group(3)) if m.group(3) else start
        count = line_count(path)
        if count is None:
            failures.append(f"{doc}: cited file does not exist: {path}")
        elif start < 1 or end < start or end > count:
            failures.append(f"{doc}: {path}:{m.group(2)}{('-' + m.group(3)) if m.group(3) else ''} is outside the file ({count} lines)")

if report_body is not None and non_report_unverified > 0 and report_open_question_rows(report_body) == 0:
    failures.append(
        f"docs/agents-v0/onboarding/report.md: {non_report_unverified} UNVERIFIED item(s) in onboarding documents "
        "but Open questions and UNVERIFIED items in report.md is empty"
    )

limit = os.environ.get("MAX_UNVERIFIED")
if limit and limit.isdigit() and unverified > int(limit):
    failures.append(f"{unverified} UNVERIFIED markers exceed MAX_UNVERIFIED={limit}")

print(f"checked {checked} document(s), {cites} citation(s), {unverified} UNVERIFIED marker(s)")
if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print("OK: onboarding documents cite real code")
PY
