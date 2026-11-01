#!/bin/sh
# test-gate-checks.sh — tier 1 tests for .agents-v0/scripts/gate-checks.sh and the sync wiring that calls it
# (onboard fix; design jiraiya-onboard-fix-design-20261101.md rev 6, line 149: "a new test-gate-checks.sh").
# Offline, no agent. Every case runs on an installed copy (install.sh into a temp git repo, Yamato's tier 1
# harness). Each helper check has a pass case and a refusal case with its exact message.
# Test ids: jiraiya-onboard-test-cases-20261101.md (N1, N2, N4, H1/H2 partial) plus AE-n / GC-n helper cases.
# Kit-only file: it is not installed into projects.
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

# onb_repo <name>: an installed brownfield-like repo, everything committed, with an onboarding report whose
# docs check passes (commit line, no TEMPLATE marker, no citations; the installed architecture.md and
# network.md templates carry TEMPLATE: markers, so the fixture fills them as a finished onboard would).
onb_repo() {
  r_="$(t1_repo "$1" --commit)"
  t1_install "$r_" || { fail "install.sh into $1"; return 1; }
  mkdir -p "$r_/docs/agents-v0/onboarding"
  base_="$(git -C "$r_" rev-parse --short HEAD)"
  cat > "$r_/$REP" <<EOR
# Onboarding report

commit: $base_

## Summary

A one-module fixture repo.

## Delivery approvals

| Phase | Evidence | Approver | Decision | Date |
|-------|----------|----------|----------|------|
EOR
  printf '# Architecture\n\nOne module, no services.\n' > "$r_/docs/agents-v0/architecture.md"
  printf '# Network\n\nNo network calls.\n' > "$r_/docs/agents-v0/network.md"
  G "$r_" add -A >/dev/null && G "$r_" commit -qm "fixture: installed kit and onboarding report"
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

# AE-4 refusal (N3 approval part, partial: JO-3/JO-4 own the gate docs list): the docs check fails
printf '\nTEMPLATE: sample row\n' >> "$a/$REP"
expect_fail "AE-4 approval_evidence refuses when the onboarding docs check fails" "$a" sh "$GC" approval_evidence onboard
out_has "AE-4 names the docs check" "REFUSED approval_evidence: the onboarding docs check failed (check-onboarding-docs.sh)"
q "$a" git checkout -q -- "$REP"

# AE-5 pass: awaiting_approval, phase result on disk, docs check passes
expect_pass "AE-5 approval_evidence passes with recorded evidence" "$a" sh "$GC" approval_evidence onboard
out_has "AE-5 prints the rule" "OK approval_evidence: onboard is awaiting_approval, $PR exists and the onboarding docs check passed"

# AE-6: a phase other than onboard is not wired yet and fails closed (exit 3)
(cd "$a" && sh "$GC" approval_evidence design) > "$T1_TMP/out.txt" 2>&1 && rc=0 || rc=$?
is_eq "AE-6 approval_evidence for another phase fails closed (exit 3)" "$rc" 3

# AE-7 pass at the sync level: --approve onboard with evidence records the approval (regression lock at 36b86cf)
expect_pass "AE-7 sync --approve onboard with evidence is recorded" "$a" sh "$SFS" "$REP" --approve onboard
is_eq "AE-7 onboard approved" "$(state_val "$a" lastApprovedPhase)" "onboard"

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

t1_done test-gate-checks.sh
