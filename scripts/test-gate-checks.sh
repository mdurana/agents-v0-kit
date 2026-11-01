#!/bin/sh
# test-gate-checks.sh — tier 1 tests for .agents-v0/scripts/gate-checks.sh and the sync wiring that calls it
# (onboard fix; design jiraiya-onboard-fix-design-20261101.md rev 6, line 149: "a new test-gate-checks.sh").
# Offline, no agent. Every case runs on an installed copy (install.sh into a temp git repo, Yamato's tier 1
# harness). Each helper check has a pass case and a refusal case with its exact message.
# Test ids: jiraiya-onboard-test-cases-20261101.md (N1, N2, N3, N4, E7, E22, H1/H2 partial) plus AE-n / GC-n
# helper cases and DG-n cases for `check-onboarding-docs.sh --gate` (JO-3/JO-4).
# Kit-only file: it is not installed into projects.
# shellcheck disable=SC2016 # backticks in the fixture docs are literal Markdown citations
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

GC=".agents-v0/scripts/gate-checks.sh"
SFS=".agents-v0/scripts/sync-feature-state.sh"
REP="docs/agents-v0/onboarding/report.md"
ST="docs/agents-v0/onboarding/state.json"
PR="docs/agents-v0/onboarding/phase-result.md"

# out_has <desc> <fixed string>: the last expect_* output holds the string
out_has() { has "$1" "$T1_TMP/out.txt" "$2"; }
# state_val <repo> <key>: one value of the onboarding state.json ("" when missing)
state_val() { python3 -c 'import json,sys
try: v = json.load(open(sys.argv[1])).get(sys.argv[2])
except Exception: v = None
print("" if v is None else (" ".join(v) if isinstance(v, list) else v))' "$1/$ST" "$2"; }
# q <dir> <command...>: a setup step; its output goes to $T1_TMP/setup.txt and a failure never stops the suite
# (a later assertion catches it)
q() { d_="$1"; shift; (cd "$d_" && "$@") > "$T1_TMP/setup.txt" 2>&1 || :; }
# is_eq <desc> <got> <want>
is_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi; }

# onb_repo <name>: an installed brownfield-like repo, everything committed, with a finished set of onboarding
# documents whose gate docs check (`check-onboarding-docs.sh --gate`) passes: every gate-rules
# onboard_gate_docs entry present, commit stamps naming a real commit in HEAD's history, citations that resolve,
# no TEMPLATE marker (the installed architecture.md, network.md and context-map.md templates carry markers or an
# empty row, so the fixture fills them as a finished onboard would). The phase result is not written here.
onb_repo() {
  r_="$(t1_repo "$1" --commit)"
  t1_install "$r_" || { fail "install.sh into $1"; return 1; }
  mkdir -p "$r_/src" && printf 'line one\nline two\nline three\n' > "$r_/src/app.py"
  G "$r_" add -A >/dev/null && G "$r_" commit -qm "fixture: installed kit and source"
  base_="$(git -C "$r_" rev-parse --short HEAD)"
  d_="$r_/docs/agents-v0"
  mkdir -p "$d_/onboarding/modules" "$d_/diagrams/sequences" "$d_/adr" "$d_/discovery"
  cat > "$r_/$REP" <<EOR
# Onboarding report

commit: $base_

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
  printf '# Module: app\n\ncommit: %s\nRoot: src\n\n## Purpose\n\nPrints three lines (`src/app.py:1-3`).\n' "$base_" > "$d_/onboarding/modules/app.md"
  printf '# Sequence: app\n\n```mermaid\nsequenceDiagram\n  User->>App: run (`src/app.py:1`)\n```\n' > "$d_/diagrams/sequences/app.md"
  printf '# ADR 0000: inherited decisions\n\nStatus: Accepted (inherited)\n\nPython, one module (`src/app.py:1`).\n' > "$d_/adr/0000-inherited-decisions.md"
  printf '# HTTP endpoints\n\nnone found\n' > "$d_/discovery/endpoints.txt"
  printf '# Architecture\n\nOne module, no services.\n' > "$d_/architecture.md"
  printf '# Network\n\nNo network calls.\n' > "$d_/network.md"
  printf '# Context map\n\n## Bounded contexts\n\n| Context | Owns | Integrations |\n|---------|------|--------------|\n| app | everything | none |\n' > "$d_/design/system/context-map.md"
  G "$r_" add -A >/dev/null && G "$r_" commit -qm "fixture: onboarding documents"
  printf '%s\n' "$r_"
}
# pr_result <repo>: the agent's phase result (with a commit line: the docs check reads every .md under onboarding/)
pr_result() {
  printf 'phase: onboard\nstatus: awaiting_approval\ncommit: %s\n\nOnboarding docs written.\n' "$(git -C "$1" rev-parse --short HEAD)" > "$1/$PR"
}
# to_awaiting <repo>: onboard in progress, then awaiting approval with a phase result on disk
to_awaiting() {
  q "$1" sh "$SFS" "$REP" --active-phase onboard --status in_progress
  q "$1" sh "$SFS" "$REP" --active-phase onboard --status awaiting_approval
  pr_result "$1"
}

# ===== JO-2 approval_evidence ==================================================================================
a="$(onb_repo ae)"

# AE-1 refusal: no onboarding state at all
expect_fail "AE-1 approval_evidence refuses with no onboarding state" "$a" sh "$GC" approval_evidence onboard
out_has "AE-1 names the missing state" "REFUSED approval_evidence: there is no onboarding state ($ST); onboard has not run"

# AE-2 refusal (N2 at helper level): status in_progress, not awaiting_approval
q "$a" sh "$SFS" "$REP" --active-phase onboard --status in_progress
pr_result "$a"
expect_fail "AE-2 approval_evidence refuses while onboard is in_progress" "$a" sh "$GC" approval_evidence onboard
out_has "AE-2 names the status" "REFUSED approval_evidence: onboard status is in_progress, not awaiting_approval"

# N2: --approve onboard while the status is not awaiting_approval is refused and records nothing
expect_fail "N2 sync --approve onboard from in_progress is refused" "$a" sh "$SFS" "$REP" --approve onboard
out_has "N2 refusal comes from approval_evidence" "REFUSED approval_evidence: onboard status is in_progress, not awaiting_approval"
is_eq "N2 nothing approved after the refusal" "$(state_val "$a" lastApprovedPhase)" ""
is_eq "N2 status still in_progress" "$(state_val "$a" activeStatus)" "in_progress"

# AE-3 refusal: awaiting_approval but no phase-result.md
q "$a" sh "$SFS" "$REP" --active-phase onboard --status awaiting_approval
q "$a" mv "$PR" "$PR.keep"
expect_fail "AE-3 approval_evidence refuses without phase-result.md" "$a" sh "$GC" approval_evidence onboard
out_has "AE-3 names the missing phase result" "REFUSED approval_evidence: $PR is missing or empty"
expect_fail "AE-3 sync --approve onboard refuses without phase-result.md" "$a" sh "$SFS" "$REP" --approve onboard
q "$a" mv "$PR.keep" "$PR"

# AE-4 refusal (N3 approval part): the gate docs check fails
printf '\nTEMPLATE: sample row\n' >> "$a/$REP"
expect_fail "AE-4 approval_evidence refuses when the onboarding docs check fails" "$a" sh "$GC" approval_evidence onboard
out_has "AE-4 names the docs check in gate mode" "REFUSED approval_evidence: the onboarding docs check failed (check-onboarding-docs.sh --gate)"
out_has "AE-4 passes on the docs check's reason" "a TEMPLATE: marker is still present"
q "$a" git checkout -q -- "$REP"
# AE-4b refusal (N3, JO-3 closes JO-2): today's default docs check passes, but a gate document is missing
q "$a" mv docs/agents-v0/adr/0000-inherited-decisions.md "$T1_TMP/adr0000.keep"
expect_pass "AE-4b setup: the default docs check still passes without adr/0000" "$a" sh .agents-v0/scripts/check-onboarding-docs.sh
expect_fail "AE-4b approval_evidence refuses when a gate document is missing" "$a" sh "$GC" approval_evidence onboard
out_has "AE-4b names the docs check in gate mode" "REFUSED approval_evidence: the onboarding docs check failed (check-onboarding-docs.sh --gate)"
out_has "AE-4b names the missing gate document" "docs/agents-v0/adr/0000-inherited-decisions.md is missing or empty (a gate document of gate-rules onboard_gate_docs)"
expect_fail "AE-4b sync --approve onboard refuses when a gate document is missing" "$a" sh "$SFS" "$REP" --approve onboard
is_eq "AE-4b nothing approved" "$(state_val "$a" lastApprovedPhase)" ""
q "$a" mv "$T1_TMP/adr0000.keep" docs/agents-v0/adr/0000-inherited-decisions.md

# AE-5 pass: awaiting_approval, phase result on disk, docs check passes
expect_pass "AE-5 approval_evidence passes with recorded evidence" "$a" sh "$GC" approval_evidence onboard
out_has "AE-5 prints the rule" "OK approval_evidence: onboard is awaiting_approval, $PR exists and the onboarding docs check passed (--gate)"

# AE-6: a phase other than onboard is not wired yet and fails closed (exit 3)
(cd "$a" && sh "$GC" approval_evidence design) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
is_eq "AE-6 approval_evidence for another phase fails closed (exit 3)" "$rc" 3

# AE-7 pass at the sync level: --approve onboard with evidence records the approval (regression lock at 36b86cf)
expect_pass "AE-7 sync --approve onboard with evidence is recorded" "$a" sh "$SFS" "$REP" --approve onboard
is_eq "AE-7 onboard approved" "$(state_val "$a" lastApprovedPhase)" "onboard"
# AE-7 (moved from test-onboard.sh, whose non-git fixture cannot pass --gate): the approval sync keeps the state
is_eq "AE-7 approval clears the active phase" "$(state_val "$a" activePhase)" ""
is_eq "AE-7 baseCommit preserved across the approval sync" "$(state_val "$a" baseCommit)" "$(sed -n 's/^commit: //p' "$a/$REP")"
has "AE-7 artifacts map records the report" "$a/$ST" '"primary": "docs/agents-v0/onboarding/report.md"'

# ===== N1: a typed Approved row in report.md never counts (JO-2, SKO-5) ==========================================
n="$(onb_repo n1)"
q "$n" sh "$SFS" "$REP" --active-phase onboard --status in_progress
printf '| onboard | %s | user | Approved | 2026-11-02 |\n' "$REP" >> "$n/$REP"
expect_pass "N1 plain sync with a typed Approved row runs" "$n" sh "$SFS" "$REP"
is_eq "N1 typed Approved row is not an approval (lastApprovedPhase)" "$(state_val "$n" lastApprovedPhase)" ""
is_eq "N1 typed Approved row is not an approval (approvedPhases)" "$(state_val "$n" approvedPhases)" ""
expect_fail "N1 --approve onboard still refuses (status in_progress)" "$n" sh "$SFS" "$REP" --approve onboard
out_has "N1 refusal comes from approval_evidence" "REFUSED approval_evidence:"
# N1 (SKO-5 half): a typed Re-opened row is not a reopen either
printf '| onboard | %s | user | Re-opened | 2026-11-02 |\n' "$REP" >> "$n/$REP"
expect_pass "N1 plain sync with a typed Re-opened row runs" "$n" sh "$SFS" "$REP"
is_eq "N1 typed Re-opened row does not count as a reopen" "$(state_val "$n" reopenCount)" "0"

# ===== JO-1 gate_committed ====================================================================================
c="$(onb_repo gc)"

# GC-1 refusal: onboard not approved
expect_fail "GC-1 gate_committed refuses when onboard is not approved" "$c" sh "$GC" gate_committed onboard
out_has "GC-1 names the missing approval" "REFUSED gate_committed: onboard is not approved in $ST, so it has no gate commit"

# GC-2 refusal (N4 at helper level): approved but not committed
to_awaiting "$c"
q "$c" sh "$SFS" "$REP" --approve onboard
is_eq "GC-2 setup: onboard approved" "$(state_val "$c" lastApprovedPhase)" "onboard"
expect_fail "GC-2 / N4 gate_committed refuses an approved but uncommitted onboard" "$c" sh "$GC" gate_committed onboard
out_has "GC-2 says the gate is not committed" "REFUSED gate_committed: the onboard gate is not committed (check-gate-commit.sh)"
out_has "GC-2 passes on check-gate-commit.sh's reason" "is not committed"

# GC-3 refusal: committed, but no onboard-v<n> tag
q "$c" G . add -A; q "$c" G . commit -qm "onboarding: onboard approved"
expect_fail "GC-3 gate_committed refuses without an onboard-v<n> tag" "$c" sh "$GC" gate_committed onboard
out_has "GC-3 names the missing tag" "REFUSED gate_committed: no onboard-v<n> tag on the onboard gate commit"

# GC-4 pass: committed and tagged
q "$c" G . tag -a onboard-v1 -m "onboard approved"
expect_pass "GC-4 gate_committed passes when committed and tagged" "$c" sh "$GC" gate_committed onboard
out_has "GC-4 prints the rule" "OK gate_committed: onboard is approved, committed (check-gate-commit.sh) and tagged onboard-v1"

# GC-5 refusal: a later uncommitted change (dirty tree) after the gate commit
printf 'scratch\n' > "$c/scratch.txt"
expect_fail "GC-5 gate_committed refuses with uncommitted changes" "$c" sh "$GC" gate_committed onboard
out_has "GC-5 says the gate is not committed" "REFUSED gate_committed: the onboard gate is not committed (check-gate-commit.sh)"
q "$c" mv scratch.txt "$T1_TMP/scratch.txt"

# GC-6 refusal: reopened and approved again; the newest tag still holds the old approval
sleep 1
q "$c" sh "$SFS" "$REP" --reopen onboard
q "$c" sh "$SFS" "$REP" --active-phase onboard --status awaiting_approval
q "$c" sh "$SFS" "$REP" --approve onboard
q "$c" G . add -A; q "$c" G . commit -qm "onboarding: onboard approved (revision)"
expect_fail "GC-6 gate_committed refuses when the newest tag holds an older approval" "$c" sh "$GC" gate_committed onboard
out_has "GC-6 names the stale tag" "REFUSED gate_committed: onboard-v1 does not hold the current onboard approval; tag the new gate commit onboard-v2"
q "$c" G . tag -a onboard-v2 -m "onboard approved"
expect_pass "GC-6 passes once the revision is tagged onboard-v2" "$c" sh "$GC" gate_committed onboard

# GC-7 refusal: not a git work tree
ng="$T1_TMP/nogit"; mkdir -p "$ng/docs/agents-v0/onboarding"
q "$c" cp -R .agents-v0 "$ng/.agents-v0"; q "$c" cp "$REP" "$ST" "$ng/docs/agents-v0/onboarding/"
expect_fail "GC-7 gate_committed refuses outside a git work tree" "$ng" sh "$GC" gate_committed onboard
out_has "GC-7 names the missing repo" "REFUSED gate_committed: not a git work tree, so the onboard gate cannot be committed"

# list reports the two wired checks
expect_pass "list runs" "$a" sh "$GC" list
out_has "list: approval_evidence is wired" "approval_evidence wired"
out_has "list: gate_committed is wired" "gate_committed wired"

# ===== JO-3/JO-4 check-onboarding-docs.sh --gate ===============================================================
# Design rev 6 lines 23, 63, 86, 110, 119, 127, 516; review jiraiya-review-of-onboard-flow-20261101.md:155-156.
DOCS=".agents-v0/scripts/check-onboarding-docs.sh"
g="$(onb_repo dg)"
pr_result "$g"
# park <repo> <path> / unpark <repo> <path>: move a document out of the repo and back (nothing is deleted)
park() { mkdir -p "$T1_TMP/parked/$(dirname "$2")" && mv "$1/$2" "$T1_TMP/parked/$2"; }
unpark() { mv "$T1_TMP/parked/$2" "$1/$2"; }

# DG-0 usage: --gate takes no paths (the list is gate-rules onboard_gate_docs)
(cd "$g" && sh "$DOCS" --gate docs/agents-v0/architecture.md) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
is_eq "DG-0 --gate with a path is a usage error (exit 2)" "$rc" 2
out_has "DG-0 says the list comes from gate-rules" "takes no paths; the list is gate-rules onboard_gate_docs"

# DG-1 pass (H1 partial: the docs check passes in gate mode, design line 71)
expect_pass "DG-1 --gate passes on a finished onboarding" "$g" sh "$DOCS" --gate
out_has "DG-1 prints the gate OK line" "OK: onboarding gate documents are present, cite real code and name real commits (--gate)"
lacks "DG-1 prints no WARN line" "$T1_TMP/out.txt" "WARN:"

# DG-2 refusal (N3 a gate doc is missing; E7 a gate template is missing): each gate-rules file entry
for f_ in docs/agents-v0/onboarding/report.md docs/agents-v0/architecture.md docs/agents-v0/network.md \
  docs/agents-v0/design/system/context-map.md docs/agents-v0/adr/0000-inherited-decisions.md \
  docs/agents-v0/discovery/endpoints.txt; do
  park "$g" "$f_"
  expect_fail "DG-2 --gate fails without $f_" "$g" sh "$DOCS" --gate
  if [ "$f_" = "$REP" ]; then
    out_has "DG-2 names the missing report" "FAIL: docs/agents-v0/onboarding/report.md is missing (copy docs/agents-v0/onboarding/_report.template.md)"
  else
    out_has "DG-2 names $f_" "FAIL: $f_ is missing or empty (a gate document of gate-rules onboard_gate_docs)"
  fi
  unpark "$g" "$f_"
done
: > "$g/docs/agents-v0/discovery/endpoints.txt"
expect_fail "DG-2 --gate fails on an empty gate document" "$g" sh "$DOCS" --gate
out_has "DG-2 names the empty endpoints.txt" "FAIL: docs/agents-v0/discovery/endpoints.txt is missing or empty"
q "$g" git checkout -q -- docs/agents-v0/discovery/endpoints.txt

# DG-3 refusal: the modules directory has no module document (only a template)
park "$g" docs/agents-v0/onboarding/modules/app.md
printf '# Module template\n\nTEMPLATE: copy me\n' > "$g/docs/agents-v0/onboarding/modules/_template.md"
expect_fail "DG-3 --gate fails with no module document" "$g" sh "$DOCS" --gate
out_has "DG-3 names the empty modules directory" "FAIL: docs/agents-v0/onboarding/modules/ has no document (a gate document of gate-rules onboard_gate_docs; templates do not count)"
unpark "$g" docs/agents-v0/onboarding/modules/app.md

# DG-4 (design line 516): in --gate every _*.md is a template and is not scanned; the default run still scans _template.md
expect_pass "DG-4 --gate skips modules/_template.md (TEMPLATE marker, no commit line)" "$g" sh "$DOCS" --gate
expect_fail "DG-4 the default run still scans modules/_template.md (unchanged)" "$g" sh "$DOCS"
q "$g" mv docs/agents-v0/onboarding/modules/_template.md "$T1_TMP/parked/modules-_template.md"

# DG-5 refusal (E22): only diagrams/sequences/_template.md is present
park "$g" docs/agents-v0/diagrams/sequences/app.md
printf '# Sequence template\n\n```mermaid\nsequenceDiagram\n```\n' > "$g/docs/agents-v0/diagrams/sequences/_template.md"
expect_fail "E22 --gate fails with only diagrams/sequences/_template.md" "$g" sh "$DOCS" --gate
out_has "E22 names the sequences directory" "FAIL: docs/agents-v0/diagrams/sequences/ has no document"
unpark "$g" docs/agents-v0/diagrams/sequences/app.md
q "$g" mv docs/agents-v0/diagrams/sequences/_template.md "$T1_TMP/parked/sequences-_template.md"

# DG-6 refusal (JO-3): the context map is the installed template (header and an empty row only)
G "$g" show "HEAD~1:docs/agents-v0/design/system/context-map.md" > "$g/docs/agents-v0/design/system/context-map.md"
expect_fail "DG-6 --gate fails on the unfilled context map" "$g" sh "$DOCS" --gate
out_has "DG-6 names the context map" "FAIL: docs/agents-v0/design/system/context-map.md: no context or integration row below the table header"
q "$g" git checkout -q -- docs/agents-v0/design/system/context-map.md

# DG-7 refusal (JO-3): report.md names a module or sequence document that does not exist
printf '\n- docs/agents-v0/diagrams/sequences/checkout.md\n' >> "$g/$REP"
expect_fail "DG-7 --gate fails when report.md names a missing sequence" "$g" sh "$DOCS" --gate
out_has "DG-7 names the missing sequence" "FAIL: docs/agents-v0/onboarding/report.md names docs/agents-v0/diagrams/sequences/checkout.md, which does not exist"
q "$g" git checkout -q -- "$REP"

# DG-8 refusal (N3 a citation does not match): a line past the end of the cited file
printf '\nAlso `src/app.py:9`.\n' >> "$g/docs/agents-v0/onboarding/modules/app.md"
expect_fail "DG-8 / N3 --gate fails on a citation past the end of the file" "$g" sh "$DOCS" --gate
out_has "DG-8 names the citation" "FAIL: docs/agents-v0/onboarding/modules/app.md: src/app.py:9 is outside the file (3 lines)"
q "$g" git checkout -q -- docs/agents-v0/onboarding/modules/app.md

# DG-9 (JO-4): extensionless and newly listed file types are citations in --gate
printf 'FROM scratch\nCOPY src /src\n' > "$g/Dockerfile"
printf '\nBuilt by `Dockerfile:5`.\n' >> "$g/docs/agents-v0/architecture.md"
expect_pass "DG-9 setup: the default run does not see a Dockerfile citation (unchanged)" "$g" sh "$DOCS"
expect_fail "DG-9 --gate fails on a Dockerfile line past the end" "$g" sh "$DOCS" --gate
out_has "DG-9 names the Dockerfile citation" "FAIL: docs/agents-v0/architecture.md: Dockerfile:5 is outside the file (2 lines)"
q "$g" git checkout -q -- docs/agents-v0/architecture.md
printf '\nBuilt by `Dockerfile:1-2`; the client is `web/main.mjs:1`.\n' >> "$g/docs/agents-v0/architecture.md"
expect_fail "DG-9 --gate fails on a missing .mjs file" "$g" sh "$DOCS" --gate
out_has "DG-9 names the missing .mjs file" "FAIL: docs/agents-v0/architecture.md: cited file does not exist: web/main.mjs"
lacks "DG-9 the valid Dockerfile range is not reported" "$T1_TMP/out.txt" "Dockerfile:1-2"
q "$g" git checkout -q -- docs/agents-v0/architecture.md

# DG-10 warning (JO-4): an unbackticked citation is reported, not failed; hostnames are not citations
printf '\nSee src/missing.py:4 and db.internal:5432.\n' >> "$g/docs/agents-v0/network.md"
expect_pass "DG-10 --gate passes with an unbackticked citation" "$g" sh "$DOCS" --gate
out_has "DG-10 warns about the unbackticked citation" "WARN: docs/agents-v0/network.md: citation-like src/missing.py:4 is not backticked, so it is not checked"
lacks "DG-10 no warning for a hostname" "$T1_TMP/out.txt" "db.internal"
q "$g" git checkout -q -- docs/agents-v0/network.md

# DG-11 refusal (N3 wrong stamp; JO-4 git cat-file -e): a stamp that is no commit, and one off HEAD's history
mod_="docs/agents-v0/onboarding/modules/app.md"
sed 's/^commit: .*/commit: deadbeef1/' "$g/$mod_" > "$T1_TMP/mod.md" && cp "$T1_TMP/mod.md" "$g/$mod_"
expect_pass "DG-11 setup: the default run accepts any hex stamp (unchanged)" "$g" sh "$DOCS"
expect_fail "DG-11 / N3 --gate fails on a stamp that is not a commit" "$g" sh "$DOCS" --gate
out_has "DG-11 names the bad stamp" "FAIL: $mod_: commit stamp deadbeef1 is not a commit in this repository"
q "$g" git checkout -q -- "$mod_"
G "$g" checkout -q -b side >/dev/null 2>&1; printf 'side\n' > "$g/side.txt"; G "$g" add side.txt; G "$g" commit -qm side
side_="$(git -C "$g" rev-parse HEAD)"; G "$g" checkout -q main >/dev/null 2>&1
sed "s/^commit: .*/commit: $side_/" "$g/$mod_" > "$T1_TMP/mod.md" && cp "$T1_TMP/mod.md" "$g/$mod_"
expect_fail "DG-11 --gate fails on a stamp outside HEAD's history" "$g" sh "$DOCS" --gate
out_has "DG-11 names the off-history stamp" "FAIL: $mod_: commit stamp $side_ is not in the history of HEAD"
q "$g" git checkout -q -- "$mod_"
expect_pass "DG-11 the restored stamps pass again" "$g" sh "$DOCS" --gate

# DG-12 (design line 110): the gate document list is read from gate-rules, and a broken gate-rules fails closed
RL=".agents-v0/scripts/gate-rules"
sed 's#^onboard_gate_docs=#onboard_gate_docs=docs/agents-v0/extra.md #' "$g/$RL" > "$T1_TMP/rules" && cp "$T1_TMP/rules" "$g/$RL"
expect_fail "DG-12 --gate requires a document added to gate-rules onboard_gate_docs" "$g" sh "$DOCS" --gate
out_has "DG-12 names the added document" "FAIL: docs/agents-v0/extra.md is missing or empty (a gate document of gate-rules onboard_gate_docs)"
grep -v '^onboard_gate_docs=' "$g/$RL" > "$T1_TMP/rules" && cp "$T1_TMP/rules" "$g/$RL"
(cd "$g" && sh "$DOCS" --gate) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
is_eq "DG-12 --gate fails closed (exit 2) when gate-rules lacks the list" "$rc" 2
out_has "DG-12 names gate-rules" "FAIL: cannot read onboard_gate_docs from gate-rules"
q "$g" git checkout -q -- "$RL"

# DG-12b (Iruka note 2): no glob in onboard_gate_docs. gate-rules refuses * ? [ in the list, and the docs check
# never expands a list entry even if a file matches it.
for gl_ in 'docs/agents-v0/*.md' 'docs/agents-v0/arch?tecture.md' 'docs/agents-v0/[a]rchitecture.md'; do
  sed "s#^onboard_gate_docs=#onboard_gate_docs=$gl_ #" "$g/$RL" > "$T1_TMP/rules" && cp "$T1_TMP/rules" "$g/$RL"
  (cd "$g" && sh "$GC" rules onboard_gate_docs) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
  is_eq "DG-12b gate-rules refuses the glob entry $gl_ (exit 2)" "$rc" 2
  out_has "DG-12b names the glob rule for $gl_" "glob characters (* ? [) are not allowed in onboard_gate_docs"
  (cd "$g" && sh "$DOCS" --gate) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
  is_eq "DG-12b --gate fails closed (exit 2) on the glob entry $gl_" "$rc" 2
  q "$g" git checkout -q -- "$RL"
done
stub_="$T1_TMP/globstub"; mkdir -p "$stub_"
cp "$g/$DOCS" "$stub_/check-onboarding-docs.sh"
printf '%s\n' '#!/bin/sh' '# test stub: a gate list that slipped past the rules check' "printf '%s\\n' 'docs/agents-v0/glob*.md'" > "$stub_/gate-checks.sh"
printf '# Glob hit\n\nA file a glob would match; it cites `src/app.py:99`, past the end.\n' > "$g/docs/agents-v0/globhit.md"
expect_fail "DG-12b --gate does not expand a glob entry even when a file matches it" "$g" sh "$stub_/check-onboarding-docs.sh" --gate
out_has "DG-12b names the literal entry" "FAIL: docs/agents-v0/glob*.md is missing or empty"
lacks "DG-12b the matching file is not pulled in by expansion" "$T1_TMP/out.txt" "globhit.md"
park "$g" docs/agents-v0/globhit.md

# DG-13 refusal: --gate needs a git work tree (stamps are checked against the history)
ng2="$T1_TMP/nogit-dg"; mkdir -p "$ng2"
q "$g" cp -R .agents-v0 docs "$ng2/"
expect_fail "DG-13 --gate fails outside a git work tree" "$ng2" sh "$DOCS" --gate
out_has "DG-13 names the missing work tree" "FAIL: --gate needs a git work tree"

# DG-14 phase-result template (the phase-result.md gap): seeded by install, an unfilled copy fails, a filled one passes
tpl_="docs/agents-v0/onboarding/_phase-result.template.md"
if [ -f "$g/$tpl_" ]; then pass "DG-14 install seeds $tpl_"; else fail "DG-14 install seeds $tpl_"; fi
has "DG-14 the template has a commit line" "$g/$tpl_" "commit: <"
has "DG-14 the template has phase: onboard" "$g/$tpl_" "phase: onboard"
cp "$g/$PR" "$T1_TMP/pr.keep"; cp "$g/$tpl_" "$g/$PR" 2>/dev/null || :
expect_fail "DG-14 an unfilled phase-result copy fails --gate" "$g" sh "$DOCS" --gate
out_has "DG-14 names the TEMPLATE marker" "FAIL: $PR: a TEMPLATE: marker is still present"
out_has "DG-14 names the missing commit stamp" "FAIL: $PR: no \`commit: <sha>\` line"
cp "$T1_TMP/pr.keep" "$g/$PR"
expect_pass "DG-14 the filled phase result passes --gate" "$g" sh "$DOCS" --gate
if t1_hash_ok "$g"; then pass "DG-14 installed copy is HASH-OK (template and gate-rules match the kit)"; else fail "DG-14 installed copy is HASH-OK (see $T1_TMP/hash.txt)"; fi

# DG-15 prose (design line 86; the phase-result gap): the installed command and skill run --gate and copy the template
for doc_ in .cursor/commands/v0-onboard.md .cursor/skills/onboard-discovery/SKILL.md; do
  has "DG-15 $doc_ runs the gate docs check" "$g/$doc_" "check-onboarding-docs.sh --gate"
  has "DG-15 $doc_ copies the phase-result template" "$g/$doc_" "_phase-result.template.md"
done

t1_done test-gate-checks.sh
