#!/bin/sh
# test-update-retired-cleanup.sh: the `install.sh --update` cleanup of retired files (Sensei 2026-11-02 00:38,
# option A: "--update leaves my CI files, archives unedited retired kit files to trash/, warns on edited ones";
# N12A 00:52 for check-installed-kit.sh). Replaces the old `rm -rf` at install.sh:319.
# Cases (jiraiya-onboard-test-cases-20261101.md, revision 6):
#   N68 user CI files (.gitlab-ci.yml, .gitlab/CODEOWNERS) byte-identical after --update, unedited and edited,
#       with one note line, not moved to trash/
#   N69 unedited retired kit files (verify-gitlab-ci-prereqs.sh and the three :319 paths) sit in trash/ with
#       the same bytes and are gone from the old path; the cleanup step holds no rm/unlink (validate-kit greps)
#   N70 an edited retired copy stays in place, byte-identical, with a warning naming it; nothing in trash/ for it
#   N71 check-installed-kit.sh fails on an unedited retired file put back (path named), warns on an edited copy
#   E35 a second --update changes nothing; a name clash in trash/ gets a suffix; user files in trash/ untouched
#   E36 the step is general: synthetic list entries for the Cursor and agy /v0-release copies, no code change
#   plus safety cases: a missing or malformed list, `..`, absolute and trash/ paths are refused before anything
#   changes; symlinked retired paths, symlinked parents and a symlinked trash/ are left alone.
# Fixture: a real 36b86cf-era install (git archive 36b86cf from the kit's history, or KIT_HISTORY_GIT) plus the
# :319 files from 4103a544^. Without that history those cases print SKIP and the rest still run. Tier 1: offline, no agent, temp folders only. Run by validate-kit.sh.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

HIST="${KIT_HISTORY_GIT:-$KIT}"
ERA=36b86cf
OLD319=4103a544^
LIST="scripts/lib/retired-files.txt"
LIB="scripts/lib/retired-files.sh"
TR=trash/agents-v0-retired
VERIFY=.agents-v0/scripts/verify-gitlab-ci-prereqs.sh
CGL=.agents-v0/scripts/check-delivery-gate-local.sh
PRE=.agents-v0/hooks/pre-commit
CIF=.agents-v0/ci/gate.sh

# upd <kit> <repo> <log>: install.sh --update from <kit>; validate-kit is not re-entered (KIT_VALIDATING=1).
upd() { KIT_VALIDATING=1 sh "$1/scripts/install.sh" --update "$2" > "$3" 2>&1; }
# kit_copy <name>: a copy of this kit (no .git) under $T1_TMP, for list-only changes; prints its path.
kit_copy() {
  k_="$T1_TMP/$1"; mkdir -p "$k_"
  ( cd "$KIT" && for e_ in * .[!.]*; do [ -e "$e_" ] || continue; [ "$e_" = .git ] && continue; cp -R "$e_" "$k_/"; done )
  printf '%s\n' "$k_"
}
same_file() { if cmp -s "$2" "$3"; then pass "$1"; else fail "$1 ($2 differs from $3)"; fi; }
gone() { if [ -e "$2" ] || [ -L "$2" ]; then fail "$1 ($2 still there)"; else pass "$1"; fi; }
here() { if [ -f "$2" ]; then pass "$1"; else fail "$1 ($2 missing)"; fi; }
no_trash_named() { if [ -d "$2/trash" ] && find "$2/trash" -name "$3" | grep -q .; then fail "$1 ($3 found under trash/)"; else pass "$1"; fi; }
ck() { sh "$1/scripts/check-installed-kit.sh" "$2" > "$3" 2>&1; }

# --- the step itself, statically (N69) ----------------------------------------------------------------
here "N69: the cleanup step is a kit file ($LIB)" "$KIT/$LIB"
here "N69: the retired-files list is a kit file ($LIST)" "$KIT/$LIST"
if [ -f "$KIT/$LIB" ] && ! grep -v '^[[:space:]]*#' "$KIT/$LIB" | grep -Eq '(^|[^A-Za-z0-9_-])(rm|unlink|rmdir)([[:space:]]|$)'; then
  pass "N69: the cleanup step holds no rm, rm -rf, rmdir or unlink"; else fail "N69: the cleanup step holds no rm, rm -rf, rmdir or unlink"; fi
lacks "N69: install.sh no longer runs rm -rf on the retired :319 paths" "$KIT/scripts/install.sh" 'rm -rf "$t/.agents-v0/ci"'
has "N69: validate-kit greps the cleanup step for rm and unlink" "$KIT/scripts/validate-kit.sh" "$LIB holds rm or unlink"
has "validate-kit runs this suite" "$KIT/scripts/validate-kit.sh" "sh scripts/test-update-retired-cleanup.sh"

# --- the 36b86cf-era fixtures -------------------------------------------------------------------------
# History-dependent cases (N68-N71, E35) need $ERA and $OLD319. A clean copy without history (git archive +
# fresh git init) prints SKIP for them and still runs every other case; a KIT_HISTORY_GIT that is set but
# lacks them is a failure.
has_hist() { git -C "$1" cat-file -e "$ERA^{commit}" 2>/dev/null && git -C "$1" cat-file -e "$OLD319^{commit}" 2>/dev/null; }
HIST_OK=0
if [ -n "${KIT_HISTORY_GIT:-}" ]; then
  if has_hist "$KIT_HISTORY_GIT"; then HIST_OK=1
  else fail "KIT_HISTORY_GIT=$KIT_HISTORY_GIT has no $ERA and $OLD319 (it must be a full clone of the kit)"; fi
elif has_hist "$KIT"; then HIST_OK=1
else
  printf 'SKIP: N68, N69 (moves), N70, N71, E35: the %s-era fixture needs %s and %s (no git history; set KIT_HISTORY_GIT to a full clone)\n' "$ERA" "$ERA" "$OLD319"
fi
if [ "$HIST_OK" = 1 ]; then
OLDKIT="$T1_TMP/kit-$ERA"; mkdir -p "$OLDKIT"
git -C "$HIST" archive "$ERA" | tar -x -C "$OLDKIT"
OLD="$T1_TMP/old-bytes"; mkdir -p "$OLD"
git -C "$HIST" ls-tree -r --name-only "$OLD319" -- templates/.agents-v0/ci templates/$PRE templates/$CGL \
  | grep -v -e '\.pyc$' -e '/__pycache__/' > "$T1_TMP/old319.txt"
while IFS= read -r p; do
  rel="${p#templates/}"; mkdir -p "$OLD/$(dirname "$rel")"; git -C "$HIST" show "$OLD319:$p" > "$OLD/$rel"
done < "$T1_TMP/old319.txt"
[ "$(wc -l < "$T1_TMP/old319.txt" | tr -d ' ')" -ge 3 ] && pass "fixture: the :319 files from $OLD319" || fail "fixture: the :319 files from $OLD319"

# era <name>: a $ERA install plus the :319 files; prints the repo path
era() {
  r_="$(t1_repo "$1" --commit)"
  sh "$OLDKIT/scripts/install.sh" "$r_" > "$T1_TMP/$1-install.log" 2>&1 || { cat "$T1_TMP/$1-install.log" >&2; fail "fixture: $ERA install ($1)"; }
  ( cd "$OLD" && find . -type f ) | while IFS= read -r f_; do mkdir -p "$r_/$(dirname "${f_#./}")"; cp "$OLD/${f_#./}" "$r_/${f_#./}"; done
  printf '%s\n' "$r_"
}
# keep <repo> <dir>: save every file the cases compare against
keep() { mkdir -p "$2"; ( cd "$1" && for f_ in .gitlab-ci.yml .gitlab/CODEOWNERS $VERIFY $PRE $CGL $(cd "$OLD" && find .agents-v0/ci -type f); do
  [ -f "$f_" ] || continue; mkdir -p "$2/$(dirname "$f_")"; cp "$f_" "$2/$f_"; done ); }

A="$(era unedited)"
here "fixture: the $ERA install seeded .gitlab-ci.yml" "$A/.gitlab-ci.yml"
here "fixture: the $ERA install seeded $VERIFY" "$A/$VERIFY"
mkdir -p "$A/.agents-v0/ci"; printf '#!/bin/sh\necho my own check\n' > "$A/.agents-v0/ci/my-check.sh"
keep "$A" "$T1_TMP/A0"
upd "$KIT" "$A" "$T1_TMP/A1.log" && pass "--update of the unedited $ERA install" || fail "--update of the unedited $ERA install (see $T1_TMP/A1.log)"

B="$(era edited)"
printf '\n# our own pipeline tweak\n' >> "$B/.gitlab-ci.yml"
printf '* @acme/owners\n' >> "$B/.gitlab/CODEOWNERS"
printf '\n# edited by the team\n' >> "$B/$VERIFY"
printf '\n# edited by the team\n' >> "$B/$CIF"
keep "$B" "$T1_TMP/B0"
upd "$KIT" "$B" "$T1_TMP/B1.log" && pass "--update of the edited $ERA install" || fail "--update of the edited $ERA install (see $T1_TMP/B1.log)"

# N68: user CI files, unedited (A) and edited (B)
for v in A B; do
  eval "r=\$$v"
  for f in .gitlab-ci.yml .gitlab/CODEOWNERS; do
    same_file "N68 ($v): $f byte-identical after --update" "$T1_TMP/${v}0/$f" "$r/$f"
  done
  no_trash_named "N68 ($v): .gitlab-ci.yml not moved to trash/" "$r" .gitlab-ci.yml
  no_trash_named "N68 ($v): CODEOWNERS not moved to trash/" "$r" 'CODEOWNERS*'
  has "N68 ($v): a note says the kit no longer manages .gitlab-ci.yml" "$T1_TMP/${v}1.log" ".gitlab-ci.yml is your file: the kit no longer manages it"
  [ "$(grep -c 'no longer manages it' "$T1_TMP/${v}1.log" 2>/dev/null || true)" = 2 ] && pass "N68 ($v): one note line per user CI file" || fail "N68 ($v): one note line per user CI file"
done

# N69: unedited retired kit files go to trash/ with the same bytes and leave their old path; nothing removed
for f in $VERIFY $PRE $CGL $(cd "$OLD" && find .agents-v0/ci -type f | LC_ALL=C sort); do
  same_file "N69: $f is in $TR/ with the same bytes" "$T1_TMP/A0/$f" "$A/$TR/$f"
  gone "N69: $f is gone from its old path" "$A/$f"
done

here "N69: the user's .agents-v0/ci/my-check.sh is still in place" "$A/.agents-v0/ci/my-check.sh"
has "N69: --update names each move" "$T1_TMP/A1.log" "RETIRED: $VERIFY moved to $TR/$VERIFY"

# N70: the edited copies stay, byte-identical, with a warning naming each; nothing in trash/ for them
for f in $VERIFY $CIF; do
  same_file "N70: edited $f stays in place, byte-identical" "$T1_TMP/B0/$f" "$B/$f"
  gone "N70: nothing goes to trash/ for edited $f" "$B/$TR/$f"
  has "N70: --update warns about edited $f" "$T1_TMP/B1.log" "WARN: retired kit file $f was edited"
done
same_file "N70: the unedited $CGL in the same install still moves" "$T1_TMP/B0/$CGL" "$B/$TR/$CGL"

# N71: check-installed-kit.sh (N12A): after --update it passes; an unedited retired file put back fails with
# the path named; the edited copy (B) only warns
if ck "$KIT" "$A" "$T1_TMP/ckA.txt"; then pass "N71: check-installed-kit passes after the cleanup"; else fail "N71: check-installed-kit passes after the cleanup ($(tr '\n' ' ' < "$T1_TMP/ckA.txt"))"; fi
cp "$T1_TMP/A0/$VERIFY" "$A/$VERIFY"; cp "$T1_TMP/A0/$CGL" "$A/$CGL"
if ck "$KIT" "$A" "$T1_TMP/ckA2.txt"; then fail "N71(1): an unedited retired file put back fails check-installed-kit"; else pass "N71(1): an unedited retired file put back fails check-installed-kit"; fi
has "N71(1): the failure names $VERIFY" "$T1_TMP/ckA2.txt" "RETIRED-LEFT $VERIFY"
has "N71(1): the failure names $CGL" "$T1_TMP/ckA2.txt" "RETIRED-LEFT $CGL"
mv "$A/$VERIFY" "$T1_TMP/putback-verify"; mv "$A/$CGL" "$T1_TMP/putback-cgl"
if ck "$KIT" "$B" "$T1_TMP/ckB.txt"; then pass "N71(2): the edited copy does not fail check-installed-kit"; else fail "N71(2): the edited copy does not fail check-installed-kit ($(tr '\n' ' ' < "$T1_TMP/ckB.txt"))"; fi
has "N71(2): check-installed-kit warns about the edited $VERIFY" "$T1_TMP/ckB.txt" "WARN RETIRED-EDITED $VERIFY"

# E35: a second --update changes nothing, with the same note and warning
for v in A B; do
  eval "r=\$$v"
  t1_snapshot "$r" "$T1_TMP/${v}s1"
  upd "$KIT" "$r" "$T1_TMP/${v}2.log" || fail "E35 ($v): the second --update runs (see $T1_TMP/${v}2.log)"
  t1_snapshot "$r" "$T1_TMP/${v}s2"
  if cmp -s "$T1_TMP/${v}s1" "$T1_TMP/${v}s2"; then pass "E35 ($v): the second --update changes nothing"
  else fail "E35 ($v): the second --update changes nothing ($(diff "$T1_TMP/${v}s1" "$T1_TMP/${v}s2" | head -4 | tr '\n' ' '))"; fi
  lacks "E35 ($v): no new moves on the second run" "$T1_TMP/${v}2.log" "RETIRED:"
  grep -E '^(NOTE|WARN: retired)' "$T1_TMP/${v}1.log" > "$T1_TMP/${v}n1" || true
  grep -E '^(NOTE|WARN: retired)' "$T1_TMP/${v}2.log" > "$T1_TMP/${v}n2" || true
  if [ -s "$T1_TMP/${v}n1" ] && cmp -s "$T1_TMP/${v}n1" "$T1_TMP/${v}n2"; then pass "E35 ($v): the same note and warning lines"; else fail "E35 ($v): the same note and warning lines"; fi
done
# E35: a name clash in trash/ and the repo's own trash/ files
C="$(era clash)"
mkdir -p "$C/$TR/.agents-v0/scripts" "$C/trash/notes"
printf 'an older copy the team archived\n' > "$C/$TR/$VERIFY"
printf 'our notes\n' > "$C/trash/notes/keep.txt"
printf 'flat copy\n' > "$C/trash/verify-gitlab-ci-prereqs.sh"
cp "$C/$TR/$VERIFY" "$T1_TMP/clash-before"; cp "$C/trash/notes/keep.txt" "$T1_TMP/keep-before"; cp "$C/trash/verify-gitlab-ci-prereqs.sh" "$T1_TMP/flat-before"
keep "$C" "$T1_TMP/C0"
upd "$KIT" "$C" "$T1_TMP/C1.log" || fail "E35: --update with a clash in trash/ runs (see $T1_TMP/C1.log)"
same_file "E35: the file already in trash/ is not overwritten" "$T1_TMP/clash-before" "$C/$TR/$VERIFY"
same_file "E35: the clashing move gets a new suffix (.1) and keeps its bytes" "$T1_TMP/C0/$VERIFY" "$C/$TR/$VERIFY.1"
gone "E35: the clashing file left its old path" "$C/$VERIFY"
same_file "E35: the repo's own trash/notes/keep.txt is untouched" "$T1_TMP/keep-before" "$C/trash/notes/keep.txt"
same_file "E35: the repo's own trash/verify-gitlab-ci-prereqs.sh is untouched" "$T1_TMP/flat-before" "$C/trash/verify-gitlab-ci-prereqs.sh"

fi # HIST_OK

# --- E36: the step is general (only list entries change) ----------------------------------------------
K2="$(kit_copy kit-e36)"
R="$(t1_repo e36 --commit)"
t1_install "$R" || fail "E36: fresh install for the synthetic entries"
E36P=".agents/skills/v0-release/SKILL.md .agents/commands/v0-release.md .cursor/commands/v0-release.md"
mkdir -p "$T1_TMP/e36-0"
for f in $E36P; do
  here "E36: the fixture has $f" "$R/$f"
  [ -f "$R/$f" ] || continue
  mkdir -p "$T1_TMP/e36-0/$(dirname "$f")"; cp "$R/$f" "$T1_TMP/e36-0/$f"
  [ -f "$K2/$LIST" ] || printf '# agents-v0 retired-files v1\n' > "$K2/$LIST"
  printf 'kit-managed %s %s\n' "$(t1_sha < "$R/$f")" "$f" >> "$K2/$LIST"
done
# a later retirement: the kit stops shipping /v0-release (data, not code) and lists its installed copies
mkdir -p "$T1_TMP/held"; mv "$K2/core/common/commands/v0-release.md" "$T1_TMP/held/"
printf '\n# edited by the team\n' >> "$R/.cursor/commands/v0-release.md"; cp "$R/.cursor/commands/v0-release.md" "$T1_TMP/e36-edited"
upd "$K2" "$R" "$T1_TMP/E1.log" || fail "E36: --update with synthetic entries runs (see $T1_TMP/E1.log)"
for f in .agents/skills/v0-release/SKILL.md .agents/commands/v0-release.md; do
  same_file "E36: unedited agy copy $f is in $TR/ with the same bytes" "$T1_TMP/e36-0/$f" "$R/$TR/$f"
  gone "E36: unedited agy copy $f is gone from its old path" "$R/$f"
done
same_file "E36: the edited Cursor copy stays in place" "$T1_TMP/e36-edited" "$R/.cursor/commands/v0-release.md"
has "E36: --update warns about the edited Cursor copy" "$T1_TMP/E1.log" "WARN: retired kit file .cursor/commands/v0-release.md was edited"
if ck "$K2" "$R" "$T1_TMP/ckE.txt"; then pass "E36: check-installed-kit passes with only the edited copy left"; else fail "E36: check-installed-kit passes with only the edited copy left ($(tr '\n' ' ' < "$T1_TMP/ckE.txt"))"; fi
has "E36: check-installed-kit warns about the edited Cursor copy" "$T1_TMP/ckE.txt" "WARN RETIRED-EDITED .cursor/commands/v0-release.md"
cp "$T1_TMP/e36-0/.agents/commands/v0-release.md" "$R/.agents/commands/v0-release.md"
if ck "$K2" "$R" "$T1_TMP/ckE2.txt"; then fail "E36: an unedited agy copy put back fails check-installed-kit"; else pass "E36: an unedited agy copy put back fails check-installed-kit"; fi
has "E36: the failure names the agy path" "$T1_TMP/ckE2.txt" "RETIRED-LEFT .agents/commands/v0-release.md"

# --- safety: a missing or malformed list fails before anything changes ---------------------------------
# Synthetic retired kit files (no history needed): KS lists them with the hashes of known bytes.
SYN=.agents-v0/scripts/old-tool.sh
SYNCI=.agents-v0/oldci/gate.sh
printf '#!/bin/sh\n# a retired kit tool (synthetic fixture)\necho old tool\n' > "$T1_TMP/syn.sh"
printf '#!/bin/sh\n# a retired kit check (synthetic fixture)\necho old ci\n' > "$T1_TMP/synci.sh"
H="$(t1_sha < "$T1_TMP/syn.sh")"
KS="$(kit_copy kit-syn)"
printf 'kit-managed %s %s\nkit-managed %s %s\n' "$H" "$SYN" "$(t1_sha < "$T1_TMP/synci.sh")" "$SYNCI" >> "$KS/$LIST"
K3="$(kit_copy kit-bad)"
S="$(t1_repo safety --commit)"
t1_install "$S" || fail "safety: fresh install"
cp "$T1_TMP/syn.sh" "$S/$SYN"
bad_list() { # <description> <list text, or MISSING>
  if [ "$2" = MISSING ]; then [ ! -e "$K3/$LIST" ] || mv "$K3/$LIST" "$T1_TMP/list-moved.$$"; else printf '%s' "$2" > "$K3/$LIST"; fi
  t1_snapshot "$S" "$T1_TMP/ss0"
  if upd "$K3" "$S" "$T1_TMP/bad.log"; then fail "safety: $1: --update refuses"; else pass "safety: $1: --update refuses"; fi
  has "safety: $1: the refusal names the list" "$T1_TMP/bad.log" "retired-files.txt"
  t1_snapshot "$S" "$T1_TMP/ss1"
  if cmp -s "$T1_TMP/ss0" "$T1_TMP/ss1"; then pass "safety: $1: nothing changed"; else fail "safety: $1: nothing changed"; fi
}
bad_list "missing list" MISSING
bad_list "empty list" ""
bad_list "no header" "kit-managed $H $SYN
"
bad_list "bad hash" "# agents-v0 retired-files v1
kit-managed nothex $SYN
"
bad_list "unknown kind" "# agents-v0 retired-files v1
kit-owned $H $SYN
"
bad_list "a .. path" "# agents-v0 retired-files v1
kit-managed $H .agents-v0/../../outside.sh
"
bad_list "an absolute path" "# agents-v0 retired-files v1
kit-managed $H /etc/hostname
"
bad_list "a path under trash/" "# agents-v0 retired-files v1
kit-managed $H trash/x.sh
"
bad_list "two spaces" "# agents-v0 retired-files v1
kit-managed  $H $SYN
"
bad_list "CRLF line ends" "$(printf '# agents-v0 retired-files v1\r\nkit-managed %s %s\r\n' "$H" "$SYN")"
here "safety: the planted retired file is still in place after every refusal" "$S/$SYN"
# control: with a good list the same planted file does move (so the refusals above are the list's doing)
upd "$KS" "$S" "$T1_TMP/S2.log" || fail "safety: --update with the good synthetic list runs (see $T1_TMP/S2.log)"
same_file "safety: control: the unedited synthetic file moves to $TR/" "$T1_TMP/syn.sh" "$S/$TR/$SYN"
gone "safety: control: the unedited synthetic file left its old path" "$S/$SYN"

# --- safety: symlinks are never followed -------------------------------------------------------------
L="$(t1_repo links --commit)"
t1_install "$L" || fail "links: fresh install"
OUT="$T1_TMP/outside"; mkdir -p "$OUT/oldci" "$OUT/trash"
cp "$T1_TMP/syn.sh" "$OUT/syn.sh"; cp "$T1_TMP/synci.sh" "$OUT/oldci/gate.sh"
ln -s "$OUT/syn.sh" "$L/$SYN"
ln -s "$OUT/oldci" "$L/.agents-v0/oldci"
upd "$KS" "$L" "$T1_TMP/L1.log" || fail "links: --update runs (see $T1_TMP/L1.log)"
[ -L "$L/$SYN" ] && pass "links: a symlinked retired file is left in place" || fail "links: a symlinked retired file is left in place"
same_file "links: the symlink's target outside the repo is untouched" "$T1_TMP/syn.sh" "$OUT/syn.sh"
same_file "links: a file under a symlinked retired folder stays (outside the repo)" "$T1_TMP/synci.sh" "$OUT/oldci/gate.sh"
has "links: --update warns about the symlinked retired file" "$T1_TMP/L1.log" "$SYN is a symlink or sits under one"
has "links: --update warns about the file under a symlinked folder" "$T1_TMP/L1.log" "$SYNCI is a symlink or sits under one"
gone "links: nothing reached trash/ through a symlink" "$L/trash"
P2="$(t1_repo trashlink --commit)"
t1_install "$P2" || fail "trashlink: fresh install"
cp "$T1_TMP/syn.sh" "$P2/$SYN"; ln -s "$OUT/trash" "$P2/trash"
upd "$KS" "$P2" "$T1_TMP/P1.log" || fail "trashlink: --update runs (see $T1_TMP/P1.log)"
here "trashlink: with trash/ a symlink the retired file stays in place" "$P2/$SYN"
[ -z "$(ls -A "$OUT/trash")" ] && pass "trashlink: nothing is moved out of the repo through trash/" || fail "trashlink: nothing is moved out of the repo through trash/"

t1_done test-update-retired-cleanup
