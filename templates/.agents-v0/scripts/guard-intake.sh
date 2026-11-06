#!/bin/sh
# guard-intake.sh — single entry point and security boundary for /v0-intake.
# Usage:
#   sh .agents-v0/scripts/guard-intake.sh check <feature> [--tier trivial|emergency|standard|major] [--reopen]
#   sh .agents-v0/scripts/guard-intake.sh start <feature> [--reopen]
#   sh .agents-v0/scripts/guard-intake.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-intake.sh ready <feature>
#   sh .agents-v0/scripts/guard-intake.sh commit <feature>
#   sh .agents-v0/scripts/guard-intake.sh steps
#
# Design: DI1 (/v0-intake guard and parameterized per-story requirements gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-intake.sh"

gi_usage() {
  printf 'usage: %s check <feature> [--tier trivial|emergency|standard|major] [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gi_validate_slug() {
  gi_v_step="$1"
  gi_v_slug="${2:-}"
  [ -n "$gi_v_slug" ] || gc_refuse "$gi_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gi_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gi_v_step" "feature slug '$gi_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gi_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gi_v_step" "feature slug '$gi_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gi_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gi_v_step" "story '$gi_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-intake"
      ;;
  esac
}

gi_rule() {
  gi_step="$1"
  gi_key="$2"
  gi_slug="${3:-}"
  gi_rules="${GC_HERE}/../gate-rules"
  [ -f "$gi_rules" ] || gc_refuse "$gi_step" "missing gate-rules file ($gi_rules)"
  gi_val="$(awk -v p="intake" -v k="$gi_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gi_rules")"
  [ -n "$gi_val" ] || gc_refuse "$gi_step" "gate-rules missing key '$gi_key' for phase 'intake'"
  if [ -n "$gi_slug" ]; then
    gi_val="$(printf '%s' "$gi_val" | sed "s/<feature>/$gi_slug/g")"
  fi
}

gi_load() {
  gi_step="$1"
  gi_slug="$2"
  gi_validate_slug "$gi_step" "$gi_slug"
  gc_to_root "$gi_step"
  gi_rule "$gi_step" phase "$gi_slug"; gi_phase="$gi_val"
  gi_rule "$gi_step" feature "$gi_slug"; gi_feature="$gi_val"
  gi_rule "$gi_step" state "$gi_slug"; gi_state="$gi_val"
  gi_rule "$gi_step" artifact "$gi_slug"; gi_artifact="$gi_val"
  gi_rule "$gi_step" result "$gi_slug"; gi_result="$gi_val"
}

gi_is_brownfield() {
  [ -f docs/agents-v0/onboarding/state.json ] && return 0
  [ -f docs/agents-v0/onboarding/report.md ] && return 0
  return 1
}

gi_check_prereqs() {
  gi_step="$1"
  gi_reqs="$2"
  gi_reopen="${3:-0}"
  gi_rule "$gi_step" approved.next "$gi_feature"; gi_approved_next="$gi_val"

  for gi_req in $gi_reqs; do
    case "$gi_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gi_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      integration-branch)
        gi_ib="main"
        if [ -x .agents-v0/scripts/resolve-integration-branch.sh ]; then
          gi_ib="$(sh .agents-v0/scripts/resolve-integration-branch.sh 2>/dev/null || echo main)"
          gi_ib="${gi_ib#origin/}"
        fi
        gi_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        if [ -n "$gi_cur" ] && [ "$gi_ib" != "HEAD" ] && [ "$gi_cur" != "$gi_ib" ]; then
          gc_refuse "$gi_step" "intake must start on the integration branch ($gi_ib); current branch is '$gi_cur'. Run git checkout $gi_ib first"
        fi
        ;;
      onboard-if-brownfield)
        if gi_is_brownfield; then
          [ -f docs/agents-v0/onboarding/state.json ] \
            || gc_refuse "$gi_step" "brownfield onboarding state missing (docs/agents-v0/onboarding/state.json); complete /v0-onboard first"
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$gi_step" "brownfield onboarding is not approved in docs/agents-v0/onboarding/state.json; complete /v0-onboard first" ;;
          esac
          if ! gi_onb_ok="$(gc_approval_ok onboard)"; then
            gc_refuse "$gi_step" "external onboard approval record missing or mismatched ($gi_onb_ok); complete /v0-onboard first"
          fi
        fi
        ;;
      plan-if-program)
        if [ -f docs/agents-v0/program.state.json ] || [ -f docs/agents-v0/milestones/plan.md ]; then
          [ -f docs/agents-v0/program.state.json ] \
            || gc_refuse "$gi_step" "program.state.json is missing; complete /v0-plan first"
          case " $(gc_state_get docs/agents-v0/program.state.json approvedPhases | tr -d '[]",') " in
            *" plan "*) ;;
            *) gc_refuse "$gi_step" "plan is not in approvedPhases in docs/agents-v0/program.state.json; complete /v0-plan first" ;;
          esac
          if ! gi_plan_ok="$(gc_approval_ok plan)"; then
            gc_refuse "$gi_step" "external plan approval record missing or mismatched ($gi_plan_ok); complete /v0-plan and have Sensei approve it first"
          fi
        fi
        ;;
      scaffold-if-greenfield)
        if ! gi_is_brownfield && [ -f docs/agents-v0/milestones/p0-platform-skeleton.md ]; then
          [ -f docs/agents-v0/program.state.json ] \
            || gc_refuse "$gi_step" "greenfield project has p0-platform-skeleton.md but no program.state.json; complete /v0-scaffold first"
          case " $(gc_state_get docs/agents-v0/program.state.json approvedPhases | tr -d '[]",') " in
            *" scaffold "*) ;;
            *) gc_refuse "$gi_step" "scaffold is not in approvedPhases in docs/agents-v0/program.state.json; complete /v0-scaffold on the integration branch before story intake" ;;
          esac
          if ! gi_scaf_ok="$(gc_approval_ok scaffold)"; then
            gc_refuse "$gi_step" "external scaffold approval record missing or mismatched ($gi_scaf_ok); complete /v0-scaffold first"
          fi
        fi
        ;;
      not-released)
        if [ -f "$gi_state" ]; then
          case " $(gc_state_get "$gi_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              gc_refuse "$gi_step" "story '$gi_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              ;;
          esac
        fi
        ;;
      not-approved)
        if [ "$gi_reopen" != 1 ] && [ -f "$gi_state" ]; then
          case " $(gc_state_get "$gi_state" approvedPhases | tr -d '[]",') " in
            *" $gi_phase "*)
              gc_refuse "$gi_step" "intake is already approved for '$gi_feature'; suggest $gi_approved_next (or pass --reopen to reopen intake)"
              ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gi_state" ]; then
          [ "$(gc_state_get "$gi_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gi_step" "intake for '$gi_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve intake $gi_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gi_state" ] || gc_refuse "$gi_step" "intake for '$gi_feature' has not been started; run $G start $gi_feature first"
        [ "$(gc_state_get "$gi_state" activePhase)" = "$gi_phase" ] \
          || gc_refuse "$gi_step" "activePhase for '$gi_feature' is '$(gc_state_get "$gi_state" activePhase)', not '$gi_phase'; run $G start $gi_feature first"
        [ "$(gc_state_get "$gi_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gi_step" "intake for '$gi_feature' is not in_progress (status: $(gc_state_get "$gi_state" activeStatus)); run $G start $gi_feature first"
        ;;
      *) gc_refuse "$gi_step" "gate-rules names an unknown prerequisite '$gi_req'; reinstall the kit" ;;
    esac
  done
}

gi_check() {
  gi_c_slug=""
  gi_c_tier="standard"
  gi_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier)
        [ $# -ge 2 ] || gi_usage
        gi_c_tier="$2"
        shift 2
        ;;
      --reopen)
        gi_c_reopen=1
        shift
        ;;
      -*)
        gi_usage
        ;;
      *)
        [ -z "$gi_c_slug" ] || gi_usage
        gi_c_slug="$1"
        shift
        ;;
    esac
  done

  # Change-tier classification gate before touching any requirements or state files (FI6)
  case "$gi_c_tier" in
    trivial)
      gc_refuse check "change tier is 'trivial' — route to /v0-triage; do not create docs/agents-v0/requirements/$gi_c_slug.md or its state file"
      ;;
    emergency)
      gc_refuse check "change tier is 'emergency' — route to /v0-maintain; do not create docs/agents-v0/requirements/$gi_c_slug.md or its state file"
      ;;
    standard|major) ;;
    *)
      gc_refuse check "unknown --tier '$gi_c_tier' (expected trivial, emergency, standard, or major)"
      ;;
  esac

  gi_load check "$gi_c_slug"
  gi_rule check check.requires "$gi_feature"; gi_requires="$gi_val"
  gi_check_prereqs check "$gi_requires" "$gi_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-intake $gi_feature (tier: $gi_c_tier)"
  if [ "$gi_c_reopen" = 1 ]; then
    printf 'Next: Start reopened intake with: %s start %s --reopen\n' "$G" "$gi_feature"
  else
    printf 'Next: Start intake with: %s start %s\n' "$G" "$gi_feature"
  fi
}

gi_start() {
  gi_s_slug=""
  gi_s_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gi_s_reopen=1
        shift
        ;;
      -*)
        gi_usage
        ;;
      *)
        [ -z "$gi_s_slug" ] || gi_usage
        gi_s_slug="$1"
        shift
        ;;
    esac
  done

  gi_load start "$gi_s_slug"
  gi_rule start start.requires "$gi_feature"; gi_requires="$gi_val"
  gi_check_prereqs start "$gi_requires" "$gi_s_reopen"
  if [ "$gi_s_reopen" != 1 ]; then
    gi_check_prereqs start "not-approved" 0
  fi

  # Refuse unrelated dirty paths on the integration branch
  gi_dirty="$(git status --porcelain 2>/dev/null | awk '{print $NF}' | grep -Ev "^docs/agents-v0/requirements/${gi_feature}(\\.|$)" || true)"
  if [ -n "$gi_dirty" ]; then
    gc_refuse start "working tree has uncommitted changes outside docs/agents-v0/requirements/${gi_feature}.*; commit or stash them first"
  fi

  mkdir -p docs/agents-v0/requirements
  if [ ! -f "$gi_artifact" ]; then
    cat > "$gi_artifact" <<EOF
# Feature Requirements: $gi_feature

As a <role>, I want <goal>, so that <benefit>.

Surfaces: backend
Vertical slice: no

## Preconditions

- <precondition>

## Desk check

Material: no
- Reviewed existing endpoints and models.

## Acceptance criteria

### AC-1 — <scenario title>
Kind: happy
Given <precondition>
When <action>
Then <observable outcome>

### AC-2 — <negative or edge scenario title>
Kind: negative
Given <invalid precondition or input>
When <action>
Then the request is rejected with status 400

## Out of scope

- <explicitly excluded item>

## Non-functional requirements

- Latency: p95 < 250ms
- Availability: 99.9%

## Applicable regulations

- None

## Security-review triggers

- Auth / RBAC changes: no
- Untrusted input / file upload: no
- Sensitive data / PII: no
- External network call: no
- State-changing endpoint: yes

## Open questions

Open questions: none

## Delivery approvals

| Phase | Decision | Approver | Date |
|---|---|---|---|
EOF
  fi

  gi_rule start start.next "$gi_feature"; gi_next="$gi_val"
  gi_rule start start.status "$gi_feature"; gi_status="$gi_val"

  if [ "$gi_s_reopen" = 1 ] && [ -f "$gi_state" ]; then
    python3 - "$gi_state" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(0)
phases = [x for x in (d.get("approvedPhases") or []) if x != "intake"]
d["approvedPhases"] = phases
d["lastApprovedPhase"] = phases[-1] if phases else ""
d["reopenCount"] = int(d.get("reopenCount") or 0) + 1
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi

  gc_state_set "$gi_state" "$gi_feature" "$gi_artifact" "activePhase=$gi_phase" \
    "activeStatus=$gi_status" "blockedReason=" "nextStep=$gi_next" || exit 1

  gc_ok start "intake in_progress on $gi_artifact"
  printf 'Next: %s\n' "$gi_next"
}

gi_block() {
  [ $# -ge 2 ] || gc_die "usage: $G block <feature> \"<plain reason>\""
  gi_b_slug="$1"
  shift
  gi_reason="$*"
  [ -n "$(printf '%s' "$gi_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason"

  gi_load block "$gi_b_slug"
  gi_rule block block.status "$gi_feature"; gi_status="$gi_val"
  gi_rule block block.next "$gi_feature"; gi_next="$gi_val"

  [ -f "$gi_state" ] || gc_refuse block "intake for '$gi_feature' has not been started ($gi_state missing)"
  [ "$(gc_state_get "$gi_state" activePhase)" = "$gi_phase" ] \
    || gc_refuse block "activePhase for '$gi_feature' is '$(gc_state_get "$gi_state" activePhase)', not '$gi_phase'"

  # Helper-brief deduplication (FI6): if <feature>.helper-brief.md exists, refuse identical repeat asks
  gi_brief="docs/agents-v0/requirements/${gi_feature}.helper-brief.md"
  if [ -f "$gi_brief" ]; then
    if ! python3 - "$gi_state" "$gi_brief" <<'PY'
import hashlib, json, re, sys
state_p, brief_p = sys.argv[1:3]
raw = open(brief_p, encoding="utf-8").read()
norm = re.sub(r"\s+", " ", raw.strip().lower())
digest = hashlib.sha256(norm.encode("utf-8")).hexdigest()
data = json.load(open(state_p, encoding="utf-8"))
prev = data.get("lastHelperBriefHash") or ""
if prev and prev == digest:
    sys.exit(1)
data["lastHelperBriefHash"] = digest
with open(state_p, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
    then
      gc_refuse block "duplicate helper brief in $gi_brief; do not re-ask the same helper question"
    fi
  fi

  gc_state_set "$gi_state" "$gi_feature" "$gi_artifact" "activePhase=$gi_phase" \
    "activeStatus=$gi_status" "blockedReason=$gi_reason" "nextStep=$gi_next" || exit 1

  gc_ok block "intake for $gi_feature blocked ($gi_reason)"
  printf 'Next: %s\n' "$gi_next"
}

gi_ready() {
  [ $# -eq 1 ] || gi_usage
  gi_r_slug="$1"
  gi_load ready "$gi_r_slug"
  gi_rule ready ready.requires "$gi_feature"; gi_requires="$gi_val"
  gi_check_prereqs ready "$gi_requires" 0

  gi_brief="docs/agents-v0/requirements/${gi_feature}.helper-brief.md"
  if [ -f "$gi_brief" ]; then
    gc_refuse ready "unresolved helper brief '$gi_brief' is still on disk; resolve and remove it (or run $G block $gi_feature \"<reason>\")"
  fi

  [ -f "$gi_artifact" ] || gc_refuse ready "requirements artifact '$gi_artifact' is missing"

  gi_base="$(gc_state_get "$gi_state" baseCommit 2>/dev/null || git rev-parse HEAD)"

  if ! gi_val_out="$(python3 - "$gi_artifact" "$gi_result" "$gi_feature" "$gi_base" <<'PY'
import glob, os, re, sys

art_path, res_path, slug, base_commit = sys.argv[1:5]
txt = open(art_path, "r", encoding="utf-8").read()

def refuse(msg):
    print(f"REFUSED ready: {msg}")
    sys.exit(1)

# 1. Proposed split check
if re.search(r"^##\s+Proposed split\b", txt, flags=re.M | re.I):
    refuse(f"{art_path} contains '## Proposed split'; run guard-intake.sh block {slug} \"Proposed split pending user confirmation\"")

# Strip Delivery approvals section before placeholder scanning
body_lines = []
in_approvals = False
for line in txt.splitlines():
    if re.match(r"^##\s+Delivery approvals\b", line, flags=re.I):
        in_approvals = True
    if not in_approvals:
        body_lines.append(line)
body = "\n".join(body_lines)

# 2. Unresolved placeholders
placeholders = re.findall(r"<(?:role|goal|benefit|precondition|scenario[^>]*|negative[^>]*|action|observable[^>]*|invalid[^>]*|explicitly[^>]*|TBD|TODO|[^>]{1,40})>|\[(?:role|goal|benefit|TODO|TBD|FIXME)\]|\b(?:TODO|TBD|FIXME)\b", body)
# Filter out valid comparison operators like `< 250ms` or `< 100`
real_ph = [p for p in placeholders if not re.match(r"^<\s*\d", p)]
if real_ph:
    refuse(f"{art_path} contains unresolved placeholders: {', '.join(sorted(set(real_ph))[:5])}")

# 3. User story sentence
us_match = re.search(r"(As an?\s+[^,\n]+,\s*I want\s+[^,\n]+,\s*so that\s+[^\n.]+\.)", body, flags=re.I)
if not us_match:
    refuse(f"{art_path} is missing a complete user story sentence ('As a <role>, I want <goal>, so that <benefit>.')")
user_story = us_match.group(1).strip()

# 4. Surfaces & Vertical slice check
surf_match = re.search(r"^Surfaces:\s*(.+)$", body, flags=re.M | re.I)
if not surf_match:
    refuse(f"{art_path} is missing 'Surfaces: backend | bff | frontend'")
raw_surfaces = [s.strip().lower() for s in re.split(r"[,|/]+", surf_match.group(1)) if s.strip()]
valid_surfaces = {"backend", "bff", "frontend"}
if not raw_surfaces or any(s not in valid_surfaces for s in raw_surfaces):
    refuse(f"{art_path} has invalid Surfaces '{surf_match.group(1).strip()}' (expected subset of: backend, bff, frontend)")
vs_match = re.search(r"^Vertical slice:\s*(yes|no)\b", body, flags=re.M | re.I)
is_vertical = bool(vs_match and vs_match.group(1).lower() == "yes")
if len(raw_surfaces) > 1 and not is_vertical:
    refuse(f"{art_path} lists multiple surfaces ({', '.join(raw_surfaces)}) without 'Vertical slice: yes'")

# 5. Mandatory sections
required_sections = [
    "Preconditions",
    "Desk check",
    "Acceptance criteria",
    "Out of scope",
    "Non-functional requirements",
    "Applicable regulations",
    "Security-review triggers",
    "Open questions",
    "Delivery approvals",
]
if "frontend" in raw_surfaces:
    required_sections.append("UX requirements")
for sec in required_sections:
    if not re.search(rf"^##\s+{re.escape(sec)}\b", txt, flags=re.M | re.I):
        refuse(f"{art_path} is missing mandatory section '## {sec}'")

if not re.search(r"^Material:\s*(yes|no)\b", body, flags=re.M | re.I):
    refuse(f"{art_path} Desk check section is missing 'Material: yes | no'")

if not re.search(r"^Open questions:\s*none\s*$", body, flags=re.M | re.I):
    refuse(f"{art_path} must resolve all open questions and state 'Open questions: none'")

# 6. Parse Gherkin Acceptance Criteria (### AC-1 .. ### AC-N)
ac_matches = list(re.finditer(r"^###\s+AC-(\d+)\b[^\n]*$", body, flags=re.M))
if not ac_matches:
    refuse(f"{art_path} has no Gherkin acceptance criteria ('### AC-1 ...')")
ac_nums = [int(m.group(1)) for m in ac_matches]
expected_nums = list(range(1, len(ac_nums) + 1))
if ac_nums != expected_nums:
    refuse(f"{art_path} acceptance criteria must be numbered contiguously AC-1..AC-{len(ac_nums)} (found: {', '.join('AC-'+str(n) for n in ac_nums)})")
if len(ac_nums) > 8:
    refuse(f"{art_path} has {len(ac_nums)} acceptance criteria (maximum is 8; split the story if larger)")

vague_then_re = re.compile(r"\b(works as expected|is handled properly|handles errors gracefully|is processed\s*$|succeeds\s*$)", flags=re.I)
refusal_re = re.compile(r"\b(refuse[ds]?|reject(?:ed|s)?|deni(?:ed|es)|400|401|403|404|409|422|error|fail(?:ed|s)?|invalid|unauthorized|forbidden)\b", flags=re.I)

kinds = []
refusing_negatives = 0
for idx, m in enumerate(ac_matches):
    start = m.end()
    end = ac_matches[idx + 1].start() if idx + 1 < len(ac_matches) else len(body)
    # Stop at next ## heading if last AC
    next_h2 = re.search(r"^##\s+", body[start:end], flags=re.M)
    if next_h2:
        end = start + next_h2.start()
    block = body[start:end]
    ac_id = f"AC-{m.group(1)}"
    km = re.search(r"^Kind:\s*(happy|negative|edge)\s*$", block, flags=re.M | re.I)
    if not km:
        refuse(f"{ac_id} is missing 'Kind: happy | negative | edge'")
    kind = km.group(1).lower()
    kinds.append(kind)
    for kw in ("Given", "When", "Then"):
        if not re.search(rf"^{kw}\s+\S+", block, flags=re.M):
            refuse(f"{ac_id} is missing a '{kw} ...' Gherkin clause")
    for then_m in re.finditer(r"^Then\s+(.+)$", block, flags=re.M):
        clause = then_m.group(1).strip()
        if vague_then_re.search(clause):
            refuse(f"{ac_id} has a vague Then clause ('{clause}'); state a concrete observable outcome")
    if kind == "negative" and refusal_re.search(block):
        refusing_negatives += 1

# 7. Security-review triggers & negative/edge enforcement (Jiraiya Rec 3)
sec_m = re.search(r"^##\s+Security-review triggers\b(.*?)(?=^##\s+|\Z)", body, flags=re.M | re.S | re.I)
sec_block = sec_m.group(1) if sec_m else ""
sec_triggered = bool(re.search(r":\s*(yes|true)\b|\|\s*(yes|true)\s*\|", sec_block, flags=re.I))
neg_na = bool(re.search(r"^Negatives:\s*N/A:\s*\S+", body, flags=re.M | re.I))

neg_or_edge_count = sum(1 for k in kinds if k in ("negative", "edge"))
if sec_triggered:
    if neg_na:
        refuse(f"{art_path} has active security-review triggers, so 'Negatives: N/A' is forbidden")
    if refusing_negatives < 1:
        refuse(f"{art_path} has active security-review triggers and must include at least one refusing 'Kind: negative' AC")
else:
    if neg_or_edge_count < 1 and not neg_na:
        refuse(f"{art_path} must include at least one 'Kind: negative' or 'Kind: edge' AC (or 'Negatives: N/A: <reason>' when no security trigger applies)")

# 8. Milestone story link & size alignment check
ac_count = len(ac_nums)
for mf in sorted(glob.glob("docs/agents-v0/milestones/*.md")):
    if os.path.basename(mf) in ("plan.md", "_template.md"):
        continue
    mtxt = open(mf, encoding="utf-8").read()
    for line in mtxt.splitlines():
        if art_path in line and line.strip().startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 7:
                try:
                    planned_size = int(cells[6])
                except ValueError:
                    planned_size = 0
                if planned_size > 0 and abs(ac_count - planned_size) > 2:
                    if not re.search(r"Plan deviation:\s*\S+", body, flags=re.I):
                        refuse(f"{art_path} has {ac_count} ACs but milestone {mf} planned Size {planned_size} (diff > 2); document 'Plan deviation: <reason>' or align ACs")

# Extract regulations summary
reg_m = re.search(r"^##\s+Applicable regulations\b(.*?)(?=^##\s+|\Z)", body, flags=re.M | re.S | re.I)
reg_summary = "none"
if reg_m:
    reg_items = [re.sub(r"^[-*]\s*", "", l.strip()) for l in reg_m.group(1).strip().splitlines() if l.strip()]
    if reg_items:
        reg_summary = ", ".join(reg_items[:3])

# Preserve existing ## Lessons block in phase-result if present
lessons_block = "## Lessons\n\n### intake\n- none\n"
if os.path.isfile(res_path):
    old_res = open(res_path, encoding="utf-8").read()
    lm = re.search(r"(^##\s+Lessons\b.*)", old_res, flags=re.M | re.S)
    if lm:
        lessons_block = lm.group(1).rstrip() + "\n"

res_content = f"""# Phase Result: intake ({slug})

- phase: intake
- status: awaiting_approval
- guard_managed: true
- feature: {slug}
- artifact: {art_path}
- base_commit: {base_commit}
- user_story: {user_story}
- ac_count: {ac_count}
- negative_count: {neg_or_edge_count}
- regulations: {reg_summary}
- open_questions: none

{lessons_block}"""

with open(res_path, "w", encoding="utf-8") as fh:
    fh.write(res_content)

print(f"ac_count={ac_count} negative_or_edge={neg_or_edge_count}")
PY
)"; then
    printf '%s\n' "$gi_val_out"
    exit 1
  fi

  gc_ok ready "intake requirements verified on $gi_artifact ($gi_val_out)"
  gi_rule ready ready.next "$gi_feature"; gi_next="$gi_val"
  gi_rule ready ready.status "$gi_feature"; gi_status="$gi_val"
  gc_state_set "$gi_state" "$gi_feature" "$gi_artifact" "activePhase=$gi_phase" \
    "activeStatus=$gi_status" "blockedReason=" "nextStep=$gi_next" || exit 1
  printf 'Next: %s\n' "$gi_next"
}

gi_commit() {
  [ $# -eq 1 ] || gi_usage
  gi_cm_slug="$1"
  gi_load commit "$gi_cm_slug"

  # Support invoking commit from either the integration branch or an existing feature/<feature> worktree (Jiraiya Rec 2)
  gi_wt_existing="$(git worktree list --porcelain | awk -v want="branch refs/heads/feature/${gi_feature}" '
    /^worktree / { path = substr($0, 10) }
    $0 == want { print path; exit }
  ')"
  if [ ! -f "$gi_state" ] && [ -n "$gi_wt_existing" ] && [ -f "$gi_wt_existing/$gi_state" ]; then
    cd "$gi_wt_existing"
  fi

  [ -f "$gi_state" ] || gc_refuse commit "no intake state for '$gi_feature' ($gi_state); run $G start $gi_feature and $G ready $gi_feature first"

  case " $(gc_state_get "$gi_state" approvedPhases | tr -d '[]",') " in
    *" $gi_phase "*) ;;
    *) gc_refuse commit "intake is not approved in $gi_state; Sensei runs approve in his own terminal first" ;;
  esac

  gi_ok_out="$(gc_approval_ok intake "$gi_feature")" || {
    printf '%s\n' "$gi_ok_out"
    gc_refuse commit "no approval record from Sensei matches intake ($gi_feature); Sensei runs approve in his own terminal"
  }
  printf '%s\n' "$gi_ok_out"

  [ -f "$gi_artifact" ] || gc_refuse commit "requirements artifact '$gi_artifact' not found"

  # Update Delivery approvals table in <feature>.md and status in <feature>.phase-result.md
  gi_rec_file="$(gc_approval_file intake "$gi_feature")"
  gi_story_id="$(python3 - "$gi_artifact" "$gi_result" "$gi_rec_file" "$gi_feature" <<'PY'
import glob, json, os, re, sys

art_path, res_path, rec_path, slug = sys.argv[1:5]
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
    approver = rec.get("approver", "Sensei")
    approved_at = rec.get("approvedAt", "").split("T")[0]
except Exception:
    approver = "Sensei"
    approved_at = ""

txt = open(art_path, "r", encoding="utf-8").read()
row = f"| Intake | {art_path} | {approver} | Approved | {approved_at} |\n"
if "## Delivery approvals" in txt:
    if not re.search(r"\|\s*Intake\s*\|", txt, flags=re.I):
        txt = txt.rstrip() + "\n" + row
else:
    txt = txt.rstrip() + "\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|---|---|---|---|---|\n" + row
with open(art_path, "w", encoding="utf-8") as fh:
    fh.write(txt)

if os.path.isfile(res_path):
    rtxt = open(res_path, "r", encoding="utf-8").read()
    rtxt = re.sub(r"^(- status:\s*).*$", r"\g<1>approved", rtxt, flags=re.M)
    with open(res_path, "w", encoding="utf-8") as fh:
        fh.write(rtxt)

# Resolve story ID from artifact or milestone manifest
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

  # Create or attach the feature/<feature> worktree if not already on feature/<feature>
  gi_cur_br="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ "$gi_cur_br" != "feature/$gi_feature" ]; then
    gi_primary_root="$(pwd)"
    sh "$GC_HERE/feature-worktree.sh" "$gi_feature" || gc_refuse commit "feature-worktree.sh failed for '$gi_feature'"
    gi_wt="$(git worktree list --porcelain | awk -v want="branch refs/heads/feature/${gi_feature}" '
      /^worktree / { path = substr($0, 10) }
      $0 == want { print path; exit }
    ')"
    [ -n "$gi_wt" ] && [ -d "$gi_wt" ] || gc_refuse commit "could not locate worktree for feature/$gi_feature"
    # If any intake file remained in primary (e.g. tracked on a reopened intake), copy it into the worktree
    for gi_f in "$gi_artifact" "$gi_state" "$gi_result"; do
      if [ -f "$gi_primary_root/$gi_f" ]; then
        mkdir -p "$(dirname "$gi_wt/$gi_f")"
        cp "$gi_primary_root/$gi_f" "$gi_wt/$gi_f"
        if git -C "$gi_primary_root" ls-files --error-unmatch -- "$gi_f" >/dev/null 2>&1; then
          git -C "$gi_primary_root" checkout -q -- "$gi_f" || true
        else
          rm -f "$gi_primary_root/$gi_f" "$gi_primary_root/${gi_f}.lock"
        fi
      fi
    done
    rm -f "$gi_primary_root/${gi_state}.lock"
    cd "$gi_wt"
  fi

  gi_wt_br="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ "$gi_wt_br" = "feature/$gi_feature" ] \
    || gc_refuse commit "expected branch 'feature/$gi_feature' in worktree $(pwd), found '${gi_wt_br:-detached}'"

  gi_allowed="$gi_artifact $gi_state $gi_result"
  if ! gi_bad_staged="$(gc_outside_paths "$gi_allowed")"; then
    gc_refuse commit "the index in $(pwd) already holds paths outside intake ($gi_bad_staged); unstage them first"
  fi

  for gi_p in $gi_allowed; do
    if [ -e "$gi_p" ] || git ls-files --error-unmatch -- "$gi_p" >/dev/null 2>&1; then
      git add -- "$gi_p"
    fi
  done

  gc_scan_staged
  gi_msg="${gi_story_id}: intake approved"
  git commit -q -m "$gi_msg" || gc_refuse commit "git commit failed in worktree $(pwd)"
  gi_sha="$(git rev-parse --short HEAD)"
  gc_ok commit "intake for $gi_feature committed on feature/$gi_feature in $(pwd) as $gi_sha (\"$gi_msg\")"
  gi_rule commit approved.next "$gi_feature"; gi_approved_next="$gi_val"
  printf 'Next: Open worktree %s and run %s\n' "$(pwd)" "$gi_approved_next"
}

gi_steps() {
  [ $# -eq 0 ] || gi_usage
  gi_rule steps ready.next; gi_ready_next="$gi_val"
  gi_rule steps approved.next; gi_approved_next="$gi_val"
  G='sh .agents-v0/scripts/guard-intake.sh'
  cat <<EOF_STEPS
1. Run \`$G check <feature> [--tier trivial|emergency|standard|major] [--reopen]\`. It validates the \`<feature>\` slug, blocks \`p0-a*\` (redirecting to \`/v0-scaffold\`), routes \`trivial\` to \`/v0-triage\` and \`emergency\` to \`/v0-maintain\`, verifies the integration branch, checks Sensei's external \`onboard\`/\`plan\`/\`scaffold\` approvals when applicable, and ensures the story is not already released or approved. When it prints \`REFUSED\`, show its message and stop.
2. Run \`$G start <feature> [--reopen]\`. It verifies a clean working tree on the integration branch, seeds \`docs/agents-v0/requirements/<feature>.md\` if absent, and sets \`docs/agents-v0/requirements/<feature>.state.json\` to \`in_progress\`.
3. Read \`docs/agents-v0/lessons.md\` and launch the \`requirements-analyst\` subagent (skill: \`spec-intake\`) to author \`docs/agents-v0/requirements/<feature>.md\` (user story sentence, Gherkin \`AC-1\`..\`AC-8\` with \`Kind: happy | negative | edge\` and observable \`Then\` outcomes, security-review triggers, NFRs, regulations, and \`Open questions: none\`). It runs no shell commands and leaves \`Delivery approvals\` tables empty.
4. If \`docs/agents-v0/requirements/<feature>.helper-brief.md\` exists or the story requires \`## Proposed split\`, run \`$G block <feature> "<plain reason>"\` (which deduplicates helper briefs and records \`blocked\`). If a helper brief was written, launch \`explore-researcher\`, pass findings back to \`requirements-analyst\`, remove the brief, and resume; if split or blocked on user input, stop.
5. When \`docs/agents-v0/requirements/<feature>.md\` is complete, run \`$G ready <feature>\`. It validates the user story sentence, Gherkin acceptance criteria, negative/edge and security-trigger refusal rules, single-surface / vertical-slice budget, milestone size alignment, mandatory sections, and \`Open questions: none\`, writes \`docs/agents-v0/requirements/<feature>.phase-result.md\`, and sets state to \`awaiting_approval\`. When it prints \`REFUSED\`, fix what it names and run \`ready\` again.
6. Stop. Present the requirements summary to Sensei and wait for explicit approval. Next: $gi_ready_next. Never run approve yourself; the agent cannot approve this gate.
7. After Sensei runs approve in his own terminal and authorises branch \`feature/<feature>\` in its own turn (Do not run the script in the same turn as the Intake approval), run \`$G commit <feature>\`. It verifies Sensei's external approval record, appends the verified \`Intake\` row to \`Delivery approvals\`, creates or attaches the \`feature/<feature>\` worktree via \`feature-worktree.sh\`, moves untracked intake artifacts into the worktree, stages only the story's intake files, scans staged content for secrets, and commits \`"<story>: intake approved"\` on \`feature/<feature>\`. Then open the worktree and suggest: $gi_approved_next.
EOF_STEPS
}

cmd="${1:-}"
case "$cmd" in
  check) shift; gi_check "$@" ;;
  start) shift; gi_start "$@" ;;
  block) shift; gi_block "$@" ;;
  ready) shift; gi_ready "$@" ;;
  commit) shift; gi_commit "$@" ;;
  steps) shift; gi_steps "$@" ;;
  *) gi_usage ;;
esac
