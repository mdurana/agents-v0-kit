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
  gc_refuse start "start not yet implemented (scheduled in DR3)"
}

gr_block() {
  gc_refuse block "block not yet implemented (scheduled in DR3)"
}

gr_ready() {
  gc_refuse ready "ready not yet implemented (scheduled in DR3)"
}

gr_commit() {
  gc_refuse commit "commit not yet implemented (scheduled in DR5)"
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
