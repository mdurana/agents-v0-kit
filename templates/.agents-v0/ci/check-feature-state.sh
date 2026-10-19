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
case "$art" in
  docs/agents-v0/onboarding/* | */docs/agents-v0/onboarding/*) state="docs/agents-v0/onboarding/state.json" ;;
  docs/agents-v0/maintain/* | */docs/agents-v0/maintain/*) state="$(dirname "$art")/state.json" ;;
esac
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
rel_art = art.replace("\\", "/")
onboarding = "docs/agents-v0/onboarding/" in rel_art
maintain_note = "docs/agents-v0/maintain/" in rel_art
if onboarding:
    phases = ["onboard"]
elif maintain_note:
    phases = ["maintain", "verify"]
else:
    phases = ["intake", "design", "build", "verify", "release"]
active_phases = phases if (onboarding or maintain_note) else phases + ["maintain"]
statuses = {"", "in_progress", "awaiting_approval", "blocked"}
positive = re.compile(
    r"^(approved|approve|yes|pass)\b(?!.*\b(?:conditions?|conditional|provisional|pending|subject to)\b)", re.I
)
reopened_re = re.compile(r"^re-?opened\b", re.I)


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
first_reopened = ""
for phase in phases:
    if phase in rows:
        if reopened_re.match(rows[phase][3]):
            first_reopened = phase
            break
        if positive.match(rows[phase][3]):
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
if active and active not in active_phases:
    print(f"FAIL: activePhase {active} is not a lifecycle phase", file=sys.stderr)
    raise SystemExit(1)
if status not in statuses:
    print(f"FAIL: activeStatus {status} is not in_progress, awaiting_approval, or blocked", file=sys.stderr)
    raise SystemExit(1)
if status == "blocked" and not (state.get("blockedReason") or "").strip():
    print("FAIL: blocked status has no blockedReason", file=sys.stderr)
    raise SystemExit(1)
if first_reopened and active in phases and phases.index(active) > phases.index(first_reopened):
    print(
        f"FAIL: activePhase {active} is downstream of Re-opened phase {first_reopened}; re-run scripts/sync-feature-state.sh",
        file=sys.stderr,
    )
    raise SystemExit(1)

if not onboarding and not maintain_note and last in ("build", "verify", "release") and not first_reopened:
    slug = os.path.splitext(os.path.basename(art))[0]
    art_root = os.path.dirname(os.path.dirname(os.path.abspath(art)))
    design_lock = os.path.join(art_root, "design", slug, "design.lock")
    is_p0_a = bool(re.search(r"^\s*Story:\s*P0-A\b", text, re.I | re.M))
    if os.path.isfile(design_lock) or is_p0_a:
        for prior in phases[: phases.index(last)]:
            if prior not in rows or not positive.match(rows[prior][3]):
                print(
                    f"FAIL: {last} is Approved in {art} while earlier phase '{prior}' has no Approved row in Delivery approvals",
                    file=sys.stderr,
                )
                raise SystemExit(1)

if onboarding or maintain_note:
    phase_result_path = os.path.join(os.path.dirname(art), "phase-result.md")
else:
    phase_result_path = os.path.splitext(art)[0] + ".phase-result.md"
if os.path.isfile(phase_result_path):
    pr_text = open(phase_result_path, encoding="utf-8").read()
    m_phase = re.search(r"^\s*phase:\s*(\S+)", pr_text, re.I | re.M)
    m_status = re.search(r"^\s*status:\s*(\S+)", pr_text, re.I | re.M)
    pr_phase = m_phase.group(1).strip().lower() if m_phase else ""
    pr_status = m_status.group(1).strip().lower() if m_status else ""
    if pr_status == "approved":
        if pr_phase not in rows or not positive.match(rows[pr_phase][3]):
            print(
                f"FAIL: {phase_result_path} has status: approved for phase '{pr_phase}', but {art} has no Approved '{pr_phase}' row",
                file=sys.stderr,
            )
            raise SystemExit(1)
        if pr_phase == last and active:
            print(
                f"FAIL: {phase_result_path} records phase '{pr_phase}' as approved while {state_path} has activePhase '{active}' ({status or '-'}) — story is in two phases at once; run scripts/sync-feature-state.sh {art} without --active-phase",
                file=sys.stderr,
            )
            raise SystemExit(1)
    elif pr_status in ("in_progress", "awaiting_approval", "blocked") and pr_phase:
        if active != pr_phase or status != pr_status:
            print(
                f"FAIL: {phase_result_path} ({pr_phase} / {pr_status}) disagrees with {state_path} ({active or '-'} / {status or '-'})",
                file=sys.stderr,
            )
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
