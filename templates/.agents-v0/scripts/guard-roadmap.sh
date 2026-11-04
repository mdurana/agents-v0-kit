#!/bin/sh
# guard-roadmap.sh: the steps of /v0-roadmap and roadmap's own rules (DR1 to DR8, DRA;
# kit-eval/proposals/sai-roadmap-redo-design-20261105.md). Paths and prerequisites come from
# .agents-v0/gate-rules (the `roadmap` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. DR1 builds `check`, DR2 `validate`, DR3 `start`/`block`/`ready`, DR5 `commit`, DR6 `steps`.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-roadmap.sh check <discovery-path>
#        verify entry prerequisites (git worktree, kit installed, onboard approved if brownfield,
#        roadmap not already approved, discovery file exists).
#   sh .agents-v0/scripts/guard-roadmap.sh validate <discovery-path> [--refresh]
#        verify 6 mandatory sections without placeholders; compare sha256 on resume (DR2).
#   sh .agents-v0/scripts/guard-roadmap.sh start <discovery-path> [--refresh]
#        begin or resume roadmap: seeds roadmap/<program>.md, sets status in_progress (DR3).
#   sh .agents-v0/scripts/guard-roadmap.sh block "<plain reason>" [--next "<next step>"]
#        record blocked state and reason (DR3).
#   sh .agents-v0/scripts/guard-roadmap.sh ready <discovery-path>
#        verifies completeness, writes phase-result.md, sets awaiting_approval (DR3).
#   sh .agents-v0/scripts/guard-roadmap.sh commit
#        verifies Sensei approval record, writes Approved row, stages roadmap files, commits, tags (DR5).
#   sh .agents-v0/scripts/guard-roadmap.sh steps
#        prints the step list for /v0-roadmap command prose (DR6).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GR_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GR_HERE/guard-common.sh" ] || {
  printf 'REFUSED roadmap: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GR_HERE"
  exit 1
}
GC_HERE="$GR_HERE"
GUARD_COMMON_LIB=1
. "$GR_HERE/guard-common.sh"

# gr_rule <step> <key>: set gr_val to the roadmap rule <key> from gate-rules, or refuse <step> (fail closed).
gr_rule() {
  gr_val="$(gc_rule roadmap "$2")" \
    || gc_refuse "$1" "gate-rules has no 'roadmap $2' rule; reinstall the kit (install.sh --update)"
}

gr_load() {
  gc_to_root "$1"
  gr_rule "$1" state; gr_state="$gr_val"
  gr_rule "$1" phase; gr_phase="$gr_val"
  gr_rule "$1" feature; gr_feature="$gr_val"
  gr_rule "$1" artifact; gr_artifact_dir="$gr_val"
}

# gr_slug <discovery-path>: derive <program> slug from discovery path (T2)
gr_slug() {
  gr_base="$(basename "$1" .md)"
  printf '%s\n' "$gr_base" | sed -E 's/[-_]discovery$//'
}

# gr_artifact <discovery-path>: compute docs/agents-v0/roadmap/<program>.md
gr_artifact() {
  gr_slug_val="$(gr_slug "$1")"
  printf 'docs/agents-v0/roadmap/%s.md\n' "$gr_slug_val"
}

# gr_is_brownfield: returns 0 if tracked application code exists (F7)
gr_is_brownfield() {
  # If git has tracked files outside kit, doc, and config directories, it is brownfield
  gr_code_files="$(git ls-files 2>/dev/null | grep -vE '^(\.agents-v0|\.cursor|docs|trash|\.git|README\.md|LICENSE|\.gitignore|\.editorconfig)' | head -n 1 || true)"
  [ -n "$gr_code_files" ]
}

gr_check() {
  [ $# -ge 1 ] && [ -n "$1" ] || gc_refuse check "no discovery path given; run /v0-roadmap <discovery-path>"
  gr_disc="$1"
  gr_load check

  gr_rule check check.requires; gr_requires="$gr_val"
  gr_rule check approved.next; gr_approved_next="$gr_val"

  for gr_req in $gr_requires; do
    case "$gr_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse check "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        # Check onboard approval record and state (F7)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse check "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif gr_is_brownfield; then
          gc_refuse check "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      not-approved)
        if [ -f "$gr_state" ]; then
          case " $(gc_state_get "$gr_state" approvedPhases | tr -d '[]",') " in
            *" $gr_phase "*) gc_refuse check "roadmap is already approved; suggest $gr_approved_next" ;;
          esac
        fi
        ;;
      *) gc_refuse check "gate-rules names an unknown prerequisite '$gr_req'; reinstall the kit" ;;
    esac
  done

  [ -f "$gr_disc" ] || gc_refuse check "discovery file '$gr_disc' does not exist; check the path"

  gc_ok check "prerequisites satisfied for $gr_disc"
  printf 'Next: Validate the discovery file with: sh .agents-v0/scripts/guard-roadmap.sh validate %s\n' "$gr_disc"
}

gr_validate() {
  [ $# -ge 1 ] && [ -n "$1" ] || gc_refuse validate "no discovery path given; run /v0-roadmap <discovery-path>"
  gr_disc="$1"; shift
  gr_refresh=0
  for arg in "$@"; do
    case "$arg" in
      --refresh) gr_refresh=1 ;;
      *) gr_usage ;;
    esac
  done
  gr_load validate
  [ -f "$gr_disc" ] || gc_refuse validate "discovery file '$gr_disc' does not exist; check the path"

  gr_rule validate validate.sections; gr_sections="$gr_val"
  gr_art="$(gr_artifact "$gr_disc")"

  # Run Python validator for section completeness, placeholder checks, and hash comparison (DR2, F3, F5)
  gr_val_out="$(python3 - "$gr_disc" "$gr_sections" "$gr_art" "$gr_refresh" <<'PY'
import hashlib, os, re, sys

disc_path, sec_csv, art_path, refresh_str = sys.argv[1:5]
is_refresh = refresh_str == "1"
required_sections = [s.strip() for s in sec_csv.split(",") if s.strip()]

try:
    with open(disc_path, "r", encoding="utf-8") as f:
        content = f.read()
except Exception as exc:
    print(f"REFUSED validate: cannot read discovery file {disc_path}: {exc}")
    sys.exit(1)

# 1. Compute current sha256
cur_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()

# 2. Parse sections
found_sections = {}
current_sec = None
current_lines = []

for line in content.splitlines():
    m = re.match(r"^#{1,3}\s+(.+)$", line)
    if m:
        title = m.group(1).strip()
        if current_sec:
            found_sections[current_sec] = "\n".join(current_lines).strip()
        current_sec = title
        current_lines = []
    elif current_sec:
        current_lines.append(line)
if current_sec:
    found_sections[current_sec] = "\n".join(current_lines).strip()

# Check missing or empty sections
missing = []
for req in required_sections:
    matched = None
    for k in found_sections:
        if k.strip().lower() == req.lower():
            matched = k
            break
    if not matched or not found_sections[matched]:
        missing.append(req)

if missing:
    print(f"REFUSED validate: missing or empty section(s) in {disc_path}: {', '.join(missing)}")
    sys.exit(1)

# Check placeholders
placeholder_patterns = [
    (r"<[^>\n]+>", "angle-bracket placeholder"),
    (r"\[[^\]\n]+\](?!\()", "bracket placeholder"),
    (r"\b(TBD|TODO|FIXME|XXX|XX)\b", "keyword placeholder"),
    (r"_{2,}", "blank line placeholder"),
    (r"\?{2,}", "question mark placeholder"),
]

for pat, desc in placeholder_patterns:
    for req in required_sections:
        matched_title = next((k for k in found_sections if k.strip().lower() == req.lower()), req)
        text = found_sections.get(matched_title, "")
        m = re.search(pat, text)
        if m:
            print(f"REFUSED validate: unresolved {desc} {m.group(0)!r} in section '{req}'")
            sys.exit(1)

# 3. Hash integrity check on resume (F5)
if os.path.isfile(art_path):
    try:
        with open(art_path, "r", encoding="utf-8") as af:
            art_text = af.read()
        hm = re.search(r"sha256:\s*([0-9a-fA-F]{64})", art_text)
        if hm:
            recorded_hash = hm.group(1).lower()
            if recorded_hash != cur_hash and not is_refresh:
                print(f"REFUSED validate: discovery file has changed (current sha256: {cur_hash[:8]} vs recorded {recorded_hash[:8]}); pass --refresh to update roadmap")
                sys.exit(1)
    except Exception:
        pass

print(f"OK validate: discovery document '{disc_path}' is complete and valid (sha256: {cur_hash})")
PY
)" || {
    if [ -f "$gr_art" ] && [ -f "$gr_state" ]; then
      gr_fail_reason="$(printf '%s' "$gr_val_out" | sed 's/^REFUSED validate: //')"
      gc_state_set "$gr_state" "$gr_feature" "$gr_art" "activePhase=$gr_phase" \
        "activeStatus=blocked" "blockedReason=$gr_fail_reason" \
        "nextStep=Fix $disc_path, then run /v0-roadmap $disc_path" 2>/dev/null || true
    fi
    printf '%s\n' "$gr_val_out"
    exit 1
  }

  printf '%s\n' "$gr_val_out"
  printf 'Next: Run sh .agents-v0/scripts/guard-roadmap.sh start %s\n' "$gr_disc"
}

gr_start() {
  [ $# -ge 1 ] && [ -n "$1" ] || gc_refuse start "no discovery path given; run /v0-roadmap <discovery-path>"
  gr_disc="$1"; shift
  gr_refresh=0
  for arg in "$@"; do
    case "$arg" in
      --refresh) gr_refresh=1 ;;
      *) gr_usage ;;
    esac
  done
  gr_load start
  gr_rule start start.requires; gr_requires="$gr_val"
  gr_rule start approved.next; gr_approved_next="$gr_val"

  for gr_req in $gr_requires; do
    case "$gr_req" in
      git-work-tree) ;;
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse start "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse start "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif gr_is_brownfield; then
          gc_refuse start "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gr_state" ]; then
          [ "$(gc_state_get "$gr_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse start "roadmap is awaiting Sensei's approval; wait for it, do not start again"
        fi
        ;;
      *) gc_refuse start "gate-rules names an unknown prerequisite '$gr_req'; reinstall the kit" ;;
    esac
  done

  [ -f "$gr_disc" ] || gc_refuse start "discovery file '$gr_disc' does not exist; check the path"

  gr_art="$(gr_artifact "$gr_disc")"
  gr_slug_val="$(gr_slug "$gr_disc")"
  gr_rule start template; gr_template="$gr_val"

  # Seed roadmap document from template if missing or --refresh (DR3)
  if [ ! -f "$gr_art" ] || [ "$gr_refresh" = 1 ]; then
    mkdir -p "$(dirname "$gr_art")"
    if [ -f "$gr_template" ]; then
      cur_hash="$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$gr_disc")"
      sed -e "s|<program>|$gr_slug_val|g" \
          -e "s|<repo-relative path the user passed to /v0-roadmap>|$gr_disc|g" \
          -e "s|<sha256-hash>|$cur_hash|g" \
          "$gr_template" > "$gr_art"
    else
      gc_refuse start "roadmap template '$gr_template' is missing; reinstall the kit"
    fi
  fi

  gr_rule start start.next; gr_next="$gr_val"
  gr_rule start start.status; gr_status="$gr_val"

  gc_state_set "$gr_state" "$gr_feature" "$gr_art" "activePhase=$gr_phase" \
    "activeStatus=$gr_status" "blockedReason=" "nextStep=$gr_next" || exit 1
  gc_ok start "roadmap state is $(gc_state_get "$gr_state" activeStatus) ($gr_state)"
  printf 'Next: %s\n' "$gr_next"
}

gr_block() {
  [ $# -ge 1 ] && [ -n "$1" ] || gr_usage
  gr_reason="$1"; shift
  gr_next=""
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --next ] && [ -n "$2" ] || gr_usage
    gr_next="$2"
  fi
  gr_load block
  if [ -z "$gr_next" ]; then gr_rule block block.next; gr_next="$gr_val"; fi
  gr_rule block block.status; gr_status="$gr_val"
  gr_art="$(gc_state_get "$gr_state" artifact 2>/dev/null || true)"
  [ -n "$gr_art" ] || gr_art="docs/agents-v0/roadmap"
  gc_state_set "$gr_state" "$gr_feature" "$gr_art" "activePhase=$gr_phase" \
    "activeStatus=$gr_status" "blockedReason=$gr_reason" "nextStep=$gr_next" || exit 1
  gc_ok block "roadmap state is $(gc_state_get "$gr_state" activeStatus): $gr_reason"
  printf 'Next: %s\n' "$gr_next"
}

gr_ready() {
  [ $# -ge 1 ] && [ -n "$1" ] || gc_refuse ready "no discovery path given; run /v0-roadmap <discovery-path>"
  gr_disc="$1"
  gr_load ready
  gr_rule ready ready.requires; gr_requires="$gr_val"
  for gr_req in $gr_requires; do
    case "$gr_req" in
      in-progress)
        gr_cur="$(gc_state_get "$gr_state" activeStatus)"
        [ "$gr_cur" = in_progress ] \
          || gc_refuse ready "roadmap is not in progress (state: ${gr_cur:-none}); run start first" ;;
      *) gc_refuse ready "gate-rules names an unknown prerequisite '$gr_req'; reinstall the kit" ;;
    esac
  done

  gr_art="$(gr_artifact "$gr_disc")"
  [ -f "$gr_art" ] || gc_refuse ready "roadmap artifact '$gr_art' does not exist; run start first"
  [ -f "$gr_disc" ] || gc_refuse ready "discovery file '$gr_disc' does not exist; check the path"

  # Verify roadmap completeness & generate phase-result.md (DR3)
  gr_ready_out="$(python3 - "$gr_disc" "$gr_art" <<'PY'
import datetime, hashlib, os, re, sys

disc_path, art_path = sys.argv[1:3]

with open(disc_path, "r", encoding="utf-8") as df:
    disc_text = df.read()
cur_hash = hashlib.sha256(disc_text.encode("utf-8")).hexdigest()

with open(art_path, "r", encoding="utf-8") as af:
    art_text = af.read()

# 1. Check discovery line & hash
hm = re.search(r"Discovery:\s*([^\s]+)\s*\(sha256:\s*([0-9a-fA-F]{64})\)", art_text)
if not hm:
    print("REFUSED ready: roadmap missing 'Discovery: <path> (sha256: <hash>)' line")
    sys.exit(1)

rec_path, rec_hash = hm.group(1), hm.group(2).lower()
if rec_hash != cur_hash:
    print(f"REFUSED ready: discovery sha256 mismatch (current: {cur_hash[:8]} vs roadmap: {rec_hash[:8]})")
    sys.exit(1)

# 2. Check sections: Now, Next, Later, Out of scope
sections = {}
current_sec = None
current_lines = []
for line in art_text.splitlines():
    m = re.match(r"^##\s+(.+)$", line)
    if m:
        t = m.group(1).strip()
        if current_sec:
            sections[current_sec] = current_lines
        current_sec = t
        current_lines = []
    elif current_sec:
        current_lines.append(line)
if current_sec:
    sections[current_sec] = current_lines

for h in ["Now", "Next", "Later"]:
    if h not in sections:
        print(f"REFUSED ready: roadmap missing '## {h}' section")
        sys.exit(1)
    items = [l.strip() for l in sections[h] if l.strip().startswith("-") or l.strip().startswith("*")]
    if not items:
        print(f"REFUSED ready: '## {h}' has no bullet items")
        sys.exit(1)

# Check placeholders
placeholder_patterns = [
    (r"<[^>\n]+>", "angle-bracket placeholder"),
    (r"\[[^\]\n]+\](?!\()", "bracket placeholder"),
    (r"\b(TBD|TODO|FIXME|XXX|XX)\b", "keyword placeholder"),
    (r"_{2,}", "blank line placeholder"),
    (r"\?{2,}", "question mark placeholder"),
]

for pat, desc in placeholder_patterns:
    for h in ["Now", "Next", "Later", "Out of scope", "Problem", "Success metric", "Chosen option"]:
        lines = sections.get(h, [])
        text = "\n".join(lines)
        cleaned = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
        m = re.search(pat, cleaned)
        if m:
            print(f"REFUSED ready: unresolved {desc} {m.group(0)!r} in section '{h}'")
            sys.exit(1)

now_count = len([l for l in sections.get("Now", []) if l.strip().startswith(("-", "*"))])
next_count = len([l for l in sections.get("Next", []) if l.strip().startswith(("-", "*"))])
later_count = len([l for l in sections.get("Later", []) if l.strip().startswith(("-", "*"))])

# Write phase-result.md
phase_res_path = re.sub(r"\.md$", ".phase-result.md", art_path)
now_ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
with open(phase_res_path, "w", encoding="utf-8") as rf:
    rf.write(f"# Roadmap Phase Result: {os.path.basename(art_path)}\n\n")
    rf.write(f"- Discovery: {disc_path} (sha256: {cur_hash})\n")
    rf.write(f"- Now items: {now_count}\n")
    rf.write(f"- Next items: {next_count}\n")
    rf.write(f"- Later items: {later_count}\n")
    rf.write(f"- Prepared at: {now_ts}\n")
    rf.write(f"- Status: awaiting_approval\n")

print(f"OK ready: roadmap prepared ({now_count} Now, {next_count} Next, {later_count} Later; {phase_res_path})")
PY
)" || {
    printf '%s\n' "$gr_ready_out"
    exit 1
  }

  printf '%s\n' "$gr_ready_out"
  gr_rule ready ready.next; gr_next="$gr_val"
  gr_rule ready ready.status; gr_status="$gr_val"
  gc_state_set "$gr_state" "$gr_feature" "$gr_art" "activePhase=$gr_phase" \
    "activeStatus=$gr_status" "blockedReason=" "nextStep=$gr_next" || exit 1
  printf 'Next: %s\n' "$gr_next"
}

gr_commit() {
  [ $# -eq 0 ] || gr_usage
  gr_load commit

  # 1. Check state approved and Sensei approval record matches (DR5, F1)
  case " $(gc_state_get "$gr_state" approvedPhases | tr -d '[]",') " in
    *" $gr_phase "*) ;;
    *) gc_refuse commit "roadmap is not approved in $gr_state; Sensei runs approve in his own terminal first" ;;
  esac

  gr_ok_out="$(gc_approval_ok roadmap)" || {
    printf '%s\n' "$gr_ok_out"
    gc_refuse commit "no approval record from Sensei matches this roadmap; Sensei runs approve in his own terminal"
  }
  printf '%s\n' "$gr_ok_out"

  # 2. Append Delivery approvals row to roadmap/<program>.md from verified record (T5)
  gr_art="$(gc_state_get "$gr_state" artifact 2>/dev/null || true)"
  [ -n "$gr_art" ] && [ -f "$gr_art" ] || {
    gr_disc="$(find docs/product -type f -name "*discovery.md" 2>/dev/null | head -n 1 || true)"
    [ -n "$gr_disc" ] && gr_art="$(gr_artifact "$gr_disc")"
  }
  [ -f "$gr_art" ] || gc_refuse commit "roadmap artifact '$gr_art' not found"

  gr_rec_file="$(gc_approval_file roadmap)"
  python3 - "$gr_art" "$gr_rec_file" <<'PY'
import json, os, re, sys
art_path, rec_path = sys.argv[1:3]
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
    approver = rec.get("approver", "Sensei")
    approved_at = rec.get("approvedAt", "").split("T")[0]
except Exception:
    approver = "Sensei"
    approved_at = ""

with open(art_path, "r", encoding="utf-8") as f:
    text = f.read()

# Check if roadmap row already exists in Delivery approvals
if not re.search(r"\|\s*roadmap\s*\|", text):
    hm = re.search(r"Discovery:\s*([^\s]+)", text)
    disc = hm.group(1) if hm else ""
    artifacts_cell = f"{art_path}, {disc}" if disc else art_path
    row = f"| roadmap | {artifacts_cell} | {approver} | Approved | {approved_at} |\n"
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
        with open(art_path, "w", encoding="utf-8") as f:
            f.writelines(out_lines)
    else:
        with open(art_path, "a", encoding="utf-8") as f:
            f.write(f"\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n{row}")
PY

  # 3. Stage roadmap commit paths, secret scan, commit, and tag (F2, DR5)
  gc_commit_tag roadmap
  gr_rule commit approved.next
  printf 'Next: %s\n' "$gr_val"
}

gr_steps() {
  gc_refuse steps "steps not yet implemented (scheduled in DR6)"
}

gr_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-roadmap.sh check <discovery-path> | validate <discovery-path> [--refresh] | start <discovery-path> [--refresh] | block "<plain reason>" [--next "<next step>"] | ready <discovery-path> | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || gr_usage
gr_cmd="$1"; shift
case "$gr_cmd" in
  check) gr_check "$@" ;;
  validate) gr_validate "$@" ;;
  start) gr_start "$@" ;;
  block) gr_block "$@" ;;
  ready) gr_ready "$@" ;;
  commit) gr_commit "$@" ;;
  steps) gr_steps "$@" ;;
  -h|--help) sed -n '2,24p' "$GR_HERE/guard-roadmap.sh" ;;
  *) gr_usage ;;
esac
