#!/bin/sh
# test-guard-scaffold.sh (scaffold redo, Design: DS8): full lifecycle tests for guard-scaffold.sh
# (check, start, block, ready, commit, steps, and dependency bridge).
# Run: sh scripts/test-guard-scaffold.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

# git identity of its own
for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-scaffold.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi

export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"

js() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], "<missing>"); print(v)' "$1" "$2" 2>&1; }

proj="$tmp/proj"
mkdir -p "$proj" && git -C "$proj" init -q -b main && printf 'x\n' > "$proj/README.md" \
  && git -C "$proj" add README.md && git -C "$proj" commit -q -m init

# Copy template scripts into target repo
mkdir -p "$proj/.agents-v0/scripts" "$proj/docs/agents-v0/roadmap" "$proj/docs/agents-v0/adr" \
  "$proj/docs/agents-v0/design/system/components" "$proj/docs/agents-v0/milestones" "$proj/docs/agents-v0/requirements" "$proj/docs/product"
cp "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-roadmap.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-architecture.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-plan.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-scaffold.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/secret_scan.py" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/sync-feature-state.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/check-gate-commit.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/check-story-dependencies.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$proj/.agents-v0/"
cp "$ROOT/templates/docs/agents-v0/roadmap/_template.md" "$proj/docs/agents-v0/roadmap/"
cp "$ROOT/templates/docs/agents-v0/milestones/p0-platform-skeleton.md" "$proj/docs/agents-v0/milestones/" 2>/dev/null || true
git -C "$proj" add .agents-v0
git -C "$proj" commit -qm "install kit templates"

GS="$proj/.agents-v0/scripts/guard-scaffold.sh"
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

# --- 1. check before plan approval -------------------------------------------------------------
out="$(cd "$proj" && sh "$GS" check 2>&1 || true)"
printf '%s' "$out" | grep -Eq 'REFUSED check: (no program state|plan is not in approvedPhases)'; check $? "check: refuses when plan is not approved" "$out"

# Setup roadmap, architecture, and plan to get plan approved
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

# Architecture
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

# Plan
(cd "$proj" && sh "$GP" start >/dev/null)
cat <<'EOF' > "$proj/docs/agents-v0/milestones/plan.md"
# Program Plan

## Milestones

| Milestone | Stories | What they cover |
|---|---|---|
| P0 | P0-A | Platform baseline |
| P1 | P1-A | Data model |

## Story Dependency Graph

```mermaid
flowchart TD
  P0A[P0-A] --> P1A[P1-A]
```
EOF
cat <<'EOF' > "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"
# Milestone: P0
## Stories
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P0-A | As a developer, I want a baseline, so that work starts. | docs/agents-v0/milestones/p0-platform-skeleton.md | planned | — | vertical slice | 4 |
EOF
cat <<'EOF' > "$proj/docs/agents-v0/milestones/p1-contracts.md"
# Milestone: P1
## Stories
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P1-A | As a client, I want an API, so that I can call it. | docs/agents-v0/requirements/p1-a.md | planned | P0-A | backend | 3 |
EOF
(cd "$proj" && sh "$GP" ready >/dev/null)
pty_approve plan >/dev/null
(cd "$proj" && sh "$GP" commit >/dev/null)

# Brownfield codebase is refused (DS1)
mkdir -p "$proj/docs/agents-v0/onboarding"
printf '{"approvedPhases":["onboard"]}\n' > "$proj/docs/agents-v0/onboarding/state.json"
out="$(cd "$proj" && sh "$GS" check 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: brownfield codebase detected; run /v0-onboard instead'; check $? "check: refuses brownfield codebase" "$out"
rm -rf "$proj/docs/agents-v0/onboarding"

# Non-integration branch is refused (DS1)
git -C "$proj" checkout -q -b feat/test-branch
out="$(cd "$proj" && sh "$GS" check 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: scaffold must run on the integration branch'; check $? "check: refuses non-integration branch" "$out"
git -C "$proj" checkout -q main

# Prereqs satisfied on integration branch (DS1)
out="$(cd "$proj" && sh "$GS" check 2>&1)"
check $? "check: passes when plan approved on integration branch" "$out"
printf '%s' "$out" | grep -q '^OK check: prerequisites satisfied for /v0-scaffold'; check $? "check: prints OK check" "$out"

# --- 2. start & block (DS2) -------------------------------------------------------------------
out="$(cd "$proj" && sh "$GS" start 2>&1)"
check $? "start: exits 0" "$out"
printf '%s' "$out" | grep -q '^OK start: scaffold in_progress on docs/agents-v0/milestones/p0-platform-skeleton.md'; check $? "start: prints OK start" "$out"
[ -f "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md" ]; check $? "start: seeds manifest if absent"
[ "$(js "$S" activePhase)" = scaffold ]; check $? "start: activePhase is scaffold"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus is in_progress"

out="$(cd "$proj" && sh "$GS" block "Waiting on container base image approval" 2>&1)"
check $? "block: exits 0" "$out"
printf '%s' "$out" | grep -q 'OK block: scaffold blocked (Waiting on container base image approval)'; check $? "block: prints OK block with reason" "$out"
[ "$(js "$S" activeStatus)" = blocked ]; check $? "block: activeStatus is blocked"

out="$(cd "$proj" && sh "$GS" start 2>&1)"
check $? "start: resumes from blocked state" "$out"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus restored to in_progress"

# --- 3. ready validation (negative & positive) (DS3) -------------------------------------------
# Missing Dockerfile
out="$(cd "$proj" && sh "$GS" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED ready: missing Dockerfile'; check $? "ready: refuses missing Dockerfile" "$out"

# Missing docker-compose.yml
printf 'FROM alpine\n' > "$proj/Dockerfile"
out="$(cd "$proj" && sh "$GS" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED ready: missing docker-compose.yml'; check $? "ready: refuses missing docker-compose.yml" "$out"

printf 'services:\n  app:\n    build: .\n' > "$proj/docker-compose.yml"

# Placeholder rejection
sed -i '1a [TODO] add database service' "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"
out="$(cd "$proj" && sh "$GS" ready 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED ready: .* contains unauthored placeholders'; check $? "ready: catches unauthored placeholders" "$out"

# Remove placeholder
sed -i '/\[TODO\]/d' "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"

# Ready succeeds
out="$(cd "$proj" && sh "$GS" ready 2>&1)"
check $? "ready: exits 0 on valid baseline" "$out"
printf '%s' "$out" | grep -q '^OK ready: scaffold baseline verified'; check $? "ready: prints OK ready" "$out"
[ -f "$proj/docs/agents-v0/milestones/scaffold.phase-result.md" ]; check $? "ready: writes scaffold.phase-result.md"
[ "$(js "$S" activeStatus)" = awaiting_approval ]; check $? "ready: activeStatus is awaiting_approval"

# Self-approval via sync-feature-state.sh is refused without external approval record (DSA)
out="$(cd "$proj" && sh .agents-v0/scripts/sync-feature-state.sh --approve scaffold docs/agents-v0/milestones/p0-platform-skeleton.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'FAIL: --approve scaffold refused without Sensei external approval record'; check $? "sync-feature-state: refuses --approve scaffold without Sensei record (DSA)" "$out"

# Commit refused before external approval (DS5)
out="$(cd "$proj" && sh "$GS" commit 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED commit: scaffold is not approved'; check $? "commit: refused before approval" "$out"

# --- 4. external approve via pty & commit (DS5) ------------------------------------------------
pty_approve scaffold >/dev/null
rec_file="$(cd "$proj" && GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_file scaffold)"
[ -f "$rec_file" ]; check $? "approve: wrote scaffold approval record outside repo"

out="$(cd "$proj" && sh "$GS" commit 2>&1)"
check $? "commit: exits 0 after Sensei approve" "$out"
printf '%s' "$out" | grep -q '^OK commit: scaffold committed on main as .*, tagged scaffold-v1'; check $? "commit: prints OK commit with tag" "$out"
git -C "$proj" tag | grep -qx 'scaffold-v1'; check $? "commit: scaffold-v1 tag created"
git -C "$proj" log -1 --format=%s | grep -qx 'scaffold: platform skeleton approved'; check $? "commit: gate commit message is 'scaffold: platform skeleton approved'"
grep -q '| scaffold | Approved |' "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"; check $? "commit: Delivery approvals row appended to p0-platform-skeleton.md"
grep -q 'P0-A.*released' "$proj/docs/agents-v0/milestones/p0-platform-skeleton.md"; check $? "commit: P0-A status updated to released"

# Check after approval refuses rerunning (DS1)
out="$(cd "$proj" && sh "$GS" check 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: scaffold is already approved; suggest /v0-intake'; check $? "check: refuses when scaffold is already approved" "$out"

# --- 5. story dependency bridge (Jiraiya Recommendation 1, DS5) -------------------------------
cat <<'EOF' > "$proj/docs/agents-v0/requirements/p1-a.md"
# Requirements: P1-A
Story: P1-A
As a client, I want an API, so that I can call it.
EOF
out="$(cd "$proj" && sh .agents-v0/scripts/check-story-dependencies.sh docs/agents-v0/requirements/p1-a.md 2>&1)"
check $? "check-story-dependencies: exits 0 for story depending on P0-A" "$out"
printf '%s' "$out" | grep -q '^OK: dependencies verified for P1-A: P0-A'; check $? "check-story-dependencies: prints OK verified for P1-A" "$out"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
