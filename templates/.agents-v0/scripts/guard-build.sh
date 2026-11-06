#!/bin/sh
# guard-build.sh — single entry point and security boundary for /v0-build.
# Usage:
#   sh .agents-v0/scripts/guard-build.sh check <feature> [--reopen]
#   sh .agents-v0/scripts/guard-build.sh start <feature> [--reopen]
#   sh .agents-v0/scripts/guard-build.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-build.sh ready <feature>
#   sh .agents-v0/scripts/guard-build.sh commit <feature>
#   sh .agents-v0/scripts/guard-build.sh steps
#
# Design: DB1 (/v0-build guard and parameterized per-story build gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-build.sh"

gb_usage() {
  printf 'usage: %s check <feature> [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gb_validate_slug() {
  gb_v_step="$1"
  gb_v_slug="${2:-}"
  [ -n "$gb_v_slug" ] || gc_refuse "$gb_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gb_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gb_v_step" "feature slug '$gb_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gb_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gb_v_step" "feature slug '$gb_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gb_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gb_v_step" "story '$gb_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-build"
      ;;
  esac
}

gb_rule() {
  gb_step="$1"
  gb_key="$2"
  gb_slug="${3:-}"
  gb_rules="${GC_HERE}/../gate-rules"
  [ -f "$gb_rules" ] || gc_refuse "$gb_step" "missing gate-rules file ($gb_rules)"
  gb_val="$(awk -v p="build" -v k="$gb_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gb_rules")"
  [ -n "$gb_val" ] || gc_refuse "$gb_step" "gate-rules missing key '$gb_key' for phase 'build'"
  if [ -n "$gb_slug" ]; then
    gb_val="$(printf '%s' "$gb_val" | sed "s/<feature>/$gb_slug/g")"
  fi
}

gb_load() {
  gb_step="$1"
  gb_slug="$2"
  gb_validate_slug "$gb_step" "$gb_slug"
  gc_to_root "$gb_step"
  gb_rule "$gb_step" phase "$gb_slug"; gb_phase="$gb_val"
  gb_rule "$gb_step" feature "$gb_slug"; gb_feature="$gb_val"
  gb_rule "$gb_step" state "$gb_slug"; gb_state="$gb_val"
  gb_rule "$gb_step" artifact "$gb_slug"; gb_artifact="$gb_val"
  gb_rule "$gb_step" report "$gb_slug"; gb_report="$gb_val"
  gb_rule "$gb_step" output "$gb_slug"; gb_output="$gb_val"
  gb_rule "$gb_step" result "$gb_slug"; gb_result="$gb_val"
  gb_req_art="docs/agents-v0/requirements/${gb_feature}.md"
}

gb_check_prereqs() {
  gb_step="$1"
  gb_reqs="$2"
  gb_reopen="${3:-0}"
  gb_rule "$gb_step" approved.next "$gb_feature"; gb_approved_next="$gb_val"

  for gb_req in $gb_reqs; do
    case "$gb_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gb_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      feature-branch)
        gb_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gb_skip_bg=1
        # <<< kit-test-override
        if [ "$gb_skip_bg" != 1 ]; then
          gb_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [ "$gb_cur" != "feature/$gb_feature" ]; then
            gb_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${gb_feature}" '
              /^worktree / { path = substr($0, 10) }
              $0 == want { print path; exit }
            ')"
            if [ -n "$gb_wt" ]; then
              gc_refuse "$gb_step" "build for '$gb_feature' must run in worktree '$gb_wt' on branch 'feature/$gb_feature' (current branch: '${gb_cur:-detached}'). Open that folder and run /v0-build $gb_feature there"
            else
              gc_refuse "$gb_step" "no 'feature/$gb_feature' branch or worktree exists (current branch: '${gb_cur:-detached}'); complete /v0-intake $gb_feature (approve + guard-intake.sh commit $gb_feature) first"
            fi
          fi
        fi
        ;;
      pack-configured)
        if [ -f "docs/agents-v0/project-profile.md" ] && [ -d ".agents-v0/packs" ]; then
          gb_pack="$(awk -F'|' '
            function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
            tolower($0) ~ /\|[ \t]*pack[ \t]*\|/ {
              v = trim($3)
              gsub(/<!--.*-->/, "", v)
              v = trim(v)
              if (v != "" && v !~ /^</) { print v; exit }
            }
          ' docs/agents-v0/project-profile.md)"
          if [ -n "$gb_pack" ] && [ ! -f ".agents-v0/packs/$gb_pack/pack.json" ]; then
            gc_refuse "$gb_step" "project-profile.md names Pack '$gb_pack', but '.agents-v0/packs/$gb_pack/pack.json' is missing"
          fi
        fi
        ;;
      not-released)
        if [ -f "$gb_state" ]; then
          case " $(gc_state_get "$gb_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              gc_refuse "$gb_step" "story '$gb_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              ;;
          esac
        fi
        ;;
      design-approved)
        [ -f "$gb_req_art" ] \
          || gc_refuse "$gb_step" "requirements artifact '$gb_req_art' is missing; complete /v0-intake $gb_feature and /v0-design $gb_feature first"
        [ -f "$gb_state" ] \
          || gc_refuse "$gb_step" "requirements state '$gb_state' is missing; complete /v0-intake $gb_feature and /v0-design $gb_feature first"
        gb_cn=0
        if [ -f "$gb_result" ] && grep -Fq "phase: design" "$gb_result" && grep -Fq "status: contract_none" "$gb_result"; then
          gb_cn=1
        fi
        if [ "$gb_cn" != 1 ]; then
          case " $(gc_state_get "$gb_state" approvedPhases | tr -d '[]",') " in
            *" design "*) ;;
            *) gc_refuse "$gb_step" "design is not in approvedPhases in '$gb_state' (and not Contract: None); complete /v0-design $gb_feature first" ;;
          esac
          gb_dgm="$(gc_state_get "$gb_state" designGuardManaged 2>/dev/null || true)"
          if [ "$gb_dgm" = "True" ] || [ "$gb_dgm" = "true" ]; then
            if ! gb_des_ok="$(gc_approval_ok design "$gb_feature")"; then
              gc_refuse "$gb_step" "external design approval record missing or mismatched ($gb_des_ok); complete /v0-design $gb_feature first"
            fi
          fi
        fi
        # Verify design gate is committed (unless skipped in kit test override)
        gb_skip_cc=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gb_skip_cc=1
        # <<< kit-test-override
        if [ "$gb_skip_cc" != 1 ] && [ -f "$GC_HERE/check-gate-commit.sh" ] && [ "$gb_reopen" != 1 ]; then
          gb_prev_act="$(gc_state_get "$gb_state" activePhase 2>/dev/null || true)"
          if [ -z "$gb_prev_act" ]; then
            if ! gb_cc_out="$(sh "$GC_HERE/check-gate-commit.sh" "$gb_req_art" 2>&1)"; then
              gc_refuse "$gb_step" "design gate is not committed on feature/$gb_feature: $gb_cc_out"
            fi
          fi
        fi
        ;;
      dependencies-verified)
        if [ -f "$GC_HERE/check-story-dependencies.sh" ]; then
          if ! gb_dep_out="$(sh "$GC_HERE/check-story-dependencies.sh" "$gb_req_art" 2>&1)"; then
            gc_refuse "$gb_step" "story dependency check failed: $gb_dep_out"
          fi
        fi
        ;;
      not-approved)
        if [ "$gb_reopen" != 1 ] && [ -f "$gb_state" ]; then
          case " $(gc_state_get "$gb_state" approvedPhases | tr -d '[]",') " in
            *" $gb_phase "*)
              gc_refuse "$gb_step" "build is already approved for '$gb_feature'; suggest $gb_approved_next (or pass --reopen to reopen build)"
              ;;
          esac
        fi
        if [ "$gb_reopen" = 1 ] && [ -f "$gb_state" ]; then
          gb_rc="$(gc_state_get "$gb_state" reopenCount 2>/dev/null || echo 0)"
          case "$gb_rc" in ''|*[!0-9]*) gb_rc=0 ;; esac
          if [ "$gb_rc" -ge 3 ]; then
            gc_refuse "$gb_step" "reopen bounce cap exceeded for '$gb_feature' (reopenCount=$gb_rc >= 3); escalate to Sensei before reopening again"
          fi
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gb_state" ]; then
          [ "$(gc_state_get "$gb_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gb_step" "build for '$gb_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve build $gb_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gb_state" ] || gc_refuse "$gb_step" "build for '$gb_feature' has not been started; run $G start $gb_feature first"
        [ "$(gc_state_get "$gb_state" activePhase)" = "$gb_phase" ] \
          || gc_refuse "$gb_step" "activePhase for '$gb_feature' is '$(gc_state_get "$gb_state" activePhase)', not '$gb_phase'; run $G start $gb_feature first"
        [ "$(gc_state_get "$gb_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gb_step" "build for '$gb_feature' is not in_progress (status: $(gc_state_get "$gb_state" activeStatus)); run $G start $gb_feature first"
        ;;
      *) gc_refuse "$gb_step" "gate-rules names an unknown prerequisite '$gb_req'; reinstall the kit" ;;
    esac
  done
}

gb_check() {
  gb_c_slug=""
  gb_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gb_c_reopen=1
        shift
        ;;
      -*)
        gb_usage
        ;;
      *)
        [ -z "$gb_c_slug" ] || gb_usage
        gb_c_slug="$1"
        shift
        ;;
    esac
  done

  gb_load check "$gb_c_slug"
  gb_rule check check.requires "$gb_feature"; gb_requires="$gb_val"
  gb_check_prereqs check "$gb_requires" "$gb_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-build $gb_feature"
  if [ "$gb_c_reopen" = 1 ]; then
    printf 'Next: Start reopened build with: %s start %s --reopen\n' "$G" "$gb_feature"
  else
    printf 'Next: Start build with: %s start %s\n' "$G" "$gb_feature"
  fi
}

# Design: DB2 (/v0-build start, block, reopen, and helper/failure-brief deduplication).
gb_start() {
  gb_s_slug=""
  gb_s_reopen=0
  gb_s_check_db=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gb_s_reopen=1
        shift
        ;;
      --check-db)
        gb_s_check_db=1
        shift
        ;;
      -*)
        gb_usage
        ;;
      *)
        [ -z "$gb_s_slug" ] || gb_usage
        gb_s_slug="$1"
        shift
        ;;
    esac
  done

  gb_load start "$gb_s_slug"
  gb_rule start start.requires "$gb_feature"; gb_requires="$gb_val"
  gb_check_prereqs start "$gb_requires" "$gb_s_reopen"
  if [ "$gb_s_reopen" != 1 ]; then
    gb_check_prereqs start "not-approved" 0
  else
    gb_check_prereqs start "not-approved" 1
  fi

  # Collision guard: refuse unrelated dirty paths outside build/app/openapi/<feature>
  gb_dirty="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | grep -v '\.lock$' | grep -Ev "^(app/|openapi/|docs/agents-v0/build/${gb_feature}/|docs/agents-v0/requirements/${gb_feature}\\.)" || true)"
  if [ -n "$gb_dirty" ]; then
    gc_refuse start "working tree has uncommitted changes outside build paths ($gb_dirty); commit or stash them first"
  fi

  if [ "$gb_s_check_db" = 1 ] && [ -f "$GC_HERE/check-database-runtime.sh" ]; then
    if ! gb_db_out="$(sh "$GC_HERE/check-database-runtime.sh" --phase build "$gb_req_art" 2>&1)"; then
      gc_refuse start "database runtime unavailable ($gb_db_out); run $G block $gb_feature \"Database runtime unavailable\" and stop"
    fi
  fi

  mkdir -p "docs/agents-v0/build/${gb_feature}"

  # Seed plan.md from approved AC-1..AC-n in requirements/<feature>.md when absent
  if [ ! -f "$gb_artifact" ]; then
    GB_REQ="$gb_req_art" GB_PLAN="$gb_artifact" GB_SLUG="$gb_feature" python3 - <<'PYPLAN'
import os, re
req_text = open(os.environ["GB_REQ"], encoding="utf-8").read()
clean_req = re.sub(r"<!--.*?-->", "", req_text, flags=re.S)
acs = sorted(set(int(n) for n in re.findall(r"^###\s+AC-(\d+)\b", clean_req, re.M)))
if not acs:
    acs = [1]
lines = [
    f"# Build Plan: {os.environ['GB_SLUG']}",
    "",
    "| AC | Status | Test | Risk |",
    "| --- | --- | --- | --- |",
]
for n in acs:
    lines.append(f"| AC-{n} | pending | TBD | standard |")
with open(os.environ["GB_PLAN"], "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PYPLAN
  fi

  # Seed build-report.md when absent
  if [ ! -f "$gb_report" ]; then
    cat > "$gb_report" <<EOF
# Build Report: ${gb_feature}

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |

## Final Verify Summary
- Status: pending

## Per-Criterion Evidence
EOF
  fi

  gb_base="$(git rev-parse --verify -q HEAD 2>/dev/null || true)"
  if [ "$gb_s_reopen" = 1 ]; then
    sh "$GC_HERE/sync-feature-state.sh" --reopen build "$gb_req_art" >/dev/null
  else
    sh "$GC_HERE/sync-feature-state.sh" --active-phase build --status in_progress "$gb_req_art" >/dev/null
  fi

  GB_ST="$gb_state" GB_BASE="$gb_base" python3 - <<'PY'
import json, os
p = os.environ["GB_ST"]
base = os.environ["GB_BASE"]
d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
if base and not d.get("baseCommit"):
    d["baseCommit"] = base
d["buildGuardManaged"] = True
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY

  gb_rule start start.next "$gb_feature"; gb_next="$gb_val"
  gc_ok start "build is in_progress for $gb_feature ($gb_artifact, $gb_report)"
  printf 'Next: %s\n' "$gb_next"
}

gb_block() {
  gb_b_slug="${1:-}"
  shift || true
  gb_b_reason="${1:-}"
  [ $# -le 1 ] || gb_usage
  gb_load block "$gb_b_slug"
  gb_b_clean="$(gc_clean_reason block "$gb_b_reason")"

  # Deduplicate helper-brief.md or failure-brief.md by SHA-256
  gb_hb=""
  if [ -f "docs/agents-v0/build/${gb_feature}/helper-brief.md" ]; then
    gb_hb="docs/agents-v0/build/${gb_feature}/helper-brief.md"
  elif [ -f "docs/agents-v0/build/${gb_feature}/failure-brief.md" ]; then
    gb_hb="docs/agents-v0/build/${gb_feature}/failure-brief.md"
  elif [ -f "docs/agents-v0/requirements/${gb_feature}.helper-brief.md" ]; then
    gb_hb="docs/agents-v0/requirements/${gb_feature}.helper-brief.md"
  fi
  if [ -n "$gb_hb" ] && [ -f "$gb_state" ]; then
    gb_dup="$(GB_ST="$gb_state" GB_HB="$gb_hb" python3 - <<'PY'
import hashlib, json, os
st_p = os.environ["GB_ST"]
hb_p = os.environ["GB_HB"]
d = json.load(open(st_p, encoding="utf-8")) if os.path.isfile(st_p) else {}
h = hashlib.sha256(open(hb_p, "rb").read()).hexdigest()
prev_h = d.get("lastHelperBriefHash", "")
if prev_h and prev_h == h:
    print("DUP")
else:
    d["lastHelperBriefHash"] = h
    with open(st_p, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
    print("OK")
PY
)"
    if [ "$gb_dup" = "DUP" ]; then
      gc_refuse block "identical brief ($gb_hb) was already recorded; escalate to Sensei instead of repeating the same ask"
    fi
  fi

  sh "$GC_HERE/sync-feature-state.sh" --active-phase build --status blocked --reason "$gb_b_clean" "$gb_req_art" >/dev/null
  gb_rule block block.next "$gb_feature"; gb_next="$gb_val"
  gc_ok block "build is blocked for $gb_feature ($gb_b_clean)"
  printf 'Next: %s\n' "$gb_next"
}

# Design: DB3 (/v0-build ready TDD plan, attempt budget, failure brief, contract merge, test execution, and evidence validator).
gb_ready() {
  gb_r_slug="${1:-}"
  [ $# -le 1 ] || gb_usage
  gb_load ready "$gb_r_slug"
  gb_rule ready ready.requires "$gb_feature"; gb_requires="$gb_val"
  gb_check_prereqs ready "$gb_requires" 0

  [ -f "$gb_artifact" ] || gc_refuse ready "build plan '$gb_artifact' does not exist"
  [ -f "$gb_report" ] || gc_refuse ready "build report '$gb_report' does not exist"
  [ -f "$gb_output" ] || gc_refuse ready "build output '$gb_output' does not exist"

  # 1. Attempt budget check (< 8 failed attempts)
  if [ -f "$GC_HERE/check-attempt-budget.sh" ]; then
    if ! gb_ab_out="$(sh "$GC_HERE/check-attempt-budget.sh" "$gb_report" 2>&1)"; then
      gc_refuse ready "attempt budget spent ($gb_ab_out); run $G block $gb_feature \"Attempt budget spent\" and stop"
    fi
  fi

  # 2. Failure-brief check on 2nd red for same test
  if [ -f "$GC_HERE/check-failure-brief.sh" ]; then
    if ! gb_fb_out="$(sh "$GC_HERE/check-failure-brief.sh" "$gb_feature" 2>&1)"; then
      gc_refuse ready "failure brief check failed ($gb_fb_out)"
    fi
  fi

  # 3. Deterministic validation of 3rd consecutive red, plan.md, catalog merge, traceability, build-report.md, and build-output.txt
  gb_val_err="$(GB_SLUG="$gb_feature" GB_REQ="$gb_req_art" GB_PLAN="$gb_artifact" GB_REPORT="$gb_report" GB_OUT="$gb_output" python3 - <<'PYVAL'
import os, re, sys

slug = os.environ["GB_SLUG"]
req_p = os.environ["GB_REQ"]
plan_p = os.environ["GB_PLAN"]
rep_p = os.environ["GB_REPORT"]
out_p = os.environ["GB_OUT"]

req_raw = open(req_p, encoding="utf-8", errors="replace").read()
clean_req = re.sub(r"<!--.*?-->", "", req_raw, flags=re.S)
req_acs = sorted(set(int(n) for n in re.findall(r"^###\s+AC-(\d+)\b", clean_req, re.M)))
req_ac_ids = [f"AC-{n}" for n in req_acs]

plan_raw = open(plan_p, encoding="utf-8", errors="replace").read()
clean_plan = re.sub(r"<!--.*?-->", "", plan_raw, flags=re.S)

rep_raw = open(rep_p, encoding="utf-8", errors="replace").read()
clean_rep = re.sub(r"<!--.*?-->", "", rep_raw, flags=re.S)

out_raw = open(out_p, encoding="utf-8", errors="replace").read()

# A. Check 3rd failure for the same test in build-report.md Attempt Cards
counts = {}
in_cards = False
total_cards = 0
for line in clean_rep.splitlines():
    if not line.strip().startswith("|"):
        in_cards = False
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 4:
        continue
    low = [c.lower() for c in cells]
    if low[0] == "command" and low[1] == "exit":
        in_cards = True
        continue
    if not in_cards or set(line.replace("|", "").strip()) <= set("-: "):
        continue
    total_cards += 1
    exit_code = cells[1]
    if not exit_code.isdigit() or exit_code == "0":
        continue
    failing = cells[3] if len(cells) > 3 else ""
    if not failing or failing in ("—", "-", "n/a", "N/A"):
        failing = "(unnamed)"
    counts[failing] = counts.get(failing, 0) + 1

third_red = [f"{name} ({n} failed attempts)" for name, n in counts.items() if n >= 3]
if third_red:
    print(f"third failure cap exceeded in {rep_p} for test(s): {', '.join(third_red)}; run guard-build.sh block {slug} 'Third consecutive failure' and stop")
    sys.exit(0)

# B. Validate plan.md rows
plan_rows = {}
in_plan = False
for line in clean_plan.splitlines():
    if not line.strip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 3:
        continue
    low = [c.lower() for c in cells]
    if low[0] == "ac" and low[1] == "status":
        in_plan = True
        continue
    if not in_plan or set(line.replace("|", "").strip()) <= set("-: "):
        continue
    ac_cell = cells[0].strip("`* ")
    status_cell = cells[1].strip("`* ").lower()
    test_cell = cells[2].strip("`* ")
    risk_cell = cells[3].strip("`* ").lower() if len(cells) > 3 else "standard"
    plan_rows[ac_cell] = (status_cell, test_cell, risk_cell)

missing_plan = [ac for ac in req_ac_ids if ac not in plan_rows]
if missing_plan:
    print(f"{plan_p} is missing row(s) for approved requirement ACs: {', '.join(missing_plan)}")
    sys.exit(0)

extra_plan = [ac for ac in plan_rows if ac not in req_ac_ids]
if extra_plan:
    print(f"{plan_p} contains unknown AC row(s) not in {req_p}: {', '.join(extra_plan)}")
    sys.exit(0)

for ac in req_ac_ids:
    st, tst, rsk = plan_rows[ac]
    if st != "done":
        print(f"{plan_p} row for {ac} has Status '{st}' (every AC row must be 'done' before ready)")
        sys.exit(0)
    if not tst or tst.lower() in ("tbd", "todo", "none", "-", "—") or tst.startswith("<"):
        print(f"{plan_p} row for {ac} must name a concrete test or '(no-red: <reason>)' (found '{tst}')")
        sys.exit(0)
    if rsk not in ("standard", "critical"):
        print(f"{plan_p} row for {ac} has invalid Risk '{rsk}' (expected 'standard' or 'critical')")
        sys.exit(0)

# C. Validate OpenAPI catalog merge when docs/agents-v0/design/<feature>/openapi.yaml exists
design_spec_p = f"docs/agents-v0/design/{slug}/openapi.yaml"
if os.path.isfile(design_spec_p):
    d_spec = open(design_spec_p, encoding="utf-8", errors="replace").read()
    ops = []
    in_paths = False
    cur_path = None
    for line in d_spec.splitlines():
        if re.match(r"^paths:\s*$", line):
            in_paths = True
            continue
        if in_paths and re.match(r"^\S", line):
            in_paths = False
        mp = re.match(r"^  (/[^:\s]*):\s*$", line) if in_paths else None
        if mp:
            cur_path = mp.group(1)
            continue
        mo = re.match(r"^\s+operationId:\s*['\"]?([A-Za-z0-9_]+)", line)
        if mo and cur_path:
            ops.append((mo.group(1), cur_path))
    if ops:
        cat_texts = []
        if os.path.isdir("openapi"):
            for f in sorted(os.listdir("openapi")):
                if f.endswith((".yaml", ".yml")):
                    cat_texts.append(open(os.path.join("openapi", f), encoding="utf-8", errors="replace").read())
        merged_all = "\n".join(cat_texts)
        if not merged_all.strip():
            print(f"{design_spec_p} exists, but no repo catalog file was found under openapi/ (merge approved operations into openapi/api-v1.yaml or openapi/<service>-v1.yaml)")
            sys.exit(0)
        for op, pth in ops:
            if not re.search(rf"\b{re.escape(op)}\b", merged_all) or pth not in merged_all:
                print(f"operation '{op}' ({pth}) from {design_spec_p} is not merged into repo openapi/ catalog")
                sys.exit(0)

# D. Validate build-report.md has at least one Attempt Card, non-pending Final Verify Summary, and per-AC file:line citations
if total_cards == 0:
    print(f"{rep_p} has no attempt cards in '## Attempt Cards' table")
    sys.exit(0)

if re.search(r"Status:\s*pending\b", clean_rep, re.I):
    print(f"{rep_p} still has 'Status: pending' in Final Verify Summary")
    sys.exit(0)

for ac in req_ac_ids:
    ac_lines = [l for l in clean_rep.splitlines() if re.search(rf"\b{re.escape(ac)}(?!\d)", l)]
    if not ac_lines or not any(re.search(r"[A-Za-z0-9_./-]+:[0-9]+", l) for l in ac_lines):
        print(f"{rep_p} is missing a 'file:line' evidence citation for {ac}")
        sys.exit(0)

# E. Validate build-output.txt is non-empty
if not out_raw.strip():
    print(f"{out_p} is empty; record raw full-verify command output in {out_p}")
    sys.exit(0)

print("OK")
PYVAL
)"
  if [ "$gb_val_err" != "OK" ]; then
    gc_refuse ready "$gb_val_err"
  fi

  # 4. Traceability check T4 (endpoint has code under app/) & T5 (endpoint has test under app/)
  if [ -f "$GC_HERE/check-traceability.sh" ]; then
    gb_tr_out="$(AGENTS_V0_TRACE_MODE=fail sh "$GC_HERE/check-traceability.sh" build "$gb_req_art" --no-write 2>&1)" || {
      gc_refuse ready "build traceability check (T4/T5) failed: $gb_tr_out"
    }
  fi

  # 5. Secret scan on build-output.txt and build-report.md
  if [ -f "$GC_HERE/secret_scan.py" ]; then
    gb_sec_out="$(python3 "$GC_HERE/secret_scan.py" "$gb_report" "$gb_output" 2>&1)" || {
      gc_refuse ready "secret scan failed on build evidence: $gb_sec_out"
    }
  fi

  # 6. Verify check-tests-ran.sh (kitfix-20261031-tests-ran)
  if [ -f "$GC_HERE/check-tests-ran.sh" ]; then
    if ! gb_tr_ran="$(sh "$GC_HERE/check-tests-ran.sh" 2>&1)"; then
      gc_refuse ready "check-tests-ran.sh failed: $gb_tr_ran"
    fi
  fi

  # 7. Write/update <feature>.phase-result.md for build
  GB_PR="$gb_result" GB_SLUG="$gb_feature" python3 - <<'PYPR'
import os, re
p = os.environ["GB_PR"]
slug = os.environ["GB_SLUG"]
lessons_block = "## Lessons\n\n### build\n- none\n"
if os.path.isfile(p):
    txt = open(p, encoding="utf-8").read()
    m = re.search(r"(^##\s+Lessons\b.*)", txt, re.M | re.S)
    if m:
        lessons_block = m.group(1).strip() + "\n"
        if "### build" not in lessons_block:
            lessons_block += "\n### build\n- none\n"
content = (
    f"# Phase Result: {slug}\n\n"
    f"phase: build\n"
    f"status: awaiting_approval\n"
    f"guard_managed: true\n\n"
    f"{lessons_block}"
)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(content)
PYPR

  sh "$GC_HERE/sync-feature-state.sh" --active-phase build --status awaiting_approval "$gb_req_art" >/dev/null
  gb_rule ready ready.next "$gb_feature"; gb_next="$gb_val"
  gc_ok ready "build for $gb_feature verified and awaiting Sensei's approval"
  printf 'Next: %s\n' "$gb_next"
}

cmd="${1:-}"
[ -n "$cmd" ] || gb_usage
shift || true

case "$cmd" in
  check) gb_check "$@" ;;
  start) gb_start "$@" ;;
  block) gb_block "$@" ;;
  ready) gb_ready "$@" ;;
  *) gb_usage ;;
esac
