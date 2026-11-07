#!/bin/sh
# test-guard-roadmap.sh (roadmap redo, Design: DR8): full lifecycle tests for guard-roadmap.sh
# (check, validate, start, block, ready, commit, steps).
# Run: sh scripts/test-guard-roadmap.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

# git identity of its own
for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-roadmap.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi

export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"

js() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], "<missing>"); print(v)' "$1" "$2" 2>&1; }

proj="$tmp/proj"
mkdir -p "$proj" && git -C "$proj" init -q -b main && printf 'x\n' > "$proj/README.md" \
  && git -C "$proj" add README.md && git -C "$proj" commit -q -m init
head="$(git -C "$proj" rev-parse HEAD)"

# Copy template scripts into target repo
mkdir -p "$proj/.agents-v0/scripts" "$proj/docs/agents-v0/roadmap" "$proj/docs/product"
cp "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/guard-roadmap.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/secret_scan.py" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/scripts/sync-feature-state.sh" "$proj/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$proj/.agents-v0/"
cp "$ROOT/templates/docs/agents-v0/roadmap/_template.md" "$proj/docs/agents-v0/roadmap/"
git -C "$proj" add .agents-v0 docs/agents-v0/roadmap/_template.md
git -C "$proj" commit -qm "install kit templates"

G="$proj/.agents-v0/scripts/guard-roadmap.sh"
S="$proj/docs/agents-v0/program.state.json"

# --- 1. check ----------------------------------------------------------------------------------
# Test no path
out="$(cd "$proj" && sh "$G" check 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: no discovery path given'; check $? "check: refuses with no discovery path" "$out"

# Test missing file
out="$(cd "$proj" && sh "$G" check docs/product/missing.md 2>&1 || true)"
printf '%s' "$out" | grep -q "REFUSED check: discovery file 'docs/product/missing.md' does not exist"; check $? "check: refuses missing discovery file" "$out"

# Create valid discovery document
cat <<EOF > "$proj/docs/product/claims-discovery.md"
# Claims Processing Discovery

## Problem
Processing paper claims takes 14 days and causes customer dissatisfaction.

## Success metric
Reduce paper claim intake latency from 14 days to 48 hours.

## Options
1. Optical Character Recognition (OCR) pipeline.
2. Web portal self-service.

## Chosen option
OCR pipeline with automated field extraction and human-in-the-loop review.

## In scope
- Scan ingestion via SFTP
- OCR extraction microservice
- Webhook notification to core ledger

## Out of scope
- Mobile app capture
- Fax machine integration
EOF

# Greenfield check exits 0
out="$(cd "$proj" && sh "$G" check docs/product/claims-discovery.md 2>&1)"
check $? "check: exits 0 on valid discovery path" "$out"
printf '%s' "$out" | grep -q '^OK check: prerequisites satisfied'; check $? "check: prints OK check" "$out"

# Brownfield without onboard approval redirects to /v0-onboard (F7)
mkdir -p "$proj/src" && echo "code" > "$proj/src/app.py"
git -C "$proj" add src/app.py && git -C "$proj" commit -qm "add code"
out="$(cd "$proj" && sh "$G" check docs/product/claims-discovery.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED check: existing codebase detected without onboarding approval'; check $? "check: brownfield redirects to /v0-onboard (F7)" "$out"

# Add onboard approval to state
mkdir -p "$proj/docs/agents-v0/onboarding"
cat <<EOF > "$proj/docs/agents-v0/onboarding/state.json"
{"approvedPhases":["onboard"]}
EOF
git -C "$proj" add docs/agents-v0/onboarding/state.json && git -C "$proj" commit -qm "onboard approved"

# Check now passes on onboarded brownfield
out="$(cd "$proj" && sh "$G" check docs/product/claims-discovery.md 2>&1)"
check $? "check: passes when brownfield is onboard-approved" "$out"

# --- 2. validate -------------------------------------------------------------------------------
out="$(cd "$proj" && sh "$G" validate docs/product/claims-discovery.md 2>&1)"
check $? "validate: exits 0 on valid discovery" "$out"
printf '%s' "$out" | grep -q '^OK validate: discovery document'; check $? "validate: prints OK validate" "$out"

# Missing section
cat <<EOF > "$proj/docs/product/bad-discovery.md"
# Incomplete
## Problem
P
EOF
out="$(cd "$proj" && sh "$G" validate docs/product/bad-discovery.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED validate: missing or empty section(s)'; check $? "validate: catches missing sections" "$out"

# Placeholder detection
cat <<EOF > "$proj/docs/product/placeholder-discovery.md"
# Test
## Problem
TODO
## Success metric
M
## Options
O
## Chosen option
C
## In scope
- S
## Out of scope
None
EOF
out="$(cd "$proj" && sh "$G" validate docs/product/placeholder-discovery.md 2>&1 || true)"
printf '%s' "$out" | grep -q "unresolved keyword placeholder 'TODO'"; check $? "validate: catches placeholders" "$out"

# --- 3. start ----------------------------------------------------------------------------------
out="$(cd "$proj" && sh "$G" start docs/product/claims-discovery.md 2>&1)"
check $? "start: exits 0" "$out"
printf '%s' "$out" | grep -q '^OK start: roadmap state is in_progress'; check $? "start: prints OK start" "$out"
[ -f "$proj/docs/agents-v0/roadmap/claims.md" ]; check $? "start: seeds roadmap/claims.md from template"
[ -f "$S" ]; check $? "start: creates program.state.json"
[ "$(js "$S" activePhase)" = roadmap ]; check $? "start: activePhase is roadmap"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus is in_progress"

# --- 4. block ----------------------------------------------------------------------------------
out="$(cd "$proj" && sh "$G" block "Waiting on legal review" 2>&1)"
check $? "block: exits 0" "$out"
printf '%s' "$out" | grep -q 'OK block: roadmap state is blocked: Waiting on legal review'; check $? "block: prints OK block with reason" "$out"
[ "$(js "$S" activeStatus)" = blocked ]; check $? "block: activeStatus is blocked"

# Resume with start
out="$(cd "$proj" && sh "$G" start docs/product/claims-discovery.md 2>&1)"
check $? "start: resumes from blocked state" "$out"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus restored to in_progress"

# --- 5. ready ----------------------------------------------------------------------------------
# Fill in completed roadmap
disc_hash=$(python3 -c "import hashlib, sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$proj/docs/product/claims-discovery.md")
cat <<EOF > "$proj/docs/agents-v0/roadmap/claims.md"
# Roadmap: claims

Discovery: docs/product/claims-discovery.md (sha256: $disc_hash)

## Problem
Processing paper claims takes 14 days and causes customer dissatisfaction.

## Success metric
Reduce paper claim intake latency from 14 days to 48 hours.

## Chosen option
OCR pipeline with automated field extraction and human-in-the-loop review.

## Now
- Scan ingestion via SFTP

## Next
- OCR extraction microservice

## Later
- Webhook notification to core ledger

## Out of scope
- Mobile app capture
- Fax machine integration

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF

out="$(cd "$proj" && sh "$G" ready docs/product/claims-discovery.md 2>&1)"
check $? "ready: exits 0 on complete roadmap" "$out"
printf '%s' "$out" | grep -q '^OK ready: roadmap prepared'; check $? "ready: prints OK ready" "$out"
[ -f "$proj/docs/agents-v0/roadmap/claims.phase-result.md" ]; check $? "ready: writes claims.phase-result.md"
[ "$(js "$S" activeStatus)" = awaiting_approval ]; check $? "ready: activeStatus is awaiting_approval"

# Start refuses while awaiting approval
out="$(cd "$proj" && sh "$G" start docs/product/claims-discovery.md 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED start: roadmap is awaiting approval'; check $? "start: refuses while awaiting approval" "$out"

# --- 6. commit refused before approve -----------------------------------------------------------
out="$(cd "$proj" && sh "$G" commit 2>&1 || true)"
printf '%s' "$out" | grep -q 'REFUSED commit: roadmap is not approved'; check $? "commit: refused before approval" "$out"

# --- 7. approve via pty ------------------------------------------------------------------------
python3 - "$proj" "$proj/.agents-v0/scripts/guard-common.sh" "Approved by user" <<'PY'
import os, pty, sys, time
proj, script, words = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.execvp("sh", ["sh", script, "approve", "roadmap"])
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


# Verify approval record exists
rec_file="$(cd "$proj" && GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_file roadmap)"
[ -f "$rec_file" ]; check $? "approve: wrote approval record outside repo"

# --- 8. commit ---------------------------------------------------------------------------------
out="$(cd "$proj" && sh "$G" commit 2>&1)"
check $? "commit: exits 0 after external approve" "$out"
printf '%s' "$out" | grep -q '^OK commit: roadmap committed on main as .*, tagged roadmap-v1'; check $? "commit: prints OK commit with tag" "$out"
git -C "$proj" tag | grep -qx 'roadmap-v1'; check $? "commit: roadmap-v1 tag created"
git -C "$proj" log -1 --format=%s | grep -qx 'program: roadmap approved'; check $? "commit: gate commit message is 'program: roadmap approved'"
grep -q '| roadmap |' "$proj/docs/agents-v0/roadmap/claims.md"; check $? "commit: Delivery approvals row appended to claims.md"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
