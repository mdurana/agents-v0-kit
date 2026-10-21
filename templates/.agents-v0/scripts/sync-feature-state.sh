#!/bin/sh
# sync-feature-state.sh — manage structured JSON workflow state (<feature>.state.json,
# maintain/<id>/state.json, onboarding/state.json, or program.state.json).
#
# Usage:
#   sh .agents-v0/scripts/sync-feature-state.sh <artifact>
#   sh .agents-v0/scripts/sync-feature-state.sh --approve <phase> <artifact>
#   sh .agents-v0/scripts/sync-feature-state.sh --reopen <phase> <artifact>
#   sh .agents-v0/scripts/sync-feature-state.sh --verify-passed <true|false> <artifact>
#   sh .agents-v0/scripts/sync-feature-state.sh --active-phase <phase> --status <status> [--reason <text>] <artifact>
#   sh .agents-v0/scripts/sync-feature-state.sh --clear-active <artifact>

set -eu

art=""
active_phase=""
active_status=""
reason=""
approve_phase=""
reopen_phase=""
verify_passed=""
set_active=0
clear_active=0

usage() {
  printf 'usage: %s [--approve PHASE | --reopen PHASE | --verify-passed true|false] [--active-phase PHASE --status STATUS] [--reason TEXT] <artifact>\n' "$0" >&2
  printf '       %s --clear-active <artifact>\n' "$0" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --approve)
      [ $# -ge 2 ] || usage
      approve_phase="$2"
      shift 2
      ;;
    --reopen)
      [ $# -ge 2 ] || usage
      reopen_phase="$2"
      shift 2
      ;;
    --verify-passed)
      [ $# -ge 2 ] || usage
      verify_passed="$2"
      shift 2
      ;;
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
case "$art" in
  docs/agents-v0/onboarding/* | */docs/agents-v0/onboarding/*)
    state="docs/agents-v0/onboarding/state.json"
    ;;
  docs/agents-v0/maintain/* | */docs/agents-v0/maintain/*)
    state="$(dirname "$art")/state.json"
    ;;
  docs/agents-v0/roadmap/* | */docs/agents-v0/roadmap/* | docs/agents-v0/architecture.md | */docs/agents-v0/architecture.md | docs/agents-v0/milestones/* | */docs/agents-v0/milestones/*)
    state="docs/agents-v0/program.state.json"
    ;;
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
HOOK_APPROVE_PHASE="$approve_phase" \
HOOK_REOPEN_PHASE="$reopen_phase" \
HOOK_VERIFY_PASSED="$verify_passed" \
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

art = os.environ["HOOK_ART"]
out = os.environ["HOOK_STATE_JSON"]
rel_art = art.replace("\\", "/")
onboarding = "docs/agents-v0/onboarding/" in rel_art
maintain_note = "docs/agents-v0/maintain/" in rel_art
program_doc = out.endswith("program.state.json")

if onboarding:
    phases = ["onboard"]
elif maintain_note:
    phases = ["maintain", "verify", "release"]
elif program_doc:
    phases = ["roadmap", "architecture", "plan"]
else:
    phases = ["intake", "design", "build", "verify", "release"]

active_phases = phases if (onboarding or maintain_note or program_doc) else phases + ["maintain"]
statuses = {"in_progress", "awaiting_approval", "blocked"}
positive = re.compile(
    r"^\s*(approved|approve|yes|pass)\b(?!.*\b(?:conditions?|conditional|provisional|pending|subject to)\b)",
    re.I,
)
reopened_re = re.compile(r"^\s*re-?opened\b", re.I)

raw_text = open(art, encoding="utf-8").read()
clean_text = re.sub(r"<!--.*?-->", "", raw_text, flags=re.S)
tier_m = re.search(r"^\s*tier:\s*(\S+)", clean_text, re.I | re.M)
tier = tier_m.group(1).lower() if tier_m else "standard"

prev = {}
if os.path.isfile(out):
    try:
        prev = json.load(open(out, encoding="utf-8"))
    except ValueError:
        prev = {}

rows, inside = {}, False
reopen_rows = 0
for line in clean_text.splitlines():
    if re.match(r"^#+\s*delivery approvals", line, re.I):
        inside = True
        continue
    if inside and re.match(r"^#+\s+\S", line):
        break
    if not inside or not line.strip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) >= 5 and cells[0].lower() in phases:
        p_key = cells[0].lower()
        if reopened_re.match(cells[3]):
            reopen_rows += 1
        rows[p_key] = cells

approved_list = [p for p in (prev.get("approvedPhases") or []) if p in phases]
prev_last = (prev.get("lastApprovedPhase") or "").lower()
if prev_last in phases and prev_last not in approved_list:
    for p in phases[: phases.index(prev_last) + 1]:
        if p not in approved_list:
            approved_list.append(p)

today_iso = time.strftime("%Y-%m-%d", time.gmtime())
phase_dates = {k.lower(): v for k, v in (prev.get("phaseDates") or {}).items() if k.lower() in phases and isinstance(v, str)}

# Sync with Markdown table if present
first_reopened = ""
if rows:
    md_approved = []
    for phase in phases:
        if phase in rows:
            if reopened_re.match(rows[phase][3]):
                first_reopened = phase
                break
            if positive.match(rows[phase][3]):
                md_approved.append(phase)
                d_cell = rows[phase][4][:10] if len(rows[phase]) >= 5 else ""
                if re.match(r"^\d{4}-\d{2}-\d{2}$", d_cell):
                    phase_dates[phase] = d_cell
    if md_approved or first_reopened:
        approved_list = md_approved

cli_approve = os.environ.get("HOOK_APPROVE_PHASE", "").strip().lower()
if cli_approve:
    if cli_approve not in phases:
        print(f"FAIL: --approve phase must be one of {', '.join(phases)}", file=sys.stderr)
        raise SystemExit(1)
    for p in phases[: phases.index(cli_approve) + 1]:
        if p not in approved_list:
            approved_list.append(p)
        if p not in phase_dates:
            phase_dates[p] = today_iso
    phase_dates[cli_approve] = today_iso
    first_reopened = ""

cli_reopen = os.environ.get("HOOK_REOPEN_PHASE", "").strip().lower()
reopen_count = max(int(prev.get("reopenCount") or 0), reopen_rows)
if cli_reopen:
    if cli_reopen not in active_phases:
        print(f"FAIL: --reopen phase must be one of {', '.join(active_phases)}", file=sys.stderr)
        raise SystemExit(1)
    first_reopened = cli_reopen
    reopen_count += 1
    if cli_reopen in phases:
        idx = phases.index(cli_reopen)
        approved_list = [p for p in approved_list if phases.index(p) < idx]
        phase_dates = {k: v for k, v in phase_dates.items() if k in approved_list}

if reopen_count > 3:
    print(f"FAIL: exceeded max Re-opened bounce budget ({reopen_count} > 3). Stop and escalate to user.", file=sys.stderr)
    raise SystemExit(2)

last_approved = approved_list[-1] if approved_list else ""


def evidence(phase):
    if phase not in rows:
        return []
    found = re.findall(r"docs/[A-Za-z0-9_./<>-]+", rows[phase][1].replace("`", ""))
    return sorted({item.rstrip(".,;") for item in found if "<" not in item})


if os.environ.get("HOOK_CLEAR_ACTIVE") == "1":
    active_phase = ""
    active_status = ""
    blocked_reason = ""
elif cli_reopen:
    active_phase = cli_reopen
    active_status = "in_progress"
    blocked_reason = ""
elif cli_approve:
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
    if (
        first_reopened
        and active_status == "blocked"
        and active_phase in phases
        and phases.index(active_phase) > phases.index(first_reopened)
    ):
        active_phase = first_reopened
else:
    active_phase = prev.get("activePhase") or ""
    active_status = prev.get("activeStatus") or ""
    blocked_reason = prev.get("blockedReason") or ""
    pr_path = (
        os.path.join(os.path.dirname(art), "phase-result.md")
        if (onboarding or maintain_note)
        else os.path.splitext(art)[0] + ".phase-result.md"
    )
    pr_approved_last = False
    if last_approved and os.path.isfile(pr_path):
        try:
            pr_txt = open(pr_path, encoding="utf-8").read()
            mp = re.search(r"^\s*phase:\s*(\S+)", pr_txt, re.I | re.M)
            ms = re.search(r"^\s*status:\s*(\S+)", pr_txt, re.I | re.M)
            if (
                mp
                and ms
                and mp.group(1).strip().lower() == last_approved
                and ms.group(1).strip().lower() == "approved"
            ):
                pr_approved_last = True
        except OSError:
            pass
    if active_phase and (active_phase == last_approved or pr_approved_last):
        active_phase = ""
        active_status = ""
        blocked_reason = ""
    if first_reopened and (
        not active_phase
        or (active_phase in phases and phases.index(active_phase) > phases.index(first_reopened))
    ):
        active_phase = first_reopened
        if active_status not in ("in_progress", "blocked"):
            active_status = "in_progress"
            blocked_reason = ""


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


feature_id = (
    "onboarding" if onboarding
    else os.path.basename(os.path.dirname(rel_art)) if maintain_note
    else "program" if program_doc
    else os.environ.get("HOOK_SLUG", "")
)
prev_bc = (prev.get("baseCommit") or "").strip()
head_bc = resolve_git_head(os.environ.get("HOOK_BASE", ""))
rep_parent = ""
if onboarding:
    m_onb = re.search(r"^commit:\s*([0-9a-f]{7,40})\b", raw_text, re.I | re.M)
    if m_onb:
        rep_parent = m_onb.group(1)
        prev_bc = ""
elif feature_id and not program_doc:
    for rep_path in (
        os.path.join("docs", "agents-v0", "build", feature_id, "build-report.md"),
        os.path.join("docs", "agents-v0", "verify", feature_id, "test-report.md"),
        os.path.join("docs", "agents-v0", "verify", feature_id, "quality-gate.md"),
    ):
        if os.path.isfile(rep_path):
            try:
                m = re.search(r"^commit:\s*([0-9a-f]{7,40})\b", open(rep_path, encoding="utf-8").read(), re.I | re.M)
                if m:
                    rep_sha = m.group(1)
                    r_full = subprocess.run(
                        ["git", "rev-parse", "--verify", "-q", f"{rep_sha}^{{commit}}"],
                        capture_output=True, text=True, check=False,
                    )
                    full_rep = r_full.stdout.strip() if r_full.returncode == 0 else ""
                    r_par = subprocess.run(
                        ["git", "rev-parse", "--verify", "-q", f"{rep_sha}^"],
                        capture_output=True, text=True, check=False,
                    )
                    if r_par.returncode == 0 and r_par.stdout.strip():
                        rep_parent = r_par.stdout.strip()
                    if prev_bc and full_rep and (prev_bc == full_rep or full_rep.startswith(prev_bc)):
                        prev_bc = ""
                    break
            except OSError:
                pass

base_commit = prev_bc or rep_parent or head_bc

# Helper brief deduplication
prior_hashes = list(prev.get("helperBriefHashes") or [])
if Path("docs/agents-v0").is_dir():
    extra_briefs = set()
    if onboarding and Path("docs/agents-v0/onboarding").is_dir():
        extra_briefs |= set(Path("docs/agents-v0/onboarding").glob("*.helper-brief.md"))
    if program_doc and Path("docs/agents-v0/design/system").is_dir():
        extra_briefs |= set(Path("docs/agents-v0/design/system").glob("*.helper-brief.md"))
    brief_candidates = sorted(
        set(Path("docs/agents-v0").rglob(f"{feature_id}.helper-brief.md"))
        | set(Path("docs/agents-v0").rglob(f"{feature_id}/helper-brief.md"))
        | extra_briefs
    )
    for brief in brief_candidates:
        try:
            b_text = brief.read_text(encoding="utf-8")
        except OSError:
            continue
        m_helper = re.search(r"^helper:\s*(.+)$", b_text, re.M)
        m_ask = re.search(r"^(?:ask|outputs|return):\s*(.+)$", b_text, re.M)
        if m_helper and m_ask:
            digest = hashlib.sha256(
                f"{brief.name}:{brief.parent.name}:{m_helper.group(1).strip()}:{m_ask.group(1).strip()}".encode("utf-8")
            ).hexdigest()[:16]
            if digest in prior_hashes:
                print(
                    f"FAIL: Duplicate helper brief ask detected ({digest}) in {brief}. Stop loop and escalate to user.",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            prior_hashes.append(digest)

# Discover on-disk phase artifacts for fast agent context indexing
prev_artifacts = dict(prev.get("artifacts") or {}) if program_doc else {}
artifacts_map = {**prev_artifacts, "primary": art}
if program_doc:
    if "docs/agents-v0/roadmap/" in rel_art:
        artifacts_map["roadmap"] = art
    elif rel_art.endswith("docs/agents-v0/architecture.md"):
        artifacts_map["architecture"] = art
    elif "docs/agents-v0/milestones/" in rel_art:
        artifacts_map["plan"] = art
    for k, rel_p in (
        ("contextMap", "docs/agents-v0/design/system/context-map.md"),
        ("arcRecord", "docs/agents-v0/design/system/arc-record.md"),
        ("architectureReview", "docs/agents-v0/design/system/architecture-review.md"),
    ):
        if os.path.isfile(rel_p):
            artifacts_map[k] = rel_p
elif onboarding:
    for k, rel_p in (
        ("repoMap", "docs/agents-v0/repo-map.md"),
        ("baseline", "docs/agents-v0/discovery/baseline.md"),
        ("securityBaseline", "docs/agents-v0/discovery/security-baseline.md"),
        ("architecture", "docs/agents-v0/architecture.md"),
        ("network", "docs/agents-v0/network.md"),
        ("contextMap", "docs/agents-v0/design/system/context-map.md"),
        ("inheritedDecisions", "docs/agents-v0/adr/0000-inherited-decisions.md"),
    ):
        if os.path.isfile(rel_p):
            artifacts_map[k] = rel_p
    mod_dir = Path("docs/agents-v0/onboarding/modules")
    if mod_dir.is_dir():
        m_files = sorted(p.as_posix() for p in mod_dir.glob("*.md") if p.is_file() and not p.name.startswith("_"))
        if m_files:
            artifacts_map["modules"] = m_files
    seq_dir = Path("docs/agents-v0/diagrams/sequences")
    if seq_dir.is_dir():
        s_files = sorted(p.as_posix() for p in seq_dir.glob("*.md") if p.is_file() and not p.name.startswith("_"))
        if s_files:
            artifacts_map["sequences"] = s_files
elif feature_id and not onboarding and not program_doc:
    candidates = {
        "design": f"docs/agents-v0/design/{feature_id}/design.md",
        "openapi": f"docs/agents-v0/design/{feature_id}/openapi.yaml",
        "asyncapi": f"docs/agents-v0/design/{feature_id}/asyncapi.yaml",
        "uxSpec": f"docs/agents-v0/design/{feature_id}/ux-spec.md",
        "designReview": f"docs/agents-v0/design/{feature_id}/review.md",
        "buildPlan": f"docs/agents-v0/build/{feature_id}/plan.md",
        "buildReport": f"docs/agents-v0/build/{feature_id}/build-report.md",
    }
    for k, rel_p in candidates.items():
        if os.path.isfile(rel_p):
            artifacts_map[k] = rel_p
    verify_dir = Path(f"docs/agents-v0/verify/{feature_id}")
    if verify_dir.is_dir():
        v_files = sorted(p.as_posix() for p in verify_dir.glob("*.md") if p.is_file())
        if v_files:
            artifacts_map["verify"] = v_files

build_ev = evidence("build") or prev.get("evidence", {}).get("build", [])
if not build_ev and "buildReport" in artifacts_map:
    build_ev = [artifacts_map["buildReport"]]
verify_ev = evidence("verify") or prev.get("evidence", {}).get("verify", [])
if not verify_ev and "verify" in artifacts_map:
    verify_ev = list(artifacts_map["verify"])

vp_raw = os.environ.get("HOOK_VERIFY_PASSED", "").strip().lower()
if vp_raw in ("true", "1", "yes"):
    verify_passed = True
elif vp_raw in ("false", "0", "no"):
    verify_passed = False
elif last_approved in ("verify", "release"):
    verify_passed = True
else:
    verify_passed = bool(prev.get("verifyPassed", False))

data = {
    "feature": feature_id,
    "tier": tier,
    "lastApprovedPhase": last_approved,
    "approvedPhases": approved_list,
    "phaseDates": {p: phase_dates.get(p, today_iso) for p in approved_list},
    "activePhase": active_phase,
    "activeStatus": active_status,
    "blockedReason": blocked_reason,
    "verifyPassed": verify_passed,
    "reopenCount": reopen_count,
    "helperBriefHashes": prior_hashes,
    "artifact": art,
    "baseCommit": base_commit,
    "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "artifacts": artifacts_map,
    "evidence": {
        "build": build_ev,
        "verify": verify_ev,
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
