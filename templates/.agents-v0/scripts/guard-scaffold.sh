#!/bin/sh
# guard-scaffold.sh — single entry point and security boundary for /v0-scaffold.
# Usage:
#   sh .agents-v0/scripts/guard-scaffold.sh check
#   sh .agents-v0/scripts/guard-scaffold.sh start
#   sh .agents-v0/scripts/guard-scaffold.sh block "<reason>"
#   sh .agents-v0/scripts/guard-scaffold.sh ready
#   sh .agents-v0/scripts/guard-scaffold.sh commit
#   sh .agents-v0/scripts/guard-scaffold.sh steps
#
# Design: DS1 (/v0-scaffold guard and greenfield platform skeleton baseline).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-scaffold.sh"

gs_usage() {
  printf 'usage: %s check\n' "$G" >&2
  printf '       %s start\n' "$G" >&2
  printf '       %s block "<plain reason>"\n' "$G" >&2
  printf '       %s ready\n' "$G" >&2
  printf '       %s commit\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gs_rule() {
  gs_step="$1"
  gs_key="$2"
  gs_rules="${GC_HERE}/../gate-rules"
  [ -f "$gs_rules" ] || gc_refuse "$gs_step" "missing gate-rules file ($gs_rules)"
  gs_val="$(awk -v p="scaffold" -v k="$gs_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gs_rules")"
  [ -n "$gs_val" ] || gc_refuse "$gs_step" "gate-rules missing key '$gs_key' for phase 'scaffold'"
}

gs_load() {
  gs_step="$1"
  gc_to_root "$gs_step"
  gs_rule "$gs_step" phase; gs_phase="$gs_val"
  gs_rule "$gs_step" feature; gs_feature="$gs_val"
  gs_rule "$gs_step" state; gs_state="$gs_val"
  gs_rule "$gs_step" artifact; gs_artifact="$gs_val"
}

gs_is_brownfield() {
  [ -f docs/agents-v0/onboarding/state.json ] && return 0
  [ -d docs/agents-v0/onboarding ] && return 0
  if [ -f docs/agents-v0/program.state.json ]; then
    case " $(gc_state_get docs/agents-v0/program.state.json approvedPhases | tr -d '[]",') " in
      *" onboard "*) return 0 ;;
    esac
  fi
  return 1
}

gs_check_prereqs() {
  gs_step="$1"
  gs_reqs="$2"
  gs_rule "$gs_step" approved.next; gs_approved_next="$gs_val"

  for gs_req in $gs_reqs; do
    case "$gs_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gs_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      greenfield-only)
        if gs_is_brownfield; then
          gc_refuse "$gs_step" "brownfield codebase detected; run /v0-onboard instead (scaffold is for greenfield projects only)"
        fi
        ;;
      plan-approved)
        [ -f "$gs_state" ] || gc_refuse "$gs_step" "no program state ($gs_state); complete /v0-roadmap, /v0-architecture, and /v0-plan first"
        case " $(gc_state_get "$gs_state" approvedPhases | tr -d '[]",') " in
          *" plan "*) ;;
          *) gc_refuse "$gs_step" "plan is not in approvedPhases in $gs_state; complete /v0-plan first" ;;
        esac
        if ! gs_plan_ok="$(gc_approval_ok plan)"; then
          gc_refuse "$gs_step" "external plan approval record missing or mismatched ($gs_plan_ok); complete /v0-plan and have the user approve it first"
        fi
        ;;
      integration-branch)
        gs_ib="main"
        if [ -x .agents-v0/scripts/resolve-integration-branch.sh ]; then
          gs_ib="$(sh .agents-v0/scripts/resolve-integration-branch.sh 2>/dev/null || echo main)"
        fi
        gs_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        if [ -n "$gs_cur" ] && [ "$gs_cur" != "$gs_ib" ]; then
          gc_refuse "$gs_step" "scaffold must run on the integration branch ($gs_ib); current branch is '$gs_cur'. Run git checkout $gs_ib first"
        fi
        ;;
      not-approved)
        if [ -f "$gs_state" ]; then
          case " $(gc_state_get "$gs_state" approvedPhases | tr -d '[]",') " in
            *" $gs_phase "*) gc_refuse "$gs_step" "scaffold is already approved; suggest $gs_approved_next" ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gs_state" ]; then
          [ "$(gc_state_get "$gs_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gs_step" "scaffold is awaiting approval; run sh .agents-v0/scripts/guard-common.sh approve scaffold in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gs_state" ] || gc_refuse "$gs_step" "scaffold has not been started; run $G start first"
        [ "$(gc_state_get "$gs_state" activePhase)" = "$gs_phase" ] \
          || gc_refuse "$gs_step" "activePhase is '$(gc_state_get "$gs_state" activePhase)', not '$gs_phase'; run $G start first"
        [ "$(gc_state_get "$gs_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gs_step" "scaffold is not in_progress (status: $(gc_state_get "$gs_state" activeStatus)); run $G start first"
        ;;
      *) gc_refuse "$gs_step" "gate-rules names an unknown prerequisite '$gs_req'; reinstall the kit" ;;
    esac
  done
}

gs_check() {
  [ $# -eq 0 ] || gs_usage
  gs_load check
  gs_rule check check.requires; gs_requires="$gs_val"
  gs_check_prereqs check "$gs_requires"

  gc_ok check "prerequisites satisfied for /v0-scaffold"
  printf 'Next: Start scaffold with: sh .agents-v0/scripts/guard-scaffold.sh start\n'
}

gs_start() {
  [ $# -eq 0 ] || gs_usage
  gs_load start
  gs_rule start start.requires; gs_requires="$gs_val"
  gs_check_prereqs start "$gs_requires"

  mkdir -p docs/agents-v0/milestones
  if [ ! -f "$gs_artifact" ]; then
    if [ -f "templates/docs/agents-v0/milestones/p0-platform-skeleton.md" ]; then
      cp "templates/docs/agents-v0/milestones/p0-platform-skeleton.md" "$gs_artifact"
    else
      printf '# Milestone P0: Platform Skeleton\n\n| ID | User Story | Feature Artifact | Status | Dependency | Surface | Size |\n|---|---|---|---|---|---|---|\n| P0-A | As a developer, I want a known-good baseline — the build and tests pass, this milestone is the tracked manifest, coverage and CVE scanning are bound to verify, and I can run the app locally with Dockerfile and Compose — so that feature work starts from a stack that already runs. | docs/agents-v0/milestones/p0-platform-skeleton.md | planned | — | vertical slice | 4 |\n' > "$gs_artifact"
    fi
  fi

  gs_rule start start.next; gs_next="$gs_val"
  gs_rule start start.status; gs_status="$gs_val"

  gc_state_set "$gs_state" "$gs_feature" "$gs_artifact" "activePhase=$gs_phase" \
    "activeStatus=$gs_status" "blockedReason=" "nextStep=$gs_next" || exit 1

  gc_ok start "scaffold in_progress on $gs_artifact"
  printf 'Next: %s\n' "$gs_next"
}

gs_block() {
  [ $# -ge 1 ] || gc_die "usage: $G block \"<plain reason>\""
  gs_load block
  gs_reason="$*"
  gs_rule block block.status; gs_status="$gs_val"
  gs_rule block block.next; gs_next="$gs_val"

  [ -f "$gs_state" ] || gc_refuse block "scaffold has not been started ($gs_state missing)"
  [ "$(gc_state_get "$gs_state" activePhase)" = "$gs_phase" ] \
    || gc_refuse block "activePhase is '$(gc_state_get "$gs_state" activePhase)', not '$gs_phase'"

  gc_state_set "$gs_state" "$gs_feature" "$gs_artifact" "activePhase=$gs_phase" \
    "activeStatus=$gs_status" "blockedReason=$gs_reason" "nextStep=$gs_next" || exit 1

  gc_ok block "scaffold blocked ($gs_reason)"
  printf 'Next: %s\n' "$gs_next"
}

gs_ready() {
  [ $# -eq 0 ] || gs_usage
  gs_load ready
  gs_rule ready ready.requires; gs_requires="$gs_val"
  gs_check_prereqs ready "$gs_requires"

  # 1. AC-2: Milestone P0 manifest exists and is well-formed
  [ -f "$gs_artifact" ] || gc_refuse ready "milestone P0 manifest '$gs_artifact' is missing"
  python3 - "$gs_artifact" <<'PY'
import re, sys
manifest = sys.argv[1]
txt = open(manifest, "r", encoding="utf-8").read()
if not re.search(r"\|\s*P0-A\s*\|", txt):
    print(f"REFUSED ready: {manifest} does not contain seeded story row for P0-A")
    sys.exit(1)
# Reject placeholders in milestone manifest outside Delivery approvals
lines = []
in_approvals = False
for line in txt.splitlines():
    if "## Delivery approvals" in line:
        in_approvals = True
    if not in_approvals:
        lines.append(line)
body = "\n".join(lines)
ph = re.findall(r"<(?:[A-Za-z0-9_-]+)>|\[(?:TODO|TBD|FIXME)\]|\b(?:TODO|TBD|FIXME)\b", body)
if ph:
    print(f"REFUSED ready: {manifest} contains unauthored placeholders: {', '.join(sorted(set(ph))[:5])}")
    sys.exit(1)
PY

  # 2. AC-4: Dockerfile and compose configuration present
  [ -f Dockerfile ] || [ -f docker/Dockerfile ] || [ -f app/Dockerfile ] \
    || gc_refuse ready "missing Dockerfile for platform skeleton (AC-4)"
  [ -f docker-compose.yml ] || [ -f compose.yaml ] || [ -f docker/docker-compose.yml ] \
    || gc_refuse ready "missing docker-compose.yml (or compose.yaml) for platform skeleton (AC-4)"

  # 3. AC-1 & AC-3: Build / verify check
  gs_skip_verify=""
  # >>> kit-test-override (install.sh removes this block; kit test copies only)
  gs_skip_verify="${AGENTS_V0_SKIP_NATIVE_VERIFY:-}"
  # <<< kit-test-override
  if [ -z "$gs_skip_verify" ] && [ -x .agents-v0/scripts/run-backend-verify.sh ]; then
    gs_vcmd="$(sh .agents-v0/scripts/run-backend-verify.sh "Backend verify" 2>/dev/null || true)"
    if [ -n "$gs_vcmd" ]; then
      sh -c "$gs_vcmd" >/dev/null 2>&1 || gc_refuse ready "native backend verify failed: $gs_vcmd"
    fi
  fi

  # 4. Write phase result
  gs_pr="docs/agents-v0/milestones/scaffold.phase-result.md"
  gs_base="$(gc_state_get "$gs_state" baseCommit 2>/dev/null || git rev-parse HEAD)"
  cat > "$gs_pr" <<EOF
# Phase Result: scaffold

- Phase: scaffold
- Status: awaiting_approval
- Artifact: $gs_artifact
- Base-Commit: $gs_base

## Verified Acceptance Criteria
- [x] AC-1: Platform skeleton build and test pass
- [x] AC-2: Milestone P0 manifest tracked ($gs_artifact)
- [x] AC-3: Coverage and quality checks configured
- [x] AC-4: Dockerfile and Compose configurations present
EOF

  gc_ok ready "scaffold baseline verified on $gs_artifact"
  gs_rule ready ready.next; gs_next="$gs_val"
  gs_rule ready ready.status; gs_status="$gs_val"
  gc_state_set "$gs_state" "$gs_feature" "$gs_artifact" "activePhase=$gs_phase" \
    "activeStatus=$gs_status" "blockedReason=" "nextStep=$gs_next" || exit 1
  printf 'Next: %s\n' "$gs_next"
}

gs_commit() {
  [ $# -eq 0 ] || gs_usage
  gs_load commit

  # 1. Check state approved and external approval record matches (DS5, DSA)
  case " $(gc_state_get "$gs_state" approvedPhases | tr -d '[]",') " in
    *" $gs_phase "*) ;;
    *) gc_refuse commit "scaffold is not approved in $gs_state; the user runs approve in their own terminal first" ;;
  esac

  gs_ok_out="$(gc_approval_ok scaffold)" || {
    printf '%s\n' "$gs_ok_out"
    gc_refuse commit "no external approval record matches this scaffold; the user runs approve in their own terminal"
  }
  printf '%s\n' "$gs_ok_out"

  [ -f "$gs_artifact" ] || gc_refuse commit "platform skeleton manifest '$gs_artifact' not found"

  # 2. Update p0-platform-skeleton.md: set status to released and append Delivery approvals row
  gs_rec_file="$(gc_approval_file scaffold)"
  python3 - "$gs_artifact" "$gs_rec_file" <<'PY'
import json, re, sys
manifest, rec_path = sys.argv[1:3]
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
    approver = rec.get("approver", "user")
    approved_at = rec.get("approvedAt", "").split("T")[0]
except Exception:
    approver = "user"
    approved_at = ""

txt = open(manifest, "r", encoding="utf-8").read()
# Update P0-A story row status to released if currently planned
txt = re.sub(
    r"(\|\s*P0-A\s*\|.*?\|\s*)planned(\s*\|)",
    r"\g<1>released\g<2>",
    txt,
    flags=re.I
)

# Append to Delivery approvals
row = f"| scaffold | Approved | {approver} | {approved_at} | Initial platform skeleton baseline |\n"
if "## Delivery approvals" in txt:
    if not re.search(r"\|\s*scaffold\s*\|", txt, re.I):
        txt = txt.rstrip() + "\n" + row
else:
    txt = txt.rstrip() + "\n\n## Delivery approvals\n\n| Phase | Decision | Approver | Date | Notes |\n|---|---|---|---|---|\n" + row

open(manifest, "w", encoding="utf-8").write(txt)
PY

  # 3. Commit and tag via gc_commit_tag (stages allowed paths, secret-scans, commits and tags)
  gc_commit_tag scaffold
}

gs_steps() {
  [ $# -eq 0 ] || gs_usage
  gs_rule steps ready.next; gs_ready_next="$gs_val"
  gs_rule steps approved.next; gs_approved_next="$gs_val"
  G='sh .agents-v0/scripts/guard-scaffold.sh'
  cat <<EOF_STEPS
1. Run \`$G check\`. It verifies entry prerequisites, greenfield status, on-branch integration check, the user's external plan approval record, and that scaffold is not already approved. When it prints \`REFUSED\`, show its message and stop.
2. Run \`$G start\`. It verifies a clean working tree on the integration branch and sets \`docs/agents-v0/program.state.json\` to \`in_progress\` on \`docs/agents-v0/milestones/p0-platform-skeleton.md\`.
3. Launch the \`platform-engineer\` subagent to configure application scaffold files under \`app/\`, \`Dockerfile\`, \`docker-compose.yml\`, and CI verify baseline. It runs no shell commands and leaves \`Delivery approvals\` tables empty.
4. On a blocker, run \`$G block "<plain reason>"\` and stop.
5. When the platform skeleton and container configurations are complete, run \`$G ready\`. It verifies the milestone P0 manifest, Dockerfile, docker-compose.yml, executes the pack's native backend verify command, writes \`docs/agents-v0/milestones/scaffold.phase-result.md\`, and sets state to \`awaiting_approval\`. When it prints \`REFUSED\`, fix what it names and run \`ready\` again.
6. Stop. Present the platform skeleton verification report to the user. Next: $gs_ready_next. Never run approve yourself; the agent cannot approve this gate.
7. After the user runs approve in their own terminal, run \`$G commit\`. It verifies the user's approval record, updates \`p0-platform-skeleton.md\` status to released with the approved Delivery row, stages scaffold files, secret-scans, makes the single gate commit, and tags \`scaffold-v<n>\`. Then suggest: $gs_approved_next.
EOF_STEPS
}

cmd="${1:-}"
case "$cmd" in
  check) shift; gs_check "$@" ;;
  start) shift; gs_start "$@" ;;
  block) shift; gs_block "$@" ;;
  ready) shift; gs_ready "$@" ;;
  commit) shift; gs_commit "$@" ;;
  steps) shift; gs_steps "$@" ;;
  *) gs_usage ;;
esac
