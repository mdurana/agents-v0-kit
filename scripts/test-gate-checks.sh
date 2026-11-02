#!/bin/sh
# test-gate-checks.sh — tier 1 tests for .agents-v0/scripts/gate-checks.sh and the sync wiring that calls it
# (onboard fix; design jiraiya-onboard-fix-design-20261101.md rev 6, line 149: "a new test-gate-checks.sh").
# Offline, no agent. Every case runs on an installed copy (install.sh into a temp git repo, Yamato's tier 1
# harness). Each helper check has a pass case and a refusal case with its exact message.
# Test ids: jiraiya-onboard-test-cases-20261101.md (N1, N2, N3, N4, E7, E22, H1/H2 partial) plus AE-n / GC-n
# helper cases, DG-n cases for `check-onboarding-docs.sh --gate` (JO-3/JO-4), PA-n (JO-9 prereq_approved) and
# NR-n (JO-10 no_restart_without_reopen: N8 N19 N28 N29 N30 E9), SS-n (JO-8 follow-up: staged path names,
# Iruka probe 8), LT-n and N80-N84 (N3A ledger integrity: the Agents-V0-Ledger trailer, ledger_ok, ledger_mark,
# ledger_turn_ok), FC-n (round 17: the fresh-clone hint on the missing-ledger refusal; FC-8 and FC-7 G3 round
# 18), LZ-n (round 18: onboard-v<n> tags with a leading zero), GW-n (round 18: greenfield_record_ok wired into prereq_approved and
# onboard; orphan roots, whole-value fields, the untrusted-root marker) and LA-n (round 19: adopt_legacy_tags, the
# person's one-time adoption of trailer-less legacy onboard-v<n> tags, and the ledger checks honouring its record).
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
# lt_trailer <repo>: the N3A trailer for the repo's gate ledger (made empty when missing); a stand-in for the
# commit chain's staged_secret_scan, which writes the same trailer into the gate commit message
lt_trailer() {
  lt_d="$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd)/agents-v0"
  mkdir -p "$lt_d"; [ -f "$lt_d/gate-ledger" ] || : > "$lt_d/gate-ledger"
  printf 'Agents-V0-Ledger: lines=%s sha256=%s\n' "$(wc -l < "$lt_d/gate-ledger" | tr -d ' ')" \
    "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$lt_d/gate-ledger")"
}
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
q "$c" G . add -A; q "$c" G . commit -qm "onboarding: onboard approved" -m "$(lt_trailer "$c")"
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
# an agent-run --reopen onboard is refused (JO-10, N19: reopen_grant_ok is not built, so no grant passes)
expect_fail "GC-6 N19 sync --reopen onboard is refused without a valid grant" "$c" sh "$SFS" "$REP" --reopen onboard
out_has "GC-6 N19 names the missing grant" "FAIL: --reopen onboard refused: no valid reopen grant (gate-checks.sh reopen_grant_ok)"
# stand-in for a person's granted reopen (the grant is not built): the state file is set back by hand
q "$c" python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["approvedPhases"]=[x for x in d.get("approvedPhases") or [] if x!="onboard"]
d["activePhase"]="onboard"; d["activeStatus"]="awaiting_approval"
json.dump(d, open(p,"w"), indent=2)' "$ST"
q "$c" sh "$SFS" "$REP" --approve onboard
q "$c" G . add -A; q "$c" G . commit -qm "onboarding: onboard approved (revision)" -m "$(lt_trailer "$c")"
expect_fail "GC-6 gate_committed refuses when the newest tag holds an older approval" "$c" sh "$GC" gate_committed onboard
out_has "GC-6 names the stale tag" "REFUSED gate_committed: onboard-v1 does not hold the current onboard approval; tag the new gate commit onboard-v2"
q "$c" G . tag -a onboard-v2 -m "onboard approved"
expect_pass "GC-6 passes once the revision is tagged onboard-v2" "$c" sh "$GC" gate_committed onboard

# GC-7 refusal: not a git work tree
ng="$T1_TMP/nogit"; mkdir -p "$ng/docs/agents-v0/onboarding"
q "$c" cp -R .agents-v0 "$ng/.agents-v0"; q "$c" cp "$REP" "$ST" "$ng/docs/agents-v0/onboarding/"
expect_fail "GC-7 gate_committed refuses outside a git work tree" "$ng" sh "$GC" gate_committed onboard
out_has "GC-7 names the missing repo" "REFUSED gate_committed: not a git work tree, so the onboard gate cannot be committed"

# ===== JO-9 prereq_approved ===================================================================================
# Design rev 6 flow step 9, lines 29, 73, 84, 97, 171, gap 1 (brownfield only) and gap 9 (the brownfield record):
# roadmap, intake, plan, architecture, deliver (and triage, maintain: Sensei 20:45; gate-rules
# prereq_approved_phases) refuse to start until onboard is approved and committed.
# PA-1 pass: a repo with no brownfield record (no onboarding state, report or baseline-audit record)
gf="$(t1_repo pa-green --commit)"; t1_install "$gf" || fail "install.sh into pa-green"
expect_pass "PA-1 prereq_approved passes with no brownfield record" "$gf" sh "$GC" prereq_approved intake
out_has "PA-1 says why" "OK prereq_approved: no brownfield record"
# PA-2 refusal: brownfield (onboarding state exists), onboard not approved
p2="$(onb_repo pa)"
q "$p2" sh "$SFS" "$REP" --active-phase onboard --status in_progress
for ph_ in roadmap intake plan architecture deliver triage maintain; do
  expect_fail "PA-2 prereq_approved $ph_ refuses while onboard is not approved" "$p2" sh "$GC" prereq_approved "$ph_"
done
out_has "PA-2 names the missing approval" "REFUSED prereq_approved: maintain needs onboard approved and committed first; onboard is not approved in $ST"
# PA-3 a phase that is not a next phase of onboard has no prerequisite here
expect_pass "PA-3 prereq_approved design passes (not in gate-rules prereq_approved_phases)" "$p2" sh "$GC" prereq_approved design
out_has "PA-3 names the list" "OK prereq_approved: design is not in gate-rules prereq_approved_phases"
# PA-4 sync: each next phase refuses to start, and nothing is written
mkdir -p "$p2/docs/agents-v0/requirements" "$p2/docs/agents-v0/roadmap" "$p2/docs/agents-v0/milestones" "$p2/docs/agents-v0/maintain/fix-1"
printf '# orders\n' > "$p2/docs/agents-v0/requirements/orders.md"
printf '# roadmap\n' > "$p2/docs/agents-v0/roadmap/prog.md"
printf '# plan\n' > "$p2/docs/agents-v0/milestones/plan.md"
printf '# note\n\ntier: standard\n' > "$p2/docs/agents-v0/maintain/fix-1/note.md"
for pa_ in "intake docs/agents-v0/requirements/orders.md" "roadmap docs/agents-v0/roadmap/prog.md" \
  "architecture docs/agents-v0/architecture.md" "plan docs/agents-v0/milestones/plan.md" \
  "maintain docs/agents-v0/maintain/fix-1/note.md"; do
  ph_="${pa_%% *}"; ar_="${pa_#* }"
  expect_fail "PA-4 sync --active-phase $ph_ in_progress refuses before onboard is approved" "$p2" sh "$SFS" --active-phase "$ph_" --status in_progress "$ar_"
  out_has "PA-4 $ph_ refusal comes from prereq_approved" "REFUSED prereq_approved: $ph_ needs onboard approved and committed first"
done
if [ -f "$p2/docs/agents-v0/requirements/orders.state.json" ]; then fail "PA-4 no intake state written"; else pass "PA-4 no intake state written"; fi
expect_pass "PA-4 recording intake blocked is still allowed" "$p2" sh "$SFS" --active-phase intake --status blocked --reason "onboard first" docs/agents-v0/requirements/orders.md
# PA-5 refusal: approved but not committed
q "$p2" sh "$SFS" "$REP" --active-phase onboard --status awaiting_approval
pr_result "$p2"
q "$p2" sh "$SFS" "$REP" --approve onboard
is_eq "PA-5 setup: onboard approved" "$(state_val "$p2" lastApprovedPhase)" "onboard"
expect_fail "PA-5 prereq_approved refuses an approved but uncommitted onboard" "$p2" sh "$GC" prereq_approved intake
out_has "PA-5 names the uncommitted approval" "REFUSED prereq_approved: intake needs onboard approved and committed first; the onboard approval in $ST is not committed"
# PA-5b refusal: committed, but no onboard-v<n> tag
q "$p2" G . add -- docs/agents-v0/onboarding; q "$p2" G . commit -qm "onboarding: onboard approved"
expect_fail "PA-5b prereq_approved refuses a committed onboard without an onboard-v<n> tag" "$p2" sh "$GC" prereq_approved intake
out_has "PA-5b names the missing tag" "REFUSED prereq_approved: intake needs onboard approved and committed first; no onboard-v<n> tag on the onboard gate commit"
# PA-6 pass: approved, committed and tagged (repo c from GC-6)
expect_pass "PA-6 prereq_approved intake passes once onboard is approved, committed and tagged" "$c" sh "$GC" prereq_approved intake
out_has "PA-6 prints the rule" "OK prereq_approved: intake: onboard is approved and committed (state.json committed, tagged onboard-v2)"
mkdir -p "$c/docs/agents-v0/requirements"; printf '# orders\n' > "$c/docs/agents-v0/requirements/orders.md"
expect_pass "PA-6 sync --active-phase intake in_progress starts after the onboard gate commit" "$c" sh "$SFS" --active-phase intake --status in_progress docs/agents-v0/requirements/orders.md
q "$c" mv docs/agents-v0/requirements "$T1_TMP/pa6-requirements"
# PA-7 refusal: only the baseline-audit record marks the repo brownfield (onboard never ran)
p7="$(t1_repo pa-audit --commit)"; t1_install "$p7" || fail "install.sh into pa-audit"
mkdir -p "$p7/docs/agents-v0/discovery"; printf 'result: pass\n' > "$p7/docs/agents-v0/discovery/baseline-audit.txt"
expect_fail "PA-7 prereq_approved refuses when only the baseline-audit record exists" "$p7" sh "$GC" prereq_approved roadmap
out_has "PA-7 says onboard has not run" "REFUSED prereq_approved: roadmap needs onboard approved and committed first; onboard has not run ($ST is missing)"
# PA-8 refusal: a corrupt onboarding state is never read as not brownfield
mkdir -p "$p7/docs/agents-v0/onboarding"; printf '{not json' > "$p7/$ST"
expect_fail "PA-8 prereq_approved refuses on a corrupt onboarding state" "$p7" sh "$GC" prereq_approved intake
out_has "PA-8 asks the user" "is not valid JSON; stop and ask the user"
# PA-9 refusal: the helper is missing on a repo with a brownfield record (fail closed)
mkdir -p "$p7/docs/agents-v0/requirements"; printf '# orders\n' > "$p7/docs/agents-v0/requirements/orders.md"
q "$p7" mv .agents-v0/scripts/gate-checks.sh "$T1_TMP/pa9-gate-checks.sh"
expect_fail "PA-9 sync refuses intake when gate-checks.sh is missing and a brownfield record exists" "$p7" sh .agents-v0/scripts/sync-feature-state.sh --active-phase intake --status in_progress docs/agents-v0/requirements/orders.md
out_has "PA-9 names the missing helper" "to check the onboard prerequisite (docs/agents-v0/onboarding/state.json exists); reinstall the kit"
q "$p7" mv "$T1_TMP/pa9-gate-checks.sh" .agents-v0/scripts/gate-checks.sh

# ===== JO-10 no_restart_without_reopen ===========================================================================
# Design rev 6 flow step 2 (Sakura SKO-1/2/3); test cases N8, N19, N28, N29, N30, E9.
nr="$(onb_repo nr)"
# cks <repo>: the onboarding state's checksum ("none" when missing), to prove a refusal recorded nothing
cks() { if [ -f "$1/$ST" ]; then cksum < "$1/$ST"; else echo none; fi; }
expect_pass "NR-1 no state and no earlier run: a new run" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-1 says why" "(no onboarding state and no earlier run: a new run)"
expect_pass "NR-2 sync --status in_progress starts onboard" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
expect_pass "NR-2 E9 resume while in_progress is allowed without --reopen" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
expect_pass "NR-2 the helper passes while in_progress" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-2 names the status" "OK no_restart_without_reopen: no state change on an onboard report awaiting review or approved without a granted --reopen onboard (onboard is in_progress)"
pr_result "$nr"
expect_pass "NR-3 sync --status awaiting_approval" "$nr" sh "$SFS" --active-phase onboard --status awaiting_approval "$REP"
expect_fail "NR-3 the helper refuses while awaiting_approval" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-3 names the status" "REFUSED no_restart_without_reopen: onboard is awaiting_approval in $ST; wait for the user's approval (--approve onboard)"
nr_ck="$(cks "$nr")"
expect_fail "NR-3 N8 restart (in_progress) while awaiting_approval is refused" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
out_has "NR-3 N8 the refusal comes from the helper" "REFUSED no_restart_without_reopen: onboard is awaiting_approval"
out_has "NR-3 N8 sync says nothing was recorded" "FAIL: onboard state change refused (gate-checks.sh no_restart_without_reopen). Nothing was recorded."
expect_fail "NR-3 N28 --clear-active while awaiting_approval is refused" "$nr" sh "$SFS" --clear-active "$REP"
out_has "NR-3 N28 the refusal comes from the helper" "REFUSED no_restart_without_reopen: onboard is awaiting_approval"
expect_fail "NR-3 N29 set blocked while awaiting_approval is refused" "$nr" sh "$SFS" --active-phase onboard --status blocked --reason "stuck" "$REP"
out_has "NR-3 N29 the refusal comes from the helper" "REFUSED no_restart_without_reopen: onboard is awaiting_approval"
expect_fail "NR-3 SKO-2 a plain sync while awaiting_approval is refused" "$nr" sh "$SFS" "$REP"
out_has "NR-3 SKO-2 the refusal comes from the helper" "REFUSED no_restart_without_reopen: onboard is awaiting_approval"
expect_fail "NR-4 N19 --reopen onboard without a grant is refused" "$nr" sh "$SFS" --reopen onboard "$REP"
out_has "NR-4 N19 the refusal comes from reopen_grant_ok" "reopen_grant_ok"
out_has "NR-4 N19 sync names the grant" "FAIL: --reopen onboard refused: no valid reopen grant (gate-checks.sh reopen_grant_ok). The retry count is kept."
is_eq "NR-3/NR-4 the refusals recorded nothing" "$(cks "$nr")" "$nr_ck"
is_eq "NR-3/NR-4 still awaiting_approval" "$(state_val "$nr" activeStatus)" "awaiting_approval"
expect_pass "NR-5 --approve onboard is still allowed while awaiting_approval" "$nr" sh "$SFS" --approve onboard "$REP"
expect_fail "NR-5 the helper refuses once onboard is approved" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-5 names the approval" "REFUSED no_restart_without_reopen: onboard is approved in $ST; a state change needs --reopen onboard with a grant that passes reopen_grant_ok"
nr_ck="$(cks "$nr")"
expect_fail "NR-5 restart (in_progress) after the approval is refused" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
expect_fail "NR-5 --clear-active after the approval is refused" "$nr" sh "$SFS" --clear-active "$REP"
is_eq "NR-5 the refusals recorded nothing" "$(cks "$nr")" "$nr_ck"
# N30 / SKO-3: a moved or corrupt state with an earlier run's trace is a refusal, never a new run
mkdir -p "$T1_TMP/nr" && mv "$nr/$ST" "$T1_TMP/nr/state.json"
expect_fail "NR-6 N30 a moved state with phase-result.md on disk is refused" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-6 N30 asks the user" "REFUSED no_restart_without_reopen: $ST is missing but an earlier onboard run left $PR; state missing or corrupt, stop and ask the user (this is not a new run)"
expect_fail "NR-6 N30 sync does not start a new run" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
is_eq "NR-6 N30 no new state was written" "$(cks "$nr")" "none"
printf '{ not json\n' > "$nr/$ST"
expect_fail "NR-7 N30 a corrupt state is refused" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-7 N30 asks the user" "REFUSED no_restart_without_reopen: $ST is not valid JSON; state missing or corrupt, stop and ask the user (this is not a new run)"
expect_fail "NR-7 N30 sync on a corrupt state is refused" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
mv "$nr/$ST" "$T1_TMP/nr/corrupt-state.json"; mv "$nr/$PR" "$T1_TMP/nr/phase-result.md"
q "$nr" G . commit -q --allow-empty -m "onboarding: onboard approved" -m "$(lt_trailer "$nr")"
q "$nr" G . tag -a onboard-v1 -m "onboard approved"
expect_fail "NR-8 N30 an onboard-v<n> tag alone is a trace" "$nr" sh "$GC" no_restart_without_reopen
out_has "NR-8 N30 names the tag" "is missing but an earlier onboard run left tags onboard-v1; state missing or corrupt"
mv "$T1_TMP/nr/state.json" "$nr/$ST"; mv "$T1_TMP/nr/phase-result.md" "$nr/$PR"
# NR-9: the helper is missing (fail closed on every onboard path)
mv "$nr/$GC" "$T1_TMP/nr/gate-checks.sh"
expect_fail "NR-9 sync refuses an onboard state change when gate-checks.sh is missing" "$nr" sh "$SFS" --active-phase onboard --status in_progress "$REP"
out_has "NR-9 names the missing helper" "FAIL: an onboard state change needs .agents-v0/scripts/gate-checks.sh (no_restart_without_reopen); reinstall the kit"
mv "$T1_TMP/nr/gate-checks.sh" "$nr/$GC"

# ===== JO-8 follow-up: staged path names (Iruka probe 8) ==========================================================
# The staged list is read NUL-separated: no word splitting, no glob expansion, no pathspec magic.
ss="$(onb_repo ss)"
# lit_add <repo> <path>: stage one path literally (no pathspec magic or globbing)
lit_add() ( GIT_LITERAL_PATHSPECS=1; export GIT_LITERAL_PATHSPECS; G "$1" add -- "$2" )
ss_nl="$(printf 'nl\nname')"
mkdir -p "$ss/docs/agents-v0/onboarding/modules"
printf '# my mod\n' > "$ss/docs/agents-v0/onboarding/modules/my mod.md"; lit_add "$ss" "docs/agents-v0/onboarding/modules/my mod.md"
expect_pass "SS-1 Iruka Q1 an onboard doc with a space in its name passes the path check" "$ss" sh "$GC" staged_secret_scan
lacks "SS-1 the name is not split" "$T1_TMP/out.txt" "lock files: mod.md"
q "$ss" G . reset -q
printf 'x\n' > "$ss/docs/agents-v0/zz.md"; lit_add "$ss" docs/agents-v0/zz.md
mkdir -p "$ss/[d]ocs/agents-v0" && printf 'outside\n' > "$ss/[d]ocs/agents-v0/zz.md"; lit_add "$ss" "[d]ocs/agents-v0/zz.md"
expect_fail "SS-2 Iruka Q2 an outside path named like a glob of an onboard path is refused" "$ss" sh "$GC" staged_secret_scan
out_has "SS-2 names the outside path" "or lock files: [d]ocs/agents-v0/zz.md. Nothing was unstaged"
lacks "SS-2 the refusal comes before the scan" "$T1_TMP/out.txt" "SECRET-SCAN"
q "$ss" G . reset -q
printf '# nl\n' > "$ss/docs/agents-v0/onboarding/$ss_nl.md"; lit_add "$ss" "docs/agents-v0/onboarding/$ss_nl.md"
is_eq "SS-3 setup: git stages a name with a newline" "$(git -C "$ss" diff --cached --name-only -z | tr '\0\n' '|~')" "docs/agents-v0/onboarding/nl~name.md|"
expect_pass "SS-3 an onboard doc with a newline in its name passes the path check" "$ss" sh "$GC" staged_secret_scan
q "$ss" G . reset -q
mkdir -p "$ss/src/$ss_nl" && printf 'outside\n' > "$ss/src/$ss_nl/x.md"; lit_add "$ss" "src/$ss_nl/x.md"
expect_fail "SS-4 an outside path with a newline in its name is refused" "$ss" sh "$GC" staged_secret_scan
out_has "SS-4 names the whole path, quoted" 'or lock files: "src/nl\nname/x.md". Nothing was unstaged'
q "$ss" G . reset -q
mkdir -p "$ss/:(top)docs/agents-v0" && printf 'outside\n' > "$ss/:(top)docs/agents-v0/m.md"; lit_add "$ss" ":(top)docs/agents-v0/m.md"
expect_fail "SS-5 an outside path that looks like pathspec magic is refused" "$ss" sh "$GC" staged_secret_scan
out_has "SS-5 names it" "or lock files: :(top)docs/agents-v0/m.md. Nothing was unstaged"
q "$ss" G . reset -q
printf 'in\n' > "$ss/docs/agents-v0/:(exclude)m.md"; lit_add "$ss" "docs/agents-v0/:(exclude)m.md"
expect_pass "SS-6 an onboard doc whose name looks like pathspec magic passes the path check" "$ss" sh "$GC" staged_secret_scan
q "$ss" G . reset -q
printf 'lock\n' > "$ss/docs/agents-v0/my deps.lock"; ( GIT_LITERAL_PATHSPECS=1; export GIT_LITERAL_PATHSPECS; G "$ss" add -f -- "docs/agents-v0/my deps.lock" )
expect_fail "SS-7 a lock file with a space in its name is refused" "$ss" sh "$GC" staged_secret_scan
out_has "SS-7 names it, quoted" 'or lock files: "docs/agents-v0/my deps.lock". Nothing was unstaged'
q "$ss" G . reset -q

# ===== N3A ledger integrity (design rev 6 "Ledger integrity (N3A)"; test cases N80-N84) ===========================
# The gate commit records the ledger (lines and sha256) in its Agents-V0-Ledger trailer; ledger_ok and every gate
# check refuse "ledger changed, ask the user" when the ledger is cut, missing or edited, or an appended line is
# not a well-formed kit line. No kit script writes FAIL lines yet (gap 10); reopen_grant_ok writes GRANT-USED and
# REOPEN-REFUSED (tested below, RG-*), and these tests append such lines by hand to test the ledger check alone.
lg="$(onb_repo lg)"
LG_LED="$(cd "$lg" && cd "$(git rev-parse --git-common-dir)" && pwd)/agents-v0/gate-ledger"
LG_GRANT="${LG_LED%/gate-ledger}/reopen-grant"
LG_EMPTY="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
lg_sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
lg_env() { env GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com "$@"; }
# lg_gate <repo> <n>: the kit's commit chain for the onboard docs (staged_secret_scan, commit_msg_ok, commit, tag)
lg_gate() { (cd "$1" && G . add --all -- docs/agents-v0 && sh "$GC" staged_secret_scan && sh "$GC" commit_msg_ok \
  && lg_env git commit -q -F "$(git rev-parse --git-path agents-v0-onboard-commit-msg.txt)" && G . tag -a "onboard-v$2" -m "onboard approved"); }
lg_keep() { cp "$LG_LED" "$T1_TMP/lg-ledger.keep"; }
lg_back() { cp "$T1_TMP/lg-ledger.keep" "$LG_LED"; }
to_awaiting "$lg"; q "$lg" sh "$SFS" "$REP" --approve onboard
expect_pass "LT-0 ledger_ok passes before any gate commit, with no ledger" "$lg" sh "$GC" ledger_ok
out_has "LT-0 says why" "OK ledger_ok: no gate commit yet and no ledger"
expect_pass "LT-1 the gate commit chain runs (trailer written before the scan record)" "$lg" lg_gate "$lg" 1
lg_msg1="$(git -C "$lg" log -1 --format=%B onboard-v1)"
case "$lg_msg1" in *"Agents-V0-Ledger: lines=0 sha256=$LG_EMPTY"*) pass "LT-1 the first gate commit carries lines=0 and the empty-ledger sha256" ;;
  *) fail "LT-1 the first gate commit carries lines=0 and the empty-ledger sha256 (got: $lg_msg1)" ;; esac
is_eq "LT-1 the subject is unchanged" "$(git -C "$lg" log -1 --format=%s onboard-v1)" "onboarding: onboard approved"
if [ -f "$LG_LED" ] && [ ! -s "$LG_LED" ]; then pass "LT-1 the chain created the empty ledger"; else fail "LT-1 the chain created the empty ledger"; fi
expect_pass "LT-1 ledger_ok passes after the gate commit" "$lg" sh "$GC" ledger_ok
out_has "LT-1 names the anchor" "OK ledger_ok: the ledger matches the Agents-V0-Ledger trailer of onboard-v1 (lines=0)"
expect_pass "LT-1 gate_committed passes with the trailer" "$lg" sh "$GC" gate_committed onboard
# two docs-check failures appended (stand-in for the FAIL writer), then the next gate commit anchors them
printf 'FAIL docs check\nFAIL docs check\n' >> "$LG_LED"
expect_pass "LT-2 appended FAIL lines after the anchor pass" "$lg" sh "$GC" ledger_ok
printf '\nRevision.\n' >> "$lg/docs/agents-v0/architecture.md"
expect_pass "LT-2 the next gate commit chain runs" "$lg" lg_gate "$lg" 2
case "$(git -C "$lg" log -1 --format=%B onboard-v2)" in *"Agents-V0-Ledger: lines=2 sha256=$(lg_sha "$LG_LED")"*) pass "LT-2 the second gate commit anchors the two FAIL lines" ;;
  *) fail "LT-2 the second gate commit anchors the two FAIL lines" ;; esac
lg_keep; lg_head="$(git -C "$lg" rev-parse HEAD)"

# N81: the ledger is cut (fewer lines than the trailer recorded)
printf 'FAIL docs check\n' > "$LG_LED"
expect_fail "N81 ledger_ok refuses a ledger shorter than the recorded count" "$lg" sh "$GC" ledger_ok
out_has "N81 says ledger changed, ask the user" "REFUSED ledger_ok: ledger changed, ask the user (the ledger has 1 lines, fewer than the 2 that the gate commit onboard-v2 recorded)"
expect_fail "N81 prereq_approved refuses on the cut ledger" "$lg" sh "$GC" prereq_approved intake
out_has "N81 prereq_approved names the ledger" "REFUSED prereq_approved: ledger changed, ask the user"
expect_fail "N81 gate_committed refuses on the cut ledger" "$lg" sh "$GC" gate_committed onboard
out_has "N81 gate_committed names the ledger" "REFUSED gate_committed: ledger changed, ask the user"
printf '\nRevision 3.\n' >> "$lg/docs/agents-v0/architecture.md"
expect_fail "N81 the next gate commit chain refuses on the cut ledger" "$lg" lg_gate "$lg" 3
out_has "N81 staged_secret_scan names the ledger" "REFUSED staged_secret_scan: ledger changed, ask the user"
is_eq "N81 no gate commit was made" "$(git -C "$lg" rev-parse HEAD)" "$lg_head"
is_eq "N81 the cut ledger is left as found (nothing repaired)" "$(wc -l < "$LG_LED" | tr -d ' ')" "1"
lg_back

# N82: the ledger is deleted (moved away); never read as zero failures
mkdir -p "$T1_TMP/lg"; mv "$LG_LED" "$T1_TMP/lg/gate-ledger.moved"
expect_fail "N82 ledger_ok refuses a missing ledger once a gate commit exists" "$lg" sh "$GC" ledger_ok
out_has "N82 says ledger changed, ask the user" "REFUSED ledger_ok: ledger changed, ask the user (the ledger $LG_LED is missing, but the gate commit onboard-v2 recorded lines=2; a missing ledger never reads as zero failures; if this checkout is a fresh clone, the person (never an agent) copies gate-ledger"
expect_fail "N82 approval_evidence refuses on the missing ledger" "$lg" sh "$GC" approval_evidence onboard
out_has "N82 approval_evidence names the ledger" "REFUSED approval_evidence: ledger changed, ask the user"
expect_fail "N82 the next gate commit chain refuses on the missing ledger" "$lg" lg_gate "$lg" 3
if [ -e "$LG_LED" ]; then fail "N82 the chain does not recreate the ledger"; else pass "N82 the chain does not recreate the ledger"; fi
is_eq "N82 no gate commit was made" "$(git -C "$lg" rev-parse HEAD)" "$lg_head"
lg_back

# N83: an earlier line is edited (same length), or a FAIL line becomes blank
printf 'FAIL docs check\nFAIL edited\n' > "$LG_LED"
expect_fail "N83 ledger_ok refuses an edited earlier line" "$lg" sh "$GC" ledger_ok
out_has "N83 says ledger changed, ask the user" "REFUSED ledger_ok: ledger changed, ask the user (the first 2 lines of the ledger no longer match the sha256 that the gate commit onboard-v2 recorded (an earlier line was edited))"
printf 'FAIL docs check\n\n' > "$LG_LED"
expect_fail "N83 ledger_ok refuses a FAIL line turned blank" "$lg" sh "$GC" ledger_ok
out_has "N83 the blank line refusal" "REFUSED ledger_ok: ledger changed, ask the user (the first 2 lines"
expect_fail "N83 no_restart_without_reopen refuses on the edited ledger" "$lg" sh "$GC" no_restart_without_reopen
out_has "N83 no_restart_without_reopen names the ledger" "REFUSED no_restart_without_reopen: ledger changed, ask the user"
lg_back
# N83 (commit step): the ledger is edited after a clean scan; commit_msg_ok refuses, no commit
expect_pass "N83 setup: a clean scan" "$lg" sh -c "git add --all -- docs/agents-v0 && sh $GC staged_secret_scan"
printf 'FAIL docs check\nFAIL edited\n' > "$LG_LED"
expect_fail "N83 commit_msg_ok refuses once the ledger changed after the scan" "$lg" sh "$GC" commit_msg_ok
out_has "N83 commit_msg_ok names the ledger" "REFUSED commit_msg_ok: ledger changed, ask the user"
lg_back
expect_pass "N83 restored ledger: commit_msg_ok passes again" "$lg" sh "$GC" commit_msg_ok

# N80: appended lines since the anchor. A GRANT-USED line must name the grant file's line, once, with count= the
# FAIL lines before it; any other line fails closed.
lg_gl="grant 2026-11-02T06:00:00+08:00 phase=onboard reason=FAKE-retry by=FAKE-person"
lg_gh="$(printf '%s' "$lg_gl" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
printf 'GRANT-USED %s count=2\n' "$lg_gh" >> "$LG_LED"
expect_fail "N80 a GRANT-USED line with no grant file is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 names the missing grant" "REFUSED ledger_ok: ledger changed, ask the user (ledger line 3 is a GRANT-USED line, but there is no grant file ($LG_GRANT))"
printf '%s\n' "$lg_gl" > "$LG_GRANT"
expect_pass "N80 a GRANT-USED line naming the grant, once, with count=2 passes" "$lg" sh "$GC" ledger_ok
lg_back; printf 'GRANT-USED %s count=2\n' "0000000000000000000000000000000000000000000000000000000000000000" >> "$LG_LED"
expect_fail "N80 a GRANT-USED line naming another grant is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 names the wrong grant" "ledger line 3 is a GRANT-USED line that names no grant in $LG_GRANT"
lg_back; printf 'GRANT-USED %s count=0\n' "$lg_gh" >> "$LG_LED"
expect_fail "N80 a GRANT-USED line with the wrong count is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 names the count" "ledger line 3 says count=0, but the FAIL lines before it give 2"
lg_back; printf 'GRANT-USED %s count=2\nGRANT-USED %s count=2\n' "$lg_gh" "$lg_gh" >> "$LG_LED"
expect_fail "N80 a grant used twice is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 names the reuse" "ledger line 3 names a grant that another GRANT-USED line already used"
for lg_bad in "hello" "FAIL " "GRANT-USED abc count=1" "REOPEN-REFUSED" "fail docs check"; do
  lg_back; printf '%s\n' "$lg_bad" >> "$LG_LED"
  expect_fail "N80 a malformed appended line fails closed: '$lg_bad'" "$lg" sh "$GC" ledger_ok
  out_has "N80 names the malformed line ('$lg_bad')" "ledger line 3 is not a well-formed FAIL, GRANT-USED or REOPEN-REFUSED line"
done
lg_back; printf 'FAIL docs check' >> "$LG_LED"
expect_fail "N80 a last line with no newline fails closed" "$lg" sh "$GC" ledger_ok
out_has "N80 names the missing newline" "has no newline (every kit write ends in one)"
lg_back; printf 'REOPEN-REFUSED no valid grant\nFAIL docs check\n' >> "$LG_LED"
expect_pass "N80 appended REOPEN-REFUSED and FAIL lines pass" "$lg" sh "$GC" ledger_ok
# N80 second reopen: each reopen appends its own grant line; every GRANT-USED line is checked against the grant
# line that was in force when it was written, single use and the count rule unchanged
lg_g2="grant 2026-11-02T06:30:00+08:00 phase=onboard reason=FAKE-retry-two by=FAKE-person"
lg_h2="$(printf '%s' "$lg_g2" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
printf '%s\n%s\n' "$lg_gl" "$lg_g2" > "$LG_GRANT"
lg_back; printf 'FAIL docs check\nGRANT-USED %s count=3\nFAIL docs check\nGRANT-USED %s count=4\n' "$lg_gh" "$lg_h2" >> "$LG_LED"
expect_pass "N80 two reopens with different grants pass (the older GRANT-USED line keeps its grant)" "$lg" sh "$GC" ledger_ok
lg_back; printf 'GRANT-USED %s count=2\nGRANT-USED %s count=2\n' "$lg_h2" "$lg_h2" >> "$LG_LED"
expect_fail "N80 second reopen: the newer grant used twice is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 second reopen names the reuse" "ledger line 3 names a grant that another GRANT-USED line already used"
lg_back; printf 'GRANT-USED %s count=2\nGRANT-USED %s count=2\n' "$(printf '%064d' 7)" "$lg_h2" >> "$LG_LED"
expect_fail "N80 second reopen: a forged older grant hash is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 second reopen names the forged line" "ledger line 3 is a GRANT-USED line that names no grant in $LG_GRANT"
lacks "N80 (6) no overwritten hint on a forged hash" "$T1_TMP/out.txt" "overwritten"
lg_back; printf 'GRANT-USED %s count=1\nGRANT-USED %s count=2\n' "$lg_gh" "$lg_h2" >> "$LG_LED"
expect_fail "N80 second reopen: a wrong count on the older line is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 second reopen names the count" "ledger line 3 says count=1, but the FAIL lines before it give 2"
printf '%s\n' "$lg_g2" > "$LG_GRANT"; lg_back; printf 'GRANT-USED %s count=2\nGRANT-USED %s count=2\n' "$lg_gh" "$lg_h2" >> "$LG_LED"
expect_fail "N80 second reopen: an overwritten (not appended) grant file is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 second reopen says why" "(this line names a hash that is not a grant line here, or an earlier grant line is gone: the grant file was overwritten instead of appended, or a line was removed)"
# N80 (Iruka R1): a forged REOPEN-REFUSED grant= line with a hash that was never a grant line, before the one real
# grant line: the grant file is as the person wrote it, so the hint names the unknown hash first
printf '%s\n' "$lg_g2" > "$LG_GRANT"; lg_back; printf 'REOPEN-REFUSED grant=%s FAKE-forged refusal\nGRANT-USED %s count=2\n' "$(printf '%064d' 9)" "$lg_h2" >> "$LG_LED"
expect_fail "N80 R1 a forged REOPEN-REFUSED hash before the real grant is refused" "$lg" sh "$GC" ledger_ok
out_has "N80 R1 the hint names the unknown hash first" "ledger line 3 is a REOPEN-REFUSED line that names no grant in $LG_GRANT (this line names a hash that is not a grant line here, or an earlier grant line is gone"
lacks "N80 R1 the hint no longer opens with the overwrite alone" "$T1_TMP/out.txt" "(an earlier grant line is gone"
lg_back
mv "$LG_GRANT" "$T1_TMP/lg/reopen-grant.moved"

# ===== reopen_grant_ok (4A, N5A, 1A; design line 277 checklist) =================================================
# The last line of the grant file is the grant; it must be newer than the last gate (a grant line already in the file
# at a gate commit is named stale by that commit), unused, strictly formatted, CR-free, in a regular file; every
# earlier grant line is named in order by a ledger line (GRANT-USED or REOPEN-REFUSED grant=). Grant times are
# relative to now (the age rule is checked against the clock).
rg="$(onb_repo rg)"
RG_LED="$(cd "$rg" && cd "$(git rev-parse --git-common-dir)" && pwd)/agents-v0/gate-ledger"
RG_GRANT="${RG_LED%/gate-ledger}/reopen-grant"
mkdir -p "$T1_TMP/rg"
rg_t() { python3 -c 'import sys,datetime; print((datetime.datetime.now().astimezone()+datetime.timedelta(seconds=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
rg_line() { printf 'grant %s phase=%s reason="FAKE-why %s" by=FAKE-person' "$(rg_t "$1")" "${2:-onboard}" "$3"; }
rg_h() { printf '%s' "$1" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'; }
rg_last() { tail -n 1 "$RG_LED"; }
rg_run() { sh "$GC" reopen_grant_ok onboard; }
to_awaiting "$rg"; q "$rg" sh "$SFS" "$REP" --approve onboard
expect_pass "RG setup: the first gate commit" "$rg" lg_gate "$rg" 1
expect_pass "RG list: reopen_grant_ok is wired" "$rg" sh "$GC" list
out_has "RG list says wired" "reopen_grant_ok wired"
expect_fail "RG-0 no grant file is refused" "$rg" rg_run
out_has "RG-0 names the missing file" "REFUSED reopen_grant_ok: there is no grant file ($RG_GRANT)"
out_has "RG-0 (5) the grant command appends with >>" "phase=onboard reason=\\\"<why>\\\" by=<your-name>\" >> '$RG_GRANT'"
lacks "RG-0 (5) no overwrite command" "$T1_TMP/out.txt" "\" > '"
is_eq "RG-0 the refusal is a REOPEN-REFUSED ledger line" "$(rg_last)" "REOPEN-REFUSED there is no grant file ($RG_GRANT)"
expect_fail "RG-0 sync --reopen onboard is refused" "$rg" sh "$SFS" "$REP" --reopen onboard
out_has "RG-0 sync passes the reason on" "REFUSED reopen_grant_ok: there is no grant file"
printf 'FAIL docs check\nFAIL docs check\n' >> "$RG_LED"
rg_l1="$(rg_line 0 onboard one)"; printf '%s\n' "$rg_l1" > "$RG_GRANT"
expect_pass "RG-1 a fresh last grant line passes" "$rg" rg_run
out_has "RG-1 says why" "OK reopen_grant_ok: grant line 1 ("
is_eq "RG-1 GRANT-USED with count= every FAIL line" "$(rg_last)" "GRANT-USED $(rg_h "$rg_l1") count=2"
expect_pass "RG-1 ledger_ok passes after the use" "$rg" sh "$GC" ledger_ok
expect_fail "RG-2 a used grant is refused (single use)" "$rg" rg_run
out_has "RG-2 names the use" "REFUSED reopen_grant_ok: the last grant line (grant line 1) was already used (ledger line 5)"
# (1) only the last line may be used: an unused line before it refuses (and is named), then the last line passes
rg_l2="$(rg_line -5 onboard two)"; rg_l3="$(rg_line 0 onboard three)"; printf '%s\n%s\n' "$rg_l2" "$rg_l3" >> "$RG_GRANT"
expect_fail "RG-3 (1) an unused grant line before the last is refused" "$rg" rg_run
out_has "RG-3 names it" "grant line 2 is an unused grant line before the last one; only the last grant line may be used"
is_eq "RG-3 the refusal names that line" "$(rg_last | cut -c1-98)" "REOPEN-REFUSED grant=$(rg_h "$rg_l2") grant line 2"
expect_pass "RG-3 (1) the last line passes once the earlier one is named" "$rg" rg_run
is_eq "RG-3 the last line is the one used" "$(rg_last)" "GRANT-USED $(rg_h "$rg_l3") count=2"
cp "$RG_GRANT" "$T1_TMP/rg/grant.keep"
# (2) any change to earlier lines, used or unused, refuses; (6) the overwritten hint only on a removal
printf '%s\n%s\n%s\n' "$(rg_line 0 onboard one-edited)" "$rg_l2" "$rg_l3" > "$RG_GRANT"
expect_fail "RG-4 (2) an edited used line is refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 names the edited used line" "ledger line 5 is a GRANT-USED line that names no grant in $RG_GRANT"
lacks "RG-4 (6) no overwritten hint on an edit" "$T1_TMP/out.txt" "overwritten"
expect_fail "RG-4 reopen_grant_ok refuses ledger first" "$rg" rg_run
out_has "RG-4 says ledger changed" "REFUSED reopen_grant_ok: ledger changed, ask the user (ledger line 5 is a GRANT-USED line"
printf '%s\n%s\n%s\n' "$rg_l1" "$(rg_line 0 onboard two-edited)" "$rg_l3" > "$RG_GRANT"
expect_fail "RG-4 (2) an edited unused (refused) line is refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 names the edited unused line" "ledger line 7 is a REOPEN-REFUSED line that names no grant in $RG_GRANT"
lacks "RG-4 (6) no overwritten hint on the unused edit" "$T1_TMP/out.txt" "overwritten"
printf '%s\n%s\n' "$rg_l2" "$rg_l3" > "$RG_GRANT"
expect_fail "RG-4 (2) a removed used line is refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 (6) the removal shows the overwritten hint" "ledger line 5 is a GRANT-USED line that names no grant in $RG_GRANT (this line names a hash that is not a grant line here, or an earlier grant line is gone: the grant file was overwritten instead of appended, or a line was removed)"
printf '%s\n%s\n' "$rg_l1" "$rg_l3" > "$RG_GRANT"
expect_fail "RG-4 (2) a removed unused line is refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 (6) names it with the hint" "ledger line 7 is a REOPEN-REFUSED line that names no grant in $RG_GRANT (this line names a hash that is not a grant line here, or an earlier grant line is gone"
printf '%s\n%s\n%s\n' "$rg_l2" "$rg_l1" "$rg_l3" > "$RG_GRANT"
expect_fail "RG-4 (2) reordered lines are refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 names the order" "grant line 1 of $RG_GRANT is not the grant that ledger line 5 named (grant lines were reordered"
printf '%s\n%s\n%s\n' "$rg_l1" "$rg_l3" "$rg_l2" > "$RG_GRANT"
expect_fail "RG-4 (2) an unused line moved after the last used one is refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 names the moved line" "grant line 2 of $RG_GRANT is not the grant that ledger line 7 named"
: > "$RG_GRANT"
expect_fail "RG-4 an empty grant file is refused" "$rg" sh "$GC" ledger_ok
out_has "RG-4 (6) says empty" "ledger line 5 is a GRANT-USED line that names no grant in $RG_GRANT (the grant file is empty)"
lacks "RG-4 (6) no overwritten hint on an empty file" "$T1_TMP/out.txt" "overwritten"
cp "$T1_TMP/rg/grant.keep" "$RG_GRANT"
expect_pass "RG-4 the restored grant file passes" "$rg" sh "$GC" ledger_ok
# (1) newer than the last gate: a grant line in the file at a gate commit is named stale by it
rg_l4="$(rg_line 0 onboard four)"; printf '%s\n' "$rg_l4" >> "$RG_GRANT"
printf '\nRevision.\n' >> "$rg/docs/agents-v0/architecture.md"
expect_pass "RG-5 the next gate commit chain runs with an unused grant line" "$rg" lg_gate "$rg" 2
is_eq "RG-5 the gate commit named it stale" "$(rg_last)" "REOPEN-REFUSED grant=$(rg_h "$rg_l4") stale: in the grant file when the scan for gate commit onboard-v2 wrote its trailer; void unless that gate commit lands with this line in its trailer"
case "$(git -C "$rg" log -1 --format=%B onboard-v2)" in *"Agents-V0-Ledger: lines=$(wc -l < "$RG_LED" | tr -d ' ') sha256=$(lg_sha "$RG_LED")"*) pass "RG-5 the gate trailer anchors the stale line" ;;
  *) fail "RG-5 the gate trailer anchors the stale line" ;; esac
expect_fail "RG-5 (1) the stale pre-gate grant is refused" "$rg" rg_run
out_has "RG-5 names the stale grant" "the last grant line (grant line 4) was already refused or went stale at a landed gate commit"
printf '%s\n' "$(rg_line -3600 onboard five)" >> "$RG_GRANT"
expect_fail "RG-6 (1) a grant dated before the last gate commit is refused" "$rg" rg_run
out_has "RG-6 names the gate" "is older than the last gate commit onboard-v2; a grant must be newer than the last gate"
printf '%s\n' "$(rg_line 3600 onboard six)" >> "$RG_GRANT"
expect_fail "RG-7 a grant dated in the future is refused" "$rg" rg_run
out_has "RG-7 says future" "grant line 6 is dated in the future"
printf '%s\n' "$(rg_line -90000 onboard seven)" >> "$RG_GRANT"
expect_fail "RG-8 a grant older than grant_max_age_seconds is refused" "$rg" rg_run
out_has "RG-8 names the rule" "older than gate-rules grant_max_age_seconds (86400)"
printf '%s\n' "$(rg_line 0 design eight)" >> "$RG_GRANT"
expect_fail "RG-9 a grant for another phase is refused" "$rg" rg_run
out_has "RG-9 names the phase" "grant line 8 grants phase=design, not onboard"
# (3) CRLF: refused, never stripped
rg_cr="$(rg_line 0 onboard nine)"; printf '%s\r\n' "$rg_cr" >> "$RG_GRANT"
expect_fail "RG-10 (3) a CRLF grant line is refused" "$rg" rg_run
out_has "RG-10 says carriage return" "grant line 9 holds a carriage return (a CRLF line ending, as some editors write); the kit refuses it rather than strip it"
is_eq "RG-10 the refusal names the line with its CR (not stripped)" "$(rg_last | cut -c1-85)" "REOPEN-REFUSED grant=$(printf '%s\r' "$rg_cr" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
# (5) strict format
rg_n=9
for rg_bad in "grant $(rg_t 0)" "grant $(rg_t 0) phase=onboard reason=\"FAKE why\" by=FAKE-person extra" \
  "grant  $(rg_t 0) phase=onboard reason=FAKE by=FAKE" "Grant $(rg_t 0) phase=onboard reason=FAKE by=FAKE" \
  "grant 2026-13-02T06:00:00+08:00 phase=onboard reason=FAKE by=FAKE" "grant $(rg_t 0 | cut -c1-19) phase=onboard reason=FAKE by=FAKE" \
  "grant $(rg_t 0) phase=onboard reason=\"FAKE by=FAKE" "grant $(rg_t 0) phase=onboard reason=FAKE	by=FAKE"; do
  rg_n=$((rg_n + 1)); printf '%s\n' "$rg_bad" >> "$RG_GRANT"
  expect_fail "RG-11 (5) a malformed grant line is refused: '$rg_bad'" "$rg" rg_run
  out_has "RG-11 names line $rg_n as malformed" "grant line $rg_n is not a well-formed grant line (it must read exactly: grant <YYYY-MM-DDTHH:MM:SS+HH:MM> phase=<phase> reason=\"<text>\" by=<name>)"
done
expect_pass "RG-11 every refused line is named: ledger_ok passes" "$rg" sh "$GC" ledger_ok
# (4) a symlink grant file is refused
mv "$RG_GRANT" "$T1_TMP/rg/grant.real"; ln -s "$T1_TMP/rg/grant.real" "$RG_GRANT"
expect_fail "RG-12 (4) ledger_ok refuses a symlink grant file" "$rg" sh "$GC" ledger_ok
out_has "RG-12 names the symlink" "the grant file $RG_GRANT is a symlink; it must be a regular file that the person appends to"
expect_fail "RG-12 (4) reopen_grant_ok refuses a symlink grant file" "$rg" rg_run
out_has "RG-12 reopen names the symlink" "REFUSED reopen_grant_ok: ledger changed, ask the user (the grant file $RG_GRANT is a symlink"
mv "$RG_GRANT" "$T1_TMP/rg/grant.symlink"; mv "$T1_TMP/rg/grant.real" "$RG_GRANT"
# a last line with no newline is refused unnamed; the person ends it, appends a new grant, and the next run names it
printf '%s' "$(rg_line 0 onboard partial)" >> "$RG_GRANT"
expect_fail "RG-13 a last grant line with no newline is refused" "$rg" rg_run
out_has "RG-13 says no newline" "has no newline, so it was not written whole by the printf command"
out_has "RG-13 tells the person to end it" "The person first ends it with: printf '\\n' >> '$RG_GRANT'"
case "$(rg_last)" in "REOPEN-REFUSED the last grant line"*) pass "RG-13 the refusal does not name the partial line" ;; *) fail "RG-13 the refusal does not name the partial line ($(rg_last))" ;; esac
printf '\n' >> "$RG_GRANT"
rg_l5="grant $(python3 -c 'import datetime; print(datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"))') phase=onboard reason=FAKE-ten by=\"FAKE person\""
printf '%s\n' "$rg_l5" >> "$RG_GRANT"
expect_fail "RG-13 the ended line is named first" "$rg" rg_run
out_has "RG-13 names the ended line" "is an unused grant line before the last one"
printf 'FAIL docs check\n' >> "$RG_LED"
expect_pass "RG-14 a +HHMM time, unquoted reason and quoted by pass" "$rg" rg_run
is_eq "RG-14 count= every FAIL line in the ledger" "$(rg_last)" "GRANT-USED $(rg_h "$rg_l5") count=3"
expect_pass "RG-14 ledger_ok passes" "$rg" sh "$GC" ledger_ok
# a grant line that is in git history is refused
rg_l6="$(rg_line 0 onboard eleven)"; printf '%s\n' "$rg_l6" >> "$RG_GRANT"; printf '%s\n' "$rg_l6" > "$rg/FAKE-grant.txt"
q "$rg" G . add FAKE-grant.txt; q "$rg" lg_env git commit -q -m "FAKE grant in history"
expect_fail "RG-15 a grant line in git history is refused" "$rg" rg_run
out_has "RG-15 names git history" "grant line 20 is in git history (commit"
expect_fail "RG-16 another phase is not wired yet" "$rg" sh "$GC" reopen_grant_ok design
out_has "RG-16 not wired" "NOT-WIRED reopen_grant_ok:"
# RS (round 14, Iruka): a stale mark counts only when a landed gate commit's trailer pins it. A refused scan, or a
# passing scan with no commit, never uses up a fresh grant; a real gate commit still makes an older grant stale.
rs_scan() { sh "$GC" staged_secret_scan; }
rs_g1="$(rg_line 0 onboard rs-one)"; printf '%s\n' "$rs_g1" >> "$RG_GRANT"
expect_fail "RS-1 staged_secret_scan with nothing staged is refused" "$rg" rs_scan
out_has "RS-1 says nothing staged" "REFUSED staged_secret_scan: nothing is staged"
expect_pass "RS-1 (Iruka repro) the fresh grant is still usable after the refused scan" "$rg" rg_run
is_eq "RS-1 it is the one used" "$(rg_last)" "GRANT-USED $(rg_h "$rs_g1") count=3"
rs_g2="$(rg_line 0 onboard rs-two)"; printf '%s\n' "$rs_g2" >> "$RG_GRANT"
printf '\nRevision RS.\n' >> "$rg/docs/agents-v0/architecture.md"; q "$rg" G . add -- docs/agents-v0
expect_pass "RS-2 a passing scan (no commit follows)" "$rg" rs_scan
expect_pass "RS-2 the grant is still usable after a passing scan with no commit" "$rg" rg_run
is_eq "RS-2 it is the one used" "$(rg_last)" "GRANT-USED $(rg_h "$rs_g2") count=3"
expect_fail "RS-2 commit_msg_ok refuses the old scan once the ledger grew (no stale mark pinned after its use)" "$rg" sh "$GC" commit_msg_ok
out_has "RS-2 says rescan" "no longer matches the ledger"
rs_g3="$(rg_line 0 onboard rs-three)"; printf '%s\n' "$rs_g3" >> "$RG_GRANT"
printf 'aws_access_key_id = AKIA%s\n' "$(printf 'FAKE%.0s' 1 2 3 4)" > "$rg/docs/agents-v0/rs-fake-note.md"; q "$rg" G . add -- docs/agents-v0
expect_fail "RS-3 a secret hit refuses the scan" "$rg" rs_scan
out_has "RS-3 the scanner refused" "REFUSED staged_secret_scan: secret_scan.py exited 1"
expect_pass "RS-3 the grant is still usable after the refused secret scan" "$rg" rg_run
is_eq "RS-3 it is the one used" "$(rg_last)" "GRANT-USED $(rg_h "$rs_g3") count=3"
q "$rg" G . restore --staged -- docs/agents-v0/rs-fake-note.md; mv "$rg/docs/agents-v0/rs-fake-note.md" "$T1_TMP/rg/"
rs_g4="$(rg_line 0 onboard rs-four)"; printf '%s\n' "$rs_g4" >> "$RG_GRANT"
expect_pass "RS-4 a passing scan leaves a void stale mark" "$rg" rs_scan
expect_pass "RS-4 (regression) the real gate commit chain runs" "$rg" lg_gate "$rg" 3
expect_fail "RS-4 (regression) the grant in the file at onboard-v3 is refused after it" "$rg" rg_run
out_has "RS-4 names it stale" "the last grant line (grant line 24) was already refused or went stale at a landed gate commit"
expect_pass "RS-4 ledger_ok passes (both stale marks pinned by onboard-v3)" "$rg" sh "$GC" ledger_ok
printf '%s\n' "$(rg_line 300 onboard rs-skew-far)" >> "$RG_GRANT"
expect_fail "RS-5 a grant 300s ahead (beyond the 120s skew) is refused" "$rg" rg_run
out_has "RS-5 says future" "grant line 25 is dated in the future"
rs_g6="$(rg_line 60 onboard rs-skew-near)"; printf '%s\n' "$rs_g6" >> "$RG_GRANT"
expect_pass "RS-5 a grant 60s ahead (within the 120s skew) passes" "$rg" rg_run
is_eq "RS-5 it is the one used" "$(rg_last)" "GRANT-USED $(rg_h "$rs_g6") count=3"
# RV (round 15, Iruka): a void stale line already at the end of the ledger would join the run the next gate commit
# pins. The scan checks the ledger as that commit would leave it and refuses before writing anything.
rv_keep="$T1_TMP/rg/rv-ledger.keep"; cp "$RG_LED" "$rv_keep"
printf 'REOPEN-REFUSED grant=%s stale: in the grant file when the scan for gate commit onboard-v4 wrote its trailer; void\n' "$(rg_h FAKE-not-a-grant-line)" >> "$RG_LED"
printf '%s\n' "$(rg_line 0 onboard rv-one)" >> "$RG_GRANT"
printf '\nRevision RV.\n' >> "$rg/docs/agents-v0/architecture.md"
expect_fail "RV-1 (Iruka repro) the chain stops when a void stale line names no grant" "$rg" lg_gate "$rg" 4
out_has "RV-1 says why, before writing" "nothing was written: with the trailer of gate commit onboard-v4 the ledger would read as refused: ledger line"
is_eq "RV-1 no line was written" "$(wc -l < "$RG_LED" | tr -d ' ')" "$(($(wc -l < "$rv_keep" | tr -d ' ') + 1))"
is_eq "RV-1 no gate commit landed" "$(git -C "$rg" tag -l onboard-v4)" ""
cp "$rv_keep" "$RG_LED"; printf 'REOPEN-REFUSED grant=%s stale: forged\n' "$(rg_h "$rs_g6")" >> "$RG_LED"
expect_fail "RV-2 the chain stops when a void stale line names a used grant" "$rg" lg_gate "$rg" 4
out_has "RV-2 names the pinned clash" "also names, and the stale one is pinned by a gate commit"
cp "$rv_keep" "$RG_LED"
expect_pass "RV-3 with the stray line gone the chain lands" "$rg" lg_gate "$rg" 4
expect_pass "RV-3 ledger_ok passes after it" "$rg" sh "$GC" ledger_ok
# RN (round 15, Yamato): the anchor is the newest gate commit (the highest onboard-v<n>, as the reopen time check
# uses), also when two gate commits record the same line count; a newer gate recording fewer lines is refused.
printf '\nRevision RN.\n' >> "$rg/docs/agents-v0/architecture.md"
expect_pass "RN-1 a gate commit with no ledger change lands" "$rg" lg_gate "$rg" 5
is_eq "RN-1 it records the same count as onboard-v4" "$(git -C "$rg" log -1 --format=%B onboard-v5 | sed -n 's/^Agents-V0-Ledger: lines=\([0-9]*\) .*/\1/p')" "$(git -C "$rg" log -1 --format=%B onboard-v4 | sed -n 's/^Agents-V0-Ledger: lines=\([0-9]*\) .*/\1/p')"
expect_pass "RN-1 ledger_ok passes" "$rg" sh "$GC" ledger_ok
out_has "RN-1 it names the newest gate commit" "the Agents-V0-Ledger trailer of onboard-v5 (lines="
q "$rg" G . tag -a onboard-v6 -m "onboard approved" onboard-v2
expect_fail "RN-2 a newer gate commit that records fewer lines is refused" "$rg" sh "$GC" ledger_ok
out_has "RN-2 says why" "the gate commit onboard-v6 recorded lines="

# N84: unattended turns. The harness marks the ledger before a turn and compares after it.
expect_pass "N84 ledger_mark prints the mark" "$lg" sh "$GC" ledger_mark
lg_mark="$(cat "$T1_TMP/out.txt")"
is_eq "N84 the mark is lines and sha256" "$lg_mark" "lines=2 sha256=$(lg_sha "$LG_LED")"
printf 'FAIL docs check\nREOPEN-REFUSED no valid grant\n' >> "$LG_LED"
expect_pass "N84 one FAIL and one REOPEN-REFUSED the harness saw pass" "$lg" sh "$GC" ledger_turn_ok "$lg_mark" 1 1
expect_fail "N84 lines the harness did not see stop the run" "$lg" sh "$GC" ledger_turn_ok "$lg_mark" 0 1
out_has "N84 names the count" "REFUSED ledger_turn_ok: ledger changed during the unattended turn, stop the run and ask the user (the turn appended 1 FAIL and 1 REOPEN-REFUSED line(s), but the harness saw 0 docs-check failure(s) and 1 refused --reopen run(s))"
lg_back; printf 'GRANT-USED %s count=2\n' "$lg_gh" >> "$LG_LED"
expect_fail "N84 a GRANT-USED line in an unattended turn stops the run" "$lg" sh "$GC" ledger_turn_ok "$lg_mark" 0 0
out_has "N84 names the grant use" "is a GRANT-USED line appended during an unattended turn (grants are never used unattended)"
printf 'FAIL docs check\n' > "$LG_LED"
expect_fail "N84 a cut during the turn stops the run" "$lg" sh "$GC" ledger_turn_ok "$lg_mark" 0 0
out_has "N84 names the cut" "the ledger was cut during the turn (1 lines, it had 2)"
printf 'FAIL docs check\nFAIL edited\n' > "$LG_LED"
expect_fail "N84 an edit during the turn stops the run" "$lg" sh "$GC" ledger_turn_ok "$lg_mark" 0 0
out_has "N84 names the edit" "the first 2 lines of the ledger changed during the turn"
mv "$LG_LED" "$T1_TMP/lg/gate-ledger.moved2"
expect_fail "N84 a deleted ledger stops the run" "$lg" sh "$GC" ledger_turn_ok "$lg_mark" 0 0
out_has "N84 names the delete" "the ledger was deleted during the turn (it had 2 lines)"
expect_pass "N84 an absent ledger marks absent" "$lg" sh "$GC" ledger_mark
out_has "N84 absent mark" "absent"
expect_pass "N84 absent before and after with no runs passes" "$lg" sh "$GC" ledger_turn_ok absent 0 0
(cd "$lg" && sh "$GC" ledger_turn_ok "lines=x" 0 0) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
is_eq "N84 a bad mark is a usage error (exit 2)" "$rc" 2
lg_back

# N3A trailer shape on the gate commits: a tag on a commit with no trailer, or a malformed one, refuses
q "$lg" G . commit -q --allow-empty -m "onboarding: onboard approved (no trailer)"
q "$lg" G . tag -a onboard-v3 -m "onboard approved"
expect_fail "N83 a gate commit with no trailer is refused" "$lg" sh "$GC" ledger_ok
out_has "N83 names the missing trailer" "REFUSED ledger_ok: ledger changed, ask the user (the gate commit onboard-v3 ("
out_has "N83 no trailer" "has no Agents-V0-Ledger trailer; if this repo's onboard-v<n> tags were made before the kit kept the gate ledger"
q "$lg" G . commit -q --allow-empty -m "onboarding: onboard approved" -m "Agents-V0-Ledger: lines=two sha256=$LG_EMPTY"
q "$lg" G . tag -f -a onboard-v3 -m "onboard approved"
expect_fail "N83 a gate commit with a malformed trailer is refused" "$lg" sh "$GC" ledger_ok
out_has "N83 names the malformed trailer" "has a malformed Agents-V0-Ledger trailer)"

# list reports the wired checks
# GF-n (5A, N2A, E31; round 15): greenfield_record_ok and the greenfield root trailer. gf_root <name> <trailer|->
# <record json>: a new repo whose root commit holds the installed kit and the record ("-": no trailer), with the
# empty ledger greenfield_trailer creates.
GFR=".agents-v0/greenfield-record.json"
GFJ='{"kind": "greenfield", "bootstrapAt": "2026-11-02T08:00:00+08:00", "kitSha": "0123456789ab"}'
gf_root() {
  r_="$(t1_repo "$1")"; t1_install "$r_" || { fail "install.sh into $1"; return 1; }
  q "$r_" sh "$GC" greenfield_trailer; printf '%s\n' "$3" > "$r_/$GFR"; G "$r_" add -A >/dev/null
  if [ "$2" = - ]; then G "$r_" commit -qm "bootstrap"; else G "$r_" commit -qm "bootstrap

$2"; fi
}
# expect_rc <desc> <rc> <dir> <command...>
expect_rc() { d_="$1"; w_rc="$2"; w_="$3"; shift 3; g_rc=0; (cd "$w_" && "$@") > "$T1_TMP/out.txt" 2>&1 || g_rc=$?
  if [ "$g_rc" = "$w_rc" ]; then pass "$d_"; else fail "$d_ (exit $g_rc, want $w_rc)"; fi; }
gq="$(t1_repo gf-ok)"; t1_install "$gq" || fail "install.sh into gf-ok"
expect_pass "GF-1 greenfield_trailer runs before the root commit" "$gq" sh "$GC" greenfield_trailer
gf_tr="$(cat "$T1_TMP/out.txt")"
is_eq "GF-1 it prints the empty-ledger trailer" "$gf_tr" "Agents-V0-Ledger: lines=0 sha256=$(printf '' | sha256sum | cut -d' ' -f1)"
is_eq "GF-1 it creates the empty ledger" "$(wc -c < "$gq/.git/agents-v0/gate-ledger" | tr -d ' ')" "0"
printf '%s\n' "$GFJ" > "$gq/$GFR"; G "$gq" add -A >/dev/null; G "$gq" commit -qm "bootstrap

$gf_tr"
expect_pass "GF-2 a valid record in the only root commit passes" "$gq" sh "$GC" greenfield_record_ok
out_has "GF-2 says greenfield" "OK greenfield_record_ok: greenfield: $GFR was added by the only root commit"
expect_pass "GF-2 ledger_ok anchors on the root trailer" "$gq" sh "$GC" ledger_ok
out_has "GF-2 names the root commit" "trailer of the greenfield root commit"
expect_fail "GF-3 greenfield_trailer refuses once HEAD has a commit" "$gq" sh "$GC" greenfield_trailer
out_has "GF-3 says why" "HEAD already has a commit"
printf ' \n' >> "$gq/$GFR"
expect_rc "GF-4 an edited work-tree copy is refused" 1 "$gq" sh "$GC" greenfield_record_ok
out_has "GF-4 asks the user" "REFUSED greenfield_record_ok: record changed, ask the user ($GFR in the work tree differs"
G "$gq" checkout -q -- "$GFR"
G "$gq" checkout -q -b gf-moved; G "$gq" mv "$GFR" .agents-v0/moved.json; G "$gq" commit -qm moved
expect_rc "GF-5 a record missing at HEAD is refused" 1 "$gq" sh "$GC" greenfield_record_ok
out_has "GF-5 says missing" "is missing at HEAD or differs from the root commit"
G "$gq" checkout -q main
mv "$gq/.git/agents-v0/gate-ledger" "$T1_TMP/gf-ledger.keep"
expect_fail "GF-6 a missing ledger under the root trailer is refused" "$gq" sh "$GC" ledger_ok
out_has "GF-6 never reads as empty" "the ledger $gq/.git/agents-v0/gate-ledger is missing, but the greenfield root commit $(git -C "$gq" rev-list --max-parents=0 HEAD | cut -c1-12) recorded lines=0"
lacks "GF-6 the root anchor is not called a gate commit" "$T1_TMP/out.txt" "the gate commit the greenfield"
mv "$T1_TMP/gf-ledger.keep" "$gq/.git/agents-v0/gate-ledger"
gb="$(t1_repo gf-brown --commit)"; t1_install "$gb" || fail "install.sh into gf-brown"
G "$gb" add -A >/dev/null; G "$gb" commit -qm installed
expect_rc "GF-7 no record: NONE, the content rule decides" 4 "$gb" sh "$GC" greenfield_record_ok
out_has "GF-7 says why" "NONE greenfield_record_ok: no greenfield record"
G "$gq" checkout -q -b gf-merged; G "$gq" fetch -q "$gb" main; G "$gq" merge -q --no-edit -X ours --allow-unrelated-histories FETCH_HEAD
expect_rc "GF-8 two root commits (E31): NONE" 4 "$gq" sh "$GC" greenfield_record_ok
out_has "GF-8 names the roots" "the repo has 2 root commits"
G "$gq" checkout -q main
printf '%s\n' "$GFJ" > "$gb/$GFR"
expect_rc "GF-9 an untracked copy is refused" 1 "$gb" sh "$GC" greenfield_record_ok
out_has "GF-9 says not committed by a root" "a copy that no root commit added"
G "$gb" add "$GFR"; G "$gb" commit -qm "record later"
expect_rc "GF-9 a record added after the root commit is refused" 1 "$gb" sh "$GC" greenfield_record_ok
out_has "GF-9 names the commit" "not by the root commit"
gf_root gf-extra "$gf_tr" '{"kind": "greenfield", "bootstrapAt": "2026-11-02T08:00:00+08:00", "kitSha": "0123456789ab", "rootSha": "0123456789ab"}'
expect_rc "GF-10 a record with another field is refused" 1 "$T1_TMP/gf-extra" sh "$GC" greenfield_record_ok
out_has "GF-10 names the keys" "must hold exactly the keys kind, bootstrapAt and kitSha"
gf_root gf-notr - "$GFJ"
expect_fail "GF-11 a root commit with the record and no trailer is refused" "$T1_TMP/gf-notr" sh "$GC" ledger_ok
out_has "GF-11 names the root" "the greenfield root commit"
out_has "GF-11 no trailer" "has no Agents-V0-Ledger trailer"
gf_root gf-one "Agents-V0-Ledger: lines=1 sha256=$(printf 'FAIL\n' | sha256sum | cut -d' ' -f1)" "$GFJ"
printf 'FAIL\n' > "$T1_TMP/gf-one/.git/agents-v0/gate-ledger"
expect_fail "GF-11 a root trailer other than lines=0 is refused" "$T1_TMP/gf-one" sh "$GC" greenfield_record_ok
out_has "GF-11 says lines=0" "must record lines=0 sha256="
# FC-n (round 17, fresh-clone option A; handoff note sai-step0-gate-checks-handoff-20261102.md lines 739-834): the
# ledger and the grant file live in the git common dir, so `git clone` copies neither. ledger_ok keeps refusing the
# missing ledger, and the refusal now says how the person starts it: copy gate-ledger and reopen-grant from the
# original checkout, or (a greenfield clone with only the root anchor, no onboard-v<n> tag) create the empty ledger.
# Nothing in the kit copies or creates them; the copies below stand in for the person's own terminal.
fc_dir() { printf '%s/agents-v0\n' "$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd)"; }
fo="$(onb_repo fc-orig)"
FO_LED="$(fc_dir "$fo")/gate-ledger"; FO_GRANT="$(fc_dir "$fo")/reopen-grant"
to_awaiting "$fo"; q "$fo" sh "$SFS" "$REP" --approve onboard
expect_pass "FC setup: the first gate commit chain runs in the original checkout" "$fo" lg_gate "$fo" 1
fc_gl1="grant 2026-11-02T06:00:00+08:00 phase=onboard reason=FAKE-retry by=FAKE-person"
fc_gl2="grant 2026-11-02T07:00:00+08:00 phase=onboard reason=FAKE-again by=FAKE-person"
fc_h1="$(rg_h "$fc_gl1")"; fc_h2="$(rg_h "$fc_gl2")"
printf 'FAIL docs check\nFAIL docs check\nGRANT-USED %s count=2\n' "$fc_h1" >> "$FO_LED"
printf '%s\n' "$fc_gl1" > "$FO_GRANT"
printf '\nRevision.\n' >> "$fo/docs/agents-v0/architecture.md"
expect_pass "FC setup: the second gate commit anchors two FAIL lines and a GRANT-USED line" "$fo" lg_gate "$fo" 2
# after the newest anchor (onboard-v2, lines=3): one more FAIL and a second reopen, not anchored by any gate yet
printf 'FAIL docs check\nGRANT-USED %s count=3\n' "$fc_h2" >> "$FO_LED"; printf '%s\n' "$fc_gl2" >> "$FO_GRANT"
expect_pass "FC setup: the original checkout's ledger passes" "$fo" sh "$GC" ledger_ok
fc="$T1_TMP/fc-clone"; git clone -q "$fo" "$fc"
FC_LED="$(fc_dir "$fc")/gate-ledger"; FC_GRANT="$(fc_dir "$fc")/reopen-grant"
if [ -e "${FC_LED%/gate-ledger}" ]; then fail "FC-1 a fresh clone has no ledger and no grant file"; else pass "FC-1 a fresh clone has no ledger and no grant file"; fi
expect_fail "FC-1 ledger_ok refuses the fresh clone's missing ledger" "$fc" sh "$GC" ledger_ok
out_has "FC-1 keeps the missing-ledger refusal" "REFUSED ledger_ok: ledger changed, ask the user (the ledger $FC_LED is missing, but the gate commit onboard-v2 recorded lines=3; a missing ledger never reads as zero failures; "
out_has "FC-1 the hint says to copy both files from the original checkout" "if this checkout is a fresh clone, the person (never an agent) copies gate-ledger and, when it exists, reopen-grant from the original checkout's git common dir (agents-v0/;"
out_has "FC-1 the hint names this checkout's ledger and grant paths" "to $FC_LED and $FC_GRANT"
out_has "FC-1 the hint names the paths command" "sh .agents-v0/scripts/gate-checks.sh paths"
out_has "FC-1 (round 18, Iruka F2/F3) the hint says when to copy" "copies them only after every pending (unused) grant line in the original's reopen-grant has been used or refused there (a pending grant copied into the clone could be used once in each checkout; a grant used before the copy is refused as already used)"
out_has "FC-1 the hint states the stuck state" "if the original checkout is gone, stop and tell the user"
lacks "FC-1 no create-empty hint once an onboard-v<n> tag exists" "$T1_TMP/out.txt" "creates the empty ledger"
if [ -e "${FC_LED%/gate-ledger}" ]; then fail "FC-1 the refusal creates nothing"; else pass "FC-1 the refusal creates nothing"; fi
expect_fail "FC-1 gate_committed refuses the same way" "$fc" sh "$GC" gate_committed onboard
out_has "FC-1 gate_committed carries the hint" "REFUSED gate_committed: ledger changed, ask the user (the ledger $FC_LED is missing"
# FC-2: the person copies both files from the original checkout
mkdir -p "${FC_LED%/gate-ledger}"; cp "$FO_LED" "$FC_LED"; cp "$FO_GRANT" "$FC_GRANT"
expect_pass "FC-2 the person's copy of the ledger and the grant file passes" "$fc" sh "$GC" ledger_ok
out_has "FC-2 names the newest anchor" "OK ledger_ok: the ledger matches the Agents-V0-Ledger trailer of onboard-v2 (lines=3)"
is_eq "FC-2 the original checkout's ledger is unchanged" "$(lg_sha "$FO_LED")" "$(lg_sha "$FC_LED")"
# FC-3: the ledger copied without the grant file
mv "$FC_GRANT" "$T1_TMP/fc-grant.moved"
expect_fail "FC-3 a ledger copied without the grant file is refused" "$fc" sh "$GC" ledger_ok
out_has "FC-3 names the missing grant file" "ledger line 3 is a GRANT-USED line, but there is no grant file ($FC_GRANT)"
mv "$T1_TMP/fc-grant.moved" "$FC_GRANT"
# FC-4: a cut copy
head -n 2 "$FO_LED" > "$FC_LED"
expect_fail "FC-4 a copy shorter than the newest anchor is refused" "$fc" sh "$GC" ledger_ok
out_has "FC-4 names the count" "the ledger has 2 lines, fewer than the 3 that the gate commit onboard-v2 recorded"
# FC-5: a ledger from another repo (same length, other lines)
printf 'FAIL other repo\nFAIL other repo\nFAIL other repo\n' > "$FC_LED"
expect_fail "FC-5 a ledger copied from another repo is refused" "$fc" sh "$GC" ledger_ok
out_has "FC-5 names the hash" "the first 3 lines of the ledger no longer match the sha256 that the gate commit onboard-v2 recorded"
# FC-6 (Jiraiya; known gap 1): a copy that keeps only the anchored lines drops the FAIL and the GRANT-USED line
# written after onboard-v2, and passes; the second grant line is then the unnamed last line again in the clone.
head -n 3 "$FO_LED" > "$FC_LED"
expect_pass "FC-6 known gap 1: a copy that drops the GRANT-USED line written after the newest anchor passes" "$fc" sh "$GC" ledger_ok
out_has "FC-6 it passes on the anchored lines alone" "OK ledger_ok: the ledger matches the Agents-V0-Ledger trailer of onboard-v2 (lines=3)"
# FC-8 (round 18, Iruka F2/F3): copy only after every pending grant was used or refused in the original. A full
# copy made after grant 2 was used there (its GRANT-USED line is in the copy) cannot use grant 2 again.
cp "$FO_LED" "$FC_LED"; cp "$FO_GRANT" "$FC_GRANT"
expect_rc "FC-8 a copy made after the original used grant 2 refuses it in the clone" 1 "$fc" sh "$GC" reopen_grant_ok onboard
out_has "FC-8 names the use" "REFUSED reopen_grant_ok: the last grant line (grant line 2) was already used (ledger line 5)"
expect_pass "FC-8 the original checkout's ledger still passes" "$fo" sh "$GC" ledger_ok
# FC-7 (Iruka): a greenfield clone with only the root anchor; the empty ledger passes until an onboard-v<n> tag exists
gf_root fc-gf "$gf_tr" "$GFJ"; gfo="$T1_TMP/fc-gf"
gfc="$T1_TMP/fc-gf-clone"; git clone -q "$gfo" "$gfc"
GFC_LED="$(fc_dir "$gfc")/gate-ledger"
expect_fail "FC-7 a root-anchor-only clone refuses the missing ledger" "$gfc" sh "$GC" ledger_ok
out_has "FC-7 keeps the refusal" "the ledger $GFC_LED is missing, but the greenfield root commit $(git -C "$gfc" rev-list --max-parents=0 HEAD | cut -c1-12) recorded lines=0"
lacks "FC-7 the root anchor is not called a gate commit" "$T1_TMP/out.txt" "the gate commit the greenfield"
out_has "FC-7 the hint says to create the empty ledger" "if this checkout is a fresh clone of a greenfield repo with no onboard-v<n> tag yet, the person (never an agent) creates the empty ledger file $GFC_LED"
lacks "FC-7 no stuck-state line while the root anchor alone applies" "$T1_TMP/out.txt" "if the original checkout is gone"
mkdir -p "${GFC_LED%/gate-ledger}"; : > "$GFC_LED"
expect_pass "FC-7 the person's empty ledger passes under the root anchor alone" "$gfc" sh "$GC" ledger_ok
out_has "FC-7 names the root anchor" "trailer of the greenfield root commit"
gfu="$T1_TMP/fc-gf-unreach"; git clone -q "$gfo" "$gfu"; GFU_LED="$(fc_dir "$gfu")/gate-ledger"
mkdir -p "${GFU_LED%/gate-ledger}"; : > "$GFU_LED"
printf 'FAIL docs check\n' >> "$(fc_dir "$gfo")/gate-ledger"; printf 'gate\n' > "$gfo/gate.txt"; G "$gfo" add gate.txt
G "$gfo" commit -qm "onboarding: onboard approved

$(lt_trailer "$gfo")"; G "$gfo" tag -a onboard-v1 -m "onboard approved"
expect_pass "FC-7 setup: the original passes with its first gate (lines=1)" "$gfo" sh "$GC" ledger_ok
G "$gfc" fetch -q --tags origin; G "$gfc" merge -q --ff-only origin/main
expect_fail "FC-7 the empty ledger is refused once an onboard-v<n> tag exists" "$gfc" sh "$GC" ledger_ok
out_has "FC-7 names the tag" "the ledger has 0 lines, fewer than the 1 that the gate commit onboard-v1 recorded"
# FC-7 (round 18, Iruka G3): the tag fetched but its commit not reachable from HEAD (no merge) still refuses
G "$gfu" fetch -q --tags origin
if git -C "$gfu" merge-base --is-ancestor onboard-v1 HEAD; then fail "FC-7 G3 setup: onboard-v1 is not reachable from HEAD"; else pass "FC-7 G3 setup: onboard-v1 is not reachable from HEAD"; fi
expect_rc "FC-7 G3 a fetched tag whose commit HEAD does not reach still refuses the empty ledger" 1 "$gfu" sh "$GC" ledger_ok
out_has "FC-7 G3 names the tag" "REFUSED ledger_ok: ledger changed, ask the user (the ledger has 0 lines, fewer than the 1 that the gate commit onboard-v1 recorded)"
mv "$GFC_LED" "$T1_TMP/fc-gf-ledger.moved"
expect_fail "FC-7 with the tag, the missing ledger is refused" "$gfc" sh "$GC" ledger_ok
out_has "FC-7 with the tag, the hint says copy from the original checkout" "copies gate-ledger and, when it exists, reopen-grant from the original checkout"
lacks "FC-7 with the tag, no create-empty hint" "$T1_TMP/out.txt" "creates the empty ledger"
# GW-n (round 18, Kakashi; Iruka T3 and J7): greenfield_record_ok is wired into prereq_approved and into every
# onboard state change (no_restart_without_reopen, which sync-feature-state.sh runs). OK and NONE go on as before;
# REFUSED stops. Also: an orphan branch in a repo with commits no longer yields a trusted greenfield root, field
# checks match the whole value (no trailing newline), and bootstrap's untrusted-root marker refuses.
gw_mark_line() { printf 'rootCommit=%s\nreason=%s\nmarkedAt=%s\n' "$1" "post-commit check failed: the commit hooks changed the tree" "2026-11-02T08:38:00+08:00"; }
# GW-1 OK: a valid record; prereq_approved and the onboard state change go on (no brownfield record: a new run)
gf_root gw-ok "$gf_tr" "$GFJ"; gw="$T1_TMP/gw-ok"
expect_rc "GW-1 setup: the record is valid (OK)" 0 "$gw" sh "$GC" greenfield_record_ok
expect_pass "GW-1 prereq_approved goes on when the record is OK" "$gw" sh "$GC" prereq_approved intake
out_has "GW-1 prereq_approved as before" "OK prereq_approved: no brownfield record"
expect_pass "GW-1 no_restart_without_reopen goes on when the record is OK" "$gw" sh "$GC" no_restart_without_reopen
out_has "GW-1 no_restart_without_reopen as before" "(no onboarding state and no earlier run: a new run)"
mkdir -p "$gw/$(dirname "$REP")"; cp "$p2/$REP" "$gw/$REP"
expect_pass "GW-1 the onboard state change (sync --status in_progress) goes on when the record is OK" "$gw" sh "$SFS" "$REP" --active-phase onboard --status in_progress
if [ -f "$gw/$ST" ]; then pass "GW-1 the onboarding state was written"; else fail "GW-1 the onboarding state was written"; fi
# GW-2 REFUSED: a record added after the root commit (gb, GF-9); both refuse and name the record check
expect_rc "GW-2 setup: the record is REFUSED" 1 "$gb" sh "$GC" greenfield_record_ok
expect_rc "GW-2 prereq_approved refuses when the record is REFUSED" 1 "$gb" sh "$GC" prereq_approved intake
out_has "GW-2 prereq_approved names the record check" "REFUSED prereq_approved: intake cannot start: the greenfield record check refused (gate-checks.sh greenfield_record_ok: record changed, ask the user ($GFR was added by commit"
out_has "GW-2 prereq_approved says stop" "Stop and show the user this output"
expect_rc "GW-2 no_restart_without_reopen refuses when the record is REFUSED" 1 "$gb" sh "$GC" no_restart_without_reopen
out_has "GW-2 no_restart_without_reopen names the record check" "REFUSED no_restart_without_reopen: onboard changes no state: the greenfield record check refused (gate-checks.sh greenfield_record_ok: record changed, ask the user"
mkdir -p "$gb/$(dirname "$REP")"; cp "$p2/$REP" "$gb/$REP"
expect_fail "GW-2 the onboard state change (sync --status in_progress) is refused" "$gb" sh "$SFS" "$REP" --active-phase onboard --status in_progress
out_has "GW-2 the state change names the record check" "onboard changes no state: the greenfield record check refused"
if [ -e "$gb/$ST" ]; then fail "GW-2 no onboarding state was written"; else pass "GW-2 no onboarding state was written"; fi
printf ' \n' >> "$gw/$GFR"
expect_rc "GW-2 an edited work-tree record: prereq_approved refuses" 1 "$gw" sh "$GC" prereq_approved intake
out_has "GW-2 names the work-tree copy" "$GFR in the work tree differs"
G "$gw" checkout -q -- "$GFR"
# GW-3 NONE: no record; both behave exactly as before
gn="$(t1_repo gw-none --commit)"; t1_install "$gn" || fail "install.sh into gw-none"
G "$gn" add -A >/dev/null; G "$gn" commit -qm installed
expect_rc "GW-3 setup: no record (NONE)" 4 "$gn" sh "$GC" greenfield_record_ok
expect_pass "GW-3 prereq_approved is unchanged when there is no record" "$gn" sh "$GC" prereq_approved intake
out_has "GW-3 prereq_approved as before" "OK prereq_approved: no brownfield record"
expect_pass "GW-3 no_restart_without_reopen is unchanged when there is no record" "$gn" sh "$GC" no_restart_without_reopen
out_has "GW-3 no_restart_without_reopen as before" "(no onboarding state and no earlier run: a new run)"
# GW-4 (Iruka T3): an orphan branch in a repo that already has commits
G "$gn" checkout -q --orphan gw-orphan
expect_rc "GW-4 greenfield_trailer refuses an orphan branch in a repo with commits" 1 "$gn" sh "$GC" greenfield_trailer
out_has "GW-4 says the repo already has commits" "REFUSED greenfield_trailer: the repo already has commits (git rev-list --all)"
mkdir -p "$(fc_dir "$gn")"; [ -e "$(fc_dir "$gn")/gate-ledger" ] || : > "$(fc_dir "$gn")/gate-ledger"
printf '%s\n' "$GFJ" > "$gn/$GFR"; G "$gn" add -A >/dev/null; G "$gn" commit -qm "bootstrap

$gf_tr"
expect_rc "GW-4 a root on an orphan branch holding the whole tree and the record is not greenfield (NONE)" 4 "$gn" sh "$GC" greenfield_record_ok
out_has "GW-4 counts every root of the repo" "NONE greenfield_record_ok: the repo has 2 root commits (git rev-list --all"
lacks "GW-4 never OK" "$T1_TMP/out.txt" "OK greenfield_record_ok"
G "$gn" checkout -q main
# GW-5 (Iruka J7): a field with a trailing newline is refused (the whole value must match)
gf_root gw-j7 "$gf_tr" '{"kind": "greenfield", "bootstrapAt": "2026-11-02T08:00:00+08:00", "kitSha": "abcdef1\n"}'
expect_rc "GW-5 kitSha 'abcdef1\\n' is refused" 1 "$T1_TMP/gw-j7" sh "$GC" greenfield_record_ok
out_has "GW-5 names kitSha" "kitSha is not a kit commit (7-40 hex, optional -dirty) or unknown"
gf_root gw-j7b "$gf_tr" '{"kind": "greenfield", "bootstrapAt": "2026-11-02T08:00:00+08:00\n", "kitSha": "unknown"}'
expect_rc "GW-5 bootstrapAt with a trailing newline is refused" 1 "$T1_TMP/gw-j7b" sh "$GC" greenfield_record_ok
out_has "GW-5 names bootstrapAt" "bootstrapAt is not a time like"
gf_root gw-j7c "$gf_tr" '{"kind": "greenfield", "bootstrapAt": "2026-11-02T08:00:00+08:00", "kitSha": "abcdef1-dirty"}'
expect_rc "GW-5 kitSha abcdef1-dirty still passes" 0 "$T1_TMP/gw-j7c" sh "$GC" greenfield_record_ok
# GW-6: bootstrap's untrusted-root marker (Yamato's format: rootCommit=, reason=, markedAt=) refuses
gm="$(fc_dir "$gw")/untrusted-root"; gw_root="$(git -C "$gw" rev-parse HEAD)"
gw_mark_line "$gw_root" > "$gm"
expect_rc "GW-6 the untrusted-root marker refuses a valid record" 1 "$gw" sh "$GC" greenfield_record_ok
out_has "GW-6 names the marker path" "REFUSED greenfield_record_ok: the untrusted-root marker $gm exists"
out_has "GW-6 names the marked root commit" "marked the root commit $gw_root of this repo as not trusted"
out_has "GW-6 says the root commit is not trusted" "so the root commit is not trusted"
out_has "GW-6 gives bootstrap's recovery steps" "move this repo aside, create a new empty repo (git init), then rerun bootstrap"
expect_rc "GW-6 prereq_approved refuses while the marker exists" 1 "$gw" sh "$GC" prereq_approved intake
out_has "GW-6 prereq_approved names the marker" "intake cannot start: the greenfield record check refused (gate-checks.sh greenfield_record_ok: the untrusted-root marker $gm exists"
expect_rc "GW-6 no_restart_without_reopen refuses while the marker exists" 1 "$gw" sh "$GC" no_restart_without_reopen
out_has "GW-6 no_restart_without_reopen names the marker" "the untrusted-root marker $gm exists"
G "$gw" worktree add -q "$T1_TMP/gw-wt" -b gw-wt
expect_rc "GW-6 a linked worktree reads the marker from the git common dir" 1 "$T1_TMP/gw-wt" sh "$GC" greenfield_record_ok
out_has "GW-6 the worktree names the same marker" "the untrusted-root marker $gm exists"
printf 'rootCommit=not-a-sha\nreason=x\n' > "$gm"
expect_rc "GW-6 a marker naming no commit still refuses" 1 "$gw" sh "$GC" greenfield_record_ok
lacks "GW-6 a malformed rootCommit is not echoed" "$T1_TMP/out.txt" "not-a-sha"
gw_mark_line "$(git -C "$gn" rev-parse HEAD)" > "$(fc_dir "$gn")/untrusted-root"
expect_rc "GW-6 the marker refuses in a repo with no record too" 1 "$gn" sh "$GC" greenfield_record_ok
mv "$(fc_dir "$gn")/untrusted-root" "$T1_TMP/gw-none-marker.moved"
mv "$gm" "$T1_TMP/gw-marker.moved"
expect_rc "GW-6 with the marker moved away, the record is OK again" 0 "$gw" sh "$GC" greenfield_record_ok
# LZ-n (round 18, Iruka review of 6255b114): an onboard-v<n> tag with a leading zero. git and python read
# onboard-v011 as 11, but the shell's $(( )) reads 011 as octal 9 and stops on 08, so commit_chain printed the
# wrong next tag (onboard-v10) or died. Every check now refuses such a tag and names it; onboard-v10 still works.
# lz_clone <name> <tag>: a clone of the FC original with both files copied and <tag> on the newest gate commit.
lz_clone() {
  lz_d="$T1_TMP/$1"; git clone -q "$fo" "$lz_d"; mkdir -p "$(fc_dir "$lz_d")"
  cp "$FO_LED" "$(fc_dir "$lz_d")/gate-ledger"; cp "$FO_GRANT" "$(fc_dir "$lz_d")/reopen-grant"
  G "$lz_d" tag -a "$2" -m "onboard approved" onboard-v2
}
LZ_SHELLS="sh"; for sh_ in dash bash; do if command -v "$sh_" >/dev/null 2>&1; then LZ_SHELLS="$LZ_SHELLS $sh_"; fi; done
for lz_t in onboard-v011 onboard-v08; do
  lz_clone "lz-$lz_t" "$lz_t"
  expect_rc "LZ-1 ledger_ok refuses the leading-zero tag $lz_t" 1 "$lz_d" sh "$GC" ledger_ok
  out_has "LZ-1 ledger_ok names $lz_t" "REFUSED ledger_ok: ledger changed, ask the user (the tag $lz_t has a leading zero"
  expect_rc "LZ-1 gate_committed refuses the leading-zero tag $lz_t" 1 "$lz_d" sh "$GC" gate_committed onboard
  out_has "LZ-1 gate_committed names $lz_t" "the tag $lz_t has a leading zero"
  for sh_ in $LZ_SHELLS; do
    expect_rc "LZ-2 $sh_: commit_chain refuses the leading-zero tag $lz_t" 1 "$lz_d" "$sh_" "$GC" commit_chain
    out_has "LZ-2 $sh_: commit_chain names $lz_t" "REFUSED commit_chain: the tag $lz_t has a leading zero"
    lacks "LZ-2 $sh_: commit_chain prints no chain with $lz_t" "$T1_TMP/out.txt" "git tag -a"
  done
done
lz_clone lz-ten onboard-v10
expect_pass "LZ-3 onboard-v10 (no leading zero) passes ledger_ok" "$lz_d" sh "$GC" ledger_ok
out_has "LZ-3 onboard-v10 is the newest anchor" "trailer of onboard-v10 (lines=3)"
for sh_ in $LZ_SHELLS; do
  expect_pass "LZ-3 $sh_: commit_chain runs with onboard-v10" "$lz_d" "$sh_" "$GC" commit_chain
  out_has "LZ-3 $sh_: the next tag is onboard-v11" "git tag -a onboard-v11 -m"
done
# LA-n (round 19, legacy option A; round 20: legacy means made before the ledger kit, and a real terminal): a repo onboarded before the kit kept the gate ledger has onboard-v<n> tags with
# no Agents-V0-Ledger trailer, and every ledger check refuses them. The person adopts them once with
# `gate-checks.sh adopt_legacy_tags` (the hook denies it to the agent): it writes <git common dir>/agents-v0/
# legacy-adoption (tags, commits, time, kit version, HEAD and the ledger lines it pins), refuses a second run, and the
# ledger checks then count the adopted tags as anchors. Any other trailer-less tag still refuses. Each refusal below
# writes nothing. The typed answer stands in for the person in their own terminal.
la_rec() { printf '%s/legacy-adoption\n' "$(fc_dir "$1")"; }
la_led() { printf '%s/gate-ledger\n' "$(fc_dir "$1")"; }
# la_pty <answer> <command...>: run the command on a real pty (stdin, stdout and /dev/tty are the pty) and type
# <answer> at the "Type adopt" prompt (<EOF> types end of input); prints what the terminal showed, exits as the command
la_pty() { python3 -c 'import os, pty, select, sys
ans, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf, sent = b"", False
while True:
    r = select.select([fd], [], [], 60)[0]
    if not r:
        break
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
    if not sent and b"Type adopt" in buf:
        os.write(fd, b"\x04" if ans == "<EOF>" else ans.encode() + b"\n")
        sent = True
st = os.waitpid(pid, 0)[1]
sys.stdout.write(buf.decode("utf-8", "replace").replace("\r\n", "\n"))
sys.exit(os.waitstatus_to_exitcode(st))' "$@"; }
# la_run <answer> <shell>: adopt_legacy_tags in a terminal (a pty), with <answer> typed at the prompt
la_run() { la_pty "$1" "$2" "$GC" adopt_legacy_tags; }
# la_none <desc> <repo>: no record was written
# la_cat: the record (nothing when it is missing, so a missing record fails the checks, not the suite)
la_cat() { cat "$LA_REC" 2>/dev/null || :; }
la_none() { if [ -e "$(la_rec "$2")" ] || [ -L "$(la_rec "$2")" ]; then fail "$1"; else pass "$1"; fi; }
# la_tree <name> <base tree|-> <mode,blob,path>...: a tree built in a scratch index of the repo $la_d (from the base
# tree, or empty for -) with those entries added; prints the tree
la_tree() { la_ix="$T1_TMP/la-index-$1"; shift
  if [ "$1" = - ]; then GIT_INDEX_FILE="$la_ix" git -C "$la_d" read-tree --empty; else GIT_INDEX_FILE="$la_ix" git -C "$la_d" read-tree "$1"; fi; shift
  for e_ in "$@"; do GIT_INDEX_FILE="$la_ix" git -C "$la_d" update-index --add --cacheinfo "$e_"; done
  GIT_INDEX_FILE="$la_ix" git -C "$la_d" write-tree; }
# la_ct <tree> <parent> <message>: a commit of that tree on that parent (prints it)
la_ct() { lg_env git -C "$la_d" commit-tree "$1" -p "$2^{commit}" -m "$3"; }
la_blob() { printf '%s' "$1" | git -C "$la_d" hash-object -w --stdin; }
# la_mk <name>: a clone of the FC original with no tags and no ledger, then the history of a repo onboarded before
# the ledger: onboard-v1 on a commit with no gate-checks.sh at all (an older kit), onboard-v2 on a commit whose
# gate-checks.sh predates the ledger (no Agents-V0-Ledger, no gate-ledger), both with the approved onboarding state
# and no trailer; then the kit update to today's kit (the fixture's own tree) on top. Nothing in the work tree changes.
la_mk() {
  la_d="$T1_TMP/$1"; git clone -q --no-tags "$fo" "$la_d"
  la_t0="$(git -C "$la_d" rev-parse 'HEAD^{tree}')"; la_st="$(git -C "$la_d" rev-parse "HEAD:$ST")"
  la_old="$(la_blob '#!/bin/sh
# FAKE- gate-checks.sh of a kit before the ledger: gate rules only
exit 0
')"
  la_tr1="$(la_tree "$1-1" - "100644,$(la_blob 'FAKE- legacy app
'),README.md" "100644,$la_st,$ST")"
  la_tr2="$(la_tree "$1-2" "$la_t0" "100755,$la_old,.agents-v0/scripts/gate-checks.sh")"
  la_c1="$(la_ct "$la_tr1" HEAD "onboarding: onboard approved (legacy, an older kit)")"
  G "$la_d" tag -a onboard-v1 -m "onboard approved" "$la_c1"
  la_c2="$(la_ct "$la_tr2" "$la_c1" "onboarding: onboard approved again (legacy, before the gate ledger)")"
  G "$la_d" tag -a onboard-v2 -m "onboard approved" "$la_c2"
  G "$la_d" update-ref -m "fixture: the kit update" HEAD "$(la_ct "$la_t0" "$la_c2" "kit: update to the gate-ledger kit")"
}
# la_ledger <repo>: the legacy ledger the person keeps: two FAIL lines and one used grant (with its grant file)
la_ledger() { mkdir -p "$(fc_dir "$1")"; printf 'FAIL docs check\nFAIL docs check\nGRANT-USED %s count=2\n' "$fc_h1" > "$(la_led "$1")"
  printf '%s\n' "$fc_gl1" > "$(fc_dir "$1")/reopen-grant"; }
LA_HINT="has no Agents-V0-Ledger trailer; if this repo's onboard-v<n> tags were made before the kit kept the gate ledger, the person (never an agent) adopts them once in their own terminal with sh .agents-v0/scripts/gate-checks.sh adopt_legacy_tags"
la_mk la-pre; lp="$la_d"; LP_LED="$(la_led "$lp")"
expect_rc "LA-1 before adoption, ledger_ok refuses the legacy tags" 1 "$lp" sh "$GC" ledger_ok
out_has "LA-1 ledger_ok names the first legacy tag" "REFUSED ledger_ok: ledger changed, ask the user (the gate commit onboard-v1 ("
out_has "LA-1 ledger_ok says how the person adopts them" "$LA_HINT"
out_has "LA-1 ledger_ok names the fresh-clone copy" "in a fresh clone of a repo that already adopted them, the person copies legacy-adoption, gate-ledger and reopen-grant from the original checkout's agents-v0/ instead). Stop and show the user)"
expect_rc "LA-1 before adoption, gate_committed refuses the legacy tags" 1 "$lp" sh "$GC" gate_committed onboard
out_has "LA-1 gate_committed says how the person adopts them" "$LA_HINT"
expect_pass "LA-2 adopt_legacy_tags --help prints the usage" "$lp" sh "$GC" adopt_legacy_tags --help
out_has "LA-2 the usage names the command" "usage: sh .agents-v0/scripts/gate-checks.sh adopt_legacy_tags [--help]"
out_has "LA-2 the usage says the person runs it once" "The person runs this once per repo, in their own terminal; an agent never runs it (the hook denies it)."
expect_rc "LA-2 adopt_legacy_tags with an unknown argument is a usage error" 2 "$lp" sh "$GC" adopt_legacy_tags --force
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-3 $sh_: adoption refuses a missing ledger" 1 "$lp" la_run adopt "$sh_"
  out_has "LA-3 $sh_: it names the missing ledger" "REFUSED adopt_legacy_tags: the ledger $LP_LED is missing, so there is nothing to pin: if this repo never had one, the person (never an agent) creates it as an empty file first"
  la_none "LA-3 $sh_: nothing was written" "$lp"
done
la_ledger "$lp"; cp "$LP_LED" "$T1_TMP/la-pre-ledger.keep"
printf 'NOT A LEDGER LINE\n' >> "$LP_LED"
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-4 $sh_: adoption refuses a malformed ledger line" 1 "$lp" la_run adopt "$sh_"
  out_has "LA-4 $sh_: it names the line" "REFUSED adopt_legacy_tags: nothing was written: the ledger cannot be adopted: ledger line 4 is not a well-formed FAIL, GRANT-USED or REOPEN-REFUSED line"
  la_none "LA-4 $sh_: nothing was written" "$lp"
done
printf 'FAIL no newline' >> "$LP_LED"
expect_rc "LA-4 adoption refuses a ledger without its final newline" 1 "$lp" la_run adopt sh
out_has "LA-4 it names the missing newline" "has no newline (every kit write ends in one)"
cp "$T1_TMP/la-pre-ledger.keep" "$LP_LED"; printf 'GRANT-USED %s count=2\n' "$fc_h2" >> "$LP_LED"
expect_rc "LA-4 adoption refuses a GRANT-USED line that names no grant" 1 "$lp" la_run adopt sh
out_has "LA-4 it names the grant mismatch" "nothing was written: the ledger cannot be adopted: ledger line 4 is a GRANT-USED line that names no grant in"
cp "$T1_TMP/la-pre-ledger.keep" "$LP_LED"
la_none "LA-4 nothing was written" "$lp"
printf 'rootCommit=%s\nreason=FAKE-test\n' "$(git -C "$lp" rev-parse HEAD)" > "$(fc_dir "$lp")/untrusted-root"
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-5 $sh_: adoption refuses with the untrusted-root marker" 1 "$lp" la_run adopt "$sh_"
  out_has "LA-5 $sh_: it names the marker" "REFUSED adopt_legacy_tags: the untrusted-root marker $(fc_dir "$lp")/untrusted-root exists"
done
mv "$(fc_dir "$lp")/untrusted-root" "$T1_TMP/la-untrusted-root.aside"
la_none "LA-5 nothing was written" "$lp"
for sh_ in $LZ_SHELLS; do
  for la_a in no "" "adopt now"; do
    expect_rc "LA-6 $sh_: the answer '$la_a' is not a confirmation" 1 "$lp" la_run "$la_a" "$sh_"
    out_has "LA-6 $sh_: it shows the record before asking" "  tag=onboard-v2 $(git -C "$lp" rev-parse onboard-v2^{commit})"
    out_has "LA-6 $sh_: it says nothing was written" "REFUSED adopt_legacy_tags: not confirmed (the answer was not adopt), so nothing was written"
  done
  expect_rc "LA-6 $sh_: no answer at all (end of input typed at the terminal) is not a confirmation" 1 "$lp" la_run "<EOF>" "$sh_"
  out_has "LA-6 $sh_: end of input writes nothing" "not confirmed (the answer was not adopt), so nothing was written"
done
la_none "LA-6 nothing was written" "$lp"
printf 'adopt\n' > "$T1_TMP/la-answer.txt"
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-22 $sh_: a piped answer is refused" 1 "$lp" sh -c 'printf "adopt\n" | "$0" "$1" adopt_legacy_tags' "$sh_" "$GC"
  out_has "LA-22 $sh_: the pipe is named" "REFUSED adopt_legacy_tags: standard input is not a terminal: the person runs this in their own terminal and types adopt there; piped or redirected input is refused, so nothing was written"
  lacks "LA-22 $sh_: a piped run shows no prompt" "$T1_TMP/out.txt" "Type adopt"
  expect_rc "LA-22 $sh_: an answer redirected from a file is refused" 1 "$lp" "$sh_" "$GC" adopt_legacy_tags < "$T1_TMP/la-answer.txt"
  out_has "LA-22 $sh_: the redirect is named" "REFUSED adopt_legacy_tags: standard input is not a terminal"
done
# stdin, stdout and stderr on a pty that is not the controlling terminal (a new session that never opened it), so
# [ -t 0 ] holds but /dev/tty cannot be opened
la_noctty() { python3 -c 'import os, sys
m, sl = os.openpty()
pid = os.fork()
if pid == 0:
    os.setsid(); os.close(m)
    for fd in (0, 1, 2):
        os.dup2(sl, fd)
    os.execvp(sys.argv[1], sys.argv[1:])
os.close(sl); buf = b""
while True:
    try:
        d = os.read(m, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
sys.stdout.write(buf.decode("utf-8", "replace").replace("\r\n", "\n"))
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))' "$@"; }
expect_rc "LA-22 a terminal on stdin with no /dev/tty is refused" 1 "$lp" la_noctty sh "$GC" adopt_legacy_tags
out_has "LA-22 no /dev/tty: refused cleanly" "REFUSED adopt_legacy_tags: cannot open /dev/tty: the person runs this in their own terminal and types adopt there; nothing was written"
la_none "LA-22 nothing was written" "$lp"
# tag shapes that refuse: each on its own clone (the suite never deletes or moves a tag back to make room)
la_mk la-lz; la_ledger "$la_d"; G "$la_d" tag -a onboard-v03 -m "onboard approved" onboard-v2
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-7 $sh_: adoption refuses a leading-zero tag" 1 "$la_d" la_run adopt "$sh_"
  out_has "LA-7 $sh_: it names the tag" "REFUSED adopt_legacy_tags: the tag onboard-v03 has a leading zero"
done
la_none "LA-7 nothing was written" "$la_d"
la_mk la-side; la_ledger "$la_d"; G "$la_d" checkout -q -b side "$(la_ct "$la_t0" onboard-v1 "kit: a side branch")"
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-8 $sh_: adoption refuses a tag that HEAD does not reach" 1 "$la_d" la_run adopt "$sh_"
  out_has "LA-8 $sh_: it names the tag" "REFUSED adopt_legacy_tags: the tag onboard-v2 ($(git -C "$la_d" rev-parse --short=12 onboard-v2^{commit})) is not reachable from HEAD"
done
la_none "LA-8 nothing was written" "$la_d"
la_mk la-tree; la_ledger "$la_d"; G "$la_d" tag onboard-v3 "HEAD^{tree}"
expect_rc "LA-9 adoption refuses a tag that names no commit" 1 "$la_d" la_run adopt sh
out_has "LA-9 it names the tag" "REFUSED adopt_legacy_tags: the tag onboard-v3 does not name a commit"
la_none "LA-9 nothing was written" "$la_d"
la_d="$T1_TMP/la-none"; git clone -q --no-tags "$fo" "$la_d"; la_ledger "$la_d"
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-10 $sh_: adoption refuses a repo with no onboard-v<n> tag" 1 "$la_d" la_run adopt "$sh_"
  out_has "LA-10 $sh_: it says there is nothing to adopt" "REFUSED adopt_legacy_tags: there is no onboard-v<n> tag to adopt"
done
la_none "LA-10 nothing was written" "$la_d"
la_d="$T1_TMP/la-new"; git clone -q "$fo" "$la_d"; mkdir -p "$(fc_dir "$la_d")"
cp "$FO_LED" "$(la_led "$la_d")"; cp "$FO_GRANT" "$(fc_dir "$la_d")/reopen-grant"
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-11 $sh_: adoption refuses a repo whose tags carry the trailer" 1 "$la_d" la_run adopt "$sh_"
  out_has "LA-11 $sh_: it names the trailer tag" "REFUSED adopt_legacy_tags: the gate commit onboard-v1 ($(git -C "$la_d" rev-parse --short=12 onboard-v1^{commit})) carries an Agents-V0-Ledger trailer, so this repo is not a legacy repo"
done
la_none "LA-11 nothing was written" "$la_d"
la_mk la-mix; la_ledger "$la_d"
G "$la_d" commit -q --allow-empty -m "onboarding: onboard approved" -m "$(lt_trailer "$la_d")"; G "$la_d" tag -a onboard-v3 -m "onboard approved"
expect_rc "LA-11 adoption refuses legacy tags mixed with a trailer tag" 1 "$la_d" la_run adopt sh
out_has "LA-11 it names the trailer tag" "the gate commit onboard-v3 ($(git -C "$la_d" rev-parse --short=12 onboard-v3^{commit})) carries an Agents-V0-Ledger trailer"
la_none "LA-11 a mixed repo: nothing was written" "$la_d"
# LA-23..LA-27 (round 20, Jiraiya must-fix): a fresh tag on a commit made with today's kit is not a legacy tag
la_d="$T1_TMP/la-fresh"; git clone -q --no-tags "$fo" "$la_d"; la_ledger "$la_d"
G "$la_d" commit -q --allow-empty -m "onboarding: onboard approved"; G "$la_d" tag onboard-v1 HEAD
laf="$la_d"; G "$laf" worktree add -q -b la-fresh-wt "$T1_TMP/la-fresh-wt" HEAD
for sh_ in $LZ_SHELLS; do
  expect_rc "LA-23 $sh_: an agent-made tag on a ledger-era commit is refused" 1 "$laf" la_run adopt "$sh_"
  out_has "LA-23 $sh_: it names the tag and the ledger-era kit" "REFUSED adopt_legacy_tags: the tag onboard-v1 ($(git -C "$laf" rev-parse --short=12 HEAD)) is not a legacy tag: its commit already holds .agents-v0/scripts/gate-checks.sh from a kit that keeps the gate ledger (it names Agents-V0-Ledger and gate-ledger), so the tag was made after the ledger and must carry the Agents-V0-Ledger trailer. Nothing was written"
  lacks "LA-23 $sh_: no prompt" "$T1_TMP/out.txt" "Type adopt"
  expect_rc "LA-23 $sh_: refused from a linked worktree too" 1 "$T1_TMP/la-fresh-wt" la_run adopt "$sh_"
  out_has "LA-23 $sh_: the worktree refusal names the tag" "the tag onboard-v1 ($(git -C "$laf" rev-parse --short=12 HEAD)) is not a legacy tag"
done
la_none "LA-23 nothing was written" "$laf"
expect_rc "LA-23 the fresh tag still refuses ledger_ok with the trailer hint" 1 "$laf" sh "$GC" ledger_ok
out_has "LA-23 ledger_ok names the fresh tag" "the gate commit onboard-v1 ("
la_mk la-mixf; la_ledger "$la_d"; G "$la_d" tag -a onboard-v3 -m "onboard approved" HEAD
expect_rc "LA-24 legacy tags mixed with a fresh tag on the kit-update commit are refused" 1 "$la_d" la_run adopt sh
out_has "LA-24 it names the fresh tag" "the tag onboard-v3 ($(git -C "$la_d" rev-parse --short=12 HEAD)) is not a legacy tag: its commit already holds .agents-v0/scripts/gate-checks.sh"
la_none "LA-24 nothing was written" "$la_d"
la_mk la-tpl; la_ledger "$la_d"
la_c="$(la_ct "$(la_tree tpl - "100644,$(la_blob 'FAKE- kit checkout
'),README.md" "100644,$la_st,$ST" "100644,$(git -C "$la_d" rev-parse 'HEAD:.agents-v0/scripts/gate-checks.sh'),templates/.agents-v0/scripts/gate-checks.sh")" onboard-v2 "onboarding: on the kit's own checkout")"
G "$la_d" tag -a onboard-v3 -m "onboard approved" "$la_c"
expect_rc "LA-25 a tag on a commit with the ledger kit at the templates path is refused" 1 "$la_d" la_run adopt sh
out_has "LA-25 it names the templates path" "the tag onboard-v3 ($(printf '%s' "$la_c" | cut -c1-12)) is not a legacy tag: its commit already holds templates/.agents-v0/scripts/gate-checks.sh from a kit that keeps the gate ledger"
la_mk la-link; la_ledger "$la_d"
la_c="$(la_ct "$(la_tree link "$la_t0" "120000,$(la_blob 'FAKE-target'),.agents-v0/scripts/gate-checks.sh")" onboard-v2 "onboarding: gate-checks.sh as a symlink")"
G "$la_d" tag -a onboard-v3 -m "onboard approved" "$la_c"
expect_rc "LA-26 a tag whose gate-checks.sh is a symlink is refused" 1 "$la_d" la_run adopt sh
out_has "LA-26 it says the file is not regular" "the tag onboard-v3 ($(printf '%s' "$la_c" | cut -c1-12)) cannot be adopted: .agents-v0/scripts/gate-checks.sh in its commit is not a regular file (120000 blob "
la_mk la-nost; la_ledger "$la_d"
la_c="$(la_ct "$(la_tree nost - "100644,$(la_blob 'FAKE- before onboarding
'),README.md")" onboard-v2 "chore: no onboarding state")"
G "$la_d" tag -a onboard-v3 -m "onboard approved" "$la_c"
expect_rc "LA-27 a tag on a commit with no approved onboarding state is refused" 1 "$la_d" la_run adopt sh
out_has "LA-27 it names the missing state" "the tag onboard-v3 ($(printf '%s' "$la_c" | cut -c1-12)) is not a legacy onboard gate commit: its commit has no docs/agents-v0/onboarding/state.json with onboard in approvedPhases"
la_none "LA-23..27 nothing was written" "$la_d"

# the adoption itself, under each shell, run from a linked worktree: the record lands in the git common dir
for sh_ in $LZ_SHELLS; do
  la_mk "la-ok-$sh_"; la="$la_d"; la_ledger "$la"; LA_REC="$(la_rec "$la")"; LA_LED="$(la_led "$la")"
  law="$T1_TMP/la-ok-$sh_-wt"; G "$la" worktree add -q -b la-wt "$law" HEAD
  expect_rc "LA-12 $sh_: the first adoption, from a linked worktree, is OK" 0 "$law" la_run adopt "$sh_"
  out_has "LA-12 $sh_: it shows where it writes" "adopt_legacy_tags: this writes $LA_REC, once, with:"
  out_has "LA-12 $sh_: it asks for the answer" "Type adopt and press Enter to write it (anything else writes nothing): "
  out_has "LA-12 $sh_: it says what it wrote" "OK adopt_legacy_tags: wrote $LA_REC; the ledger matches the legacy adoption record $LA_REC (adopted tag onboard-v2) (lines=3) and its 0 later line(s) are well formed"
  if [ -f "$LA_REC" ] && [ ! -L "$LA_REC" ]; then pass "LA-12 $sh_: the record is a regular file in the git common dir"; else fail "LA-12 $sh_: the record is a regular file in the git common dir"; fi
  la_wgd="$(cd "$law" && cd "$(git rev-parse --git-dir)" && pwd)"
  if [ -e "$la_wgd/agents-v0/legacy-adoption" ]; then fail "LA-12 $sh_: no record in the worktree's own git dir"; else pass "LA-12 $sh_: no record in the worktree's own git dir"; fi
  la_kit="unknown"; if [ -f "$la/.agents-kit-version" ]; then la_kit="$(sed -n 's/^[^+]*+\([0-9a-f]\{7,40\}\(-dirty\)\{0,1\}\)$/\1/p' "$la/.agents-kit-version")"; [ -n "$la_kit" ] || la_kit="unknown"; fi
  is_eq "LA-13 $sh_: the record has 8 lines" "$(la_cat | wc -l | tr -d ' ')" "8"
  is_eq "LA-13 $sh_: line 1 is the header" "$(la_cat | sed -n 1p)" "# agents-v0 legacy tag adoption record: written once by the person with gate-checks.sh adopt_legacy_tags; never edit, never commit"
  if la_cat | sed -n 2p | grep -Eq '^adoptedAt=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$'; then pass "LA-13 $sh_: line 2 is adoptedAt with the local offset"; else fail "LA-13 $sh_: line 2 is adoptedAt with the local offset (got '$(la_cat | sed -n 2p)')"; fi
  is_eq "LA-13 $sh_: line 3 is the kit sha" "$(la_cat | sed -n 3p)" "kitSha=$la_kit"
  is_eq "LA-13 $sh_: line 4 is HEAD" "$(la_cat | sed -n 4p)" "head=$(git -C "$law" rev-parse HEAD)"
  is_eq "LA-13 $sh_: line 5 is the ledger's line count" "$(la_cat | sed -n 5p)" "ledgerLines=3"
  is_eq "LA-13 $sh_: line 6 is the ledger's sha256" "$(la_cat | sed -n 6p)" "ledgerSha256=$(lg_sha "$LA_LED")"
  is_eq "LA-13 $sh_: line 7 is onboard-v1 and its commit" "$(la_cat | sed -n 7p)" "tag=onboard-v1 $(git -C "$la" rev-parse onboard-v1^{commit})"
  is_eq "LA-13 $sh_: line 8 is onboard-v2 and its commit" "$(la_cat | sed -n 8p)" "tag=onboard-v2 $(git -C "$la" rev-parse onboard-v2^{commit})"
  la_ck="$(la_cat | cksum)"
  expect_rc "LA-14 $sh_: a second adoption, from the main checkout, is refused" 1 "$la" la_run adopt "$sh_"
  out_has "LA-14 $sh_: it names the existing record" "REFUSED adopt_legacy_tags: the legacy adoption record $LA_REC already exists (adopted at $(la_cat | sed -n 's/^adoptedAt=//p')): adoption runs once per repo, so nothing was written"
  lacks "LA-14 $sh_: it does not ask again" "$T1_TMP/out.txt" "Type adopt"
  expect_rc "LA-14 $sh_: a second adoption from the worktree is refused too" 1 "$law" la_run adopt "$sh_"
  is_eq "LA-14 $sh_: the record is unchanged" "$(la_cat | cksum)" "$la_ck"
  expect_rc "LA-15 $sh_: after adoption, ledger_ok passes in the main checkout" 0 "$la" "$sh_" "$GC" ledger_ok
  out_has "LA-15 $sh_: the adopted record is the anchor" "OK ledger_ok: the ledger matches the legacy adoption record $LA_REC (adopted tag onboard-v2) (lines=3)"
  expect_rc "LA-15 $sh_: after adoption, ledger_ok passes in the linked worktree" 0 "$law" "$sh_" "$GC" ledger_ok
  expect_rc "LA-15 $sh_: after adoption, gate_committed passes the ledger guard" 0 "$la" "$sh_" "$GC" gate_committed onboard
done
# after the adoption (the last shell's repo): edits, a bad record, a moved tag, the next gate commit, a clone
printf 'FAIL docs check\n' >> "$LA_LED"
expect_pass "LA-16 a FAIL line after the adoption is a later line" "$la" sh "$GC" ledger_ok
out_has "LA-16 it counts one later line" "(lines=3) and its 1 later line(s) are well formed"
cp "$LA_LED" "$T1_TMP/la-ledger.keep"
printf 'FAIL edited\nFAIL docs check\nGRANT-USED %s count=2\nFAIL docs check\n' "$fc_h1" > "$LA_LED"
expect_rc "LA-16 an edit of an adopted line refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-16 it names the record" "REFUSED ledger_ok: ledger changed, ask the user (the first 3 lines of the ledger no longer match the sha256 that the legacy adoption record $LA_REC (adopted tag onboard-v1) recorded (an earlier line was edited))"
head -n 2 "$T1_TMP/la-ledger.keep" > "$LA_LED"
expect_rc "LA-16 a cut ledger refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-16 it names the record's count" "the ledger has 2 lines, fewer than the 3 that the legacy adoption record $LA_REC (adopted tag onboard-v1) recorded"
cp "$T1_TMP/la-ledger.keep" "$LA_LED"
cp "$LA_REC" "$T1_TMP/la-record.keep" || :
printf 'tag=onboard-v3 %s\n' "$(git -C "$la" rev-parse HEAD)" >> "$LA_REC"
expect_rc "LA-17 a record that names a tag that does not exist refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-17 it names the gone tag" "the legacy adoption record $LA_REC adopted onboard-v3 ("
cp "$T1_TMP/la-record.keep" "$LA_REC" || :; printf 'note=FAKE-edit\n' >> "$LA_REC"
expect_rc "LA-17 an edited record refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-17 it says the record is not valid" "REFUSED ledger_ok: ledger changed, ask the user (the legacy adoption record $LA_REC is not valid (line 9 must be tag=onboard-v<n> <commit sha>)"
cp "$T1_TMP/la-record.keep" "$LA_REC" || :; sed 's/^ledgerLines=3$/ledgerLines=03/' "$T1_TMP/la-record.keep" > "$LA_REC" || :
expect_rc "LA-17 a record with a malformed field refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-17 it names the field" "is not valid (line 5 must be ledgerLines=<0|[1-9][0-9]*>)"
cp "$T1_TMP/la-record.keep" "$LA_REC" || :
expect_pass "LA-17 the restored record passes" "$la" sh "$GC" ledger_ok
la_v2="$(git -C "$la" rev-parse onboard-v2^{commit})"
G "$la" tag -f -a onboard-v2 -m "onboard approved" onboard-v1
expect_rc "LA-18 an adopted tag moved after the adoption refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-18 it says the tag was moved" "the tag onboard-v2 names $(git -C "$la" rev-parse --short=12 onboard-v1^{commit}), but the legacy adoption record $LA_REC adopted it at $(printf '%s' "$la_v2" | cut -c1-12) (the tag was moved after the adoption)"
G "$la" tag -f -a onboard-v2 -m "onboard approved" "$la_v2"
expect_pass "LA-18 the tag moved back passes" "$la" sh "$GC" ledger_ok
for sh_ in $LZ_SHELLS; do
  expect_pass "LA-19 $sh_: commit_chain runs after the adoption" "$la" "$sh_" "$GC" commit_chain
  out_has "LA-19 $sh_: the next tag is onboard-v3" "git tag -a onboard-v3 -m"
done
printf '\nRevision after the adoption.\n' >> "$la/docs/agents-v0/architecture.md"
expect_pass "LA-19 the first gate commit after the adoption runs the chain" "$la" lg_gate "$la" 3
expect_pass "LA-19 the new gate commit's trailer anchors the ledger" "$la" sh "$GC" ledger_ok
out_has "LA-19 onboard-v3 is the newest anchor" "the ledger matches the Agents-V0-Ledger trailer of onboard-v3 (lines=4)"
lac="$T1_TMP/la-clone"; git clone -q "$la" "$lac"
expect_rc "LA-20 a fresh clone of an adopted repo refuses without the record" 1 "$lac" sh "$GC" ledger_ok
out_has "LA-20 it says to copy the record" "in a fresh clone of a repo that already adopted them, the person copies legacy-adoption, gate-ledger and reopen-grant from the original checkout's agents-v0/ instead"
mkdir -p "$(fc_dir "$lac")"; cp "$LA_REC" "$(la_rec "$lac")" || :; cp "$LA_LED" "$(la_led "$lac")"; cp "$(fc_dir "$la")/reopen-grant" "$(fc_dir "$lac")/reopen-grant"
expect_pass "LA-20 with the three files copied, the clone passes" "$lac" sh "$GC" ledger_ok
expect_rc "LA-20 the clone refuses a new adoption" 1 "$lac" la_run adopt sh
out_has "LA-20 it names the copied record" "the legacy adoption record $(la_rec "$lac") already exists"
G "$la" commit -q --allow-empty -m "onboarding: onboard approved (no trailer, after the adoption)"; G "$la" tag -a onboard-v4 -m "onboard approved"
expect_rc "LA-21 a trailer-less tag made after the adoption refuses" 1 "$la" sh "$GC" ledger_ok
out_has "LA-21 it says the tag is not adopted" "the gate commit onboard-v4 ($(git -C "$la" rev-parse --short=12 onboard-v4^{commit})) has no Agents-V0-Ledger trailer, and it is not one of the tags the legacy adoption record $LA_REC adopted (onboard-v1, onboard-v2, at $(la_cat | sed -n 's/^adoptedAt=//p')); adoption runs once"
expect_rc "LA-21 gate_committed refuses it too" 1 "$la" sh "$GC" gate_committed onboard
out_has "LA-21 gate_committed says the tag is not adopted" "and it is not one of the tags the legacy adoption record"
expect_pass "list runs" "$a" sh "$GC" list
out_has "list: approval_evidence is wired" "approval_evidence wired"
out_has "list: gate_committed is wired" "gate_committed wired"
out_has "list: prereq_approved is wired" "prereq_approved wired"
out_has "list: staged_secret_scan is wired" "staged_secret_scan wired"
out_has "list: no_restart_without_reopen is wired" "no_restart_without_reopen wired"
out_has "list: commit_msg_ok is wired" "commit_msg_ok wired"
out_has "list: ledger_ok is wired (N3A)" "ledger_ok wired"
out_has "list: ledger_turn_ok is wired (N84)" "ledger_turn_ok wired"
out_has "list: greenfield_record_ok is wired (5A)" "greenfield_record_ok wired"

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
