#!/bin/sh
# test-onboard-flow.sh — tier 1 flow test for /v0-onboard on an installed copy (onboard fix JO-5 v1, with the
# JO-6 template cases and the JO-7 helper-brief cases). Design: jiraiya-onboard-fix-design-20261101.md rev 6
# (JO-5 :30 :37 :77 :91 :123 :128, JO-6 :39 :57, JO-7 :22 :38); test ids from
# jiraiya-onboard-test-cases-20261101.md: N14 N22 N36 N37 E21 SKO-10 SKO-11 (partial; see "Open" below).
# Offline, no agent. One git fixture with an installed copy (Yamato's tier 1 harness: the AGENTS_V0_* switch
# guard runs when the harness is sourced). The suite refuses to run (exit 2) unless check-installed-kit.sh
# prints HASH-OK for the fixture, so every case runs on the real installed scripts.
#   PR-n  prose parse (tier 1 part of N22): the `sh .agents-v0/scripts/...` steps in every installed copy of
#         the onboard command, skill and agent are read in order and compared with the step list below, and
#         each flag must exist in the named installed script. A copy with one step swapped or one flag
#         changed must fail the parse.
#   FL-n  the flow, steps 1 to 7 of the command, in order, on the fixture (the step 2 commands are taken
#         from the parsed prose).
#   BR-n  helper briefs in docs/agents-v0/onboarding/briefs/ (and its subfolders) and the archive folder
#         (JO-7; BR-10..13 are Iruka's 03:23 follow-up findings).
#   FL-9  the next phase (intake) refuses before the onboard gate commit and starts after it (JO-9).
#   TP-n  the minimal install seeds the templates the skill points to (JO-6, E21).
#   FL-8  the step 8 commit chain (JO-8): commit_chain, the staged-path check (N15), the planted FAKE secret
#         (N6), the clean commit plus tag, other dirty work listed and left out (N7).
# Open (not built yet, so not tested here): the gate_committed range re-scan (N40), the script-level resume refusal
# (JO-10), N27 (baseline output never committed; needs JO-8), the unattended run, and the tier 2 replay.
# Kit-only file: it is not installed into projects.
# shellcheck disable=SC2016 # backticks in the fixture docs are literal Markdown citations
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

SFS=".agents-v0/scripts/sync-feature-state.sh"
DOCS=".agents-v0/scripts/check-onboarding-docs.sh"
GC=".agents-v0/scripts/gate-checks.sh"
REP="docs/agents-v0/onboarding/report.md"
ST="docs/agents-v0/onboarding/state.json"
BR="docs/agents-v0/onboarding/briefs"
AR="docs/agents-v0/onboarding/briefs/archive"

out_has() { has "$1" "$T1_TMP/out.txt" "$2"; }
is_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi; }
# rc <dir> <command...>: run it and print only its exit code (output in $T1_TMP/out.txt)
rc() { d_="$1"; shift; if (cd "$d_" && "$@") > "$T1_TMP/out.txt" 2>&1; then echo 0; else echo $?; fi; }
state_val() { python3 -c 'import json,sys
try: v = json.load(open(sys.argv[1])).get(sys.argv[2])
except Exception: v = None
print("" if v is None else (" ".join(str(x) for x in v) if isinstance(v, list) else v))' "$1/$ST" "$2"; }

# prose_cmds <file>: every `sh .agents-v0/scripts/...` code span in the file, in order, one per line
prose_cmds() {
  python3 -c 'import re,sys
t = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r"`(sh \.agents-v0/scripts/[^`]+)`", t):
    print(" ".join(m.group(1).split()))' "$1"
}
# prose_check <repo> <prose file> <expected step list>: 0 when the prose steps equal the list and every flag
# exists in the installed script it is passed to; otherwise prints PROSE-MISMATCH lines and returns 1
prose_check() {
  pr_="$1"; pf_="$2"; pe_="$3"; po_="$T1_TMP/prose.txt"; bad_=0
  prose_cmds "$pf_" > "$po_" || return 1
  if ! cmp -s "$po_" "$pe_"; then
    printf 'PROSE-MISMATCH: %s: the step list differs from the flow test\n' "$pf_"; diff "$pe_" "$po_" || :; bad_=1
  fi
  while IFS= read -r pc_; do
    set -f
    # shellcheck disable=SC2086 # split the step into words on purpose (no globbing: set -f)
    set -- $pc_
    set +f
    ps_="$2"; shift 2
    if [ ! -f "$pr_/$ps_" ]; then printf 'PROSE-MISMATCH: %s names %s, which is not installed\n' "$pf_" "$ps_"; bad_=1; continue; fi
    for pa_ in "$@"; do
      case "$pa_" in
        --*) grep -Eq -- "(^|[^a-z-])$pa_([^a-z-]|\$)" "$pr_/$ps_" ||
               { printf 'PROSE-MISMATCH: %s passes %s to %s, which does not take it\n' "$pf_" "$pa_" "$ps_"; bad_=1; } ;;
      esac
    done
  done < "$po_"
  return "$bad_"
}

# ---------------------------------------------------------------------------------------------- fixture
r="$(t1_repo flow --commit)"
mkdir -p "$r/src" && printf 'def main():\n    return 1\n# end\n' > "$r/src/app.py"
G "$r" add -- src/app.py && G "$r" commit -qm "fixture: source"
t1_install "$r" || { printf 'test-onboard-flow: install.sh failed\n' >&2; exit 2; }
if ! t1_hash_ok "$r"; then
  cat "$T1_TMP/hash.txt" >&2
  printf 'test-onboard-flow: refusing to run: check-installed-kit.sh did not print HASH-OK for the fixture\n' >&2
  exit 2
fi
pass "FL-0 harness guard: no AGENTS_V0_* switch set, installed copy is HASH-OK"
G "$r" add -- . && G "$r" commit -qm "fixture: installed kit"
base="$(git -C "$r" rev-parse --short HEAD)"

# ------------------------------------------------------------------------------- PR: prose parse (N22)
ONB="$T1_TMP/steps-onboard.txt"; SKL="$T1_TMP/steps-skill.txt"; DOC="$T1_TMP/steps-documenter.txt"
cat > "$ONB" <<'EOS'
sh .agents-v0/scripts/sync-feature-state.sh --active-phase onboard --status in_progress docs/agents-v0/onboarding/report.md
sh .agents-v0/scripts/audit-brownfield-baseline.sh
sh .agents-v0/scripts/generate-repo-map.sh
sh .agents-v0/scripts/collect-dependency-graphs.sh
sh .agents-v0/scripts/discover-codebase.sh
sh .agents-v0/scripts/activate-stack-pack.sh --detect
sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md
sh .agents-v0/scripts/check-onboarding-docs.sh --gate
sh .agents-v0/scripts/sync-feature-state.sh --active-phase onboard --status awaiting_approval docs/agents-v0/onboarding/report.md
sh .agents-v0/scripts/sync-feature-state.sh --approve onboard docs/agents-v0/onboarding/report.md
sh .agents-v0/scripts/gate-checks.sh commit_chain
sh .agents-v0/scripts/gate-checks.sh staged_secret_scan
EOS
cat > "$SKL" <<'EOS'
sh .agents-v0/scripts/audit-brownfield-baseline.sh
sh .agents-v0/scripts/generate-repo-map.sh
sh .agents-v0/scripts/collect-dependency-graphs.sh
sh .agents-v0/scripts/discover-codebase.sh
sh .agents-v0/scripts/activate-stack-pack.sh --detect
sh .agents-v0/scripts/check-onboarding-docs.sh --gate
sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md --active-phase onboard --status awaiting_approval
sh .agents-v0/scripts/sync-feature-state.sh --approve onboard docs/agents-v0/onboarding/report.md
EOS
cat > "$DOC" <<'EOS'
sh .agents-v0/scripts/sync-feature-state.sh --active-phase onboard --status awaiting_approval docs/agents-v0/onboarding/report.md
sh .agents-v0/scripts/sync-feature-state.sh --approve onboard docs/agents-v0/onboarding/report.md
EOS
for pair in ".cursor/commands/v0-onboard.md:$ONB" ".agents/commands/v0-onboard.md:$ONB" \
            ".agents/skills/v0-onboard/SKILL.md:$ONB" ".cursor/skills/onboard-discovery/SKILL.md:$SKL" \
            ".agents/skills/onboard-discovery/SKILL.md:$SKL" ".cursor/agents/codebase-documenter.md:$DOC" \
            ".agents/agents/codebase-documenter.md:$DOC"; do
  pf="${pair%%:*}"; pe="${pair#*:}"
  if [ ! -f "$r/$pf" ]; then fail "PR-1 installed prose $pf exists"; continue; fi
  if prose_check "$r" "$r/$pf" "$pe" > "$T1_TMP/out.txt" 2>&1; then pass "PR-1 $pf: steps and flags match the installed scripts"
  else cat "$T1_TMP/out.txt" >&2; fail "PR-1 $pf: steps and flags match the installed scripts"; fi
done
# N22: a copy with two steps swapped, and a copy with one flag changed, must both fail the parse
m="$T1_TMP/mut"; mkdir -p "$m"
sed -e 's#generate-repo-map\.sh#@@SWAP@@#' -e 's#`sh \.agents-v0/scripts/discover-codebase\.sh`#`sh .agents-v0/scripts/generate-repo-map.sh`#' \
    -e 's#@@SWAP@@#discover-codebase.sh#' "$r/.cursor/commands/v0-onboard.md" > "$m/swapped.md"
if prose_check "$r" "$m/swapped.md" "$ONB" > "$T1_TMP/out.txt" 2>&1; then fail "PR-2 N22 swapped steps fail the parse"
else pass "PR-2 N22 swapped steps fail the parse"; fi
out_has "PR-2 N22 the mismatch is named" "PROSE-MISMATCH: $m/swapped.md: the step list differs"
sed 's#check-onboarding-docs\.sh --gate#check-onboarding-docs.sh --gated#' "$r/.cursor/commands/v0-onboard.md" > "$m/flag.md"
sed 's#check-onboarding-docs\.sh --gate#check-onboarding-docs.sh --gated#' "$ONB" > "$m/flag-steps.txt"
if prose_check "$r" "$m/flag.md" "$ONB" > "$T1_TMP/out.txt" 2>&1; then fail "PR-3 N22 a changed flag fails the parse"
else pass "PR-3 N22 a changed flag fails the parse"; fi
# even when the step list is edited to match, the script check still catches the flag
if prose_check "$r" "$m/flag.md" "$m/flag-steps.txt" > "$T1_TMP/out.txt" 2>&1; then fail "PR-4 N22 an unknown flag fails against the script"
else pass "PR-4 N22 an unknown flag fails against the script"; fi
out_has "PR-4 N22 the flag is named" "passes --gated to .agents-v0/scripts/check-onboarding-docs.sh"
# JO-7: the prose names the briefs folder and the archive folder the scripts use
for pf in .cursor/commands/v0-onboard.md .agents/skills/v0-onboard/SKILL.md .cursor/skills/onboard-discovery/SKILL.md \
          .agents/skills/onboard-discovery/SKILL.md .cursor/agents/codebase-documenter.md .agents/agents/codebase-documenter.md; do
  has "PR-5 JO-7 $pf names $BR/" "$r/$pf" "$BR/"
done
has "PR-6 JO-7 v0-onboard step 4 archives a used brief" "$r/.cursor/commands/v0-onboard.md" "move that brief to \`$AR/\`"
lacks "PR-6 JO-7 v0-onboard no longer deletes the brief" "$r/.cursor/commands/v0-onboard.md" "delete that brief"
# JO-6: the skill points at the installed manifest template, not the kit path
for pf in .cursor/skills/onboard-discovery/SKILL.md .agents/skills/onboard-discovery/SKILL.md; do
  has "PR-7 JO-6 E21 $pf names the installed manifest template" "$r/$pf" "docs/agents-v0/_workspace.manifest.template.json"
  lacks "PR-7 JO-6 E21 $pf no longer names the kit path" "$r/$pf" "templates/docs/agents-v0/workspace.manifest.json"
done

# ------------------------------------------------------------------------- TP: templates (JO-6, E21)
for f in docs/agents-v0/adr/_template.md docs/agents-v0/diagrams/sequences/_template.md \
         docs/agents-v0/discovery/_template.md docs/agents-v0/_workspace.manifest.template.json; do
  if [ -f "$r/$f" ]; then pass "TP-1 E21 minimal install seeds $f"; else fail "TP-1 E21 minimal install seeds $f"; fi
done
if [ -e "$r/docs/agents-v0/workspace.manifest.json" ]; then fail "TP-2 the example manifest is not installed at the live path orchestrator reads"
else pass "TP-2 the example manifest is not installed at the live path orchestrator reads"; fi
if [ -f "$r/docs/agents-v0/_workspace.manifest.template.json" ] &&
   cmp -s "$KIT/templates/docs/agents-v0/workspace.manifest.json" "$r/docs/agents-v0/_workspace.manifest.template.json"; then
  pass "TP-3 the manifest template is the kit example"; else fail "TP-3 the manifest template is the kit example"; fi
# the default docs check scans docs/agents-v0/diagrams/ (it needs report.md, so run it on that folder here)
expect_pass "TP-4 the docs check passes on diagrams/ with the seeded sequence template" "$r" sh "$DOCS" docs/agents-v0/diagrams
# --update on an install that predates JO-6 (the four files parked away) seeds only the missing ones, and an
# edited template survives
u="$(t1_repo upd --commit)"
t1_install "$u" || fail "TP-5 install.sh into upd"
mkdir -p "$T1_TMP/parked"
for f in diagrams/sequences/_template.md discovery/_template.md _workspace.manifest.template.json; do
  [ -f "$u/docs/agents-v0/$f" ] && mv "$u/docs/agents-v0/$f" "$T1_TMP/parked/" || :
done
mkdir -p "$u/docs/agents-v0/adr"
printf '# ADR template (edited by the team)\n' > "$u/docs/agents-v0/adr/_template.md"
G "$u" add -- . && G "$u" commit -qm "fixture: pre-JO-6 install, edited adr template"
# KIT_VALIDATING=1 skips the nested validate-kit run (this suite itself runs under validate-kit).
if KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" --update --quick "$u" > "$T1_TMP/out.txt" 2>&1; then pass "TP-5 E21 --update runs"
else cat "$T1_TMP/out.txt" >&2; fail "TP-5 E21 --update runs"; fi
for f in diagrams/sequences/_template.md discovery/_template.md _workspace.manifest.template.json; do
  if [ -f "$u/docs/agents-v0/$f" ]; then pass "TP-6 E21 --update seeds the missing $f"; else fail "TP-6 E21 --update seeds the missing $f"; fi
done
is_eq "TP-7 E21 --update leaves the edited adr template unchanged" "$(cat "$u/docs/agents-v0/adr/_template.md")" "# ADR template (edited by the team)"

# --------------------------------------------------------------------------- FL: the flow, steps 1-7
# Resume/step 1: report from the installed template, phase in_progress
cp "$r/docs/agents-v0/onboarding/_report.template.md" "$r/$REP"
expect_pass "FL-1 sync --status in_progress" "$r" sh "$SFS" --active-phase onboard --status in_progress "$REP"
is_eq "FL-1 state is in_progress" "$(state_val "$r" activeStatus)" "in_progress"
# Step 2: the discovery commands exactly as the prose gives them
sed -n '2,6p' "$ONB" > "$T1_TMP/step2.txt"
while IFS= read -r c; do
  set -f
  # shellcheck disable=SC2086 # split the step into words on purpose (no globbing: set -f)
  set -- $c
  set +f
  got="$(rc "$r" "$@")"
  case "$2" in
    */audit-brownfield-baseline.sh) case "$got" in 0|2) pass "FL-2 $2 ran (exit $got; a red baseline is recorded, not a stop)" ;; *) fail "FL-2 $2 (exit $got)" ;; esac ;;
    */activate-stack-pack.sh) is_eq "FL-2 $* exits 3 with no pack marker" "$got" 3; out_has "FL-2 activate-stack-pack asks for the pack id" "no pack marker" ;;
    *) is_eq "FL-2 $2 exits 0" "$got" 0 ;;
  esac
done < "$T1_TMP/step2.txt"
if [ -f "$r/docs/agents-v0/discovery/endpoints.txt" ]; then pass "FL-2 discovery wrote docs/agents-v0/discovery/endpoints.txt"
else fail "FL-2 discovery wrote docs/agents-v0/discovery/endpoints.txt"; fi

# Step 4 helpers (JO-7): briefs live in briefs/, used ones go to briefs/archive/
mkdir -p "$r/$BR"
printf 'helper: explore-researcher\noutputs: docs/agents-v0/onboarding/modules/app.md\nask: list every caller of main in src/\nscope: src/\n' > "$r/$BR/app.helper-brief.md"
expect_pass "BR-1 first sync with a brief in briefs/ passes" "$r" sh "$SFS" "$REP"
n_h="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("helperBriefHashes") or []))' "$r/$ST")"
is_eq "BR-1 the brief ask is recorded" "$n_h" 1
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-2 N14 a second sync while the brief is still in briefs/ exits 2" "$got" 2
out_has "BR-2 N14 the leftover brief is named" "$BR/app.helper-brief.md"
out_has "BR-2 N14 the archive folder is named" "$AR/"
expect_fail "BR-3 --gate fails while a brief is left in briefs/" "$r" sh "$DOCS" --gate
out_has "BR-3 the --gate failure names the brief" "$BR/app.helper-brief.md"
out_has "BR-3 the --gate failure names the archive folder" "$AR/"
mkdir -p "$r/$AR" && mv "$r/$BR/app.helper-brief.md" "$r/$AR/app.helper-brief.md"
expect_pass "BR-4 N36 an archived brief does not trip sync" "$r" sh "$SFS" "$REP"
cp "$r/$AR/app.helper-brief.md" "$r/$BR/app.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-5 N36 the same ask back in briefs/ still exits 2" "$got" 2
mv "$r/$BR/app.helper-brief.md" "$T1_TMP/parked/app.helper-brief.md.again"
printf 'outputs: docs/agents-v0/onboarding/modules/app.md\nscope: src/\n' > "$r/$BR/bad.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-6 N37 a brief with no helper:/ask: lines fails closed (exit 2)" "$got" 2
out_has "BR-6 N37 the malformed brief is named" "$BR/bad.helper-brief.md"
mv "$r/$BR/bad.helper-brief.md" "$T1_TMP/parked/bad.helper-brief.md"
printf 'helper: explore-researcher\nask: \377\376 not utf-8\n' > "$r/$BR/bin.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-7 N37 an unreadable (not UTF-8) brief fails closed (exit 2)" "$got" 2
out_has "BR-7 N37 the unreadable brief is named" "$BR/bin.helper-brief.md"
mv "$r/$BR/bin.helper-brief.md" "$T1_TMP/parked/bin.helper-brief.md"
mkdir -p "$r/$BR/dir.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-8 N37 a brief path that cannot be read (a folder) fails closed (exit 2)" "$got" 2
out_has "BR-8 N37 that path is named" "$BR/dir.helper-brief.md"
mv "$r/$BR/dir.helper-brief.md" "$T1_TMP/parked/dir.helper-brief.md"
# a legacy brief straight under onboarding/ is still read by sync, and named by --gate
printf 'helper: explore-researcher\nask: legacy ask\n' > "$r/docs/agents-v0/onboarding/old.helper-brief.md"
expect_pass "BR-9 a legacy brief in onboarding/ is still read by sync" "$r" sh "$SFS" "$REP"
expect_fail "BR-9 --gate fails on a legacy brief left in onboarding/" "$r" sh "$DOCS" --gate
out_has "BR-9 the --gate failure names the legacy brief" "docs/agents-v0/onboarding/old.helper-brief.md"
mv "$r/docs/agents-v0/onboarding/old.helper-brief.md" "$r/$AR/old.helper-brief.md"
# JO-7 follow-up (Iruka 03:23): a real ask: line is required; one folder key for both onboarding locations;
# briefs in subfolders of briefs/ are read; --gate fails on any brief under onboarding/ outside the archive
printf 'helper: explore-researcher\noutputs: docs/agents-v0/onboarding/modules/app.md\n' > "$r/$BR/noask.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-10 N37 a brief with helper: and outputs: but no ask: fails closed (exit 2)" "$got" 2
out_has "BR-10 N37 the brief with no ask: is named" "$BR/noask.helper-brief.md"
mv "$r/$BR/noask.helper-brief.md" "$T1_TMP/parked/noask.helper-brief.md"
printf 'helper: explore-researcher\nask: moved ask\n' > "$r/docs/agents-v0/onboarding/mv.helper-brief.md"
expect_pass "BR-11 a legacy brief in onboarding/ is synced" "$r" sh "$SFS" "$REP"
mv "$r/docs/agents-v0/onboarding/mv.helper-brief.md" "$r/$BR/mv.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-11 N14 the same brief moved from onboarding/ to briefs/ still exits 2" "$got" 2
out_has "BR-11 N14 the moved brief is named" "$BR/mv.helper-brief.md"
mv "$r/$BR/mv.helper-brief.md" "$r/$AR/mv.helper-brief.md"
mkdir -p "$r/$BR/sub"
printf 'helper: explore-researcher\nask: nested ask\n' > "$r/$BR/sub/n.helper-brief.md"
expect_pass "BR-12 the first sync with a brief in briefs/sub/ passes" "$r" sh "$SFS" "$REP"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-12 N14 a second sync with the brief still in briefs/sub/ exits 2" "$got" 2
out_has "BR-12 N14 the nested brief is named by sync" "$BR/sub/n.helper-brief.md"
expect_fail "BR-12 --gate fails while a brief waits in briefs/sub/" "$r" sh "$DOCS" --gate
out_has "BR-12 the --gate failure names the nested brief" "$BR/sub/n.helper-brief.md"
printf 'outputs: x.md\n' > "$r/$BR/sub/bad.helper-brief.md"
got="$(rc "$r" sh "$SFS" "$REP")"
is_eq "BR-12 N37 a malformed brief in briefs/sub/ fails closed (exit 2)" "$got" 2
out_has "BR-12 N37 the malformed nested brief is named" "$BR/sub/bad.helper-brief.md"
mkdir -p "$r/$AR/sub"
mv "$r/$BR/sub/n.helper-brief.md" "$r/$AR/sub/n.helper-brief.md"
mv "$r/$BR/sub/bad.helper-brief.md" "$r/$AR/sub/bad.helper-brief.md"
expect_pass "BR-12 N36 briefs in briefs/archive/sub/ (one malformed) do not trip sync" "$r" sh "$SFS" "$REP"
mkdir -p "$r/docs/agents-v0/onboarding/modules"
printf 'helper: explore-researcher\nask: stray ask\n' > "$r/docs/agents-v0/onboarding/modules/stray.helper-brief.md"
expect_fail "BR-13 --gate fails on a brief elsewhere under onboarding/ (modules/)" "$r" sh "$DOCS" --gate
out_has "BR-13 the --gate failure names the stray brief" "docs/agents-v0/onboarding/modules/stray.helper-brief.md"
out_has "BR-13 the --gate failure names the archive folder" "$AR/"
mv "$r/docs/agents-v0/onboarding/modules/stray.helper-brief.md" "$r/$AR/stray.helper-brief.md"

# Step 5: the gate documents (the codebase-documenter's work, written by the fixture)
expect_fail "FL-5 --gate fails before the gate documents exist" "$r" sh "$DOCS" --gate
d="$r/docs/agents-v0"
mkdir -p "$d/onboarding/modules" "$d/diagrams/sequences" "$d/adr" "$d/discovery" "$d/design/system"
cat > "$r/$REP" <<EOR
# Onboarding report

commit: $base

## Summary

A one-module fixture repo; the entry point is \`src/app.py:1\`.

## Modules

| Module | Document | Owner | Confidence |
|--------|----------|-------|------------|
| app | docs/agents-v0/onboarding/modules/app.md | team | high |

## Flows

- docs/agents-v0/diagrams/sequences/app.md

## Delivery approvals

| Phase | Evidence | Approver | Decision | Date |
|-------|----------|----------|----------|------|
EOR
printf '# Module: app\n\ncommit: %s\nRoot: src\n\n## Purpose\n\nReturns one (`src/app.py:1-2`).\n' "$base" > "$d/onboarding/modules/app.md"
printf '# Sequence: app\n\n```mermaid\nsequenceDiagram\n  User->>App: run (`src/app.py:1`)\n```\n' > "$d/diagrams/sequences/app.md"
printf '# ADR 0000: inherited decisions\n\nStatus: Accepted (inherited)\n\nPython, one module (`src/app.py:1`).\n' > "$d/adr/0000-inherited-decisions.md"
printf '# Architecture\n\nOne module, no services.\n' > "$d/architecture.md"
printf '# Network\n\nNo network calls.\n' > "$d/network.md"
printf '# Context map\n\n## Bounded contexts\n\n| Context | Owns | Integrations |\n|---------|------|--------------|\n| app | everything | none |\n' > "$d/design/system/context-map.md"
expect_pass "FL-5 --gate passes with the documents and only archived briefs" "$r" sh "$DOCS" --gate
expect_pass "FL-5 the default docs check passes too (briefs are not scanned as documents)" "$r" sh "$DOCS"
# Step 6: phase result from the installed template, then awaiting_approval
sed -e "s#^commit: .*#commit: $base#" -e 's#^<!-- TEMPLATE:.*-->$#Filled in by the flow test.#' \
    "$d/onboarding/_phase-result.template.md" > "$d/onboarding/phase-result.md"
expect_pass "FL-6 sync --status awaiting_approval" "$r" sh "$SFS" --active-phase onboard --status awaiting_approval "$REP"
is_eq "FL-6 state is awaiting_approval" "$(state_val "$r" activeStatus)" "awaiting_approval"
# Step 7: approval
expect_pass "FL-7 sync --approve onboard" "$r" sh "$SFS" --approve onboard "$REP"
case " $(state_val "$r" approvedPhases) " in *" onboard "*) pass "FL-7 onboard is in approvedPhases" ;; *) fail "FL-7 onboard is in approvedPhases" ;; esac
# Step 9 before the gate commit (JO-9): the next phase refuses while onboard is approved but not committed
mkdir -p "$T1_TMP/fl9" && printf '# orders\n' > "$T1_TMP/fl9/orders.md"
fl9_req="docs/agents-v0/requirements/orders.md"
expect_fail "FL-9 prereq_approved intake refuses before the onboard gate commit" "$r" sh "$GC" prereq_approved intake
out_has "FL-9 names the uncommitted approval" "the onboard approval in $ST is not committed"
# Step 8 (JO-8): the onboard gate commit chain, printed by the helper and run unchanged
fl8_head="$(git -C "$r" rev-parse HEAD)"
expect_pass "FL-8 commit_chain prints the chain" "$r" sh "$GC" commit_chain
fl8_chain="$(cat "$T1_TMP/out.txt")"
out_has "FL-8 the chain stages only the onboard paths, lock files excluded" "git add --all -- docs/agents-v0 README.md ':(exclude,glob)**/*.lock' && "
out_has "FL-8 the chain scans after staging and before the commit" "&& sh .agents-v0/scripts/gate-checks.sh staged_secret_scan && git commit -F .git/agents-v0-onboard-commit-msg.txt && "
out_has "FL-8 the chain tags the first onboard gate onboard-v1" "git tag -a onboard-v1 -m \"onboard approved\""
lacks "FL-8 the chain never sweeps with git add -A" "$T1_TMP/out.txt" "add -A"
lacks "FL-8 the chain never amends" "$T1_TMP/out.txt" "--amend"
fl8_add() { G "$r" add --all -- docs/agents-v0 README.md ':(exclude,glob)**/*.lock'; }
# N7: a stray untracked file outside docs/agents-v0 is not staged. N15: a pre-staged file outside the list
# refuses before the scan, and nothing is unstaged.
printf 'stray\n' > "$r/src/stray.txt"
printf 'def one():\n    return 1  # edited\n' > "$r/src/app.py"; G "$r" add -- src/app.py
fl8_add
expect_fail "FL-8 N15 staged_secret_scan refuses a pre-staged path outside the onboard paths" "$r" sh "$GC" staged_secret_scan
out_has "FL-8 N15 the outside path is named" "REFUSED staged_secret_scan: the index holds paths outside gate-rules onboard_commit_paths (docs/agents-v0 README.md) or lock files: src/app.py"
lacks "FL-8 N15 the refusal comes before the scan" "$T1_TMP/out.txt" "SECRET-SCAN"
is_eq "FL-8 N15 nothing was unstaged" "$(git -C "$r" diff --cached --name-only -- src/app.py)" "src/app.py"
G "$r" restore --staged -- src/app.py
# N6: a planted FAKE secret (AKIA plus 16 capitals with the FAKE marker, made fresh here, not in the
# allow-list) under docs/agents-v0 blocks the commit; the scanner's output passes through and never shows it
fl8_key="AKIA$(printf 'FAKE%.0s' 1 2 3 4)"
printf 'aws_access_key_id = %s\n' "$fl8_key" > "$r/docs/agents-v0/onboarding/fake-note.md"
fl8_add
expect_fail "FL-8 N6 staged_secret_scan blocks the planted fake secret" "$r" sh "$GC" staged_secret_scan
out_has "FL-8 N6 the scanner's hit passes through" "HIT docs/agents-v0/onboarding/fake-note.md:1 content.aws-key-id lineSha256="
out_has "FL-8 N6 the scanner's verdict passes through" "SECRET-SCAN REFUSED hits=1"
out_has "FL-8 N6 the helper refuses on the scanner's exit" "REFUSED staged_secret_scan: secret_scan.py exited 1"
lacks "FL-8 N6 the secret is never printed" "$T1_TMP/out.txt" "$fl8_key"
is_eq "FL-8 N6 no commit was made" "$(git -C "$r" rev-parse HEAD)" "$fl8_head"
if [ -f "$r/.agents-v0/secret-allowlist.json" ] && grep -q AKIAFAKE "$r/.agents-v0/secret-allowlist.json"; then
  fail "FL-8 N6 the fake key is not in the allow-list"; else pass "FL-8 N6 the fake key is not in the allow-list"; fi
mv "$r/docs/agents-v0/onboarding/fake-note.md" "$T1_TMP/fl8-fake-note.md"
fl8_add
# the clean case: the printed chain runs unchanged and makes one commit plus the tag
expect_pass "FL-8 the printed chain commits the clean onboard gate" "$r" env GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com sh -c "$fl8_chain"
out_has "FL-8 the scan is clean" "SECRET-SCAN clean"
out_has "FL-8 the clean scan passes" "OK staged_secret_scan: the index holds only onboard paths and no secret"
out_has "FL-8 N7 other dirty files are listed, not swept in" "other uncommitted files, not in this commit: src/app.py src/stray.txt"
is_eq "FL-8 one new commit on top of the old HEAD (no amend)" "$(git -C "$r" rev-parse HEAD^)" "$fl8_head"
is_eq "FL-8 the commit message" "$(git -C "$r" log -1 --format=%s)" "onboarding: onboard approved"
is_eq "FL-8 the tag is on the gate commit" "$(git -C "$r" rev-parse 'onboard-v1^{commit}')" "$(git -C "$r" rev-parse HEAD)"
outside="$(git -C "$r" show --name-only --format= HEAD | grep -v '^docs/agents-v0/' || :)"
is_eq "FL-8 the gate commit holds only docs/agents-v0 files" "$outside" ""
is_eq "FL-8 N7 the stray file stays untracked" "$(git -C "$r" status --porcelain -- src/stray.txt)" "?? src/stray.txt"
# gate_committed (check-gate-commit.sh, unchanged) still wants a clean tree: park the user's other work
mv "$r/src/stray.txt" "$T1_TMP/fl8-stray.txt"; G "$r" checkout -q -- src/app.py
expect_pass "FL-8 gate_committed onboard passes after the gate commit" "$r" sh "$GC" gate_committed onboard
# Step 9 after the gate commit (JO-9): the next phase starts
expect_pass "FL-9 prereq_approved intake passes after the onboard gate commit" "$r" sh "$GC" prereq_approved intake
mkdir -p "$r/docs/agents-v0/requirements" && cp "$T1_TMP/fl9/orders.md" "$r/$fl9_req"
expect_pass "FL-9 sync --active-phase intake in_progress starts after the onboard gate commit" "$r" sh "$SFS" --active-phase intake --status in_progress "$fl9_req"

t1_done test-onboard-flow
