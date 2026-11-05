#!/bin/sh
# test-guard-architecture.sh (architecture redo, Design: DA8): full lifecycle tests for guard-architecture.sh
# (check, start, block, ready, commit, steps, and /v0-plan handoff).
# Run: sh scripts/test-guard-architecture.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

# git identity of its own
for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-architecture.XXXXXX")"
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
cp "$ROOT/templates/.agents-v0/scripts/secret_scan.py" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/sync-feature-state.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/check-gate-commit.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$proj/.agents-v0/"
cp "$ROOT/templates/docs/agents-v0/roadmap/_template.md" "$proj/docs/agents-v0/roadmap/"
cp "$ROOT/templates/docs/agents-v0/architecture.md" "$proj/docs/agents-v0/"
cp "$ROOT/templates/docs/agents-v0/network.md" "$proj/docs/agents-v0/"
printf '# Program Plan\n' > "$proj/docs/agents-v0/milestones/plan.md"
git -C "$proj" add .agents-v0 docs/agents-v0
git -C "$proj" commit -qm "install kit templates"

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

# --- 1. check before roadmap approval ----------------------------------------------------------
out="$(cd "$proj" && sh "$GA" check 2>&1 || true)"
printf '%s' "$out" | grep -Eq 'REFUSED check: (no program state|roadmap is not approved)'; check $? "check: refuses when roadmap is not approved" "$out"

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

# Brownfield without onboard approval redirects to /v0-onboard (FA7)
mkdir -p "$proj/src" && echo "code" > "$proj/src/app.py"
git -C "$proj" add src/app.py && git -C "$proj" commit -qm "add code"
out="$(cd "$proj" && sh "$GA" check 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: existing codebase detected without onboarding approval'; check $? "check: brownfield redirects to /v0-onboard (FA7)" "$out"

# Add onboard approval to state
mkdir -p "$proj/docs/agents-v0/onboarding"
printf '{"approvedPhases":["onboard"]}\n' > "$proj/docs/agents-v0/onboarding/state.json"
git -C "$proj" add docs/agents-v0/onboarding/state.json && git -C "$proj" commit -qm "onboard approved"

# Check now passes
out="$(cd "$proj" && sh "$GA" check 2>&1)"
check $? "check: passes when roadmap and onboard are approved" "$out"
printf '%s' "$out" | grep -q '^OK check: prerequisites satisfied'; check $? "check: prints OK check" "$out"

# --- 2. start & block --------------------------------------------------------------------------
out="$(cd "$proj" && sh "$GA" start 2>&1)"
check $? "start: exits 0" "$out"
printf '%s' "$out" | grep -q '^OK start: architecture state is in_progress'; check $? "start: prints OK start" "$out"
[ "$(js "$S" activePhase)" = architecture ]; check $? "start: activePhase is architecture"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus is in_progress"
[ "$(js "$S" artifact)" = "docs/agents-v0/architecture.md" ]; check $? "start: artifact is docs/agents-v0/architecture.md"

out="$(cd "$proj" && sh "$GA" block "Waiting on security zone confirmation" 2>&1)"
check $? "block: exits 0" "$out"
printf '%s' "$out" | grep -q 'OK block: architecture state is blocked: Waiting on security zone confirmation'; check $? "block: prints OK block with reason" "$out"
[ "$(js "$S" activeStatus)" = blocked ]; check $? "block: activeStatus is blocked"

out="$(cd "$proj" && sh "$GA" start 2>&1)"
check $? "start: resumes from blocked state" "$out"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus restored to in_progress"

# --- 3. ready validation (negative & positive) -------------------------------------------------
# Fails on template placeholders in architecture.md
out="$(cd "$proj" && sh "$GA" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED ready:'; check $? "ready: refuses unauthored template" "$out"

# Author complete architecture.md and network.md
cat <<'EOF' > "$proj/docs/agents-v0/architecture.md"
# System Architecture

## C4 Context
```mermaid
flowchart LR
  user["Claimant"] -->|"HTTPS"| portal["Claims Portal"]
```

## C4 Container
```mermaid
flowchart LR
  portal["Portal UI"] -->|"REST JSON"| api["Claims Service"]
  api -->|"SQL"| db[("Claims DB")]
```

## Data flow
```mermaid
sequenceDiagram
  Claimant->>Claims Service: POST /claims
  Claims Service->>Claims DB: INSERT claim
```

## Data models
```mermaid
erDiagram
  CLAIM ||--o{ DOCUMENT : contains
```

## State machine
```mermaid
stateDiagram-v2
  [*] --> Received
  Received --> Processed
```

## Failure domains and degradation
Bulkhead between SFTP ingestion and synchronous REST API.

## MVP and future state
MVP covers SFTP intake and OCR worker; future adds ledger webhooks.

## Architecture Decision Records
- `docs/agents-v0/adr/0001-modular-monolith.md`

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF

cat <<'EOF' > "$proj/docs/agents-v0/network.md"
# Network Topology

## Target topology
```mermaid
flowchart LR
  edge["Public Edge"] -->|"mTLS"| app["Application Zone"]
  app -->|"TCP 5432"| data["Data Zone"]
```

## Zone Inventory
| Zone | Purpose | Ingress | Egress |
|------|---------|---------|--------|
| Public Edge | TLS termination | 443 | App Zone |
| Application Zone | Claims API | Edge | Data Zone |
| Data Zone | PostgreSQL | App Zone | None |
EOF

# Fails when pattern ADR is missing
out="$(cd "$proj" && sh "$GA" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'no pattern ADR found under docs/agents-v0/adr/'; check $? "ready: refuses missing pattern ADR with Pack: <id>" "$out"

# Write pattern ADR (Proposed) and system design files
cat <<'EOF' > "$proj/docs/agents-v0/adr/0001-modular-monolith.md"
# ADR 0001: Modular Monolith on Python

- **Status:** Proposed
- **Deciders:** <approvers>
- **Date:** YYYY-MM-DD

Pack: python

## Context
Need low operational overhead for MVP claims intake.

## Decision
Use a Python modular monolith (`Pack: python`) over microservices.
EOF

for sf in context-map.md nfr-slo.md threat-model.md ops-readiness.md arc-record.md; do
  printf '# %s\n\nConcrete content for %s referencing ADR 0001 (Proposed).\n' "$sf" "$sf" > "$proj/docs/agents-v0/design/system/$sf"
done
printf '# Claims Component\n\nImplements ADR 0001 (Proposed).\n' > "$proj/docs/agents-v0/design/system/components/claims.md"

# Fails when architecture-review.md has Open findings (FA3)
cat <<'EOF' > "$proj/docs/agents-v0/design/system/architecture-review.md"
agent: design-reviewer

# Architecture Review
Reviewed against ADR 0001 (Proposed).

| # | Category | Severity | Finding | Status |
|---|----------|----------|---------|--------|
| F1 | Security | High | Missing rate limit on edge | Open |
EOF

out="$(cd "$proj" && sh "$GA" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'has 1 Open finding(s) (F1)'; check $? "ready: refuses when architecture-review.md has Open findings (FA3)" "$out"

# Resolve finding in architecture-review.md
cat <<'EOF' > "$proj/docs/agents-v0/design/system/architecture-review.md"
agent: design-reviewer

# Architecture Review
Reviewed against ADR 0001 (Proposed).

| # | Category | Severity | Finding | Status |
|---|----------|----------|---------|--------|
| F1 | Security | High | Missing rate limit on edge | Resolved |
EOF

out="$(cd "$proj" && sh "$GA" ready 2>&1)"
check $? "ready: exits 0 when pack is complete and 0 Open findings remain" "$out"
printf '%s' "$out" | grep -q '^OK ready: architecture pack verified'; check $? "ready: prints OK ready" "$out"
[ -f "$proj/docs/agents-v0/architecture.phase-result.md" ]; check $? "ready: writes architecture.phase-result.md"
[ "$(js "$S" activeStatus)" = awaiting_approval ]; check $? "ready: activeStatus is awaiting_approval"

# Start refuses while awaiting approval
out="$(cd "$proj" && sh "$GA" start 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED start: architecture is awaiting Sensei'; check $? "start: refuses while awaiting approval" "$out"

# Self-approval via sync-feature-state.sh is refused without external approval record (FA1)
out="$(cd "$proj" && sh .agents-v0/scripts/sync-feature-state.sh --approve architecture docs/agents-v0/architecture.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'FAIL: --approve architecture refused without Sensei external approval record'; check $? "sync-feature-state: refuses --approve architecture without Sensei record (FA1)" "$out"

# Commit refused before approve
out="$(cd "$proj" && sh "$GA" commit 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED commit: architecture is not approved'; check $? "commit: refused before approval" "$out"

# --- 4. approve via pty & commit ---------------------------------------------------------------
pty_approve architecture >/dev/null
rec_file="$(cd "$proj" && GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_file architecture)"
[ -f "$rec_file" ]; check $? "approve: wrote architecture approval record outside repo"

out="$(cd "$proj" && sh "$GA" commit 2>&1)"
check $? "commit: exits 0 after Sensei approve" "$out"
printf '%s' "$out" | grep -q '^OK commit: architecture committed on main as .*, tagged architecture-v1'; check $? "commit: prints OK commit with tag" "$out"
git -C "$proj" tag | grep -qx 'architecture-v1'; check $? "commit: architecture-v1 tag created"
git -C "$proj" log -1 --format=%s | grep -qx 'program: architecture approved'; check $? "commit: gate commit message is 'program: architecture approved'"
grep -q '| architecture |' "$proj/docs/agents-v0/architecture.md"; check $? "commit: Delivery approvals row appended to architecture.md"
grep -q '^- \*\*Status:\*\* Accepted$' "$proj/docs/agents-v0/adr/0001-modular-monolith.md"; check $? "commit: promoted pattern ADR Status to Accepted (FA5)"
grep -q '(Accepted)' "$proj/docs/agents-v0/design/system/components/claims.md"; check $? "commit: updated (Proposed) to (Accepted) in component plan"
grep -q '(Accepted)' "$proj/docs/agents-v0/design/system/architecture-review.md"; check $? "commit: updated (Proposed) to (Accepted) in architecture-review.md"

# --- 5. /v0-plan handoff (DA7) -----------------------------------------------------------------
printf '# Program Plan\n' > "$proj/docs/agents-v0/milestones/plan.md"
out="$(cd "$proj" && sh .agents-v0/scripts/sync-feature-state.sh --active-phase plan --status in_progress docs/agents-v0/milestones/plan.md 2>&1)"
check $? "plan handoff: sync-feature-state allows plan in_progress when architecture record is valid" "$out"

# Removing external approval record blocks plan entry
rm -f "$rec_file"
out="$(cd "$proj" && sh .agents-v0/scripts/sync-feature-state.sh --active-phase plan --status in_progress docs/agents-v0/milestones/plan.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'FAIL: plan requires approved architecture record'; check $? "plan handoff: refuses plan in_progress when external architecture record is missing (DA7)" "$out"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
