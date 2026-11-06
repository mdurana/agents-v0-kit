#!/bin/sh
# test-guard-plan.sh (plan redo, Design: DP8): full lifecycle tests for guard-plan.sh
# (check, start, block, ready, commit, steps, and intake handoff).
# Run: sh scripts/test-guard-plan.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

# git identity of its own
for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-plan.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi

export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"

js() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], "<missing>"); print(v)' "$1" "$2" 2>&1; }

proj="$tmp/proj"
mkdir -p "$proj" && git -C "$proj" init -q -b main && printf 'x\n' > "$proj/README.md" \
  && git -C "$proj" add README.md && git -C "$proj" commit -q -m init

# Copy template scripts into target repo
mkdir -p "$proj/.agents-v0/scripts" "$proj/docs/agents-v0/roadmap" "$proj/docs/agents-v0/adr" \
  "$proj/docs/agents-v0/design/system/components" "$proj/docs/agents-v0/milestones" "$proj/docs/product"
cp "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-roadmap.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-architecture.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-plan.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/secret_scan.py" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/sync-feature-state.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/check-gate-commit.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$proj/.agents-v0/"
cp "$ROOT/templates/docs/agents-v0/roadmap/_template.md" "$proj/docs/agents-v0/roadmap/"
cp "$ROOT/templates/docs/agents-v0/architecture.md" "$proj/docs/agents-v0/"
cp "$ROOT/templates/docs/agents-v0/network.md" "$proj/docs/agents-v0/"
git -C "$proj" add .agents-v0 docs/agents-v0
git -C "$proj" commit -qm "install kit templates"

GP="$proj/.agents-v0/scripts/guard-plan.sh"
GA="$proj/.agents-v0/scripts/guard-architecture.sh"
GR="$proj/.agents-v0/scripts/guard-roadmap.sh"
S="$proj/docs/agents-v0/program.state.json"

pty_approve() {
  python3 - "$proj" "$proj/.agents-v0/scripts/guard-common.sh" "$1" "Approved by Sensei" <<'PY'
import os, pty, sys, time
proj, script, cmd, words = sys.argv[1:5]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.execvp("sh", ["sh", script, "approve", cmd])
buf, sent, end = b"", False, time.time() + 30
while time.time() < end:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    if not sent and b"Type your approval words" in buf:
        os.write(fd, words.encode() + b"\r")
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

# --- 1. check before architecture approval -----------------------------------------------------
out="$(cd "$proj" && sh "$GP" check 2>&1 || true)"
printf '%s' "$out" | grep -Eq 'REFUSED check: (no program state|architecture is not in approvedPhases)'; check $? "check: refuses when architecture is not approved" "$out"

# Complete and approve roadmap first
cat <<EOF > "$proj/docs/product/claims-discovery.md"
# Claims Discovery
## Problem
Paper claims take 14 days.
## Success metric
Reduce latency to 48 hours.
## Options
1. OCR pipeline
2. Manual portal
## Chosen option
OCR pipeline with human review.
## In scope
- SFTP intake
- OCR worker
## Out of scope
- Fax intake
EOF
git -C "$proj" add docs/product/claims-discovery.md && git -C "$proj" commit -qm "add discovery"
disc_hash=$(python3 -c "import hashlib, sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$proj/docs/product/claims-discovery.md")
(cd "$proj" && sh "$GR" start docs/product/claims-discovery.md >/dev/null)
cat <<EOF > "$proj/docs/agents-v0/roadmap/claims.md"
# Roadmap: claims
Discovery: docs/product/claims-discovery.md (sha256: $disc_hash)
## Problem
Paper claims take 14 days.
## Success metric
Reduce latency to 48 hours.
## Chosen option
OCR pipeline with human review.
## Now
- SFTP intake
## Next
- OCR worker
## Later
- Ledger webhook
## Out of scope
- Fax intake
## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
(cd "$proj" && sh "$GR" ready docs/product/claims-discovery.md >/dev/null)
pty_approve roadmap >/dev/null
(cd "$proj" && sh "$GR" commit >/dev/null)

# Complete and approve architecture
(cd "$proj" && sh "$GA" start >/dev/null)
cat <<'EOF' > "$proj/docs/agents-v0/architecture.md"
# System Architecture
## C4 Context
```mermaid
flowchart LR
  user["User"]
```
## C4 Container
```mermaid
flowchart LR
  app["App"]
```
## Data flow
```mermaid
sequenceDiagram
  User->>App: Action
```
## Data models
```mermaid
erDiagram
  DATA ||--o{ ITEM : has
```
## State machine
```mermaid
stateDiagram-v2
  [*] --> State
```
## Failure domains and degradation
None.
## MVP and future state
MVP.
## Architecture Decision Records
- `docs/agents-v0/adr/0001-modular.md`
## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
cat <<'EOF' > "$proj/docs/agents-v0/network.md"
# Network Topology
## Target topology
```mermaid
flowchart LR
  edge["Edge"]
```
EOF
cat <<'EOF' > "$proj/docs/agents-v0/adr/0001-modular.md"
# ADR 0001
- **Status:** Proposed
Pack: python
EOF
for sf in context-map.md nfr-slo.md threat-model.md ops-readiness.md arc-record.md; do
  printf '# %s\n' "$sf" > "$proj/docs/agents-v0/design/system/$sf"
done
printf 'agent: design-reviewer\n\n# Review\n\n| # | Category | Severity | Finding | Status |\n|---|---|---|---|---|\n' > "$proj/docs/agents-v0/design/system/architecture-review.md"

(cd "$proj" && sh "$GA" ready >/dev/null)
pty_approve architecture >/dev/null
(cd "$proj" && sh "$GA" commit >/dev/null)

# Brownfield without onboard approval redirects to /v0-onboard (FP7)
mkdir -p "$proj/src" && echo "code" > "$proj/src/app.py"
git -C "$proj" add src/app.py && git -C "$proj" commit -qm "add code"
out="$(cd "$proj" && sh "$GP" check 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: existing codebase detected without onboarding approval'; check $? "check: brownfield redirects to /v0-onboard (FP7)" "$out"

# Add onboard approval to state
mkdir -p "$proj/docs/agents-v0/onboarding"
printf '{"approvedPhases":["onboard"]}\n' > "$proj/docs/agents-v0/onboarding/state.json"
git -C "$proj" add docs/agents-v0/onboarding/state.json && git -C "$proj" commit -qm "onboard approved"

# Check now passes
out="$(cd "$proj" && sh "$GP" check 2>&1)"
check $? "check: passes when architecture and onboard are approved" "$out"
printf '%s' "$out" | grep -q '^OK check: prerequisites satisfied'; check $? "check: prints OK check" "$out"

# --- 2. start & block --------------------------------------------------------------------------
out="$(cd "$proj" && sh "$GP" start 2>&1)"
check $? "start: exits 0" "$out"
printf '%s' "$out" | grep -q '^OK start: plan state is in_progress'; check $? "start: prints OK start" "$out"
[ -f "$proj/docs/agents-v0/milestones/plan.md" ]; check $? "start: seeds plan.md if absent"
[ "$(js "$S" activePhase)" = plan ]; check $? "start: activePhase is plan"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus is in_progress"

out="$(cd "$proj" && sh "$GP" block "Waiting on product clarification" 2>&1)"
check $? "block: exits 0" "$out"
printf '%s' "$out" | grep -q 'OK block: plan state is blocked: Waiting on product clarification'; check $? "block: prints OK block with reason" "$out"
[ "$(js "$S" activeStatus)" = blocked ]; check $? "block: activeStatus is blocked"

out="$(cd "$proj" && sh "$GP" start 2>&1)"
check $? "start: resumes from blocked state" "$out"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus restored to in_progress"

# --- 3. ready validation (negative & positive) -------------------------------------------------
# Fails when plan.md has no story diagram or missing manifests
out="$(cd "$proj" && sh "$GP" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED ready:'; check $? "ready: refuses incomplete plan" "$out"

# Setup valid plan.md and milestones
cat <<'EOF' > "$proj/docs/agents-v0/milestones/plan.md"
# Program Plan

## Milestones

| Milestone | Stories | What they cover |
|---|---|---|
| P0 | P0-A | Platform baseline |
| P1 | P1-A, P1-B | Contracts and data model |

## Story Dependency Graph

```mermaid
flowchart TD
  P0A[P0-A] --> P1A[P1-A]
  P1A --> P1B[P1-B]
```
EOF

# Manifest with cycle (P1-A -> P1-B -> P1-A)
cat <<'EOF' > "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"
# Milestone: P0
## Stories
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P0-A | As a developer, I want a baseline, so that work starts. | docs/agents-v0/requirements/p0-a.md | planned | — | vertical slice | 4 |
EOF

cat <<'EOF' > "$proj/docs/agents-v0/milestones/p1-contracts.md"
# Milestone: P1
## Stories
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P1-A | As a client, I want an API, so that I can call it. | docs/agents-v0/requirements/p1-a.md | planned | P1-B | backend | 3 |
| P1-B | As a service, I want storage, so that I can persist. | docs/agents-v0/requirements/p1-b.md | planned | P1-A | backend | 3 |
EOF

out="$(cd "$proj" && sh "$GP" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'dependency cycle detected in milestones'; check $? "ready: catches dependency cycles (Jiraiya Rec 1)" "$out"

# Fix cycle and make dependencies valid
cat <<'EOF' > "$proj/docs/agents-v0/milestones/p1-contracts.md"
# Milestone: P1
## Stories
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P1-A | As a client, I want an API, so that I can call it. | docs/agents-v0/requirements/p1-a.md | planned | P0-A | backend | 3 |
| P1-B | As a service, I want storage, so that I can persist. | docs/agents-v0/requirements/p1-b.md | planned | P1-A | backend | 3 |
EOF

out="$(cd "$proj" && sh "$GP" ready 2>&1)"
check $? "ready: exits 0 on valid manifests and plan.md" "$out"
printf '%s' "$out" | grep -q '^OK ready: plan verified'; check $? "ready: prints OK ready" "$out"
[ -f "$proj/docs/agents-v0/milestones/plan.phase-result.md" ]; check $? "ready: writes plan.phase-result.md"
[ "$(js "$S" activeStatus)" = awaiting_approval ]; check $? "ready: activeStatus is awaiting_approval"

# Self-approval via sync-feature-state.sh is refused without external approval record (FP1, DPA)
out="$(cd "$proj" && sh .agents-v0/scripts/sync-feature-state.sh --approve plan docs/agents-v0/milestones/plan.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'FAIL: --approve plan refused without Sensei external approval record'; check $? "sync-feature-state: refuses --approve plan without Sensei record (FP1, DPA)" "$out"

# Commit refused before approve
out="$(cd "$proj" && sh "$GP" commit 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED commit: plan is not approved'; check $? "commit: refused before approval" "$out"

# --- 4. approve via pty & commit ---------------------------------------------------------------
pty_approve plan >/dev/null
rec_file="$(cd "$proj" && GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_file plan)"
[ -f "$rec_file" ]; check $? "approve: wrote plan approval record outside repo"

out="$(cd "$proj" && sh "$GP" commit 2>&1)"
check $? "commit: exits 0 after Sensei approve" "$out"
printf '%s' "$out" | grep -q '^OK commit: plan committed on main as .*, tagged plan-v1'; check $? "commit: prints OK commit with tag" "$out"
git -C "$proj" tag | grep -qx 'plan-v1'; check $? "commit: plan-v1 tag created"
git -C "$proj" log -1 --format=%s | grep -qx 'program: plan approved'; check $? "commit: gate commit message is 'program: plan approved'"
grep -q '| plan |' "$proj/docs/agents-v0/milestones/plan.md"; check $? "commit: Delivery approvals row appended to plan.md"
grep -q '| plan |' "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"; check $? "commit: Delivery approvals row appended to p0-platform-skeleton.md (FP5)"
grep -q '| plan |' "$proj/docs/agents-v0/milestones/p1-contracts.md"; check $? "commit: Delivery approvals row appended to p1-contracts.md (FP5)"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
