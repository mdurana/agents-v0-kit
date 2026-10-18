#!/bin/sh
# check-feature-state.sh — optional consistency check between artifact and .state.json.
#
# Usage: sh .agents-v0/ci/check-feature-state.sh <docs/agents-v0/requirements/feature.md>
# Exit 0 when state missing (optional) or in sync; 1 when drift detected.

set -eu

art="${1:-}"
[ -f "$art" ] || { printf 'FAIL: artifact not found: %s\n' "$art" >&2; exit 1; }
slug="$(basename "$art" .md)"
state="docs/agents-v0/requirements/${slug}.state.json"
[ -f "$state" ] || { printf 'OK: no state file (optional): %s\n' "$state"; exit 0; }

base_commit=""
if command -v git >/dev/null 2>&1; then
  base_commit="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
fi

HOOK_ART="$art" HOOK_STATE="$state" HOOK_BASE="$base_commit" python3 - <<'PY'
import json
import os
import re
import sys

art = os.environ["HOOK_ART"]
state_path = os.environ["HOOK_STATE"]
phases = ["intake", "design", "build", "verify", "release"]
statuses = {"", "in_progress", "awaiting_approval", "blocked"}
positive = re.compile(
    r"^(approved|approve|yes|pass)\b(?!.*\b(?:conditions?|conditional|provisional|pending|subject to)\b)", re.I
)


def resolve_git_head(seed: str) -> str:
    if seed and re.match(r"^[0-9a-f]{7,40}$", seed, re.I):
        return seed
    cur = os.path.abspath(".")
    while True:
        dot_git = os.path.join(cur, ".git")
        git_dir = ""
        if os.path.isdir(dot_git):
            git_dir = dot_git
        elif os.path.isfile(dot_git):
            try:
                raw = open(dot_git, encoding="utf-8").read().strip()
                if raw.startswith("gitdir:"):
                    rel = raw.split(":", 1)[1].strip()
                    git_dir = rel if os.path.isabs(rel) else os.path.normpath(os.path.join(cur, rel))
            except OSError:
                git_dir = ""
        if git_dir and os.path.isfile(os.path.join(git_dir, "HEAD")):
            try:
                head = open(os.path.join(git_dir, "HEAD"), encoding="utf-8").read().strip()
                if re.match(r"^[0-9a-f]{40}$", head, re.I):
                    return head
                if head.startswith("ref:"):
                    ref = head.split(":", 1)[1].strip()
                    for base in (git_dir, os.path.dirname(os.path.dirname(git_dir))):
                        ref_file = os.path.join(base, ref)
                        if os.path.isfile(ref_file):
                            sha = open(ref_file, encoding="utf-8").read().strip()
                            if re.match(r"^[0-9a-f]{40}$", sha, re.I):
                                return sha
                        packed = os.path.join(base, "packed-refs")
                        if os.path.isfile(packed):
                            for pline in open(packed, encoding="utf-8").read().splitlines():
                                parts = pline.strip().split()
                                if len(parts) == 2 and parts[1] == ref and re.match(r"^[0-9a-f]{40}$", parts[0], re.I):
                                    return parts[0]
            except OSError:
                pass
            return ""
        parent = os.path.dirname(cur)
        if parent == cur:
            return ""
        cur = parent


try:
    state = json.load(open(state_path, encoding="utf-8"))
except ValueError:
    print(f"FAIL: state file is not JSON: {state_path}", file=sys.stderr)
    raise SystemExit(1)

if state.get("artifact") != art:
    print(f"FAIL: state artifact path {state.get('artifact', '')} != {art}", file=sys.stderr)
    raise SystemExit(1)

if "lastApprovedPhase" not in state and "currentPhase" in state:
    print(f"OK: legacy currentPhase in {state_path}; re-run scripts/sync-feature-state.sh")
    raise SystemExit(0)

text = open(art, encoding="utf-8").read()
rows, inside = {}, False
for line in text.splitlines():
    if re.match(r"^#+\s*delivery approvals", line, re.I):
        inside = True
        continue
    if inside and re.match(r"^#+\s", line):
        break
    if not inside or not line.strip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) >= 5 and cells[0].lower() in phases:
        rows[cells[0].lower()] = cells

last = ""
for phase in phases:
    if phase in rows and positive.match(rows[phase][3]):
        last = phase

recorded = state.get("lastApprovedPhase") or ""
if recorded != last:
    print(
        f"FAIL: lastApprovedPhase {recorded or '-'} != approvals {last or '-'}",
        file=sys.stderr,
    )
    raise SystemExit(1)

active = state.get("activePhase") or ""
status = state.get("activeStatus") or ""
if active and active not in phases + ["maintain"]:
    print(f"FAIL: activePhase {active} is not a lifecycle phase", file=sys.stderr)
    raise SystemExit(1)
if status not in statuses:
    print(f"FAIL: activeStatus {status} is not in_progress, awaiting_approval, or blocked", file=sys.stderr)
    raise SystemExit(1)
if status == "blocked" and not (state.get("blockedReason") or "").strip():
    print("FAIL: blocked status has no blockedReason", file=sys.stderr)
    raise SystemExit(1)

head_sha = resolve_git_head(os.environ.get("HOOK_BASE", ""))
base_commit = (state.get("baseCommit") or "").strip()
if base_commit and not re.match(r"^[0-9a-f]{7,40}$", base_commit, re.I):
    print(f"FAIL: baseCommit {base_commit} is not a commit SHA in {state_path}", file=sys.stderr)
    raise SystemExit(1)
if head_sha and not base_commit:
    print(f"FAIL: baseCommit is empty in {state_path}; re-run scripts/sync-feature-state.sh", file=sys.stderr)
    raise SystemExit(1)

print(f"OK: state file matches artifact {art} (lastApproved={last or '-'} active={active or '-'} status={status or '-'})")
PY
