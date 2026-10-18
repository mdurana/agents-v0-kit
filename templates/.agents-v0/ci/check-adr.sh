#!/bin/sh
# check-adr.sh — an accepted ADR stays; a later decision is a successor.
#
# Usage: sh .agents-v0/ci/check-adr.sh
# Scans docs/agents-v0/adr/*.md. Each record has Status Proposed, Accepted,
# Accepted (inherited), or "Superseded by ADR <NN>". A superseded record names
# one existing successor whose status is Accepted. The successor has its own
# alternatives. A superseded record names its successor; that chain ends at an
# Accepted ADR. docs/agents-v0/adr/0000-inherited-decisions.md is the as-is
# record and is not edited after it is accepted.
#
# When git history contains an Accepted revision, later revisions and the
# working tree may change only the Status line, and only to Superseded by a
# successor. Rewriting Decision or Alternatives fails. With no git history,
# structure is still checked.

set -eu
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

python3 - <<'PY'
import os
import re
import subprocess
import sys

adr_dir = os.path.join("docs", "agents-v0", "adr")
failures = []


def fail(msg):
    failures.append(msg)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def adr_status(text):
    match = re.search(r"(?im)^(?:[-*]\s*)?(?:\*\*)?Status(?:\*\*)?\s*:\s*(.+?)\s*$", text or "")
    if not match:
        return None
    return re.sub(r"\*+", "", match.group(1)).strip()


def status_kind(status):
    if status is None:
        return None
    if re.match(r"(?i)^proposed$", status):
        return "proposed"
    if re.match(r"(?i)^accepted(?:\s*\(inherited\))?$", status):
        return "accepted"
    if re.match(r"(?i)^superseded by\s+\S", status):
        return "superseded"
    return "invalid"


def sections(text):
    out, name, buf = {}, None, []
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            if name is not None:
                out[name] = "\n".join(buf)
            name, buf = match.group(1).lower(), []
        elif name is not None:
            buf.append(line)
    if name is not None:
        out[name] = "\n".join(buf)
    return out


def alternative_count(text):
    body = ""
    for name, part in sections(text).items():
        if "alternatives" in name:
            body = part
            break
    count = 0
    for ln in body.splitlines():
        if not re.match(r"^\s*[-*]\s+\S", ln) or "TEMPLATE" in ln:
            continue
        no_comment = re.sub(r"<!--.*?-->", "", ln).strip(" -*").strip()
        if no_comment and not no_comment.startswith("<"):
            count += 1
    return count


def norm_lines(text):
    lines = [ln.rstrip() for ln in (text or "").splitlines()]
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def norm_body(text):
    kept = []
    for ln in norm_lines(text):
        if re.search(r"(?i)^(?:[-*]\s*)?(?:\*\*)?Status(?:\*\*)?\s*:", ln.strip()):
            continue
        kept.append(ln)
    return kept


def git_ok():
    proc = subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], capture_output=True)
    return proc.returncode == 0


def git_revs(path):
    if not git_ok():
        return []
    proc = subprocess.run(
        ["git", "log", "--reverse", "--format=%H", "--", path],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return []
    return [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]


def git_show(rev, path):
    proc = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", "replace")


def history(path):
    blobs = []
    for rev in git_revs(path):
        text = git_show(rev, path)
        if text is not None:
            blobs.append(text)
    return blobs


def is_inherited(path):
    return os.path.basename(path) == "0000-inherited-decisions.md"


def resolve_successor(status, current):
    match = re.match(r"(?i)^superseded by\s+(.+)$", status.strip())
    if not match:
        return None, "status is not a supersession"
    ref = match.group(1).strip().strip("`").rstrip(".")
    if "/" in ref or ref.endswith(".md"):
        if os.path.isfile(ref) and os.path.abspath(ref) != os.path.abspath(current):
            return ref, None
        return None, f"successor not found: {ref}"
    token = re.sub(r"(?i)^ADR[-\s]+", "", ref).strip()
    num = re.match(r"(\d+)", token)
    if not num:
        return None, f"successor is not an ADR number or path: {ref}"
    pat = re.compile(rf"(?i)^(?:ADR-)?0*{int(num.group(1))}(?:-|\.|$)")
    found = []
    for name in sorted(os.listdir(adr_dir)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(adr_dir, name)
        if os.path.abspath(path) == os.path.abspath(current):
            continue
        if pat.match(name[:-3]):
            found.append(path)
    if len(found) == 1:
        return found[0], None
    if len(found) > 1:
        return None, "successor matches more than one ADR: " + ", ".join(found)
    return None, f"no ADR file matches {ref}"


def check_successor(path, status):
    """The direct successor may itself be superseded. The chain must end Accepted."""
    successor, err = resolve_successor(status, path)
    if err:
        fail(f"{path}: {err}")
        return
    seen = {os.path.abspath(path)}
    hop = successor
    for _ in range(20):
        abspath = os.path.abspath(hop)
        if abspath in seen:
            fail(f"{path}: supersession cycle at {hop}")
            return
        seen.add(abspath)
        hop_text = read(hop)
        kind = status_kind(adr_status(hop_text))
        if kind == "accepted":
            return
        if kind != "superseded":
            shown = adr_status(hop_text) or "missing"
            fail(f"{hop}: successor chain from {path} must end at an Accepted ADR (got {shown})")
            return
        nxt, nxt_err = resolve_successor(adr_status(hop_text), hop)
        if nxt_err:
            fail(f"{hop}: {nxt_err}")
            return
        hop = nxt
    fail(f"{path}: supersession chain does not end")


def check_immutable(path, current):
    blobs = history(path)
    if is_inherited(path):
        start = next((i for i, blob in enumerate(blobs) if "Accepted (inherited)" in blob), None)
        if start is None:
            return
        base = norm_lines(blobs[start])
        for blob in blobs[start:]:
            if norm_lines(blob) != base:
                fail(f"{path}: inherited decisions changed after they were accepted; write a new ADR")
                return
        if norm_lines(current) != base:
            fail(f"{path}: inherited decisions changed after they were accepted; write a new ADR")
        return
    start = next((i for i, blob in enumerate(blobs) if status_kind(adr_status(blob)) == "accepted"), None)
    if start is None:
        return
    base_body = norm_body(blobs[start])
    later = [(f"history of {path}", blob) for blob in blobs[start:]]
    later.append((path, current))
    for label, blob in later:
        kind = status_kind(adr_status(blob))
        if kind not in ("accepted", "superseded") or norm_body(blob) != base_body:
            fail(f"{label}: accepted decision was rewritten; set Status to "
                 "\"Superseded by ADR <NN>\" and write the new decision in the next file")
            return


def check_file(path, text):
    if is_inherited(path):
        if "Accepted (inherited)" not in text:
            fail(f"{path}: inherited decisions keep the status Accepted (inherited)")
        check_immutable(path, text)
        return
    status = adr_status(text)
    kind = status_kind(status)
    if kind is None:
        fail(f"{path}: missing Status (Proposed, Accepted, or Superseded by ADR <NN>)")
    elif kind == "invalid":
        fail(f"{path}: Status must be Proposed, Accepted, or Superseded by ADR <NN> (got {status})")
    if alternative_count(text) < 2:
        fail(f"{path}: needs at least two alternatives considered")
    if kind == "superseded":
        check_successor(path, status)
    check_immutable(path, text)


if not os.path.isdir(adr_dir):
    print("OK: no docs/agents-v0/adr directory")
    raise SystemExit(0)

for name in sorted(os.listdir(adr_dir)):
    if not name.endswith(".md") or name.startswith("_"):
        continue
    path = os.path.join(adr_dir, name)
    text = read(path)
    if text is None:
        fail(f"{path}: unreadable")
        continue
    check_file(path, text)

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print("OK: ADR records")
PY
