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
                glr_mgm="$(gc_state_get "$glr_state" maintainGuardManaged 2>/dev/null || true)"
                if [ "$glr_mgm" = "True" ] || [ "$glr_mgm" = "true" ]; then
                  if ! glr_m_ok="$(gc_approval_ok maintain "$glr_feature")"; then
                    gc_refuse "$glr_step" "external maintain approval record missing or mismatched ($glr_m_ok); complete /v0-maintain $glr_feature first"
                  fi
                fi
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
        if [ "$glr_step" = "start" ]; then
          glr_check_non_doc_drift start
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

# Design: DLR2 (/v0-local-release start, block, and post-verify non-doc drift bounce).
glr_story_id_of() {
  glr_sid=""
  if [ -f "$glr_req_art" ]; then
    glr_sid="$(awk '
      /^Story:[ \t]*/ { sub(/^Story:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }
      /^#[ \t]+Maintain Note:[ \t]*/ { sub(/^#[ \t]+Maintain Note:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }
    ' "$glr_req_art" 2>/dev/null || true)"
  fi
  case "$glr_sid" in
    ""|"<"*|*"TBD"*) glr_sid="$glr_feature" ;;
  esac
  printf '%s\n' "$glr_sid"
}

glr_check_non_doc_drift() {
  glr_d_step="$1"
  # Skip non-doc drift bounce only for emergency maintenance notes releasing ahead of verify
  if [ "$glr_is_maintain" = 1 ]; then
    glr_d_tier="$(gc_state_get "$glr_state" tier 2>/dev/null || true)"
    case " $(gc_state_get "$glr_state" approvedPhases | tr -d '[]",') " in
      *" verify "*) ;;
      *)
        if [ "$glr_d_tier" = "emergency" ]; then
          return 0
        fi
        ;;
    esac
  fi

  glr_d_sid="$(glr_story_id_of)"
  glr_drift="$(GLR_SLUG="$glr_feature" GLR_SID="$glr_d_sid" python3 - <<'PYDRIFT'
import os, re, subprocess

slug = os.environ["GLR_SLUG"]
sid = os.environ["GLR_SID"]

def is_doc_or_meta(p):
    if p.endswith(".lock"):
        return True
    if p in ("README.md", "CHANGELOG.md", ".gitignore"):
        return True
    if p.startswith("docs/") or p.startswith(".agents-v0/"):
        return True
    return False

changed = []
# 1. Working tree changes
st = subprocess.run(["git", "status", "--porcelain=v1", "-uall"], capture_output=True, text=True, check=False).stdout
for line in st.splitlines():
    if len(line) < 4:
        continue
    p = line[3:].split(" -> ")[-1].strip('"')
    if p and not is_doc_or_meta(p) and p not in changed:
        changed.append(p)

# 2. Committed changes since latest '<story>: verify approved' commit on this branch
log = subprocess.run(["git", "log", "--format=%H\t%s", "-n", "30", "HEAD"], capture_output=True, text=True, check=False).stdout
v_sha = ""
want_subjects = {f"{sid.lower()}: verify approved", f"{slug.lower()}: verify approved"}
for line in log.splitlines():
    parts = line.split("\t", 1)
    if len(parts) == 2 and parts[1].strip().lower() in want_subjects:
        v_sha = parts[0].strip()
        break

if v_sha:
    df = subprocess.run(["git", "diff", "--name-only", f"{v_sha}..HEAD"], capture_output=True, text=True, check=False).stdout
    for p in df.splitlines():
        p = p.strip()
        if p and not is_doc_or_meta(p) and p not in changed:
            changed.append(p)

if changed:
    print(", ".join(changed[:5]))
PYDRIFT
)"
  if [ -n "$glr_drift" ]; then
    glr_was_vgm="$(gc_state_get "$glr_state" verifyGuardManaged 2>/dev/null || true)"
    sh "$GC_HERE/sync-feature-state.sh" --reopen verify --verify-passed false "$glr_req_art" >/dev/null 2>&1 || true
    GLR_ST="$glr_state" GLR_VGM="$glr_was_vgm" python3 - <<'PY'
import json, os
p = os.environ["GLR_ST"]
if os.path.isfile(p):
    d = json.load(open(p, encoding="utf-8"))
    if os.environ.get("GLR_VGM") in ("True", "true"):
        d["verifyGuardManaged"] = True
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
PY
    if [ -f "$glr_result" ]; then
      GLR_RES="$glr_result" python3 - <<'PY'
import os, re
p = os.environ["GLR_RES"]
txt = open(p, encoding="utf-8").read()
txt = re.sub(r"(?m)^status:\s*\S+", "status: changes_requested", txt)
open(p, "w", encoding="utf-8").write(txt)
PY
    fi
    gc_refuse "$glr_d_step" "BOUNCED $glr_d_step: non-doc files changed since Verify approval ($glr_drift); automatically reopened verify (verifyPassed=false). Route back to /v0-verify $glr_feature"
  fi
}

glr_start() {
  glr_s_slug=""
  glr_s_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        glr_s_maint=1
        shift
        ;;
      -*)
        glr_usage
        ;;
      *)
        [ -z "$glr_s_slug" ] || glr_usage
        glr_s_slug="$1"
        shift
        ;;
    esac
  done

  glr_load start "$glr_s_slug" "$glr_s_maint"
  glr_rule start start.requires "$glr_feature"; glr_requires="$glr_val"
  glr_check_prereqs start "$glr_requires"

  # Auto-bounce to /v0-verify if any non-doc files drifted since Verify approval
  glr_check_non_doc_drift start

  # Refuse unrelated dirty doc files outside release/verify/requirements/maintain/diagrams/README/CHANGELOG
  glr_dirty="$(GLR_SLUG="$glr_feature" python3 - <<'PYDIRTY'
import os, subprocess
slug = os.environ["GLR_SLUG"]
st = subprocess.run(["git", "status", "--porcelain=v1", "-uall"], capture_output=True, text=True, check=False).stdout
bad = []
allowed_prefixes = (
    f"docs/agents-v0/release/{slug}/",
    f"docs/agents-v0/verify/{slug}/",
    f"docs/agents-v0/requirements/{slug}.",
    f"docs/agents-v0/maintain/{slug}/",
    "docs/agents-v0/diagrams/",
)
for line in st.splitlines():
    if len(line) < 4:
        continue
    p = line[3:].split(" -> ")[-1].strip('"')
    if p.endswith(".lock") or p in ("README.md", "CHANGELOG.md", ".gitignore"):
        continue
    if p == "docs/agents-v0/lessons.md":
        bad.append(p)
        continue
    if not p.startswith(allowed_prefixes):
        bad.append(p)
if bad:
    print(", ".join(bad[:5]))
PYDIRTY
)"
  if [ -n "$glr_dirty" ]; then
    gc_refuse start "working tree has uncommitted changes outside local-release paths ($glr_dirty); commit, revert, or stash them first"
  fi

  glr_base="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
  glr_rule start start.next "$glr_feature"; glr_next="$glr_val"
  glr_rule start start.status "$glr_feature"; glr_status="$glr_val"

  glr_was_vgm="$(gc_state_get "$glr_state" verifyGuardManaged 2>/dev/null || true)"
  gc_state_set "$glr_state" "$glr_feature" "$glr_req_art" "activePhase=$glr_phase" \
    "activeStatus=$glr_status" "blockedReason=" "nextStep=$glr_next" || exit 1

  GLR_ST="$glr_state" GLR_BASE="$glr_base" GLR_VGM="$glr_was_vgm" python3 - <<'PY'
import json, os
p = os.environ["GLR_ST"]
base = os.environ["GLR_BASE"]
d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
if base and not d.get("baseCommit"):
    d["baseCommit"] = base
d["releaseGuardManaged"] = True
if os.environ.get("GLR_VGM") in ("True", "true"):
    d["verifyGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY

  mkdir -p "docs/agents-v0/release/${glr_feature}"

  gc_ok start "local-release started for '$glr_feature' (status: $glr_status)"
  printf 'Next: Sync README/CHANGELOG if needed, run final native stack verify into %s, populate ## Proposed lessons in %s, then run %s ready %s\n' \
    "$glr_output" "$glr_result" "$G" "$glr_feature"
}

glr_block() {
  glr_b_slug=""
  glr_b_reason=""
  glr_b_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        glr_b_maint=1
        shift
        ;;
      -*)
        glr_usage
        ;;
      *)
        if [ -z "$glr_b_slug" ]; then
          glr_b_slug="$1"
        elif [ -z "$glr_b_reason" ]; then
          glr_b_reason="$1"
        else
          glr_usage
        fi
        shift
        ;;
    esac
  done

  glr_load block "$glr_b_slug" "$glr_b_maint"
  [ -n "$(printf '%s' "$glr_b_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason; pass a plain-text explanation"
  [ -f "$glr_state" ] || gc_refuse block "local-release for '$glr_feature' has not been started ($glr_state missing)"
  [ "$(gc_state_get "$glr_state" activePhase)" = "$glr_phase" ] \
    || gc_refuse block "activePhase for '$glr_feature' is '$(gc_state_get "$glr_state" activePhase)', not '$glr_phase'"

  glr_rule block block.next "$glr_feature"; glr_next="$glr_val"
  glr_rule block block.status "$glr_feature"; glr_status="$glr_val"

  glr_was_vgm="$(gc_state_get "$glr_state" verifyGuardManaged 2>/dev/null || true)"
  glr_was_rgm="$(gc_state_get "$glr_state" releaseGuardManaged 2>/dev/null || true)"
  gc_state_set "$glr_state" "$glr_feature" "$glr_req_art" "activePhase=$glr_phase" \
    "activeStatus=$glr_status" "blockedReason=$glr_b_reason" "nextStep=$glr_next" || exit 1

  GLR_ST="$glr_state" GLR_VGM="$glr_was_vgm" GLR_RGM="$glr_was_rgm" python3 - <<'PY'
import json, os
p = os.environ["GLR_ST"]
if os.path.isfile(p):
    d = json.load(open(p, encoding="utf-8"))
    if os.environ.get("GLR_VGM") in ("True", "true"):
        d["verifyGuardManaged"] = True
    if os.environ.get("GLR_RGM") in ("True", "true"):
        d["releaseGuardManaged"] = True
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
PY

  gc_ok block "local-release for '$glr_feature' marked blocked ($glr_b_reason)"
}

# Design: DLR3 (/v0-local-release ready gate: final native verify log check, proposed lessons collection, and check-lessons.sh enforcement).
glr_ready() {
  glr_r_slug=""
  glr_r_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        glr_r_maint=1
        shift
        ;;
      -*)
        glr_usage
        ;;
      *)
        [ -z "$glr_r_slug" ] || glr_usage
        glr_r_slug="$1"
        shift
        ;;
    esac
  done

  glr_load ready "$glr_r_slug" "$glr_r_maint"
  glr_rule ready ready.requires "$glr_feature"; glr_requires="$glr_val"
  glr_check_prereqs ready "$glr_requires"

  # Auto-bounce to /v0-verify if any non-doc files drifted since Verify approval
  glr_check_non_doc_drift ready

  # 1. Verify final native stack output log exists, is non-empty, and has no failure markers
  [ -s "$glr_output" ] \
    || gc_refuse ready "missing or empty final native verify log '$glr_output'; run the final native stack verify command into '$glr_output' before ready"

  glr_log_bad="$(GLR_OUT="$glr_output" python3 - <<'PYLOG'
import os, re
txt = open(os.environ["GLR_OUT"], encoding="utf-8", errors="replace").read()
patterns = [
    ("BUILD FAILURE", re.compile(r"\bBUILD FAILURE\b")),
    ("FAIL marker", re.compile(r"(?m)^\s*(?:FAIL:|FAILED\b|\[ERROR\]\s+Tests\s+run:)")),
    ("non-zero test failures", re.compile(r"Tests run:\s*\d+,\s*Failures:\s*[1-9]\d*")),
    ("non-zero test errors", re.compile(r"Tests run:\s*\d+,\s*Failures:\s*\d+,\s*Errors:\s*[1-9]\d*")),
]
for label, rx in patterns:
    m = rx.search(txt)
    if m:
        print(f"{label} ({m.group(0).strip()[:80]})")
        break
PYLOG
)"
  if [ -n "$glr_log_bad" ]; then
    gc_refuse ready "final native verify log '$glr_output' is not green: $glr_log_bad"
  fi

  if [ -f "$GC_HERE/check-tests-ran.sh" ]; then
    if ! glr_tr_out="$(sh "$GC_HERE/check-tests-ran.sh" 2>&1)"; then
      gc_refuse ready "check-tests-ran.sh failed: $glr_tr_out"
    fi
  fi

  # 2. Resolve integration ref for check-lessons.sh --unchanged-since
  glr_int_ref="main"
  if [ -f "$GC_HERE/resolve-integration-branch.sh" ]; then
    glr_resolved="$(sh "$GC_HERE/resolve-integration-branch.sh" 2>/dev/null || true)"
    [ -z "$glr_resolved" ] || glr_int_ref="$glr_resolved"
  fi

  # 3. Ensure phase-result exists before first check-lessons.sh pass
  mkdir -p "$(dirname "$glr_result")"
  if [ ! -f "$glr_result" ]; then
    cat >"$glr_result" <<EOF
phase: release
status: awaiting_approval
feature: $glr_feature
guard_managed: true

# Phase Result: $glr_feature (release)

## Summary
- Final native stack verification passed (\`$glr_output\`).

## Lessons
### release
- none

## Proposed lessons
- none
EOF
  fi

  # 4. Pass 1 of check-lessons.sh (--unchanged-since <integration-ref> --phase-result <phase-result>)
  if [ -f "$GC_HERE/check-lessons.sh" ]; then
    if ! glr_cl1="$(sh "$GC_HERE/check-lessons.sh" --unchanged-since "$glr_int_ref" --phase-result "$glr_result" 2>&1)"; then
      gc_refuse ready "check-lessons.sh failed before proposal collection: $glr_cl1"
    fi
  fi

  # 5. Normalize phase-result header (phase: release, status: awaiting_approval, guard_managed: true)
  #    and collect any ## Lessons candidates into ## Proposed lessons if not already populated
  GLR_RES="$glr_result" GLR_SLUG="$glr_feature" python3 - <<'PYPR'
import os, re
from pathlib import Path

pr_path = Path(os.environ["GLR_RES"])
slug = os.environ["GLR_SLUG"]
txt = pr_path.read_text(encoding="utf-8")

def norm_text(v):
    return re.sub(r"\s+", " ", (v or "").strip()).rstrip(".").lower()

# Load active lessons from docs/agents-v0/lessons.md to drop exact duplicates
active_pairs = set()
lessons_path = Path("docs/agents-v0/lessons.md")
if lessons_path.is_file():
    ltxt = re.sub(r"<!--.*?-->", "", lessons_path.read_text(encoding="utf-8"), flags=re.S)
    cur_what, cur_do = "", ""
    for line in ltxt.splitlines():
        if line.startswith("### L-"):
            if cur_what or cur_do:
                active_pairs.add((cur_what, cur_do))
            cur_what, cur_do = "", ""
        elif line.startswith("- What happened:"):
            cur_what = norm_text(line.partition(":")[2])
        elif line.startswith("- Do instead:"):
            cur_do = norm_text(line.partition(":")[2])
    if cur_what or cur_do:
        active_pairs.add((cur_what, cur_do))

# Update or prepend header keys
if re.search(r"(?m)^phase:\s*\S+", txt):
    txt = re.sub(r"(?m)^phase:\s*\S+", "phase: release", txt, count=1)
else:
    txt = "phase: release\n" + txt

if re.search(r"(?m)^status:\s*\S+", txt):
    txt = re.sub(r"(?m)^status:\s*\S+", "status: awaiting_approval", txt, count=1)
else:
    txt = re.sub(r"(?m)^(phase:\s*\S+)", r"\1\nstatus: awaiting_approval", txt, count=1)

if re.search(r"(?m)^guard_managed:\s*\S+", txt):
    txt = re.sub(r"(?m)^guard_managed:\s*\S+", "guard_managed: true", txt, count=1)
else:
    txt = re.sub(r"(?m)^(status:\s*\S+)", r"\1\nguard_managed: true", txt, count=1)

clean = re.sub(r"<!--.*?-->", "", txt, flags=re.S)

# Parse ## Lessons candidates
lessons_candidates = []
m_les = re.search(r"(?m)^##\s+Lessons\s*$", clean, re.I)
if m_les:
    rest = clean[m_les.end():]
    m_next = re.search(r"(?m)^#{1,2}\s", rest)
    les_body = rest[:m_next.start()] if m_next else rest
    cur_ph = "release"
    for line in les_body.splitlines():
        hm = re.match(r"^###\s+(\S+)\s*$", line.strip())
        if hm:
            cur_ph = hm.group(1).lower()
            continue
        if line.startswith("- ") and not re.match(r"^-\s+none\.?\s*$", line.strip(), re.I):
            bullet_body = line[2:].strip()
            w_m = re.search(r"What happened:\s*(.*?)(?=\s+·\s+(?:Trigger|What happened|Do instead|Scope):|$)", bullet_body)
            d_m = re.search(r"Do instead:\s*(.*?)(?=\s+·\s+(?:Trigger|What happened|Do instead|Scope):|$)", bullet_body)
            pair = (norm_text(w_m.group(1) if w_m else ""), norm_text(d_m.group(1) if d_m else ""))
            if pair not in active_pairs:
                lessons_candidates.append((cur_ph, bullet_body))
else:
    txt = txt.rstrip() + "\n\n## Lessons\n### release\n- none\n"

# Check if ## Proposed lessons exists and whether it already has P-<n> entries
clean = re.sub(r"<!--.*?-->", "", txt, flags=re.S)
m_prop = re.search(r"(?m)^##\s+Proposed lessons\s*$", clean, re.I)
has_existing_p = False
if m_prop:
    rest = clean[m_prop.end():]
    m_next = re.search(r"(?m)^#{1,2}\s", rest)
    prop_body = rest[:m_next.start()] if m_next else rest
    for line in prop_body.splitlines():
        if re.match(r"^- P-\d+\s+·\s+", line.strip()):
            has_existing_p = True
            break

if not has_existing_p:
    if lessons_candidates:
        prop_lines = [f"- P-{i} · pending · {ph} · {b}" for i, (ph, b) in enumerate(lessons_candidates, 1)]
    else:
        prop_lines = ["- none"]
    new_sec = "## Proposed lessons\n" + "\n".join(prop_lines) + "\n"
    if m_prop:
        # Replace existing ## Proposed lessons section
        m_prop_raw = re.search(r"(?m)^##\s+Proposed lessons\s*$", txt, re.I)
        if m_prop_raw:
            rest_raw = txt[m_prop_raw.end():]
            m_next_raw = re.search(r"(?m)^#{1,2}\s", rest_raw)
            end_idx = m_prop_raw.end() + (m_next_raw.start() if m_next_raw else len(rest_raw))
            txt = txt[:m_prop_raw.start()] + new_sec + ("\n" + txt[end_idx:].lstrip("\n") if end_idx < len(txt) else "")
    else:
        txt = txt.rstrip() + "\n\n" + new_sec

pr_path.write_text(txt, encoding="utf-8")
PYPR

  # 6. Pass 2 of check-lessons.sh (--unchanged-since <integration-ref> --phase-result <phase-result>)
  if [ -f "$GC_HERE/check-lessons.sh" ]; then
    if ! glr_cl2="$(sh "$GC_HERE/check-lessons.sh" --unchanged-since "$glr_int_ref" --phase-result "$glr_result" 2>&1)"; then
      gc_refuse ready "check-lessons.sh failed after proposal collection: $glr_cl2"
    fi
  fi

  # 7. Secret scan across release output, phase-result, and updated docs
  if [ -f "$GC_HERE/secret_scan.py" ]; then
    glr_sec_out="$(python3 -B - "$GC_HERE" "$glr_output" "$glr_result" "README.md" "CHANGELOG.md" <<'PYSEC'
import os, sys
sys.path.insert(0, sys.argv[1])
import secret_scan
hits = []
for p in sys.argv[2:]:
    if not p or not os.path.isfile(p):
        continue
    txt = open(p, encoding="utf-8", errors="replace").read()
    for line_no, line in enumerate(txt.splitlines(), 1):
        for rule_id, label, rx in secret_scan.CONTENT_RULES:
            if rx.search(line):
                hits.append(f"{p}:{line_no} ({rule_id}: {label})")
if hits:
    print("secret pattern detected in " + ", ".join(hits))
    sys.exit(1)
PYSEC
)" || {
      gc_refuse ready "secret scan failed: $glr_sec_out"
    }
  fi

  # 8. Transition state to awaiting_approval
  glr_base="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
  glr_rule ready ready.next "$glr_feature"; glr_next="$glr_val"
  glr_rule ready ready.status "$glr_feature"; glr_status="$glr_val"

  glr_was_vgm="$(gc_state_get "$glr_state" verifyGuardManaged 2>/dev/null || true)"
  gc_state_set "$glr_state" "$glr_feature" "$glr_req_art" "activePhase=$glr_phase" \
    "activeStatus=$glr_status" "blockedReason=" "nextStep=$glr_next" || exit 1

  GLR_ST="$glr_state" GLR_BASE="$glr_base" GLR_VGM="$glr_was_vgm" python3 - <<'PY'
import json, os
p = os.environ["GLR_ST"]
base = os.environ["GLR_BASE"]
d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
if base:
    d["baseCommit"] = base
d["releaseGuardManaged"] = True
if os.environ.get("GLR_VGM") in ("True", "true"):
    d["verifyGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY

  gc_ok ready "local-release for '$glr_feature' is awaiting Sensei's approval"
  printf 'Stop here. Present the release readiness summary and every P-<n> in %s to Sensei.\n' "$glr_result"
  printf 'Sensei approves from an external terminal with:\n'
  printf '  sh .agents-v0/scripts/guard-common.sh approve local-release %s\n' "$glr_feature"
  printf 'Wait for Sensei to reply in chat before running: %s commit %s\n' "$G" "$glr_feature"
}

# Design: DLR5 (/v0-local-release two-step commit: story-branch release prep commit + integration branch squash/no-ff merge, lesson decisions, --approve release, and check-release-evidence.sh).
glr_commit() {
  glr_m_slug=""
  glr_m_maint=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --maintain)
        glr_m_maint=1
        shift
        ;;
      -*)
        glr_usage
        ;;
      *)
        [ -z "$glr_m_slug" ] || glr_usage
        glr_m_slug="$1"
        shift
        ;;
    esac
  done

  glr_load commit "$glr_m_slug" "$glr_m_maint"
  [ -f "$glr_state" ] || gc_refuse commit "state file '$glr_state' is missing"
  glr_check_prereqs commit "git-work-tree kit-installed feature-branch pack-configured not-released"

  # 1. Verify Sensei's external approval record for local-release <feature>
  if ! glr_ok_msg="$(gc_approval_ok local-release "$glr_feature")"; then
    gc_refuse commit "$glr_ok_msg"
  fi
  glr_app_file="$(gc_approval_file local-release "$glr_feature")"
  glr_words="$(GLR_AF="$glr_app_file" python3 - <<'PYW'
import json, os
d = json.load(open(os.environ["GLR_AF"], encoding="utf-8"))
print(d.get("words") or "")
PYW
)"

  # Refuse if the current worktree index already has staged files
  if ! git diff --cached --quiet --no-ext-diff 2>/dev/null; then
    gc_refuse commit "the git index already holds staged changes; unstage them (git restore --staged .) before running commit"
  fi

  # Re-verify no post-verify non-doc drift occurred before committing
  glr_check_non_doc_drift commit

  glr_sid="$(glr_story_id_of)"
  glr_tier="$(gc_state_get "$glr_state" tier 2>/dev/null || true)"

  # Resolve integration branch name and worktrees
  glr_int_ref="main"
  if [ -f "$GC_HERE/resolve-integration-branch.sh" ]; then
    glr_res_int="$(sh "$GC_HERE/resolve-integration-branch.sh" 2>/dev/null || true)"
    [ -z "$glr_res_int" ] || glr_int_ref="$glr_res_int"
  fi
  glr_int_branch="${glr_int_ref#origin/}"
  [ "$glr_int_branch" != "HEAD" ] || glr_int_branch="main"

  glr_story_branch="feature/$glr_feature"
  if [ "$glr_is_maintain" = 1 ]; then
    if [ "$glr_tier" = "trivial" ]; then
      glr_story_branch="$glr_int_branch"
    else
      glr_story_branch="maintain/$glr_feature"
    fi
  fi

  glr_story_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/$glr_story_branch" '
    /^worktree / { p = substr($0, 10) }
    $0 == want { print p; exit }
  ')"
  glr_int_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/$glr_int_branch" '
    /^worktree / { p = substr($0, 10) }
    $0 == want { print p; exit }
  ')"

  glr_cur_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$glr_story_wt" ] || { [ "$glr_cur_branch" = "$glr_story_branch" ] && glr_story_wt="$(pwd)"; }

  glr_step_a_sha=""
  # --- Step A: Commit release preparation on story branch (when separate from integration branch) ---
  if [ "$glr_story_branch" != "$glr_int_branch" ]; then
    [ -n "$glr_story_wt" ] && [ -d "$glr_story_wt" ] \
      || gc_refuse commit "cannot find worktree for story branch '$glr_story_branch'"
    (
      cd "$glr_story_wt"
      # Ensure state on story branch has activePhase=release, activeStatus=awaiting_approval
      GLR_ST="$glr_state" python3 - <<'PYST'
import json, os
p = os.environ["GLR_ST"]
if os.path.isfile(p):
    d = json.load(open(p, encoding="utf-8"))
    d["activePhase"] = "release"
    d["activeStatus"] = "awaiting_approval"
    d["releaseGuardManaged"] = True
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
PYST
      for glr_p in README.md CHANGELOG.md .gitignore \
        "docs/agents-v0/diagrams" \
        "docs/agents-v0/release/$glr_feature" \
        "docs/agents-v0/verify/$glr_feature" \
        "$glr_req_art" "$glr_state" "$glr_result" \
        "docs/agents-v0/requirements/${glr_feature}.trace.json" \
        "docs/agents-v0/maintain/$glr_feature"; do
        if [ -e "$glr_p" ] || [ -n "$(git ls-files -- "$glr_p" 2>/dev/null)" ]; then
          git add --all -- "$glr_p"
        fi
      done
      git reset -q -- '*.lock' '**/*.lock' 2>/dev/null || true
      if ! git diff --cached --quiet --no-ext-diff 2>/dev/null; then
        gc_scan_staged >/dev/null
        git commit -q -m "${glr_sid}: release approved"
      fi
      # Refuse if story worktree still has uncommitted changes outside release paths
      glr_rem="$(git status --porcelain=v1 -uall 2>/dev/null | grep -v '\.lock$' || true)"
      if [ -n "$glr_rem" ]; then
        gc_refuse commit "story worktree '$glr_story_wt' still has uncommitted changes after staging release paths: $glr_rem"
      fi
    ) || exit 1
    glr_step_a_sha="$(git rev-parse --short "refs/heads/$glr_story_branch" 2>/dev/null || true)"
  fi

  # --- Step B: Integration branch merge, lesson decisions, --approve release, and final commit ---
  if [ -z "$glr_int_wt" ]; then
    # Single-worktree fallback (e.g. when integration branch is not checked out in another worktree)
    git checkout -q "$glr_int_branch" || gc_refuse commit "cannot switch to integration branch '$glr_int_branch'"
    glr_int_wt="$(pwd)"
  fi

  glr_step_b_sha=""
  (
    cd "$glr_int_wt"
    if [ "$glr_story_branch" != "$glr_int_branch" ]; then
      glr_int_dirty="$(git status --porcelain=v1 -uall 2>/dev/null | grep -v '\.lock$' || true)"
      if [ -n "$glr_int_dirty" ]; then
        gc_refuse commit "integration worktree '$glr_int_wt' ($glr_int_branch) has uncommitted changes ($glr_int_dirty); clean or stash them first"
      fi
      if [ "$glr_is_maintain" = 1 ]; then
        if ! git merge --no-ff --no-commit "$glr_story_branch" >/dev/null 2>&1; then
          git merge --abort >/dev/null 2>&1 || git reset --hard -q HEAD >/dev/null 2>&1 || true
          gc_refuse commit "git merge --no-ff $glr_story_branch failed or conflicted in '$glr_int_wt'"
        fi
      else
        if ! git merge --squash "$glr_story_branch" >/dev/null 2>&1; then
          git reset --hard -q HEAD >/dev/null 2>&1 || true
          gc_refuse commit "git merge --squash $glr_story_branch failed or conflicted in '$glr_int_wt'"
        fi
      fi
    fi

    # 1. Run sync-feature-state.sh --approve release while index holds the exact squash-merge tree
    if ! glr_sync_out="$(sh .agents-v0/scripts/sync-feature-state.sh --approve release "$glr_req_art" 2>&1)"; then
      gc_refuse commit "sync-feature-state.sh --approve release failed: $glr_sync_out"
    fi

    # 2. Apply Sensei's lesson decisions from approval words to phase-result and docs/agents-v0/lessons.md
    GLR_RES="$glr_result" GLR_WORDS="$glr_words" GLR_SLUG="$glr_feature" GLR_HERE="$GC_HERE" python3 - <<'PYLES'
import datetime, os, re, subprocess, sys
from pathlib import Path

pr_path = Path(os.environ["GLR_RES"])
words = os.environ["GLR_WORDS"]
slug = os.environ["GLR_SLUG"]
here = os.environ["GLR_HERE"]

FIELD_RE = re.compile(r"(Trigger|What happened|Do instead|Scope):\s*(.*?)(?=\s+·\s+(?:Trigger|What happened|Do instead|Scope):|$)")

def parse_approval(text, proposed_ids):
    problems, accepted, rejected = [], set(), set()
    pid_list = r"P-\d+(?:\s*(?:,|and|&|\+)\s*P-\d+)*"
    for m in re.finditer(rf"\b(accept(?:ed|s|ing)?|keep|reject(?:ed|s|ing)?|drop)\s+({pid_list})(\s+if\s+proposed)?",
                         text, re.I):
        verb = m.group(1).lower()
        ids = [x.upper() for x in re.findall(r"P-\d+", m.group(2), re.I)]
        tolerant = bool(m.group(3))
        for pid in ids:
            if pid not in proposed_ids:
                if not tolerant:
                    problems.append(f"the approval {'accepts' if verb[0] in 'ak' else 'rejects'} {pid}, which is not in ## Proposed lessons")
                continue
            (accepted if verb[0] in "ak" else rejected).add(pid)
    both = sorted(accepted & rejected, key=lambda x: int(x[2:]))
    for pid in both:
        problems.append(f"the approval both accepts and rejects {pid}")
    if re.search(r"\b(?:accept|keep)\s+all\b", text, re.I):
        accepted |= set(proposed_ids) - rejected
    return accepted - rejected, problems

txt = pr_path.read_text(encoding="utf-8")
lines = txt.splitlines()
prop_ids = []
prop_meta = {}
in_prop = False
for line in lines:
    if re.match(r"^##\s+Proposed lessons\s*$", line, re.I):
        in_prop = True
        continue
    if in_prop and re.match(r"^#{1,2}\s", line):
        in_prop = False
        continue
    if in_prop:
        m = re.match(r"^- (P-\d+)\s+·\s+(pending|accepted|rejected)\s+·\s+(\S+)\s+·\s+(.*)$", line)
        if m:
            pid = m.group(1).upper()
            prop_ids.append(pid)
            prop_meta[pid] = {"phase": m.group(3).lower(), "rest": m.group(4), "fields": dict(FIELD_RE.findall(m.group(4)))}

want, problems = parse_approval(words, prop_ids)
if problems:
    print("; ".join(problems), file=sys.stderr)
    sys.exit(1)

new_lines = []
in_prop = False
for line in lines:
    if re.match(r"^status:\s*\S+", line):
        new_lines.append("status: approved")
        continue
    if re.match(r"^##\s+Proposed lessons\s*$", line, re.I):
        in_prop = True
        new_lines.append(line)
        continue
    if in_prop and re.match(r"^#{1,2}\s", line):
        in_prop = False
        new_lines.append(line)
        continue
    if in_prop:
        m = re.match(r"^- (P-\d+)\s+·\s+(pending|accepted|rejected)\s+·\s+(\S+)\s+·\s+(.*)$", line)
        if m:
            pid = m.group(1).upper()
            dec = "accepted" if pid in want else "rejected"
            new_lines.append(f"- {pid} · {dec} · {m.group(3)} · {m.group(4)}")
            continue
    new_lines.append(line)

pr_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")

# Append accepted lessons to docs/agents-v0/lessons.md if not already present
lessons_path = Path("docs/agents-v0/lessons.md")
today = datetime.date.today().isoformat()
for pid in prop_ids:
    if pid not in want:
        continue
    meta = prop_meta[pid]
    f = meta["fields"]
    # Check if already present for this story
    if lessons_path.is_file():
        ltxt = lessons_path.read_text(encoding="utf-8")
    else:
        lessons_path.parent.mkdir(parents=True, exist_ok=True)
        ltxt = "# Lessons\n\n## Active lessons\n_No entries yet._\n"
        lessons_path.write_text(ltxt, encoding="utf-8")

    # Get next L-NNN id from check-lessons.sh --next-id
    r = subprocess.run(["sh", os.path.join(here, "check-lessons.sh"), "--next-id"], capture_output=True, text=True, check=True)
    lid = r.stdout.strip()
    entry = (
        f"### {lid} · {today} · accepted\n"
        f"- Story/phase: {slug} / {meta['phase']}\n"
        f"- Trigger: {f.get('Trigger', 'other').strip()}\n"
        f"- What happened: {f.get('What happened', '').strip()}\n"
        f"- Do instead: {f.get('Do instead', '').strip()}\n"
        f"- Scope: {f.get('Scope', 'repo').strip()}\n"
    )
    ltxt = re.sub(r"(?m)^_No entries yet\._\s*\n?", "", ltxt)
    if re.search(r"(?m)^##\s+Active lessons\s*$", ltxt):
        ltxt = ltxt.rstrip() + "\n\n" + entry
    else:
        ltxt = ltxt.rstrip() + "\n\n## Active lessons\n\n" + entry
    lessons_path.write_text(ltxt, encoding="utf-8")
PYLES

    if [ -f .agents-v0/scripts/check-lessons.sh ]; then
      if ! glr_cld="$(sh .agents-v0/scripts/check-lessons.sh --decided --phase-result "$glr_result" 2>&1)"; then
        gc_refuse commit "check-lessons.sh --decided failed: $glr_cld"
      fi
      if ! glr_cla="$(sh .agents-v0/scripts/check-lessons.sh 2>&1)"; then
        gc_refuse commit "check-lessons.sh failed: $glr_cla"
      fi
      if ! glr_clm="$(sh .agents-v0/scripts/check-lessons.sh --phase-result "$glr_result" --approval-text "$glr_words" 2>&1)"; then
        gc_refuse commit "check-lessons.sh --approval-text failed: $glr_clm"
      fi
    fi

    # 3. Record Release approval row in requirement / maintenance artifact
    GLR_ART="$glr_req_art" GLR_APP_FILE="$glr_app_file" python3 - <<'PYART'
import datetime, json, os, re
from pathlib import Path

art = Path(os.environ["GLR_ART"])
if not art.is_file():
    raise SystemExit(0)
rec = json.load(open(os.environ["GLR_APP_FILE"], encoding="utf-8"))
approver = rec.get("approver") or "sensei"
date_str = (rec.get("approvedAt") or datetime.date.today().isoformat())[:10]
txt = art.read_text(encoding="utf-8")
if re.search(r"(?im)^\|\s*Release\s*\|", txt):
    txt = re.sub(
        r"(?im)^\|\s*Release\s*\|[^\n]*\|",
        f"| Release | Approved | {approver} | {date_str} | Approved via guard-local-release.sh |",
        txt,
    )
elif re.search(r"(?im)^##\s+Delivery approvals\b", txt):
    txt = txt.rstrip() + f"\n| Release | Approved | {approver} | {date_str} | Approved via guard-local-release.sh |\n"
art.write_text(txt, encoding="utf-8")
PYART

    # 4. Stage updated docs/agents-v0 files, scan staged for secrets, and commit
    for glr_f in "$glr_req_art" "$glr_state" "$glr_result" "docs/agents-v0/lessons.md" "docs/agents-v0/lessons-archive.md"; do
      if [ -e "$glr_f" ]; then
        git add -- "$glr_f"
      fi
    done
    git reset -q -- '*.lock' '**/*.lock' 2>/dev/null || true

    glr_gate_msg="$(git rev-parse --git-path agents-v0-gate-msg.txt 2>/dev/null || true)"
    if [ "$glr_is_maintain" = 0 ] && [ -n "$glr_gate_msg" ] && [ -f "$glr_gate_msg" ]; then
      gc_scan_staged --message-file "$glr_gate_msg" >/dev/null
      git commit -q -F "$glr_gate_msg" || gc_refuse commit "git commit -F $glr_gate_msg failed"
    else
      gc_scan_staged >/dev/null
      git commit -q -m "${glr_sid}: release approved" || gc_refuse commit "git commit failed on '$glr_int_branch'"
    fi

    # 5. Verify check-release-evidence.sh for feature stories
    if [ "$glr_is_maintain" = 0 ] && [ -f .agents-v0/scripts/check-release-evidence.sh ]; then
      if ! glr_cre="$(sh .agents-v0/scripts/check-release-evidence.sh "$glr_req_art" 2>&1)"; then
        gc_refuse commit "check-release-evidence.sh failed after squash commit: $glr_cre"
      fi
    fi
  ) || exit 1

  glr_step_b_sha="$(git -C "$glr_int_wt" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$glr_step_a_sha" ]; then
    gc_ok commit "local-release committed: story branch $glr_story_branch ($glr_step_a_sha) + integration branch $glr_int_branch ($glr_step_b_sha)"
    printf 'Commits made:\n'
    printf '  1. %s (%s): %s: release approved\n' "$glr_step_a_sha" "$glr_story_branch" "$glr_sid"
    printf '  2. %s (%s): %s\n' "$glr_step_b_sha" "$glr_int_branch" "$(git -C "$glr_int_wt" log -1 --format=%s HEAD)"
  else
    gc_ok commit "local-release committed on integration branch $glr_int_branch ($glr_step_b_sha)"
    printf 'Commits made:\n'
    printf '  1. %s (%s): %s\n' "$glr_step_b_sha" "$glr_int_branch" "$(git -C "$glr_int_wt" log -1 --format=%s HEAD)"
  fi
}

# Design: DLR6 (/v0-local-release generated steps block).
glr_steps() {
  cat <<'EOF'
1. Run `sh .agents-v0/scripts/guard-local-release.sh check <feature> [--maintain]`. It validates the `<feature>` slug, blocks `p0-a*` (redirecting to `/v0-scaffold`), verifies the current checkout is the `feature/<feature>` worktree (or `maintain/<id>` for a maintenance note), checks `docs/agents-v0/project-profile.md` Pack configuration, confirms the story is not already released, and verifies `verify` is approved with `"verifyPassed": true`, Sensei's external `verify` approval record, and committed Verify gate (or `tier: "emergency"` maintenance note with rollback plan and `Follow-up verify due`). When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-local-release.sh start <feature> [--maintain]`. It checks for post-Verify non-doc drift: if any file outside `docs/`, `README.md`, `CHANGELOG.md`, or `.gitignore` changed since the Verify gate commit, `start` automatically reopens `verify` (`verifyPassed: false`), increments `reopenCount`, and exits with `REFUSED start: BOUNCED` routing back to `/v0-verify <feature>`. Otherwise it creates `docs/agents-v0/release/<feature>/` and sets `activePhase: "release"`, `activeStatus: "in_progress"`.
3. Execute the release preparation and final native stack check in the main session with the shell-less `release-manager` subagent (skill: `local-release`):
   - **Changelog & Final Native Stack Check (main session):** When the profile uses a changelog, run `sh .agents-v0/scripts/release-notes.sh docs/agents-v0/requirements/<feature>.md --include-unreleased --insert CHANGELOG.md`. Resolve the final verify command with `sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`, execute the printed command into `docs/agents-v0/release/<feature>/release-output.txt`, and run `sh .agents-v0/scripts/check-tests-ran.sh docs/agents-v0/release/<feature>/release-output.txt` after Maven output. If the tree is not green, run `sh .agents-v0/scripts/guard-local-release.sh block <feature> "<plain reason>"` and stop.
   - **Docs Sync & Proposed Lessons (`release-manager`, no shell):** Launch shell-less `release-manager` to sync `README.md` or sequence diagrams (`docs/agents-v0/diagrams/`) when user-facing setup or flows changed, add at most 3 `### release` candidates under `## Lessons` in `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md`), and collect every candidate across `## Lessons` into `## Proposed lessons` as `- P-<n> · pending · <phase> · Trigger: … · What happened: … · Do instead: … · Scope: …` (or `- none`), dropping exact duplicates of active entries in `docs/agents-v0/lessons.md`. A story branch never edits `docs/agents-v0/lessons.md`.
4. Run `sh .agents-v0/scripts/guard-local-release.sh ready <feature> [--maintain]`. It verifies `docs/agents-v0/release/<feature>/release-output.txt` is non-empty and green, re-checks post-Verify non-doc drift, runs `sh .agents-v0/scripts/check-lessons.sh --unchanged-since <integration-ref> --phase-result <phase-result>` before and after normalizing `## Proposed lessons`, scans for secrets, and sets `activePhase: "release"`, `activeStatus: "awaiting_approval"`.
5. Stop. Present the release readiness summary and every `P-<n>` in `## Proposed lessons` to Sensei and wait for explicit approval (asking Sensei to accept or reject each `P-<n>`; any `P-<n>` not explicitly accepted is marked `rejected`). Next: Sensei reviews the release summary and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve local-release <feature>. Never run approve yourself; the agent cannot approve this gate.
6. After Sensei runs approve in his own terminal, run `sh .agents-v0/scripts/guard-local-release.sh commit <feature> [--maintain]`. It verifies Sensei's external approval record, commits the release preparation (`"<story>: release approved"`) on `feature/<feature>` (or `maintain/<id>`), switches to the integration worktree resolved by `sh .agents-v0/scripts/resolve-integration-branch.sh`, runs `git merge --squash feature/<feature>` (or `git merge --no-ff --no-commit maintain/<id>`), marks each `P-<n>` `accepted` or `rejected` from Sensei's verbatim approval words, appends accepted entries to `docs/agents-v0/lessons.md` using `check-lessons.sh --next-id`, validates with `check-lessons.sh --decided` and `check-lessons.sh --phase-result <phase-result> --approval-text '<Sensei words>'`, records the `Release` approval on the integration branch, commits the single squash commit (`"<story>: release approved (squash-merge of feature/<feature>)"` with `Story-Branch: feature/<feature>` and `Story-Tip: <tip>` trailers), and runs `sh .agents-v0/scripts/check-release-evidence.sh docs/agents-v0/requirements/<feature>.md`.
7. <!-- kitfix-20261031-keep-branches --> <!-- kitfix-20261029-step4-p1e --> Keep `feature/<feature>` and `maintain/<id>` branches after release (never delete or rename them, and never commit or modify state on the story branch after merge). List every commit made in this turn (short SHA, branch, subject) across both worktrees. When `docs/agents-v0/project-profile.md` defines a **Deploy** table, follow `release-deploy` (one explicit authorization per environment, a smoke check, and a rollback command).
EOF
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
