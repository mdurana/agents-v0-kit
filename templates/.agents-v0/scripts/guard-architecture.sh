#!/bin/sh
# guard-architecture.sh: the steps of /v0-architecture and architecture's own rules (DA1 to DA8, DAA;
# kit-eval/proposals/sai-architecture-redo-design-20261105.md). Paths and prerequisites come from
# .agents-v0/gate-rules (the `architecture` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. DA1 builds `check`, DA2 `start`/`block`, DA3 `ready`, DA5 `commit`, DA6 `steps`.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-architecture.sh check
#        verify entry prerequisites (git worktree, kit installed, onboard approved if brownfield,
#        roadmap externally approved via gc_approval_ok roadmap, architecture not already approved).
#   sh .agents-v0/scripts/guard-architecture.sh start
#        begin or resume architecture: ensures architecture templates exist, sets status in_progress (DA2).
#   sh .agents-v0/scripts/guard-architecture.sh block "<plain reason>" [--next "<next step>"]
#        record blocked state and reason (DA2).
#   sh .agents-v0/scripts/guard-architecture.sh ready
#        verifies architecture pack completeness, Pattern ADR with Pack: <id>, and zero Open findings
#        in architecture-review.md, writes architecture.phase-result.md, sets awaiting_approval (DA3).
#   sh .agents-v0/scripts/guard-architecture.sh commit
#        verifies Sensei approval record, promotes ADR to Accepted, writes Approved row, runs
#        activate-stack-pack.sh, stages architecture paths, secret-scans, commits, tags (DA5).
#   sh .agents-v0/scripts/guard-architecture.sh steps
#        prints the step list for /v0-architecture command prose (DA6).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GA_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GA_HERE/guard-common.sh" ] || {
  printf 'REFUSED architecture: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GA_HERE"
  exit 1
}
GC_HERE="$GA_HERE"
GUARD_COMMON_LIB=1
. "$GA_HERE/guard-common.sh"

# ga_rule <step> <key>: set ga_val to the architecture rule <key> from gate-rules, or refuse <step> (fail closed).
ga_rule() {
  ga_val="$(gc_rule architecture "$2")" \
    || gc_refuse "$1" "gate-rules has no 'architecture $2' rule; reinstall the kit (install.sh --update)"
}

ga_load() {
  gc_to_root "$1"
  ga_rule "$1" state; ga_state="$ga_val"
  ga_rule "$1" phase; ga_phase="$ga_val"
  ga_rule "$1" feature; ga_feature="$ga_val"
  ga_rule "$1" artifact; ga_artifact="$ga_val"
}

# ga_is_brownfield: returns 0 if tracked application code exists (FA7)
ga_is_brownfield() {
  ga_code_files="$(git ls-files 2>/dev/null | grep -vE '^(\.agents-v0|\.cursor|\.agents|docs|trash|\.git|README\.md|LICENSE|CHANGELOG\.md|\.gitignore|\.cursorignore|\.gitlab|\.gitlab-ci\.yml|\.editorconfig|AGENTS\.md)' | head -n 1 || true)"
  [ -n "$ga_code_files" ]
}

ga_check_prereqs() {
  ga_step="$1"
  ga_reqs="$2"
  ga_rule "$ga_step" approved.next; ga_approved_next="$ga_val"

  for ga_req in $ga_reqs; do
    case "$ga_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$ga_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$ga_step" "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif ga_is_brownfield; then
          gc_refuse "$ga_step" "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      roadmap-approved)
        [ -f "$ga_state" ] || gc_refuse "$ga_step" "no program state ($ga_state); complete /v0-roadmap first"
        case " $(gc_state_get "$ga_state" approvedPhases | tr -d '[]",') " in
          *" roadmap "*) ;;
          *) gc_refuse "$ga_step" "roadmap is not in approvedPhases in $ga_state; complete /v0-roadmap first" ;;
        esac
        if ! ga_rm_ok="$(gc_approval_ok roadmap)"; then
          gc_refuse "$ga_step" "external roadmap approval record missing or mismatched ($ga_rm_ok); complete /v0-roadmap and have Sensei approve it first"
        fi
        ;;
      not-approved)
        if [ -f "$ga_state" ]; then
          case " $(gc_state_get "$ga_state" approvedPhases | tr -d '[]",') " in
            *" $ga_phase "*) gc_refuse "$ga_step" "architecture is already approved; suggest $ga_approved_next" ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$ga_state" ]; then
          [ "$(gc_state_get "$ga_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$ga_step" "architecture is awaiting Sensei's approval; wait for it, do not start again"
        fi
        ;;
      *) gc_refuse "$ga_step" "gate-rules names an unknown prerequisite '$ga_req'; reinstall the kit" ;;
    esac
  done
}

ga_check() {
  [ $# -eq 0 ] || ga_usage
  ga_load check
  ga_rule check check.requires; ga_requires="$ga_val"
  ga_check_prereqs check "$ga_requires"

  gc_ok check "prerequisites satisfied for /v0-architecture"
  printf 'Next: Start architecture with: sh .agents-v0/scripts/guard-architecture.sh start\n'
}

ga_start() {
  [ $# -eq 0 ] || ga_usage
  ga_load start
  ga_rule start start.requires; ga_requires="$ga_val"
  ga_check_prereqs start "$ga_requires"

  mkdir -p docs/agents-v0/adr docs/agents-v0/design/system/components docs/agents-v0/diagrams/sequences
  if [ ! -f "$ga_artifact" ]; then
    printf '# Architecture\n\n## C4 Context\n\n## C4 Container\n\n## Data flow\n\n## Data models\n\n### Conceptual\n\n### Logical\n\n### Physical\n\n## State machine\n\n## Failure domains and degradation\n\n## MVP and future state\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n' > "$ga_artifact"
  fi
  if [ ! -f docs/agents-v0/network.md ]; then
    printf '# Network & Topology\n\n## Target topology\n' > docs/agents-v0/network.md
  fi

  ga_rule start start.next; ga_next="$ga_val"
  ga_rule start start.status; ga_status="$ga_val"

  gc_state_set "$ga_state" "$ga_feature" "$ga_artifact" "activePhase=$ga_phase" \
    "activeStatus=$ga_status" "blockedReason=" "nextStep=$ga_next" || exit 1
  gc_ok start "architecture state is $(gc_state_get "$ga_state" activeStatus) ($ga_state)"
  printf 'Next: %s\n' "$ga_next"
}

ga_block() {
  [ $# -ge 1 ] && [ -n "$1" ] || ga_usage
  ga_reason="$1"; shift
  ga_next=""
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --next ] && [ -n "$2" ] || ga_usage
    ga_next="$2"
  fi
  ga_load block
  if [ -z "$ga_next" ]; then ga_rule block block.next; ga_next="$ga_val"; fi
  ga_rule block block.status; ga_status="$ga_val"
  gc_state_set "$ga_state" "$ga_feature" "$ga_artifact" "activePhase=$ga_phase" \
    "activeStatus=$ga_status" "blockedReason=$ga_reason" "nextStep=$ga_next" || exit 1
  gc_ok block "architecture state is $(gc_state_get "$ga_state" activeStatus): $ga_reason"
  printf 'Next: %s\n' "$ga_next"
}

ga_ready() {
  [ $# -eq 0 ] || ga_usage
  ga_load ready
  ga_rule ready ready.requires; ga_requires="$ga_val"
  for ga_req in $ga_requires; do
    case "$ga_req" in
      in-progress)
        ga_cur="$(gc_state_get "$ga_state" activeStatus)"
        [ "$ga_cur" = in_progress ] \
          || gc_refuse ready "architecture is not in progress (state: ${ga_cur:-none}); run start first" ;;
      *) gc_refuse ready "gate-rules names an unknown prerequisite '$ga_req'; reinstall the kit" ;;
    esac
  done

  [ -f "$ga_artifact" ] || gc_refuse ready "architecture artifact '$ga_artifact' does not exist; run start first"

  ga_ready_out="$(python3 - "$ga_artifact" <<'PY'
import datetime, glob, os, re, sys

arch_path = sys.argv[1]

def refuse(msg):
    print(f"REFUSED ready: {msg}")
    sys.exit(1)

if not os.path.isfile(arch_path):
    refuse(f"missing {arch_path}")

arch_text = open(arch_path, "r", encoding="utf-8").read()
arch_clean = re.sub(r"<!--.*?-->", "", arch_text, flags=re.DOTALL)

# 1. Check mandatory sections in architecture.md
req_arch_sections = [
    "C4 Context",
    "C4 Container",
    "Data flow",
    "Data models",
    "State machine",
    "Failure domains and degradation",
    "MVP and future state",
]

sections = {}
cur_sec = None
cur_lines = []
for line in arch_clean.splitlines():
    m = re.match(r"^##\s+(.+)$", line)
    if m:
        if cur_sec:
            sections[cur_sec] = "\n".join(cur_lines).strip()
        cur_sec = m.group(1).strip()
        cur_lines = []
    elif cur_sec:
        cur_lines.append(line)
if cur_sec:
    sections[cur_sec] = "\n".join(cur_lines).strip()

missing_sec = []
for req in req_arch_sections:
    matched = next((k for k in sections if k.lower() == req.lower()), None)
    if not matched or not sections[matched]:
        missing_sec.append(req)
if missing_sec:
    refuse(f"missing or empty section(s) in {arch_path}: {', '.join(missing_sec)}")

if "placeholder[" in arch_clean:
    refuse(f"unresolved diagram placeholder in {arch_path}")

# 2. Check network.md
net_path = "docs/agents-v0/network.md"
if not os.path.isfile(net_path):
    refuse(f"missing {net_path}")
net_clean = re.sub(r"<!--.*?-->", "", open(net_path, "r", encoding="utf-8").read(), flags=re.DOTALL)
if not re.search(r"^##\s+Target topology\b", net_clean, re.I | re.M):
    refuse(f"{net_path} missing '## Target topology' section")

# 3. Check Pattern ADR with Pack: <id>
adr_files = sorted(
    f for f in glob.glob("docs/agents-v0/adr/*.md")
    if not os.path.basename(f).startswith("_") and not os.path.basename(f).startswith("0000-")
)
if not adr_files:
    refuse("no pattern ADR found under docs/agents-v0/adr/ (expected docs/agents-v0/adr/<NN>-<slug>.md)")

pack_id = None
pattern_adr = None
for adr in adr_files:
    txt = re.sub(r"<!--.*?-->", "", open(adr, "r", encoding="utf-8").read(), flags=re.DOTALL)
    m = re.search(r"^\s*Pack:\s*([a-z][a-z0-9_-]*)\s*$", txt, re.M)
    if m:
        pack_id = m.group(1).strip()
        pattern_adr = adr
        break

if not pattern_adr or not pack_id:
    refuse("no pattern ADR under docs/agents-v0/adr/ declares 'Pack: <id>'")

# 4. Check required design/system files
sys_files = [
    "docs/agents-v0/design/system/context-map.md",
    "docs/agents-v0/design/system/nfr-slo.md",
    "docs/agents-v0/design/system/threat-model.md",
    "docs/agents-v0/design/system/ops-readiness.md",
    "docs/agents-v0/design/system/arc-record.md",
]
for sf in sys_files:
    if not os.path.isfile(sf):
        refuse(f"missing required architecture pack file {sf}")
    stxt = re.sub(r"<!--.*?-->", "", open(sf, "r", encoding="utf-8").read(), flags=re.DOTALL).strip()
    if not stxt:
        refuse(f"architecture pack file {sf} is empty")
    # Check for angle-bracket template placeholders outside Delivery approvals
    body_before_approvals = re.split(r"^##\s+Delivery approvals\b", stxt, flags=re.I | re.M)[0]
    pm = re.search(r"<(?!/?(?:br|sub|sup)\b)[^>\n]+>", body_before_approvals)
    if pm:
        refuse(f"unresolved placeholder {pm.group(0)!r} in {sf}")
    km = re.search(r"\b(TBD|TODO|FIXME|XXX)\b", body_before_approvals)
    if km:
        refuse(f"unresolved keyword placeholder {km.group(0)!r} in {sf}")

# Check placeholders in architecture.md target sections
for req in req_arch_sections:
    matched = next((k for k in sections if k.lower() == req.lower()), req)
    sec_txt = sections.get(matched, "")
    pm = re.search(r"<(?!/?(?:br|sub|sup)\b)[^>\n]+>", sec_txt)
    if pm:
        refuse(f"unresolved placeholder {pm.group(0)!r} in {arch_path} section '{req}'")
    km = re.search(r"\b(TBD|TODO|FIXME|XXX)\b", sec_txt)
    if km:
        refuse(f"unresolved keyword placeholder {km.group(0)!r} in {arch_path} section '{req}'")

# 5. Check architecture-review.md (FA3)
rev_path = "docs/agents-v0/design/system/architecture-review.md"
if not os.path.isfile(rev_path):
    refuse(f"missing {rev_path}; launch design-reviewer on the architecture pack first")
rev_text = open(rev_path, "r", encoding="utf-8").read()
if not re.search(r"^\s*agent:\s*design-reviewer\b", rev_text, re.I | re.M):
    refuse(f"{rev_path} must start with 'agent: design-reviewer'")

open_findings = []
for line in rev_text.splitlines():
    if not line.strip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) >= 5 and cells[0].lower() not in ("#", "---") and not re.match(r"^-+$", cells[0]):
        status_cell = cells[-1].lower()
        if status_cell == "open":
            open_findings.append(cells[0])

if open_findings:
    refuse(f"{rev_path} has {len(open_findings)} Open finding(s) ({', '.join(open_findings)}); resolve or disposition all findings before ready")

# 6. Write docs/agents-v0/architecture.phase-result.md
phase_res_path = "docs/agents-v0/architecture.phase-result.md"
now_ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
with open(phase_res_path, "w", encoding="utf-8") as rf:
    rf.write("# Architecture Phase Result\n\n")
    rf.write(f"- Artifact: {arch_path}\n")
    rf.write(f"- Pattern ADR: {pattern_adr} (Pack: {pack_id})\n")
    rf.write(f"- Review: {rev_path} (0 Open findings)\n")
    rf.write(f"- Prepared at: {now_ts}\n")
    rf.write("- Status: awaiting_approval\n")

print(f"OK ready: architecture pack verified (ADR: {pattern_adr}, Pack: {pack_id}, 0 Open findings; {phase_res_path})")
PY
)" || {
    printf '%s\n' "$ga_ready_out"
    exit 1
  }

  printf '%s\n' "$ga_ready_out"
  ga_rule ready ready.next; ga_next="$ga_val"
  ga_rule ready ready.status; ga_status="$ga_val"
  gc_state_set "$ga_state" "$ga_feature" "$ga_artifact" "activePhase=$ga_phase" \
    "activeStatus=$ga_status" "blockedReason=" "nextStep=$ga_next" || exit 1
  printf 'Next: %s\n' "$ga_next"
}

ga_commit() {
  [ $# -eq 0 ] || ga_usage
  ga_load commit

  # 1. Check state approved and Sensei approval record matches (DA5, FA1)
  case " $(gc_state_get "$ga_state" approvedPhases | tr -d '[]",') " in
    *" $ga_phase "*) ;;
    *) gc_refuse commit "architecture is not approved in $ga_state; Sensei runs approve in his own terminal first" ;;
  esac

  ga_ok_out="$(gc_approval_ok architecture)" || {
    printf '%s\n' "$ga_ok_out"
    gc_refuse commit "no approval record from Sensei matches this architecture; Sensei runs approve in his own terminal"
  }
  printf '%s\n' "$ga_ok_out"

  [ -f "$ga_artifact" ] || gc_refuse commit "architecture artifact '$ga_artifact' not found"

  # 2. Extract Pack: <id>, promote Pattern ADR to Accepted, update (Proposed) labels, and append Delivery approvals row (FA5)
  ga_rec_file="$(gc_approval_file architecture)"
  ga_pack_id="$(python3 - "$ga_artifact" "$ga_rec_file" <<'PY'
import glob, json, os, re, sys

arch_path, rec_path = sys.argv[1:3]
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
    approver = rec.get("approver", "Sensei")
    approved_at = rec.get("approvedAt", "").split("T")[0]
except Exception:
    approver = "Sensei"
    approved_at = ""

adr_files = sorted(
    f for f in glob.glob("docs/agents-v0/adr/*.md")
    if not os.path.basename(f).startswith("_") and not os.path.basename(f).startswith("0000-")
)
pack_id = ""
pattern_adr = ""
for adr in adr_files:
    txt = open(adr, "r", encoding="utf-8").read()
    clean = re.sub(r"<!--.*?-->", "", txt, flags=re.DOTALL)
    m = re.search(r"^\s*Pack:\s*([a-z][a-z0-9_-]*)\s*$", clean, re.M)
    if m:
        pack_id = m.group(1).strip()
        pattern_adr = adr
        # Promote Status: Proposed -> Accepted and set Deciders / Date
        new_txt = re.sub(
            r"^(\s*-\s*\*\*Status:\*\*)\s*Proposed\b.*$",
            r"\1 Accepted",
            txt,
            flags=re.M | re.I,
        )
        new_txt = re.sub(
            r"^(\s*-\s*\*\*Deciders:\*\*)\s*(?:<[^>]+>|TBD|TODO)?.*$",
            f"\\1 {approver}",
            new_txt,
            flags=re.M | re.I,
        )
        if approved_at:
            new_txt = re.sub(
                r"^(\s*-\s*\*\*Date:\*\*)\s*(?:YYYY-MM-DD|<[^>]+>)\s*$",
                f"\\1 {approved_at}",
                new_txt,
                flags=re.M | re.I,
            )
        if new_txt != txt:
            with open(adr, "w", encoding="utf-8") as f:
                f.write(new_txt)
        break

# Update (Proposed) labels in component plans and architecture-review.md
for comp in glob.glob("docs/agents-v0/design/system/components/*.md") + ["docs/agents-v0/design/system/architecture-review.md"]:
    if os.path.isfile(comp):
        ctxt = open(comp, "r", encoding="utf-8").read()
        cnew = ctxt.replace("(Proposed)", "(Accepted)")
        if cnew != ctxt:
            with open(comp, "w", encoding="utf-8") as f:
                f.write(cnew)

# Append architecture row to Delivery approvals in architecture.md
text = open(arch_path, "r", encoding="utf-8").read()
if not re.search(r"\|\s*architecture\s*\|", text, re.I):
    pack_paths = [
        arch_path,
        "docs/agents-v0/network.md",
    ]
    if pattern_adr:
        pack_paths.append(pattern_adr)
    for sf in [
        "docs/agents-v0/design/system/context-map.md",
        "docs/agents-v0/design/system/nfr-slo.md",
        "docs/agents-v0/design/system/threat-model.md",
        "docs/agents-v0/design/system/ops-readiness.md",
        "docs/agents-v0/design/system/arc-record.md",
        "docs/agents-v0/design/system/architecture-review.md",
    ]:
        if os.path.isfile(sf):
            pack_paths.append(sf)
    artifacts_cell = ", ".join(pack_paths)
    row = f"| architecture | {artifacts_cell} | {approver} | Approved | {approved_at} |\n"
    if "## Delivery approvals" in text:
        lines = text.splitlines(keepends=True)
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
        with open(arch_path, "w", encoding="utf-8") as f:
            f.writelines(out_lines)
    else:
        with open(arch_path, "a", encoding="utf-8") as f:
            f.write(f"\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n{row}")

print(pack_id)
PY
)" || gc_refuse commit "failed to promote pattern ADR and record Delivery approvals row"

  # 3. Bind stack pack via activate-stack-pack.sh if available and pack_id is present (T5)
  if [ -n "$ga_pack_id" ] && [ -f .agents-v0/scripts/activate-stack-pack.sh ] && [ -f docs/agents-v0/project-profile.md ]; then
    ga_act_rc=0
    ga_act_out="$(sh .agents-v0/scripts/activate-stack-pack.sh "$ga_pack_id" 2>&1)" || ga_act_rc=$?
    if [ "$ga_act_rc" = 2 ]; then
      gc_refuse commit "activate-stack-pack.sh refused to replace existing Pack in docs/agents-v0/project-profile.md ($ga_act_out)"
    elif [ "$ga_act_rc" != 0 ]; then
      gc_refuse commit "activate-stack-pack.sh $ga_pack_id failed (exit $ga_act_rc): $ga_act_out"
    fi
  fi

  # 4. Stage architecture commit paths, secret scan, commit, and tag (FA2, DA5)
  gc_commit_tag architecture
  ga_rule commit approved.next
  printf 'Next: %s\n' "$ga_val"
}

ga_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-architecture.sh check | start | block "<plain reason>" [--next "<next step>"] | ready | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || ga_usage
ga_cmd="$1"; shift
case "$ga_cmd" in
  check) ga_check "$@" ;;
  start) ga_start "$@" ;;
  block) ga_block "$@" ;;
  ready) ga_ready "$@" ;;
  commit) ga_commit "$@" ;;
  -h|--help) sed -n '2,24p' "$GA_HERE/guard-architecture.sh" ;;
  *) ga_usage ;;
esac
