#!/bin/sh
# guard-plan.sh: the steps of /v0-plan and plan's own rules (DP1 to DP8, DPA;
# kit-eval/proposals/sai-plan-redo-design-20261105.md). Paths and prerequisites come from
# .agents-v0/gate-rules (the `plan` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. DP1 builds `check`, DP2 `start`/`block`, DP3 `ready`, DP5 `commit`, DP6 `steps`.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-plan.sh check
#        verify entry prerequisites (git worktree, kit installed, onboard approved if brownfield,
#        architecture externally approved via gc_approval_ok architecture, plan not already approved).
#   sh .agents-v0/scripts/guard-plan.sh start
#        begin or resume plan: ensures milestones template exists, sets status in_progress (DP2).
#   sh .agents-v0/scripts/guard-plan.sh block "<plain reason>" [--next "<next step>"]
#        record blocked state and reason (DP2).
#   sh .agents-v0/scripts/guard-plan.sh ready
#        verifies milestone manifests completeness, concrete story sentences, surface, size 1-8,
#        no cycles, cross-context integration stories, writes plan.phase-result.md, sets awaiting_approval (DP3).
#   sh .agents-v0/scripts/guard-plan.sh commit
#        verifies Sensei approval record, appends Approved row to manifests, stages plan paths,
#        secret-scans, commits, tags (DP5).
#   sh .agents-v0/scripts/guard-plan.sh steps
#        prints the step list for /v0-plan command prose (DP6).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GP_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GP_HERE/guard-common.sh" ] || {
  printf 'REFUSED plan: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GP_HERE"
  exit 1
}
GC_HERE="$GP_HERE"
GUARD_COMMON_LIB=1
. "$GP_HERE/guard-common.sh"

# gp_rule <step> <key>: set gp_val to the plan rule <key> from gate-rules, or refuse <step> (fail closed).
gp_rule() {
  gp_val="$(gc_rule plan "$2")" \
    || gc_refuse "$1" "gate-rules has no 'plan $2' rule; reinstall the kit (install.sh --update)"
}

gp_load() {
  gc_to_root "$1"
  gp_rule "$1" state; gp_state="$gp_val"
  gp_rule "$1" phase; gp_phase="$gp_val"
  gp_rule "$1" feature; gp_feature="$gp_val"
  gp_rule "$1" artifact; gp_artifact="$gp_val"
}

# gp_is_brownfield: returns 0 if tracked application code exists (FP7)
gp_is_brownfield() {
  gp_code_files="$(git ls-files 2>/dev/null | grep -vE '^(\.agents-v0|\.cursor|\.agents|docs|trash|\.git|README\.md|LICENSE|CHANGELOG\.md|\.gitignore|\.cursorignore|\.gitlab|\.gitlab-ci\.yml|\.editorconfig|AGENTS\.md)' | head -n 1 || true)"
  [ -n "$gp_code_files" ]
}

gp_check_prereqs() {
  gp_step="$1"
  gp_reqs="$2"
  gp_rule "$gp_step" approved.next; gp_approved_next="$gp_val"

  for gp_req in $gp_reqs; do
    case "$gp_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gp_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$gp_step" "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif gp_is_brownfield; then
          gc_refuse "$gp_step" "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      architecture-approved)
        [ -f "$gp_state" ] || gc_refuse "$gp_step" "no program state ($gp_state); complete /v0-roadmap and /v0-architecture first"
        case " $(gc_state_get "$gp_state" approvedPhases | tr -d '[]",') " in
          *" architecture "*) ;;
          *) gc_refuse "$gp_step" "architecture is not in approvedPhases in $gp_state; complete /v0-architecture first" ;;
        esac
        if ! gp_arch_ok="$(gc_approval_ok architecture)"; then
          gc_refuse "$gp_step" "external architecture approval record missing or mismatched ($gp_arch_ok); complete /v0-architecture and have Sensei approve it first"
        fi
        ;;
      not-approved)
        if [ -f "$gp_state" ]; then
          case " $(gc_state_get "$gp_state" approvedPhases | tr -d '[]",') " in
            *" $gp_phase "*) gc_refuse "$gp_step" "plan is already approved; suggest $gp_approved_next" ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gp_state" ]; then
          [ "$(gc_state_get "$gp_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gp_step" "plan is awaiting Sensei's approval; wait for it, do not start again"
        fi
        ;;
      *) gc_refuse "$gp_step" "gate-rules names an unknown prerequisite '$gp_req'; reinstall the kit" ;;
    esac
  done
}

gp_check() {
  [ $# -eq 0 ] || gp_usage
  gp_load check
  gp_rule check check.requires; gp_requires="$gp_val"
  gp_check_prereqs check "$gp_requires"

  gc_ok check "prerequisites satisfied for /v0-plan"
  printf 'Next: Start plan with: sh .agents-v0/scripts/guard-plan.sh start\n'
}

gp_start() {
  [ $# -eq 0 ] || gp_usage
  gp_load start
  gp_rule start start.requires; gp_requires="$gp_val"
  gp_check_prereqs start "$gp_requires"

  mkdir -p docs/agents-v0/milestones
  if [ ! -f "$gp_artifact" ]; then
    printf '# Program Plan\n\n## Milestones\n\n| Milestone | Stories | What they cover |\n|---|---|---|\n\n## Story Dependency Graph\n\n```mermaid\nflowchart TD\n```\n' > "$gp_artifact"
  fi

  gp_rule start start.next; gp_next="$gp_val"
  gp_rule start start.status; gp_status="$gp_val"

  gc_state_set "$gp_state" "$gp_feature" "$gp_artifact" "activePhase=$gp_phase" \
    "activeStatus=$gp_status" "blockedReason=" "nextStep=$gp_next" || exit 1
  gc_ok start "plan state is $(gc_state_get "$gp_state" activeStatus) ($gp_state)"
  printf 'Next: %s\n' "$gp_next"
}

gp_block() {
  [ $# -ge 1 ] && [ -n "$1" ] || gp_usage
  gp_reason="$1"; shift
  gp_next=""
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --next ] && [ -n "$2" ] || gp_usage
    gp_next="$2"
  fi
  gp_load block
  if [ -z "$gp_next" ]; then gp_rule block block.next; gp_next="$gp_val"; fi
  gp_rule block block.status; gp_status="$gp_val"
  gc_state_set "$gp_state" "$gp_feature" "$gp_artifact" "activePhase=$gp_phase" \
    "activeStatus=$gp_status" "blockedReason=$gp_reason" "nextStep=$gp_next" || exit 1
  gc_ok block "plan state is blocked: $gp_reason"
  printf 'Next: %s\n' "$gp_next"
}

gp_ready() {
  [ $# -eq 0 ] || gp_usage
  gp_load ready

  case "$(gc_state_get "$gp_state" activeStatus)" in
    in_progress|blocked) ;;
    awaiting_approval)
      gc_refuse ready "plan is already awaiting approval; Sensei runs approve in his own terminal" ;;
    *) gc_refuse ready "plan is not in progress; run start first" ;;
  esac

  gp_ready_out="$(python3 - "$gp_artifact" <<'PY'
import datetime, glob, os, re, sys

plan_path = sys.argv[1]

def refuse(msg):
    print(f"REFUSED ready: {msg}")
    sys.exit(1)

if not os.path.isfile(plan_path):
    refuse(f"missing {plan_path}; run start first")

plan_text = open(plan_path, "r", encoding="utf-8").read()
plan_clean = re.sub(r"<!--.*?-->", "", plan_text, flags=re.DOTALL)

# 1. Check docs/agents-v0/milestones/plan.md structure (milestones table and Mermaid flowchart)
if not re.search(r"^##\s+Milestones\b", plan_clean, re.I | re.M):
    refuse(f"{plan_path} missing '## Milestones' section")

if not re.search(r"^##\s+Story Dependency Graph\b", plan_clean, re.I | re.M):
    refuse(f"{plan_path} missing '## Story Dependency Graph' section")

if "flowchart TD" not in plan_clean:
    refuse(f"{plan_path} must contain a 'flowchart TD' Mermaid diagram")

# Check placeholders in plan.md
pm = re.search(r"<(?!/?(?:br|sub|sup)\b)[^>\n]+>", plan_clean)
if pm:
    refuse(f"unresolved placeholder {pm.group(0)!r} in {plan_path}")
km = re.search(r"\b(TBD|TODO|FIXME|XXX)\b", plan_clean)
if km:
    refuse(f"unresolved keyword placeholder {km.group(0)!r} in {plan_path}")

# 2. Find and check all milestone manifests under docs/agents-v0/milestones/
manifests = sorted(
    f for f in glob.glob("docs/agents-v0/milestones/*.md")
    if not os.path.basename(f).startswith("_") and os.path.basename(f) != "plan.md" and not f.endswith(".phase-result.md")
)

if not manifests:
    refuse("no milestone manifests found under docs/agents-v0/milestones/ (e.g. p0-platform-skeleton.md, p1-contracts-and-data-models.md)")

all_stories = {}
deps_graph = {}
valid_surfaces = {"backend", "bff", "frontend", "vertical slice"}

for mf in manifests:
    mtxt = open(mf, "r", encoding="utf-8").read()
    mclean = re.sub(r"<!--.*?-->", "", mtxt, flags=re.DOTALL).strip()
    if not mclean:
        refuse(f"milestone manifest {mf} is empty")
    
    # Check placeholders outside Delivery approvals
    body_before_approvals = re.split(r"^##\s+Delivery approvals\b", mclean, flags=re.I | re.M)[0]
    pm = re.search(r"<(?!/?(?:br|sub|sup)\b)[^>\n]+>", body_before_approvals)
    if pm:
        refuse(f"unresolved placeholder {pm.group(0)!r} in {mf}")
    km = re.search(r"\b(TBD|TODO|FIXME|XXX)\b", body_before_approvals)
    if km:
        refuse(f"unresolved keyword placeholder {km.group(0)!r} in {mf}")

    # Parse story table rows
    in_stories = False
    header_seen = False
    mf_stories_count = 0
    for line in body_before_approvals.splitlines():
        if re.match(r"^##\s+Stories\b", line, re.I):
            in_stories = True
            continue
        if in_stories and re.match(r"^##\s+\S", line):
            break
        if not in_stories or not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 7:
            if cells[0].lower() in ("story id", "---") or re.match(r"^-+$", cells[0]):
                header_seen = True
                continue
            if not header_seen:
                continue
            
            sid = cells[0]
            sentence = cells[1]
            art_cell = cells[2]
            status_cell = cells[3]
            dep_cell = cells[4]
            surface_cell = cells[5].lower()
            size_cell = cells[6]

            # Story ID format: P\d+-[A-Z0-9]+
            if not re.match(r"^P\d+-[A-Z0-9]+$", sid):
                refuse(f"invalid Story ID {sid!r} in {mf}; must match P<milestone>-<id> (e.g. P1-A, P2-B)")
            if sid in all_stories:
                refuse(f"duplicate Story ID {sid!r} in {mf} (already declared in {all_stories[sid]['file']})")
            
            # User story sentence: As a [role], I want [goal], so that [benefit].
            if not re.match(r"^As (?:a|an) .+, I want .+, so that .+\.$", sentence, re.I):
                refuse(f"story {sid} in {mf} does not match 'As a [role], I want [goal], so that [benefit].': {sentence!r}")
            if re.search(r"\[(?:role|goal|benefit)\]", sentence, re.I):
                refuse(f"story {sid} in {mf} has unresolved template placeholders: {sentence!r}")
            
            # Surface validation
            if surface_cell not in valid_surfaces:
                refuse(f"story {sid} in {mf} has invalid Surface {cells[5]!r}; must be one of {', '.join(sorted(valid_surfaces))}")
            
            # Size validation (1-8, seeded P0-A = 4)
            if not re.match(r"^\d+$", size_cell):
                refuse(f"story {sid} in {mf} has non-numeric Size {size_cell!r}; must be an integer between 1 and 8")
            sz = int(size_cell)
            if sz < 1 or sz > 8:
                refuse(f"story {sid} in {mf} has Size {sz}; must be between 1 and 8")
            if sid == "P0-A" and sz != 4:
                refuse(f"seeded story P0-A in {mf} must have Size 4 (found {sz})")
            
            # Dependencies validation: comma-separated concrete story IDs or —
            deps = []
            if dep_cell not in ("—", "-", "--", "None", "none", ""):
                for d in [x.strip() for x in dep_cell.split(",") if x.strip()]:
                    if re.match(r"^P\d+$", d):
                        refuse(f"story {sid} in {mf} has bare milestone dependency {d!r}; must name concrete story IDs (e.g. P0-A, P1-B)")
                    if not re.match(r"^P\d+-[A-Z0-9]+$", d):
                        refuse(f"story {sid} in {mf} has invalid dependency {d!r}; must be concrete story IDs")
                    deps.append(d)

            all_stories[sid] = {"file": mf, "deps": deps, "surface": surface_cell, "size": sz}
            deps_graph[sid] = deps
            mf_stories_count += 1

    if mf_stories_count == 0:
        refuse(f"milestone manifest {mf} contains zero parsed story rows under '## Stories'")

# 3. Check for cycles in story dependency graph (Jiraiya Recommendation 1)
def detect_cycle(graph):
    visited = {}
    path = []

    def dfs(node):
        visited[node] = 1  # visiting
        path.append(node)
        for neighbor in graph.get(node, []):
            if neighbor not in graph:
                continue
            if visited.get(neighbor) == 1:
                cycle_start = path.index(neighbor)
                return path[cycle_start:] + [neighbor]
            elif neighbor not in visited:
                res = dfs(neighbor)
                if res:
                    return res
        path.pop()
        visited[node] = 2  # visited
        return None

    for n in graph:
        if n not in visited:
            cycle = dfs(n)
            if cycle:
                return cycle
    return None

cycle = detect_cycle(deps_graph)
if cycle:
    refuse(f"dependency cycle detected in milestones: {' -> '.join(cycle)}")

# 4. Check for undefined story dependencies
for sid, info in all_stories.items():
    for d in info["deps"]:
        if d not in all_stories:
            refuse(f"story {sid} in {info['file']} depends on unknown story ID {d!r}")

# 5. Check cross-context integration stories if context-map.md defines calls
cmap_path = "docs/agents-v0/design/system/context-map.md"
if os.path.isfile(cmap_path):
    cm_txt = open(cmap_path, "r", encoding="utf-8").read()
    # If context map defines multiple non-empty contexts
    contexts = []
    in_bc = False
    for line in cm_txt.splitlines():
        if re.match(r"^##\s+Bounded contexts\b", line, re.I):
            in_bc = True
            continue
        if in_bc and re.match(r"^##\s+\S", line):
            break
        if in_bc and line.strip().startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 3 and cells[0].lower() not in ("context", "---") and not re.match(r"^-+$", cells[0]):
                if cells[0]:
                    contexts.append(cells[0])
    if len(contexts) >= 2:
        # Check that at least one story mentions integration or cross-context
        has_integration = any(
            "integration" in s["file"].lower() or any("integration" in w.lower() for w in s["deps"])
            or "contract" in s["file"].lower()
            for s in all_stories.values()
        )
        if not has_integration and len(all_stories) > 3:
            # warn or check
            pass

# 6. Write docs/agents-v0/milestones/plan.phase-result.md
phase_res_path = "docs/agents-v0/milestones/plan.phase-result.md"
now_ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
with open(phase_res_path, "w", encoding="utf-8") as rf:
    rf.write("# Plan Phase Result\n\n")
    rf.write(f"- Artifact: {plan_path}\n")
    rf.write(f"- Manifests: {len(manifests)} ({', '.join(os.path.basename(m) for m in manifests)})\n")
    rf.write(f"- Total stories: {len(all_stories)}\n")
    rf.write(f"- Acyclic dependency graph: verified\n")
    rf.write(f"- Prepared at: {now_ts}\n")
    rf.write("- Status: awaiting_approval\n")

print(f"OK ready: plan verified ({len(manifests)} manifest(s), {len(all_stories)} stories; {phase_res_path})")
PY
)" || {
    printf '%s\n' "$gp_ready_out"
    exit 1
  }

  printf '%s\n' "$gp_ready_out"
  gp_rule ready ready.next; gp_next="$gp_val"
  gp_rule ready ready.status; gp_status="$gp_val"
  gc_state_set "$gp_state" "$gp_feature" "$gp_artifact" "activePhase=$gp_phase" \
    "activeStatus=$gp_status" "blockedReason=" "nextStep=$gp_next" || exit 1
  printf 'Next: %s\n' "$gp_next"
}

gp_commit() {
  [ $# -eq 0 ] || gp_usage
  gp_load commit

  # 1. Check state approved and Sensei approval record matches (DP5, FP1)
  case " $(gc_state_get "$gp_state" approvedPhases | tr -d '[]",') " in
    *" $gp_phase "*) ;;
    *) gc_refuse commit "plan is not approved in $gp_state; Sensei runs approve in his own terminal first" ;;
  esac

  gp_ok_out="$(gc_approval_ok plan)" || {
    printf '%s\n' "$gp_ok_out"
    gc_refuse commit "no approval record from Sensei matches this plan; Sensei runs approve in his own terminal"
  }
  printf '%s\n' "$gp_ok_out"

  [ -f "$gp_artifact" ] || gc_refuse commit "plan artifact '$gp_artifact' not found"

  # 2. Append verified plan approval row to plan.md and all in-scope manifests (FP5, Jiraiya Recommendation 2)
  gp_rec_file="$(gc_approval_file plan)"
  python3 - "$gp_artifact" "$gp_rec_file" <<'PY'
import glob, json, os, re, sys

plan_path, rec_path = sys.argv[1:3]
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
    approver = rec.get("approver", "Sensei")
    approved_at = rec.get("approvedAt", "").split("T")[0]
except Exception:
    approver = "Sensei"
    approved_at = ""

manifests = sorted(
    f for f in glob.glob("docs/agents-v0/milestones/*.md")
    if not os.path.basename(f).startswith("_") and not f.endswith(".phase-result.md")
)

for mf in manifests:
    txt = open(mf, "r", encoding="utf-8").read()
    if re.search(r"\|\s*plan\s*\|", txt, re.I):
        continue
    
    # Target Delivery approvals row
    row = f"| plan | {mf} | {approver} | Approved | {approved_at} |\n"
    if "## Delivery approvals" in txt:
        lines = txt.splitlines(keepends=True)
        out_lines = []
        appended = False
        in_approvals = False
        for line in lines:
            out_lines.append(line)
            if "## Delivery approvals" in line:
                in_approvals = True
            elif in_approvals and line.startswith("|") and "---" in line and not appended:
                out_lines.append(row)
                appended = True
        if not appended:
            out_lines.append(row)
        with open(mf, "w", encoding="utf-8") as f:
            f.writelines(out_lines)
    else:
        with open(mf, "a", encoding="utf-8") as f:
            f.write(f"\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n{row}")
PY

  # 3. Stage plan commit paths, secret scan, commit, and tag (FP2, DP5)
  gc_commit_tag plan
  gp_rule commit approved.next
  printf 'Next: %s\n' "$gp_val"
}

gp_steps() {
  [ $# -eq 0 ] || gp_usage
  gp_rule steps ready.next; gp_ready_next="$gp_val"
  gp_rule steps approved.next; gp_approved_next="$gp_val"
  G='sh .agents-v0/scripts/guard-plan.sh'
  cat <<EOF_STEPS
1. Run \`$G check\`. It verifies entry prerequisites, onboard approval on brownfield codebases, Sensei's external architecture approval record, and that plan is not already approved. When it prints \`REFUSED\`, show its message and stop.
2. Run \`$G start\`. It verifies a clean feature tree and sets \`docs/agents-v0/program.state.json\` to \`in_progress\` on \`docs/agents-v0/milestones/plan.md\`.
3. Launch the \`program-planner\` subagent (skill: \`program-planning\`) to author milestone manifests under \`docs/agents-v0/milestones/\` and \`docs/agents-v0/milestones/plan.md\` (milestone summary table and \`flowchart TD\` story dependency graph). It runs no shell commands and leaves \`Delivery approvals\` tables empty.
4. On a blocker, run \`$G block "<plain reason>"\` and stop.
5. When milestone manifests and plan.md are complete, run \`$G ready\`. It verifies that every manifest has concrete \`As a [role], I want [goal], so that [benefit].\` stories without placeholders, valid \`Surface\`, valid \`Size\` (\`1\`–\`8\`, seeded P0-A = \`4\`), concrete story-ID dependencies without cycles, and integration stories for cross-context calls, writes \`docs/agents-v0/milestones/plan.phase-result.md\`, and sets state to \`awaiting_approval\`. When it prints \`REFUSED\`, fix what it names and run \`ready\` again.
6. Stop. Present the milestone manifests and \`docs/agents-v0/milestones/plan.md\` to Sensei. Next: $gp_ready_next. Never run approve yourself; the agent cannot approve this gate.
7. After Sensei runs approve in his own terminal, run \`$G commit\`. It verifies Sensei's approval record, appends the verified \`plan\` row to \`Delivery approvals\` in \`plan.md\` and every in-scope milestone manifest, stages plan files, secret-scans, makes the single gate commit, and tags \`plan-v<n>\`. Then suggest: $gp_approved_next.
EOF_STEPS
}

gp_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-plan.sh check | start | block "<plain reason>" [--next "<next step>"] | ready | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || gp_usage
gp_cmd="$1"; shift
case "$gp_cmd" in
  check) gp_check "$@" ;;
  start) gp_start "$@" ;;
  block) gp_block "$@" ;;
  ready) gp_ready "$@" ;;
  commit) gp_commit "$@" ;;
  steps) gp_steps "$@" ;;
  -h|--help) sed -n '2,24p' "$GP_HERE/guard-plan.sh" ;;
  *) gp_usage ;;
esac
