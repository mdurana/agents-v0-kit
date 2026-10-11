#!/bin/sh
# sync-feature-state.sh — derive docs/agents-v0/requirements/<feature>.state.json from the feature artifact.
#
# Usage:
#   sh .agents-v0/scripts/sync-feature-state.sh <docs/agents-v0/requirements/feature.md>
#   sh .agents-v0/scripts/sync-feature-state.sh --active-phase <phase> --status <status> [--reason <text>] <artifact>
#   sh .agents-v0/scripts/sync-feature-state.sh --clear-active <artifact>
#
# Without flags, lastApprovedPhase is derived from Approved rows. An in_progress or
# blocked active phase is kept. awaiting_approval is cleared once that phase is Approved.
# With flags, set the phase in flight. Status is in_progress, awaiting_approval, or blocked.
# blocked requires --reason. --clear-active drops the phase in flight. Decision Local is
# not an Approved token, so lastApprovedPhase stays on the previous Approved phase.
# This script never writes an approval.
# Other artifacts: docs/agents-v0/onboarding/report.md keeps docs/agents-v0/onboarding/state.json (phase "onboard");
# docs/agents-v0/maintain/<id>/note.md keeps docs/agents-v0/maintain/<id>/state.json (phases "maintain", "verify").

set -eu

art=""
active_phase=""
active_status=""
reason=""
set_active=0
clear_active=0

usage() {
  printf 'usage: %s [--active-phase PHASE --status STATUS] [--reason TEXT] <requirements-artifact>\n' "$0" >&2
  printf '       %s --clear-active <requirements-artifact>\n' "$0" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --active-phase)
      [ $# -ge 2 ] || usage
      active_phase="$2"
      set_active=1
      shift 2
      ;;
    --status)
      [ $# -ge 2 ] || usage
      active_status="$2"
      set_active=1
      shift 2
      ;;
    --reason)
      [ $# -ge 2 ] || usage
      reason="$2"
      shift 2
      ;;
    --clear-active)
      clear_active=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      [ -z "$art" ] || usage
      art="$1"
      shift
      ;;
  esac
done

[ -n "$art" ] && [ -f "$art" ] || usage
if [ "$set_active" = 1 ] && [ "$clear_active" = 1 ]; then
  usage
fi
if [ "$set_active" = 1 ]; then
  [ -n "$active_phase" ] && [ -n "$active_status" ] || usage
fi

slug="$(basename "$art" .md)"
state="docs/agents-v0/requirements/${slug}.state.json"
# /v0-onboard keeps its own state beside its report: docs/agents-v0/onboarding/state.json (phase "onboard").
# A maintenance note keeps its state beside it: docs/agents-v0/maintain/<id>/state.json (phases "maintain", "verify").
case "$art" in
  docs/agents-v0/onboarding/* | */docs/agents-v0/onboarding/*) state="docs/agents-v0/onboarding/state.json" ;;
  docs/agents-v0/maintain/* | */docs/agents-v0/maintain/*) state="$(dirname "$art")/state.json" ;;
esac
base_commit=""
if command -v git >/dev/null 2>&1; then
  base_commit="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
fi

HOOK_STATE_JSON="$state" \
HOOK_ART="$art" \
HOOK_SLUG="$slug" \
HOOK_BASE="$base_commit" \
HOOK_SET_ACTIVE="$set_active" \
HOOK_CLEAR_ACTIVE="$clear_active" \
HOOK_ACTIVE_PHASE="$active_phase" \
HOOK_ACTIVE_STATUS="$active_status" \
HOOK_BLOCKED_REASON="$reason" \
python3 - <<'PY'
import json
import os
import re
import sys
import time

art = os.environ["HOOK_ART"]
out = os.environ["HOOK_STATE_JSON"]
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
statuses = {"in_progress", "awaiting_approval", "blocked"}
# A conditional approval is not an approval; the last row for a phase is its current decision.
positive = re.compile(
    r"^(approved|approve|yes|pass)\b(?!.*\b(?:conditions?|conditional|provisional|pending|subject to)\b)", re.I
)

text = open(art, encoding="utf-8").read()
tier_m = re.search(r"^\s*tier:\s*(\S+)", text, re.I | re.M)
tier = tier_m.group(1).lower() if tier_m else "standard"

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

last_approved = ""
for phase in phases:
    if phase in rows and positive.match(rows[phase][3]):
        last_approved = phase


def evidence(phase):
    if phase not in rows:
        return []
    found = re.findall(r"docs/[A-Za-z0-9_./<>-]+", rows[phase][1].replace("`", ""))
    return sorted({item.rstrip(".,;") for item in found if "<" not in item})


prev = {}
if os.path.isfile(out):
    try:
        prev = json.load(open(out, encoding="utf-8"))
    except ValueError:
        prev = {}

if os.environ.get("HOOK_CLEAR_ACTIVE") == "1":
    active_phase = ""
    active_status = ""
    blocked_reason = ""
elif os.environ.get("HOOK_SET_ACTIVE") == "1":
    active_phase = os.environ.get("HOOK_ACTIVE_PHASE", "")
    active_status = os.environ.get("HOOK_ACTIVE_STATUS", "")
    blocked_reason = os.environ.get("HOOK_BLOCKED_REASON", "")
    if active_phase not in active_phases:
        print(f"FAIL: active phase must be one of {', '.join(active_phases)}", file=sys.stderr)
        raise SystemExit(1)
    if active_status not in statuses:
        print(f"FAIL: status must be one of {', '.join(sorted(statuses))}", file=sys.stderr)
        raise SystemExit(1)
    if active_status == "blocked" and not blocked_reason.strip():
        print("FAIL: --reason is required when status is blocked", file=sys.stderr)
        raise SystemExit(1)
    if active_status != "blocked":
        blocked_reason = ""
else:
    active_phase = prev.get("activePhase") or ""
    active_status = prev.get("activeStatus") or ""
    blocked_reason = prev.get("blockedReason") or ""
    if active_phase and active_phase == last_approved:
        active_phase = ""
        active_status = ""
        blocked_reason = ""

data = {
    "feature": ("onboarding" if onboarding
                else os.path.basename(os.path.dirname(rel_art)) if maintain_note
                else os.environ.get("HOOK_SLUG", "")),
    "tier": tier,
    "lastApprovedPhase": last_approved,
    "activePhase": active_phase,
    "activeStatus": active_status,
    "blockedReason": blocked_reason,
    "artifact": art,
    "baseCommit": os.environ.get("HOOK_BASE", ""),
    "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "evidence": {
        "build": evidence("build") or prev.get("evidence", {}).get("build", []),
        "verify": evidence("verify") or prev.get("evidence", {}).get("verify", []),
    },
}
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
print(
    f"Wrote {out} (lastApproved={last_approved or '-'} "
    f"active={active_phase or '-'} status={active_status or '-'} tier={tier})"
)
PY
