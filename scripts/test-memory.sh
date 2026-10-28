#!/bin/sh
# test-memory.sh — behavior tests for the cross-story memory scripts (no network, no agents).
# MEM-10: covers templates/.agents-v0/scripts/stories-status.sh (worktree view) and
# templates/.agents-v0/scripts/check-lessons.sh (lessons format, ids, cap, size, secrets,
# phase-result candidates, story-branch guard), and that install.sh puts both scripts and the
# lessons templates into a project. Run by validate-kit.sh.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
SS="$KIT/templates/.agents-v0/scripts/stories-status.sh"
CL="$KIT/templates/.agents-v0/scripts/check-lessons.sh"
tmp="$(mktemp -d)"
# shellcheck disable=SC2154  # rc is assigned inside the trap string
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
has() { if grep -Fq -- "$3" "$2"; then pass "$1"; else fail "$1 (missing '$3')"; cat "$2" >&2; fi; }
run() { # want(ok|fail) description dir command...
  want="$1"; desc="$2"; dir="$3"; shift 3
  if (cd "$dir" && "$@") >"$tmp/out" 2>&1; then got=ok; else got=fail; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (got $got, wanted $want)"; cat "$tmp/out" >&2; fi
}

git_init() {
  git init -q -b main "$1"
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
}
state() { # path feature lastApproved activePhase activeStatus verifyPassed reopenCount tier reason
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<JSON
{"feature": "$2", "tier": "$8", "lastApprovedPhase": "$3", "approvedPhases": [], "activePhase": "$4",
 "activeStatus": "$5", "blockedReason": "$9", "verifyPassed": $6, "reopenCount": $7}
JSON
}

# ---------------------------------------------------------------- stories-status.sh
m="$tmp/shop"
git_init "$m"
state "$m/docs/agents-v0/program.state.json" program plan "" "" false 0 standard ""
state "$m/docs/agents-v0/requirements/p0-a-platform-skeleton.state.json" p0-a-platform-skeleton release "" "" true 0 standard ""
git -C "$m" add -A && git -C "$m" commit -qm "main: program + p0"

run ok "stories-status: no worktrees" "$m" sh "$SS"
has "stories-status: lists program row" "$tmp/out" "| program"
has "stories-status: lists P0-A row" "$tmp/out" "p0-a-platform-skeleton"

git -C "$m" worktree add -q -b feature/orders "$tmp/shop-orders" main
git -C "$m" worktree add -q -b feature/refunds "$tmp/shop-refunds" main
git -C "$m" worktree add -q -b maintain/cve-1 "$tmp/shop-maintain-cve-1" main
state "$tmp/shop-orders/docs/agents-v0/requirements/orders.state.json" orders design build in_progress false 1 standard ""
printf '{ "feature": "refunds", "activePhase": ' > "$tmp/shop-refunds/docs/agents-v0/requirements/refunds.state.json"
state "$tmp/shop-maintain-cve-1/docs/agents-v0/maintain/cve-1/state.json" cve-1 "" maintain blocked false 0 emergency "Database runtime unavailable"
# A stale copy of orders on main that disagrees with the worktree.
state "$m/docs/agents-v0/requirements/orders.state.json" orders intake "" "" false 0 standard ""

before="$(cd "$tmp" && find shop shop-orders shop-refunds shop-maintain-cve-1 -path '*/.git' -prune -o -type f -print | sort | xargs cksum; git -C shop worktree list --porcelain)"
run ok "stories-status: main + 2 feature + 1 maintain worktree, one malformed" "$m" sh "$SS"
cp "$tmp/out" "$tmp/table"
has "stories-status: orders read from its worktree" "$tmp/table" "feature/orders"
has "stories-status: orders build in_progress" "$tmp/table" "in_progress"
has "stories-status: stale main copy flagged" "$tmp/table" "other copy differs: main checkout"
has "stories-status: malformed refunds reported" "$tmp/table" "malformed JSON"
has "stories-status: maintain row" "$tmp/table" "maintain/cve-1"
has "stories-status: blocked reason" "$tmp/table" "Database runtime unavailable"
after="$(cd "$tmp" && find shop shop-orders shop-refunds shop-maintain-cve-1 -path '*/.git' -prune -o -type f -print | sort | xargs cksum; git -C shop worktree list --porcelain)"
if [ "$before" = "$after" ]; then pass "stories-status: writes no files"; else fail "stories-status: files changed"; fi
run ok "stories-status --json" "$tmp/shop-orders" sh "$SS" --json
if python3 -c 'import json,sys; rows=json.load(open(sys.argv[1])); assert {r["story"] for r in rows} >= {"orders","refunds","cve-1","program"}, rows' "$tmp/out"; then
  pass "stories-status --json parses and lists every story (run from a worktree)"
else
  fail "stories-status --json content"
fi
run ok "stories-status --all-copies" "$m" sh "$SS" --all-copies
if [ "$(grep -c '| orders ' "$tmp/out")" = 2 ]; then pass "stories-status --all-copies shows both orders copies"; else fail "stories-status --all-copies"; cat "$tmp/out" >&2; fi
rm -rf "$tmp/shop-refunds"
run ok "stories-status: worktree folder removed by hand" "$m" sh "$SS"
has "stories-status: missing worktree folder reported" "$tmp/out" "worktree folder missing"
mkdir -p "$tmp/plain/docs/agents-v0/requirements"
state "$tmp/plain/docs/agents-v0/requirements/solo.state.json" solo intake design awaiting_approval false 0 standard ""
run ok "stories-status: not a git repository" "$tmp/plain" sh "$SS"
has "stories-status: non-git note" "$tmp/out" "not a git repository"
run fail "stories-status: unknown option is a usage error" "$m" sh "$SS" --bogus

# ---------------------------------------------------------------- check-lessons.sh
L="$tmp/lessons"
mkdir -p "$L/docs/agents-v0/requirements" "$L/docs/agents-v0/maintain/fix-1"
cp "$KIT/templates/docs/agents-v0/lessons.md" "$KIT/templates/docs/agents-v0/lessons-archive.md" "$L/docs/agents-v0/"
run ok "check-lessons: kit templates pass" "$L" sh "$CL"
run ok "check-lessons: --next-id on empty memory" "$L" sh "$CL" --next-id
has "check-lessons: first id is L-001" "$tmp/out" "L-001"

entry() { # id status
  printf '### %s · 2026-10-28 · %s\n- Story/phase: orders / build\n- Trigger: failure-brief\n- What happened: Migration used a reserved word.\n- Do instead: Check column names against the reserved-word list.\n- Scope: Stories that add a migration.\n' "$1" "$2"
}
good() {
  { printf '# Lessons\n\n## Active lessons\n\n'; entry L-002 accepted; printf '\n'; entry L-003 accepted; } > "$L/docs/agents-v0/lessons.md"
  { printf '# Lessons archive\n\n## Archived lessons\n\n'; entry L-001 promoted; printf -- '- Promoted to: docs/agents-v0/project-profile.md (Conventions)\n'; } > "$L/docs/agents-v0/lessons-archive.md"
}
good
run ok "check-lessons: good active + archive" "$L" sh "$CL"
run ok "check-lessons: --next-id after L-003" "$L" sh "$CL" --next-id
has "check-lessons: next id is L-004" "$tmp/out" "L-004"

good; sed -i.bak 's/^### L-003 · 2026-10-28 · accepted/### L-003 - 2026-10-28 - accepted/' "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: bad heading format" "$L" sh "$CL"
has "check-lessons: bad heading message" "$tmp/out" "bad entry heading"
good; sed -i.bak '/^- Do instead:/d' "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: missing Do instead bullet" "$L" sh "$CL"
good; sed -i.bak 's/^### L-003/### L-002/' "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: duplicate id" "$L" sh "$CL"
has "check-lessons: duplicate message" "$tmp/out" "duplicate id L-002"
good; sed -i.bak 's/^### L-003/### L-005/' "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: gap in ids" "$L" sh "$CL"
has "check-lessons: gap message" "$tmp/out" "missing L-003, L-004"
good; sed -i.bak '/^- Promoted to:/d' "$L/docs/agents-v0/lessons-archive.md"
run fail "check-lessons: promoted entry without pointer" "$L" sh "$CL"
good; sed -i.bak 's/· accepted/· promoted/' "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: lessons.md holds only accepted entries" "$L" sh "$CL"
good; sed -i.bak 's/^- Trigger: failure-brief/- Trigger: hunch/' "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: unknown trigger" "$L" sh "$CL"
good; long="$(python3 -c 'print("x" * 900)')"; sed -i.bak "s/^- Scope: Stories that add a migration./- Scope: $long/" "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: entry over the size limit" "$L" sh "$CL"
good; printf -- '- What happened: token=%s\n' "glpat-$(printf 'a%.0s' $(seq 1 24))" >> "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: fake GitLab token" "$L" sh "$CL"
has "check-lessons: secret message" "$tmp/out" "looks like a secret"
good; printf -- '- What happened: password: %s\n' "Hunter2Hunter2" >> "$L/docs/agents-v0/lessons.md"
run fail "check-lessons: password assignment" "$L" sh "$CL"
good; printf -- '- Note: password: <from vault>\n' >> "$L/docs/agents-v0/lessons.md"
run ok "check-lessons: placeholder password is not a secret" "$L" sh "$CL"
{ printf '# Lessons\n\n## Active lessons\n\n'; i=1; while [ $i -le 31 ]; do entry "$(printf 'L-%03d' $i)" accepted; i=$((i + 1)); done; } > "$L/docs/agents-v0/lessons.md"
printf '# Lessons archive\n\n## Archived lessons\n' > "$L/docs/agents-v0/lessons-archive.md"
run fail "check-lessons: 31 active entries over the default cap" "$L" sh "$CL"
has "check-lessons: cap message" "$tmp/out" "31 active entries (cap 30)"
run ok "check-lessons: --max-active 40 allows 31" "$L" sh "$CL" --max-active 40
run ok "check-lessons: LESSONS_MAX_ACTIVE=40 allows 31" "$L" env LESSONS_MAX_ACTIVE=40 sh "$CL"
good

PR="$L/docs/agents-v0/requirements/orders.phase-result.md"
cand() { printf -- '- Trigger: review · What happened: %s · Do instead: Validate ids server side. · Scope: Any {id} route.\n' "$1"; }
{ printf 'phase: build\nstatus: awaiting_approval\n\n## Lessons\n\n### design\n'; cand d1; printf '\n### build\n'; cand b1; cand b2; cand b3; printf '\n## Next\n- none\n'; } > "$PR"
run ok "check-lessons: 3 candidates in one phase" "$L" sh "$CL" --phase-result docs/agents-v0/requirements/orders.phase-result.md
{ printf 'phase: build\nstatus: awaiting_approval\n\n## Lessons\n\n### build\n'; cand b1; cand b2; cand b3; cand b4; } > "$PR"
run fail "check-lessons: 4 candidates in one phase" "$L" sh "$CL"
has "check-lessons: max-3 message" "$tmp/out" "4 lesson candidates for phase 'build' (max 3 per phase)"
{ printf '## Lessons\n\n### build\n- Trigger: review · What happened: x\n'; } > "$PR"
run fail "check-lessons: candidate missing fields" "$L" sh "$CL"
{ printf '## Lessons\n\n### shipping\n'; cand s1; } > "$PR"
run fail "check-lessons: unknown phase subsection" "$L" sh "$CL"
{ printf '## Lessons\n\n### verify\n- none\n'; } > "$PR"
run ok "check-lessons: '- none' candidate" "$L" sh "$CL"
{ printf '## Lessons\n\n### build\n'; cand "used key AKIAABCDEFGHIJKLMNOP"; } > "$PR"
run fail "check-lessons: fake AWS key in a candidate" "$L" sh "$CL"
{ printf '## Lessons\n\n### build\n'; cand b1; printf '\n## Proposed lessons\n- P-1 · pending · build · Trigger: review · What happened: x · Do instead: y · Scope: z\n'; } > "$PR"
run ok "check-lessons: pending proposal before the gate" "$L" sh "$CL"
run fail "check-lessons: --decided refuses a pending proposal" "$L" sh "$CL" --decided
sed -i.bak 's/P-1 · pending/P-1 · accepted/' "$PR"
run ok "check-lessons: --decided after the user decided" "$L" sh "$CL" --decided
printf -- '- P-2 accepted build Trigger: x\n' >> "$PR"
run fail "check-lessons: malformed proposal" "$L" sh "$CL"
rm -f "$PR" "$PR.bak"
printf '## Lessons\n\n### maintain\n' > "$L/docs/agents-v0/maintain/fix-1/phase-result.md"
cand m1 >> "$L/docs/agents-v0/maintain/fix-1/phase-result.md"
run ok "check-lessons: maintain phase-result" "$L" sh "$CL"

# Story-branch guard.
g="$tmp/guard"
git_init "$g"
mkdir -p "$g/docs/agents-v0"
cp "$KIT/templates/docs/agents-v0/lessons.md" "$KIT/templates/docs/agents-v0/lessons-archive.md" "$g/docs/agents-v0/"
git -C "$g" add -A && git -C "$g" commit -qm base
git -C "$g" checkout -qb feature/orders
run ok "check-lessons: --unchanged-since main on an untouched branch" "$g" sh "$CL" --unchanged-since main
printf '\nlocal note\n' >> "$g/docs/agents-v0/lessons.md"
run fail "check-lessons: uncommitted lessons.md edit on a story branch" "$g" sh "$CL" --unchanged-since main
git -C "$g" commit -qam "edit lessons on story branch"
run fail "check-lessons: committed lessons.md edit on a story branch" "$g" sh "$CL" --unchanged-since main
has "check-lessons: guard message" "$tmp/out" "Story branches never edit lessons.md"
run fail "check-lessons: unknown ref" "$g" sh "$CL" --unchanged-since no-such-branch

# ---------------------------------------------------------------- install.sh seeds the memory files
t="$tmp/target"
git_init "$t"
if sh "$KIT/scripts/install.sh" "$t" >"$tmp/install.log" 2>&1; then
  for f in .agents-v0/scripts/stories-status.sh .agents-v0/scripts/check-lessons.sh; do
    if [ -x "$t/$f" ]; then pass "install.sh installs $f (executable)"; else fail "install.sh did not install $f"; fi
  done
  for f in docs/agents-v0/lessons.md docs/agents-v0/lessons-archive.md; do
    if [ -f "$t/$f" ]; then pass "install.sh seeds $f"; else fail "install.sh did not seed $f"; fi
  done
  run ok "check-lessons: passes in a fresh install" "$t" sh .agents-v0/scripts/check-lessons.sh
  run ok "stories-status: runs in a fresh install" "$t" sh .agents-v0/scripts/stories-status.sh
else
  fail "install.sh into a fresh target"; cat "$tmp/install.log" >&2
fi

if [ "$status" = 0 ]; then
  printf 'test-memory: OK\n'
else
  printf 'test-memory: FAILED\n' >&2
fi
exit "$status"
