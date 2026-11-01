#!/bin/sh
# check-onboarding-docs.sh — the onboarding documents cite real code (onboard-discovery).
#
# Usage: sh .agents-v0/scripts/check-onboarding-docs.sh [<path>...]
#        sh .agents-v0/scripts/check-onboarding-docs.sh --gate
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
#
# --gate (onboard fix JO-3/JO-4; design jiraiya-onboard-fix-design-20261101.md rev 6, lines 23, 86, 110, 119):
# the Onboard gate's docs check, run by `gate-checks.sh approval_evidence onboard` before --approve onboard.
# It checks documents only: it never approves, commits, writes state or scans for secrets. It runs from the
# repo root (a git work tree is required) and, on top of everything above, fails when:
#   - an entry of the gate-rules `onboard_gate_docs` list is missing: a file entry must be a non-empty file, an
#     entry ending in `/` must be a directory holding at least one .md document (templates do not count);
#   - the context map has no table row below a header row (the empty template row does not count);
#   - report.md names a docs/agents-v0/onboarding/modules/<name>.md or docs/agents-v0/diagrams/sequences/<name>.md
#     that does not exist;
#   - a `commit:` stamp in a checked document is not a commit of this repo or not in the history of HEAD.
# In --gate every _*.md file (_template.md, _*.template.md) is a template: never scanned, never a gate document.
# Citations also accept more extensions and extensionless build files (Dockerfile, Makefile, ...); a
# citation-like `path.ext:N` that is not backticked is not checked and is reported as a WARN line (no failure).
# The gate document list lives only in gate-rules (read through gate-checks.sh rules; any error there fails
# closed). Exit codes: 0 pass, 1 fail, 2 usage or gate-rules error.
# Not here yet (gap 10, blocked on the ledger and hook work): each --gate failure adding a ledger FAIL line and the
# retry cap (gate-rules docs_check_cap).

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

GATE=0
GATE_DOCS=""
if [ "${1:-}" = "--gate" ]; then
  shift
  [ "$#" -eq 0 ] || { printf 'usage: sh .agents-v0/scripts/check-onboarding-docs.sh --gate (takes no paths; the list is gate-rules onboard_gate_docs)\n' >&2; exit 2; }
  GATE=1
  HERE="$(cd "$(dirname "$0")" && pwd)"
  [ -f "$HERE/gate-checks.sh" ] || { printf 'FAIL: %s/gate-checks.sh is missing, so the gate docs list cannot be read (reinstall the kit: install.sh --update)\n' "$HERE" >&2; exit 2; }
  GATE_DOCS="$(sh "$HERE/gate-checks.sh" rules onboard_gate_docs)" || { printf 'FAIL: cannot read onboard_gate_docs from gate-rules (see the error above)\n' >&2; exit 2; }
  [ -n "$GATE_DOCS" ] || { printf 'FAIL: gate-rules onboard_gate_docs is empty\n' >&2; exit 2; }
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  [ -n "$top" ] || { printf 'FAIL: --gate needs a git work tree (commit stamps are checked against the history)\n' >&2; exit 1; }
  cd "$top" || { printf 'FAIL: cannot cd to %s\n' "$top" >&2; exit 2; }
  [ -f docs/agents-v0/onboarding/report.md ] || { printf 'FAIL: docs/agents-v0/onboarding/report.md is missing (copy docs/agents-v0/onboarding/_report.template.md)\n' >&2; exit 1; }
  set -- docs/agents-v0/onboarding docs/agents-v0/architecture.md docs/agents-v0/network.md docs/agents-v0/design/system/context-map.md docs/agents-v0/diagrams docs/agents-v0/adr/0000-inherited-decisions.md
  # Split the list on blanks only: no pathname expansion (gate-checks.sh also refuses * ? [ in it).
  case "$-" in *f*) had_f=1 ;; *) had_f=0 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- "$@" $GATE_DOCS
  [ "$had_f" = 1 ] || set +f
  present=""
  for path in "$@"; do
    case "$path" in
      *.md|*/) [ -e "$path" ] && present="$present $path" ;;
      *) [ -d "$path" ] && present="$present $path" ;;
    esac
  done
  # shellcheck disable=SC2086
  set -- $present
elif [ "$#" -eq 0 ]; then
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

CHECK_PATHS="$(printf '%s\n' "$@")" GATE="$GATE" GATE_DOCS="$GATE_DOCS" python3 - <<'PY'
import os
import re
import subprocess
import sys

EXT = ("java|kt|cs|rs|rb|php|swift|scala|c|cpp|h|hpp|ts|tsx|js|jsx|svelte|vue|py|go|xml|csproj|sln|yml|yaml|json|properties|sql|gradle|kts|md|sh|html|css|toml|tf|conf")
CITE = re.compile(r"`([A-Za-z0-9_./@+\-]+\.(?:%s)):(\d+)(?:-(\d+))?`" % EXT)
GATE = os.environ.get("GATE") == "1"
if GATE:
    # JO-4: more source and config extensions, and extensionless build files (Dockerfile, Dockerfile.dev, ...).
    EXT = EXT + "|mjs|cjs|mts|cts|txt|ini|cfg|bat|cmd|ps1|groovy|proto|graphql|gql|scss|sass|less|dart|lua|pl|r|ex|exs|erl|clj|m|mm|cmake|bzl|bazel|nix|hcl|tfvars|tpl|j2|jinja|xsd|wsdl|rst|adoc|csv|mk|dockerfile|bash|zsh|fs|vb|razor|cshtml|jsp|ftl|hbs|ejs|pug|mustache"
    NAMES = "Dockerfile|Containerfile|Makefile|GNUmakefile|Jenkinsfile|Procfile|Gemfile|Rakefile|Vagrantfile|Brewfile|Justfile|Tiltfile|CODEOWNERS"
    TARGET = r"(?:[A-Za-z0-9_.@+\-]+/)*(?:[A-Za-z0-9_.@+\-]+\.(?:%s)|(?:%s)(?:\.[A-Za-z0-9_\-]+)?)" % (EXT, NAMES)
    CITE = re.compile(r"`(%s):(\d+)(?:-(\d+))?`" % TARGET)
    # A citation-like token outside backticks: a path with a / or a known extension, then :N (hostnames like
    # db.internal:5432 do not match: their suffix is not an extension above).
    BARE = re.compile(r"(?<![`\w/.@+\-])(%s):(\d+)(?:-\d+)?(?![\w`])" % TARGET)
failures, unverified, checked, cites = [], 0, 0, 0
warnings = []
line_counts = {}


def line_count(path):
    if path not in line_counts:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                line_counts[path] = sum(1 for _ in handle)
        except OSError:
            line_counts[path] = None
    return line_counts[path]


def is_template(name):
    # Default run: _*.template.md only (unchanged). --gate: every _*.md is a template (design rev 6 line 516).
    if GATE:
        return name.startswith("_")
    return name.startswith("_") and name.endswith(".template.md")


docs = []
for raw in os.environ["CHECK_PATHS"].splitlines():
    if not raw:
        continue
    if os.path.isdir(raw):
        for dirpath, _dirs, names in os.walk(raw):
            for name in sorted(names):
                if name.endswith(".md") and not is_template(name):
                    docs.append(os.path.join(dirpath, name))
    elif os.path.isfile(raw) and not (GATE and is_template(os.path.basename(raw))):
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
stamps = []
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
    if GATE:
        for line in re.sub(r"`[^`\n]*`", "", cite_body).splitlines():
            for m in BARE.finditer(line):
                warnings.append(f"{doc}: citation-like {m.group(0)} is not backticked, so it is not checked")
        for m in re.finditer(r"^commit:\s*(\S+)", body, re.M):
            stamps.append((doc, m.group(1)))

if report_body is not None and non_report_unverified > 0 and report_open_question_rows(report_body) == 0:
    failures.append(
        f"docs/agents-v0/onboarding/report.md: {non_report_unverified} UNVERIFIED item(s) in onboarding documents "
        "but Open questions and UNVERIFIED items in report.md is empty"
    )

def git(*args):
    return subprocess.run(["git", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def is_md_doc(name):
    return name.endswith(".md") and not is_template(name)


if GATE:
    # JO-3: every gate document of gate-rules onboard_gate_docs is present.
    for entry in os.environ.get("GATE_DOCS", "").split():
        if entry.startswith("/") or ".." in entry.split("/"):
            failures.append(f"gate-rules onboard_gate_docs: {entry} is not a path inside the repo")
        elif entry.endswith("/"):
            found = os.path.isdir(entry) and any(
                is_md_doc(n) for _d, _s, names in os.walk(entry) for n in names
            )
            if not found:
                failures.append(f"{entry} has no document (a gate document of gate-rules onboard_gate_docs; templates do not count)")
        elif not os.path.isfile(entry) or os.path.getsize(entry) == 0:
            failures.append(f"{entry} is missing or empty (a gate document of gate-rules onboard_gate_docs)")
    # JO-3: the context map has at least one table row below a header row.
    cm = "docs/agents-v0/design/system/context-map.md"
    if os.path.isfile(cm):
        rows, prev_sep = 0, False
        for line in re.sub(r"<!--.*?-->", "", open(cm, encoding="utf-8", errors="replace").read(), flags=re.S).splitlines():
            s = line.strip()
            if not s.startswith("|"):
                prev_sep = False
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if cells and all(c and set(c) <= set("-: ") for c in cells):
                prev_sep = True
                continue
            if prev_sep and any(cells):
                rows += 1
        if rows == 0:
            failures.append(f"{cm}: no context or integration row below the table header (the empty template row does not count)")
    # JO-3: each module and sequence document report.md names exists.
    if report_body is not None:
        named = re.sub(r"<!--.*?-->", "", report_body, flags=re.S)
        named = "\n".join(ln for ln in named.splitlines() if not ln.lstrip().startswith(">"))
        for rel in sorted(set(re.findall(r"docs/agents-v0/(?:onboarding/modules|diagrams/sequences)/[A-Za-z0-9_.\-]+\.md", named))):
            if not os.path.isfile(rel):
                failures.append(f"docs/agents-v0/onboarding/report.md names {rel}, which does not exist")
    # JO-4: every commit stamp is a commit of this repo and in the history of HEAD.
    for doc, sha in stamps:
        if not re.fullmatch(r"[0-9a-f]{7,40}", sha):
            failures.append(f"{doc}: commit stamp {sha} is not a commit id (7-40 lowercase hex)")
        elif not git("cat-file", "-e", sha + "^{commit}"):
            failures.append(f"{doc}: commit stamp {sha} is not a commit in this repository")
        elif not git("merge-base", "--is-ancestor", sha, "HEAD"):
            failures.append(f"{doc}: commit stamp {sha} is not in the history of HEAD")

limit = os.environ.get("MAX_UNVERIFIED")
if limit and limit.isdigit() and unverified > int(limit):
    failures.append(f"{unverified} UNVERIFIED markers exceed MAX_UNVERIFIED={limit}")

print(f"checked {checked} document(s), {cites} citation(s), {unverified} UNVERIFIED marker(s)")
for item in warnings:
    print(f"WARN: {item}")
if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
if GATE:
    print("OK: onboarding gate documents are present, cite real code and name real commits (--gate)")
else:
    print("OK: onboarding documents cite real code")
PY
