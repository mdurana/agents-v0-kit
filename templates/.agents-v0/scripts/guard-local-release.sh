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
    d["reopenCount"] = int(d.get("reopenCount") or 0) + 1
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
  [ -n "$glr_b_reason" ] || gc_refuse block "missing block reason; pass a plain-text explanation"
  case "$glr_b_reason" in
    *"$gc_nl"*) gc_refuse block "block reason must be a single line" ;;
  esac
  glr_rule block block.requires "$glr_feature"; glr_requires="$glr_val"
  glr_check_prereqs block "$glr_requires"

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

  if grep -Eq 'Tests run:|\[INFO\] ---' "$glr_output" 2>/dev/null && [ -f "$GC_HERE/check-tests-ran.sh" ]; then
    if ! glr_tr_out="$(sh "$GC_HERE/check-tests-ran.sh" "$glr_output" 2>&1)"; then
      gc_refuse ready "check-tests-ran.sh failed on '$glr_output': $glr_tr_out"
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
    glr_scan_files="$glr_output $glr_result"
    [ ! -f "README.md" ] || glr_scan_files="$glr_scan_files README.md"
    [ ! -f "CHANGELOG.md" ] || glr_scan_files="$glr_scan_files CHANGELOG.md"
    # shellcheck disable=SC2086
    if ! glr_sec_out="$(python3 "$GC_HERE/secret_scan.py" $glr_scan_files 2>&1)"; then
      gc_refuse ready "secret scan failed: $glr_sec_out"
    fi
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
