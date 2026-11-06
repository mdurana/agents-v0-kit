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

gd_ready() {
  [ $# -eq 1 ] || gd_usage
  gd_r_slug="$1"
  gd_load ready "$gd_r_slug"
  gd_rule ready ready.requires "$gd_feature"; gd_requires="$gd_val"
  gd_check_prereqs ready "$gd_requires" 0

  gd_brief="docs/agents-v0/design/${gd_feature}/helper-brief.md"
  if [ -f "$gd_brief" ]; then
    gc_refuse ready "unresolved helper brief '$gd_brief' is still on disk; resolve and remove it (or run $G block $gd_feature \"<reason>\")"
  fi

  # Reject any modification to the repo-wide OpenAPI catalog during Design (Jiraiya Rec 3)
  gd_cat_dirty="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | grep -E '^openapi/' || true)"
  if [ -n "$gd_cat_dirty" ]; then
    gc_refuse ready "repo-wide OpenAPI catalog ($gd_cat_dirty) was modified during Design; keep changes in docs/agents-v0/design/$gd_feature/openapi.yaml (Build merges the approved draft)"
  fi

  [ -f "$gd_artifact" ] || gc_refuse ready "design artifact '$gd_artifact' is missing"

  gd_base="$(gc_state_get "$gd_state" baseCommit 2>/dev/null || git rev-parse HEAD)"

  if ! gd_val_out="$(python3 - "$gd_req_art" "$gd_artifact" "$gd_result" "$gd_feature" "$gd_base" <<'PY'
import glob, os, re, sys
try:
    import yaml
except ImportError:
    yaml = None

req_path, design_path, res_path, slug, base_commit = sys.argv[1:6]
req_txt = open(req_path, "r", encoding="utf-8").read()
design_txt = open(design_path, "r", encoding="utf-8").read()

def refuse(msg):
    print(f"REFUSED ready: {msg}")
    sys.exit(1)

# 1. Unresolved TEMPLATE comments or placeholders in design.md
if "<!-- TEMPLATE:" in design_txt:
    refuse(f"{design_path} still contains unresolved '<!-- TEMPLATE:' lines; replace and delete them")

clean_design = re.sub(r"<!--.*?-->", "", design_txt, flags=re.S)
placeholders = re.findall(r"<(?:feature|reason|AC-\d+|operationId[^>]*|role|BOLA[^>]*|describe[^>]*|metrics[^>]*|feature flag[^>]*|TBD|TODO|[^>]{1,40})>|\[(?:TODO|TBD|FIXME)\]|\b(?:TODO|TBD|FIXME)\b", clean_design)
real_ph = [p for p in placeholders if not re.match(r"^<\s*\d", p)]
if real_ph:
    refuse(f"{design_path} contains unresolved placeholders: {', '.join(sorted(set(real_ph))[:5])}")

# 2. Mandatory sections in design.md
required_sections = [
    "Traceability",
    "Data model",
    "Authorization",
    "Events",
    "Failure modes",
    "Observability",
    "Rollout",
]
for sec in required_sections:
    if not re.search(rf"^##\s+{re.escape(sec)}\b", clean_design, flags=re.M | re.I):
        refuse(f"{design_path} is missing mandatory section '## {sec}'")

def section_body(text, heading):
    m = re.search(rf"^##\s+{re.escape(heading)}\b[^\n]*\n(.*?)(?=^##\s+|\Z)", text, flags=re.M | re.S | re.I)
    return m.group(1).strip() if m else ""

trace_sec = section_body(clean_design, "Traceability")
auth_sec = section_body(clean_design, "Authorization")
events_sec = section_body(clean_design, "Events")
fail_sec = section_body(clean_design, "Failure modes")

# 3. Parse requirements ACs, negative/edge ACs, surfaces, Material, security triggers
clean_req = re.sub(r"<!--.*?-->", "", req_txt, flags=re.S)
ac_matches = list(re.finditer(r"^###\s+AC-(\d+)\b[^\n]*$", clean_req, flags=re.M))
req_acs = [int(m.group(1)) for m in ac_matches]
neg_edge_acs = []
for idx, m in enumerate(ac_matches):
    start = m.end()
    end = ac_matches[idx + 1].start() if idx + 1 < len(ac_matches) else len(clean_req)
    next_h2 = re.search(r"^##\s+", clean_req[start:end], flags=re.M)
    if next_h2:
        end = start + next_h2.start()
    blk = clean_req[start:end]
    km = re.search(r"^Kind:\s*(happy|negative|edge)\s*$", blk, flags=re.M | re.I)
    if km and km.group(1).lower() in ("negative", "edge"):
        neg_edge_acs.append(f"AC-{m.group(1)}")

# T1 & T3: Every AC-n from requirements must appear in Traceability, and no unknown AC-n in design.md
missing_acs = [f"AC-{n}" for n in req_acs if not re.search(rf"\bAC-{n}(?!\d)", trace_sec)]
if missing_acs:
    refuse(f"{design_path} ## Traceability is missing requirements ACs: {', '.join(missing_acs)}")
extra_acs = sorted(set(int(n) for n in re.findall(r"\bAC-(\d+)(?!\d)", clean_design)) - set(req_acs))
if extra_acs:
    refuse(f"{design_path} cites unknown AC ids not in {req_path}: {', '.join('AC-'+str(n) for n in extra_acs)}")

# Failure modes must name every Kind: negative and Kind: edge AC
missing_neg_fail = [ac for ac in neg_edge_acs if not re.search(rf"\b{re.escape(ac)}(?!\d)", fail_sec)]
if missing_neg_fail:
    refuse(f"{design_path} ## Failure modes must name every Kind: negative and Kind: edge AC (missing: {', '.join(missing_neg_fail)})")

# 4. Material: yes check
mat_m = re.search(r"^Material:\s*(yes|no)\b", clean_req, flags=re.M | re.I)
is_material = bool(mat_m and mat_m.group(1).lower() == "yes")
if is_material:
    if "docs/agents-v0/design/system/arc-record.md" not in clean_design:
        refuse(f"{req_path} has 'Material: yes', so {design_path} must cite 'docs/agents-v0/design/system/arc-record.md'")
    if not os.path.isfile("docs/agents-v0/design/system/arc-record.md"):
        refuse(f"{req_path} has 'Material: yes', but 'docs/agents-v0/design/system/arc-record.md' is missing on disk")

# 5. OpenAPI contract validation
openapi_path = f"docs/agents-v0/design/{slug}/openapi.yaml"
has_openapi = os.path.isfile(openapi_path)
no_http_api = bool(re.search(r"N/A:\s*no\s+/api/v1\s+operation", clean_design, flags=re.I))

if has_openapi and no_http_api:
    refuse(f"{openapi_path} exists on disk, so {design_path} must not say 'N/A: no /api/v1 operation'")
if not has_openapi and not no_http_api:
    refuse(f"neither {openapi_path} exists nor does {design_path} record 'N/A: no /api/v1 operation'")

op_ids = []
if has_openapi:
    raw_oa = open(openapi_path, "r", encoding="utf-8").read()
    if yaml is not None:
        try:
            oa = yaml.safe_load(raw_oa)
        except Exception as exc:
            refuse(f"{openapi_path} is not valid YAML: {exc}")
    else:
        oa = None
    if not isinstance(oa, dict) or not str(oa.get("openapi", "")).startswith("3.0"):
        refuse(f"{openapi_path} must declare 'openapi: 3.0.x'")
    # Check no external $ref
    for ref_m in re.finditer(r"\$ref:\s*['\"]?([^'\"\s#]+)", raw_oa):
        ext_ref = ref_m.group(1)
        if ext_ref:
            refuse(f"{openapi_path} must be self-contained (external $ref '{ext_ref}' is forbidden)")
    paths = oa.get("paths") or {}
    if not isinstance(paths, dict) or not paths:
        refuse(f"{openapi_path} must define at least one path under 'paths:'")
    for p_key, p_item in paths.items():
        if not str(p_key).startswith("/api/v1"):
            refuse(f"{openapi_path} path '{p_key}' must start with '/api/v1'")
        if not isinstance(p_item, dict):
            continue
        for method, op_obj in p_item.items():
            m_low = str(method).lower()
            if m_low not in ("get", "post", "put", "patch", "delete", "head", "options"):
                continue
            if not isinstance(op_obj, dict):
                refuse(f"{openapi_path} {method.upper()} {p_key} is invalid")
            op_id = op_obj.get("operationId")
            if not op_id or not isinstance(op_id, str):
                refuse(f"{openapi_path} {method.upper()} {p_key} is missing 'operationId'")
            if op_id in op_ids:
                refuse(f"{openapi_path} has duplicate operationId '{op_id}'")
            op_ids.append(op_id)
            # Check operationId in Authorization and Traceability
            if not re.search(rf"\b{re.escape(op_id)}\b", auth_sec):
                refuse(f"operationId '{op_id}' from {openapi_path} is missing in {design_path} ## Authorization")
            if not re.search(rf"\b{re.escape(op_id)}\b", trace_sec):
                refuse(f"operationId '{op_id}' from {openapi_path} is missing in {design_path} ## Traceability")
            # For {id} path, verify Authorization row has non-empty BOLA resource rule
            if "{" in str(p_key):
                row_found = False
                for line in auth_sec.splitlines():
                    if line.strip().startswith("|") and re.search(rf"\b{re.escape(op_id)}\b", line):
                        cells = [c.strip() for c in line.strip().strip("|").split("|")]
                        if len(cells) >= 3 and cells[2] and cells[2] not in ("-", "—", "N/A", "none"):
                            row_found = True
                if not row_found:
                    refuse(f"operationId '{op_id}' on parameterized path '{p_key}' requires a non-empty BOLA Resource rule in ## Authorization")
            # For POST, require Idempotency-Key header parameter
            if m_low == "post":
                params = (op_obj.get("parameters") or []) + (p_item.get("parameters") or [])
                has_idem = any(isinstance(pr, dict) and str(pr.get("name", "")).lower() == "idempotency-key" for pr in params)
                if not has_idem and not re.search(r"Idempotency-Key", raw_oa, flags=re.I):
                    refuse(f"{openapi_path} POST {p_key} ({op_id}) requires an 'Idempotency-Key' header parameter")
            # For write methods (post/put/patch) with requestBody object schema, check additionalProperties: false
            if m_low in ("post", "put", "patch") and "requestBody" in op_obj:
                if "additionalProperties: false" not in raw_oa and "'additionalProperties': False" not in str(oa):
                    refuse(f"{openapi_path} write operation {method.upper()} {p_key} ({op_id}) request-body schema must set 'additionalProperties: false' (VAPT F8)")

# 6. Event contract validation
asyncapi_path = f"docs/agents-v0/design/{slug}/asyncapi.yaml"
events_dir = f"docs/agents-v0/design/{slug}/events"
event_files = sorted(glob.glob(f"{events_dir}/*")) if os.path.isdir(events_dir) else []
has_events = os.path.isfile(asyncapi_path) or bool(event_files)
no_events = bool(re.search(r"N/A:\s*no\s+event\s+contract", events_sec, flags=re.I))

if has_events and no_events:
    refuse(f"event contract files exist for {slug}, so {design_path} ## Events must not say 'N/A: no event contract'")
if not has_events and not no_events:
    refuse(f"no event contract files exist for {slug}, so {design_path} ## Events must state 'N/A: no event contract'")
for ef in event_files:
    if os.path.isfile(ef):
        eftxt = open(ef, encoding="utf-8").read()
        if "eventVersion" not in eftxt:
            refuse(f"event schema '{ef}' must include 'eventVersion'")

# 7. UX spec & mockups validation
surf_m = re.search(r"^Surfaces:\s*(.+)$", clean_req, flags=re.M | re.I)
surfaces = [s.strip().lower() for s in re.split(r"[,|/]+", surf_m.group(1)) if s.strip()] if surf_m else ["backend"]
ux_spec_path = f"docs/agents-v0/design/{slug}/ux-spec.md"
mockups_dir = f"docs/agents-v0/design/{slug}/mockups"
has_ux = os.path.isfile(ux_spec_path) or ("frontend" in surfaces)

if has_ux:
    if not os.path.isfile(ux_spec_path):
        refuse(f"story includes frontend surface, so '{ux_spec_path}' is required")
    ux_txt = open(ux_spec_path, "r", encoding="utf-8").read()
    if not re.search(r"WCAG\s*2\.1\s*AA", ux_txt, flags=re.I):
        refuse(f"{ux_spec_path} must specify WCAG 2.1 AA accessibility requirements")
    for state_word in ("loading", "error", "empty", "success"):
        if not re.search(rf"\b{state_word}\b", ux_txt, flags=re.I):
            refuse(f"{ux_spec_path} state matrix must cover '{state_word}' state")
    html_files = sorted(glob.glob(f"{mockups_dir}/*.html")) if os.path.isdir(mockups_dir) else []
    if not html_files:
        refuse(f"'{mockups_dir}/' must contain at least one static HTML mockup (*.html)")
    mockup_components = set()
    for hf in html_files:
        htxt = open(hf, "r", encoding="utf-8").read()
        if re.search(r"\bfetch\s*\(|\baxios\.|\bXMLHttpRequest\b", htxt):
            refuse(f"mockup '{hf}' must be static HTML/CSS only (API calls like fetch/axios are forbidden)")
        for cm in re.finditer(r'data-component=["\']([^"\']+)["\']', htxt):
            mockup_components.add(cm.group(1).strip())
    if not mockup_components:
        refuse(f"mockups under '{mockups_dir}/' must mark interactive elements with data-component=\"<Component name>\"")
    for comp in sorted(mockup_components):
        if comp not in ux_txt:
            refuse(f"mockup data-component '{comp}' has no matching entry in {ux_spec_path}")

# 8. Evaluate Contract: None shortcut vs. Standard Design Gate (Jiraiya Rec 2)
has_non_health_public = bool(re.search(r"permitAll|public\s+route|unauthenticated", auth_sec, flags=re.I) and not re.search(r"/(?:health|ready|live)\b", auth_sec))
is_contract_none = (
    no_http_api
    and no_events
    and not has_openapi
    and not has_events
    and not has_ux
    and not is_material
    and not has_non_health_public
)

adr_m = re.search(r"^ADR:\s*(.+)$", clean_design, flags=re.M | re.I)
if not adr_m:
    refuse(f"{design_path} is missing the 'ADR: <path or N/A: no product decision>' line")
adr_val = adr_m.group(1).strip()

if is_contract_none:
    # Preserve existing ## Lessons block in phase-result if present
    lessons_block = "## Lessons\n\n### design\n- none\n"
    if os.path.isfile(res_path):
        old_res = open(res_path, encoding="utf-8").read()
        lm = re.search(r"(^##\s+Lessons\b.*)", old_res, flags=re.M | re.S)
        if lm:
            lessons_block = lm.group(1).rstrip() + "\n"
    res_content = f"""# Phase Result: design ({slug})

- phase: design
- status: contract_none
- guard_managed: true
- feature: {slug}
- artifact: {design_path}
- base_commit: {base_commit}
- contract: none
- adr: {adr_val}

{lessons_block}"""
    with open(res_path, "w", encoding="utf-8") as fh:
        fh.write(res_content)
    print("MODE=contract_none")
    sys.exit(0)

# 9. Standard Design Gate: validate ADR and review.md
if re.match(r"^N/A\b", adr_val, flags=re.I):
    refuse(f"standard design gate requires a real ADR file on 'ADR: docs/agents-v0/adr/<NN>-<slug>.md' (got '{adr_val}')")
adr_path = adr_val.split()[0].strip("`")
if not os.path.isfile(adr_path):
    refuse(f"ADR file '{adr_path}' cited in {design_path} does not exist on disk")
adr_txt = open(adr_path, "r", encoding="utf-8").read()
if not re.search(r"(?:\*\*)?Status(?:\*\*)?:\s*(Proposed|Accepted)\b", adr_txt, flags=re.I):
    refuse(f"ADR '{adr_path}' must declare 'Status: Proposed' (or 'Accepted')")
# Check at least 2 options/alternatives in ADR
opt_count = len(re.findall(r"^(?:###\s+Option|[-*]\s+\*\*Option|\|\s*Option\s+\d)", adr_txt, flags=re.M | re.I))
if opt_count < 2 and not re.search(r"##\s+Alternatives", adr_txt, flags=re.I):
    refuse(f"ADR '{adr_path}' must compare at least two alternatives")

review_path = f"docs/agents-v0/design/{slug}/review.md"
if not os.path.isfile(review_path):
    refuse(f"design review report '{review_path}' is missing; launch design-reviewer first")
rev_txt = open(review_path, "r", encoding="utf-8").read()
first_non_empty = next((l.strip() for l in rev_txt.splitlines() if l.strip()), "")
if first_non_empty != "agent: design-reviewer":
    refuse(f"{review_path} first line must be 'agent: design-reviewer'")

open_criticals = 0
for line in rev_txt.splitlines():
    if line.strip().startswith("|"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 5 and cells[1].lower() == "critical" and cells[4].lower() == "open":
            open_criticals += 1
if open_criticals > 0:
    refuse(f"{review_path} has {open_criticals} Open Critical finding(s); resolve them and re-run design-reviewer before ready")

lessons_block = "## Lessons\n\n### design\n- none\n"
if os.path.isfile(res_path):
    old_res = open(res_path, encoding="utf-8").read()
    lm = re.search(r"(^##\s+Lessons\b.*)", old_res, flags=re.M | re.S)
    if lm:
        lessons_block = lm.group(1).rstrip() + "\n"

res_content = f"""# Phase Result: design ({slug})

- phase: design
- status: awaiting_approval
- guard_managed: true
- feature: {slug}
- artifact: {design_path}
- base_commit: {base_commit}
- adr: {adr_path}
- review: {review_path}
- operations: {len(op_ids)}

{lessons_block}"""

with open(res_path, "w", encoding="utf-8") as fh:
    fh.write(res_content)

print(f"MODE=standard operations={len(op_ids)} adr={adr_path}")
PY
)"; then
    printf '%s\n' "$gd_val_out"
    exit 1
  fi

  case "$gd_val_out" in
    MODE=contract_none*)
      gc_ok ready "design verified with Contract: None shortcut on $gd_artifact"
      printf 'Next: Commit the Contract: None design artifact with: %s commit %s\n' "$G" "$gd_feature"
      ;;
    *)
      gc_ok ready "design artifacts and review verified on $gd_artifact ($gd_val_out)"
      gd_rule ready ready.next "$gd_feature"; gd_next="$gd_val"
      gd_rule ready ready.status "$gd_feature"; gd_status="$gd_val"
      gc_state_set "$gd_state" "$gd_feature" "$gd_req_art" "activePhase=$gd_phase" \
        "activeStatus=$gd_status" "blockedReason=" "nextStep=$gd_next" || exit 1
      printf 'Next: %s\n' "$gd_next"
      ;;
  esac
}

gd_commit() {
  [ $# -eq 1 ] || gd_usage
  gd_cm_slug="$1"
  gd_load commit "$gd_cm_slug"

  [ -f "$gd_state" ] || gc_refuse commit "no state for '$gd_feature' ($gd_state); run $G start $gd_feature and $G ready $gd_feature first"
  [ -f "$gd_artifact" ] || gc_refuse commit "design artifact '$gd_artifact' not found"

  # Reject any modification to the repo-wide OpenAPI catalog during Design (Jiraiya Rec 3)
  gd_cat_dirty="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | grep -E '^openapi/' || true)"
  if [ -n "$gd_cat_dirty" ]; then
    gc_refuse commit "repo-wide OpenAPI catalog ($gd_cat_dirty) was modified during Design; revert catalog changes before committing Design"
  fi

  # Check branch (unless skipped in kit test override)
  gd_skip_bg=0
  # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
  [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gd_skip_bg=1
  # <<< kit-test-override
  if [ "$gd_skip_bg" != 1 ]; then
    gd_cur_br="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ "$gd_cur_br" = "feature/$gd_feature" ] \
      || gc_refuse commit "design commit for '$gd_feature' must run on branch 'feature/$gd_feature' (current: '${gd_cur_br:-detached}')"
  fi

  # Check if Contract: None shortcut was verified by ready
  gd_is_cn=0
  if [ -f "$gd_result" ] && grep -Fq "phase: design" "$gd_result" && grep -Fq "status: contract_none" "$gd_result"; then
    gd_is_cn=1
  fi

  if [ "$gd_is_cn" = 1 ]; then
    # Contract: None shortcut commit (no external approval required; --approve build backfills design)
    gd_story_id="$(python3 - "$gd_req_art" "$gd_state" "$gd_feature" <<'PY'
import glob, json, os, re, sys
req_path, state_path, slug = sys.argv[1:4]
d = json.load(open(state_path, encoding="utf-8"))
d["activePhase"] = ""
d["activeStatus"] = ""
d["blockedReason"] = ""
d["nextStep"] = f"/v0-build {slug}"
with open(state_path, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")

txt = open(req_path, encoding="utf-8").read()
m = re.search(r"^\s*(?:\*\*)?Story(?:\*\*)?:\s*(?:\*\*)?`?([A-Z][A-Z0-9]*-[A-Z0-9]+)", txt, flags=re.M)
if m:
    print(m.group(1))
    sys.exit(0)
for mf in sorted(glob.glob("docs/agents-v0/milestones/*.md")):
    for line in open(mf, encoding="utf-8"):
        if f"requirements/{slug}.md" in line and line.strip().startswith("|"):
            cell = line.strip().strip("|").split("|")[0].strip().strip("`* ")
            if cell:
                print(cell)
                sys.exit(0)
print(slug)
PY
)"
    gd_allowed="docs/agents-v0/design/${gd_feature} docs/agents-v0/requirements/${gd_feature}.state.json docs/agents-v0/requirements/${gd_feature}.phase-result.md"
    if ! gd_bad_staged="$(gc_outside_paths "$gd_allowed")"; then
      gc_refuse commit "the index already holds paths outside Contract: None design ($gd_bad_staged); unstage them first"
    fi
    for gd_p in $gd_allowed; do
      if [ -e "$gd_p" ] || git ls-files --error-unmatch -- "$gd_p" >/dev/null 2>&1; then
        git add -- "$gd_p"
      fi
    done
    gc_scan_staged
    gd_msg="${gd_story_id}: design (Contract: None)"
    git commit -q -m "$gd_msg" || gc_refuse commit "git commit failed for Contract: None design"
    gd_sha="$(git rev-parse --short HEAD)"
    gc_ok commit "design (Contract: None) for $gd_feature committed as $gd_sha (\"$gd_msg\")"
    gd_rule commit approved.next "$gd_feature"; gd_approved_next="$gd_val"
    printf 'Next: %s\n' "$gd_approved_next"
    return 0
  fi

  # Standard Design Gate commit
  case " $(gc_state_get "$gd_state" approvedPhases | tr -d '[]",') " in
    *" $gd_phase "*) ;;
    *) gc_refuse commit "design is not approved in $gd_state; Sensei runs approve in his own terminal first" ;;
  esac

  gd_ok_out="$(gc_approval_ok design "$gd_feature")" || {
    printf '%s\n' "$gd_ok_out"
    gc_refuse commit "no approval record from Sensei matches design ($gd_feature); Sensei runs approve in his own terminal"
  }
  printf '%s\n' "$gd_ok_out"

  # Run traceability check (T1-T3)
  if [ -f "$GC_HERE/check-traceability.sh" ]; then
    sh "$GC_HERE/check-traceability.sh" design "$gd_req_art" || gc_refuse commit "check-traceability.sh design failed for '$gd_feature'"
  fi

  # Promote ADR to Accepted, append verified Design row to <feature>.md, update phase-result.md, and index artifacts in state.json
  gd_rec_file="$(gc_approval_file design "$gd_feature")"
  gd_story_id="$(python3 - "$gd_req_art" "$gd_artifact" "$gd_result" "$gd_state" "$gd_rec_file" "$gd_feature" <<'PY'
import glob, json, os, re, sys

req_path, design_path, res_path, state_path, rec_path, slug = sys.argv[1:7]
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
    approver = rec.get("approver", "Sensei")
    approved_at = rec.get("approvedAt", "").split("T")[0]
except Exception:
    approver = "Sensei"
    approved_at = ""

# 1. Promote cited ADR from Proposed to Accepted
design_txt = open(design_path, "r", encoding="utf-8").read()
adr_m = re.search(r"^ADR:\s*(\S+)", design_txt, flags=re.M | re.I)
adr_path = ""
if adr_m and not adr_m.group(1).lower().startswith("n/a"):
    adr_path = adr_m.group(1).strip("`")
    if os.path.isfile(adr_path):
        atxt = open(adr_path, "r", encoding="utf-8").read()
        atxt_new = re.sub(r"((?:\*\*)?Status(?:\*\*)?:\s*)Proposed\b", r"\g<1>Accepted", atxt, flags=re.I)
        if atxt_new != atxt:
            with open(adr_path, "w", encoding="utf-8") as fh:
                fh.write(atxt_new)

# 2. Collect design artifacts for the approval row and state.json
arts = [design_path]
for opt_p in (
    f"docs/agents-v0/design/{slug}/openapi.yaml",
    f"docs/agents-v0/design/{slug}/asyncapi.yaml",
    f"docs/agents-v0/design/{slug}/ux-spec.md",
    f"docs/agents-v0/design/{slug}/review.md",
):
    if os.path.isfile(opt_p):
        arts.append(opt_p)
if adr_path and os.path.isfile(adr_path):
    arts.append(adr_path)

# 3. Append or update Design row in <feature>.md ## Delivery approvals
req_txt = open(req_path, "r", encoding="utf-8").read()
row = f"| Design | {', '.join(arts)} | {approver} | Approved | {approved_at} |\n"
if "## Delivery approvals" in req_txt:
    if re.search(r"^\|\s*Design\s*\|", req_txt, flags=re.M | re.I):
        req_txt = re.sub(r"^\|\s*Design\s*\|[^\n]*\n", row, req_txt, flags=re.M | re.I)
    else:
        req_txt = req_txt.rstrip() + "\n" + row
else:
    req_txt = req_txt.rstrip() + "\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|---|---|---|---|---|\n" + row
with open(req_path, "w", encoding="utf-8") as fh:
    fh.write(req_txt)

# 4. Update phase-result.md to status: approved
if os.path.isfile(res_path):
    rtxt = open(res_path, "r", encoding="utf-8").read()
    rtxt = re.sub(r"^(- status:\s*).*$", r"\g<1>approved", rtxt, flags=re.M)
    with open(res_path, "w", encoding="utf-8") as fh:
        fh.write(rtxt)

# 5. Index artifacts in <feature>.state.json
if os.path.isfile(state_path):
    st = json.load(open(state_path, encoding="utf-8"))
    art_map = st.get("artifacts") if isinstance(st.get("artifacts"), dict) else {}
    art_map["requirements"] = req_path
    art_map["design"] = design_path
    if os.path.isfile(f"docs/agents-v0/design/{slug}/openapi.yaml"):
        art_map["openapi"] = f"docs/agents-v0/design/{slug}/openapi.yaml"
    if os.path.isfile(f"docs/agents-v0/design/{slug}/ux-spec.md"):
        art_map["uxSpec"] = f"docs/agents-v0/design/{slug}/ux-spec.md"
    if os.path.isfile(f"docs/agents-v0/design/{slug}/review.md"):
        art_map["designReview"] = f"docs/agents-v0/design/{slug}/review.md"
    st["artifacts"] = art_map
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=2)
        fh.write("\n")

# 6. Resolve story ID
m = re.search(r"^\s*(?:\*\*)?Story(?:\*\*)?:\s*(?:\*\*)?`?([A-Z][A-Z0-9]*-[A-Z0-9]+)", req_txt, flags=re.M)
if m:
    print(m.group(1))
    sys.exit(0)
for mf in sorted(glob.glob("docs/agents-v0/milestones/*.md")):
    for line in open(mf, encoding="utf-8"):
        if f"requirements/{slug}.md" in line and line.strip().startswith("|"):
            cell = line.strip().strip("|").split("|")[0].strip().strip("`* ")
            if cell:
                print(cell)
                sys.exit(0)
print(slug)
PY
)"

  gd_rule commit commit.paths "$gd_feature"; gd_allowed="$gd_val"
  if ! gd_bad_staged="$(gc_outside_paths "$gd_allowed")"; then
    gc_refuse commit "the index already holds paths outside design ($gd_bad_staged); unstage them first"
  fi

  for gd_p in $gd_allowed; do
    if [ -e "$gd_p" ] || git ls-files --error-unmatch -- "$gd_p" >/dev/null 2>&1; then
      git add -- "$gd_p"
    fi
  done

  gc_scan_staged
  gd_msg="${gd_story_id}: design approved"
  git commit -q -m "$gd_msg" || gc_refuse commit "git commit failed on feature/$gd_feature"
  gd_sha="$(git rev-parse --short HEAD)"
  gc_ok commit "design for $gd_feature committed on feature/$gd_feature as $gd_sha (\"$gd_msg\")"
  gd_rule commit approved.next "$gd_feature"; gd_approved_next="$gd_val"
  printf 'Next: %s\n' "$gd_approved_next"
}

gd_steps() {
  [ $# -eq 0 ] || gd_usage
  gd_rule steps ready.next; gd_ready_next="$gd_val"
  gd_rule steps approved.next; gd_approved_next="$gd_val"
  G='sh .agents-v0/scripts/guard-design.sh'
  cat <<EOF_STEPS
1. Run \`$G check <feature> [--reopen]\`. It validates the \`<feature>\` slug, blocks \`p0-a*\` (redirecting to \`/v0-scaffold\`), verifies the current checkout is the \`feature/<feature>\` worktree, checks Sensei's external \`intake\` approval and committed gate, and ensures the story is not already released or approved (or checks \`reopenCount < 3\` when \`--reopen\` is passed). When it prints \`REFUSED\`, show its message and stop.
2. Run \`$G start <feature> [--reopen]\`. It verifies a clean working tree on \`feature/<feature>\`, seeds \`docs/agents-v0/design/<feature>/design.md\` from \`docs/agents-v0/design/_design.template.md\` if absent, and sets \`docs/agents-v0/requirements/<feature>.state.json\` to \`in_progress\`.
3. Read \`docs/agents-v0/lessons.md\` and launch the shell-less Design subagents in sequence (none may edit the repo-wide \`openapi/\` catalog or run shell commands):
   - **Contract draft (\`schema-author\`):** When the story adds or modifies an HTTP \`/api/v1\` operation or event contract, write \`docs/agents-v0/design/<feature>/openapi.yaml\` and/or \`docs/agents-v0/design/<feature>/events/\`.
   - **Architecture & ADR (\`solution-architect\`, skill: \`contract-first-design\`):** Write \`docs/agents-v0/design/<feature>/design.md\` (tracing every \`AC-n\` and NFR, data model, BOLA authorization matrix per \`operationId\`, failure modes naming every \`Kind: negative\` and \`Kind: edge\` AC, observability, and rollout), an ADR under \`docs/agents-v0/adr/<NN>-<slug>.md\` (\`Status: Proposed\`, comparing at least two alternatives, or \`ADR: N/A: no product decision\` when \`Contract: None\`), and \`docs/agents-v0/design/system/arc-record.md\` when \`Material: yes\`.
   - **UX spec & mockups (\`ux-designer\`, skill: \`ux-design\`):** For UI-affecting stories, write \`docs/agents-v0/design/<feature>/ux-spec.md\` (flows, loading/error/empty/success state matrix, component defaults, WCAG 2.1 AA rules) and static HTML mockups under \`docs/agents-v0/design/<feature>/mockups/\` with matching \`data-component\` attributes.
   - **Design review (\`design-reviewer\`):** Unless the story qualifies for the \`Contract: None\` shortcut (no \`/api/v1\` operation, no event contract, no \`ux-spec.md\`, no non-health public route, and \`Material: no\`), launch \`design-reviewer\` to write \`docs/agents-v0/design/<feature>/review.md\` and resolve any open \`Critical\` findings (max 3 cycles).
4. If \`docs/agents-v0/design/<feature>/helper-brief.md\` exists or open \`Critical\` findings remain after 3 review cycles, run \`$G block <feature> "<plain reason>"\` (which deduplicates helper briefs and records \`blocked\`). If a helper brief was written, launch the named helper, pass findings back, remove the brief, and resume; otherwise stop and escalate to Sensei.
5. When the design artifacts are complete, run \`$G ready <feature>\`. It verifies that the repo-wide \`openapi/\` catalog is untouched, checks \`design.md\` sections, AC traceability (\`T1\`–\`T3\`), \`Kind: negative\`/\`edge\` failure modes, OpenAPI 3.0 validity (\`/api/v1/\`, \`additionalProperties: false\`, \`Idempotency-Key\`, BOLA rules), UX mockup \`data-component\` parity, ADR options, and zero open \`Critical\` findings in \`review.md\`. When the story qualifies for the \`Contract: None\` shortcut, \`ready\` records \`status: contract_none\`; run \`$G commit <feature>\` and proceed directly to \`$gd_approved_next\`. Otherwise \`ready\` writes \`docs/agents-v0/requirements/<feature>.phase-result.md\` and sets state to \`awaiting_approval\`. When it prints \`REFUSED\`, fix what it names and run \`ready\` again.
6. Stop. Present the design artifacts and \`review.md\` summary to Sensei and wait for explicit approval. Next: $gd_ready_next. Never run approve yourself; the agent cannot approve this gate.
7. After Sensei runs approve in his own terminal, run \`$G commit <feature>\`. It verifies Sensei's external approval record, promotes the cited ADR to \`Status: Accepted\`, appends the verified \`Design\` row to \`Delivery approvals\`, runs traceability checks, stages only the story's design and state paths, scans staged content for secrets, and commits \`"<story>: design approved"\` on \`feature/<feature>\`. Then suggest: $gd_approved_next.
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




