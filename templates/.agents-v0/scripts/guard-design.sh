#!/bin/sh
# guard-design.sh — single entry point and security boundary for /v0-design.
# Usage:
#   sh .agents-v0/scripts/guard-design.sh check <feature> [--reopen]
#   sh .agents-v0/scripts/guard-design.sh start <feature> [--reopen]
#   sh .agents-v0/scripts/guard-design.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-design.sh ready <feature>
#   sh .agents-v0/scripts/guard-design.sh commit <feature>
#   sh .agents-v0/scripts/guard-design.sh steps
#
# Design: DD1 (/v0-design guard and parameterized per-story design gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-design.sh"

gd_usage() {
  printf 'usage: %s check <feature> [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gd_validate_slug() {
  gd_v_step="$1"
  gd_v_slug="${2:-}"
  [ -n "$gd_v_slug" ] || gc_refuse "$gd_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gd_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gd_v_step" "feature slug '$gd_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gd_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gd_v_step" "feature slug '$gd_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gd_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gd_v_step" "story '$gd_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-design"
      ;;
  esac
}

gd_rule() {
  gd_step="$1"
  gd_key="$2"
  gd_slug="${3:-}"
  gd_rules="${GC_HERE}/../gate-rules"
  [ -f "$gd_rules" ] || gc_refuse "$gd_step" "missing gate-rules file ($gd_rules)"
  gd_val="$(awk -v p="design" -v k="$gd_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gd_rules")"
  [ -n "$gd_val" ] || gc_refuse "$gd_step" "gate-rules missing key '$gd_key' for phase 'design'"
  if [ -n "$gd_slug" ]; then
    gd_val="$(printf '%s' "$gd_val" | sed "s/<feature>/$gd_slug/g")"
  fi
}

gd_load() {
  gd_step="$1"
  gd_slug="$2"
  gd_validate_slug "$gd_step" "$gd_slug"
  gc_to_root "$gd_step"
  gd_rule "$gd_step" phase "$gd_slug"; gd_phase="$gd_val"
  gd_rule "$gd_step" feature "$gd_slug"; gd_feature="$gd_val"
  gd_rule "$gd_step" state "$gd_slug"; gd_state="$gd_val"
  gd_rule "$gd_step" artifact "$gd_slug"; gd_artifact="$gd_val"
  gd_rule "$gd_step" result "$gd_slug"; gd_result="$gd_val"
  gd_req_art="docs/agents-v0/requirements/${gd_feature}.md"
}

gd_check_prereqs() {
  gd_step="$1"
  gd_reqs="$2"
  gd_reopen="${3:-0}"
  gd_rule "$gd_step" approved.next "$gd_feature"; gd_approved_next="$gd_val"

  for gd_req in $gd_reqs; do
    case "$gd_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gd_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      feature-branch)
        gd_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gd_skip_bg=1
        # <<< kit-test-override
        if [ "$gd_skip_bg" != 1 ]; then
          gd_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [ "$gd_cur" != "feature/$gd_feature" ]; then
            gd_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${gd_feature}" '
              /^worktree / { path = substr($0, 10) }
              $0 == want { print path; exit }
            ')"
            if [ -n "$gd_wt" ]; then
              gc_refuse "$gd_step" "design for '$gd_feature' must run in worktree '$gd_wt' on branch 'feature/$gd_feature' (current branch: '${gd_cur:-detached}'). Open that folder and run /v0-design $gd_feature there"
            else
              gc_refuse "$gd_step" "no 'feature/$gd_feature' branch or worktree exists (current branch: '${gd_cur:-detached}'); complete /v0-intake $gd_feature (approve + guard-intake.sh commit $gd_feature) first"
            fi
          fi
        fi
        ;;
      not-released)
        if [ -f "$gd_state" ]; then
          case " $(gc_state_get "$gd_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              gc_refuse "$gd_step" "story '$gd_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              ;;
          esac
        fi
        ;;
      intake-approved)
        [ -f "$gd_req_art" ] \
          || gc_refuse "$gd_step" "requirements artifact '$gd_req_art' is missing; complete /v0-intake $gd_feature first"
        [ -f "$gd_state" ] \
          || gc_refuse "$gd_step" "requirements state '$gd_state' is missing; complete /v0-intake $gd_feature first"
        case " $(gc_state_get "$gd_state" approvedPhases | tr -d '[]",') " in
          *" intake "*) ;;
          *) gc_refuse "$gd_step" "intake is not in approvedPhases in '$gd_state'; complete /v0-intake $gd_feature first" ;;
        esac
        # Verify external intake approval when story is guard-managed
        gd_base="$(gc_state_get "$gd_state" baseCommit 2>/dev/null || true)"
        if [ -n "$gd_base" ] || { [ -f "$gd_result" ] && grep -Fq "guard_managed: true" "$gd_result"; }; then
          if ! gd_int_ok="$(gc_approval_ok intake "$gd_feature")"; then
            gc_refuse "$gd_step" "external intake approval record missing or mismatched ($gd_int_ok); complete /v0-intake $gd_feature first"
          fi
        fi
        # Verify intake gate is committed (unless skipped in kit test override)
        gd_skip_cc=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gd_skip_cc=1
        # <<< kit-test-override
        if [ "$gd_skip_cc" != 1 ] && [ -f "$GC_HERE/check-gate-commit.sh" ] && [ "$gd_reopen" != 1 ]; then
          gd_prev_act="$(gc_state_get "$gd_state" activePhase 2>/dev/null || true)"
          if [ -z "$gd_prev_act" ]; then
            if ! gd_cc_out="$(sh "$GC_HERE/check-gate-commit.sh" "$gd_req_art" 2>&1)"; then
              gc_refuse "$gd_step" "intake gate is not committed on feature/$gd_feature: $gd_cc_out"
            fi
          fi
        fi
        ;;
      not-approved)
        if [ "$gd_reopen" != 1 ] && [ -f "$gd_state" ]; then
          case " $(gc_state_get "$gd_state" approvedPhases | tr -d '[]",') " in
            *" $gd_phase "*)
              gc_refuse "$gd_step" "design is already approved for '$gd_feature'; suggest $gd_approved_next (or pass --reopen to amend design)"
              ;;
          esac
        fi
        if [ "$gd_reopen" = 1 ] && [ -f "$gd_state" ]; then
          gd_rc="$(gc_state_get "$gd_state" reopenCount 2>/dev/null || echo 0)"
          case "$gd_rc" in ''|*[!0-9]*) gd_rc=0 ;; esac
          if [ "$gd_rc" -ge 3 ]; then
            gc_refuse "$gd_step" "reopen bounce cap exceeded for '$gd_feature' (reopenCount=$gd_rc >= 3); escalate to Sensei before reopening again"
          fi
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gd_state" ]; then
          [ "$(gc_state_get "$gd_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gd_step" "design for '$gd_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve design $gd_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gd_state" ] || gc_refuse "$gd_step" "design for '$gd_feature' has not been started; run $G start $gd_feature first"
        [ "$(gc_state_get "$gd_state" activePhase)" = "$gd_phase" ] \
          || gc_refuse "$gd_step" "activePhase for '$gd_feature' is '$(gc_state_get "$gd_state" activePhase)', not '$gd_phase'; run $G start $gd_feature first"
        [ "$(gc_state_get "$gd_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gd_step" "design for '$gd_feature' is not in_progress (status: $(gc_state_get "$gd_state" activeStatus)); run $G start $gd_feature first"
        ;;
      *) gc_refuse "$gd_step" "gate-rules names an unknown prerequisite '$gd_req'; reinstall the kit" ;;
    esac
  done
}

gd_check() {
  gd_c_slug=""
  gd_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gd_c_reopen=1
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

  gd_load check "$gd_c_slug"
  gd_rule check check.requires "$gd_feature"; gd_requires="$gd_val"
  gd_check_prereqs check "$gd_requires" "$gd_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-design $gd_feature"
  if [ "$gd_c_reopen" = 1 ]; then
    printf 'Next: Start reopened design with: %s start %s --reopen\n' "$G" "$gd_feature"
  else
    printf 'Next: Start design with: %s start %s\n' "$G" "$gd_feature"
  fi
}

gd_start() {
  gd_s_slug=""
  gd_s_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gd_s_reopen=1
        shift
        ;;
      -*)
        gd_usage
        ;;
      *)
        [ -z "$gd_s_slug" ] || gd_usage
        gd_s_slug="$1"
        shift
        ;;
    esac
  done

  gd_load start "$gd_s_slug"
  gd_rule start start.requires "$gd_feature"; gd_requires="$gd_val"
  gd_check_prereqs start "$gd_requires" "$gd_s_reopen"
  if [ "$gd_s_reopen" != 1 ]; then
    gd_check_prereqs start "not-approved" 0
  else
    gd_check_prereqs start "not-approved" 1
  fi

  # Refuse unrelated dirty paths on feature/<feature> (ignoring .lock files and design-scoped paths)
  gd_dirty="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | grep -v '\.lock$' | grep -Ev "^(docs/agents-v0/design/${gd_feature}/|docs/agents-v0/adr/|docs/agents-v0/diagrams/|docs/agents-v0/design/system/arc-record\\.md$|docs/agents-v0/requirements/${gd_feature}\\.)" || true)"
  if [ -n "$gd_dirty" ]; then
    gc_refuse start "working tree has uncommitted changes outside design paths ($gd_dirty); commit or stash them first (note: never modify repo-wide openapi/ catalog during Design)"
  fi

  mkdir -p "docs/agents-v0/design/${gd_feature}"
  if [ ! -f "$gd_artifact" ]; then
    if [ -f "docs/agents-v0/design/_design.template.md" ]; then
      sed "s/<feature>/$gd_feature/g" "docs/agents-v0/design/_design.template.md" > "$gd_artifact"
    else
      cat > "$gd_artifact" <<EOF
# Design: $gd_feature

ADR: docs/agents-v0/adr/01-${gd_feature}.md

## Traceability

| Requirement | Satisfied by | Notes |
|-------------|--------------|-------|
| <AC-1> | <operationId / component> | |

## Data model

<describe entities, keys, indexes, retention, PII, and migration shape>

## Authorization

| operationId | Roles or scopes | Resource rule | Notes |
|-------------|-----------------|---------------|-------|
| <operationId> | <role> | <BOLA ownership rule> | |

## Events

N/A: no event contract

## Failure modes

<describe dependency failures, slow/partial failure behavior, and name every Kind: negative and Kind: edge AC>

## Observability

<metrics, logs, traces, alerts>

## Rollout

<feature flag, deploy order, backward compatibility, rollback>
EOF
    fi
  fi

  gd_rule start start.next "$gd_feature"; gd_next="$gd_val"
  gd_rule start start.status "$gd_feature"; gd_status="$gd_val"

  if [ "$gd_s_reopen" = 1 ] && [ -f "$gd_state" ]; then
    python3 - "$gd_state" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(0)
reopen_count = int(d.get("reopenCount") or 0) + 1
d["reopenCount"] = reopen_count
if "approvedPhases" in d and isinstance(d["approvedPhases"], list):
    if "design" in d["approvedPhases"]:
        idx = d["approvedPhases"].index("design")
        d["approvedPhases"] = d["approvedPhases"][:idx]
    d["lastApprovedPhase"] = d["approvedPhases"][-1] if d["approvedPhases"] else ""
d["verifyPassed"] = False
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi

  gc_state_set "$gd_state" "$gd_feature" "$gd_req_art" "activePhase=$gd_phase" \
    "activeStatus=$gd_status" "blockedReason=" "nextStep=$gd_next" || exit 1

  # Mark designGuardManaged=true so sync-feature-state.sh and check-gate-commit.sh know this story's design uses guard-design.sh
  python3 - "$gd_state" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["designGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY

  gc_ok start "design in_progress on $gd_artifact"
  printf 'Next: %s\n' "$gd_next"
}

gd_block() {
  [ $# -ge 2 ] || gc_die "usage: $G block <feature> \"<plain reason>\""
  gd_b_slug="$1"
  shift
  gd_reason="$*"
  [ -n "$(printf '%s' "$gd_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason"

  gd_load block "$gd_b_slug"
  gd_rule block block.status "$gd_feature"; gd_status="$gd_val"
  gd_rule block block.next "$gd_feature"; gd_next="$gd_val"

  [ -f "$gd_state" ] || gc_refuse block "design for '$gd_feature' has not been started ($gd_state missing)"
  [ "$(gc_state_get "$gd_state" activePhase)" = "$gd_phase" ] \
    || gc_refuse block "activePhase for '$gd_feature' is '$(gc_state_get "$gd_state" activePhase)', not '$gd_phase'"

  # Helper-brief deduplication (FD6): if docs/agents-v0/design/<feature>/helper-brief.md exists, refuse identical repeat asks
  gd_brief="docs/agents-v0/design/${gd_feature}/helper-brief.md"
  if [ -f "$gd_brief" ]; then
    if ! python3 - "$gd_state" "$gd_brief" <<'PY'
import hashlib, json, re, sys
state_p, brief_p = sys.argv[1:3]
raw = open(brief_p, encoding="utf-8").read()
norm = re.sub(r"\s+", " ", raw.strip().lower())
digest = hashlib.sha256(norm.encode("utf-8")).hexdigest()
data = json.load(open(state_p, encoding="utf-8"))
hashes = data.get("helperBriefHashes") if isinstance(data.get("helperBriefHashes"), dict) else {}
prev = hashes.get("design") or data.get("lastDesignHelperBriefHash") or ""
if prev and prev == digest:
    sys.exit(1)
hashes["design"] = digest
data["helperBriefHashes"] = hashes
data["lastDesignHelperBriefHash"] = digest
with open(state_p, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
    then
      gc_refuse block "duplicate helper brief in $gd_brief; do not re-ask the same helper question"
    fi
  fi

  gc_state_set "$gd_state" "$gd_feature" "$gd_req_art" "activePhase=$gd_phase" \
    "activeStatus=$gd_status" "blockedReason=$gd_reason" "nextStep=$gd_next" || exit 1

  gc_ok block "design for $gd_feature blocked ($gd_reason)"
  printf 'Next: %s\n' "$gd_next"
}

cmd="${1:-}"
case "$cmd" in
  check) shift; gd_check "$@" ;;
  start) shift; gd_start "$@" ;;
  block) shift; gd_block "$@" ;;
  *) gd_usage ;;
esac

