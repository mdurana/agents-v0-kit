#!/bin/sh
# test-command-flows.sh — follow the /v0-* gate steps as the command files state them, in a real git
# repo with the delivery-gate hooks installed, and assert that:
#   * the right step passes (a correct artifact commits),
#   * each "agent skipped a step" variant is blocked (a wrong Approved row never reaches a commit),
#   * the manifest, gate.sh, pre-commit, the after-edit hook, install --git-hooks, and the --update
#     in-flight guard agree with each other.
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

# in <dir> <command...>: run in <dir>.
expect_pass() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then pass "$desc"; else fail "$desc (expected exit 0)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
}
expect_fail() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then fail "$desc (expected non-zero)"; sed 's/^/    /' "$tmp/out.txt" >&2; else pass "$desc"; fi
}
expect_out() { # <description> <pattern> — the last command's output must match.
  if grep -Eq "$2" "$tmp/out.txt"; then pass "$1"; else fail "$1 (output lacks: $2)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
}
commit() { # <dir> <message> — plain commit (the repo hooks apply).
  (cd "$1" && git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$2")
}

# new_repo <dir> [--git-hooks]: a scratch repo with the kit installed from this checkout.
new_repo() {
  d="$1"; shift
  mkdir -p "$d"
  git -C "$d" init -q -b main
  (cd "$d" && sh "$KIT/scripts/install.sh" "$@" "$d" >/dev/null 2>&1) || { fail "install.sh $* into $d"; return 1; }
  git -C "$d" add -A
  commit "$d" base
}

# ---------------------------------------------------------------------------------------------
# install.sh --git-hooks and the --update in-flight guard
# ---------------------------------------------------------------------------------------------
plain="$tmp/plain"
new_repo "$plain"
[ -f "$plain/.agents-v0/ci/gate.sh" ] && [ -f "$plain/.agents-v0/ci/gates.json" ] && [ -x "$plain/.agents-v0/hooks/pre-commit" ] \
  && pass "install seeds gate.sh, gates.json, and an executable pre-commit hook" \
  || fail "install seeds gate.sh, gates.json, and an executable pre-commit hook"
[ -z "$(git -C "$plain" config --get core.hooksPath || true)" ] \
  && pass "install without --git-hooks leaves core.hooksPath unset" \
  || fail "install without --git-hooks leaves core.hooksPath unset"

r="$tmp/r"
new_repo "$r" --git-hooks
[ "$(git -C "$r" config --get core.hooksPath)" = ".agents-v0/hooks" ] \
  && pass "install --git-hooks sets core.hooksPath=.agents-v0/hooks" \
  || fail "install --git-hooks sets core.hooksPath=.agents-v0/hooks"

mkdir -p "$plain/docs/agents-v0/requirements"
printf '{"activePhase":"build","activeStatus":"in_progress"}\n' > "$plain/docs/agents-v0/requirements/orders.state.json"
if (cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update "$plain") >"$tmp/out.txt" 2>&1; then
  fail "install --update refuses while a story is in progress"
else
  pass "install --update refuses while a story is in progress"
  expect_out "the refusal names the story and the override" 'orders.state.json.*activePhase=build|allow-in-flight'
fi
if (cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update --allow-in-flight "$plain") >"$tmp/out.txt" 2>&1; then
  pass "install --update --allow-in-flight updates anyway"
else
  fail "install --update --allow-in-flight updates anyway"; sed 's/^/    /' "$tmp/out.txt" >&2
fi
printf '{"activePhase":"","activeStatus":""}\n' > "$plain/docs/agents-v0/requirements/orders.state.json"
if (cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update "$plain") >"$tmp/out.txt" 2>&1; then
  pass "install --update proceeds once no story is in progress"
else
  fail "install --update proceeds once no story is in progress"; sed 's/^/    /' "$tmp/out.txt" >&2
fi

# ---------------------------------------------------------------------------------------------
# /v0-roadmap: preflight -> write -> gate -> approve -> gate --approved -> commit
# ---------------------------------------------------------------------------------------------
mkdir -p "$r/docs/product" "$r/docs/agents-v0/roadmap"
cat > "$r/docs/product/claims-discovery.md" <<'EOF'
# Claims Discovery
## Problem
Slow batch claim adjudication.
## Success metric
Adjudication time under 15 minutes.
## Options
### Option A: In-memory queue
Single-node queue for batch processing.
### Option B: Event stream
Partitioned log for high-throughput streams.
## Chosen option
Option A.
## In scope
- Batch file ingestion
- Adjudication rules engine
## Out of scope
- Real-time mobile push notifications
EOF
disc_hash="$(python3 -c 'import hashlib, sys; sys.stdout.write(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$r/docs/product/claims-discovery.md")"
write_roadmap() { # <file> [approval-row]
  cat > "$1" <<EOF
# Roadmap: claims

Discovery: docs/product/claims-discovery.md (sha256: $disc_hash)

## Problem
Slow batch claim adjudication.

## Success metric
Adjudication time under 15 minutes.

## Chosen option
Option A.

## Now
- Batch file ingestion

## Next
- Adjudication rules engine

## Later

## Out of scope
- Real-time mobile push notifications

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
${2:-}
EOF
}
RM="docs/agents-v0/roadmap/claims.md"
write_roadmap "$r/$RM"
expect_pass "roadmap: gate.sh roadmap passes a correct draft" "$r" sh .agents-v0/ci/gate.sh roadmap "$RM"
expect_fail "roadmap: gate.sh roadmap --approved fails before the Approved row" "$r" sh .agents-v0/ci/gate.sh roadmap --approved "$RM"
(cd "$r" && git add -A && commit "$r" "roadmap draft") \
  && pass "roadmap: a draft with no Approved row commits (pre-commit stays out of the way)" \
  || fail "roadmap: a draft with no Approved row commits (pre-commit stays out of the way)"

# Agent skipped step: Approved row written while the discovery changed after the roadmap was drafted.
printf '\n- Extra scope item\n' >> "$r/docs/product/claims-discovery.md"
write_roadmap "$r/$RM" "| roadmap | $RM, docs/product/claims-discovery.md | dev | Approved | 2026-01-01 |"
(cd "$r" && git add -A)
if (cd "$r" && git -c user.name=test -c user.email=test@example.com commit -q -m "approve stale roadmap") >"$tmp/out.txt" 2>&1; then
  fail "roadmap: pre-commit blocks an Approved row whose discovery hash is stale"
else
  pass "roadmap: pre-commit blocks an Approved row whose discovery hash is stale"
  expect_out "roadmap: the block names the failing check" 'FAIL gate|check-roadmap'
fi
git -C "$r" reset -q --hard HEAD

# Correct approval commits.
write_roadmap "$r/$RM" "| roadmap | $RM, docs/product/claims-discovery.md | dev | Approved | 2026-01-01 |"
expect_pass "roadmap: gate.sh roadmap --approved passes with a correct Approved row" "$r" sh .agents-v0/ci/gate.sh roadmap --approved "$RM"
(cd "$r" && git add -A && commit "$r" "approve roadmap") \
  && pass "roadmap: a correct Approved row commits" \
  || fail "roadmap: a correct Approved row commits"

# Agent skipped step: editing the sealed, approved roadmap without re-approval (content drifts from discovery).
sedi 's/^- Batch file ingestion$/- Batch file ingestion\n- Invented theme/' "$r/$RM"
(cd "$r" && git add -A)
if (cd "$r" && git -c user.name=test -c user.email=test@example.com commit -q -m "edit sealed roadmap") >/dev/null 2>&1; then
  fail "roadmap: pre-commit blocks an invented item added to an approved roadmap"
else
  pass "roadmap: pre-commit blocks an invented item added to an approved roadmap"
fi
git -C "$r" reset -q --hard HEAD

# --no-verify is the one way past the hook, and the shell policy refuses an agent that tries it.
act="$(HOOK_CMD='git commit --no-verify -m skip' python3 "$KIT/core/common/hooks/hook-policy.py" shell)"
case "$act" in *'"block"'*) pass "an agent cannot skip pre-commit with --no-verify" ;; *) fail "an agent cannot skip pre-commit with --no-verify ($act)" ;; esac

# ---------------------------------------------------------------------------------------------
# after-edit hook: advisory gate output reaches the agent, and the hook still exits 0
# ---------------------------------------------------------------------------------------------
cp -R "$KIT/core/common/hooks" "$r/.after-edit-hooks"
write_roadmap "$r/$RM" ""
sedi 's/^- Batch file ingestion$/- Invented theme/' "$r/$RM"
out="$(cd "$r" && printf '{"file_path":"%s/%s"}' "$r" "$RM" | sh .after-edit-hooks/after-edit.sh 2>/dev/null)" && rc=0 || rc=$?
[ "$rc" = 0 ] && pass "after-edit hook stays warning-only (exit 0) when the gate fails" || fail "after-edit hook stays warning-only (exit 0) when the gate fails (rc=$rc)"
printf '%s' "$out" | grep -q 'phase gate' \
  && pass "after-edit hook hands the failing gate to the agent as context" \
  || fail "after-edit hook hands the failing gate to the agent as context (got: $out)"
rm -rf "$r/.after-edit-hooks"
git -C "$r" checkout -q -- "$RM"

# ---------------------------------------------------------------------------------------------
# /v0-plan: gate plan -> approve -> gate plan --approved (a manifest with no Approved plan row is not an approval)
# ---------------------------------------------------------------------------------------------
mkdir -p "$r/docs/agents-v0/milestones"
cat > "$r/docs/agents-v0/milestones/p1.md" <<'EOF'
# Milestone: P1

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| P1-A | As a clerk, I want to place an order, so that stock is reserved. | docs/agents-v0/requirements/orders.md | planned | — | backend | 3 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
expect_fail "plan: gate.sh plan --approved fails before the plan row" "$r" sh .agents-v0/ci/gate.sh plan --approved docs/agents-v0/milestones/p1.md
(cd "$r" && git add -A && commit "$r" "plan draft") && pass "plan: a manifest with no plan row commits" || fail "plan: a manifest with no plan row commits"

# ---------------------------------------------------------------------------------------------
# /v0-intake: gate intake -> approve -> gate intake --approved; an Approved row on a failing story is blocked
# ---------------------------------------------------------------------------------------------
mkdir -p "$r/docs/agents-v0/requirements"
write_story() { # <file> <approval-row> <then-line>
  cat > "$1" <<EOF
# Orders

As a clerk, I want to place an order, so that stock is reserved.

Milestone: P1
Milestone file: docs/agents-v0/milestones/p1.md
Story: P1-A
Surfaces: backend
Material: no

## Preconditions
The clerk is signed in and fixture CUST-1 exists.

## Desk check
Call POST /api/v1/orders with fixture CUST-1 and confirm the order row.

## Acceptance criteria

### AC-1 — place the order
Kind: happy
Given a signed-in clerk and fixture CUST-1
When the clerk places an order for SKU-1
Then $3

### AC-2 — reject an unsigned clerk
Kind: negative
Given no session for fixture CUST-1
When the clerk places an order
Then HTTP 401 and no order row is written

## Out of scope
- Mobile checkout

## NFRs
The place-order call returns within two seconds for fixture CUST-1.

## Regulations
N/A: no personal data beyond the customer id already stored.

## Security-review triggers
- auth: the clerk must be signed in

## Open questions
none

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
$2
EOF
}
ORD="docs/agents-v0/requirements/orders.md"
write_story "$r/$ORD" "" "HTTP 201 and the order row is stored with status PENDING"
expect_pass "intake: gate.sh intake passes a correct story" "$r" sh .agents-v0/ci/gate.sh intake "$ORD"
(cd "$r" && git add -A && commit "$r" "intake draft") && pass "intake: a draft story with no Approved row commits" || fail "intake: a draft story with no Approved row commits"

# Agent skipped step: Approved row on a story whose Then is only a stub.
write_story "$r/$ORD" "| intake | $ORD | dev | Approved | 2026-01-01 |" "ok"
(cd "$r" && git add -A)
if (cd "$r" && git -c user.name=test -c user.email=test@example.com commit -q -m "approve weak intake") >"$tmp/out.txt" 2>&1; then
  fail "intake: pre-commit blocks an Approved intake row on a story that fails check-intake"
else
  pass "intake: pre-commit blocks an Approved intake row on a story that fails check-intake"
fi
git -C "$r" reset -q --hard HEAD

write_story "$r/$ORD" "| intake | $ORD | dev | Approved | 2026-01-01 |" "HTTP 201 and the order row is stored with status PENDING"
(cd "$r" && git add -A && commit "$r" "approve intake") && pass "intake: a correct Approved intake row commits" || fail "intake: a correct Approved intake row commits"

# A conditional approval is not an approval, so the gate does not run and cannot be skipped by wording it differently.
write_story "$r/$ORD" "| intake | $ORD | dev | Approved with conditions: add AC | 2026-01-01 |" "HTTP 201 and the order row is stored with status PENDING"
expect_fail "intake: gate.sh intake --approved rejects a conditional approval" "$r" sh .agents-v0/ci/gate.sh intake --approved "$ORD"
git -C "$r" checkout -q -- "$ORD"

# verify gate: gate.sh verify --approved enforces evidence checks
write_story "$r/$ORD" "| intake | $ORD | dev | Approved | 2026-01-01 |
| verify | $ORD | dev | Approved | 2026-01-01 |" "HTTP 201 and the order row is stored with status PENDING"
expect_fail "verify: gate.sh verify --approved fails when evidence reports are missing" "$r" sh .agents-v0/ci/gate.sh verify --approved "$ORD"
git -C "$r" checkout -q -- "$ORD"

head_sha="$(git -C "$r" rev-parse HEAD)"
mkdir -p "$r/docs/agents-v0/verify/orders"
write_story "$r/$ORD" "| intake | $ORD | dev | Approved | 2026-01-01 |
| verify | docs/agents-v0/verify/orders/test-report.md | dev | Approved | 2026-01-01 |" "HTTP 201 and the order row is stored with status PENDING"

# (1) untracked report -> gate.sh verify --approved FAILS
printf 'commit: %s\nkit-version: test\nagent: test-engineer\n' "$head_sha" > "$r/docs/agents-v0/verify/orders/test-report.md"
expect_fail "verify: gate.sh verify --approved fails with untracked verify report" "$r" sh .agents-v0/ci/gate.sh verify --approved "$ORD"

# (2) staged report -> passes the evidence check
(cd "$r" && git add docs/agents-v0/verify/orders/test-report.md)
expect_pass "verify: gate.sh verify --approved passes with staged verify report" "$r" sh .agents-v0/ci/gate.sh verify --approved "$ORD"

# (3) non-SHA commit: stamp -> FAILS
printf 'commit: not-a-sha\nkit-version: test\nagent: test-engineer\n' > "$r/docs/agents-v0/verify/orders/test-report.md"
(cd "$r" && git add docs/agents-v0/verify/orders/test-report.md)
expect_fail "verify: gate.sh verify --approved fails when commit: is non-SHA" "$r" sh .agents-v0/ci/gate.sh verify --approved "$ORD"

# committed report passes
printf 'commit: %s\nkit-version: test\nagent: test-engineer\n' "$head_sha" > "$r/docs/agents-v0/verify/orders/test-report.md"
(cd "$r" && git add docs/agents-v0/verify/orders/test-report.md && commit "$r" "verify report")
expect_pass "verify: gate.sh verify --approved passes with committed verify report" "$r" sh .agents-v0/ci/gate.sh verify --approved "$ORD"
git -C "$r" reset -q --hard HEAD~1
git -C "$r" checkout -q -- "$ORD"

# ---------------------------------------------------------------------------------------------
# gate.sh itself
# ---------------------------------------------------------------------------------------------
expect_fail "gate.sh rejects an unknown phase" "$r" sh .agents-v0/ci/gate.sh nonsense "$ORD"
expect_fail "gate.sh rejects a missing artifact" "$r" sh .agents-v0/ci/gate.sh intake docs/agents-v0/requirements/missing.md
expect_pass "gate.sh --list prints every phase" "$r" sh .agents-v0/ci/gate.sh --list
expect_pass "gate.sh --staged with nothing staged passes" "$r" sh .agents-v0/ci/gate.sh --staged
cp "$r/.agents-v0/ci/gates.json" "$tmp/gates.bak"
python3 - "$r/.agents-v0/ci/gates.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["phases"]["intake"]["draft"].append({"run": ["ci/check-does-not-exist.sh"]})
json.dump(d, open(p, "w"))
PY
expect_fail "gate.sh fails a phase whose manifest names a missing script" "$r" sh .agents-v0/ci/gate.sh intake "$ORD"
cp "$tmp/gates.bak" "$r/.agents-v0/ci/gates.json"

if [ "$status" -ne 0 ]; then
  echo "test-command-flows: FAILED" >&2
  exit 1
fi
echo "test-command-flows: OK"
