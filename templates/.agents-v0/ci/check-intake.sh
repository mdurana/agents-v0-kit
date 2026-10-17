#!/bin/sh
# check-intake.sh — an Intake artifact is testable before the gate is presented.
#
# Usage: sh .agents-v0/ci/check-intake.sh docs/agents-v0/requirements/<feature>.md
#
# Skips Story: P0-A (that file is copied by /v0-build). Otherwise requires the
# spec-intake shape: one user-story sentence, Surfaces, Material, Preconditions,
# Desk check, AC-1..AC-n (at most 8) each with Kind, Given, When, and a Then
# that is long enough and not a banned phrase, one negative or edge (or
# Negatives: N/A when no security trigger), Out of scope, NFRs, Regulations,
# Security-review triggers, and Open questions: none. A security-review trigger
# needs a Kind: negative whose Then is a refusal. An open ## Proposed split fails.
# Needs python3.

set -eu

art="${1:-}"
if [ -z "$art" ]; then
  printf 'usage: %s docs/agents-v0/requirements/<feature>.md\n' "$0" >&2
  exit 1
fi
[ -f "$art" ] || { printf 'FAIL: requirements artifact not found: %s\n' "$art" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

ART="$art" python3 - <<'PY'
import os
import re
import sys

path = os.environ["ART"]
with open(path, encoding="utf-8", errors="replace") as handle:
    text = handle.read()
failures = []


def fail(msg):
    failures.append(msg)


if re.search(r"(?m)^Story:\s*P0-A\s*$", text):
    print(f"OK: {path} is P0-A and skips the intake check")
    raise SystemExit(0)

BANNED = ("works as expected", "handles errors gracefully", "successfully processes")
REFUSAL = re.compile(
    r"(?i)(\b(400|401|403|422)\b|unauthorized|forbidden|rejected|denied|invalid|validation)"
)
PLACEHOLDER = re.compile(
    r"(<[^>\n]+>|\[\.\.\.\]|\b(TBD|TODO|FIXME|XXX?)\b|__+|[?]{2,}|TEMPLATE:)",
    re.IGNORECASE,
)
TRIGGER = re.compile(r"(?i)\b(auth|authentication|authorization|upload|rbac|public route)\b")
SURFACES = {"backend", "bff", "frontend"}


def sections(body):
    out, name, buf = {}, None, []
    for line in body.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if name is not None:
                out[name] = "\n".join(buf)
            name, buf = m.group(1).lower(), []
        elif name is not None:
            buf.append(line)
    if name is not None:
        out[name] = "\n".join(buf)
    return out


def section(secs, key):
    for name, body in secs.items():
        if key in name:
            return body
    return None


def plain(body):
    text_ = re.sub(r"<!--.*?-->", "", body or "", flags=re.S)
    return "\n".join(l for l in text_.splitlines() if l.strip() and not re.match(r"^\s*\|[-:| ]+\|\s*$", l))


def na_reason(body):
    m = re.search(r"(?i)\bN/A\b\s*:\s*(.+)", plain(body))
    return bool(m and len(m.group(1).strip()) >= 4)


def is_none(body):
    words = " ".join(re.sub(r"(?m)^\s*[-*]\s*", "", plain(body)).split())
    return bool(re.match(r"(?i)^(none|n/a\b)", words))


def filled(body, allow_na=True, allow_none=False, min_len=20):
    text_ = plain(body)
    if allow_na and na_reason(text_):
        return True
    if allow_none and is_none(text_):
        return True
    return len(text_.strip()) >= min_len


secs = sections(text)
if re.search(r"(?m)^##\s+Proposed split\s*$", text):
    fail(f"{path}: Proposed split is still open — do not present the Intake gate")
    split_body = section(secs, "proposed split") or ""
    if not re.search(r"(?m)^\s*\|.+\|.+\|", split_body):
        fail(f"{path}: Proposed split must list extra stories in a table (sentence, surface, dependency)")

stories = [l for l in text.splitlines() if re.match(r"(?i)^As a .+?, I want .+?, so that \S", l)]
if len(stories) != 1:
    fail(f"{path}: user story must be one line: As a [role], I want [goal], so that [benefit].")
elif "<" in stories[0] or ">" in stories[0]:
    fail(f"{path}: user story still has a placeholder")

if not re.search(r"(?mi)^Material:\s*(yes|no)\s*$", text):
    fail(f"{path}: Material: must be yes or no")

surf = re.search(r"(?m)^Surfaces:\s*(.+)$", text)
vert = re.search(r"(?mi)^Vertical slice:\s*yes\s*$", text)
if not surf:
    fail(f"{path}: Surfaces: is missing")
else:
    parts = [p.strip() for p in surf.group(1).split(",") if p.strip()]
    if not parts or any(p not in SURFACES for p in parts):
        fail(f"{path}: Surfaces: must be backend, bff, or frontend")
    elif not vert and len(parts) != 1:
        fail(f"{path}: Surfaces: must be one surface unless Vertical slice: yes")

ms = re.search(r"(?m)^Milestone:\s*\S", text)
mf = re.search(r"(?m)^Milestone file:\s*(\S+)", text)
st = re.search(r"(?m)^Story:\s*(\S+)", text)
if ms and not mf:
    fail(f"{path}: Milestone: is set but Milestone file: is missing")
if mf:
    mpath = mf.group(1).strip()
    if ".." in mpath or not mpath.startswith("docs/agents-v0/milestones/") or not mpath.endswith(".md"):
        fail(f"{path}: Milestone file: must be docs/agents-v0/milestones/<name>.md")
    elif not os.path.isfile(mpath):
        fail(f"{path}: Milestone file not found: {mpath}")
    elif not st:
        fail(f"{path}: Story: is missing")
    elif not re.search(r"\b%s\b" % re.escape(st.group(1)), open(mpath, encoding="utf-8", errors="replace").read()):
        fail(f"{path}: {mpath} does not name {st.group(1)}")

pre = section(secs, "preconditions")
if pre is None:
    fail(f"{path}: section 'Preconditions' is missing")
elif not filled(pre):
    fail(f"{path}: Preconditions is empty (write it, or \"N/A: <reason>\")")

desk = section(secs, "desk check")
if desk is None:
    fail(f"{path}: section 'Desk check' is missing")
else:
    desk_text = plain(desk).strip()
    if len(desk_text) < 40 or PLACEHOLDER.search(desk_text):
        fail(f"{path}: Desk check must be one sentence with no placeholder")

scope = section(secs, "out of scope")
if scope is None:
    fail(f"{path}: section 'Out of scope' is missing")
elif not (is_none(scope) or na_reason(scope) or re.search(r"(?m)^\s*[-*]\s+\S{3,}", plain(scope) or "")):
    fail(f"{path}: Out of scope needs a bullet, \"none\", or \"N/A: <reason>\"")

for key, label in (("nfr", "NFRs"), ("regulation", "Regulations")):
    body = section(secs, key)
    if body is None:
        fail(f"{path}: section '{label}' is missing")
    elif not filled(body):
        fail(f"{path}: section '{label}' is empty (write it, or \"N/A: <reason>\")")

if surf and "frontend" in surf.group(1).lower():
    ux = section(secs, "ux requirements")
    if ux is None:
        fail(f"{path}: section 'UX requirements' is missing")
    elif not filled(ux, allow_none=False):
        fail(f"{path}: UX requirements are empty")

trig = section(secs, "security-review triggers")
if trig is None:
    fail(f"{path}: section 'Security-review triggers' is missing")
    has_trigger = False
elif not plain(trig).strip():
    fail(f"{path}: Security-review triggers is empty (write the triggers, or \"none\")")
    has_trigger = False
else:
    has_trigger = (not is_none(trig)) and bool(TRIGGER.search(plain(trig)))

oq = section(secs, "open questions")
if oq is None:
    fail(f"{path}: section 'Open questions' is missing")
elif not re.match(r"(?i)^none\s*$", " ".join(plain(oq).split())):
    fail(f"{path}: Open questions must be 'none' before the gate")

waiver = re.search(r"(?m)^Negatives:\s*N/A:\s*(.+)$", text)
waiver_ok = bool(waiver and len(waiver.group(1).strip()) >= 4)
if waiver and has_trigger:
    fail(f"{path}: Negatives: N/A is not allowed when a security-review trigger applies")

blocks = re.split(r"(?m)^###\s+", text)[1:]
acs = []
seen = set()
mentioned = set(re.findall(r"\bAC-\d+\b", text))
refusal = False
for block in blocks:
    m = re.match(r"(AC-\d+)\b[ \t]+(.+)$", block, re.M)
    if not m:
        if re.match(r"AC-\d+\b", block):
            fail(f"{path}: {block.splitlines()[0]} needs a scenario name")
        continue
    ac, name = m.group(1), m.group(2).strip(" -—\t")
    if ac in seen:
        fail(f"{path}: {ac} is duplicated")
    seen.add(ac)
    if len(name) < 3:
        fail(f"{path}: {ac} needs a scenario name")
    kind_m = re.search(r"(?mi)^Kind:\s*(happy|negative|edge)\s*$", block)
    if not kind_m:
        fail(f"{path}: {ac} needs Kind: happy, negative, or edge")
        kind = ""
    else:
        kind = kind_m.group(1).lower()
    for label in ("Given", "When", "Then"):
        if not re.search(r"(?m)^%s\s+\S.{2,}" % label, block):
            fail(f"{path}: {ac} needs a {label} line")
    then_lines = []
    take = False
    for line in block.splitlines():
        if re.match(r"^Then\b", line):
            take = True
        elif take and not re.match(r"^And\b", line):
            break
        if take:
            then_lines.append(line)
    outcome = " ".join(then_lines)
    low = outcome.lower()
    for phrase in BANNED:
        if phrase in low:
            fail(f"{path}: {ac} Then contains \"{phrase}\"")
    if outcome and len(outcome.strip()) < 12:
        fail(f"{path}: {ac} Then is too short")
    if kind == "negative" and REFUSAL.search(outcome):
        refusal = True
    acs.append((ac, kind))

headed = {ac for ac, _k in acs}
for ac in sorted(mentioned - headed, key=lambda s: int(s.split("-")[1])):
    fail(f"{path}: {ac} is not a ### heading")

nums = sorted(int(ac.split("-")[1]) for ac, _k in acs)
if not nums:
    fail(f"{path}: no acceptance criteria")
elif nums != list(range(1, len(nums) + 1)):
    fail(f"{path}: acceptance criteria must be AC-1 through AC-{len(nums)} with no gaps")
elif len(nums) > 8:
    fail(f"{path}: more than eight acceptance criteria")

kinds = {k for _ac, k in acs}
if "negative" not in kinds and "edge" not in kinds and not waiver_ok:
    fail(f"{path}: needs one Kind: negative or Kind: edge, or a Negatives: N/A line when no security-review trigger applies")
if has_trigger and not refusal:
    fail(f"{path}: a security-review trigger needs a Kind: negative whose Then is an authorization or validation refusal")

if failures:
    for msg in failures:
        print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: {path} passes the intake check")
PY
