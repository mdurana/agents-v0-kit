#!/bin/sh
# test-tier1-harness.sh: self-test for scripts/lib/tier1-harness.sh and scripts/tier1.sh (onboard fix, step 0).
# Offline, no agent. Checks the AGENTS_V0_* guard, the install-into-a-temp-repo fixture and HASH-OK, the
# byte-identical snapshot (used by E37 and E38), the time limit and report line, and that cleanup removes
# only this run's own temp folder. Run by validate-kit.sh.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"
T="$KIT/scripts/tier1.sh"

# 1. The guard refuses each of the seven test switches, in the harness and in tier1.sh.
for v in $T1_OVERRIDE_VARS; do
  if env "$v=1" sh -c 'KIT="$1"; . "$1/scripts/lib/tier1-harness.sh"; t1_guard_env' _ "$KIT" > "$T1_TMP/g.txt" 2>&1; then
    fail "harness guard refuses $v"; else has "harness guard names $v" "$T1_TMP/g.txt" "$v"; fi
  if env "$v=" sh "$T" -- true > "$T1_TMP/g.txt" 2>&1; then fail "tier1.sh refuses $v (even when empty)"
  else has "tier1.sh names $v" "$T1_TMP/g.txt" "$v"; fi
done
expect_pass "harness guard passes with no switch set" "$T1_TMP" t1_guard_env

# 2. Fixture: a real install into an empty temp repo matches the kit (HASH-OK); a planted edit does not.
r="$(t1_repo plain)"
if t1_install "$r"; then pass "install.sh into an empty temp repo"; else fail "install.sh into an empty temp repo"; fi
if t1_hash_ok "$r"; then pass "installed copy is HASH-OK"; else fail "installed copy is HASH-OK ($(cat "$T1_TMP/hash.txt"))"; fi
first="$(ls "$r/.agents-v0/scripts" | head -1)"
printf '\n# planted\n' >> "$r/.agents-v0/scripts/$first"
if t1_hash_ok "$r"; then fail "an edited installed script is not HASH-OK"; else pass "an edited installed script is not HASH-OK"; fi
c="$(t1_repo withcommit --commit)"
[ "$(git -C "$c" rev-list --count HEAD)" = 1 ] && pass "t1_repo --commit makes one commit" || fail "t1_repo --commit makes one commit"
[ -z "$(git -C "$r" rev-list --all 2>/dev/null)" ] && pass "t1_repo --empty makes no commit" || fail "t1_repo --empty makes no commit"

# 3. Snapshot: equal when nothing changed; differs on a tracked edit, an untracked file, a new ref, a staged file.
t1_snapshot "$c" "$T1_TMP/s0"; t1_snapshot "$c" "$T1_TMP/s1"
cmp -s "$T1_TMP/s0" "$T1_TMP/s1" && pass "snapshot is stable" || fail "snapshot is stable"
printf 'x\n' >> "$c/README.md"; t1_snapshot "$c" "$T1_TMP/s1"
cmp -s "$T1_TMP/s0" "$T1_TMP/s1" && fail "snapshot sees a tracked edit" || pass "snapshot sees a tracked edit"
G "$c" checkout -q -- README.md; printf 'u\n' > "$c/untracked.txt"; t1_snapshot "$c" "$T1_TMP/s1"
cmp -s "$T1_TMP/s0" "$T1_TMP/s1" && fail "snapshot sees an untracked file" || pass "snapshot sees an untracked file"
mv "$c/untracked.txt" "$T1_TMP/untracked.txt"; G "$c" branch side; t1_snapshot "$c" "$T1_TMP/s1"
cmp -s "$T1_TMP/s0" "$T1_TMP/s1" && fail "snapshot sees a new ref" || pass "snapshot sees a new ref"
G "$c" branch -q -D side; t1_snapshot "$c" "$T1_TMP/s1"
cmp -s "$T1_TMP/s0" "$T1_TMP/s1" && pass "snapshot is equal again after undoing the changes" || fail "snapshot is equal again after undoing the changes"

# 4. tier1.sh: pass, fail, timeout (exit 124, names the limit), and the report line.
if sh "$T" --report "$T1_TMP/rep" -- true > "$T1_TMP/o.txt" 2>&1; then has "tier1.sh PASS report" "$T1_TMP/rep" "tier1 PASS "; else fail "tier1.sh passes a passing command"; fi
set +e; sh "$T" --report "$T1_TMP/rep" -- false > "$T1_TMP/o.txt" 2>&1; rc=$?; set -e
[ "$rc" = 1 ] && pass "tier1.sh keeps a failing command's exit code" || fail "tier1.sh keeps a failing command's exit code (got $rc)"
has "tier1.sh FAIL report" "$T1_TMP/rep" "tier1 FAIL "
set +e; sh "$T" --time-limit 1 --report "$T1_TMP/rep" -- sh -c 'sleep 30' > "$T1_TMP/o.txt" 2>&1; rc=$?; set -e
[ "$rc" = 124 ] && pass "tier1.sh stops a run past the limit with exit 124" || fail "tier1.sh stops a run past the limit with exit 124 (got $rc)"
has "tier1.sh timeout message names the limit" "$T1_TMP/o.txt" "past the 1s tier 1 time limit"
has "tier1.sh TIMEOUT report" "$T1_TMP/rep" "tier1 TIMEOUT "
expect_fail "tier1.sh refuses --time-limit 0" "$T1_TMP" sh "$T" --time-limit 0 -- true
expect_fail "tier1.sh refuses a non-number limit" "$T1_TMP" sh "$T" --time-limit 5m -- true

# 5. Cleanup removes only its own folder: a sibling temp folder and an unmarked folder survive.
keep="$(mktemp -d "${TMPDIR:-/tmp}/kit-tier1-keep.XXXXXX")"
inner="$(sh -c 'KIT="$1"; . "$1/scripts/lib/tier1-harness.sh"; printf "%s\n" "$T1_TMP"' _ "$KIT")"
[ ! -e "$inner" ] && pass "a run's own temp folder is gone after it exits" || fail "a run's own temp folder is gone after it exits ($inner)"
[ -d "$keep" ] && pass "another temp folder is left alone" || fail "another temp folder is left alone"
unm="$(sh -c 'KIT="$1"; . "$1/scripts/lib/tier1-harness.sh"; rm -f "$T1_TMP/.kit-tier1-owned"; printf "%s\n" "$T1_TMP"' _ "$KIT")"
[ -d "$unm" ] && pass "a folder without the run marker is not removed" || fail "a folder without the run marker is not removed"
# This suite made $keep and $unm itself in this run, so it may remove them.
rm -rf "$keep" "$unm"

t1_done test-tier1-harness
