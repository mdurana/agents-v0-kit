#!/bin/sh
# guard-maintain.sh — single entry point and security boundary for /v0-maintain.
# Usage:
#   sh .agents-v0/scripts/guard-maintain.sh check <id> [--tier trivial|standard|emergency] [--reopen]
#   sh .agents-v0/scripts/guard-maintain.sh start <id> [--tier trivial|standard|emergency] [--reopen]
#   sh .agents-v0/scripts/guard-maintain.sh block <id> "<reason>"
#   sh .agents-v0/scripts/guard-maintain.sh ready <id>
#   sh .agents-v0/scripts/guard-maintain.sh commit <id>
#   sh .agents-v0/scripts/guard-maintain.sh steps
#
# Design: DM1 (/v0-maintain guard and parameterized per-note maintenance gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-maintain.sh"

gm_usage() {
  printf 'usage: %s check <id> [--tier trivial|standard|emergency] [--reopen]\n' "$G" >&2
  printf '       %s start <id> [--tier trivial|standard|emergency] [--reopen]\n' "$G" >&2
  printf '       %s block <id> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <id>\n' "$G" >&2
  printf '       %s commit <id>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gm_validate_slug() {
  gm_v_step="$1"
  gm_v_slug="${2:-}"
  [ -n "$gm_v_slug" ] || gc_refuse "$gm_v_step" "missing <id> slug; pass a lowercase maintenance id (e.g. fix-login-500)"
  case "$gm_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gm_v_step" "maintenance id '$gm_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gm_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gm_v_step" "maintenance id '$gm_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gm_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gm_v_step" "story '$gm_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-maintain"
      ;;
  esac
}

gm_validate_tier_arg() {
  gm_vt_step="$1"
  gm_vt_tier="$2"
  case "$gm_vt_tier" in
    trivial|standard|emergency) ;;
    *) gc_refuse "$gm_vt_step" "invalid --tier '$gm_vt_tier'; must be one of: trivial, standard, emergency" ;;
  esac
}

gm_rule() {
  gm_step="$1"
  gm_key="$2"
  gm_slug="${3:-}"
  gm_rules="${GC_HERE}/../gate-rules"
  [ -f "$gm_rules" ] || gc_refuse "$gm_step" "missing gate-rules file ($gm_rules)"
  gm_val="$(awk -v p="maintain" -v k="$gm_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gm_rules")"
  [ -n "$gm_val" ] || gc_refuse "$gm_step" "gate-rules missing key '$gm_key' for phase 'maintain'"
  if [ -n "$gm_slug" ]; then
    gm_val="$(printf '%s' "$gm_val" | sed "s/<feature>/$gm_slug/g")"
  fi
}

gm_load() {
  gm_step="$1"
  gm_slug="$2"
  gm_tier_arg="${3:-}"
  gm_validate_slug "$gm_step" "$gm_slug"
  if [ -n "$gm_tier_arg" ]; then
    gm_validate_tier_arg "$gm_step" "$gm_tier_arg"
  fi
  gc_to_root "$gm_step"
  gm_rule "$gm_step" phase "$gm_slug"; gm_phase="$gm_val"
  gm_rule "$gm_step" feature "$gm_slug"; gm_feature="$gm_val"
  gm_rule "$gm_step" state "$gm_slug"; gm_state="$gm_val"
  gm_rule "$gm_step" artifact "$gm_slug"; gm_artifact="$gm_val"
  gm_rule "$gm_step" template "$gm_slug"; gm_template="$gm_val"
  gm_rule "$gm_step" report "$gm_slug"; gm_report="$gm_val"
  gm_rule "$gm_step" output "$gm_slug"; gm_output="$gm_val"
  gm_rule "$gm_step" result "$gm_slug"; gm_result="$gm_val"

  gm_eff_tier="$gm_tier_arg"
  if [ -z "$gm_eff_tier" ] && [ -f "$gm_state" ]; then
    gm_st_tier="$(gc_state_get "$gm_state" tier 2>/dev/null || true)"
    case "$gm_st_tier" in
      trivial|standard|emergency) gm_eff_tier="$gm_st_tier" ;;
    esac
  fi
  if [ -z "$gm_eff_tier" ] && [ -f "$gm_artifact" ]; then
    gm_note_tier="$(GM_NOTE="$gm_artifact" python3 - <<'PYNT'
import os, re
txt = open(os.environ["GM_NOTE"], encoding="utf-8").read()
txt = re.sub(r"<!--.*?-->", "", txt, flags=re.S)
m = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Tier(?:\*\*)?\s*:\s*`?(trivial|standard|emergency)`?\b", txt)
if m:
    print(m.group(1).lower())
PYNT
)"
    if [ -n "$gm_note_tier" ]; then
      gm_eff_tier="$gm_note_tier"
    fi
  fi
  [ -n "$gm_eff_tier" ] || gm_eff_tier="standard"
}

gm_is_brownfield() {
  [ -f docs/agents-v0/onboarding/state.json ] && return 0
  [ -f docs/agents-v0/onboarding/report.md ] && return 0
  return 1
}

gm_has_tier_confirmed() {
  gm_htc_note="$1"
  [ -f "$gm_htc_note" ] || return 1
  gm_htc_ok="$(GM_NOTE="$gm_htc_note" python3 - <<'PYTC'
import os, re
txt = open(os.environ["GM_NOTE"], encoding="utf-8").read()
txt = re.sub(r"<!--.*?-->", "", txt, flags=re.S)
for line in txt.splitlines():
    m = re.match(r"^\s*(?:-\s*)?(?:\*\*)?Tier\s+confirmed\s+by(?:\*\*)?\s*:\s*(.+?)\s*$", line, re.I)
    if m:
        val = m.group(1).strip()
        if val and not re.search(r"<[^>]+>", val) and val.lower() not in ("tbd", "todo", "n/a", "none"):
            print("1")
            break
PYTC
)"
  [ "$gm_htc_ok" = "1" ]
}

gm_check_prereqs() {
  gm_step="$1"
  gm_reqs="$2"
  gm_reopen="${3:-0}"
  gm_rule "$gm_step" approved.next "$gm_feature"; gm_approved_next="$gm_val"

  for gm_req in $gm_reqs; do
    case "$gm_req" in
      git-work-tree) ;;
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gm_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        if gm_is_brownfield; then
          [ -f docs/agents-v0/onboarding/state.json ] \
            || gc_refuse "$gm_step" "brownfield onboarding state missing (docs/agents-v0/onboarding/state.json); complete /v0-onboard first"
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$gm_step" "brownfield onboarding is not approved in docs/agents-v0/onboarding/state.json; complete /v0-onboard first" ;;
          esac
          if ! gm_onb_ok="$(gc_approval_ok onboard)"; then
            gc_refuse "$gm_step" "external onboard approval record missing or mismatched ($gm_onb_ok); complete /v0-onboard first"
          fi
        fi
        ;;
      no-collision)
        gm_collision="$(GM_SLUG="$gm_feature" python3 - <<'PYCOL'
import os, re, subprocess
slug = os.environ["GM_SLUG"]
out = subprocess.run(["git", "status", "--porcelain=v1", "-uall"], capture_output=True, text=True, check=False).stdout
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
    if m_sub and m_sub.group(1) != "system" and m_sub.group(1) != slug:
        bad.append(p)
if bad:
    print(", ".join(bad[:5]))
PYCOL
)"
        if [ -n "$gm_collision" ]; then
          gc_refuse "$gm_step" "uncommitted changes for another story detected in working tree ($gm_collision); resolve or stash them before running /v0-maintain $gm_feature"
        fi
        ;;
      not-released)
        if [ -f "$gm_state" ]; then
          case " $(gc_state_get "$gm_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              if [ "$gm_eff_tier" = "emergency" ]; then
                case " $(gc_state_get "$gm_state" approvedPhases | tr -d '[]",') " in
                  *" verify "*)
                    gc_refuse "$gm_step" "emergency maintenance note '$gm_feature' is already released and verified; start a new maintenance id"
                    ;;
                  *)
                    gm_act_st="$(gc_state_get "$gm_state" activeStatus 2>/dev/null || true)"
                    if [ "$gm_act_st" = "blocked" ]; then
                      gc_refuse "$gm_step" "emergency maintenance note '$gm_feature' was released and blocked on a Critical finding during follow-up Verify; start a new maintenance <id> instead of reopening '$gm_feature'"
                    fi
                    gc_refuse "$gm_step" "emergency maintenance note '$gm_feature' is already released and owes follow-up Verify; run /v0-verify $gm_feature --maintain"
                    ;;
                esac
              fi
              gc_refuse "$gm_step" "maintenance note '$gm_feature' is already released; start a new maintenance id"
              ;;
          esac
        fi
        ;;
      not-approved)
        if [ -f "$gm_state" ]; then
          case " $(gc_state_get "$gm_state" approvedPhases | tr -d '[]",') " in
            *" maintain "*)
              if [ "$gm_reopen" = 1 ]; then
                gm_rc="$(gc_state_get "$gm_state" reopenCount 2>/dev/null || echo 0)"
                case "$gm_rc" in ''|*[!0-9]*) gm_rc=0 ;; esac
                if [ "$gm_rc" -ge 3 ]; then
                  gc_refuse "$gm_step" "maintenance note '$gm_feature' has reached the maximum reopen cap (reopenCount=$gm_rc >= 3); write docs/agents-v0/maintain/$gm_feature/helper-brief.md and escalate to Sensei"
                fi
              else
                if [ "$gm_eff_tier" = "emergency" ]; then
                  gc_refuse "$gm_step" "maintain is already approved for emergency note '$gm_feature'; run /v0-local-release $gm_feature --maintain (or /v0-verify $gm_feature --maintain), or pass --reopen to reopen maintain"
                else
                  gc_refuse "$gm_step" "maintain is already approved for '$gm_feature'; suggest $gm_approved_next (or pass --reopen to reopen maintain)"
                fi
              fi
              ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ "$gm_reopen" != 1 ] && [ -f "$gm_state" ]; then
          if [ "$(gc_state_get "$gm_state" activePhase 2>/dev/null || true)" = "maintain" ] \
             && [ "$(gc_state_get "$gm_state" activeStatus 2>/dev/null || true)" = "awaiting_approval" ]; then
            gc_refuse "$gm_step" "maintain for '$gm_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve maintain $gm_feature in your external terminal"
          fi
        fi
        ;;
      maintain-branch)
        gm_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gm_skip_bg=1
        # <<< kit-test-override
        if [ "$gm_skip_bg" != 1 ]; then
          gm_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          gm_ib="main"
          if [ -x "$GC_HERE/resolve-integration-branch.sh" ]; then
            gm_ib="$(sh "$GC_HERE/resolve-integration-branch.sh" 2>/dev/null || echo main)"
            gm_ib="${gm_ib#origin/}"
          fi
          if [ "$gm_eff_tier" = "trivial" ]; then
            if [ -n "$gm_cur" ] && [ "$gm_ib" != "HEAD" ] && [ "$gm_cur" != "$gm_ib" ]; then
              gc_refuse "$gm_step" "trivial maintenance note '$gm_feature' must stay on the integration branch '$gm_ib' (current branch: '$gm_cur')"
            fi
            if [ -z "$gm_tier_arg" ] && [ -f "$gm_artifact" ] && ! gm_has_tier_confirmed "$gm_artifact"; then
              gc_refuse "$gm_step" "trivial maintenance note '$gm_feature' has no 'Tier confirmed by' line in '$gm_artifact'; run /v0-triage or pass --tier trivial after user confirmation"
            fi
          else
            if [ "$gm_cur" != "maintain/$gm_feature" ]; then
              gm_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/maintain/${gm_feature}" '
                /^worktree / { path = substr($0, 10) }
                $0 == want { print path; exit }
              ')"
              if [ -n "$gm_wt" ] && [ "$gm_wt" != "$(pwd)" ]; then
                gc_refuse "$gm_step" "maintenance note '$gm_feature' (tier: $gm_eff_tier) has an active worktree at '$gm_wt' on branch 'maintain/$gm_feature' (current branch: '${gm_cur:-detached}'). Open that folder and run /v0-maintain $gm_feature there"
              fi
              if [ -n "$gm_cur" ] && [ "$gm_ib" != "HEAD" ] && [ "$gm_cur" != "$gm_ib" ]; then
                gc_refuse "$gm_step" "maintenance note '$gm_feature' (tier: $gm_eff_tier) must run on 'maintain/$gm_feature' or start from integration branch '$gm_ib' (current branch: '$gm_cur')"
              fi
              if git show-ref --verify --quiet "refs/heads/maintain/${gm_feature}"; then
                if git log --first-parent --format=%B "$gm_ib" 2>/dev/null | grep -Eq "^Story-Branch:[[:space:]]*maintain/${gm_feature}[[:space:]]*\$"; then
                  gc_refuse "$gm_step" "branch 'maintain/$gm_feature' was already squash-merged into '$gm_ib'; start a new maintenance id"
                fi
              fi
            fi
          fi
        fi
        ;;
      in-progress)
        [ -f "$gm_state" ] || gc_refuse "$gm_step" "maintain for '$gm_feature' has not been started; run $G start $gm_feature first"
        [ "$(gc_state_get "$gm_state" activePhase)" = "$gm_phase" ] \
          || gc_refuse "$gm_step" "activePhase for '$gm_feature' is '$(gc_state_get "$gm_state" activePhase)', not '$gm_phase'; run $G start $gm_feature first"
        [ "$(gc_state_get "$gm_state" activeStatus)" = "in_progress" ] \
          || gc_refuse "$gm_step" "maintain for '$gm_feature' is not in_progress (status: $(gc_state_get "$gm_state" activeStatus)); run $G start $gm_feature first"
        ;;
      *)
        gc_refuse "$gm_step" "unknown prerequisite '$gm_req' in gate-rules" ;;
    esac
  done
}

gm_parse_check_start_args() {
  gm_p_step="$1"
  shift
  gm_p_slug=""
  gm_p_tier=""
  gm_p_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier)
        [ $# -ge 2 ] || gc_refuse "$gm_p_step" "--tier requires a value (trivial|standard|emergency)"
        gm_p_tier="$2"
        shift 2
        ;;
      --tier=*)
        gm_p_tier="${1#--tier=}"
        shift
        ;;
      --reopen)
        gm_p_reopen=1
        shift
        ;;
      -*)
        gm_usage
        ;;
      *)
        [ -z "$gm_p_slug" ] || gm_usage
        gm_p_slug="$1"
        shift
        ;;
    esac
  done
}

gm_check() {
  gm_parse_check_start_args check "$@"
  gm_load check "$gm_p_slug" "$gm_p_tier"
  gm_rule check check.requires "$gm_feature"
  gm_check_prereqs check "$gm_val" "$gm_p_reopen"
  gc_ok check "maintain ($gm_feature, tier=$gm_eff_tier) prerequisites satisfied"
}

gm_start() {
  gc_refuse start "start not yet implemented (DM2)"
}

gm_block() {
  gc_refuse block "block not yet implemented (DM2)"
}

gm_ready() {
  gc_refuse ready "ready not yet implemented (DM3)"
}

gm_commit() {
  gc_refuse commit "commit not yet implemented (DM5)"
}

gm_steps() {
  gc_refuse steps "steps not yet implemented (DM6)"
}

cmd="${1:-}"
[ -n "$cmd" ] || gm_usage
shift
case "$cmd" in
  check)  gm_check "$@" ;;
  start)  gm_start "$@" ;;
  block)  gm_block "$@" ;;
  ready)  gm_ready "$@" ;;
  commit) gm_commit "$@" ;;
  steps)  gm_steps "$@" ;;
  *)      gm_usage ;;
esac
