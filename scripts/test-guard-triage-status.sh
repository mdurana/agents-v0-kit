#!/bin/sh
# test-guard-triage-status.sh — automated test suite for /v0-triage guard and /v0-status (Design: DST1-DST8, DSTA).
# Run: sh scripts/test-guard-triage-status.sh
set -u
export PYTHONDONTWRITEBYTECODE=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-triage-status.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

passed=0
failed=0
pass() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1" >&2; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /' >&2; }

expect_pass() {
  desc="$1"; dir="$2"; shift 2
  if out="$(cd "$dir" && "$@" 2>&1)"; then
    pass "$desc"
  else
    fail "$desc (expected exit 0)" "$out"
  fi
}

expect_fail() {
  desc="$1"; dir="$2"; shift 2
  if out="$(cd "$dir" && "$@" 2>&1)"; then
    fail "$desc (expected non-zero)" "$out"
  else
    pass "$desc"
  fi
}

expect_out() {
  desc="$1"; pat="$2"
  if printf '%s\n' "$out" | grep -Eq "$pat"; then
    pass "$desc"
  else
    fail "$desc (missing pattern: $pat)" "$out"
  fi
}

G() {
  dir="$1"; shift
  git -C "$dir" -c user.name="Sensei" -c user.email="sensei@example.com" -c commit.gpgsign=false "$@"
}

pty_approve() {
  pa_dir="$1"
  pa_phase="$2"
  pa_feat="$3"
  pa_words="$4"
  python3 - "$pa_dir" "$pa_phase" "$pa_feat" "$pa_words" <<'PY'
import os, pty, sys, time
repo, phase, feature, words = sys.argv[1:5]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(repo)
    argv = ["sh", ".agents-v0/scripts/guard-common.sh", "approve", phase]
    if feature:
        argv.append(feature)
    os.execvp("sh", argv)
buf, sent, end = b"", False, time.time() + 15
while time.time() < end:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    if not sent and b"Type your approval words" in buf:
        os.write(fd, words.encode("utf-8") + b"\r")
        sent = True
try:
    os.close(fd)
except OSError:
    pass
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode("utf-8", "replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

approvals="$tmp/approvals"
export AGENTS_V0_APPROVALS_DIR="$approvals"
mkdir -p "$approvals"

r="$tmp/repo"
mkdir -p "$r/.agents-v0/scripts" "$r/docs/agents-v0/maintain" "$r/docs/agents-v0/requirements" "$r/src"
cp "$KIT"/templates/.agents-v0/gate-rules "$r/.agents-v0/gate-rules"
cp "$KIT"/templates/.agents-v0/secret-allowlist.json "$r/.agents-v0/secret-allowlist.json"
cp "$KIT"/templates/docs/agents-v0/maintain/_note.template.md "$r/docs/agents-v0/maintain/_note.template.md"
cp "$KIT"/templates/.agents-v0/scripts/*.sh "$KIT"/templates/.agents-v0/scripts/*.py "$r/.agents-v0/scripts/"
chmod +x "$r/.agents-v0/scripts/"*.sh
cp "$KIT/templates/docs/agents-v0/lessons.md" "$KIT/templates/docs/agents-v0/lessons-archive.md" "$r/docs/agents-v0/"
cat > "$r/docs/agents-v0/project-profile.md" <<'EOF'
# Project Profile

| Field | Value |
|---|---|
| Pack | java |
| Build tool | maven |
| Timezone | UTC |
EOF
cat > "$r/README.md" <<'EOF'
# Demo Service
Initial README.
EOF
cat > "$r/package.json" <<'EOF'
{
  "name": "demo-ui",
  "dependencies": {
    "lodash": "4.17.20"
  }
}
EOF
cat > "$r/src/OrderController.java" <<'EOF'
package demo;
public class OrderController {}
EOF

G "$r" init -q -b main
G "$r" add -A
G "$r" commit -qm "chore: initial fixture"

# --- 1. Pre-start trivial diff qualification (Design: DST1) ------------------
printf '// controller edit\n' >> "$r/src/OrderController.java"
expect_fail "check: refuses dirty controller file before start" "$r" sh .agents-v0/scripts/guard-triage.sh check fix-doc
expect_out "check: controller refusal routes to /v0-maintain" "/v0-maintain"
G "$r" checkout -- src/OrderController.java

mkdir -p "$r/docs/api"
printf 'openapi: 3.0.3\n' > "$r/docs/api/openapi.yaml"
expect_fail "check: refuses OpenAPI contract under docs/ before start" "$r" sh .agents-v0/scripts/guard-triage.sh check fix-doc
expect_out "check: contract refusal mentions contract or schema file" "contract or schema file"
rm -rf "$r/docs/api"

sed -i 's/"lodash": "4.17.20"/"lodash": "4.18.0"/' "$r/package.json"
expect_fail "check: refuses minor version bump (4.17.20 -> 4.18.0)" "$r" sh .agents-v0/scripts/guard-triage.sh check bump-lodash
expect_out "check: minor version bump refusal mentions 1-for-1 patch version bumps" "1-for-1 patch version bumps"

sed -i 's/"lodash": "4.18.0"/"lodash": "4.17.21"/' "$r/package.json"
expect_pass "check: accepts 1-for-1 patch version bump (4.17.20 -> 4.17.21)" "$r" sh .agents-v0/scripts/guard-triage.sh check bump-lodash
G "$r" checkout -- package.json

# --- 2. Full /v0-triage lifecycle on docs-only edit (Design: DST1, DST2, DSTA)
printf '\nUpdated build instructions.\n' >> "$r/README.md"
expect_pass "check: accepts README.md documentation edit" "$r" sh .agents-v0/scripts/guard-triage.sh check doc-readme
expect_pass "start: initializes doc-readme on main with Tier: trivial" "$r" sh .agents-v0/scripts/guard-triage.sh start doc-readme
expect_out "start: output confirms OK start" "^OK start:"

if [ ! -d "$tmp/repo-maintain-doc-readme" ] && [ "$(git -C "$r" rev-parse --abbrev-ref HEAD)" = "main" ]; then
  pass "start: stays on main without creating a maintain worktree"
else
  fail "start: expected to stay on main with no worktree"
fi

if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("tier")=="trivial" and d.get("triageGuardManaged") is True and d.get("activeStatus")=="in_progress", d' "$r/docs/agents-v0/maintain/doc-readme/state.json"; then
  pass "start: state.json has tier=trivial, triageGuardManaged=True, activeStatus=in_progress"
else
  fail "start: state.json fields mismatch"
fi

expect_pass "block: records blocked state for doc-readme" "$r" sh .agents-v0/scripts/guard-triage.sh block doc-readme "Waiting on Sensei tier confirmation"
expect_pass "start: resumes doc-readme from blocked" "$r" sh .agents-v0/scripts/guard-triage.sh start doc-readme

expect_fail "ready: refuses while note.md still has placeholders and unconfirmed tier" "$r" sh .agents-v0/scripts/guard-triage.sh ready doc-readme

cat > "$r/docs/agents-v0/maintain/doc-readme/note.md" <<'EOF'
# Maintenance note: Update README build instructions

Id: doc-readme
Type: docs
Trigger: README-1
Tier: trivial
Tier confirmed by: sensei on 2026-11-05

## Scope
- `README.md` build instructions.

## Acceptance
- Expected: `README.md` documents the current Maven verify command.
- Actual: `README.md` was missing the updated build instructions.
- Done when: `README.md` includes the updated build instructions (`README.md:1`).

## Security surface
- None.

## Rollback
- Revert the `doc-readme` commit on `main`.

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
cat > "$r/docs/agents-v0/build/doc-readme/build-report.md" <<'EOF'
# Build Report: doc-readme

## Attempt Cards

| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| `docs-only check` | 0 | 1 | — | `README.md:1` |

## Final Verify Summary
- Command: `docs-only check`
- Status: PASS
EOF
cat > "$r/docs/agents-v0/maintain/doc-readme/phase-result.md" <<'EOF'
# Maintain Phase Result: doc-readme

phase: maintain
status: in_progress

## Summary
Updated README.md build instructions.

## Lessons

### maintain
- none
EOF

# Verify ready refuses if an OpenAPI contract under docs/ is snuck in before ready
mkdir -p "$r/docs/contracts"
printf 'openapi: 3.0.3\n' > "$r/docs/contracts/openapi.yaml"
expect_fail "ready: refuses when docs/contracts/openapi.yaml is added" "$r" sh .agents-v0/scripts/guard-triage.sh ready doc-readme
rm -rf "$r/docs/contracts"

expect_pass "ready: marks doc-readme awaiting_approval when note and diff are valid" "$r" sh .agents-v0/scripts/guard-triage.sh ready doc-readme
expect_out "ready: prints approve triage <id> instruction" "approve triage doc-readme"

expect_fail "commit: refuses before Sensei's external approval" "$r" sh .agents-v0/scripts/guard-triage.sh commit doc-readme

# Verify stories-status.sh while awaiting_approval
expect_pass "stories-status: --story doc-readme while awaiting_approval" "$r" sh .agents-v0/scripts/stories-status.sh --story doc-readme
expect_out "stories-status: names approve triage doc-readme when awaiting_approval" "approve triage doc-readme"

# Verify approve triage refuses a Tier: standard note (Jiraiya rec #2)
mkdir -p "$r/docs/agents-v0/maintain/std-bug"
cat > "$r/docs/agents-v0/maintain/std-bug/note.md" <<'EOF'
# Maintenance Note: std-bug
- Tier: standard
EOF
cat > "$r/docs/agents-v0/maintain/std-bug/state.json" <<'EOF'
{"feature": "std-bug", "tier": "standard", "activePhase": "maintain", "activeStatus": "awaiting_approval", "baseCommit": "HEAD"}
EOF
expect_fail "approve triage: refuses Tier: standard note" "$r" pty_approve "$r" triage std-bug "approved"
expect_out "approve triage: refusal mentions Tier: trivial only" "only applies to Tier: trivial"
rm -rf "$r/docs/agents-v0/maintain/std-bug"

# Sensei runs approve triage doc-readme in external PTY
expect_pass "approve triage: succeeds on Tier: trivial note doc-readme" "$r" pty_approve "$r" triage doc-readme "approved trivial readme fix"
expect_out "approve triage: confirms approval" "OK approve:"

# Verify stories-status.sh detects uncommitted externally-approved gate!
expect_pass "stories-status: detects uncommitted gate after external approval" "$r" sh .agents-v0/scripts/stories-status.sh --story doc-readme
expect_out "stories-status: note reports uncommitted gate" "uncommitted gate \(maintain\)"
expect_out "stories-status: nextCommand is guard-triage.sh commit doc-readme" "sh \.agents-v0/scripts/guard-triage\.sh commit doc-readme"

# Commit the trivial triage gate
expect_pass "commit: creates trivial triage gate commit" "$r" sh .agents-v0/scripts/guard-triage.sh commit doc-readme
expect_out "commit: output confirms OK commit" "^OK commit:"

expect_pass "stories-status: after commit, routes doc-readme to /v0-verify doc-readme --maintain" "$r" sh .agents-v0/scripts/stories-status.sh --story doc-readme
expect_out "stories-status: nextCommand is /v0-verify doc-readme --maintain" "/v0-verify doc-readme --maintain"

# --- 3. stories-status.sh release evidence, deploy table, and post-Verify drift (Design: DST3, DST5)
# 3a. Unsupported release evidence (release in approvedPhases, but quality-gate.md missing)
cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Story: orders
## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|---|---|---|---|---|
| Release | docs/agents-v0/requirements/orders.md | sensei | Approved | 2026-11-05 |
EOF
cat > "$r/docs/agents-v0/requirements/orders.state.json" <<'EOF'
{
  "feature": "orders",
  "tier": "standard",
  "lastApprovedPhase": "release",
  "approvedPhases": ["intake", "design", "build", "verify", "release"],
  "activePhase": "",
  "activeStatus": "",
  "verifyPassed": true,
  "reopenCount": 0
}
EOF
expect_pass "stories-status: --story orders --json with missing quality-gate.md" "$r" sh .agents-v0/scripts/stories-status.sh --story orders --json
if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["releaseEvidenceOk"] is False and "unsupported by evidence" in d["note"] and "UNSUPPORTED BY EVIDENCE" in d["nextCommand"], d' "$out"; then
  pass "stories-status: flags releaseEvidenceOk=False and unsupported by evidence when quality-gate.md is missing"
else
  fail "stories-status: expected releaseEvidenceOk=False" "$out"
fi

# 3b. Valid release evidence + configured Deploy table in project-profile.md without deploy row
mkdir -p "$r/docs/agents-v0/verify/orders"
printf '# Quality Gate: orders\nResult: PASS\n' > "$r/docs/agents-v0/verify/orders/quality-gate.md"
cat >> "$r/docs/agents-v0/project-profile.md" <<'EOF'

## Deploy

| Env | Target | How | Evidence |
|---|---|---|---|
| staging | k8s-staging | helm upgrade | smoke-check |
EOF
expect_pass "stories-status: --story orders --json with valid release evidence and configured Deploy table" "$r" sh .agents-v0/scripts/stories-status.sh --story orders --json
if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["releaseEvidenceOk"] is True and d["deployPending"] is True and "release-deploy" in d["nextCommand"], d' "$out"; then
  pass "stories-status: reports releaseEvidenceOk=True and deployPending=True (release-deploy) when Deploy table is configured"
else
  fail "stories-status: expected deployPending=True" "$out"
fi
G "$r" add -A
G "$r" commit -qm "test: add orders release fixture"

# 3c. Post-Verify source drift detection
base_sha="$(git -C "$r" rev-parse HEAD)"
cat > "$r/docs/agents-v0/requirements/payments.state.json" <<EOF
{
  "feature": "payments",
  "tier": "standard",
  "lastApprovedPhase": "verify",
  "approvedPhases": ["intake", "design", "build", "verify"],
  "activePhase": "",
  "activeStatus": "",
  "verifyPassed": true,
  "reopenCount": 0,
  "baseCommit": "$base_sha"
}
EOF
G "$r" add -A
G "$r" commit -qm "test: add payments verify-approved state"

printf '// post-verify edit\n' >> "$r/src/OrderController.java"
expect_pass "stories-status: --story payments --json detects post-Verify source drift" "$r" sh .agents-v0/scripts/stories-status.sh --story payments --json
if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["postVerifyDrift"] is True and "post-Verify source drift" in d["note"] and "/v0-verify payments" in d["nextCommand"], d' "$out"; then
  pass "stories-status: flags postVerifyDrift=True and routes back to /v0-verify payments"
else
  fail "stories-status: expected postVerifyDrift=True" "$out"
fi
G "$r" checkout -- src/OrderController.java

# 3d. Unknown --story <slug> exits non-zero and lists available workstreams
expect_fail "stories-status: --story nonexistent exits non-zero" "$r" sh .agents-v0/scripts/stories-status.sh --story nonexistent
expect_out "stories-status: unknown story lists available workstreams" "available workstreams:"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
