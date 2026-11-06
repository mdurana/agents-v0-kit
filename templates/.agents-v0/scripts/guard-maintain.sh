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

gm_enter_worktree_if_needed() {
  gm_ew_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/maintain/${gm_feature}" '
    /^worktree / { path = substr($0, 10) }
    $0 == want { print path; exit }
  ')"
  if [ ! -f "$gm_state" ] && [ -n "$gm_ew_wt" ] && [ -f "$gm_ew_wt/$gm_state" ]; then
    cd "$gm_ew_wt"
  fi
}

# Design: DM2 (/v0-maintain start, worktree provisioning, reopen, block, and helper-brief deduplication).
gm_start() {
  gm_parse_check_start_args start "$@"
  gm_load start "$gm_p_slug" "$gm_p_tier"
  gm_enter_worktree_if_needed

  gm_rule start start.requires "$gm_feature"
  gm_check_prereqs start "$gm_val" "$gm_p_reopen"
  gm_check_prereqs start "not-approved" "$gm_p_reopen"
  gm_check_prereqs start "maintain-branch" "$gm_p_reopen"

  # Provision or attach maintain/<id> worktree for standard/emergency when not already on maintain/<id>
  gm_skip_bg=0
  # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
  [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gm_skip_bg=1
  # <<< kit-test-override
  if [ "$gm_skip_bg" != 1 ] && [ "$gm_eff_tier" != "trivial" ]; then
    gm_cur_br="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [ "$gm_cur_br" != "maintain/$gm_feature" ]; then
      gm_primary_root="$(pwd)"
      if ! gm_wt_out="$(sh "$GC_HERE/feature-worktree.sh" --maintain "$gm_feature" 2>&1)"; then
        gc_refuse start "feature-worktree.sh --maintain $gm_feature failed: $gm_wt_out"
      fi
      printf '%s\n' "$gm_wt_out"
      gm_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/maintain/${gm_feature}" '
        /^worktree / { path = substr($0, 10) }
        $0 == want { print path; exit }
      ')"
      [ -n "$gm_wt" ] && [ -d "$gm_wt" ] || gc_refuse start "could not locate worktree for maintain/$gm_feature"
      if [ ! -f "$gm_wt/$gm_template" ] && [ -f "$gm_primary_root/$gm_template" ]; then
        mkdir -p "$(dirname "$gm_wt/$gm_template")"
        cp "$gm_primary_root/$gm_template" "$gm_wt/$gm_template"
      fi
      cd "$gm_wt"
    fi
  fi

  # Seed docs/agents-v0/maintain/<id>/note.md from _note.template.md when absent
  mkdir -p "$(dirname "$gm_artifact")"
  if [ ! -f "$gm_artifact" ]; then
    if [ -f "$gm_template" ]; then
      cp "$gm_template" "$gm_artifact"
    else
      cat > "$gm_artifact" <<EOF
# Maintenance note: ${gm_feature}

Id: ${gm_feature}
Tier: ${gm_eff_tier}
Tier confirmed by: <name of the person who agreed to this tier, in chat> on <YYYY-MM-DD>
Type: <bug | cve | dependency | refactor | docs | migration>
Trigger: <issue, alert, or incident link>
Follow-up verify due: <YYYY-MM-DD; Tier emergency only, delete the line otherwise>

## Scope

## Acceptance

## Security surface

## Rollback

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
    fi
  fi

  # Populate Id: <id> (and Tier: <tier> when --tier was explicitly passed) in note.md if still template placeholders
  GM_NOTE="$gm_artifact" GM_ID="$gm_feature" GM_TIER_ARG="$gm_p_tier" python3 - <<'PYNOTE'
import os, re
p = os.environ["GM_NOTE"]
mid = os.environ["GM_ID"]
tier_arg = os.environ["GM_TIER_ARG"]
txt = open(p, encoding="utf-8").read()
txt = re.sub(r"^(Id:\s*)<id>\s*$", rf"\g<1>{mid}", txt, flags=re.M)
if tier_arg:
    txt = re.sub(r"^(Tier:\s*)<[^>]+>\s*$", rf"\g<1>{tier_arg}", txt, flags=re.M)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(txt)
PYNOTE

  # Seed docs/agents-v0/build/<id>/build-report.md when absent
  mkdir -p "$(dirname "$gm_report")"
  if [ ! -f "$gm_report" ]; then
    cat > "$gm_report" <<EOF
# Build Report: ${gm_feature}

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |

## Final Verify Summary
- Status: pending

## Per-Criterion Evidence
EOF
  fi

  gm_base="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
  gm_rule start start.next "$gm_feature"; gm_next="$gm_val"
  gm_rule start start.status "$gm_feature"; gm_status="$gm_val"

  if [ "$gm_p_reopen" = 1 ] && [ -f "$gm_state" ]; then
    python3 - "$gm_state" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(0)
reopen_count = int(d.get("reopenCount") or 0) + 1
d["reopenCount"] = reopen_count
if "approvedPhases" in d and isinstance(d["approvedPhases"], list):
    if "maintain" in d["approvedPhases"]:
        idx = d["approvedPhases"].index("maintain")
        d["approvedPhases"] = d["approvedPhases"][:idx]
    d["lastApprovedPhase"] = d["approvedPhases"][-1] if d["approvedPhases"] else ""
d["verifyPassed"] = False
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi

  gc_state_set "$gm_state" "$gm_feature" "$gm_artifact" "activePhase=$gm_phase" \
    "activeStatus=$gm_status" "blockedReason=" "nextStep=$gm_next" || exit 1

  GM_ST="$gm_state" GM_BASE="$gm_base" GM_TIER="$gm_eff_tier" GM_REOPEN="$gm_p_reopen" python3 - <<'PY'
import json, os
p = os.environ["GM_ST"]
base = os.environ["GM_BASE"]
tier = os.environ["GM_TIER"]
reopen = os.environ["GM_REOPEN"] == "1"
d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
if base and (reopen or not d.get("baseCommit")):
    d["baseCommit"] = base
d["tier"] = tier
d["maintainGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY

  gc_ok start "maintain is in_progress for $gm_feature (tier=$gm_eff_tier, note=$gm_artifact, report=$gm_report)"
  printf 'Next: %s\n' "$gm_next"
}

gm_block() {
  gm_b_slug="${1:-}"
  shift || true
  gm_b_reason="${*:-}"
  gm_load block "$gm_b_slug"
  gm_enter_worktree_if_needed
  [ -n "$(printf '%s' "$gm_b_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason"
  gm_rule block block.next "$gm_feature"; gm_next="$gm_val"
  gm_rule block block.status "$gm_feature"; gm_status="$gm_val"

  [ -f "$gm_state" ] || gc_refuse block "maintain for '$gm_feature' has not been started ($gm_state missing)"
  [ "$(gc_state_get "$gm_state" activePhase)" = "$gm_phase" ] \
    || gc_refuse block "activePhase for '$gm_feature' is '$(gc_state_get "$gm_state" activePhase)', not '$gm_phase'"

  # Deduplicate helper-brief.md or failure-brief.md by SHA-256
  gm_hb=""
  if [ -f "docs/agents-v0/maintain/${gm_feature}/helper-brief.md" ]; then
    gm_hb="docs/agents-v0/maintain/${gm_feature}/helper-brief.md"
  elif [ -f "docs/agents-v0/build/${gm_feature}/helper-brief.md" ]; then
    gm_hb="docs/agents-v0/build/${gm_feature}/helper-brief.md"
  elif [ -f "docs/agents-v0/build/${gm_feature}/failure-brief.md" ]; then
    gm_hb="docs/agents-v0/build/${gm_feature}/failure-brief.md"
  fi
  if [ -n "$gm_hb" ]; then
    gm_dup="$(GM_ST="$gm_state" GM_HB="$gm_hb" python3 - <<'PY'
import hashlib, json, os, re
st_p = os.environ["GM_ST"]
hb_p = os.environ["GM_HB"]
d = json.load(open(st_p, encoding="utf-8")) if os.path.isfile(st_p) else {}
raw = open(hb_p, encoding="utf-8", errors="replace").read()
norm = re.sub(r"\s+", " ", raw.strip().lower())
h = hashlib.sha256(norm.encode("utf-8")).hexdigest()
prev_list = d.get("helperBriefHashes")
if not isinstance(prev_list, list):
    prev_list = []
prev_last = d.get("lastHelperBriefHash", "")
if h in prev_list or (prev_last and prev_last == h):
    print("DUP")
else:
    prev_list.append(h)
    d["helperBriefHashes"] = prev_list
    d["lastHelperBriefHash"] = h
    with open(st_p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
    print("OK")
PY
)"
    if [ "$gm_dup" = "DUP" ]; then
      gc_state_set "$gm_state" "$gm_feature" "$gm_artifact" "activePhase=$gm_phase" \
        "activeStatus=$gm_status" "blockedReason=Duplicate helper-brief detected: $gm_b_reason" "nextStep=$gm_next" || exit 1
      gc_refuse block "duplicate helper-brief ($gm_hb) detected with identical SHA-256 content; escalate to Sensei instead of looping"
    fi
  fi

  gc_state_set "$gm_state" "$gm_feature" "$gm_artifact" "activePhase=$gm_phase" \
    "activeStatus=$gm_status" "blockedReason=$gm_b_reason" "nextStep=$gm_next" || exit 1
  gc_ok block "maintain blocked for $gm_feature: $gm_b_reason"
  printf 'Next: %s\n' "$gm_next"
}

# Design: DM3 (/v0-maintain ready note, tier, 800-line ceiling, attempt-budget, failure-brief, and verification validator).
gm_ready() {
  [ $# -eq 1 ] || gm_usage
  gm_r_slug="$1"
  gm_load ready "$gm_r_slug"
  gm_enter_worktree_if_needed

  gm_rule ready ready.requires "$gm_feature"
  gm_check_prereqs ready "$gm_val" 0

  [ -f "$gm_artifact" ] || gc_refuse ready "maintenance note '$gm_artifact' is missing"
  [ -f "$gm_report" ] || gc_refuse ready "build report '$gm_report' is missing"

  # 1-5. Validate note.md fields, placeholders, Tier confirmed by, emergency rollback + follow-up date, trivial scope, and MAINTAIN_MAX_LINES
  gm_base="$(gc_state_get "$gm_state" baseCommit 2>/dev/null || true)"
  [ -n "$gm_base" ] || gm_base="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
  gm_max_lines="${MAINTAIN_MAX_LINES:-800}"

  if ! gm_val_out="$(GM_NOTE="$gm_artifact" GM_ID="$gm_feature" GM_BASE="$gm_base" GM_MAX_LINES="$gm_max_lines" python3 - <<'PYREADY'
import os, re, subprocess, sys

note_path = os.environ["GM_NOTE"]
slug = os.environ["GM_ID"]
base_commit = os.environ["GM_BASE"]
try:
    max_lines = int(os.environ.get("GM_MAX_LINES") or "800")
except ValueError:
    max_lines = 800

def refuse(msg):
    print(msg)
    sys.exit(1)

raw = open(note_path, encoding="utf-8").read()
if not raw.strip():
    refuse(f"{note_path} is empty")

if "<!-- TEMPLATE:" in raw:
    refuse(f"{note_path} still contains unfilled '<!-- TEMPLATE:' comments; complete or remove template comments before ready")

clean = re.sub(r"<!--.*?-->", "", raw, flags=re.S)
no_code = re.sub(r"```.*?```", "", clean, flags=re.S)

# Check header fields: Id, Tier, Type, Trigger
m_id = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Id(?:\*\*)?\s*:\s*`?([^\s`]+)`?\s*$", no_code)
if not m_id or m_id.group(1).strip() != slug:
    refuse(f"{note_path} must declare 'Id: {slug}' (found: {m_id.group(1) if m_id else 'missing'})")

m_tier = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Tier(?:\*\*)?\s*:\s*`?([^\n`]+)`?\s*$", no_code)
if not m_tier:
    refuse(f"{note_path} is missing 'Tier: trivial | standard | emergency'")
tier = m_tier.group(1).strip().lower()
if tier not in ("trivial", "standard", "emergency"):
    refuse(f"{note_path} has invalid Tier '{m_tier.group(1).strip()}'; must be trivial, standard, or emergency")

m_type = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Type(?:\*\*)?\s*:\s*`?([^\n`]+)`?\s*$", no_code)
if not m_type:
    refuse(f"{note_path} is missing 'Type: bug | cve | dependency | refactor | docs | migration'")
mtype = m_type.group(1).strip().lower()
if mtype not in ("bug", "cve", "dependency", "refactor", "docs", "migration"):
    refuse(f"{note_path} has invalid Type '{m_type.group(1).strip()}'; must be bug, cve, dependency, refactor, docs, or migration")

m_trig = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Trigger(?:\*\*)?\s*:\s*(.+?)\s*$", no_code)
if not m_trig or not m_trig.group(1).strip() or re.search(r"<[^>]+>", m_trig.group(1)):
    refuse(f"{note_path} must have a non-placeholder 'Trigger:' line")

# Check Tier confirmed by for trivial and emergency
m_conf = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Tier\s+confirmed\s+by(?:\*\*)?\s*:\s*(.+?)\s*$", no_code)
if tier in ("trivial", "emergency"):
    if not m_conf:
        refuse(f"{note_path} with Tier: {tier} requires 'Tier confirmed by: <person> on <YYYY-MM-DD>'")
    cval = m_conf.group(1).strip()
    if not cval or re.search(r"<[^>]+>", cval) or cval.lower() in ("tbd", "todo", "n/a", "none"):
        refuse(f"{note_path} has placeholder 'Tier confirmed by: {cval}'; record the person and date")

# Check Follow-up verify due for emergency (and ensure template placeholder is removed for non-emergency)
m_due = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Follow-up\s+verify\s+due(?:\*\*)?\s*:\s*(.+?)\s*$", no_code)
if tier == "emergency":
    if not m_due or not re.match(r"^\d{4}-\d{2}-\d{2}\b", m_due.group(1).strip()):
        refuse(f"{note_path} with Tier: emergency requires 'Follow-up verify due: YYYY-MM-DD'")
elif m_due and re.search(r"<[^>]+>", m_due.group(1)):
    refuse(f"{note_path} still has template placeholder on 'Follow-up verify due:'; delete the line for non-emergency notes")

# Check required sections: Scope, Acceptance, Security surface, Rollback
def get_section(name):
    m = re.search(rf"(?im)^##\s+{re.escape(name)}\s*$(.*?)(?=^##\s+|\Z)", no_code, flags=re.S)
    return m.group(1).strip() if m else None

for sec in ("Scope", "Acceptance", "Security surface"):
    body = get_section(sec)
    if body is None or not body:
        refuse(f"{note_path} section '## {sec}' is missing or empty")
    if re.search(r"<[A-Za-z][^>\n]*>", body):
        refuse(f"{note_path} section '## {sec}' still contains a template placeholder")

rb_body = get_section("Rollback")
if rb_body is None:
    refuse(f"{note_path} section '## Rollback' is missing")
if tier == "emergency":
    if not rb_body or rb_body.lower() in ("none", "n/a", "tbd", "todo") or re.search(r"<[A-Za-z][^>\n]*>", rb_body):
        refuse(f"{note_path} with Tier: emergency requires a concrete non-empty '## Rollback' plan")

acc_body = get_section("Acceptance") or ""
if mtype == "bug":
    if not (re.search(r"(?i)\bexpected\b", acc_body) and re.search(r"(?i)\bactual\b", acc_body)):
        refuse(f"{note_path} with Type: bug must document both 'Expected' and 'Actual' behavior in '## Acceptance'")
    if not re.search(r"(?i)\btest\b|`[^`]+`", acc_body):
        refuse(f"{note_path} with Type: bug must name the reproducing test in '## Acceptance'")
elif mtype in ("cve", "dependency"):
    if not (re.search(r"->|→|\bto\b|\bfrom\b|CVE-\d{4}-\d+", acc_body, flags=re.I)):
        refuse(f"{note_path} with Type: {mtype} must document package versions (from -> to) or CVE IDs in '## Acceptance'")

sec_body = get_section("Security surface") or ""
if tier == "trivial":
    if not re.match(r"^(?:[-*]\s*)?(?:none|no|n/a|not\s+applicable)\b", sec_body.strip(), flags=re.I):
        refuse(f"{note_path} with Tier: trivial cannot touch a security surface ('## Security surface' must state 'None'); use Tier: standard")

# Check changed files and line counts relative to base_commit
diff_target = base_commit if base_commit else "HEAD"
numstat_out = subprocess.run(["git", "diff", "--numstat", diff_target], capture_output=True, text=True, check=False).stdout
status_out = subprocess.run(["git", "status", "--porcelain=v1", "-uall"], capture_output=True, text=True, check=False).stdout

changed_files = {}
for line in numstat_out.splitlines():
    parts = line.split("\t")
    if len(parts) == 3:
        a, d, p = parts
        try:
            lines_changed = (int(a) if a != "-" else 0) + (int(d) if d != "-" else 0)
        except ValueError:
            lines_changed = 0
        changed_files[p] = lines_changed

for line in status_out.splitlines():
    if len(line) < 4:
        continue
    st = line[:2]
    p = line[3:].split(" -> ")[-1].strip('"')
    if p.endswith(".lock"):
        continue
    if st == "??" and os.path.isfile(p) and p not in changed_files:
        try:
            changed_files[p] = sum(1 for _ in open(p, encoding="utf-8", errors="replace"))
        except OSError:
            changed_files[p] = 0

LOCKFILES = {
    "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Cargo.lock", "go.sum", "poetry.lock", "uv.lock"
}
MANIFESTS = {
    "pom.xml", "build.gradle", "build.gradle.kts", "package.json", "pyproject.toml",
    "requirements.txt", "Cargo.toml", "go.mod"
} | LOCKFILES

def is_doc_or_meta(p):
    if p.startswith("docs/") or p.startswith(".agents-v0/") or p.startswith(".cursor/") or p.startswith(".agents/"):
        return True
    bn = os.path.basename(p)
    if bn.endswith(".md") or bn in ("README", "CHANGELOG", "LICENSE"):
        return True
    return False

def is_manifest_or_lock(p):
    bn = os.path.basename(p)
    return bn in MANIFESTS or (bn.startswith("requirements") and bn.endswith(".txt"))

non_doc_source_lines = 0
non_doc_files = []
for p, lcount in changed_files.items():
    if is_doc_or_meta(p):
        continue
    non_doc_files.append(p)
    if os.path.basename(p) not in LOCKFILES:
        non_doc_source_lines += lcount

if tier == "trivial":
    bad_trivial = [p for p in non_doc_files if not is_manifest_or_lock(p)]
    if bad_trivial:
        refuse(f"Tier: trivial only allows documentation edits or 1-for-1 patch version bumps in manifests/lockfiles; found source changes in: {', '.join(bad_trivial[:5])}. Use Tier: standard on a maintain/{slug} worktree")

if non_doc_source_lines > max_lines:
    refuse(f"changed non-doc source lines ({non_doc_source_lines}) exceed MAINTAIN_MAX_LINES ({max_lines}); changes over {max_lines} lines are a feature and must route to /v0-intake")

has_non_doc = "1" if (non_doc_files or mtype != "docs") else "0"
print(f"{tier}|{mtype}|{non_doc_source_lines}|{has_non_doc}")
PYREADY
)"; then
    gc_refuse ready "$gm_val_out"
  fi

  gm_parsed_tier="$(printf '%s' "$gm_val_out" | cut -d'|' -f1)"
  gm_parsed_type="$(printf '%s' "$gm_val_out" | cut -d'|' -f2)"
  gm_parsed_lines="$(printf '%s' "$gm_val_out" | cut -d'|' -f3)"
  gm_has_nondoc="$(printf '%s' "$gm_val_out" | cut -d'|' -f4)"

  # 6. Validate attempt budget (<8) and failure-brief / 3rd-red cap on build-report.md
  if [ -f "$GC_HERE/check-attempt-budget.sh" ]; then
    if ! gm_ab_out="$(sh "$GC_HERE/check-attempt-budget.sh" "$gm_report" 2>&1)"; then
      gc_refuse ready "attempt budget check failed ($gm_ab_out); run $G block $gm_feature \"Attempt budget exhausted\" and stop"
    fi
  fi
  if [ -f "$GC_HERE/check-failure-brief.sh" ]; then
    if ! gm_fb_out="$(sh "$GC_HERE/check-failure-brief.sh" "$gm_report" 2>&1)"; then
      gc_refuse ready "failure-brief check failed ($gm_fb_out); author docs/agents-v0/build/$gm_feature/failure-brief.md or run $G block $gm_feature \"Consecutive red verify cap\""
    fi
  fi

  # For non-docs changes, verify passing attempt row + Final Verify Summary PASS + build-output.txt + check-tests-ran.sh
  if [ "$gm_has_nondoc" = "1" ]; then
    if ! gm_rep_ok="$(GM_REP="$gm_report" python3 - <<'PYREP'
import os, re, sys
txt = open(os.environ["GM_REP"], encoding="utf-8").read()
clean = re.sub(r"<!--.*?-->", "", txt, flags=re.S)
pass_rows = 0
for line in clean.splitlines():
    if line.strip().startswith("|"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[0].lower() not in ("command", "---") and not set(cells[0]) <= {"-"}:
            ex = cells[1].lower()
            if ex in ("0", "pass", "passed", "ok", "exit 0"):
                pass_rows += 1
if pass_rows == 0:
    print("build-report.md must record at least one passing verification attempt row (Exit 0)")
    sys.exit(1)
if not re.search(r"(?im)^-\s*Status:\s*(?:PASS|passed|green|ok)\b", clean):
    print("build-report.md '## Final Verify Summary' must record '- Status: PASS'")
    sys.exit(1)
PYREP
)"; then
      gc_refuse ready "$gm_rep_ok"
    fi

    [ -f "$gm_output" ] && [ -s "$gm_output" ] \
      || gc_refuse ready "verification output log '$gm_output' is missing or empty; run the native stack verify command and tee output to '$gm_output'"

    if [ -f "$GC_HERE/check-tests-ran.sh" ]; then
      if ! gm_tr_out="$(sh "$GC_HERE/check-tests-ran.sh" 2>&1)"; then
        gc_refuse ready "check-tests-ran.sh failed ($gm_tr_out)"
      fi
    fi
  fi

  # 7. When docs/agents-v0/onboarding/report.md exists, run check-onboarding-docs.sh
  if [ -f "docs/agents-v0/onboarding/report.md" ] && [ -f "$GC_HERE/check-onboarding-docs.sh" ]; then
    if ! gm_od_out="$(sh "$GC_HERE/check-onboarding-docs.sh" 2>&1)"; then
      gc_refuse ready "check-onboarding-docs.sh failed ($gm_od_out)"
    fi
  fi

  # 8. Secret scan on note.md, build-report.md, and build-output.txt
  if [ -f "$GC_HERE/secret_scan.py" ]; then
    if ! gm_sec_out="$(python3 - "$GC_HERE" "$gm_artifact" "$gm_report" "$gm_output" <<'PYSEC'
import os, sys
sys.path.insert(0, sys.argv[1])
import secret_scan
bad = []
for p in sys.argv[2:]:
    if not p or not os.path.isfile(p):
        continue
    for lineno, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
        for r_id, pat in secret_scan.CONTENT_RULES:
            if pat.search(line):
                bad.append(f"{p}:{lineno} ({r_id})")
if bad:
    print(", ".join(bad))
    sys.exit(1)
PYSEC
)"; then
      gc_refuse ready "secret pattern detected in maintenance artifacts ($gm_sec_out)"
    fi
  fi

  # Write/normalize docs/agents-v0/maintain/<id>/phase-result.md
  GM_RES="$gm_result" GM_ID="$gm_feature" GM_ART="$gm_artifact" GM_BASE="$gm_base" \
  GM_TIER="$gm_parsed_tier" GM_TYPE="$gm_parsed_type" GM_LINES="$gm_parsed_lines" python3 - <<'PYRES'
import os, re

res_path = os.environ["GM_RES"]
slug = os.environ["GM_ID"]
art_path = os.environ["GM_ART"]
base_commit = os.environ["GM_BASE"]
tier = os.environ["GM_TIER"]
mtype = os.environ["GM_TYPE"]
lines = os.environ["GM_LINES"]

lessons_block = "## Lessons\n\n### maintain\n- none\n"
if os.path.isfile(res_path):
    old_res = open(res_path, encoding="utf-8").read()
    lm = re.search(r"(^##\s+Lessons\b.*)", old_res, flags=re.M | re.S)
    if lm:
        lessons_block = lm.group(1).rstrip() + "\n"

res_content = f"""# Phase Result: maintain ({slug})

- phase: maintain
- status: awaiting_approval
- guard_managed: true
- feature: {slug}
- tier: {tier}
- type: {mtype}
- changed_lines: {lines}
- artifact: {art_path}
- base_commit: {base_commit}

{lessons_block}"""

os.makedirs(os.path.dirname(res_path) or ".", exist_ok=True)
with open(res_path, "w", encoding="utf-8") as fh:
    fh.write(res_content)
PYRES

  gm_rule ready ready.next "$gm_feature"; gm_next="$gm_val"
  gm_rule ready ready.status "$gm_feature"; gm_status="$gm_val"
  gc_state_set "$gm_state" "$gm_feature" "$gm_artifact" "activePhase=$gm_phase" \
    "activeStatus=$gm_status" "blockedReason=" "nextStep=$gm_next" || exit 1

  GM_ST="$gm_state" GM_TIER="$gm_parsed_tier" python3 - <<'PYST'
import json, os
p = os.environ["GM_ST"]
tier = os.environ["GM_TIER"]
d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
d["tier"] = tier
d["maintainGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PYST

  gc_ok ready "maintain note verified for $gm_feature (tier=$gm_parsed_tier, type=$gm_parsed_type, non_doc_lines=$gm_parsed_lines)"
  printf 'Next: %s\n' "$gm_next"
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
