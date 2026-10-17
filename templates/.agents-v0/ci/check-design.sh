#!/bin/sh
# check-design.sh — a Standard-tier design is complete, traceable, and pinned after approval.
#
# Usage:
#   sh .agents-v0/ci/check-design.sh <feature>                  structure and traceability
#   sh .agents-v0/ci/check-design.sh <feature> --hash           print the hash of the design files
#   sh .agents-v0/ci/check-design.sh <feature> --pin "<why>"    check, then append "date hash why" to design.lock
#   sh .agents-v0/ci/check-design.sh <feature> --verify-lock    the files still match the last pin
#
# Files: docs/agents-v0/design/<feature>/design.md (from docs/agents-v0/design/_design.template.md), the contract draft
# (openapi.yaml), asyncapi.yaml, events/, ux-spec.md, mockups/, amendments.md, design.lock; the requirements
# artifact docs/agents-v0/requirements/<feature>.md; the ADR named on the "ADR:" line of design.md.
#
# Structure checks: design.md has the sections Traceability, Data model, Authorization, Failure
# modes, Observability, and Rollout, each with content or "N/A: <reason>"; no TEMPLATE: line is
# left; every AC-n of the requirements artifact appears in Traceability; every operationId of the
# draft appears in Authorization; the "ADR:" line names an existing ADR with at least two
# alternatives (or says "N/A: <reason>"). That ADR has Status Proposed or Accepted. A pin requires
# Accepted. Citing a superseded ADR fails: point at the successor. Every AC whose requirements block
# says Kind: negative or Kind: edge is named in Failure modes.
# Lock: the pin is the design as the person approved it, including the cited ADR. After that, a
# change to the design or that ADR is an amendment: run design-reviewer so review.md names the new
# hash and has no open Critical, then docs/agents-v0/design/<feature>/amendments.md needs an Approved
# row naming the first 12 characters of that hash, then a new pin line. A changed decision supersedes
# the ADR (ci/check-adr.sh) instead of rewriting it. Pin only after that review and the person's approval.

set -eu

feature="${1:-}"
action="${2:-check}"
reason="${3:-}"
if [ -z "$feature" ]; then
  printf 'usage: %s <feature> [--hash | --pin "<why>" | --verify-lock]\n' "$0" >&2
  exit 1
fi
case "$action" in
  check | --hash | --pin | --verify-lock) ;;
  *) printf 'FAIL: unknown option %s\n' "$action" >&2; exit 1 ;;
esac
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

FEATURE="$feature" ACTION="$action" REASON="$reason" python3 - <<'PY'
import datetime
import glob
import hashlib
import os
import re
import sys

feature, action, reason = os.environ["FEATURE"], os.environ["ACTION"], os.environ["REASON"]
base = os.path.join("docs", "agents-v0", "design", feature)
failures = []


def fail(msg):
    failures.append(msg)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def named_adr(body):
    if not body:
        return None
    match = re.search(r"^ADR:\s*(.+)$", body, re.M)
    if not match:
        return None
    ref = match.group(1).strip().strip("`")
    if re.match(r"^N/A\b", ref):
        return None
    return ref


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


def design_files():
    out = []
    for name in ("design.md", "openapi.yaml", "openapi.yml", "openapi.json", "asyncapi.yaml", "asyncapi.yml", "asyncapi.json", "ux-spec.md"):
        if os.path.isfile(os.path.join(base, name)):
            out.append(os.path.join(base, name))
    for sub in ("events", "mockups"):
        for dirpath, _dirs, names in os.walk(os.path.join(base, sub)):
            out += [os.path.join(dirpath, n) for n in names]
    adr = named_adr(read(os.path.join(base, "design.md")))
    if adr and os.path.isfile(adr):
        out.append(adr)
    return sorted(set(out))


def require_accepted_adr():
    """A pin is an accepted decision. Proposed stays unpinned; superseded must not stay cited."""
    adr = named_adr(read(os.path.join(base, "design.md")))
    if not adr:
        return
    text = read(adr)
    if text is None:
        fail(f"{adr}: cited ADR is missing")
        return
    kind = status_kind(adr_status(text))
    if kind != "accepted":
        shown = adr_status(text) or "missing"
        fail(f"{adr}: an approved design cites an ADR whose status is {shown}; "
             "set Status to Accepted before the pin, or supersede it and cite the successor")


def current_hash():
    digest = hashlib.sha256()
    for path in design_files():
        digest.update(path.replace(os.sep, "/").encode() + b"\0")
        with open(path, "rb") as handle:
            digest.update(handle.read() + b"\0")
    return digest.hexdigest()


def sections(text):
    """Map lower-cased '## heading' to its body text."""
    out, name, buf = {}, None, []
    for line in text.splitlines():
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


def review_not_required(body):
    """A design with no API, no AsyncAPI/events, no UI, and no public route can be pinned without design-reviewer."""
    if not body or "N/A: no /api/v1 operation" not in body:
        return False
    if os.path.isfile(os.path.join(base, "ux-spec.md")):
        return False
    for name in ("openapi.yaml", "openapi.yml", "openapi.json", "asyncapi.yaml", "asyncapi.yml", "asyncapi.json"):
        if os.path.isfile(os.path.join(base, name)):
            return False
    for _dirpath, _dirs, names in os.walk(os.path.join(base, "events")):
        if names:
            return False
    # A health, readiness, or liveness route is the skeleton's proof, not a product API.
    kept = re.sub(
        r"(?i)[^\n]*permitAll[^\n]*(health|ready|live)[^\n]*|[^\n]*(health|ready|live)[^\n]*permitAll[^\n]*",
        "",
        body,
    )
    if re.search(r"permitAll|public route", kept, re.I):
        return False
    return True


def has_content(body):
    text = re.sub(r"<!--.*?-->", "", body or "", flags=re.S)
    text = "\n".join(l for l in text.splitlines() if l.strip() and not re.match(r"^\s*\|[-:| ]+\|\s*$", l))
    if re.search(r"\bN/A\b\s*[:\-—]\s*\S{4,}", text):
        return True
    return len(text.strip()) >= 20


def check():
    path = os.path.join(base, "design.md")
    body = read(path)
    if body is None:
        fail(f"{path} is missing (copy docs/agents-v0/design/_design.template.md)")
        return
    if "TEMPLATE:" in body:
        fail(f"{path}: a TEMPLATE: line is still present")
    secs = sections(body)
    for key, label in (("traceability", "Traceability"), ("data model", "Data model"), ("authorization", "Authorization"),
                       ("failure modes", "Failure modes"), ("observability", "Observability"), ("rollout", "Rollout")):
        part = section(secs, key)
        if part is None:
            fail(f"{path}: section '{label}' is missing")
        elif not has_content(part):
            fail(f"{path}: section '{label}' is empty (write it, or \"N/A: <reason>\")")
    requirements = read(os.path.join("docs", "agents-v0", "requirements", f"{feature}.md"))
    trace = section(secs, "traceability") or ""
    if requirements is None:
        fail(f"docs/agents-v0/requirements/{feature}.md not found (needed for AC traceability)")
    else:
        for ac in sorted(set(re.findall(r"\bAC-\d+\b", requirements)), key=lambda s: int(s[3:])):
            if not re.search(r"\b%s\b" % re.escape(ac), trace):
                fail(f"{path}: {ac} is not in Traceability")
        failure = section(secs, "failure modes") or ""
        for block in re.split(r"(?m)^###\s+", requirements)[1:]:
            heading = re.match(r"(AC-\d+)\b", block)
            kind = re.search(r"(?mi)^Kind:\s*(negative|edge)\s*$", block)
            if heading and kind and not re.search(r"\b%s\b" % re.escape(heading.group(1)), failure):
                fail(f"{path}: {heading.group(1)} ({kind.group(1).lower()}) is not in Failure modes")
    draft = next((p for p in (os.path.join(base, n) for n in ("openapi.yaml", "openapi.yml", "openapi.json")) if os.path.isfile(p)), None)
    if draft:
        ids = re.findall(r"""["']?operationId["']?\s*:\s*["']?([\w.\-]+)""", read(draft) or "")
        authz = section(secs, "authorization") or ""
        for op_id in ids:
            if not re.search(r"(?<![\w.\-])%s(?![\w.\-])" % re.escape(op_id), authz):
                fail(f"{path}: operationId {op_id} is not in Authorization")
    m = re.search(r"^ADR:\s*(.+)$", body, re.M)
    if not m:
        fail(f"{path}: no 'ADR:' line (name the ADR, or \"ADR: N/A: <reason>\")")
    elif not re.match(r"^N/A\b", m.group(1).strip()):
        adr = m.group(1).strip().strip("`")
        text = read(adr)
        if text is None:
            fail(f"{path}: ADR not found: {adr}")
        else:
            kind = status_kind(adr_status(text))
            if kind is None:
                fail(f"{adr}: missing Status (Proposed, Accepted, or Superseded by ADR <NN>)")
            elif kind == "invalid":
                fail(f"{adr}: Status must be Proposed, Accepted, or Superseded by ADR <NN> (got {adr_status(text)})")
            elif kind == "superseded":
                fail(f"{adr}: design cites a superseded ADR; cite the successor named by its Status")
            else:
                alt = section(sections(text), "alternatives") or ""
                items = [l for l in alt.splitlines() if re.match(r"^\s*[-*]\s+\S", l) and "TEMPLATE" not in l]
                if len(items) < 2:
                    fail(f"{adr}: needs at least two alternatives considered")


lock_path = os.path.join(base, "design.lock")


def lock_lines():
    text = read(lock_path)
    return [l for l in (text or "").splitlines() if l.strip()]


def verify_lock():
    lines = lock_lines()
    if not lines:
        fail(f"{lock_path} is missing: pin the approved design (sh .agents-v0/ci/check-design.sh {feature} --pin \"approved\")")
        return
    now = current_hash()
    last = lines[-1].split()
    if len(last) < 2 or last[1] != now:
        fail(f"the design changed since the last pin ({last[1][:12] if len(last) > 1 else '?'} -> {now[:12]}): "
             f"run design-reviewer so {base}/review.md names {now[:12]} and has no open Critical, "
             f"add an Approved row in {base}/amendments.md, then pin")
    amendments = read(os.path.join(base, "amendments.md")) or ""
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        short = parts[1][:12]
        rows = [r for r in amendments.splitlines() if short in r]
        if not any(re.search(r"\|\s*approved\b", r, re.I) for r in rows):
            fail(f"pin {short} has no Approved row in {base}/amendments.md")


if not os.path.isdir(base):
    print(f"FAIL: {base} not found", file=sys.stderr)
    raise SystemExit(1)

if action == "--hash":
    print(current_hash())
    raise SystemExit(0)
if action == "--verify-lock":
    verify_lock()
    require_accepted_adr()
elif action == "--pin":
    check()
    require_accepted_adr()
    review = read(os.path.join(base, "review.md"))
    if review is None:
        if not review_not_required(read(os.path.join(base, "design.md"))):
            fail(f"{base}/review.md is missing: run design-reviewer before the design is approved")
    else:
        m = re.search(r"^design-hash:\s*([0-9a-f]{12})", review, re.M)
        if not m or not current_hash().startswith(m.group(1)):
            fail(f"{base}/review.md reviewed a different version of the design (design-hash {m.group(1) if m else '?'}, now {current_hash()[:12]}): run design-reviewer again")
        for line in review.splitlines():
            if re.search(r"\|\s*Critical\s*\|", line, re.I) and not re.search(r"\bResolved\b", line, re.I):
                fail(f"{base}/review.md has an unresolved Critical finding: {line.strip()[:100]}")
    if not failures:
        why = reason.strip() or ("approved" if not lock_lines() else "")
        if not why:
            fail("--pin needs a reason (the amendment id)")
        else:
            with open(lock_path, "a", encoding="utf-8") as handle:
                handle.write(f"{datetime.date.today().isoformat()} {current_hash()} {why}\n")
            print(f"pinned {current_hash()[:12]} in {lock_path}")
else:
    check()

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: design {action.lstrip('-') if action != 'check' else 'check'} for {feature}")
PY
