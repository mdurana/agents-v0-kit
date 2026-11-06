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
case "$art" in
  *.phase-result.md | *.helper-brief.md)
    printf 'FAIL: artifact must be a primary artifact, not %s\n' "$art" >&2
    exit 1
    ;;
  docs/agents-v0/requirements/*.md | */docs/agents-v0/requirements/*.md)
    state="docs/agents-v0/requirements/${slug}.state.json"
    ;;
  docs/agents-v0/onboarding/*.md | */docs/agents-v0/onboarding/*.md)
    state="docs/agents-v0/onboarding/state.json"
    ;;
  docs/agents-v0/maintain/*/note.md | */docs/agents-v0/maintain/*/note.md)
    state="$(dirname "$art")/state.json"
    ;;
  docs/agents-v0/roadmap/*.md | */docs/agents-v0/roadmap/*.md | docs/agents-v0/architecture.md | */docs/agents-v0/architecture.md | docs/agents-v0/milestones/*.md | */docs/agents-v0/milestones/*.md)
    state="docs/agents-v0/program.state.json"
    ;;
  *)
    printf 'FAIL: artifact must be a requirements file, maintain/<id>/note.md, onboarding file, or program artifact (%s)\n' "$art" >&2
    exit 1
    ;;
esac

# Deterministic milestone dependency gate (v0-build.md Prerequisite): a story cannot enter
# Build (in_progress / awaiting_approval) or have Build approved while a dependency is unverified.
# Recording the blocked state is always allowed.
case "$art" in
  docs/agents-v0/requirements/*.md | */docs/agents-v0/requirements/*.md)
    dep_gate=0
    if [ "$set_active" = 1 ] && [ "$active_phase" = build ] && [ "$active_status" != blocked ]; then
      dep_gate=1
    fi
    [ "$approve_phase" = build ] && dep_gate=1
    if [ "$dep_gate" = 1 ]; then
      sh "$(dirname "$0")/check-story-dependencies.sh" "$art" >/dev/null || exit 1
    fi
    ;;
esac

# Architecture prerequisite gate (F8, T6): cannot enter architecture unless Sensei's external roadmap approval record exists
if [ "$set_active" = 1 ] && [ "$active_phase" = architecture ] && [ "$active_status" != blocked ]; then
  guard_common="$(dirname "$0")/guard-common.sh"
  if [ -f "$guard_common" ]; then
    GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
    if ! ok_msg="$(gc_approval_ok roadmap)"; then
      printf 'FAIL: architecture requires approved roadmap record: %s\n' "$ok_msg" >&2
      printf '  Complete /v0-roadmap and ensure Sensei approves via guard-common.sh approve roadmap before starting architecture.\n' >&2
      exit 1
    fi
  fi
fi

# Plan prerequisite gate (FA8, DA7): cannot enter non-P0-A plan unless Sensei's external architecture approval record exists
if [ "$set_active" = 1 ] && [ "$active_phase" = plan ] && [ "$active_status" != blocked ]; then
  guard_common="$(dirname "$0")/guard-common.sh"
  if [ -f "$guard_common" ]; then
    GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
    plan_prog_phases="$(gc_state_get docs/agents-v0/program.state.json approvedPhases 2>/dev/null | tr -d '[]",' || true)"
    case " $plan_prog_phases " in
      *" roadmap "*|*" architecture "*)
        if ! ok_msg="$(gc_approval_ok architecture)"; then
          printf 'FAIL: plan requires approved architecture record: %s\n' "$ok_msg" >&2
          printf '  Complete /v0-architecture and ensure Sensei approves via guard-common.sh approve architecture before starting plan.\n' >&2
          exit 1
        fi
        ;;
    esac
  fi
fi

# Release approval only on the integration branch (kitfix-20261029-step4-p1e). Release is recorded in the
# integration checkout after the merge (v0-local-release step 6, local-release step 8;
# P0-A is already on that branch). Recording it on feature/<feature> or maintain/<id>
# after the merge leaves that branch ahead of the integration branch.
approve_lc="$(printf '%s' "$approve_phase" | tr '[:upper:]' '[:lower:]')"
# Refuse --approve roadmap, architecture, plan, scaffold, or guard-managed intake unless gc_approval_ok succeeds (F1, FA1, FP1, FS1, FI1, DSA, DIA)
case "$approve_lc" in
  roadmap|architecture|plan|scaffold)
    guard_common="$(dirname "$0")/guard-common.sh"
    if [ -f "$guard_common" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
      if ! ok_msg="$(gc_approval_ok "$approve_lc")"; then
        printf 'FAIL: --approve %s refused without Sensei external approval record: %s\n' "$approve_lc" "$ok_msg" >&2
        printf '  Sensei must approve in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve %s\n' "$approve_lc" >&2
        exit 1
      fi
    else
      printf 'FAIL: --approve %s requires %s\n' "$approve_lc" "$guard_common" >&2
      exit 1
    fi
    ;;
  intake)
    guard_common="$(dirname "$0")/guard-common.sh"
    intake_slug="$slug"
    intake_state="docs/agents-v0/requirements/${intake_slug}.state.json"
    intake_pr="docs/agents-v0/requirements/${intake_slug}.phase-result.md"
    if [ -f "$guard_common" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
      intake_base=""
      [ -f "$intake_state" ] && intake_base="$(gc_state_get "$intake_state" baseCommit 2>/dev/null || true)"
      if [ -n "$intake_base" ] || { [ -f "$intake_pr" ] && grep -Fq "guard_managed: true" "$intake_pr"; }; then
        if ! ok_msg="$(gc_approval_ok intake "$intake_slug")"; then
          printf 'FAIL: --approve intake for %s refused without Sensei external approval record: %s\n' "$intake_slug" "$ok_msg" >&2
          printf '  Sensei must approve in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve intake %s\n' "$intake_slug" >&2
          exit 1
        fi
      fi
    fi
    ;;
  design)
    guard_common="$(dirname "$0")/guard-common.sh"
    design_slug="$slug"
    design_state="docs/agents-v0/requirements/${design_slug}.state.json"
    design_pr="docs/agents-v0/requirements/${design_slug}.phase-result.md"
    if [ -f "$guard_common" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
      design_gm=""
      [ -f "$design_state" ] && design_gm="$(gc_state_get "$design_state" designGuardManaged 2>/dev/null || true)"
      if [ "$design_gm" = "True" ] || [ "$design_gm" = "true" ] || { [ -f "$design_pr" ] && grep -Fq "phase: design" "$design_pr" && grep -Fq "guard_managed: true" "$design_pr"; }; then
        if ! ok_msg="$(gc_approval_ok design "$design_slug")"; then
          printf 'FAIL: --approve design for %s refused without Sensei external approval record: %s\n' "$design_slug" "$ok_msg" >&2
          printf '  Sensei must approve in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve design %s\n' "$design_slug" >&2
          exit 1
        fi
      fi
    fi
    ;;
  build)
    guard_common="$(dirname "$0")/guard-common.sh"
    build_slug="$slug"
    build_state="docs/agents-v0/requirements/${build_slug}.state.json"
    build_pr="docs/agents-v0/requirements/${build_slug}.phase-result.md"
    if [ -f "$guard_common" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
      build_gm=""
      [ -f "$build_state" ] && build_gm="$(gc_state_get "$build_state" buildGuardManaged 2>/dev/null || true)"
      if [ "$build_gm" = "True" ] || [ "$build_gm" = "true" ] || { [ -f "$build_pr" ] && grep -Fq "phase: build" "$build_pr" && grep -Fq "guard_managed: true" "$build_pr"; }; then
        if ! ok_msg="$(gc_approval_ok build "$build_slug")"; then
          printf 'FAIL: --approve build for %s refused without Sensei external approval record: %s\n' "$build_slug" "$ok_msg" >&2
          printf '  Sensei must approve in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve build %s\n' "$build_slug" >&2
          exit 1
        fi
      fi
    fi
    ;;
  verify)
    guard_common="$(dirname "$0")/guard-common.sh"
    verify_slug="$slug"
    verify_state="$state"
    verify_pr="docs/agents-v0/requirements/${verify_slug}.phase-result.md"
    [ -f "$verify_pr" ] || verify_pr="docs/agents-v0/maintain/${verify_slug}/phase-result.md"
    if [ -f "$guard_common" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$guard_common"
      verify_gm=""
      [ -f "$verify_state" ] && verify_gm="$(gc_state_get "$verify_state" verifyGuardManaged 2>/dev/null || true)"
      if [ "$verify_gm" = "True" ] || [ "$verify_gm" = "true" ] || { [ -f "$verify_pr" ] && grep -Fq "phase: verify" "$verify_pr" && grep -Fq "guard_managed: true" "$verify_pr"; }; then
        if ! ok_msg="$(gc_approval_ok verify "$verify_slug")"; then
          printf 'FAIL: --approve verify for %s refused without Sensei external approval record: %s\n' "$verify_slug" "$ok_msg" >&2
          printf '  Sensei must approve in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve verify %s\n' "$verify_slug" >&2
          exit 1
        fi
      fi
    fi
    ;;
esac

if [ "$approve_lc" = release ] && command -v git >/dev/null 2>&1 \
   && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  resolver="$(dirname "$0")/resolve-integration-branch.sh"
  if [ ! -f "$resolver" ]; then
    printf 'FAIL: --approve release needs %s to find the integration branch\n' "$resolver" >&2
    exit 1
  fi
  integration="$(sh "$resolver")"
  integration="${integration#origin/}"
  current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ "$integration" != HEAD ] && [ "$current" != "$integration" ]; then
    printf 'FAIL: --approve release runs only on the integration branch %s (current: %s).\n' \
      "$integration" "${current:-detached HEAD}" >&2
    printf '  Merge the story branch into %s, then run this in the %s checkout (git worktree list).\n' \
      "$integration" "$integration" >&2
    printf '  After the merge, do not commit to feature/<feature> or maintain/<id> or update its state.\n' >&2
    exit 1
  fi
fi

# Feature-branch guard (kitfix-20261031-branch-guard). Design, Build, Verify and the pre-merge
# Release work of a feature story happen only on feature/<feature>, in the worktree that
# feature-worktree.sh created after the user authorised the branch (v0-intake step 7). Run
# 20261029-1629 (P2-A): one truncated Intake turn skipped that step and design, build, verify and
# release were all recorded and committed on main; prose in v0-design/v0-build did not stop it.
# P0-A has no feature branch and works on the integration branch. Recording a blocked state is
# allowed anywhere (it records a stop, it does no work). Maintenance notes are not checked here.
# AGENTS_V0_SKIP_BRANCH_GUARD=1 skips the check in the kit's own test copies only: install.sh removes the
# override block below, so an installed copy always runs the guard (kitfix-20261031-installed-no-overrides).
bg_skip=0
# >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
[ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || bg_skip=1
# <<< kit-test-override
case "$art" in
  docs/agents-v0/requirements/*.md | */docs/agents-v0/requirements/*.md)
    bg_phase=""
    if [ "$set_active" = 1 ] && [ "$active_status" != blocked ]; then
      case "$active_phase" in design|build|verify|release) bg_phase="$active_phase" ;; esac
    fi
    case "$approve_lc" in design|build|verify) bg_phase="$approve_lc" ;; esac
    if [ -z "$bg_phase" ] && [ -n "$verify_passed" ] && [ "$approve_lc" != release ]; then
      bg_phase="verify"
    fi
    if [ -n "$bg_phase" ] && [ "$bg_skip" != 1 ] \
       && command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      bg_current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      bg_p0a=0
      case "$slug" in p0-a-*|p0-a) bg_p0a=1 ;; esac
      grep -Eiq '^[[:space:]]*(\*\*)?Story(\*\*)?:[[:space:]]*(\*\*)?P0-A([^A-Za-z0-9]|$)' "$art" 2>/dev/null && bg_p0a=1
      if [ "$bg_p0a" = 1 ]; then
        bg_resolver="$(dirname "$0")/resolve-integration-branch.sh"
        if [ -f "$bg_resolver" ]; then
          bg_int="$(sh "$bg_resolver")"
          bg_int="${bg_int#origin/}"
          if [ "$bg_int" != HEAD ] && [ "$bg_current" != "$bg_int" ]; then
            printf 'FAIL: P0-A %s runs only on the integration branch %s (current: %s).\n' \
              "$bg_phase" "$bg_int" "${bg_current:-detached HEAD}" >&2
            exit 1
          fi
        fi
      elif [ "$bg_current" != "feature/$slug" ]; then
        printf 'FAIL: %s for %s runs only on feature/%s (current: %s).\n' \
          "$bg_phase" "$slug" "$slug" "${bg_current:-detached HEAD}" >&2
        if git show-ref --verify --quiet "refs/heads/feature/$slug"; then
          printf '  Open the feature/%s worktree (git worktree list) and run this there.\n' "$slug" >&2
        else
          printf '  No feature/%s branch exists: /v0-intake %s must finish its branch step first (ask the user to authorise the branch, then sh .agents-v0/scripts/feature-worktree.sh %s), then work in the folder it prints.\n' \
            "$slug" "$slug" "$slug" >&2
        fi
        printf '  Do not set in_progress, approve, or commit this story on the integration branch.\n' >&2
        exit 1
      fi
    fi
    ;;
esac

# Gate commits (kitfix-20261031-gate-commit). Every approved gate is one commit (check-gate-commit.sh):
# a new phase does not start while the last approved phase is uncommitted, and a feature story's release
# is approved only after feature/<feature> is committed and squash-staged in the integration checkout.
# AGENTS_V0_SKIP_COMMIT_CHECK=1 skips both in the kit's own test copies only (installed copies never skip).
gc_script="$(dirname "$0")/check-gate-commit.sh"
gc_skip=0
# >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
[ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gc_skip=1
# <<< kit-test-override
# An installed copy refuses when a gate script is missing (deleting it must not switch the check off);
# the kit's own test copies may run without them.
kit_missing_ok=0
# >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
kit_missing_ok=1
# <<< kit-test-override
for kit_req in check-gate-commit.sh check-traceability.sh; do
  if [ ! -f "$(dirname "$0")/$kit_req" ] && [ "$kit_missing_ok" != 1 ]; then
    printf 'FAIL: .agents-v0/scripts/%s is missing; reinstall the kit (install.sh --update) before recording a phase.\n' "$kit_req" >&2
    exit 1
  fi
done
if [ "$gc_skip" != 1 ] && [ -f "$gc_script" ]; then
  if [ "$set_active" = 1 ] && [ "$active_status" = in_progress ]; then
    gc_prev_active="$(python3 -c 'import json,sys
try: print((json.load(open(sys.argv[1])).get("activePhase") or ""))
except Exception: print("")' "$state" 2>/dev/null || true)"
    if [ -z "$gc_prev_active" ]; then
      sh "$gc_script" "$art" >/dev/null || exit 1
    fi
    # Design handoff check (DI7): when entering design in_progress on a guard-managed intake story, verify external intake approval
    if [ "$active_phase" = "design" ] && [ -f "$(dirname "$0")/guard-common.sh" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$(dirname "$0")/guard-common.sh"
      di7_base=""
      [ -f "$state" ] && di7_base="$(gc_state_get "$state" baseCommit 2>/dev/null || true)"
      if [ -n "$di7_base" ]; then
        if ! di7_ok="$(gc_approval_ok intake "$slug")"; then
          printf 'FAIL: design for %s refused without Sensei external intake approval record: %s\n' "$slug" "$di7_ok" >&2
          printf '  Complete /v0-intake %s (sh .agents-v0/scripts/guard-common.sh approve intake %s && sh .agents-v0/scripts/guard-intake.sh commit %s) first.\n' "$slug" "$slug" "$slug" >&2
          exit 1
        fi
      fi
    fi
    # Build handoff check (DD7): when entering build in_progress on a guard-managed design story, verify external design approval (or Contract: None)
    if [ "$active_phase" = "build" ] && [ -f "$(dirname "$0")/guard-common.sh" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$(dirname "$0")/guard-common.sh"
      dd7_gm=""
      [ -f "$state" ] && dd7_gm="$(gc_state_get "$state" designGuardManaged 2>/dev/null || true)"
      dd7_pr="docs/agents-v0/requirements/${slug}.phase-result.md"
      dd7_cn=0
      if [ -f "$dd7_pr" ] && grep -Fq "phase: design" "$dd7_pr" && grep -Fq "status: contract_none" "$dd7_pr"; then
        dd7_cn=1
      fi
      if [ "$dd7_cn" != 1 ] && { [ "$dd7_gm" = "True" ] || [ "$dd7_gm" = "true" ]; }; then
        if ! dd7_ok="$(gc_approval_ok design "$slug")"; then
          printf 'FAIL: build for %s refused without Sensei external design approval record: %s\n' "$slug" "$dd7_ok" >&2
          printf '  Complete /v0-design %s (sh .agents-v0/scripts/guard-common.sh approve design %s && sh .agents-v0/scripts/guard-design.sh commit %s) first.\n' "$slug" "$slug" "$slug" >&2
          exit 1
        fi
      fi
    fi
    # Verify handoff check (DB7): when entering verify in_progress on a guard-managed build story, verify external build approval
    if [ "$active_phase" = "verify" ] && [ -f "$(dirname "$0")/guard-common.sh" ]; then
      GC_HERE="$(dirname "$0")" GUARD_COMMON_LIB=1 . "$(dirname "$0")/guard-common.sh"
      db7_gm=""
      [ -f "$state" ] && db7_gm="$(gc_state_get "$state" buildGuardManaged 2>/dev/null || true)"
      if [ "$db7_gm" = "True" ] || [ "$db7_gm" = "true" ]; then
        if ! db7_ok="$(gc_approval_ok build "$slug")"; then
          printf 'FAIL: verify for %s refused without Sensei external build approval record: %s\n' "$slug" "$db7_ok" >&2
          printf '  Complete /v0-build %s (sh .agents-v0/scripts/guard-common.sh approve build %s && sh .agents-v0/scripts/guard-build.sh commit %s) first.\n' "$slug" "$slug" "$slug" >&2
          exit 1
        fi
      fi
    fi
  fi

  case "$art" in
    docs/agents-v0/requirements/*.md | */docs/agents-v0/requirements/*.md)
      if [ "$approve_lc" = release ]; then
        sh "$gc_script" --release "$art" >/dev/null || exit 1
      fi
      ;;
  esac
fi

# Gate-to-gate consistency (kitfix-20261031-traceability): at the Design, Build and Verify approvals,
# check-traceability.sh checks the ids the earlier gates approved (warn first; AGENTS_V0_TRACE_MODE=fail
# makes a failure refuse the approval) and records them in <feature>.trace.json for this gate's commit.
case "$art" in
  docs/agents-v0/requirements/*.md | */docs/agents-v0/requirements/*.md)
    case "$approve_lc" in
      design|build|verify)
        tr_script="$(dirname "$0")/check-traceability.sh"
        if [ -f "$tr_script" ]; then sh "$tr_script" "$approve_lc" "$art" || exit 1; fi
        ;;
    esac
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
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
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

os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
lock_fd = open(out + ".lock", "w", encoding="utf-8")
fcntl.flock(lock_fd, fcntl.LOCK_EX)

prev = {}
if os.path.isfile(out):
    try:
        with open(out, encoding="utf-8") as f:
            prev = json.load(f)
    except ValueError as exc:
        print(f"FAIL: corrupt JSON in {out}: {exc}", file=sys.stderr)
        raise SystemExit(1)

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

# kitfix-20261031-single-clock: one clock for every date this script writes (phaseDates, phaseTimes,
# the Date cell of the approved Delivery approvals row, updatedAt). The project time zone comes from
# AGENTS_V0_TZ (kit test copies only), else the `Timezone` row of docs/agents-v0/project-profile.md, else the system zone.
# Run 20261029-1629 (P2-A H3): the script dated approvals in UTC while the agent typed local dates
# (or `date -u`), so phaseDates went backwards across midnight Asia/Manila.
# AGENTS_V0_NOW=<ISO time with offset> pins the clock (kit test copies only: install.sh removes both env reads).
import datetime as _dt


def _project_tz():
    name = ""
    # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
    name = os.environ.get("AGENTS_V0_TZ", "").strip()
    # <<< kit-test-override
    if not name:
        prof = "docs/agents-v0/project-profile.md"
        try:
            for line in open(prof, encoding="utf-8"):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if len(cells) >= 2 and cells[0].lower() in ("timezone", "time zone"):
                    v = re.sub(r"<!--.*?-->", "", cells[1]).strip()
                    if v and not v.startswith("<") and " " not in v:
                        name = v
                    break
        except OSError:
            pass
    if name:
        try:
            from zoneinfo import ZoneInfo
            return ZoneInfo(name)
        except Exception:
            print(f"WARN: unknown time zone {name!r}; using the system zone", file=sys.stderr)
    return None


def kit_now():
    pinned = ""
    # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
    pinned = os.environ.get("AGENTS_V0_NOW", "").strip()
    # <<< kit-test-override
    tz = _project_tz()
    if pinned:
        t = _dt.datetime.fromisoformat(pinned)
        if t.tzinfo is None:
            t = t.astimezone()
    else:
        t = _dt.datetime.now().astimezone()
    return t.astimezone(tz) if tz is not None else t.astimezone()


now_dt = kit_now()
today_iso = now_dt.date().isoformat()
now_iso = now_dt.isoformat(timespec="seconds")
phase_dates = {k.lower(): v for k, v in (prev.get("phaseDates") or {}).items() if k.lower() in phases and isinstance(v, str)}
phase_times = {k.lower(): v for k, v in (prev.get("phaseTimes") or {}).items() if k.lower() in phases and isinstance(v, str)}

# Merge Markdown table rows with state.json approvals (union positive rows; withdraw on Re-opened or non-positive row)
first_reopened = ""
if rows:
    cut_idx = None
    for idx, phase in enumerate(phases):
        if phase not in rows:
            continue
        decision = rows[phase][3]
        if reopened_re.match(decision):
            first_reopened = phase
            cut_idx = idx
            break
        if positive.match(decision):
            if phase not in approved_list:
                approved_list.append(phase)
            d_cell = rows[phase][4][:10] if len(rows[phase]) >= 5 else ""
            if re.match(r"^\d{4}-\d{2}-\d{2}$", d_cell):
                # The recorded approval date wins; a table cell only fills a phase with no date yet.
                if phase not in phase_dates:
                    phase_dates[phase] = d_cell
                elif phase_dates[phase] != d_cell:
                    print(
                        f"WARN: Delivery approvals date for {phase} ({d_cell}) differs from the recorded "
                        f"approval date ({phase_dates[phase]}); the state keeps {phase_dates[phase]}.",
                        file=sys.stderr,
                    )
        else:
            cut_idx = idx
            break
    approved_list = [p for p in phases if p in approved_list]
    if cut_idx is not None:
        approved_list = [p for p in approved_list if phases.index(p) < cut_idx]
        phase_dates = {k: v for k, v in phase_dates.items() if k in approved_list}
        phase_times = {k: v for k, v in phase_times.items() if k in approved_list}

cli_approve = os.environ.get("HOOK_APPROVE_PHASE", "").strip().lower()
if cli_approve:
    if cli_approve not in phases:
        print(f"FAIL: --approve phase must be one of {', '.join(phases)}", file=sys.stderr)
        raise SystemExit(1)
    # kitfix-20261031-skeleton (design evidence): --approve design on a feature story needs the
    # agent's own design.md on disk. The harness never writes it (fix-and-resume.md 5.6, P1-C).
    if (
        not (onboarding or maintain_note or program_doc)
        and cli_approve == "design"
        and not os.environ.get("HOOK_SLUG", "").startswith("p0-a")
    ):
        dpath = os.path.join("docs", "agents-v0", "design", os.environ.get("HOOK_SLUG", ""), "design.md")
        if not os.path.isfile(dpath) or not open(dpath, encoding="utf-8").read().strip():
            print(
                f"FAIL: --approve design needs {dpath} (written by /v0-design in this story's worktree). "
                "Do not approve; finish /v0-design first.",
                file=sys.stderr,
            )
            raise SystemExit(1)
    # Preconditions (KD-02): on a feature story, --approve verify|release needs the Verify
    # evidence on disk, and --approve release needs verifyPassed already true (or set in this
    # call). A single call can no longer forge a complete, released story from nothing.
    if not (onboarding or maintain_note or program_doc) and cli_approve in ("verify", "release"):
        slug_id = os.environ.get("HOOK_SLUG", "")
        qg = os.path.join("docs", "agents-v0", "verify", slug_id, "quality-gate.md")
        vp_now = os.environ.get("HOOK_VERIFY_PASSED", "").strip().lower() in ("true", "1", "yes")
        missing = []
        if not os.path.isfile(qg):
            missing.append(f"{qg} is missing")
        if cli_approve == "release" and not (prev.get("verifyPassed") is True or vp_now):
            missing.append("verifyPassed is not true (run /v0-verify first)")
        if missing:
            print(
                f"FAIL: --approve {cli_approve} needs Verify evidence: {'; '.join(missing)}. "
                "Do not approve; run /v0-verify for this story.",
                file=sys.stderr,
            )
            raise SystemExit(1)
    # An emergency note may release before Verify. Do not backfill verify,
    # and do not treat that release as verifyPassed. P0-A is a feature story.
    emergency_skip_verify = (
        maintain_note and tier == "emergency" and "verify" not in approved_list
        and cli_approve != "verify"
    )
    for p in phases[: phases.index(cli_approve) + 1]:
        if emergency_skip_verify and p == "verify":
            continue
        if p not in approved_list:
            approved_list.append(p)
        if p not in phase_dates:
            phase_dates[p] = today_iso
        if p not in phase_times:
            phase_times[p] = now_iso
    phase_dates[cli_approve] = today_iso
    phase_times[cli_approve] = now_iso
    # D2: the script, not the agent, writes the Date cell of the approved row (same clock).
    try:
        lines = raw_text.splitlines(keepends=True)
        in_sec, hit = False, None
        for i, line in enumerate(lines):
            if re.match(r"^#+\s*delivery approvals", line, re.I):
                in_sec = True
                continue
            if in_sec and re.match(r"^#+\s+\S", line):
                break
            if in_sec and line.strip().startswith("|"):
                c = [x.strip() for x in line.strip().strip("|").split("|")]
                if len(c) >= 5 and c[0].lower() == cli_approve and positive.match(c[3]):
                    hit = (i, c)
        if hit is not None and hit[1][4][:10] != today_iso:
            i, c = hit
            c[4] = today_iso
            nl = "\n" if lines[i].endswith("\n") else ""
            lines[i] = "| " + " | ".join(c) + " |" + nl
            with open(art, "w", encoding="utf-8") as fh:
                fh.write("".join(lines))
    except OSError as exc:
        print(f"WARN: could not write the approval date into {art}: {exc}", file=sys.stderr)
    approved_list = [p for p in phases if p in approved_list]
    first_reopened = ""

cli_reopen = os.environ.get("HOOK_REOPEN_PHASE", "").strip().lower()
reopen_count = max(int(prev.get("reopenCount") or 0), reopen_rows)
if (
    cli_reopen
    and not onboarding
    and not program_doc
    and "release" in approved_list
):
    if maintain_note:
        print(
            "FAIL: this maintenance note is released. Do not open it again. Start a new id.",
            file=sys.stderr,
        )
    else:
        print(
            "FAIL: this story is released. Do not open it again. "
            "Start /v0-maintain for a fix or a small change, or /v0-intake with a new slug for a new feature.",
            file=sys.stderr,
        )
    raise SystemExit(1)
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
        phase_times = {k: v for k, v in phase_times.items() if k in approved_list}

reopen_exceeded = reopen_count > 3

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
    if reopen_count > 3:
        reopen_count = 3
        reopen_exceeded = False
elif cli_reopen:
    active_phase = cli_reopen
    if reopen_exceeded:
        active_status = "blocked"
        blocked_reason = f"Exceeded max Re-opened bounce budget ({reopen_count} > 3)"
    else:
        active_status = "in_progress"
        blocked_reason = ""
elif cli_approve:
    active_phase = ""
    active_status = ""
    blocked_reason = ""
    if reopen_count > 3:
        reopen_count = 3
        reopen_exceeded = False
elif os.environ.get("HOOK_SET_ACTIVE") == "1":
    active_phase = os.environ.get("HOOK_ACTIVE_PHASE", "")
    active_status = os.environ.get("HOOK_ACTIVE_STATUS", "")
    blocked_reason = os.environ.get("HOOK_BLOCKED_REASON", "")
    if active_phase not in active_phases:
        print(f"FAIL: active phase must be one of {', '.join(active_phases)}", file=sys.stderr)
        raise SystemExit(1)
    if active_phase in approved_list and not cli_reopen:
        verify_next = (
            "/v0-verify " + os.path.basename(os.path.dirname(rel_art))
            if maintain_note
            else "/v0-verify"
        )
        story_next = (
            "/v0-maintain for a fix, /v0-triage for a docs-only edit or patch bump, "
            "or /v0-intake with a new slug"
        )
        if "release" in approved_list:
            if maintain_note and tier == "emergency" and "verify" not in approved_list:
                nxt = verify_next
                released = "this maintenance note is released and still owes Verify"
            elif maintain_note:
                nxt = "a new maintenance id"
                released = "this maintenance note is released"
            else:
                nxt = story_next
                released = "this story is released"
            print(
                f"FAIL: {released}. Do not open it again. Next: {nxt}.",
                file=sys.stderr,
            )
            raise SystemExit(1)
        nxt = {
            "onboard": "/v0-roadmap, /v0-intake, /v0-triage, or /v0-maintain",
            "roadmap": "/v0-architecture",
            "architecture": "/v0-plan",
            "plan": "/v0-intake, or /v0-build when the first story is P0-A",
            "intake": "/v0-design",
            "design": "/v0-build",
            "build": "/v0-verify",
            "verify": "/v0-local-release",
            "maintain": "/v0-local-release" if tier == "emergency" else verify_next,
            "release": story_next,
        }.get(active_phase, "/v0-status")
        print(
            f"FAIL: {active_phase} is already approved. Do not open it again. Next: {nxt}.",
            file=sys.stderr,
        )
        raise SystemExit(1)
    if active_status not in statuses:
        print(f"FAIL: status must be one of {', '.join(sorted(statuses))}", file=sys.stderr)
        raise SystemExit(1)
    if active_status == "blocked" and not blocked_reason.strip():
        print("FAIL: --reason is required when status is blocked", file=sys.stderr)
        raise SystemExit(1)
    if active_status != "blocked":
        blocked_reason = ""
    if reopen_exceeded:
        active_status = "blocked"
        blocked_reason = blocked_reason or f"Exceeded max Re-opened bounce budget ({reopen_count} > 3)"
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
skip_brief_dedup = bool(cli_approve) or os.environ.get("HOOK_CLEAR_ACTIVE") == "1"
if Path("docs/agents-v0").is_dir() and not skip_brief_dedup:
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
        m_ask = re.search(r"^ask:\s*(.+)$", b_text, re.M) or re.search(r"^(?:outputs|return):\s*(.+)$", b_text, re.M)
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
elif cli_reopen and "verify" not in approved_list:
    verify_passed = False
elif last_approved in ("verify", "release"):
    if maintain_note and tier == "emergency" and "verify" not in approved_list:
        verify_passed = bool(prev.get("verifyPassed", False))
    else:
        verify_passed = True
else:
    verify_passed = bool(prev.get("verifyPassed", False))

data = {
    "feature": feature_id,
    "tier": tier,
    "lastApprovedPhase": last_approved,
    "approvedPhases": approved_list,
    "phaseDates": {p: phase_dates.get(p, today_iso) for p in approved_list},
    "phaseTimes": {p: phase_times[p] for p in approved_list if p in phase_times},
    "activePhase": active_phase,
    "activeStatus": active_status,
    "blockedReason": blocked_reason,
    "verifyPassed": verify_passed,
    "reopenCount": reopen_count,
    "helperBriefHashes": prior_hashes,
    "artifact": art,
    "baseCommit": base_commit,
    "updatedAt": now_iso,
    "artifacts": artifacts_map,
    "evidence": {
        "build": build_ev,
        "verify": verify_ev,
    },
}
if prev.get("designGuardManaged"):
    data["designGuardManaged"] = True
if prev.get("buildGuardManaged"):
    data["buildGuardManaged"] = True
if prev.get("verifyGuardManaged"):
    data["verifyGuardManaged"] = True
tmp_fd, tmp_path = tempfile.mkstemp(prefix=".state.", suffix=".tmp", dir=os.path.dirname(out) or ".")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_path, out)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
if reopen_exceeded:
    print(f"FAIL: exceeded max Re-opened bounce budget ({reopen_count} > 3). Stop and escalate to user.", file=sys.stderr)
    raise SystemExit(2)
print(
    f"Wrote {out} (lastApproved={last_approved or '-'} "
    f"active={active_phase or '-'} status={active_status or '-'} tier={tier})"
)
# kitfix-20261031-branch-guard: the branch step is its own turn, after the Intake approval.
_slug = os.environ.get("HOOK_SLUG", "")
if (
    cli_approve == "intake"
    and not (onboarding or maintain_note or program_doc)
    and not _slug.startswith("p0-a")
):
    print(
        f"Next: ask the user to authorise branch feature/{_slug}, and stop. After that reply, run "
        f"sh .agents-v0/scripts/feature-worktree.sh {_slug}. /v0-design refuses to start without it."
    )
PY

# kitfix-20261031-gate-commit: say how to commit the gate that was just approved.
if [ -n "$approve_lc" ] && [ -f "$gc_script" ]; then
  gc_cmd="$(sh "$gc_script" --message "$approve_lc" "$art" 2>/dev/null || true)"
  if [ -n "$gc_cmd" ]; then
    gc_p0a=0
    case "$slug" in p0-a-*|p0-a) gc_p0a=1 ;; esac
    grep -Eiq '^[[:space:]]*(\*\*)?Story(\*\*)?:[[:space:]]*(\*\*)?P0-A([^A-Za-z0-9]|$)' "$art" 2>/dev/null && gc_p0a=1
    case "$art:$approve_lc:$gc_p0a" in
      *docs/agents-v0/requirements/*:intake:0)
        printf 'Commit the Intake gate in the branch turn, in the new worktree after feature-worktree.sh: %s\n' "$gc_cmd" ;;
      *)
        printf 'Next: commit this gate (one commit, never amend): %s\n' "$gc_cmd" ;;
    esac
  fi
fi
