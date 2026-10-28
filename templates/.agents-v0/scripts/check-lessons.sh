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
#   --approval-text <text>    with exactly one --phase-result: check the release decisions against the
#                             user's release approval message, passed verbatim (MEM-14, grammar below)
#   --accepted <P-1,P-3>      same check with an explicit accepted list instead of the message
#                             ("none" or "" = nothing accepted)
#   --root <dir>              repository root (default: current directory)
#
# Approval grammar (--approval-text, MEM-14; case does not matter):
#   "Accept P-1"  "Accept P-1, P-3"  "Accept P-1 and P-3"  "Keep P-2"  "Accept all"  -> accepted
#   "Reject P-2"  "Reject P-2 and P-4"  "Drop P-5"  "reject any other proposed lessons" -> rejected
#   ("Accept all, reject P-2" accepts every P-<n> except P-2.)
#   "Accept P-1 if proposed" is tolerated: no error when P-1 does not exist. Without "if proposed",
#   accepting a P-<n> that is not in "## Proposed lessons" fails. A P-<n> that is both accepted and
#   rejected fails. Anything not explicitly accepted is rejected (the local-release rule).
# The check then requires: every P-<n> is marked accepted exactly when the message accepts it, and
# docs/agents-v0/lessons.md holds exactly one active entry per accepted P-<n> for this story
# (same Story/phase, What happened, Do instead, Trigger, Scope) and none for a rejected one.
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
  printf 'usage: %s [--phase-result FILE]... [--decided] [--unchanged-since REF] [--tip REF] [--max-active N] [--max-chars N] [--next-id] [--approval-text TEXT | --accepted LIST] [--root DIR]\n' "$0" >&2
  exit 2
}

prs=""
decided=0
since=""
tip="HEAD"
next_id=0
approval=""
approval_set=0
accepted_list=""
accepted_set=0
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
    --tip) [ $# -ge 2 ] || usage; tip="$2"; shift 2 ;;
    --max-active) [ $# -ge 2 ] || usage; max_active="$2"; shift 2 ;;
    --max-chars) [ $# -ge 2 ] || usage; max_chars="$2"; shift 2 ;;
    --next-id) next_id=1; shift ;;
    --approval-text) [ $# -ge 2 ] || usage; approval="$2"; approval_set=1; shift 2 ;;
    --accepted) [ $# -ge 2 ] || usage; accepted_list="$2"; accepted_set=1; shift 2 ;;
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
case "$max_active" in ''|*[!0-9]*) usage ;; esac
case "$max_chars" in ''|*[!0-9]*) usage ;; esac
if [ "$approval_set" = 1 ] && [ "$accepted_set" = 1 ]; then
  printf 'FAIL: use --approval-text or --accepted, not both\n' >&2
  exit 2
fi
if [ "$approval_set" = 1 ] || [ "$accepted_set" = 1 ]; then
  # MEM-14: the decision check is about one story, so it needs exactly one phase-result.
  if [ "$(printf '%s' "$prs" | grep -c .)" != 1 ]; then
    printf 'FAIL: --approval-text / --accepted needs exactly one --phase-result <file>\n' >&2
    exit 2
  fi
fi
if [ -n "$root" ]; then
  cd "$root" || { printf 'FAIL: --root not found: %s\n' "$root" >&2; exit 2; }
fi

CL_APPROVAL="$approval" CL_APPROVAL_SET="$approval_set" CL_ACCEPTED="$accepted_list" CL_ACCEPTED_SET="$accepted_set" \
CL_PRS="$prs" CL_DECIDED="$decided" CL_SINCE="$since" CL_TIP="$tip" CL_NEXT="$next_id" \
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
TIP = os.environ.get("CL_TIP", "HEAD") or "HEAD"
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
    rt = subprocess.run(["git", "rev-parse", "--verify", "-q", f"{TIP}^{{commit}}"],
                        capture_output=True, text=True, check=False)
    head = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD^{commit}"],
                          capture_output=True, text=True, check=False)
    if r.returncode != 0:
        fail(f"--unchanged-since: unknown ref {SINCE}")
    elif rt.returncode != 0:
        fail(f"--tip: unknown ref {TIP}")
    else:
        committed = subprocess.run(["git", "diff", "--name-only", f"{SINCE}...{TIP}", "--", *paths],
                                   capture_output=True, text=True, check=False).stdout.split()
        local, untracked = [], []
        if TIP == "HEAD" or (head.returncode == 0 and rt.stdout.strip() == head.stdout.strip()):
            local = subprocess.run(["git", "diff", "--name-only", "HEAD", "--", *paths],
                                   capture_output=True, text=True, check=False).stdout.split()
            untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", *paths],
                                       capture_output=True, text=True, check=False).stdout.split()
        changed = sorted(set(committed + local + untracked))
        if changed:
            # MEM-12: restore from the branch point, not from <ref>. When <ref> gained lessons after the
            # branch was cut (another story released), "git checkout <ref> -- <file>" would copy those
            # new lessons into the branch and this check would still fail.
            base = subprocess.run(["git", "merge-base", SINCE, TIP], capture_output=True, text=True,
                                  check=False).stdout.strip()
            at = f" (= {base[:12]})" if base else ""
            fail("this branch changed " + ", ".join(changed) + f" since {SINCE}. Story branches never edit "
                 "lessons.md; put candidates in the phase-result '## Lessons' section and, after the user "
                 f"agrees, restore the file from the branch point{at}: "
                 f"git checkout $(git merge-base {SINCE} {TIP}) -- {' '.join(changed)} (then commit the restore when the "
                 "edit was committed)")

# --- MEM-14: the decisions and lessons.md match the user's release approval -------------------
FIELD_RE = re.compile(r"(Trigger|What happened|Do instead|Scope):\s*(.*?)(?=\s+·\s+(?:Trigger|What happened|Do instead|Scope):|$)")


def norm_text(v):
    return re.sub(r"\s+", " ", (v or "").strip()).rstrip(".").lower()


def parse_approval(text, proposed_ids):
    """Return (accepted set, problems). Grammar in the header of this script."""
    problems, accepted, rejected = [], set(), set()
    pid_list = r"P-\d+(?:\s*(?:,|and|&|\+)\s*P-\d+)*"
    for m in re.finditer(rf"\b(accept(?:ed|s|ing)?|keep|reject(?:ed|s|ing)?|drop)\s+({pid_list})(\s+if\s+proposed)?",
                         text, re.I):
        verb = m.group(1).lower()
        ids = [x.upper() for x in re.findall(r"P-\d+", m.group(2), re.I)]
        tolerant = bool(m.group(3))
        for pid in ids:
            if pid not in proposed_ids:
                if not tolerant:
                    problems.append(f"the approval {'accepts' if verb[0] in 'ak' else 'rejects'} {pid}, "
                                    "which is not in ## Proposed lessons")
                continue
            (accepted if verb[0] in "ak" else rejected).add(pid)
    both = sorted(accepted & rejected, key=lambda x: int(x[2:]))
    for pid in both:
        problems.append(f"the approval both accepts and rejects {pid}; ask the user which one they meant")
    if re.search(r"\b(?:accept|keep)\s+all\b", text, re.I):
        accepted |= set(proposed_ids) - rejected
    return accepted - rejected, problems


def story_of(pr):
    parts = Path(pr).parts
    if pr.name == "phase-result.md" and "maintain" in parts:
        return pr.parent.name
    return pr.name[: -len(".phase-result.md")] if pr.name.endswith(".phase-result.md") else pr.stem


if os.environ.get("CL_APPROVAL_SET") == "1" or os.environ.get("CL_ACCEPTED_SET") == "1":
    pr = prs[0]
    story = story_of(pr)
    props = []
    if pr.is_file():
        start, body = section(strip_comments(read(pr)), "Proposed lessons")
        for line in body or []:
            m = re.match(r"^- (P-\d+)\s+·\s+(pending|accepted|rejected)\s+·\s+(\S+)\s+·\s+(.*)$", line)
            if m:
                fields = dict(FIELD_RE.findall(m.group(4)))
                props.append({"id": m.group(1), "status": m.group(2), "phase": m.group(3).lower(), "f": fields})
    ids = [p["id"] for p in props]
    if os.environ.get("CL_APPROVAL_SET") == "1":
        want, problems = parse_approval(os.environ.get("CL_APPROVAL", ""), ids)
        for msg in problems:
            fail(f"{pr}: {msg}")
    else:
        raw_list = os.environ.get("CL_ACCEPTED", "").strip()
        want = set()
        if raw_list.lower() not in ("", "none", "-"):
            for tok in re.split(r"[,\s]+", raw_list):
                if not tok:
                    continue
                if not re.fullmatch(r"P-\d+", tok, re.I):
                    fail(f"--accepted: '{tok}' is not a P-<n> id")
                elif tok.upper() not in ids:
                    fail(f"{pr}: --accepted names {tok.upper()}, which is not in ## Proposed lessons")
                else:
                    want.add(tok.upper())
    # Active entries of this story in lessons.md.
    mine = []
    for e in active:
        sp = e["fields"].get("Story/phase", "")
        st, _, ph = sp.partition("/")
        if st.strip().lower() == story.lower():
            mine.append({"e": e, "phase": ph.strip().lower()})
    used = set()
    for p in props:
        expect = "accepted" if p["id"] in want else "rejected"
        if p["status"] != expect:
            fail(f"{pr}: {p['id']} is marked {p['status']} but the approval {'accepts' if expect == 'accepted' else 'does not accept'} "
                 f"it; mark it {expect}")
        what, do = norm_text(p["f"].get("What happened")), norm_text(p["f"].get("Do instead"))
        hits = [i for i, m in enumerate(mine)
                if norm_text(m["e"]["fields"].get("What happened")) == what
                or norm_text(m["e"]["fields"].get("Do instead")) == do]
        if expect == "rejected":
            for i in hits:
                used.add(i)
                fail(f"{LESSONS}: {mine[i]['e']['id']} repeats {p['id']}, which the user did not accept; remove it "
                     "(rejected lessons stay in the phase-result only)")
            continue
        if not hits:
            fail(f"{LESSONS}: accepted {p['id']} ({story} / {p['phase']}) has no active entry; append it with an id "
                 "from --next-id")
            continue
        if len(hits) > 1:
            fail(f"{LESSONS}: accepted {p['id']} appears {len(hits)} times ("
                 + ", ".join(mine[i]["e"]["id"] for i in hits) + "); keep one")
        for i in hits:
            used.add(i)
            e = mine[i]["e"]
            diffs = []
            if mine[i]["phase"] != p["phase"]:
                diffs.append(f"Story/phase '{e['fields'].get('Story/phase')}' (want '{story} / {p['phase']}')")
            for key in ("What happened", "Do instead", "Trigger", "Scope"):
                if norm_text(e["fields"].get(key)) != norm_text(p["f"].get(key)):
                    diffs.append(f"{key}")
            if diffs:
                fail(f"{LESSONS}: {e['id']} does not match accepted {p['id']}: " + "; ".join(diffs)
                     + " differ from the phase-result proposal")
    for i, m in enumerate(mine):
        if i not in used:
            fail(f"{LESSONS}: {m['e']['id']} is a lesson for {story} that matches no accepted proposal in {pr}")
    if not errors:
        acc = sorted(want, key=lambda x: int(x[2:]))
        print(f"check-lessons: approval matches ({', '.join(acc) or 'none'} accepted, "
              f"{len(props) - len(acc)} rejected, {len(mine)} lesson(s) for {story})")

if errors:
    for msg in errors:
        print(f"FAIL: {msg}", file=sys.stderr)
    print(f"check-lessons: {len(errors)} problem(s)", file=sys.stderr)
    raise SystemExit(1)
print(f"check-lessons: OK ({len(active)} active, {len(archived)} archived, {len(prs)} phase-result file(s) checked)")
PY
