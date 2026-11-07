#!/bin/sh
# guard-deliver.sh — single entry point, phase dispatcher, and security boundary for /v0-deliver.
# Usage:
#   sh .agents-v0/scripts/guard-deliver.sh check <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]
#   sh .agents-v0/scripts/guard-deliver.sh start <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]
#   sh .agents-v0/scripts/guard-deliver.sh block <feature> "<reason>" [--maintain]
#   sh .agents-v0/scripts/guard-deliver.sh ready <feature> [--maintain]
#   sh .agents-v0/scripts/guard-deliver.sh commit <feature> [--maintain]
#   sh .agents-v0/scripts/guard-deliver.sh steps
#
# Design: DDL1 (/v0-deliver phase dispatcher, worktree resolver, and gate-rules boundary).
set -eu
export PYTHONDONTWRITEBYTECODE=1

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-deliver.sh"

gd_usage() {
  printf 'usage: %s check <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>" [--maintain]\n' "$G" >&2
  printf '       %s ready <feature> [--maintain]\n' "$G" >&2
  printf '       %s commit <feature> [--maintain]\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gd_validate_slug() {
  gd_v_step="$1"
  gd_v_slug="${2:-}"
  [ -n "$gd_v_slug" ] || gc_refuse "$gd_v_step" "missing <feature> slug; pass a lowercase feature or maintenance slug (e.g. feat-login)"
  case "$gd_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gd_v_step" "feature slug '$gd_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gd_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gd_v_step" "feature slug '$gd_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gd_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gd_v_step" "story '$gd_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-deliver"
      ;;
  esac
}

gd_validate_tier_arg() {
  gd_vt_step="$1"
  gd_vt_tier="$2"
  case "$gd_vt_tier" in
    trivial|standard|emergency|major) ;;
    *) gc_refuse "$gd_vt_step" "invalid --tier '$gd_vt_tier'; must be one of: trivial, standard, emergency, major" ;;
  esac
}

gd_rule() {
  gd_step="$1"
  gd_key="$2"
  gd_slug="${3:-}"
  gd_rules="${GC_HERE}/../gate-rules"
  [ -f "$gd_rules" ] || gc_refuse "$gd_step" "missing gate-rules file ($gd_rules)"
  gd_val="$(awk -v p="deliver" -v k="$gd_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gd_rules")"
  [ -n "$gd_val" ] || gc_refuse "$gd_step" "gate-rules missing key '$gd_key' for phase 'deliver'"
  if [ -n "$gd_slug" ]; then
    gd_val="$(printf '%s' "$gd_val" | sed "s/<feature>/$gd_slug/g")"
  fi
}

gd_is_brownfield() {
  [ -f docs/agents-v0/onboarding/state.json ] && return 0
  [ -f docs/agents-v0/onboarding/report.md ] && return 0
  [ -f docs/agents-v0/onboarding/baseline-status.json ] && return 0
  return 1
}

gd_next_phase_after() {
  gd_np_prev="$1"
  gd_np_maint="$2"
  gd_np_tier="$3"
  case "$gd_np_prev" in
    "")
      if [ "$gd_np_maint" = 1 ]; then
        printf 'maintain\n'
      else
        printf 'intake\n'
      fi
      ;;
    intake)
      printf 'design\n'
      ;;
    design)
      printf 'build\n'
      ;;
    maintain)
      if [ "$gd_np_tier" = "emergency" ]; then
        printf 'local-release\n'
      else
        printf 'verify\n'
      fi
      ;;
    build)
      printf 'verify\n'
      ;;
    verify)
      printf 'local-release\n'
      ;;
    release|local-release)
      printf 'complete\n'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

# Resolve worktree, state file, maintain mode, pending gate commit, and target phase.
gd_resolve_context() {
  gd_rc_step="$1"
  gd_feature="$2"
  gd_arg_maint="${3:-0}"
  gd_arg_tier="${4:-}"
  gd_arg_reopen="${5:-0}"

  gd_validate_slug "$gd_rc_step" "$gd_feature"
  if [ -n "$gd_arg_tier" ]; then
    gd_validate_tier_arg "$gd_rc_step" "$gd_arg_tier"
  fi
  gc_to_root "$gd_rc_step"

  [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
    || gc_refuse "$gd_rc_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first"

  # Locate primary worktree and any linked feature/<slug> or maintain/<slug> worktree
  gd_main_wt="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10); exit }')"
  [ -n "$gd_main_wt" ] || gd_main_wt="$(pwd)"
  gd_wt_feat="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${gd_feature}" '
    /^worktree / { path = substr($0, 10) }
    $0 == want { print path; exit }
  ')"
  gd_wt_maint="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/maintain/${gd_feature}" '
    /^worktree / { path = substr($0, 10) }
    $0 == want { print path; exit }
  ')"

  gd_is_maintain="$gd_arg_maint"
  if [ "$gd_is_maintain" != 1 ]; then
    if [ -n "$gd_wt_maint" ] || [ -f "docs/agents-v0/maintain/${gd_feature}/state.json" ] || [ -f "$gd_main_wt/docs/agents-v0/maintain/${gd_feature}/state.json" ]; then
      if [ -z "$gd_wt_feat" ] && [ ! -f "docs/agents-v0/requirements/${gd_feature}.state.json" ] && [ ! -f "$gd_main_wt/docs/agents-v0/requirements/${gd_feature}.state.json" ]; then
        gd_is_maintain=1
      fi
    fi
  fi

  if [ "$gd_arg_tier" = "trivial" ]; then
    gc_refuse "$gd_rc_step" "trivial tier changes do not use the full /v0-deliver pipeline; run /v0-triage or /v0-maintain $gd_feature --tier trivial instead"
  fi
  if [ "$gd_arg_tier" = "emergency" ] && [ "$gd_is_maintain" != 1 ]; then
    gc_refuse "$gd_rc_step" "emergency hotfixes start at /v0-maintain $gd_feature --tier emergency (or pass --maintain to /v0-deliver $gd_feature --maintain)"
  fi

  if [ "$gd_is_maintain" = 1 ]; then
    gd_rel_state="docs/agents-v0/maintain/${gd_feature}/state.json"
    gd_rel_art="docs/agents-v0/maintain/${gd_feature}/note.md"
    gd_rel_res="docs/agents-v0/maintain/${gd_feature}/phase-result.md"
    if [ -n "$gd_wt_maint" ] && [ -d "$gd_wt_maint" ]; then
      gd_work_dir="$gd_wt_maint"
    else
      gd_work_dir="$(pwd)"
    fi
  else
    gd_rel_state="docs/agents-v0/requirements/${gd_feature}.state.json"
    gd_rel_art="docs/agents-v0/requirements/${gd_feature}.md"
    gd_rel_res="docs/agents-v0/requirements/${gd_feature}.phase-result.md"
    if [ -n "$gd_wt_feat" ] && [ -d "$gd_wt_feat" ] && [ -f "$gd_wt_feat/$gd_rel_state" ]; then
      gd_work_dir="$gd_wt_feat"
    elif [ ! -f "$gd_rel_state" ] && [ -f "$gd_main_wt/$gd_rel_state" ]; then
      gd_work_dir="$gd_main_wt"
    else
      gd_work_dir="$(pwd)"
    fi
  fi

  # Check if already released on integration branch or in worktree
  for gd_chk_st in "$gd_main_wt/$gd_rel_state" "$gd_work_dir/$gd_rel_state"; do
    if [ -f "$gd_chk_st" ]; then
      gd_chk_apps=" $(gc_state_get "$gd_chk_st" approvedPhases 2>/dev/null | tr -d '[]",') "
      case "$gd_chk_apps" in
        *" release "*|*" local-release "*)
          gd_chk_tier="$(gc_state_get "$gd_chk_st" tier 2>/dev/null || true)"
          if [ "$gd_is_maintain" = 1 ] && [ "$gd_chk_tier" = "emergency" ]; then
            case "$gd_chk_apps" in
              *" verify "*) ;;
              *)
                gc_refuse "$gd_rc_step" "emergency maintenance note '$gd_feature' is already released and owes post-facto Verify; run /v0-verify $gd_feature --maintain"
                ;;
            esac
          fi
          gc_refuse "$gd_rc_step" "story '$gd_feature' is already released (release is in approvedPhases in $gd_rel_state); do not reopen a released story — start a new feature at /v0-intake or a maintenance note at /v0-maintain"
          ;;
      esac
    fi
  done

  # Brownfield onboarding check (checked against worktree or main repo)
  if (cd "$gd_main_wt" && gd_is_brownfield); then
    if [ -f "$gd_main_wt/docs/agents-v0/onboarding/baseline-status.json" ]; then
      gd_bs_ok="$(GD_BS="$gd_main_wt/docs/agents-v0/onboarding/baseline-status.json" python3 - <<'PYBS'
import json, os
try:
    d = json.load(open(os.environ["GD_BS"], encoding="utf-8"))
    print("1" if d.get("ok") is True else "0")
except Exception:
    print("0")
PYBS
)"
      [ "$gd_bs_ok" = "1" ] \
        || gc_refuse "$gd_rc_step" "brownfield baseline check failed in docs/agents-v0/onboarding/baseline-status.json (ok != true); fix baseline or complete /v0-onboard first"
    fi
    [ -f "$gd_main_wt/docs/agents-v0/onboarding/state.json" ] \
      || gc_refuse "$gd_rc_step" "brownfield onboarding state missing (docs/agents-v0/onboarding/state.json); complete /v0-onboard first"
    case " $(gc_state_get "$gd_main_wt/docs/agents-v0/onboarding/state.json" approvedPhases | tr -d '[]",') " in
      *" onboard "*) ;;
      *) gc_refuse "$gd_rc_step" "brownfield onboarding is not approved in docs/agents-v0/onboarding/state.json; complete /v0-onboard first" ;;
    esac
    if ! gd_onb_ok="$(cd "$gd_main_wt" && gc_approval_ok onboard)"; then
      gc_refuse "$gd_rc_step" "external onboard approval record missing or mismatched ($gd_onb_ok); complete /v0-onboard first"
    fi
  fi

  # Cross-story uncommitted collision check in the active worktree
  gd_collision="$(GD_SLUG="$gd_feature" GD_WD="$gd_work_dir" python3 - <<'PYCOL'
import os, re, subprocess
slug = os.environ["GD_SLUG"]
wd = os.environ["GD_WD"]
out = subprocess.run(["git", "-C", wd, "status", "--porcelain=v1", "-uall"], capture_output=True, text=True, check=False).stdout
bad = []
for line in out.splitlines():
    if len(line) < 4:
        continue
    p = line[3:].split(" -> ")[-1].strip('"')
    if p.endswith(".lock"):
        continue
    m_req = re.match(r"^docs/agents-v0/requirements/([a-z0-9][a-z0-9-]*)\.(?:md|state\.json|phase-result\.md|trace\.json)$", p)
    if m_req and m_req.group(1) != slug:
        bad.append(p)
        continue
    m_sub = re.match(r"^docs/agents-v0/(?:design|build|verify|release|maintain)/([a-z0-9][a-z0-9-]*)/", p)
    if m_sub and m_sub.group(1) != slug:
        bad.append(p)
        continue
if bad:
    print(", ".join(bad[:5]))
PYCOL
)"
  [ -z "$gd_collision" ] \
    || gc_refuse "$gd_rc_step" "working tree holds uncommitted files belonging to another story/note ($gd_collision); commit or stash them before running /v0-deliver $gd_feature"

  gd_state_full="$gd_work_dir/$gd_rel_state"
  gd_art_full="$gd_work_dir/$gd_rel_art"
  gd_res_full="$gd_work_dir/$gd_rel_res"

  gd_eff_tier="${gd_arg_tier:-standard}"
  gd_active_phase=""
  gd_active_status=""
  gd_last_approved=""
  gd_pending_commit_phase=""
  gd_target_phase=""

  if [ -f "$gd_state_full" ]; then
    gd_st_tier="$(gc_state_get "$gd_state_full" tier 2>/dev/null || true)"
    [ -z "$gd_st_tier" ] || gd_eff_tier="$gd_st_tier"
    if [ "$gd_eff_tier" = "trivial" ]; then
      gc_refuse "$gd_rc_step" "story '$gd_feature' has tier 'trivial' in $gd_rel_state; run /v0-triage or /v0-maintain $gd_feature --tier trivial instead of /v0-deliver"
    fi
    if [ "$gd_eff_tier" = "emergency" ] && [ "$gd_is_maintain" != 1 ]; then
      gc_refuse "$gd_rc_step" "story '$gd_feature' has tier 'emergency'; emergency hotfixes use /v0-maintain $gd_feature --tier emergency (or /v0-deliver $gd_feature --maintain)"
    fi
    gd_active_phase="$(gc_state_get "$gd_state_full" activePhase 2>/dev/null || true)"
    [ "$gd_active_phase" != "release" ] || gd_active_phase="local-release"
    gd_active_status="$(gc_state_get "$gd_state_full" activeStatus 2>/dev/null || true)"
    gd_last_approved="$(gc_state_get "$gd_state_full" lastApprovedPhase 2>/dev/null || true)"
    [ "$gd_last_approved" != "release" ] || gd_last_approved="local-release"
  fi

  # Determine pending gate commit vs active/next target phase
  if [ "$gd_active_status" = "awaiting_approval" ]; then
    gd_wait_p="${gd_active_phase:-$gd_last_approved}"
    [ -n "$gd_wait_p" ] || gd_wait_p="intake"
    if (cd "$gd_work_dir" && gc_approval_ok "$gd_wait_p" "$gd_feature" >/dev/null 2>&1); then
      gd_pending_commit_phase="$gd_wait_p"
      gd_target_phase="$(gd_next_phase_after "$gd_wait_p" "$gd_is_maintain" "$gd_eff_tier")"
    else
      if [ "$gd_rc_step" = "check" ] || [ "$gd_rc_step" = "start" ] || [ "$gd_rc_step" = "commit" ]; then
        gc_refuse "$gd_rc_step" "$gd_wait_p for '$gd_feature' is awaiting_approval; the user must approve in their own terminal outside Cursor first: sh .agents-v0/scripts/guard-common.sh approve $gd_wait_p $gd_feature (or: sh .agents-v0/scripts/guard-common.sh approve deliver $gd_feature)"
      fi
      gd_target_phase="$gd_wait_p"
    fi
  elif [ "$gd_active_status" = "in_progress" ] || [ "$gd_active_status" = "blocked" ]; then
    gd_target_phase="${gd_active_phase:-$(gd_next_phase_after "$gd_last_approved" "$gd_is_maintain" "$gd_eff_tier")}"
  else
    # activeStatus is empty: check if Contract: None design or lastApprovedPhase was approved by the user but not yet gate-committed
    if [ -f "$gd_res_full" ] && grep -Fq "phase: design" "$gd_res_full" && grep -Fq "status: contract_none" "$gd_res_full"; then
      if [ -n "$(git -C "$gd_work_dir" status --porcelain -- "$gd_rel_state" "$gd_rel_res" "docs/agents-v0/design/${gd_feature}" 2>/dev/null || true)" ]; then
        gd_pending_commit_phase="design"
      fi
      if [ "$gd_last_approved" = "intake" ] || [ "$gd_last_approved" = "design" ]; then
        gd_target_phase="build"
      else
        gd_target_phase="$(gd_next_phase_after "$gd_last_approved" "$gd_is_maintain" "$gd_eff_tier")"
      fi
    elif [ -n "$gd_last_approved" ] && [ -f "$gd_res_full" ] && grep -Fq "status: awaiting_approval" "$gd_res_full"; then
      # The user ran `guard-common.sh approve <phase> <feature>` (which cleared activeStatus in state.json),
      # and `guard-<phase>.sh commit <feature>` has not been run yet.
      if (cd "$gd_work_dir" && gc_approval_ok "$gd_last_approved" "$gd_feature" >/dev/null 2>&1); then
        gd_pending_commit_phase="$gd_last_approved"
        gd_target_phase="$(gd_next_phase_after "$gd_last_approved" "$gd_is_maintain" "$gd_eff_tier")"
      else
        gc_refuse "$gd_rc_step" "$gd_last_approved is marked approved in $gd_rel_state without a matching external approval record; the user must run: sh .agents-v0/scripts/guard-common.sh approve $gd_last_approved $gd_feature"
      fi
    else
      gd_target_phase="$(gd_next_phase_after "$gd_last_approved" "$gd_is_maintain" "$gd_eff_tier")"
    fi
  fi
}

gd_parse_check_start_args() {
  gd_p_step="$1"
  shift
  gd_p_slug=""
  gd_p_maint=0
  gd_p_tier=""
  gd_p_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        gd_p_maint=1
        shift
        ;;
      --tier)
        [ $# -ge 2 ] || gc_refuse "$gd_p_step" "--tier requires a value (trivial, standard, emergency, or major)"
        gd_p_tier="$2"
        shift 2
        ;;
      --tier=*)
        gd_p_tier="${1#--tier=}"
        shift
        ;;
      --reopen)
        gd_p_reopen=1
        shift
        ;;
      -*)
        gd_usage
        ;;
      *)
        [ -z "$gd_p_slug" ] || gd_usage
        gd_p_slug="$1"
        shift
        ;;
    esac
  done
  [ -n "$gd_p_slug" ] || gc_refuse "$gd_p_step" "missing <feature> slug; usage: $G $gd_p_step <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]"
}

gd_check() {
  gd_parse_check_start_args check "$@"
  gd_resolve_context check "$gd_p_slug" "$gd_p_maint" "$gd_p_tier" "$gd_p_reopen"

  gd_m_flag=""
  [ "$gd_is_maintain" != 1 ] || gd_m_flag=" --maintain"

  if [ -n "$gd_pending_commit_phase" ]; then
    gc_ok check "$gd_pending_commit_phase for $gd_feature is approved and ready to commit in $gd_work_dir; next phase: $gd_target_phase"
    printf 'Next: %s start %s%s\n' "$G" "$gd_feature" "$gd_m_flag"
    return 0
  fi

  [ "$gd_target_phase" != "complete" ] \
    || gc_refuse check "story '$gd_feature' has already completed local-release"
  [ "$gd_target_phase" != "unknown" ] \
    || gc_refuse check "cannot resolve next phase for '$gd_feature' from lastApprovedPhase='$gd_last_approved'"

  # Delegate prerequisite check to the target phase guard inside the resolved worktree
  gd_sub_args="$gd_feature"
  if [ "$gd_is_maintain" = 1 ] && [ "$gd_target_phase" != "maintain" ]; then
    gd_sub_args="$gd_sub_args --maintain"
  fi
  if [ "$gd_target_phase" = "maintain" ] && [ -n "$gd_p_tier" ]; then
    gd_sub_args="$gd_sub_args --tier $gd_p_tier"
  fi
  if [ "$gd_p_reopen" = 1 ]; then
    gd_sub_args="$gd_sub_args --reopen"
  fi

  # shellcheck disable=SC2086
  if ! gd_sub_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-${gd_target_phase}.sh" check $gd_sub_args 2>&1)"; then
    printf '%s\n' "$gd_sub_out"
    exit 1
  fi
  printf '%s\n' "$gd_sub_out"
  gc_ok check "deliver ($gd_feature) routed to phase '$gd_target_phase' in $gd_work_dir"
  printf 'Next: %s start %s%s\n' "$G" "$gd_feature" "$gd_m_flag"
}

# Design: DDL2 (/v0-deliver start with auto-commit of approved prior gate, worktree delegation, and block).
gd_mark_deliver_managed() {
  gd_mdm_st="$1"
  gd_mdm_tier="${2:-}"
  [ -f "$gd_mdm_st" ] || return 0
  GD_ST="$gd_mdm_st" GD_TIER="$gd_mdm_tier" python3 - <<'PYMDM'
import fcntl, json, os
st_path = os.environ["GD_ST"]
tier = os.environ.get("GD_TIER", "")
lock = open(st_path + ".lock", "w", encoding="utf-8")
fcntl.flock(lock, fcntl.LOCK_EX)
try:
    d = json.load(open(st_path, encoding="utf-8"))
    d["deliverGuardManaged"] = True
    if tier in ("standard", "emergency", "major"):
        d["tier"] = tier
    with open(st_path, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
finally:
    fcntl.flock(lock, fcntl.LOCK_UN)
    lock.close()
PYMDM
}

gd_start() {
  gd_parse_check_start_args start "$@"
  gd_resolve_context start "$gd_p_slug" "$gd_p_maint" "$gd_p_tier" "$gd_p_reopen"

  gd_m_flag=""
  [ "$gd_is_maintain" != 1 ] || gd_m_flag=" --maintain"

  # FDL2 / DDL2: If prior phase is approved externally (or Contract: None design ready) and uncommitted, auto-commit it first!
  if [ -n "$gd_pending_commit_phase" ]; then
    if [ "$gd_active_status" = "awaiting_approval" ] && [ "$gd_pending_commit_phase" != "local-release" ]; then
      case " $(gc_state_get "$gd_state_full" approvedPhases 2>/dev/null | tr -d '[]",') " in
        *" $gd_pending_commit_phase "*) ;;
        *)
          (cd "$gd_work_dir" && gc_state_set "$gd_rel_state" "$gd_feature" "$gd_rel_art" \
            "approvePhase=$gd_pending_commit_phase" "activePhase=" "activeStatus=" "blockedReason=" "nextStep=") || exit 1
          ;;
      esac
    fi
    gd_cm_args="$gd_feature"
    if [ "$gd_is_maintain" = 1 ] && [ "$gd_pending_commit_phase" != "maintain" ]; then
      gd_cm_args="$gd_cm_args --maintain"
    fi
    # shellcheck disable=SC2086
    if ! gd_cm_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-${gd_pending_commit_phase}.sh" commit $gd_cm_args 2>&1)"; then
      printf '%s\n' "$gd_cm_out"
      exit 1
    fi
    printf '%s\n' "$gd_cm_out"

    if [ "$gd_pending_commit_phase" = "local-release" ]; then
      gc_ok start "deliver ($gd_feature) auto-committed local-release; story delivery is COMPLETE"
      printf 'Next: /v0-status\n'
      return 0
    fi

    # Re-resolve context after committing the gate (e.g., intake commit creates feature/<feature> worktree)
    gd_resolve_context start "$gd_p_slug" "$gd_p_maint" "$gd_p_tier" "$gd_p_reopen"
  fi

  [ "$gd_target_phase" != "complete" ] \
    || gc_refuse start "story '$gd_feature' has already completed local-release"
  [ "$gd_target_phase" != "unknown" ] \
    || gc_refuse start "cannot resolve next phase for '$gd_feature' from lastApprovedPhase='$gd_last_approved'"

  # If activeStatus is already in_progress for the target phase (and not --reopen), resume cleanly without failing on dirty phase files
  if [ "$gd_active_status" = "in_progress" ] && [ "$gd_active_phase" = "$gd_target_phase" ] && [ "$gd_p_reopen" = 0 ]; then
    gd_mark_deliver_managed "$gd_state_full" "$gd_p_tier"
    gc_ok start "deliver ($gd_feature) resumed in-progress phase '$gd_target_phase' in $gd_work_dir"
    printf 'Next: Execute phase '\''%s'\'' in %s, then run: %s ready %s%s\n' "$gd_target_phase" "$gd_work_dir" "$G" "$gd_feature" "$gd_m_flag"
    return 0
  fi

  gd_st_args="$gd_feature"
  if [ "$gd_is_maintain" = 1 ] && [ "$gd_target_phase" != "maintain" ]; then
    gd_st_args="$gd_st_args --maintain"
  fi
  if [ "$gd_target_phase" = "maintain" ] && [ -n "$gd_p_tier" ]; then
    gd_st_args="$gd_st_args --tier $gd_p_tier"
  fi
  if [ "$gd_p_reopen" = 1 ]; then
    gd_st_args="$gd_st_args --reopen"
  fi

  # shellcheck disable=SC2086
  if ! gd_st_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-${gd_target_phase}.sh" start $gd_st_args 2>&1)"; then
    printf '%s\n' "$gd_st_out"
    exit 1
  fi
  printf '%s\n' "$gd_st_out"

  # Refresh worktree path in case guard-maintain.sh start provisioned maintain/<feature>
  gd_resolve_context start "$gd_p_slug" "$gd_p_maint" "$gd_p_tier" 0
  gd_mark_deliver_managed "$gd_state_full" "$gd_p_tier"

  gc_ok start "deliver ($gd_feature) started phase '$gd_target_phase' in $gd_work_dir"
  printf 'Next: Execute phase '\''%s'\'' in %s, then run: %s ready %s%s\n' "$gd_target_phase" "$gd_work_dir" "$G" "$gd_feature" "$gd_m_flag"
}

gd_block() {
  gd_b_slug=""
  gd_b_reason=""
  gd_b_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        gd_b_maint=1
        shift
        ;;
      -*)
        gd_usage
        ;;
      *)
        if [ -z "$gd_b_slug" ]; then
          gd_b_slug="$1"
        elif [ -z "$gd_b_reason" ]; then
          gd_b_reason="$1"
        else
          gd_b_reason="$gd_b_reason $1"
        fi
        shift
        ;;
    esac
  done
  [ -n "$gd_b_slug" ] || gc_refuse block "missing <feature> slug; usage: $G block <feature> \"<reason>\" [--maintain]"
  [ -n "$(printf '%s' "$gd_b_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason"

  gd_resolve_context block "$gd_b_slug" "$gd_b_maint" "" 0
  [ -f "$gd_state_full" ] || gc_refuse block "deliver for '$gd_feature' has not been started ($gd_rel_state missing)"
  gd_b_phase="${gd_active_phase:-$gd_target_phase}"
  [ -n "$gd_b_phase" ] && [ "$gd_b_phase" != "complete" ] && [ "$gd_b_phase" != "unknown" ] \
    || gc_refuse block "no active phase to block for '$gd_feature'"

  if [ "$gd_b_phase" = "local-release" ] && [ "$gd_is_maintain" = 1 ]; then
    if ! gd_b_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-local-release.sh" block "$gd_feature" "$gd_b_reason" --maintain 2>&1)"; then
      printf '%s\n' "$gd_b_out"
      exit 1
    fi
  else
    if ! gd_b_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-${gd_b_phase}.sh" block "$gd_feature" "$gd_b_reason" 2>&1)"; then
      printf '%s\n' "$gd_b_out"
      exit 1
    fi
  fi
  printf '%s\n' "$gd_b_out"
  gd_m_flag=""
  [ "$gd_is_maintain" != 1 ] || gd_m_flag=" --maintain"
  gc_ok block "deliver ($gd_feature) blocked in phase '$gd_b_phase' ($gd_b_reason)"
  printf 'Next: Resolve the blocker, then run: %s start %s%s\n' "$G" "$gd_feature" "$gd_m_flag"
}

# Design: DDL3 (/v0-deliver ready delegation, Contract: None auto-commit & fast-forward, and Verify bounce propagation).
gd_ready() {
  gd_r_slug=""
  gd_r_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        gd_r_maint=1
        shift
        ;;
      -*)
        gd_usage
        ;;
      *)
        [ -z "$gd_r_slug" ] || gd_usage
        gd_r_slug="$1"
        shift
        ;;
    esac
  done
  [ -n "$gd_r_slug" ] || gc_refuse ready "missing <feature> slug; usage: $G ready <feature> [--maintain]"

  gd_resolve_context ready "$gd_r_slug" "$gd_r_maint" "" 0
  [ -f "$gd_state_full" ] || gc_refuse ready "deliver for '$gd_feature' has not been started ($gd_rel_state missing)"
  [ "$gd_active_status" = "in_progress" ] && [ -n "$gd_active_phase" ] \
    || gc_refuse ready "deliver for '$gd_feature' is not in_progress (activePhase='${gd_active_phase:-none}', activeStatus='${gd_active_status:-none}'); run $G start $gd_feature first"

  gd_r_args="$gd_feature"
  if [ "$gd_is_maintain" = 1 ] && [ "$gd_active_phase" != "maintain" ]; then
    gd_r_args="$gd_r_args --maintain"
  fi

  # shellcheck disable=SC2086
  if ! gd_r_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-${gd_active_phase}.sh" ready $gd_r_args 2>&1)"; then
    printf '%s\n' "$gd_r_out"
    exit 1
  fi
  printf '%s\n' "$gd_r_out"

  # FDL6 / DDL3: When design qualifies for Contract: None, guard-design.sh ready writes status: contract_none.
  # Auto-commit Contract: None design and route directly to build (`guard-deliver.sh start <feature>`).
  if [ "$gd_active_phase" = "design" ] && [ -f "$gd_res_full" ] \
    && grep -Fq "phase: design" "$gd_res_full" && grep -Fq "status: contract_none" "$gd_res_full"; then
    if ! gd_cn_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-design.sh" commit "$gd_feature" 2>&1)"; then
      printf '%s\n' "$gd_cn_out"
      exit 1
    fi
    printf '%s\n' "$gd_cn_out"
    gc_ok ready "deliver ($gd_feature) design (Contract: None) verified and auto-committed; proceed directly to build"
    printf 'Next: %s start %s\n' "$G" "$gd_feature"
    return 0
  fi

  gc_ok ready "deliver ($gd_feature) phase '$gd_active_phase' is awaiting_approval in $gd_work_dir"
  printf 'Next: The user reviews the %s deliverables and runs, in their own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve %s %s (or: sh .agents-v0/scripts/guard-common.sh approve deliver %s)\n' \
    "$gd_active_phase" "$gd_active_phase" "$gd_feature" "$gd_feature"
}

# Design: DDL5 (/v0-deliver commit delegation with external approval verification and next-phase routing).
gd_commit() {
  gd_c_slug=""
  gd_c_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        gd_c_maint=1
        shift
        ;;
      -*)
        gd_usage
        ;;
      *)
        [ -z "$gd_c_slug" ] || gd_usage
        gd_c_slug="$1"
        shift
        ;;
    esac
  done
  [ -n "$gd_c_slug" ] || gc_refuse commit "missing <feature> slug; usage: $G commit <feature> [--maintain]"

  gd_resolve_context commit "$gd_c_slug" "$gd_c_maint" "" 0
  [ -f "$gd_state_full" ] || gc_refuse commit "deliver for '$gd_feature' has not been started ($gd_rel_state missing)"
  [ -n "$gd_pending_commit_phase" ] \
    || gc_refuse commit "no approved uncommitted gate found for '$gd_feature' (activePhase='${gd_active_phase:-none}', activeStatus='${gd_active_status:-none}', lastApprovedPhase='${gd_last_approved:-none}'); run $G ready $gd_feature and have the user approve first"

  gd_c_phase="$gd_pending_commit_phase"

  gd_c_args="$gd_feature"
  if [ "$gd_is_maintain" = 1 ] && [ "$gd_c_phase" != "maintain" ]; then
    gd_c_args="$gd_c_args --maintain"
  fi

  # shellcheck disable=SC2086
  if ! gd_c_out="$(cd "$gd_work_dir" && sh "$GC_HERE/guard-${gd_c_phase}.sh" commit $gd_c_args 2>&1)"; then
    printf '%s\n' "$gd_c_out"
    exit 1
  fi
  printf '%s\n' "$gd_c_out"

  gd_m_flag=""
  [ "$gd_is_maintain" != 1 ] || gd_m_flag=" --maintain"

  if [ "$gd_c_phase" = "local-release" ]; then
    gc_ok commit "deliver ($gd_feature) committed local-release; story delivery is COMPLETE"
    printf 'Next: /v0-status\n'
    return 0
  fi

  gc_ok commit "deliver ($gd_feature) committed phase '$gd_c_phase'; next phase is '$gd_target_phase'"
  printf 'Next: %s start %s%s\n' "$G" "$gd_feature" "$gd_m_flag"
}

# Design: DDL6 (/v0-deliver generated step block).
gd_steps() {
  [ $# -eq 0 ] || gd_usage
  gd_rule steps ready.next; gd_ready_next="$gd_val"
  gd_rule steps approved.next; gd_approved_next="$gd_val"
  G='sh .agents-v0/scripts/guard-deliver.sh'
  cat <<EOF_STEPS
1. Run \`$G check <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]\`. It validates the \`<feature>\` slug, blocks \`p0-a*\` (redirecting to \`/v0-scaffold\`), routes \`--tier trivial\` to \`/v0-triage\` and \`--tier emergency\` (without \`--maintain\`) to \`/v0-maintain <id> --tier emergency\`, checks brownfield \`onboard\` approval (\`docs/agents-v0/onboarding/state.json\` + \`baseline-status.json\`), checks cross-story uncommitted collisions, resolves the linked worktree (\`feature/<feature>\` or \`maintain/<id>\`), refuses if the story is already released, and delegates prerequisite checks to the active/next phase guard (\`intake\` → \`design\` → \`build\` → \`verify\` → \`local-release\`, or \`maintain\` → \`verify\` → \`local-release\`). If a phase is at \`awaiting_approval\` without the user's external approval record, it refuses and prints the exact external \`approve\` command. When it prints \`REFUSED\`, show its message and stop.
2. Run \`$G start <feature> [--maintain] [--tier trivial|standard|emergency|major] [--reopen]\`. When the prior phase was externally approved by the user in their own terminal (or \`Contract: None\` design is ready), \`start\` automatically executes \`guard-<prev_phase>.sh commit <feature>\` inside the resolved worktree before starting the next phase. It then delegates \`start\` to the active phase guard (\`guard-intake.sh\`, \`guard-design.sh\`, \`guard-build.sh\`, \`guard-verify.sh\`, \`guard-local-release.sh\`, or \`guard-maintain.sh\`) in the story's worktree and sets \`"deliverGuardManaged": true\` in the state file.
3. Read \`docs/agents-v0/lessons.md\`, optionally consult the shell-less \`orchestrator\` subagent for routing/status advice, and execute the active phase's work in the resolved worktree by following that phase's command (\`/v0-intake\`, \`/v0-design\`, \`/v0-build\`, \`/v0-verify\`, \`/v0-local-release\`, or \`/v0-maintain\`) and launching its shell-less specialist subagents (\`requirements-analyst\`, \`schema-author\`, \`solution-architect\`, \`ux-designer\`, \`design-reviewer\`, \`backend-engineer\`, \`bff-engineer\`, \`frontend-engineer\`, \`test-engineer\`, \`security-reviewer\`, \`code-reviewer\`, \`release-manager\`, \`maintenance-engineer\`).
4. If a subagent writes a \`helper-brief.md\` or \`failure-brief.md\` or hits a phase blocker, run \`$G block <feature> "<plain reason>" [--maintain]\` (which delegates to the active phase guard's \`block\` subcommand with SHA-256 brief deduplication). Launch the requested shell-less helper (\`explore-researcher\`, \`schema-author\`, \`debug-investigator\`, \`docs-author\`), pass its findings back, remove the brief, and resume via Step 2; otherwise stop and escalate to the user.
5. When the active phase's artifacts and verification evidence are complete, run \`$G ready <feature> [--maintain]\`. It delegates validation to \`guard-<active_phase>.sh ready <feature>\` inside the story's worktree:
   - **\`Contract: None\` in Design:** When the story qualifies for the \`Contract: None\` shortcut, \`ready\` auto-commits \`"<story>: design (Contract: None)"\` on \`feature/<feature>\` and prints \`Next: $G start <feature>\`; loop immediately back to Step 2 to start \`build\`.
   - **Verify Critical bounce:** When \`verify\` finds any Open \`Critical\` issue, \`ready\` automatically bounces the story to \`build\` (\`--reopen build\` or \`--reopen maintain\`) and exits non-zero; report the bounce and stop.
   - **Standard phase gate:** Otherwise \`ready\` sets \`activeStatus\` to \`awaiting_approval\` and prints the user's external approval command. When it prints \`REFUSED\`, fix what it names and run \`ready\` again.
6. Stop at the gate. Present the phase summary and artifacts to the user and wait for explicit approval. Next: $gd_ready_next. Never run \`approve\` yourself; the agent cannot approve any gate.
7. After the user runs \`approve\` in their own terminal outside Cursor, either run \`$G commit <feature> [--maintain]\` (which verifies the user's external approval record, delegates the safe-staged gate commit to \`guard-<phase>.sh commit <feature>\` in the worktree, and prints \`Next: $G start <feature>\` or \`COMPLETE\` after \`local-release\`) or re-run \`$gd_approved_next\` (where Step 2 automatically commits the approved gate and starts the next phase).
EOF_STEPS
}

cmd="${1:-}"
case "$cmd" in
  check) shift; gd_check "$@" ;;
  start) shift; gd_start "$@" ;;
  block) shift; gd_block "$@" ;;
  ready) shift; gd_ready "$@" ;;
  commit) shift; gd_commit "$@" ;;
  steps) shift; gd_steps "$@" ;;
  *) gd_usage ;;
esac
