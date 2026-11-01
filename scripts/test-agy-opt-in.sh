#!/bin/sh
# test-agy-opt-in.sh: the Antigravity (agy) adapter is opt-in (Kakashi 03:03, Sensei agy scope A: agy is out of the
# onboard fix and its adapter is unproven). A default install or --update copies no .agents/ file (.agents/hooks.json,
# rules, agents, commands, skills, hooks, the hook-python pin); install.sh --with-antigravity installs them exactly
# as before; --update without the flag leaves an existing .agents/ untouched (never deleted, moved or refreshed);
# --update --with-antigravity refreshes it. check-installed-kit.sh is HASH-OK in both modes and checks .agents/hooks
# whenever it is there. Tier 1: offline, temp folders only.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

# agy_snap <repo> <out>: every file and symlink under .agents/ with its sha256 and mode.
agy_snap() {
  ( cd "$1" && [ -d .agents ] && find .agents \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f_; do
      if [ -L "$f_" ]; then printf 'L %s %s\n' "$(readlink "$f_")" "$f_"
      else printf 'F %s %s %s\n' "$(t1_sha < "$f_")" "$(t1_mode "$f_")" "$f_"; fi; done ) > "$2" || :
}
# rest_snap <repo> <out>: every file outside .agents/ and .git/ (the version stamp aside), with sha256 and mode.
rest_snap() {
  ( cd "$1" && find . \( -name .git -o -name .agents \) -prune -o \( -type f -o -type l \) -print | grep -v '^\./\.agents-kit-version$' |
      LC_ALL=C sort | while IFS= read -r f_; do printf '%s %s %s\n' "$(t1_sha < "$f_")" "$(t1_mode "$f_")" "$f_"; done ) > "$2"
}
no_agy() { # <label> <repo>
  if [ -e "$2/.agents" ]; then fail "$1: no .agents/ at all ($(cd "$2" && find .agents | head -5 | tr '\n' ' '))"; else pass "$1: no .agents/ at all"; fi
}
upd() { KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" --update "$@" > "$T1_TMP/upd.log" 2>&1; }

# --- 1. static: the flag, its usage text and header, and validate-kit --------------------------------------------
has "install.sh parses --with-antigravity" "$KIT/scripts/install.sh" "    --with-antigravity)"
has "install.sh usage names --with-antigravity" "$KIT/scripts/install.sh" "[--with-antigravity]"
has "install.sh header documents --with-antigravity" "$KIT/scripts/install.sh" "#   --with-antigravity"
has "validate-kit runs this suite" "$KIT/scripts/validate-kit.sh" "sh scripts/test-agy-opt-in.sh"
has "validate-kit --target checks .agents/ only when it is installed" "$KIT/scripts/validate-kit.sh" '  if [ -e "$t/.agents" ]; then  # the Antigravity adapter is opt-in'

# --- 2. default install: no agy file; the Cursor side and HASH-OK as usual ------------------------------------------
D="$(t1_repo default --commit)"
t1_install "$D" && pass "default install runs" || fail "default install runs"
no_agy "default install" "$D"
[ -f "$D/.cursor/hooks.json" ] && [ -x "$D/.cursor/hooks/pre-shell.sh" ] && pass "default install: the Cursor adapter is installed" || fail "default install: the Cursor adapter is installed"
if t1_hash_ok "$D"; then pass "default install: check-installed-kit HASH-OK"; else fail "default install: check-installed-kit HASH-OK ($(cat "$T1_TMP/hash.txt"))"; fi
lacks "default install: check-installed-kit reports nothing about .agents/" "$T1_TMP/hash.txt" ".agents/"
upd "$D" && pass "default install: --update runs" || fail "default install: --update runs (see $T1_TMP/upd.log)"
no_agy "default install, --update" "$D"
lacks "default install, --update: no agy note" "$T1_TMP/upd.log" "--with-antigravity"
W="$(t1_repo starters --commit)"
t1_install "$W" --with-starters && pass "--with-starters install runs" || fail "--with-starters install runs"
no_agy "--with-starters install" "$W"

# --- 3. --with-antigravity: the agy tree as before; nothing else differs from a default install ---------------------
A="$(t1_repo agy --commit)"
t1_install "$A" --with-antigravity && pass "--with-antigravity install runs" || fail "--with-antigravity install runs"
if cmp -s "$KIT/core/common/adapters/antigravity/hooks.json" "$A/.agents/hooks.json"; then pass "opt-in: .agents/hooks.json is the kit adapter"; else fail "opt-in: .agents/hooks.json is the kit adapter"; fi
hk=0; for f in "$KIT"/core/common/hooks/*; do [ -f "$f" ] || continue; cmp -s "$f" "$A/.agents/hooks/${f##*/}" || hk=1; done
[ "$hk" = 0 ] && pass "opt-in: every core/common/hooks file is in .agents/hooks byte for byte" || fail "opt-in: every core/common/hooks file is in .agents/hooks byte for byte"
[ -x "$A/.agents/hooks/pre-shell.sh" ] && [ -x "$A/.agents/hooks/hook-policy.py" ] && pass "opt-in: the agy hooks are executable" || fail "opt-in: the agy hooks are executable"
if cmp -s "$A/.cursor/hooks/hook-python" "$A/.agents/hooks/hook-python" && [ "$(t1_mode "$A/.agents/hooks/hook-python")" = 644 ]; then pass "opt-in: .agents/hooks/hook-python is the same pin as Cursor's (644)"; else fail "opt-in: .agents/hooks/hook-python is the same pin as Cursor's (644)"; fi
if diff -r "$A/.cursor/rules/org" "$A/.agents/rules/org" >/dev/null; then pass "opt-in: .agents/rules/org equals .cursor/rules/org"; else fail "opt-in: .agents/rules/org equals .cursor/rules/org"; fi
if diff -r "$A/.cursor/agents" "$A/.agents/agents" >/dev/null; then pass "opt-in: .agents/agents equals .cursor/agents (models applied)"; else fail "opt-in: .agents/agents equals .cursor/agents (models applied)"; fi
if diff -r "$A/.cursor/commands" "$A/.agents/commands" >/dev/null; then pass "opt-in: .agents/commands equals .cursor/commands"; else fail "opt-in: .agents/commands equals .cursor/commands"; fi
sk=0; for f in "$KIT"/core/common/commands/*.md; do c_="$(basename "$f" .md)"; head -n 2 "$A/.agents/skills/$c_/SKILL.md" 2>/dev/null | grep -qx "name: $c_" || sk=1; done
[ "$sk" = 0 ] && pass "opt-in: each command has its .agents/skills/<command>/SKILL.md" || fail "opt-in: each command has its .agents/skills/<command>/SKILL.md"
[ -f "$A/.agents/skills/spec-intake/SKILL.md" ] && pass "opt-in: the kit skills are in .agents/skills" || fail "opt-in: the kit skills are in .agents/skills"
if t1_hash_ok "$A"; then pass "opt-in: check-installed-kit HASH-OK"; else fail "opt-in: check-installed-kit HASH-OK ($(cat "$T1_TMP/hash.txt"))"; fi
nd_="$(sed -n 's/^HASH-OK files=\([0-9]*\).*/\1/p' "$T1_TMP/hash.txt")"
sh "$KIT/scripts/check-installed-kit.sh" "$D" > "$T1_TMP/hashD.txt" 2>&1 || :
dd_="$(sed -n 's/^HASH-OK files=\([0-9]*\).*/\1/p' "$T1_TMP/hashD.txt")"
nh_=0; for f in "$KIT"/core/common/hooks/*; do [ -f "$f" ] && nh_=$((nh_ + 1)); done
if [ -n "$nd_" ] && [ -n "$dd_" ] && [ "$nd_" -eq $((dd_ + nh_)) ]; then pass "opt-in: check-installed-kit also hashes the $nh_ .agents/hooks files ($dd_ -> $nd_)"
else fail "opt-in: check-installed-kit also hashes the .agents/hooks files (default ${dd_:-?}, opt-in ${nd_:-?}, hooks $nh_)"; fi
rest_snap "$D" "$T1_TMP/restD"; rest_snap "$A" "$T1_TMP/restA"
sed 's/^[^ ]* [^ ]* //' "$T1_TMP/restD" > "$T1_TMP/restD.n"; sed 's/^[^ ]* [^ ]* //' "$T1_TMP/restA" > "$T1_TMP/restA.n"
if cmp -s "$T1_TMP/restD.n" "$T1_TMP/restA.n"; then pass "opt-in: outside .agents/ it installs the same files as a default install"; else fail "opt-in: outside .agents/ it installs the same files as a default install ($(diff "$T1_TMP/restD.n" "$T1_TMP/restA.n" | head -4 | tr '\n' ' '))"; fi

# --- 4. --update without the flag on a project that has .agents/: untouched, with a note ---------------------------
printf '\nproject note\n' >> "$A/.agents/rules/org/workflow-orchestration.mdc"
printf 'mine\n' > "$A/.agents/project-own.txt"
G "$A" add -A && G "$A" commit -qm "agy install"
agy_snap "$A" "$T1_TMP/agyA0"
upd "$A" && pass "agy project: --update (no flag) runs" || fail "agy project: --update (no flag) runs (see $T1_TMP/upd.log)"
agy_snap "$A" "$T1_TMP/agyA1"
if [ -s "$T1_TMP/agyA0" ] && cmp -s "$T1_TMP/agyA0" "$T1_TMP/agyA1"; then pass "agy project, --update (no flag): every .agents/ file is byte-identical (an edited rule and a project file too)"
else fail "agy project, --update (no flag): every .agents/ file is byte-identical ($(diff "$T1_TMP/agyA0" "$T1_TMP/agyA1" | head -4 | tr '\n' ' '))"; fi
[ -z "$(git -C "$A" status --porcelain -- .agents)" ] && pass "agy project, --update (no flag): git sees no change under .agents/" || fail "agy project, --update (no flag): git sees no change under .agents/"
[ ! -e "$A/trash" ] && pass "agy project, --update (no flag): nothing moved to trash/" || fail "agy project, --update (no flag): nothing moved to trash/"
has "agy project, --update (no flag): a note says how to refresh .agents/" "$T1_TMP/upd.log" "install.sh --update --with-antigravity"
if t1_hash_ok "$A"; then pass "agy project, --update (no flag): check-installed-kit HASH-OK"; else fail "agy project, --update (no flag): check-installed-kit HASH-OK ($(cat "$T1_TMP/hash.txt"))"; fi

# --- 5. a stale .agents/hooks fails check-installed-kit with the refresh hint; --update --with-antigravity fixes it --
printf '# stale\n' >> "$A/.agents/hooks/pre-shell.sh"
if t1_hash_ok "$A"; then fail "stale .agents/hooks: check-installed-kit fails"; else pass "stale .agents/hooks: check-installed-kit fails"; fi
has "stale .agents/hooks: DIFF line names the file" "$T1_TMP/hash.txt" "DIFF .agents/hooks/pre-shell.sh"
has "stale .agents/hooks: the line says how to refresh" "$T1_TMP/hash.txt" "install.sh --update --with-antigravity"
upd --with-antigravity "$A" && pass "agy project: --update --with-antigravity runs" || fail "agy project: --update --with-antigravity runs (see $T1_TMP/upd.log)"
if cmp -s "$KIT/core/common/hooks/pre-shell.sh" "$A/.agents/hooks/pre-shell.sh"; then pass "--update --with-antigravity: .agents/hooks refreshed"; else fail "--update --with-antigravity: .agents/hooks refreshed"; fi
if t1_hash_ok "$A"; then pass "--update --with-antigravity: check-installed-kit HASH-OK"; else fail "--update --with-antigravity: check-installed-kit HASH-OK ($(cat "$T1_TMP/hash.txt"))"; fi
[ -f "$A/.agents/project-own.txt" ] && pass "--update --with-antigravity: a project file under .agents/ stays" || fail "--update --with-antigravity: a project file under .agents/ stays"
lacks "--update --with-antigravity: no refresh note" "$T1_TMP/upd.log" "left as is"

# --- 6. --with-antigravity does not apply to --link ----------------------------------------------------------------
L="$(t1_repo link --commit)"
if sh "$KIT/scripts/install.sh" --link --commit HEAD --path "$KIT" --with-antigravity "$L" > "$T1_TMP/link.log" 2>&1; then fail "--link --with-antigravity is refused"
else has "--link --with-antigravity is refused" "$T1_TMP/link.log" "--with-antigravity"; fi
no_agy "--link --with-antigravity" "$L"

t1_done test-agy-opt-in
