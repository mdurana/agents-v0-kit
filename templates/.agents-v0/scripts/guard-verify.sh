#!/bin/sh
# guard-verify.sh — single entry point and security boundary for /v0-verify.
# Usage:
#   sh .agents-v0/scripts/guard-verify.sh check <feature> [--reopen]
#   sh .agents-v0/scripts/guard-verify.sh start <feature> [--reopen] [--check-db]
#   sh .agents-v0/scripts/guard-verify.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-verify.sh ready <feature>
#   sh .agents-v0/scripts/guard-verify.sh commit <feature>
#   sh .agents-v0/scripts/guard-verify.sh steps
#
# Design: DV1 (/v0-verify guard and parameterized per-story verify gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-verify.sh"

gv_usage() {
  printf 'usage: %s check <feature> [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen] [--check-db]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gv_validate_slug() {
  gv_v_step="$1"
  gv_v_slug="${2:-}"
  [ -n "$gv_v_slug" ] || gc_refuse "$gv_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gv_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gv_v_step" "feature slug '$gv_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gv_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gv_v_step" "feature slug '$gv_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gv_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gv_v_step" "story '$gv_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-verify"
      ;;
  esac
}

gv_rule() {
  gv_step="$1"
  gv_key="$2"
  gv_slug="${3:-}"
  gv_rules="${GC_HERE}/../gate-rules"
  [ -f "$gv_rules" ] || gc_refuse "$gv_step" "missing gate-rules file ($gv_rules)"
  gv_val="$(awk -v p="verify" -v k="$gv_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gv_rules")"
  [ -n "$gv_val" ] || gc_refuse "$gv_step" "gate-rules missing key '$gv_key' for phase 'verify'"
  if [ -n "$gv_slug" ]; then
    gv_val="$(printf '%s' "$gv_val" | sed "s/<feature>/$gv_slug/g")"
  fi
}

gv_load() {
  gv_step="$1"
  gv_slug="$2"
  gv_validate_slug "$gv_step" "$gv_slug"
  gc_to_root "$gv_step"
  gv_rule "$gv_step" phase "$gv_slug"; gv_phase="$gv_val"
  gv_rule "$gv_step" feature "$gv_slug"; gv_feature="$gv_val"
  gv_rule "$gv_step" state "$gv_slug"; gv_state="$gv_val"
  gv_rule "$gv_step" artifact "$gv_slug"; gv_artifact="$gv_val"
  gv_rule "$gv_step" vapt "$gv_slug"; gv_vapt="$gv_val"
  gv_rule "$gv_step" review "$gv_slug"; gv_review="$gv_val"
  gv_rule "$gv_step" output "$gv_slug"; gv_output="$gv_val"
  gv_rule "$gv_step" result "$gv_slug"; gv_result="$gv_val"
  gv_req_art="docs/agents-v0/requirements/${gv_feature}.md"
  gv_is_maintain=0
  if [ ! -f "$gv_req_art" ] && [ -f "docs/agents-v0/maintain/${gv_feature}/note.md" ]; then
    gv_is_maintain=1
    gv_req_art="docs/agents-v0/maintain/${gv_feature}/note.md"
    gv_state="docs/agents-v0/maintain/${gv_feature}/state.json"
    gv_result="docs/agents-v0/maintain/${gv_feature}/phase-result.md"
  fi
}

gv_check_prereqs() {
  gv_step="$1"
  gv_reqs="$2"
  gv_reopen="${3:-0}"
  gv_rule "$gv_step" approved.next "$gv_feature"; gv_approved_next="$gv_val"

  for gv_req in $gv_reqs; do
    case "$gv_req" in
      git-work-tree) ;;
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gv_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      feature-branch)
        gv_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gv_skip_bg=1
        # <<< kit-test-override
        if [ "$gv_skip_bg" != 1 ]; then
          gv_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [ "$gv_is_maintain" = 1 ]; then
            gv_tier="$(gc_state_get "$gv_state" tier 2>/dev/null || true)"
            gv_rel_ok=0
            case " $(gc_state_get "$gv_state" approvedPhases 2>/dev/null | tr -d '[]",') " in *" release "*) gv_rel_ok=1 ;; esac
            if [ "$gv_tier" != "trivial" ] && ! { [ "$gv_tier" = "emergency" ] && [ "$gv_rel_ok" = 1 ]; }; then
              if [ "$gv_cur" != "maintain/$gv_feature" ]; then
                gc_refuse "$gv_step" "verify for maintenance note '$gv_feature' must run on branch 'maintain/$gv_feature' (current branch: '${gv_cur:-detached}')"
              fi
            fi
          else
            if [ "$gv_cur" != "feature/$gv_feature" ]; then
              gv_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${gv_feature}" '
                /^worktree / { path = substr($0, 10) }
                $0 == want { print path; exit }
              ')"
              if [ -n "$gv_wt" ]; then
                gc_refuse "$gv_step" "verify for '$gv_feature' must run in worktree '$gv_wt' on branch 'feature/$gv_feature' (current branch: '${gv_cur:-detached}'). Open that folder and run /v0-verify $gv_feature there"
              else
                gc_refuse "$gv_step" "no 'feature/$gv_feature' branch or worktree exists (current branch: '${gv_cur:-detached}'); complete /v0-intake $gv_feature (approve + guard-intake.sh commit $gv_feature) first"
              fi
            fi
          fi
        fi
        ;;
      pack-configured)
        if [ -f "docs/agents-v0/project-profile.md" ] && [ -d ".agents-v0/packs" ]; then
          gv_pack="$(awk -F'|' '
            function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
            tolower($0) ~ /\|[ \t]*pack[ \t]*\|/ {
              v = trim($3)
              gsub(/<!--.*-->/, "", v)
              v = trim(v)
              if (v != "" && v !~ /^</) { print v; exit }
            }
          ' docs/agents-v0/project-profile.md)"
          if [ -n "$gv_pack" ] && [ ! -f ".agents-v0/packs/$gv_pack/pack.json" ]; then
            gc_refuse "$gv_step" "project-profile.md names Pack '$gv_pack', but '.agents-v0/packs/$gv_pack/pack.json' is missing"
          fi
        fi
        ;;
      not-released)
        if [ -f "$gv_state" ]; then
          gv_tier="$(gc_state_get "$gv_state" tier 2>/dev/null || true)"
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              if [ "$gv_is_maintain" = 1 ] && [ "$gv_tier" = "emergency" ]; then
                case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
                  *" verify "*) gc_refuse "$gv_step" "emergency maintenance note '$gv_feature' already has release and verify approved; start a new maintenance id" ;;
                esac
              else
                gc_refuse "$gv_step" "story '$gv_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              fi
              ;;
          esac
        fi
        ;;
      build-approved)
        [ -f "$gv_req_art" ] \
          || gc_refuse "$gv_step" "primary artifact '$gv_req_art' is missing; complete /v0-intake, /v0-design, and /v0-build $gv_feature first"
        [ -f "$gv_state" ] \
          || gc_refuse "$gv_step" "state file '$gv_state' is missing; complete /v0-intake, /v0-design, and /v0-build $gv_feature first"
        if [ "$gv_is_maintain" = 1 ]; then
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" maintain "*) ;;
            *) gc_refuse "$gv_step" "maintain is not in approvedPhases in '$gv_state'; complete /v0-maintain $gv_feature first" ;;
          esac
        else
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" build "*) ;;
            *) gc_refuse "$gv_step" "build is not in approvedPhases in '$gv_state'; complete /v0-build $gv_feature first" ;;
          esac
          gv_bgm="$(gc_state_get "$gv_state" buildGuardManaged 2>/dev/null || true)"
          if [ "$gv_bgm" = "True" ] || [ "$gv_bgm" = "true" ]; then
            if ! gv_bld_ok="$(gc_approval_ok build "$gv_feature")"; then
              gc_refuse "$gv_step" "external build approval record missing or mismatched ($gv_bld_ok); complete /v0-build $gv_feature first"
            fi
          fi
        fi
        gv_skip_cc=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gv_skip_cc=1
        # <<< kit-test-override
        if [ "$gv_skip_cc" != 1 ] && [ -f "$GC_HERE/check-gate-commit.sh" ] && [ "$gv_reopen" != 1 ]; then
          gv_prev_act="$(gc_state_get "$gv_state" activePhase 2>/dev/null || true)"
          if [ -z "$gv_prev_act" ]; then
            if ! gv_cc_out="$(sh "$GC_HERE/check-gate-commit.sh" "$gv_req_art" 2>&1)"; then
              gc_refuse "$gv_step" "build gate is not committed on feature/$gv_feature: $gv_cc_out"
            fi
          fi
        fi
        ;;
      not-approved)
        if [ "$gv_reopen" != 1 ] && [ -f "$gv_state" ]; then
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" $gv_phase "*)
              gc_refuse "$gv_step" "verify is already approved for '$gv_feature'; suggest $gv_approved_next (or pass --reopen to reopen verify)"
              ;;
          esac
        fi
        if [ "$gv_reopen" = 1 ] && [ -f "$gv_state" ]; then
          gv_rc="$(gc_state_get "$gv_state" reopenCount 2>/dev/null || echo 0)"
          case "$gv_rc" in ''|*[!0-9]*) gv_rc=0 ;; esac
          if [ "$gv_rc" -ge 3 ]; then
            gc_refuse "$gv_step" "reopen bounce cap exceeded for '$gv_feature' (reopenCount=$gv_rc >= 3); escalate to Sensei before reopening again"
          fi
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gv_state" ]; then
          [ "$(gc_state_get "$gv_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gv_step" "verify for '$gv_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve verify $gv_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gv_state" ] || gc_refuse "$gv_step" "verify for '$gv_feature' has not been started; run $G start $gv_feature first"
        [ "$(gc_state_get "$gv_state" activePhase)" = "$gv_phase" ] \
          || gc_refuse "$gv_step" "activePhase for '$gv_feature' is '$(gc_state_get "$gv_state" activePhase)', not '$gv_phase'; run $G start $gv_feature first"
        [ "$(gc_state_get "$gv_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gv_step" "verify for '$gv_feature' is not in_progress (status: $(gc_state_get "$gv_state" activeStatus)); run $G start $gv_feature first"
        ;;
      *) gc_refuse "$gv_step" "gate-rules names an unknown prerequisite '$gv_req'; reinstall the kit" ;;
    esac
  done
}

gv_check() {
  gv_c_slug=""
  gv_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gv_c_reopen=1
        shift
        ;;
      -*)
        gv_usage
        ;;
      *)
        [ -z "$gv_c_slug" ] || gv_usage
        gv_c_slug="$1"
        shift
        ;;
    esac
  done

  gv_load check "$gv_c_slug"
  gv_rule check check.requires "$gv_feature"; gv_requires="$gv_val"
  gv_check_prereqs check "$gv_requires" "$gv_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-verify $gv_feature"
  if [ "$gv_c_reopen" = 1 ]; then
    printf 'Next: Start reopened verify with: %s start %s --reopen\n' "$G" "$gv_feature"
  else
    printf 'Next: Start verify with: %s start %s\n' "$G" "$gv_feature"
  fi
}

# Design: DV2 (/v0-verify start, block, reopen, and helper-brief deduplication).
gv_start() {
  gv_s_slug=""
  gv_s_reopen=0
  gv_s_check_db=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gv_s_reopen=1
        shift
        ;;
      --check-db)
        gv_s_check_db=1
        shift
        ;;
      -*)
        gv_usage
        ;;
      *)
        [ -z "$gv_s_slug" ] || gv_usage
        gv_s_slug="$1"
        shift
        ;;
    esac
  done

  gv_load start "$gv_s_slug"
  gv_rule start start.requires "$gv_feature"; gv_requires="$gv_val"
  gv_check_prereqs start "$gv_requires" "$gv_s_reopen"
  if [ "$gv_s_reopen" != 1 ]; then
    gv_check_prereqs start "not-approved" 0
  else
    gv_check_prereqs start "not-approved" 1
  fi

  # Collision guard: refuse unrelated dirty paths outside verify/app/requirements/<feature>
  gv_dirty="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | grep -v '\.lock$' | grep -Ev "^(app/|docs/agents-v0/verify/${gv_feature}/|docs/agents-v0/design/system/slo-evidence\\.md$|docs/agents-v0/requirements/${gv_feature}\\.|docs/agents-v0/maintain/${gv_feature}/)" || true)"
  if [ -n "$gv_dirty" ]; then
    gc_refuse start "working tree has uncommitted changes outside verify paths ($gv_dirty); commit or stash them first"
  fi

  if [ "$gv_s_check_db" = 1 ] && [ -f "$GC_HERE/check-database-runtime.sh" ]; then
    if ! gv_db_out="$(sh "$GC_HERE/check-database-runtime.sh" --phase verify "$gv_req_art" 2>&1)"; then
      gc_refuse start "database runtime unavailable ($gv_db_out); run $G block $gv_feature \"Database runtime unavailable\" and stop"
    fi
  fi

  gv_base="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
  gv_rule start start.next "$gv_feature"; gv_next="$gv_val"
  gv_rule start start.status "$gv_feature"; gv_status="$gv_val"

  if [ "$gv_s_reopen" = 1 ] && [ -f "$gv_state" ]; then
    python3 - "$gv_state" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(0)
reopen_count = int(d.get("reopenCount") or 0) + 1
d["reopenCount"] = reopen_count
if "approvedPhases" in d and isinstance(d["approvedPhases"], list):
    if "verify" in d["approvedPhases"]:
        idx = d["approvedPhases"].index("verify")
        d["approvedPhases"] = d["approvedPhases"][:idx]
    d["lastApprovedPhase"] = d["approvedPhases"][-1] if d["approvedPhases"] else ""
d["verifyPassed"] = False
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi

  gc_state_set "$gv_state" "$gv_feature" "$gv_req_art" "activePhase=$gv_phase" \
    "activeStatus=$gv_status" "blockedReason=" "nextStep=$gv_next" || exit 1

  GV_ST="$gv_state" GV_BASE="$gv_base" python3 - <<'PY'
import json, os
p = os.environ["GV_ST"]
base = os.environ["GV_BASE"]
d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
if base and not d.get("baseCommit"):
    d["baseCommit"] = base
d["verifyGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY

  mkdir -p "docs/agents-v0/verify/${gv_feature}"

  # Seed quality-gate.md from approved AC-1..AC-n when absent
  if [ ! -f "$gv_artifact" ]; then
    GV_REQ="$gv_req_art" GV_QG="$gv_artifact" GV_SLUG="$gv_feature" GV_SHA="${gv_base:-HEAD}" python3 - <<'PYQG'
import os, re
req_text = open(os.environ["GV_REQ"], encoding="utf-8").read()
clean_req = re.sub(r"<!--.*?-->", "", req_text, flags=re.S)
acs = sorted(set(int(n) for n in re.findall(r"^###\s+AC-(\d+)\b", clean_req, re.M)))
if not acs:
    acs = [1]
lines = [
    f"commit: {os.environ['GV_SHA']}",
    "agent: test-engineer",
    "",
    f"# Quality Gate: {os.environ['GV_SLUG']}",
    "",
    "## Summary",
    "- Build status: PENDING",
    "- Changed-line coverage: TBD%",
    "- Backend line coverage: TBD%",
    "- Frontend line coverage: N/A",
    "- Unsuppressed HIGH/CRITICAL CVEs: TBD",
    "",
    "## AC Traceability",
    "| AC | Test | Status | Evidence |",
    "| --- | --- | --- | --- |",
]
for n in acs:
    lines.append(f"| AC-{n} | TBD | PENDING | TBD |")
lines += [
    "",
    "## Findings",
    "| ID | Label | Finding | Evidence | Status |",
    "| --- | --- | --- | --- | --- |",
]
with open(os.environ["GV_QG"], "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PYQG
  fi

  gv_tier="$(gc_state_get "$gv_state" tier 2>/dev/null || echo standard)"
  if [ "$gv_tier" != "trivial" ]; then
    if [ ! -f "$gv_vapt" ]; then
      cat > "$gv_vapt" <<EOF
commit: ${gv_base:-HEAD}
agent: security-reviewer

# VAPT Checklist: ${gv_feature}

| Finding | Control | Status | Evidence | Retest |
| --- | --- | --- | --- | --- |
| F4 | Access control enforced server-side | PENDING | TBD | TBD |
| F8 | Same-role peer {id} access -> 403/404 | PENDING | TBD | TBD |
| F9 | JWT alg/iss/aud/exp + fail-closed blacklist | PENDING | TBD | TBD |
| F10 | Audit events recorded without raw token | PENDING | TBD | TBD |

## Findings
| ID | Label | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
EOF
    fi
    if [ ! -f "$gv_review" ]; then
      cat > "$gv_review" <<EOF
commit: ${gv_base:-HEAD}
agent: code-reviewer

# Code Review: ${gv_feature}

| ID | Label | Finding | Evidence | Rule Clause | Status |
| --- | --- | --- | --- | --- | --- |
EOF
    fi
  fi

  gc_ok start "verify is in_progress for $gv_feature ($gv_artifact)"
  printf 'Next: %s\n' "$gv_next"
}

gv_block() {
  gv_b_slug="${1:-}"
  shift || true
  gv_b_reason="${*:-}"
  gv_load block "$gv_b_slug"
  [ -n "$(printf '%s' "$gv_b_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason"
  gv_b_clean="$gv_b_reason"
  gv_rule block block.next "$gv_feature"; gv_next="$gv_val"
  gv_rule block block.status "$gv_feature"; gv_status="$gv_val"

  [ -f "$gv_state" ] || gc_refuse block "verify for '$gv_feature' has not been started ($gv_state missing)"
  [ "$(gc_state_get "$gv_state" activePhase)" = "$gv_phase" ] \
    || gc_refuse block "activePhase for '$gv_feature' is '$(gc_state_get "$gv_state" activePhase)', not '$gv_phase'"

  # Deduplicate helper-brief.md by SHA-256
  gv_hb=""
  if [ -f "docs/agents-v0/verify/${gv_feature}/helper-brief.md" ]; then
    gv_hb="docs/agents-v0/verify/${gv_feature}/helper-brief.md"
  elif [ -f "docs/agents-v0/requirements/${gv_feature}.helper-brief.md" ]; then
    gv_hb="docs/agents-v0/requirements/${gv_feature}.helper-brief.md"
  fi
  if [ -n "$gv_hb" ]; then
    gv_dup="$(GV_ST="$gv_state" GV_HB="$gv_hb" python3 - <<'PY'
import hashlib, json, os, re
st_p = os.environ["GV_ST"]
hb_p = os.environ["GV_HB"]
d = json.load(open(st_p, encoding="utf-8")) if os.path.isfile(st_p) else {}
raw = open(hb_p, encoding="utf-8", errors="replace").read()
norm = re.sub(r"\s+", " ", raw.strip().lower())
h = hashlib.sha256(norm.encode("utf-8")).hexdigest()
hashes = d.get("helperBriefHashes") if isinstance(d.get("helperBriefHashes"), dict) else {}
prev_h = hashes.get("verify") or d.get("lastHelperBriefHash", "")
if prev_h and prev_h == h:
    print("DUP")
else:
    hashes["verify"] = h
    d["helperBriefHashes"] = hashes
    d["lastHelperBriefHash"] = h
    with open(st_p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
    print("OK")
PY
)"
    if [ "$gv_dup" = "DUP" ]; then
      gc_refuse block "identical brief ($gv_hb) was already recorded; escalate to Sensei instead of repeating the same ask"
    fi
  fi

  gc_state_set "$gv_state" "$gv_feature" "$gv_req_art" "activePhase=$gv_phase" \
    "activeStatus=$gv_status" "blockedReason=$gv_b_clean" "nextStep=$gv_next" || exit 1
  gc_ok block "verify is blocked for $gv_feature ($gv_b_clean)"
  printf 'Next: %s\n' "$gv_next"
}

# Design: DV3 (/v0-verify ready quality-gate, VAPT F4/F8/F9/F10, code-review, T6 traceability, and automatic Critical bounce).
gv_ready() {
  gv_r_slug="${1:-}"
  [ $# -le 1 ] || gv_usage
  gv_load ready "$gv_r_slug"
  gv_rule ready ready.requires "$gv_feature"; gv_requires="$gv_val"
  gv_check_prereqs ready "$gv_requires" 0

  [ -f "$gv_artifact" ] || gc_refuse ready "quality gate report '$gv_artifact' does not exist"
  [ -f "$gv_output" ] || gc_refuse ready "verify output '$gv_output' does not exist"

  gv_tier="$(gc_state_get "$gv_state" tier 2>/dev/null || echo standard)"
  if [ "$gv_tier" != "trivial" ]; then
    [ -f "$gv_vapt" ] || gc_refuse ready "VAPT checklist '$gv_vapt' does not exist"
    [ -f "$gv_review" ] || gc_refuse ready "code review report '$gv_review' does not exist"
  fi

  # 1. Verify check-tests-ran.sh (kitfix-20261031-tests-ran)
  if [ -f "$GC_HERE/check-tests-ran.sh" ]; then
    if ! gv_tr_ran="$(sh "$GC_HERE/check-tests-ran.sh" 2>&1)"; then
      gc_refuse ready "check-tests-ran.sh failed: $gv_tr_ran"
    fi
  fi

  # 2. Deterministic validation of verify-output.txt, quality-gate.md, vapt-checklist.md, code-review.md, ux-report.md, and Critical findings
  gv_val_err="$(GV_SLUG="$gv_feature" GV_REQ="$gv_req_art" GV_QG="$gv_artifact" GV_VAPT="$gv_vapt" GV_REV="$gv_review" GV_OUT="$gv_output" GV_TIER="$gv_tier" python3 - <<'PYVAL'
import datetime, os, re, sys

slug = os.environ["GV_SLUG"]
req_p = os.environ["GV_REQ"]
qg_p = os.environ["GV_QG"]
vapt_p = os.environ["GV_VAPT"]
rev_p = os.environ["GV_REV"]
out_p = os.environ["GV_OUT"]
tier = os.environ.get("GV_TIER", "standard")

out_raw = open(out_p, encoding="utf-8", errors="replace").read()
if not out_raw.strip():
    print(f"REFUSE:{out_p} is empty; record raw verify command output in {out_p}")
    sys.exit(0)

qg_raw = open(qg_p, encoding="utf-8", errors="replace").read()
clean_qg = re.sub(r"<!--.*?-->", "", qg_raw, flags=re.S)

if not re.search(r"(?m)^agent:\s*test-engineer\b", clean_qg):
    print(f"REFUSE:{qg_p} is missing 'agent: test-engineer' header")
    sys.exit(0)

if re.search(r"Build status:\s*PENDING\b", clean_qg, re.I) or re.search(r"\bTBD\b", clean_qg):
    print(f"REFUSE:{qg_p} still contains PENDING or TBD placeholders")
    sys.exit(0)

if not re.search(r"Build status:\s*(PASS|PASSED|GREEN|OK)\b", clean_qg, re.I):
    print(f"REFUSE:{qg_p} must report 'Build status: PASS'")
    sys.exit(0)

# Coverage thresholds (default >=80% changed lines, >=80% backend, >=70% frontend, or valid coverage_ratchet in project-profile.md)
backend_min = 80.0
frontend_min = 70.0
if os.path.isfile("docs/agents-v0/project-profile.md"):
    prof_txt = open("docs/agents-v0/project-profile.md", encoding="utf-8", errors="replace").read()
    m_rat = re.search(r"coverage_ratchet.*?([0-9]+(?:\.[0-9]+)?)%.*?(20[0-9]{2}-[0-9]{2}-[0-9]{2})", prof_txt, re.I | re.S)
    if m_rat:
        try:
            exp = datetime.date.fromisoformat(m_rat.group(2))
            if exp >= datetime.date.today():
                backend_min = float(m_rat.group(1))
        except ValueError:
            pass

m_chg = re.search(r"Changed-line coverage:\s*([0-9]+(?:\.[0-9]+)?)%", clean_qg, re.I)
if not m_chg:
    print(f"REFUSE:{qg_p} must report 'Changed-line coverage: <n>%'")
    sys.exit(0)
if float(m_chg.group(1)) < 80.0:
    print(f"REFUSE:{qg_p} Changed-line coverage is {m_chg.group(1)}% (minimum required: 80%)")
    sys.exit(0)

m_be = re.search(r"Backend line coverage:\s*(?:([0-9]+(?:\.[0-9]+)?)%|N/A)", clean_qg, re.I)
if m_be and m_be.group(1) is not None:
    if float(m_be.group(1)) < backend_min:
        print(f"REFUSE:{qg_p} Backend line coverage is {m_be.group(1)}% (minimum required: {backend_min:g}%)")
        sys.exit(0)

m_fe = re.search(r"Frontend line coverage:\s*(?:([0-9]+(?:\.[0-9]+)?)%|N/A)", clean_qg, re.I)
if m_fe and m_fe.group(1) is not None:
    if float(m_fe.group(1)) < frontend_min:
        print(f"REFUSE:{qg_p} Frontend line coverage is {m_fe.group(1)}% (minimum required: {frontend_min:g}%)")
        sys.exit(0)

m_cve = re.search(r"Unsuppressed HIGH/CRITICAL CVEs:\s*([0-9]+)", clean_qg, re.I)
if not m_cve:
    print(f"REFUSE:{qg_p} must report 'Unsuppressed HIGH/CRITICAL CVEs: 0'")
    sys.exit(0)
if int(m_cve.group(1)) > 0:
    print(f"REFUSE:{qg_p} reports {m_cve.group(1)} unsuppressed HIGH/CRITICAL CVE(s)")
    sys.exit(0)

# UX report check when ux-spec.md exists
ux_spec_p = f"docs/agents-v0/design/{slug}/ux-spec.md"
ux_rep_p = f"docs/agents-v0/verify/{slug}/ux-report.md"
if os.path.isfile(ux_spec_p):
    if not os.path.isfile(ux_rep_p):
        print(f"REFUSE:{ux_spec_p} exists, so {ux_rep_p} is required for UI accessibility (axe-core) and UX verification")
        sys.exit(0)

critical_findings = []

def scan_findings_table(text, source_name):
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4 or set(line.replace("|", "").strip()) <= set("-: "):
            continue
        low = [c.lower() for c in cells]
        if low[0] in ("id", "#", "finding"):
            continue
        # Check if any cell is 'critical' and status is not 'resolved'/'closed'
        has_crit = any(c == "critical" for c in low)
        is_resolved = any(c in ("resolved", "closed", "fixed") for c in low)
        if has_crit and not is_resolved:
            critical_findings.append(f"{source_name}: {line.strip()}")

scan_findings_table(clean_qg, qg_p)

if tier != "trivial":
    vapt_raw = open(vapt_p, encoding="utf-8", errors="replace").read()
    clean_vapt = re.sub(r"<!--.*?-->", "", vapt_raw, flags=re.S)
    if not re.search(r"(?m)^commit:\s*\S+", clean_vapt) or not re.search(r"(?m)^agent:\s*security-reviewer\b", clean_vapt):
        print(f"REFUSE:{vapt_p} must start with 'commit:' and 'agent: security-reviewer' headers")
        sys.exit(0)
    if re.search(r"\b(PENDING|TBD)\b", clean_vapt):
        print(f"REFUSE:{vapt_p} still contains PENDING or TBD placeholders")
        sys.exit(0)
    for ctrl in ("F4", "F8", "F9", "F10"):
        ctrl_lines = [l for l in clean_vapt.splitlines() if re.search(rf"\b{ctrl}\b", l) and l.strip().startswith("|")]
        if not ctrl_lines:
            print(f"REFUSE:{vapt_p} is missing always-on VAPT control row '{ctrl}'")
            sys.exit(0)
        row_txt = ctrl_lines[0]
        if re.search(r"\bFAIL(ED)?\b", row_txt, re.I):
            critical_findings.append(f"{vapt_p} ({ctrl} FAIL): {row_txt.strip()}")
        elif not re.search(r"\b(PASS(ED)?|N/A)\b", row_txt, re.I):
            print(f"REFUSE:{vapt_p} row for '{ctrl}' must record PASS, FAIL, or N/A with reason")
            sys.exit(0)
        elif re.search(r"\bPASS(ED)?\b", row_txt, re.I) and not re.search(r"[A-Za-z0-9_./-]+:[0-9]+", row_txt):
            print(f"REFUSE:{vapt_p} PASS row for '{ctrl}' must cite 'file:line' evidence")
            sys.exit(0)
    scan_findings_table(clean_vapt, vapt_p)

    rev_raw = open(rev_p, encoding="utf-8", errors="replace").read()
    clean_rev = re.sub(r"<!--.*?-->", "", rev_raw, flags=re.S)
    if not re.search(r"(?m)^commit:\s*\S+", clean_rev) or not re.search(r"(?m)^agent:\s*code-reviewer\b", clean_rev):
        print(f"REFUSE:{rev_p} must start with 'commit:' and 'agent: code-reviewer' headers")
        sys.exit(0)
    if re.search(r"\b(PENDING|TBD)\b", clean_rev):
        print(f"REFUSE:{rev_p} still contains PENDING or TBD placeholders")
        sys.exit(0)
    scan_findings_table(clean_rev, rev_p)

if critical_findings:
    print("BOUNCE:" + " ; ".join(critical_findings))
    sys.exit(0)

print("OK")
PYVAL
)"

  case "$gv_val_err" in
    REFUSE:*)
      gc_refuse ready "${gv_val_err#REFUSE:}"
      ;;
    BOUNCE:*)
      gv_crit_summary="${gv_val_err#BOUNCE:}"
      # Write phase-result with Critical findings and trigger automatic reopen of build (or maintain)
      GV_PR="$gv_result" GV_SLUG="$gv_feature" GV_CRIT="$gv_crit_summary" python3 - <<'PYBNC'
import os, re
p = os.environ["GV_PR"]
slug = os.environ["GV_SLUG"]
crit = os.environ["GV_CRIT"]
lessons_block = "## Lessons\n\n### verify\n- none\n"
if os.path.isfile(p):
    txt = open(p, encoding="utf-8").read()
    m = re.search(r"(^##\s+Lessons\b.*)", txt, re.M | re.S)
    if m:
        lessons_block = m.group(1).strip() + "\n"
        if "### verify" not in lessons_block:
            lessons_block += "\n### verify\n- none\n"
content = (
    f"# Phase Result: {slug}\n\n"
    f"phase: verify\n"
    f"status: changes_requested\n"
    f"guard_managed: true\n\n"
    f"## Critical Findings\n"
    f"- {crit}\n\n"
    f"{lessons_block}"
)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(content)
PYBNC
      gv_reopen_target="build"
      [ "$gv_is_maintain" = 1 ] && gv_reopen_target="maintain"
      if [ "$gv_is_maintain" = 1 ] && [ "$gv_tier" = "emergency" ]; then
        case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
          *" release "*)
            sh "$GC_HERE/sync-feature-state.sh" --verify-passed false --active-phase verify --status blocked --reason "Critical finding in owed emergency verify; start a new maintenance id" "$gv_req_art" >/dev/null || true
            gc_refuse ready "Open Critical finding(s) in owed emergency verify ($gv_crit_summary); state set to blocked — start /v0-maintain with a new <id>"
            ;;
        esac
      fi
      if ! gv_ro_out="$(sh "$GC_HERE/sync-feature-state.sh" --verify-passed false --reopen "$gv_reopen_target" "$gv_req_art" 2>&1)"; then
        gc_refuse ready "Open Critical finding(s) ($gv_crit_summary) triggered reopen of $gv_reopen_target, which exceeded the reopen bounce cap: $gv_ro_out"
      fi
      gc_refuse ready "Open Critical finding(s) detected ($gv_crit_summary); automatically reopened '$gv_reopen_target' (verifyPassed=false). Route back to /v0-${gv_reopen_target} $gv_feature"
      ;;
  esac

  # 3. Traceability check T6 (every AC-<n> has a passing row in quality-gate.md)
  if [ "$gv_is_maintain" = 0 ] && [ -f "$GC_HERE/check-traceability.sh" ]; then
    gv_tr_out="$(AGENTS_V0_TRACE_MODE=fail sh "$GC_HERE/check-traceability.sh" verify "$gv_req_art" --no-write 2>&1)" || {
      gc_refuse ready "verify traceability check (T6) failed: $gv_tr_out"
    }
  fi

  # 4. Secret scan on verify reports and verify-output.txt
  if [ -f "$GC_HERE/secret_scan.py" ]; then
    gv_sec_out="$(python3 -B - "$GC_HERE" "$gv_artifact" "$gv_output" "$gv_vapt" "$gv_review" <<'PYSEC'
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
      gc_refuse ready "secret scan failed on verify evidence: $gv_sec_out"
    }
  fi

  # 5. Write/update <feature>.phase-result.md for verify
  GV_PR="$gv_result" GV_SLUG="$gv_feature" python3 - <<'PYPR'
import os, re
p = os.environ["GV_PR"]
slug = os.environ["GV_SLUG"]
lessons_block = "## Lessons\n\n### verify\n- none\n"
if os.path.isfile(p):
    txt = open(p, encoding="utf-8").read()
    m = re.search(r"(^##\s+Lessons\b.*)", txt, re.M | re.S)
    if m:
        lessons_block = m.group(1).strip() + "\n"
        if "### verify" not in lessons_block:
            lessons_block += "\n### verify\n- none\n"
content = (
    f"# Phase Result: {slug}\n\n"
    f"phase: verify\n"
    f"status: awaiting_approval\n"
    f"guard_managed: true\n\n"
    f"{lessons_block}"
)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(content)
PYPR

  gv_rule ready ready.next "$gv_feature"; gv_next="$gv_val"
  gc_state_set "$gv_state" "$gv_feature" "$gv_req_art" "activePhase=$gv_phase" \
    "activeStatus=awaiting_approval" "blockedReason=" "nextStep=$gv_next" || exit 1
  python3 - "$gv_state" <<'PYVP'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["verifyPassed"] = True
d["verifyGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PYVP

  gc_ok ready "verify for $gv_feature passed all checks (verifyPassed=true) and is awaiting Sensei's approval"
  printf 'Next: %s\n' "$gv_next"
}

cmd="${1:-}"
[ -n "$cmd" ] || gv_usage
shift || true

case "$cmd" in
  check) gv_check "$@" ;;
  start) gv_start "$@" ;;
  block) gv_block "$@" ;;
  ready) gv_ready "$@" ;;
  *) gv_usage ;;
esac
