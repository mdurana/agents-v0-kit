#!/bin/sh
# test-tier1-harness.sh: self-test for scripts/lib/tier1-harness.sh, tier1-vars.sh and scripts/tier1.sh
# (onboard fix, step 0). Offline, no agent. Checks the AGENTS_V0_* guard (on source and in tier1.sh), the
# install-into-a-temp-repo fixture and HASH-OK, the byte-identical snapshot (used by E37 and E38: work-tree
# files and modes, untracked files, symlinks, staged entries, refs, .git/agents-v0), the time limit, a
# manual stop and the report line, and that cleanup removes only this run's own temp folder.
# Run by validate-kit.sh.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"
T="$KIT/scripts/tier1.sh"
# src <shell text>: run text in a fresh sh that has sourced the harness
src() { sh -c 'KIT="$1"; shift; . "$KIT/scripts/lib/tier1-harness.sh"; eval "$1"' _ "$KIT" "$1"; }
# kids_of <pid>: any process still in that process group
left_in_group() { ps -eo pgid= 2>/dev/null | tr -d ' ' | grep -qx "$1"; }

# 1. The guard refuses each of the seven test switches: on sourcing the harness, and in tier1.sh.
for v in $T1_OVERRIDE_VARS; do
  if env "$v=1" sh -c 'KIT="$1"; . "$1/scripts/lib/tier1-harness.sh"; echo sourced' _ "$KIT" > "$T1_TMP/g.txt" 2>&1; then
    fail "sourcing the harness refuses $v"; else has "sourcing the harness names $v" "$T1_TMP/g.txt" "$v"; lacks "sourcing stops before any test runs ($v)" "$T1_TMP/g.txt" sourced; fi
  if env "$v=" sh "$T" -- true > "$T1_TMP/g.txt" 2>&1; then fail "tier1.sh refuses $v (even when empty)"
  else has "tier1.sh names $v" "$T1_TMP/g.txt" "$v"; fi
done
[ "$(printf '%s\n' $T1_OVERRIDE_VARS | wc -l | tr -d ' ')" = 7 ] && pass "one list of seven switches" || fail "one list of seven switches"

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

# 3. Snapshot: stable, sees each kind of change, and equal again once the change is undone.
s0="$T1_TMP/s0"; s1="$T1_TMP/s1"
t1_snapshot "$c" "$s0"; t1_snapshot "$c" "$s1"
cmp -s "$s0" "$s1" && pass "snapshot is stable" || fail "snapshot is stable"
same() { t1_snapshot "$c" "$s1"; if cmp -s "$s0" "$s1"; then pass "$1"; else fail "$1"; fi; }
diff_() { t1_snapshot "$c" "$s1"; if cmp -s "$s0" "$s1"; then fail "$1"; else pass "$1"; fi; }
printf 'x\n' >> "$c/README.md"; diff_ "snapshot sees a tracked edit"; G "$c" checkout -q -- README.md
chmod 755 "$c/README.md"; diff_ "snapshot sees a mode change"; chmod 644 "$c/README.md"
printf 'u\n' > "$c/untracked.txt"; diff_ "snapshot sees an untracked file"
G "$c" add untracked.txt; diff_ "snapshot sees a staged file"; G "$c" rm -q --cached untracked.txt; mv "$c/untracked.txt" "$T1_TMP/"
ln -s README.md "$c/link"; diff_ "snapshot sees a symlink"; mv "$c/link" "$T1_TMP/"
mkdir -p "$c/.git/agents-v0"; printf 'gate\n' > "$c/.git/agents-v0/gate-ledger"; diff_ "snapshot sees a new ledger in .git/agents-v0"
t1_snapshot "$c" "$s0"; printf 'more\n' >> "$c/.git/agents-v0/gate-ledger"; diff_ "snapshot sees a ledger change"
printf 'gate\n' > "$c/.git/agents-v0/gate-ledger"; same "snapshot is equal after restoring the ledger"
G "$c" branch side; diff_ "snapshot sees a new ref"; G "$c" branch -q -D side
same "snapshot is equal again after undoing the changes"
G "$c" worktree add -q "$T1_TMP/wt" -b wtb 2>/dev/null
if t1_snapshot "$T1_TMP/wt" "$T1_TMP/swt" && grep -q '^H refs/heads/wtb' "$T1_TMP/swt"; then pass "snapshot works in a linked worktree"; else fail "snapshot works in a linked worktree"; fi

# 4. tier1.sh: pass, fail, timeout (exit 124, names the limit, no process left), a manual stop, the report.
if sh "$T" --report "$T1_TMP/rep" -- true > "$T1_TMP/o.txt" 2>&1; then has "tier1.sh PASS report" "$T1_TMP/rep" "tier1 PASS "; else fail "tier1.sh passes a passing command"; fi
grep -Eq '^tier1 PASS [0-9a-f]{40} (clean|dirty) [0-9]+s ' "$T1_TMP/rep" && pass "report has the full commit and clean|dirty" || fail "report has the full commit and clean|dirty ($(cat "$T1_TMP/rep"))"
set +e; sh "$T" --report "$T1_TMP/rep" -- false > "$T1_TMP/o.txt" 2>&1; rc=$?; set -e
[ "$rc" = 1 ] && pass "tier1.sh keeps a failing command's exit code" || fail "tier1.sh keeps a failing command's exit code (got $rc)"
has "tier1.sh FAIL report" "$T1_TMP/rep" "tier1 FAIL "
set +e; sh "$T" --time-limit 1 -- sh -c 'sleep 3; exit 1' > "$T1_TMP/o.txt" 2>&1; rc=$?; set -e
[ "$rc" = 124 ] && pass "a run past the limit is a TIMEOUT" || fail "a run past the limit is a TIMEOUT (got $rc)"
set +e; sh "$T" --time-limit 5 -- sh -c 'sleep 1; exit 3' > "$T1_TMP/o.txt" 2>&1; rc=$?; set -e
[ "$rc" = 3 ] && pass "a failure inside the limit is a FAIL, not a TIMEOUT" || fail "a failure inside the limit is a FAIL, not a TIMEOUT (got $rc)"
set +e; sh "$T" --time-limit 1 --report "$T1_TMP/rep" -- sh -c 'sleep 30 & sleep 30; wait' > "$T1_TMP/o.txt" 2>&1; rc=$?; set -e
[ "$rc" = 124 ] && pass "tier1.sh stops a run past the limit with exit 124" || fail "tier1.sh stops a run past the limit with exit 124 (got $rc)"
has "tier1.sh timeout message names the limit" "$T1_TMP/o.txt" "at the 1s tier 1 time limit"
has "tier1.sh TIMEOUT report" "$T1_TMP/rep" "tier1 TIMEOUT "
sleep 1
if pgrep -f 'sleep 30' >/dev/null 2>&1 && ps -eo args= | grep -q '^sleep 30$'; then
  ps -eo pid=,pgid=,args= | grep ' sleep 30$' > "$T1_TMP/left.txt" || true
  fail "no process is left after a timeout ($(cat "$T1_TMP/left.txt"))"
else pass "no process is left after a timeout"; fi
sh "$T" -- sh -c 'sleep 40 & sleep 40; wait' > "$T1_TMP/o.txt" 2>&1 & tp=$!
sleep 1; kill -TERM "$tp"; set +e; wait "$tp"; rc=$?; set -e
[ "$rc" = 143 ] && pass "a TERM stops tier1.sh with exit 143" || fail "a TERM stops tier1.sh with exit 143 (got $rc)"
sleep 2
if ps -eo args= | grep -q '^sleep 40$'; then fail "no process is left after a TERM"; else pass "no process is left after a TERM"; fi
expect_fail "tier1.sh refuses --time-limit 0" "$T1_TMP" sh "$T" --time-limit 0 -- true
expect_fail "tier1.sh refuses a non-number limit" "$T1_TMP" sh "$T" --time-limit 5m -- true
expect_fail "tier1.sh refuses --time-limit with no value" "$T1_TMP" sh "$T" --time-limit

# 5. Cleanup removes only its own folder.
keep="$(mktemp -d "${TMPDIR:-/tmp}/kit-tier1-keep.XXXXXX")"
inner="$(src 'printf "%s\n" "$T1_TMP"')"
[ -n "$inner" ] && [ ! -e "$inner" ] && pass "a run's own temp folder is gone after it exits" || fail "a run's own temp folder is gone after it exits ($inner)"
[ -d "$keep" ] && pass "another temp folder is left alone" || fail "another temp folder is left alone"
# A victim folder outside the run, marked like a run folder: T1_TMP cannot be pointed at it.
victim="$keep/victim"; mkdir -p "$victim"; : > "$victim/.kit-tier1-owned"
src 'T1_TMP="$T1_TMP/../../'"${keep##*/}"'/victim"' > "$T1_TMP/o.txt" 2>&1 || true
[ -d "$victim" ] && pass "T1_TMP cannot be pointed outside the run (readonly)" || fail "T1_TMP cannot be pointed outside the run (readonly)"
# A marker with the wrong token is not removed; neither is one with no marker.
unm="$(src 'printf x > "$T1_TMP/.kit-tier1-owned"; printf "%s\n" "$T1_TMP"')"
[ -d "$unm" ] && pass "a folder whose marker lacks the run token is not removed" || fail "a folder whose marker lacks the run token is not removed"
unm2="$(src 'rm -f "$T1_TMP/.kit-tier1-owned"; printf "%s\n" "$T1_TMP"')"
[ -d "$unm2" ] && pass "a folder without the run marker is not removed" || fail "a folder without the run marker is not removed"
# A failed mktemp stops the harness and writes nothing at the filesystem root.
if TMPDIR="$T1_TMP/does-not-exist" sh -c 'KIT="$1"; . "$1/scripts/lib/tier1-harness.sh"' _ "$KIT" > "$T1_TMP/o.txt" 2>&1; then
  fail "a missing temp root stops the harness"; else pass "a missing temp root stops the harness"; fi
[ ! -e /.kit-tier1-owned ] && pass "no marker is written at the filesystem root" || fail "no marker is written at the filesystem root"
# This suite made $keep, $unm and $unm2 itself in this run, so it may remove them.
rm -rf "$keep" "$unm" "$unm2"

t1_done test-tier1-harness
