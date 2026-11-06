#!/bin/sh
# guard-local-release.sh — single entry point and security boundary for /v0-local-release.
# Usage:
#   sh .agents-v0/scripts/guard-local-release.sh check <feature> [--maintain]
#   sh .agents-v0/scripts/guard-local-release.sh start <feature> [--maintain]
#   sh .agents-v0/scripts/guard-local-release.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-local-release.sh ready <feature> [--maintain]
#   sh .agents-v0/scripts/guard-local-release.sh commit <feature> [--maintain]
#   sh .agents-v0/scripts/guard-local-release.sh steps
#
# Design: DLR1 (/v0-local-release guard and parameterized per-story release gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-local-release.sh"

glr_usage() {
  printf 'usage: %s check <feature> [--maintain]\n' "$G" >&2
  printf '       %s start <feature> [--maintain]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature> [--maintain]\n' "$G" >&2
  printf '       %s commit <feature> [--maintain]\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

glr_validate_slug() {
  glr_v_step="$1"
  glr_v_slug="${2:-}"
  [ -n "$glr_v_slug" ] || gc_refuse "$glr_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$glr_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$glr_v_step" "feature slug '$glr_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$glr_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$glr_v_step" "feature slug '$glr_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$glr_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$glr_v_step" "story '$glr_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-local-release"
      ;;
  esac
}

glr_rule() {
  glr_step="$1"
  glr_key="$2"
  glr_slug="${3:-}"
  glr_rules="${GC_HERE}/../gate-rules"
  [ -f "$glr_rules" ] || gc_refuse "$glr_step" "missing gate-rules file ($glr_rules)"
  glr_val="$(awk -v p="local-release" -v k="$glr_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$glr_rules")"
  [ -n "$glr_val" ] || gc_refuse "$glr_step" "gate-rules missing key '$glr_key' for phase 'local-release'"
  if [ -n "$glr_slug" ]; then
    glr_val="$(printf '%s' "$glr_val" | sed "s/<feature>/$glr_slug/g")"
  fi
}

glr_load() {
  glr_step="$1"
  glr_slug="$2"
  glr_force_maint="${3:-0}"
  glr_validate_slug "$glr_step" "$glr_slug"
  gc_to_root "$glr_step"
  glr_rule "$glr_step" phase "$glr_slug"; glr_phase="$glr_val"
  glr_rule "$glr_step" feature "$glr_slug"; glr_feature="$glr_val"
  glr_rule "$glr_step" state "$glr_slug"; glr_state="$glr_val"
  glr_rule "$glr_step" artifact "$glr_slug"; glr_artifact="$glr_val"
  glr_rule "$glr_step" output "$glr_slug"; glr_output="$glr_val"
  glr_rule "$glr_step" result "$glr_slug"; glr_result="$glr_val"
  glr_req_art="$glr_artifact"
  glr_is_maintain=0
  if [ "$glr_force_maint" = 1 ] || { [ ! -f "$glr_req_art" ] && [ -f "docs/agents-v0/maintain/${glr_feature}/note.md" ]; }; then
    glr_is_maintain=1
    glr_req_art="docs/agents-v0/maintain/${glr_feature}/note.md"
    glr_artifact="$glr_req_art"
    glr_state="docs/agents-v0/maintain/${glr_feature}/state.json"
    glr_result="docs/agents-v0/maintain/${glr_feature}/phase-result.md"
  fi
}

glr_check_prereqs() {
  glr_step="$1"
  glr_reqs="$2"
  glr_rule "$glr_step" approved.next "$glr_feature"; glr_approved_next="$glr_val"

  for glr_req in $glr_reqs; do
    case "$glr_req" in
      git-work-tree) ;;
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$glr_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      feature-branch)
        glr_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || glr_skip_bg=1
        # <<< kit-test-override
        if [ "$glr_skip_bg" != 1 ]; then
          glr_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [ "$glr_is_maintain" = 1 ]; then
            glr_tier="$(gc_state_get "$glr_state" tier 2>/dev/null || true)"
            if [ "$glr_tier" = "trivial" ]; then
              if [ -f "$GC_HERE/resolve-integration-branch.sh" ]; then
                glr_int="$(sh "$GC_HERE/resolve-integration-branch.sh" 2>/dev/null || true)"
                glr_int="${glr_int#origin/}"
                if [ -n "$glr_int" ] && [ "$glr_int" != "HEAD" ] && [ "$glr_cur" != "$glr_int" ]; then
                  gc_refuse "$glr_step" "local-release for trivial maintenance note '$glr_feature' must run on integration branch '$glr_int' (current branch: '${glr_cur:-detached}')"
                fi
              fi
            else
              if [ "$glr_cur" != "maintain/$glr_feature" ]; then
                gc_refuse "$glr_step" "local-release for maintenance note '$glr_feature' must run on branch 'maintain/$glr_feature' (current branch: '${glr_cur:-detached}')"
              fi
            fi
          else
            if [ "$glr_cur" != "feature/$glr_feature" ]; then
              glr_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${glr_feature}" '
                /^worktree / { path = substr($0, 10) }
                $0 == want { print path; exit }
              ')"
              if [ -n "$glr_wt" ]; then
                gc_refuse "$glr_step" "local-release for '$glr_feature' must run in worktree '$glr_wt' on branch 'feature/$glr_feature' (current branch: '${glr_cur:-detached}'). Open that folder and run /v0-local-release $glr_feature there"
              else
                gc_refuse "$glr_step" "no 'feature/$glr_feature' branch or worktree exists (current branch: '${glr_cur:-detached}'); complete /v0-intake $glr_feature (approve + guard-intake.sh commit $glr_feature) first"
              fi
            fi
          fi
        fi
        ;;
      no-collision)
        glr_collision="$(GLR_SLUG="$glr_feature" python3 - <<'PYCOL'
import os, re, subprocess
slug = os.environ["GLR_SLUG"]
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
        if [ -n "$glr_collision" ]; then
          gc_refuse "$glr_step" "uncommitted changes for another story detected in working tree ($glr_collision); resolve or stash them before running /v0-local-release $glr_feature"
        fi
        ;;
      pack-configured)
        if [ -f "docs/agents-v0/project-profile.md" ] && [ -d ".agents-v0/packs" ]; then
          glr_pack="$(awk -F'|' '
            function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
            tolower($0) ~ /\|[ \t]*pack[ \t]*\|/ {
              v = trim($3)
              gsub(/<!--.*-->/, "", v)
              v = trim(v)
              if (v != "" && v !~ /^</) { print v; exit }
            }
          ' docs/agents-v0/project-profile.md)"
          if [ -n "$glr_pack" ] && [ ! -f ".agents-v0/packs/$glr_pack/pack.json" ]; then
            gc_refuse "$glr_step" "project-profile.md names Pack '$glr_pack', but '.agents-v0/packs/$glr_pack/pack.json' is missing"
          fi
        fi
        ;;
      not-released)
        if [ -f "$glr_state" ]; then
          glr_tier="$(gc_state_get "$glr_state" tier 2>/dev/null || true)"
          case " $(gc_state_get "$glr_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              if [ "$glr_is_maintain" = 1 ] && [ "$glr_tier" = "emergency" ]; then
                case " $(gc_state_get "$glr_state" approvedPhases | tr -d '[]",') " in
                  *" verify "*) gc_refuse "$glr_step" "emergency maintenance note '$glr_feature' is already released and verified; start a new maintenance id" ;;
                  *) gc_refuse "$glr_step" "emergency maintenance note '$glr_feature' is already released and still owes Verify; run /v0-verify $glr_feature" ;;
                esac
              elif [ "$glr_is_maintain" = 1 ]; then
                gc_refuse "$glr_step" "maintenance note '$glr_feature' is already released; start a new maintenance id"
              else
                gc_refuse "$glr_step" "story '$glr_feature' is already released; start /v0-maintain for a fix, /v0-triage for a docs/version bump, or /v0-intake with a new feature slug"
              fi
              ;;
          esac
        fi
        ;;
      verify-approved)
        [ -f "$glr_req_art" ] \
          || gc_refuse "$glr_step" "primary artifact '$glr_req_art' is missing; complete /v0-verify $glr_feature first"
        [ -f "$glr_state" ] \
          || gc_refuse "$glr_step" "state file '$glr_state' is missing; complete /v0-verify $glr_feature first"
        glr_tier="$(gc_state_get "$glr_state" tier 2>/dev/null || true)"
        glr_em_bypass=0
        if [ "$glr_is_maintain" = 1 ] && [ "$glr_tier" = "emergency" ]; then
          case " $(gc_state_get "$glr_state" approvedPhases | tr -d '[]",') " in
            *" verify "*) ;;
            *" maintain "*)
              glr_em_ok="$(GLR_NOTE="$glr_req_art" python3 - <<'PYEM'
import os, re
txt = open(os.environ["GLR_NOTE"], encoding="utf-8").read()
txt = re.sub(r"<!--.*?-->", "", txt, flags=re.S)
has_rb = bool(re.search(r"(?i)(?:rollback\s+plan|##\s*rollback)\s*[:\n]+\s*\S+", txt))
has_due = bool(re.search(r"(?i)follow-up\s+verify\s+due\s*:\s*\d{4}-\d{2}-\d{2}", txt))
print("1" if (has_rb and has_due) else "0")
PYEM
)"
              if [ "$glr_em_ok" = "1" ]; then
                glr_em_bypass=1
              else
                gc_refuse "$glr_step" "emergency maintenance note '$glr_feature' requires a rollback plan and 'Follow-up verify due: YYYY-MM-DD' in '$glr_req_art' before releasing ahead of /v0-verify"
              fi
              ;;
            *) gc_refuse "$glr_step" "maintain is not in approvedPhases in '$glr_state'; complete /v0-maintain $glr_feature first" ;;
          esac
        fi
        if [ "$glr_em_bypass" = 0 ]; then
          case " $(gc_state_get "$glr_state" approvedPhases | tr -d '[]",') " in
            *" verify "*) ;;
            *) gc_refuse "$glr_step" "verify is not in approvedPhases in '$glr_state'; complete /v0-verify $glr_feature first" ;;
          esac
          glr_vp="$(gc_state_get "$glr_state" verifyPassed 2>/dev/null || true)"
          [ "$glr_vp" = "true" ] || [ "$glr_vp" = "True" ] \
            || gc_refuse "$glr_step" "verifyPassed is not true in '$glr_state'; complete /v0-verify $glr_feature first"
          glr_vgm="$(gc_state_get "$glr_state" verifyGuardManaged 2>/dev/null || true)"
          if [ "$glr_vgm" = "True" ] || [ "$glr_vgm" = "true" ]; then
            if ! glr_v_ok="$(gc_approval_ok verify "$glr_feature")"; then
              gc_refuse "$glr_step" "external verify approval record missing or mismatched ($glr_v_ok); complete /v0-verify $glr_feature first"
            fi
          fi
        fi
        glr_skip_cc=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || glr_skip_cc=1
        # <<< kit-test-override
        if [ "$glr_skip_cc" != 1 ] && [ -f "$GC_HERE/check-gate-commit.sh" ]; then
          glr_prev_act="$(gc_state_get "$glr_state" activePhase 2>/dev/null || true)"
          if [ -z "$glr_prev_act" ]; then
            if ! glr_cc_out="$(sh "$GC_HERE/check-gate-commit.sh" "$glr_req_art" 2>&1)"; then
              gc_refuse "$glr_step" "previous gate is not committed: $glr_cc_out"
            fi
          fi
        fi
        ;;
      not-approved)
        if [ -f "$glr_state" ]; then
          case " $(gc_state_get "$glr_state" approvedPhases | tr -d '[]",') " in
            *" $glr_phase "*)
              gc_refuse "$glr_step" "release is already approved for '$glr_feature'; suggest $glr_approved_next"
              ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$glr_state" ]; then
          [ "$(gc_state_get "$glr_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$glr_step" "local-release for '$glr_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve local-release $glr_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$glr_state" ] || gc_refuse "$glr_step" "local-release for '$glr_feature' has not been started; run $G start $glr_feature first"
        [ "$(gc_state_get "$glr_state" activePhase)" = "$glr_phase" ] \
          || gc_refuse "$glr_step" "activePhase for '$glr_feature' is '$(gc_state_get "$glr_state" activePhase)', not '$glr_phase'; run $G start $glr_feature first"
        [ "$(gc_state_get "$glr_state" activeStatus)" = in_progress ] \
          || gc_refuse "$glr_step" "local-release for '$glr_feature' is not in_progress (status: $(gc_state_get "$glr_state" activeStatus)); run $G start $glr_feature first"
        ;;
      *) gc_refuse "$glr_step" "gate-rules names an unknown prerequisite '$glr_req'; reinstall the kit" ;;
    esac
  done
}

glr_check() {
  glr_c_slug=""
  glr_c_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        glr_c_maint=1
        shift
        ;;
      -*)
        glr_usage
        ;;
      *)
        [ -z "$glr_c_slug" ] || glr_usage
        glr_c_slug="$1"
        shift
        ;;
    esac
  done

  glr_load check "$glr_c_slug" "$glr_c_maint"
  glr_rule check check.requires "$glr_feature"; glr_requires="$glr_val"
  glr_check_prereqs check "$glr_requires"

  gc_ok check "prerequisites satisfied for /v0-local-release $glr_feature"
  if [ "$glr_is_maintain" = 1 ]; then
    printf 'Next: Start local-release with: %s start %s --maintain\n' "$G" "$glr_feature"
  else
    printf 'Next: Start local-release with: %s start %s\n' "$G" "$glr_feature"
  fi
}

glr_start() {
  gc_refuse start "not implemented yet"
}

glr_block() {
  gc_refuse block "not implemented yet"
}

glr_ready() {
  gc_refuse ready "not implemented yet"
}

glr_commit() {
  gc_refuse commit "not implemented yet"
}

glr_steps() {
  gc_refuse steps "not implemented yet"
}

cmd="${1:-}"
[ -n "$cmd" ] || glr_usage
shift || true

case "$cmd" in
  check) glr_check "$@" ;;
  start) glr_start "$@" ;;
  block) glr_block "$@" ;;
  ready) glr_ready "$@" ;;
  commit) glr_commit "$@" ;;
  steps) glr_steps "$@" ;;
  *) glr_usage ;;
esac
