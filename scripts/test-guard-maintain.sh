#!/bin/sh
# test-guard-maintain.sh — automated test suite for /v0-maintain guard (Design: DM1-DM8, DMA).
# Run: sh scripts/test-guard-maintain.sh
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-maintain.XXXXXX")"
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

pty_approve() {
  repo_dir="$1"
  phase_cmd="$2"
  feature_arg="${3:-}"
  words="${4:-Approved by user}"
  python3 - "$repo_dir" "$phase_cmd" "$feature_arg" "$words" <<'PY'
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

export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"
mkdir -p "$AGENTS_V0_APPROVALS_DIR"

r="$tmp/repo"
mkdir -p "$r/.agents-v0/scripts" "$r/docs/agents-v0/maintain" "$r/docs/agents-v0/build" "$r/app/src"
git -C "$r" init -q -b main
git -C "$r" config user.name "Test"
git -C "$r" config user.email "test@example.com"
git -C "$r" config commit.gpgsign false

cp "$KIT"/templates/.agents-v0/gate-rules "$r/.agents-v0/gate-rules"
cp "$KIT"/templates/.agents-v0/secret-allowlist.json "$r/.agents-v0/secret-allowlist.json"
cp "$KIT"/templates/docs/agents-v0/maintain/_note.template.md "$r/docs/agents-v0/maintain/_note.template.md"
cp "$KIT"/templates/docs/agents-v0/lessons.md "$r/docs/agents-v0/lessons.md"
cp "$KIT"/templates/docs/agents-v0/lessons-archive.md "$r/docs/agents-v0/lessons-archive.md"
for s in guard-common.sh guard-maintain.sh guard-verify.sh guard-local-release.sh \
         secret_scan.py sync-feature-state.sh resolve-integration-branch.sh feature-worktree.sh \
         check-gate-commit.sh check-traceability.sh check-attempt-budget.sh \
         check-failure-brief.sh check-tests-ran.sh check-onboarding-docs.sh check-lessons.sh check-release-evidence.sh; do
  cp "$KIT/templates/.agents-v0/scripts/$s" "$r/.agents-v0/scripts/$s"
  chmod +x "$r/.agents-v0/scripts/$s"
done

cat > "$r/docs/agents-v0/project-profile.md" <<'EOF'
# Project Profile
| Field | Value |
|---|---|
| Pack | java |
EOF
mkdir -p "$r/.agents-v0/packs/java"
printf '{"name":"java"}\n' > "$r/.agents-v0/packs/java/pack.json"
printf '# Readme\n' > "$r/README.md"
printf 'public class App { public static int v() { return 1; } }\n' > "$r/app/src/App.java"

git -C "$r" add -A
git -C "$r" commit -qm "initial commit"

# -----------------------------------------------------------------------------
# 1. DM1: check prerequisites, slug validation, p0-a block, baseline-status, collision
# -----------------------------------------------------------------------------
expect_fail "check: missing <id> slug is refused" "$r" sh .agents-v0/scripts/guard-maintain.sh check
expect_fail "check: invalid uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-maintain.sh check Fix_1
expect_fail "check: p0-a is refused and redirected to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-maintain.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"

mkdir -p "$r/docs/agents-v0/onboarding"
printf '{"ok": false}\n' > "$r/docs/agents-v0/onboarding/baseline-status.json"
expect_fail "check: refuses when brownfield baseline-status.json has ok=false" "$r" sh .agents-v0/scripts/guard-maintain.sh check fix-bug
expect_out "check: baseline refusal names baseline-status.json" "baseline-status.json"
rm -rf "$r/docs/agents-v0/onboarding"

mkdir -p "$r/docs/agents-v0/maintain/other-fix"
printf 'dirty\n' > "$r/docs/agents-v0/maintain/other-fix/note.md"
expect_fail "check: refuses when another maintenance note has uncommitted changes" "$r" sh .agents-v0/scripts/guard-maintain.sh check fix-bug
expect_out "check: collision refusal names other-fix" "other-fix"
rm -rf "$r/docs/agents-v0/maintain/other-fix"

expect_pass "check: valid slug fix-bug passes" "$r" sh .agents-v0/scripts/guard-maintain.sh check fix-bug

# -----------------------------------------------------------------------------
# 2. DM2: start provisions maintain/<id> worktree, seeds note.md & build-report.md, block & helper-brief dedup
# -----------------------------------------------------------------------------
expect_pass "start: provisions maintain/fix-bug worktree and seeds note.md + build-report.md" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh start fix-bug
wt="$(git -C "$r" worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} $0=="branch refs/heads/maintain/fix-bug"{print p; exit}')"
if [ -n "$wt" ] && [ -f "$wt/docs/agents-v0/maintain/fix-bug/note.md" ] && [ -f "$wt/docs/agents-v0/build/fix-bug/build-report.md" ]; then
  pass "start: created maintain/fix-bug worktree with seeded note.md and build-report.md"
else
  fail "start: created maintain/fix-bug worktree with seeded note.md and build-report.md" "wt=$wt"
fi
if grep -Fq '"maintainGuardManaged": true' "$wt/docs/agents-v0/maintain/fix-bug/state.json"; then
  pass "start: sets maintainGuardManaged=true in state.json"
else
  fail "start: sets maintainGuardManaged=true in state.json"
fi

cat > "$wt/docs/agents-v0/maintain/fix-bug/helper-brief.md" <<'EOF'
helper: explore-researcher
outputs:
  - root cause
return: summary
ask: Where is App.v called?
EOF
expect_pass "block: records blocked state and hashes helper-brief.md on 1st call" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh block fix-bug "Waiting on explore-researcher"
expect_fail "block: refuses duplicate helper-brief.md with identical SHA-256" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh block fix-bug "Waiting on explore-researcher again"
expect_out "block: duplicate helper-brief refusal mentions identical SHA-256" "identical SHA-256"
rm -f "$wt/docs/agents-v0/maintain/fix-bug/helper-brief.md"

expect_pass "start: resumes fix-bug after block" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh start fix-bug

# -----------------------------------------------------------------------------
# 3. DM3: ready validates note.md, placeholders, ceiling, budget, failure-brief, build-output.txt, check-tests-ran.sh
# -----------------------------------------------------------------------------
expect_fail "ready: refuses when note.md still has <!-- TEMPLATE: placeholders" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
expect_out "ready: placeholder refusal names TEMPLATE" "TEMPLATE"

cat > "$wt/docs/agents-v0/maintain/fix-bug/note.md" <<'EOF'
# Maintenance note: Fix App.v return value

Id: fix-bug
Type: bug
Trigger: ISSUE-42
Tier: standard

## Scope
- `app/src/App.java` return value calculation.

## Acceptance
- Expected: `App.v()` returns `2`.
- Actual: `App.v()` returned `1`.
- Done when: `AppTest` verifies `App.v() == 2` (`app/src/App.java:1`).

## Security surface
- None.

## Rollback
- Revert the `maintain/fix-bug` merge commit on `main`.

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF

printf 'public class App { public static int v() { return 2; } }\n' > "$wt/app/src/App.java"

cat > "$wt/docs/agents-v0/build/fix-bug/build-report.md" <<'EOF'
# Build Report: fix-bug

## Attempt Cards

| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| `./mvnw test -Dtest=AppTest` | 1 | 1 | `AppTest#returnsTwo` | `app/src/App.java:1` |
| `./mvnw verify` | 0 | 2 | — | `app/src/App.java:1` |

## Final Verify Summary
- Command: `./mvnw verify`
- Status: PASS
- Output log: `docs/agents-v0/build/fix-bug/build-output.txt`
EOF

expect_fail "ready: refuses when build-output.txt is missing for a non-docs change" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
expect_out "ready: missing build-output.txt refusal names build-output.txt" "build-output.txt"

cat > "$wt/docs/agents-v0/build/fix-bug/build-output.txt" <<'EOF'
[INFO] --- surefire:3.2.5:test (default-test) @ app ---
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
EOF
mkdir -p "$wt/app/src/test/java"
printf '<project/>\n' > "$wt/app/pom.xml"
printf 'public class AppTest {}\n' > "$wt/app/src/test/java/AppTest.java"
expect_fail "ready: refuses when check-tests-ran.sh detects 0 tests ran for Maven module" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
expect_out "ready: 0 tests refusal names check-tests-ran.sh" "check-tests-ran.sh"
rm -rf "$wt/app/pom.xml" "$wt/app/src/test"

# Test MAINTAIN_MAX_LINES ceiling
for i in 1 2 3 4 5 6 7 8; do
  printf '// line %s\n' "$i" >> "$wt/app/src/App.java"
done
expect_fail "ready: refuses when changed non-doc lines exceed MAINTAIN_MAX_LINES=5" "$wt" \
  env MAINTAIN_MAX_LINES=5 sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
expect_out "ready: line ceiling refusal routes to /v0-intake" "/v0-intake"
printf 'public class App { public static int v() { return 2; } }\n' > "$wt/app/src/App.java"

# Test failure-brief enforcement when same test fails twice consecutively
cp "$wt/docs/agents-v0/build/fix-bug/build-report.md" "$tmp/good-report.md"
cat > "$wt/docs/agents-v0/build/fix-bug/build-report.md" <<'EOF'
# Build Report: fix-bug

## Attempt Cards

| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| `./mvnw test` | 1 | 1 | `AppTest#returnsTwo` | `app/src/App.java:1` |
| `./mvnw test` | 1 | 2 | `AppTest#returnsTwo` | `app/src/App.java:1` |
| `./mvnw test` | 0 | 3 | — | `app/src/App.java:1` |

## Final Verify Summary
- Command: `./mvnw test`
- Status: PASS
EOF
expect_fail "ready: refuses when same test fails twice consecutively without failure-brief.md" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
expect_out "ready: failure-brief refusal names failure-brief.md" "failure-brief\.md"
cp "$tmp/good-report.md" "$wt/docs/agents-v0/build/fix-bug/build-report.md"

expect_pass "ready: passes when note.md, build-report.md, and build-output.txt are valid" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
if [ -f "$wt/docs/agents-v0/maintain/fix-bug/phase-result.md" ] \
   && grep -Fq "status: awaiting_approval" "$wt/docs/agents-v0/maintain/fix-bug/phase-result.md" \
   && grep -Fq '"activeStatus": "awaiting_approval"' "$wt/docs/agents-v0/maintain/fix-bug/state.json"; then
  pass "ready: writes phase-result.md and sets activeStatus=awaiting_approval"
else
  fail "ready: writes phase-result.md and sets activeStatus=awaiting_approval"
fi

# -----------------------------------------------------------------------------
# 4. DMA & DM5: self-approval block, PTY external approval, safe-staged commit, and --reopen
# -----------------------------------------------------------------------------
expect_fail "DMA: sync-feature-state.sh --approve maintain is refused without external approval record" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --approve maintain docs/agents-v0/maintain/fix-bug/note.md
expect_out "DMA: sync-feature-state refusal names guard-common.sh approve maintain fix-bug" "guard-common.sh approve maintain fix-bug"

expect_fail "DM5: guard-maintain.sh commit is refused without external approval record" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh commit fix-bug
expect_out "DM5: commit refusal names guard-common.sh approve maintain fix-bug" "guard-common.sh approve maintain fix-bug"

expect_pass "DMA: the user approves maintain fix-bug from external PTY (run from main repo)" "$r" \
  pty_approve "$r" maintain fix-bug "Approved fix-bug"

touch "$wt/docs/agents-v0/maintain/fix-bug/state.json.lock"
expect_pass "DM5: guard-maintain.sh commit fix-bug succeeds after external approval" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh commit fix-bug

if git -C "$wt" log -1 --format=%s | grep -Fxq "maintain/fix-bug: maintain approved"; then
  pass "DM5: commit message is 'maintain/fix-bug: maintain approved'"
else
  fail "DM5: commit message is 'maintain/fix-bug: maintain approved'" "$(git -C "$wt" log -1 --format=%s)"
fi
if ! git -C "$wt" show --name-only --format= HEAD | grep -Fq ".lock"; then
  pass "DM5: *.lock files are never staged or committed"
else
  fail "DM5: *.lock files are never staged or committed"
fi
if grep -Fq "| Maintain |" "$wt/docs/agents-v0/maintain/fix-bug/note.md" \
   && grep -Fq '"lastApprovedPhase": "maintain"' "$wt/docs/agents-v0/maintain/fix-bug/state.json"; then
  pass "DM5: note.md Delivery approvals and state.json record maintain approval"
else
  fail "DM5: note.md Delivery approvals and state.json record maintain approval"
fi

expect_fail "check: refuses already-approved fix-bug without --reopen" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh check fix-bug
expect_out "check: already-approved refusal suggests /v0-verify fix-bug --maintain or --reopen" "/v0-verify fix-bug --maintain"

expect_pass "check: --reopen is allowed when reopenCount < 3" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh check fix-bug --reopen
expect_pass "start: --reopen increments reopenCount and reopens maintain" "$wt" \
  sh .agents-v0/scripts/guard-maintain.sh start fix-bug --reopen
if grep -Fq '"reopenCount": 1' "$wt/docs/agents-v0/maintain/fix-bug/state.json"; then
  pass "start --reopen: increments reopenCount to 1"
else
  fail "start --reopen: increments reopenCount to 1"
fi

# Re-ready, re-approve, and re-commit fix-bug after reopen
expect_pass "ready: re-ready fix-bug after reopen" "$wt" sh .agents-v0/scripts/guard-maintain.sh ready fix-bug
expect_pass "DMA: the user re-approves fix-bug in PTY" "$r" pty_approve "$r" maintain fix-bug "Re-approved fix-bug"
expect_pass "DM5: re-commit fix-bug after reopen" "$wt" sh .agents-v0/scripts/guard-maintain.sh commit fix-bug

# -----------------------------------------------------------------------------
# 5. Tier: trivial lane (stays on integration branch, requires Tier confirmed by, enforces docs/lockfile scope)
# -----------------------------------------------------------------------------
expect_pass "trivial: check doc-sync-1 --tier trivial on main" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh check doc-sync-1 --tier trivial
expect_pass "trivial: start doc-sync-1 --tier trivial stays on main without creating maintain/doc-sync-1 branch" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh start doc-sync-1 --tier trivial
if ! git -C "$r" show-ref --verify --quiet refs/heads/maintain/doc-sync-1; then
  pass "trivial: does not create maintain/doc-sync-1 branch"
else
  fail "trivial: should not create maintain/doc-sync-1 branch"
fi

cat > "$r/docs/agents-v0/maintain/doc-sync-1/note.md" <<'EOF'
# Maintenance note: Sync README setup instructions

Id: doc-sync-1
Type: docs
Trigger: DOC-7
Tier: trivial

## Scope
- `README.md` setup instructions.

## Acceptance
- Done when `README.md` documents the Java 21 requirement.

## Security surface
None.

## Rollback
- Revert the `README.md` commit on `main`.

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
printf '# Readme\nRequires Java 21.\n' > "$r/README.md"

cat > "$r/docs/agents-v0/build/doc-sync-1/build-report.md" <<'EOF'
# Build Report — doc-sync-1

## Summary
- Story: `doc-sync-1`
- Status: PASS
- Attempts used: 1 / 8

### Attempt 1
- Command: `doc-sync check`
- Result: PASS
EOF

expect_fail "trivial ready: refuses when Tier confirmed by is missing" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh ready doc-sync-1
expect_out "trivial ready: refusal names Tier confirmed by" "Tier confirmed by"

# Add Tier confirmed by, then test scope violation (editing app/src/App.java in trivial tier)
sed -i '/^Tier: trivial$/a Tier confirmed by: user on 2026-11-06' "$r/docs/agents-v0/maintain/doc-sync-1/note.md"
printf '// forbidden trivial edit\n' >> "$r/app/src/App.java"
expect_fail "trivial ready: refuses when non-doc / non-manifest file app/src/App.java is modified" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh ready doc-sync-1
expect_out "trivial ready: scope refusal names app/src/App.java" "app/src/App.java"
git -C "$r" checkout -- app/src/App.java

expect_pass "trivial ready: passes for docs-only edit with Tier confirmed by" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh ready doc-sync-1
expect_pass "trivial DMA: the user approves doc-sync-1 in PTY" "$r" \
  pty_approve "$r" maintain doc-sync-1 "Approved trivial doc sync"
expect_pass "trivial DM5: commit doc-sync-1 on main" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh commit doc-sync-1

# -----------------------------------------------------------------------------
# 6. Tier: emergency lane & DM7 handoff into guard-verify.sh and guard-local-release.sh
# -----------------------------------------------------------------------------
expect_pass "emergency: start hotfix-1 --tier emergency provisions maintain/hotfix-1 worktree" "$r" \
  sh .agents-v0/scripts/guard-maintain.sh start hotfix-1 --tier emergency
wt_em="$(git -C "$r" worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} $0=="branch refs/heads/maintain/hotfix-1"{print p; exit}')"

cat > "$wt_em/docs/agents-v0/maintain/hotfix-1/note.md" <<'EOF'
# Maintenance note: Emergency null-check hotfix

Id: hotfix-1
Type: bug
Trigger: INC-999
Tier: emergency
Tier confirmed by: user on 2026-11-06

## Scope
- `app/src/App.java` null-check guard.

## Acceptance
- Expected: `App.v()` returns `3`.
- Actual: `App.v()` threw NPE on null input.
- Done when `App.v()` guards null input (`app/src/App.java:1`).

## Security surface
- None.

## Rollback
- Revert `maintain/hotfix-1` merge commit and redeploy previous tag.

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
printf 'public class App { public static int v() { return 3; } }\n' > "$wt_em/app/src/App.java"
cp "$tmp/good-report.md" "$wt_em/docs/agents-v0/build/hotfix-1/build-report.md"
cat > "$wt_em/docs/agents-v0/build/hotfix-1/build-output.txt" <<'EOF'
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
EOF

expect_fail "emergency ready: refuses without Follow-up verify due: YYYY-MM-DD" "$wt_em" \
  sh .agents-v0/scripts/guard-maintain.sh ready hotfix-1
expect_out "emergency ready: refusal names Follow-up verify due" "Follow-up verify due"

sed -i '/^Tier confirmed by:/a Follow-up verify due: 2026-11-10' "$wt_em/docs/agents-v0/maintain/hotfix-1/note.md"
expect_pass "emergency ready: passes once Follow-up verify due and Rollback are present" "$wt_em" \
  sh .agents-v0/scripts/guard-maintain.sh ready hotfix-1
expect_pass "emergency DMA: the user approves hotfix-1 in PTY" "$r" \
  pty_approve "$r" maintain hotfix-1 "Approved emergency hotfix-1"
expect_pass "emergency DM5: commit hotfix-1 on maintain/hotfix-1" "$wt_em" \
  sh .agents-v0/scripts/guard-maintain.sh commit hotfix-1
expect_out "emergency DM5: commit output routes to /v0-local-release hotfix-1 --maintain" "/v0-local-release hotfix-1 --maintain"

# DM7 handoff tests: with approval record present, guard-verify.sh check and guard-local-release.sh check pass;
# when approval record is missing, both refuse!
expect_pass "DM7: guard-verify.sh check hotfix-1 --maintain passes with valid maintain approval record" "$wt_em" \
  sh .agents-v0/scripts/guard-verify.sh check hotfix-1 --maintain
expect_pass "DM7: guard-local-release.sh check hotfix-1 --maintain passes with valid maintain approval record" "$wt_em" \
  sh .agents-v0/scripts/guard-local-release.sh check hotfix-1 --maintain

rec_file="$(find "$AGENTS_V0_APPROVALS_DIR" -name "maintain-hotfix-1.json" | head -n 1)"
mv "$rec_file" "$rec_file.bak"
expect_fail "DM7: guard-verify.sh check hotfix-1 --maintain refuses when external maintain approval record is missing" "$wt_em" \
  sh .agents-v0/scripts/guard-verify.sh check hotfix-1 --maintain
expect_out "DM7: guard-verify refusal names external maintain approval record" "external maintain approval record"

expect_fail "DM7: guard-local-release.sh check hotfix-1 --maintain refuses when external maintain approval record is missing" "$wt_em" \
  sh .agents-v0/scripts/guard-local-release.sh check hotfix-1 --maintain
expect_out "DM7: guard-local-release refusal names external maintain approval record" "external maintain approval record"

expect_fail "DM7: sync-feature-state.sh --active-phase verify in_progress refuses when external maintain approval record is missing" "$wt_em" \
  sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status in_progress docs/agents-v0/maintain/hotfix-1/note.md
expect_out "DM7: sync-feature-state verify refusal names external maintain approval record" "external maintain approval record"
mv "$rec_file.bak" "$rec_file"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
