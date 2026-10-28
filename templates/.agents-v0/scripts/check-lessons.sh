#!/bin/sh
# check-lessons.sh — validate the cross-story lessons memory.
#
# MEM-04: lessons learned in one story (a failure brief, a Verify fail, a re-open, a review
# finding) used to stay in that story's phase-result. They now flow into
# docs/agents-v0/lessons.md through the local-release gate, with a human decision on each.
# This script keeps that memory small, well-formed, and free of secrets.
#
# Usage:
#   sh .agents-v0/scripts/check-lessons.sh [options]
#
# With no options it checks docs/agents-v0/lessons.md, docs/agents-v0/lessons-archive.md, and the
# Lessons / Proposed lessons sections of every docs/agents-v0/requirements/*.phase-result.md and
# docs/agents-v0/maintain/*/phase-result.md.
#
# Options:
#   --phase-result <file>     check only this phase-result file (repeatable) plus the lessons files
#   --decided                 every entry under "## Proposed lessons" must be accepted or rejected
#                             (no "pending"). Run it before appending accepted entries to lessons.md.
#   --unchanged-since <ref>   fail when lessons.md or lessons-archive.md changed on this branch since
#                             it left <ref> (committed or not). Story branches never edit lessons.md.
#   --max-active <n>          active-entry cap in lessons.md (default 30, or $LESSONS_MAX_ACTIVE)
#   --max-chars <n>           size limit per entry or candidate (default 800, or $LESSONS_MAX_CHARS)
#   --next-id                 print the next free lesson id (e.g. L-007) and exit 0
#   --root <dir>              repository root (default: current directory)
#
# Exit 0: all checks pass. Exit 1: a check failed (plain FAIL lines on stderr). Exit 2: usage.
#
# Formats (see docs/agents-v0/lessons.md for the full description):
#   lessons.md entry:     ### L-NNN · YYYY-MM-DD · accepted
#                         - Story/phase: <story> / <phase>
#                         - Trigger: failure-brief | verify-fail | reopen | review | attempt-budget | blocked | other
#                         - What happened: ...
#                         - Do instead: ...
#                         - Scope: ...
#   archive entry:        same, status promoted (plus "- Promoted to: docs/agents-v0/project-profile.md ..."
#                         or an ADR / design record path) or retired (plus "- Reason: ...")
#   phase-result:         ## Lessons
#                         ### <phase>
#                         - Trigger: review · What happened: ... · Do instead: ... · Scope: ...
#                         (at most 3 bullets per phase; "- none" is allowed)
#   release proposal:     ## Proposed lessons
#                         - P-1 · pending · <phase> · Trigger: ... · What happened: ... · Do instead: ... · Scope: ...
#                         (pending | accepted | rejected)

set -eu

usage() {
  printf 'usage: %s [--phase-result FILE]... [--decided] [--unchanged-since REF] [--max-active N] [--max-chars N] [--next-id] [--root DIR]\n' "$0" >&2
  exit 2
}

prs=""
decided=0
since=""
next_id=0
max_active="${LESSONS_MAX_ACTIVE:-30}"
max_chars="${LESSONS_MAX_CHARS:-800}"
root=""
nl='
'
while [ $# -gt 0 ]; do
  case "$1" in
    --phase-result) [ $# -ge 2 ] || usage; prs="${prs}${2}${nl}"; shift 2 ;;
    --decided) decided=1; shift ;;
    --unchanged-since) [ $# -ge 2 ] || usage; since="$2"; shift 2 ;;
    --max-active) [ $# -ge 2 ] || usage; max_active="$2"; shift 2 ;;
    --max-chars) [ $# -ge 2 ] || usage; max_chars="$2"; shift 2 ;;
    --next-id) next_id=1; shift ;;
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
case "$max_active" in ''|*[!0-9]*) usage ;; esac
case "$max_chars" in ''|*[!0-9]*) usage ;; esac
if [ -n "$root" ]; then
  cd "$root" || { printf 'FAIL: --root not found: %s\n' "$root" >&2; exit 2; }
fi

CL_PRS="$prs" CL_DECIDED="$decided" CL_SINCE="$since" CL_NEXT="$next_id" \
CL_MAX_ACTIVE="$max_active" CL_MAX_CHARS="$max_chars" python3 - <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

LESSONS = Path("docs/agents-v0/lessons.md")
ARCHIVE = Path("docs/agents-v0/lessons-archive.md")
MAX_ACTIVE = int(os.environ["CL_MAX_ACTIVE"])
MAX_CHARS = int(os.environ["CL_MAX_CHARS"])
DECIDED = os.environ.get("CL_DECIDED") == "1"
SINCE = os.environ.get("CL_SINCE", "")
TRIGGERS = {"failure-brief", "verify-fail", "reopen", "review", "attempt-budget", "blocked", "other"}
PHASES = {"intake", "design", "build", "verify", "release", "maintain"}
REQUIRED = ("Story/phase", "Trigger", "What happened", "Do instead", "Scope")
CANDIDATE_FIELDS = ("Trigger", "What happened", "Do instead", "Scope")
HEAD_RE = re.compile(r"^### (L-(\d{3,}))\s+·\s+(\d{4}-\d{2}-\d{2})\s+·\s+([a-z]+)\s*$")
POINTER_RE = re.compile(r"docs/agents-v0/(project-profile\.md|adr/\S+\.md|design/\S+\.md)")

# Plain secret patterns. A match fails the check; the message names the line, not the value.
SECRET_RES = [
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("AWS access key id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{30,}\b")),
    ("GitLab token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b")),
    ("API secret key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("JSON Web Token", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    ("credential in URL", re.compile(r"\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]{3,}@", re.I)),
    ("password/secret/token assignment",
     re.compile(r"\b(?:password|passwd|pwd|secret|client[_-]?secret|api[_-]?key|access[_-]?token|auth[_-]?token|token)\b\s*[:=]\s*[\"']?(?![<$*{\[(]|x{3,}|\.\.\.|redacted|changeme|example|none|null|placeholder)[^\s\"'`]{8,}", re.I)),
]

errors = []


def fail(msg):
    errors.append(msg)


def strip_comments(text):
    # Keep line numbers stable: replace comment bodies with the same number of newlines.
    return re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


def scan_secrets(path, text):
    for no, line in enumerate(text.splitlines(), 1):
        for label, rx in SECRET_RES:
            if rx.search(line):
                fail(f"{path}:{no}: looks like a secret ({label}). Remove it; lessons must never hold secrets.")
                break


def parse_entries(path, text):
    """Return a list of entries: dict(id, num, date, status, lines, fields, line)."""
    entries = []
    cur = None
    for no, line in enumerate(text.splitlines(), 1):
        if line.startswith("### "):
            m = HEAD_RE.match(line)
            if not m:
                fail(f"{path}:{no}: bad entry heading {line.strip()!r}; expected '### L-NNN · YYYY-MM-DD · <status>'")
                cur = None
                continue
            cur = {"id": m.group(1), "num": int(m.group(2)), "date": m.group(3), "status": m.group(4),
                   "lines": [line], "fields": {}, "line": no}
            entries.append(cur)
            continue
        if line.startswith("## ") or line.startswith("# "):
            cur = None
            continue
        if cur is None:
            continue
        cur["lines"].append(line)
        fm = re.match(r"^- ([A-Za-z/ ]+?):\s*(.*)$", line)
        if fm:
            cur["fields"][fm.group(1).strip()] = fm.group(2).strip()
    return entries


def check_entry(path, e, allowed_status):
    where = f"{path}:{e['line']} {e['id']}"
    if e["status"] not in allowed_status:
        fail(f"{where}: status '{e['status']}' is not allowed here (use {' or '.join(sorted(allowed_status))})")
    for f in REQUIRED:
        if not e["fields"].get(f):
            fail(f"{where}: missing or empty '- {f}:' bullet")
    trig = (e["fields"].get("Trigger") or "").split()[0:1]
    if trig and trig[0].strip(",.;") not in TRIGGERS:
        fail(f"{where}: Trigger '{trig[0]}' is not one of {', '.join(sorted(TRIGGERS))}")
    body = "\n".join(l for l in e["lines"]).strip()
    if len(body) > MAX_CHARS:
        fail(f"{where}: entry is {len(body)} characters (limit {MAX_CHARS}); keep one short line per bullet")
    if e["status"] == "promoted" and not POINTER_RE.search(e["fields"].get("Promoted to", "")):
        fail(f"{where}: a promoted entry needs '- Promoted to: docs/agents-v0/project-profile.md ...' "
             "or an ADR / design record path")
    if e["status"] == "retired" and not e["fields"].get("Reason"):
        fail(f"{where}: a retired entry needs '- Reason: ...'")


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"{path}: cannot read ({exc.strerror or exc})")
        return ""


# --- lessons.md and lessons-archive.md ---------------------------------------------------
active, archived = [], []
if LESSONS.is_file():
    raw = read(LESSONS)
    scan_secrets(LESSONS, raw)
    active = parse_entries(LESSONS, strip_comments(raw))
if ARCHIVE.is_file():
    raw = read(ARCHIVE)
    scan_secrets(ARCHIVE, raw)
    archived = parse_entries(ARCHIVE, strip_comments(raw))

all_nums = [e["num"] for e in active + archived]
if os.environ.get("CL_NEXT") == "1":
    print(f"L-{(max(all_nums) if all_nums else 0) + 1:03d}")
    raise SystemExit(0)

for e in active:
    check_entry(LESSONS, e, {"accepted"})
for e in archived:
    check_entry(ARCHIVE, e, {"promoted", "retired"})

seen = {}
for path, group in ((LESSONS, active), (ARCHIVE, archived)):
    prev = 0
    for e in group:
        if e["id"] in seen:
            fail(f"{path}:{e['line']}: duplicate id {e['id']} (also at {seen[e['id']]})")
        else:
            seen[e["id"]] = f"{path}:{e['line']}"
        if e["num"] <= prev:
            fail(f"{path}:{e['line']}: {e['id']} is out of order (ids rise from top to bottom)")
        prev = max(prev, e["num"])
if all_nums:
    expected = set(range(1, max(all_nums) + 1))
    gaps = sorted(expected - set(all_nums))
    if gaps:
        fail("lesson ids are not sequential; missing " + ", ".join(f"L-{n:03d}" for n in gaps[:10])
             + " (number new entries with --next-id; move entries to the archive, do not delete them)")
if len(active) > MAX_ACTIVE:
    fail(f"{LESSONS}: {len(active)} active entries (cap {MAX_ACTIVE}). Move the oldest or least useful to "
         f"{ARCHIVE}: promote (rule in project-profile.md or an ADR) or retire.")

# --- phase-result Lessons / Proposed lessons ----------------------------------------------
pr_arg = [p for p in os.environ.get("CL_PRS", "").splitlines() if p.strip()]
if pr_arg:
    prs = [Path(p) for p in pr_arg]
else:
    prs = sorted(Path("docs/agents-v0/requirements").glob("*.phase-result.md")) \
        + sorted(Path("docs/agents-v0/maintain").glob("*/phase-result.md"))


def section(text, title):
    """Return (start_line_no, lines) of '## <title>' up to the next '## ' heading, or (0, None)."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.match(rf"^##\s+{re.escape(title)}\s*$", line, re.I):
            out = []
            for later in lines[i + 1:]:
                if re.match(r"^#{1,2}\s", later):
                    break
                out.append(later)
            return i + 2, out
    return 0, None


def has_fields(text, fields):
    return [f for f in fields if not re.search(rf"(?:^|·|\s){re.escape(f)}:\s*\S", text)]


for pr in prs:
    if not pr.is_file():
        fail(f"{pr}: phase-result file not found")
        continue
    raw = read(pr)
    text = strip_comments(raw)
    start, body = section(text, "Lessons")
    if body is not None:
        scan_secrets(f"{pr} (Lessons)", "\n".join(body))
        phase, counts = None, {}
        for off, line in enumerate(body):
            no = start + off
            h = re.match(r"^###\s+(\S+)\s*$", line)
            if h:
                phase = h.group(1).lower()
                if phase not in PHASES:
                    fail(f"{pr}:{no}: '### {h.group(1)}' is not a story phase ({', '.join(sorted(PHASES))})")
                if phase in counts:
                    fail(f"{pr}:{no}: phase '{phase}' appears twice under ## Lessons; keep one subsection per phase")
                counts.setdefault(phase, 0)
                continue
            if not line.startswith("- "):
                continue
            if re.match(r"^-\s+none\.?\s*$", line, re.I):
                continue
            if phase is None:
                fail(f"{pr}:{no}: lesson candidate outside a '### <phase>' subsection")
                continue
            counts[phase] = counts.get(phase, 0) + 1
            missing = has_fields(line, CANDIDATE_FIELDS)
            if missing:
                fail(f"{pr}:{no}: candidate is missing {', '.join(missing)}")
            if len(line) > MAX_CHARS:
                fail(f"{pr}:{no}: candidate is {len(line)} characters (limit {MAX_CHARS})")
        for ph, n in counts.items():
            if n > 3:
                fail(f"{pr}: {n} lesson candidates for phase '{ph}' (max 3 per phase). Keep the three that would "
                     "most change what the next story does.")
    start, body = section(text, "Proposed lessons")
    if body is not None:
        scan_secrets(f"{pr} (Proposed lessons)", "\n".join(body))
        for off, line in enumerate(body):
            no = start + off
            if not line.startswith("- "):
                continue
            if re.match(r"^-\s+none\.?\s*$", line, re.I):
                continue
            m = re.match(r"^- (P-\d+)\s+·\s+(pending|accepted|rejected)\s+·\s+(\S+)\s+·\s+(.*)$", line)
            if not m:
                fail(f"{pr}:{no}: bad proposed lesson; expected '- P-N · pending|accepted|rejected · <phase> · "
                     "Trigger: ... · What happened: ... · Do instead: ... · Scope: ...'")
                continue
            if m.group(3).lower() not in PHASES:
                fail(f"{pr}:{no}: {m.group(1)} phase '{m.group(3)}' is not a story phase")
            missing = has_fields(m.group(4), CANDIDATE_FIELDS)
            if missing:
                fail(f"{pr}:{no}: {m.group(1)} is missing {', '.join(missing)}")
            if DECIDED and m.group(2) == "pending":
                fail(f"{pr}:{no}: {m.group(1)} is still pending; ask the user to accept or reject it")

# --- story branches never edit lessons.md ------------------------------------------------
if SINCE:
    paths = [str(LESSONS), str(ARCHIVE)]
    r = subprocess.run(["git", "rev-parse", "--verify", "-q", f"{SINCE}^{{commit}}"],
                       capture_output=True, text=True, check=False)
    if r.returncode != 0:
        fail(f"--unchanged-since: unknown ref {SINCE}")
    else:
        committed = subprocess.run(["git", "diff", "--name-only", f"{SINCE}...HEAD", "--", *paths],
                                   capture_output=True, text=True, check=False).stdout.split()
        local = subprocess.run(["git", "diff", "--name-only", "HEAD", "--", *paths],
                               capture_output=True, text=True, check=False).stdout.split()
        untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", *paths],
                                   capture_output=True, text=True, check=False).stdout.split()
        changed = sorted(set(committed + local + untracked))
        if changed:
            fail("this branch changed " + ", ".join(changed) + f" since {SINCE}. Story branches never edit "
                 "lessons.md; put candidates in the phase-result '## Lessons' section and restore the file "
                 f"(git checkout {SINCE} -- <file>, after the user agrees).")

if errors:
    for msg in errors:
        print(f"FAIL: {msg}", file=sys.stderr)
    print(f"check-lessons: {len(errors)} problem(s)", file=sys.stderr)
    raise SystemExit(1)
print(f"check-lessons: OK ({len(active)} active, {len(archived)} archived, {len(prs)} phase-result file(s) checked)")
PY
