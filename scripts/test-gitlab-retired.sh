#!/bin/sh
# test-gitlab-retired.sh: E28, the GitLab CI retirement (Sensei 23:54, narrowed by N1 at 00:38).
# The kit no longer ships .gitlab-ci.yml, .gitlab/CODEOWNERS or verify-gitlab-ci-prereqs.sh: they sit in the
# kit's trash/gitlab-ci-retired-20261102/ (same relative paths, kept in git history, never deleted), and
# nothing copies trash/ into a project. The MR template and render-mr-body.sh stay (N1, E32).
# Cases: the kit layout; install.sh seeds and refreshes none of them (fresh, --with-starters, --update) and
# keeps the MR template; validate-kit no longer requires them and guards that they do not come back; the
# retired-files list keeps them (user-owned CI files, kit-managed verify script). An --update of a
# 36b86cf-era install is N68/N69 in test-update-retired-cleanup.sh. Tier 1: offline, temp folders only.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"

TRD=trash/gitlab-ci-retired-20261102
MR=.gitlab/merge_request_templates/default.md
VERIFY=.agents-v0/scripts/verify-gitlab-ci-prereqs.sh
LIST="$KIT/scripts/lib/retired-files.txt"
RETIRED=".gitlab-ci.yml templates/.gitlab-ci.yml templates/.gitlab/CODEOWNERS templates/$VERIFY"
here() { if [ -f "$2" ]; then pass "$1"; else fail "$1 ($2 missing)"; fi; }
gone() { if [ -e "$2" ] || [ -L "$2" ]; then fail "$1 ($2 is there)"; else pass "$1"; fi; }

# --- the kit layout -------------------------------------------------------------------------------------
for p in $RETIRED; do
  gone "E28: the kit no longer has $p" "$KIT/$p"
  here "E28: $p is archived at $TRD/$p" "$KIT/$TRD/$p"
done
here "E28/E32: the MR template is still shipped" "$KIT/templates/$MR"
here "E28/E32: render-mr-body.sh is still shipped" "$KIT/templates/.agents-v0/scripts/render-mr-body.sh"
if [ -f "$KIT/$TRD/templates/$VERIFY" ] && grep -Fqx "kit-managed $(t1_sha < "$KIT/$TRD/templates/$VERIFY") $VERIFY" "$LIST"; then
  pass "E28: the archived verify script is a released version in retired-files.txt"
else fail "E28: the archived verify script is a released version in retired-files.txt"; fi
has "E28: retired-files.txt keeps .gitlab-ci.yml as user-owned" "$LIST" "user-owned - .gitlab-ci.yml"
has "E28: retired-files.txt keeps .gitlab/CODEOWNERS as user-owned" "$LIST" "user-owned - .gitlab/CODEOWNERS"
has "E28: retired-files.txt keeps verify-gitlab-ci-prereqs.sh as kit-managed" "$LIST" " $VERIFY"

# --- install.sh and validate-kit.sh, statically --------------------------------------------------------
I="$KIT/scripts/install.sh"
if grep -Eq '^\.gitlab-ci\.yml$|^\.gitlab/CODEOWNERS$|verify-gitlab-ci-prereqs\.sh' "$I"; then
  fail "E28: install.sh no longer lists .gitlab-ci.yml, CODEOWNERS or verify-gitlab-ci-prereqs.sh ($(grep -nE '^\.gitlab-ci\.yml$|^\.gitlab/CODEOWNERS$|verify-gitlab-ci-prereqs\.sh' "$I" | cut -d: -f1 | tr '\n' ' '))"
else pass "E28: install.sh no longer lists .gitlab-ci.yml, CODEOWNERS or verify-gitlab-ci-prereqs.sh"; fi
lacks "E28: the dead CODEOWNERS @your-team warning is gone from install.sh" "$I" "@your-team"
[ "$(grep -cx "$MR" "$I" || true)" = 2 ] && pass "E28/N1: install.sh still seeds and refreshes the MR template" || fail "E28/N1: install.sh still seeds and refreshes the MR template"
V="$KIT/scripts/validate-kit.sh"
if grep -Eq '^[[:space:]]+templates/(\.gitlab-ci\.yml|\.gitlab/CODEOWNERS|\.agents-v0/scripts/verify-gitlab-ci-prereqs\.sh) \\$' "$V"; then
  fail "E28: validate-kit no longer requires the retired GitLab artefacts"; else pass "E28: validate-kit no longer requires the retired GitLab artefacts"; fi
lacks "E28: validate-kit no longer lints templates/.gitlab-ci.yml" "$V" "' templates/.gitlab-ci.yml"
has "E28: validate-kit guards that the retired GitLab files are not shipped again" "$V" "retired GitLab file is shipped again (E28)"
has "E28/N1: validate-kit still requires the MR template" "$V" "templates/$MR"
has "validate-kit runs this suite" "$V" "sh scripts/test-gitlab-retired.sh"

# --- behaviour: fresh install, --with-starters, --update ----------------------------------------------
no_gitlab() { # <label> <repo>
  for f in .gitlab-ci.yml .gitlab/CODEOWNERS "$VERIFY"; do gone "E28 ($1): $f is not installed" "$2/$f"; done
  gone "E28 ($1): no trash/ is created in the project" "$2/trash"
  if find "$2" -path "$2/.git" -prune -o -name '*gitlab-ci-retired*' -print | grep -q .; then
    fail "E28 ($1): nothing from the kit's $TRD reaches the project"; else pass "E28 ($1): nothing from the kit's $TRD reaches the project"; fi
  if cmp -s "$KIT/templates/$MR" "$2/$MR"; then pass "E28/N1 ($1): the MR template is installed"; else fail "E28/N1 ($1): the MR template is installed"; fi
  if t1_hash_ok "$2"; then pass "E28 ($1): check-installed-kit passes"; else fail "E28 ($1): check-installed-kit passes ($(tr '\n' ' ' < "$T1_TMP/hash.txt"))"; fi
}
F="$(t1_repo fresh --commit)"
t1_install "$F" && pass "E28: fresh install" || fail "E28: fresh install"
no_gitlab fresh "$F"
W="$(t1_repo starters --commit)"
t1_install "$W" --with-starters && pass "E28: --with-starters install" || fail "E28: --with-starters install"
no_gitlab with-starters "$W"
# --update: the project's own CI files stay byte-identical; the MR template is refreshed (N1)
U="$(t1_repo update --commit)"
t1_install "$U" || fail "E28: install before --update"
mkdir -p "$U/.gitlab"
printf 'stages: [build]\nbuild:\n  script: [make]\n' > "$U/.gitlab-ci.yml"
printf '* @acme/owners\n' > "$U/.gitlab/CODEOWNERS"
cp "$U/.gitlab-ci.yml" "$T1_TMP/ci-before"; cp "$U/.gitlab/CODEOWNERS" "$T1_TMP/co-before"
printf '\nlocal edit\n' >> "$U/$MR"
KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" --update "$U" > "$T1_TMP/upd.log" 2>&1 && pass "E28: --update runs" || fail "E28: --update runs (see $T1_TMP/upd.log)"
if cmp -s "$T1_TMP/ci-before" "$U/.gitlab-ci.yml"; then pass "E28/N68 (--update): the project's .gitlab-ci.yml is byte-identical"; else fail "E28/N68 (--update): the project's .gitlab-ci.yml is byte-identical"; fi
if cmp -s "$T1_TMP/co-before" "$U/.gitlab/CODEOWNERS"; then pass "E28/N68 (--update): the project's CODEOWNERS is byte-identical"; else fail "E28/N68 (--update): the project's CODEOWNERS is byte-identical"; fi
if cmp -s "$KIT/templates/$MR" "$U/$MR"; then pass "E28/N1 (--update): the MR template is refreshed"; else fail "E28/N1 (--update): the MR template is refreshed"; fi
gone "E28 (--update): verify-gitlab-ci-prereqs.sh is not installed" "$U/$VERIFY"
lacks "E28 (--update): no @your-team warning" "$T1_TMP/upd.log" "@your-team"

t1_done test-gitlab-retired
