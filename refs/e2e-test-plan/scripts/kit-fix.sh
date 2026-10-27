#!/usr/bin/env bash
# kit-fix.sh — the kit fix procedure of fix-and-resume.md §4, as three sub-commands run one after the other.
#   bash scripts/kit-fix.sh start  --test-root <dir> --step <N>   clone the kit (once per run) and open the fix branch
#   bash scripts/kit-fix.sh check  --test-root <dir>              fix comments + fixes-doc entry + syntax + validate-kit
#   bash scripts/kit-fix.sh finish --test-root <dir>              write the patch; commit/push only when the flags say so
# Rules this script enforces:
#   * the fix branch starts at the exact kit commit the test used (first kit_sha= in results/run.meta), plus any earlier
#     fixes of the same run, so fixes accumulate; the patch is always the whole difference from that base commit
#   * nothing is committed unless KIT_FIX_COMMIT=1; nothing is pushed unless KIT_FIX_PUSH=1 (and KIT_FIX_COMMIT=1);
#     a push only creates or fast-forwards the fix branch; never force, never a base branch, never a merge, never a PR
#   * validate-kit.sh takes no --quick flag: quick mode is the env var KIT_SKIP_APP_TEMPLATE_TEST=1; full mode needs JDK 21
# Exit: 0 ok, 1 check failed (details printed), 2 refused (bad state or flags), 3 limit reached.
set -u
cmd="${1:-}"; shift || :
TR=""; STEP=""
while [ $# -gt 0 ]; do case "$1" in --test-root) TR="$2"; shift 2;; --step) STEP="$2"; shift 2;; *) echo "unknown argument $1" >&2; exit 2;; esac; done
[ -n "$TR" ] && [ -f "$TR/results/run.meta" ] || { echo "kit-fix: --test-root <dir of an earlier run> is required" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${KIT_UPSTREAM:=https://github.com/mdurana/agents-v0-kit.git}" "${KIT_FIX_COMMIT:=0}" "${KIT_FIX_PUSH:=0}" "${KIT_FIX_VALIDATE:=auto}"
: "${KIT_FIXES_DOC:=refs/kit-fixes.md}" "${MAX_FIX_ATTEMPTS_PER_STEP:=2}" "${MAX_FIX_ATTEMPTS_TOTAL:=5}"
FX="$TR/kitfix"; D="$FX/agents-v0-kit"; CUR="$FX/current.env"; LOG="$TR/results/kit-fixes.tsv"
mkdir -p "$FX"
ts(){ TZ=Asia/Manila date '+%Y-%m-%d %H:%M'; }
say(){ printf '[%s Asia/Manila] kit-fix %s\n' "$(ts)" "$*"; }
sha256_cmd(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
tree_now(){ local ix; ix="$(mktemp)"; rm -f "$ix"; GIT_INDEX_FILE="$ix" git -C "$D" read-tree HEAD && GIT_INDEX_FILE="$ix" git -C "$D" add -A &&
            GIT_INDEX_FILE="$ix" git -C "$D" write-tree; rm -f "$ix"; }
BASE="$(grep -m1 '^kit_sha=' "$TR/results/run.meta" | cut -d= -f2)"
[ -n "$BASE" ] || { echo "kit-fix: no kit_sha in $TR/results/run.meta (step 2 never checked out the kit)" >&2; exit 2; }
BASE_REF="$(grep -m1 '^kit_ref=' "$TR/results/run.meta" | cut -d= -f2)"

case "$cmd" in
start)
  case "$STEP" in [2-8]) ;; *) echo "kit-fix start: --step must be 2..8 (steps 0 and 1 test the box, not the kit)" >&2; exit 2;; esac
  n_step=$(awk -F'\t' -v s="$STEP" '$3==s' "$LOG" 2>/dev/null | wc -l | tr -d ' '); n_all=$(cat "$LOG" 2>/dev/null | grep -c .)
  [ "$n_step" -lt "$MAX_FIX_ATTEMPTS_PER_STEP" ] || { say "FIX-LIMIT step $STEP already has $n_step fixes (MAX_FIX_ATTEMPTS_PER_STEP=$MAX_FIX_ATTEMPTS_PER_STEP)"; exit 3; }
  [ "$n_all" -lt "$MAX_FIX_ATTEMPTS_TOTAL" ] || { say "FIX-LIMIT $n_all fixes in this run (MAX_FIX_ATTEMPTS_TOTAL=$MAX_FIX_ATTEMPTS_TOTAL)"; exit 3; }
  [ ! -f "$CUR" ] || { . "$CUR"; [ -f "$FX/$FIX_ID.done" ] || { echo "kit-fix: $FIX_ID is still open; run check and finish first" >&2; exit 2; }; }
  if [ ! -d "$D/.git" ]; then git clone -q "$KIT_UPSTREAM" "$D" || exit 2; fi
  git -C "$D" cat-file -e "$BASE^{commit}" 2>/dev/null || git -C "$D" fetch -q origin "$BASE" || { echo "kit-fix: base commit $BASE not found upstream" >&2; exit 2; }
  day="$(TZ=Asia/Manila date +%Y%m%d)"; BR="kitfix-$day-step$STEP"; k=$(( n_step + 1 )); ID="$BR-a$k"
  PREV_PATCH="$(awk -F'\t' 'END{print $8}' "$LOG" 2>/dev/null)"; PREV_BR="$(awk -F'\t' 'END{print $4}' "$LOG" 2>/dev/null)"
  if git -C "$D" rev-parse -q --verify "refs/heads/$BR" >/dev/null; then git -C "$D" checkout -q "$BR"           # a later attempt for the same step
  elif [ -n "$PREV_BR" ] && [ "$KIT_FIX_COMMIT" = 1 ] && git -C "$D" rev-parse -q --verify "refs/heads/$PREV_BR" >/dev/null; then
    git -C "$D" checkout -q -b "$BR" "$PREV_BR"                                                                  # build on the earlier, committed fix
  else git -C "$D" checkout -q -b "$BR" "$BASE"; fi
  if [ -z "$(git -C "$D" status --porcelain)" ] && [ -n "$PREV_PATCH" ] && [ -f "$PREV_PATCH" ] && [ "$(git -C "$D" rev-parse HEAD)" = "$BASE" ]; then
    git -C "$D" apply "$PREV_PATCH" || { echo "kit-fix: the earlier fix patch $PREV_PATCH does not apply on $BASE" >&2; exit 2; }; fi   # earlier uncommitted fixes
  printf 'FIX_ID=%s\nFIX_BRANCH=%s\nFIX_BASE=%s\nFIX_BASE_REF=%s\nFIX_STEP=%s\nFIX_ATTEMPT=%s\nFIX_DIR=%s\nFIX_START_TREE=%s\n' \
    "$ID" "$BR" "$BASE" "$BASE_REF" "$STEP" "$k" "$D" "$(tree_now)" > "$CUR"
  say "START $ID on branch $BR from $BASE ($BASE_REF) in $D"
  echo "Next: edit files in $D. Put the text '$ID' in a plain-language comment in every changed file, and add a section"
  echo "'## $ID' with the lines Defect:, Evidence:, Fix:, How to check: to $D/$KIT_FIXES_DOC. Then: bash $HERE/kit-fix.sh check --test-root $TR";;
check)
  [ -f "$CUR" ] || { echo "kit-fix: no open fix (run start first)" >&2; exit 2; }; . "$CUR"; ok=1
  now="$(tree_now)"; changed="$(git -C "$D" diff --name-only "$FIX_START_TREE" "$now")"
  [ -n "$changed" ] || { say "CHECK FAIL nothing changed since start"; exit 1; }
  for f in $changed; do [ -f "$D/$f" ] || continue
    case "$f" in *.json|*.tgz|*.tar*|*.zip|*.png|*.jpg|*.jar|"$KIT_FIXES_DOC") continue;; esac
    grep -qF "$FIX_ID" "$D/$f" || { say "CHECK FAIL $f has no comment naming $FIX_ID"; ok=0; }
    case "$f" in *.sh) sh -n "$D/$f" 2>/dev/null || bash -n "$D/$f" || { say "CHECK FAIL $f syntax"; ok=0; };;
                 *.py) python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$D/$f" || { say "CHECK FAIL $f syntax"; ok=0; };; esac
  done
  doc="$D/$KIT_FIXES_DOC"
  if [ -f "$doc" ] && grep -q "^## $FIX_ID\$" "$doc"; then
    sec="$(awk -v h="## $FIX_ID" '$0==h{on=1; next} on && /^## /{exit} on' "$doc")"
    for fld in 'Defect:' 'Evidence:' 'Fix:' 'How to check:'; do printf '%s\n' "$sec" | grep -q "^$fld\|^- $fld\|^\*\*$fld" || { say "CHECK FAIL $KIT_FIXES_DOC section $FIX_ID lacks '$fld'"; ok=0; }; done
  else say "CHECK FAIL $KIT_FIXES_DOC has no section '## $FIX_ID'"; ok=0; fi
  mode="$KIT_FIX_VALIDATE"
  if [ "$mode" != quick ]; then jv="$("${JAVA_HOME:-/nonexistent}/bin/java" -version 2>&1 | head -1)"
    case "$jv" in *'"21'*) mode=full;; *) [ "$mode" = full ] && { say "CHECK FAIL KIT_FIX_VALIDATE=full needs JDK 21 in JAVA_HOME (found: ${jv:-none})"; ok=0; }; mode=quick;; esac; fi
  vlog="$FX/$FIX_ID.validate-$mode.log"
  if [ "$mode" = full ]; then (cd "$D" && sh scripts/validate-kit.sh) > "$vlog" 2>&1
  else (cd "$D" && KIT_SKIP_APP_TEMPLATE_TEST=1 sh scripts/validate-kit.sh) > "$vlog" 2>&1; fi    # validate-kit has no --quick flag
  grep -q '^validate-kit: OK' "$vlog" || { say "CHECK FAIL validate-kit ($mode) did not print 'validate-kit: OK' — see $vlog"; ok=0; }
  [ "$ok" = 1 ] || exit 1
  printf '%s\t%s\n' "$now" "$mode" > "$FX/$FIX_ID.checked"; say "CHECK OK $FIX_ID validate=$mode files: $(echo $changed)";;
finish)
  [ -f "$CUR" ] || { echo "kit-fix: no open fix" >&2; exit 2; }; . "$CUR"
  now="$(tree_now)"; [ -f "$FX/$FIX_ID.checked" ] && [ "$(cut -f1 "$FX/$FIX_ID.checked")" = "$now" ] || { echo "kit-fix: files changed after the last passing check; run check again" >&2; exit 2; }
  mode="$(cut -f2 "$FX/$FIX_ID.checked")"
  ix="$(mktemp)"; rm -f "$ix"; P="$FX/$FIX_ID.patch"
  GIT_INDEX_FILE="$ix" git -C "$D" read-tree HEAD && GIT_INDEX_FILE="$ix" git -C "$D" add -A && GIT_INDEX_FILE="$ix" git -C "$D" diff --cached --binary "$FIX_BASE" > "$P"; rm -f "$ix"
  git -C "$D" diff --stat "$FIX_BASE" > "$FX/$FIX_ID.diffstat" 2>/dev/null || :
  [ -s "$P" ] || { echo "kit-fix: empty patch" >&2; exit 2; }
  committed=no; pushed=no
  if [ "$KIT_FIX_COMMIT" = 1 ]; then
    subj="$(awk -v h="## $FIX_ID" '$0==h{on=1; next} on && /^## /{exit} on && /Defect:/{sub(/.*Defect:[[:space:]]*/,""); print; exit}' "$D/$KIT_FIXES_DOC" | cut -c1-60)"
    git -C "$D" add -A && git -C "$D" commit -q -m "fix(kit): $FIX_ID ${subj}" -m "Found by the agents-v0 portal end-to-end test, step $FIX_STEP. Base: $FIX_BASE ($FIX_BASE_REF). See $KIT_FIXES_DOC." && committed="$(git -C "$D" rev-parse --short=12 HEAD)"
  fi
  if [ "$KIT_FIX_PUSH" = 1 ]; then
    [ "$committed" != no ] || { echo "kit-fix: KIT_FIX_PUSH=1 needs KIT_FIX_COMMIT=1; nothing pushed" >&2; exit 2; }
    case "$FIX_BRANCH" in kitfix-*) ;; *) echo "kit-fix: refusing to push a non-kitfix branch" >&2; exit 2;; esac
    [ "$FIX_BRANCH" != "$FIX_BASE_REF" ] || { echo "kit-fix: refusing to push to the base branch" >&2; exit 2; }
    rsha="$(git -C "$D" ls-remote --heads origin "$FIX_BRANCH" | cut -f1)"
    if [ -n "$rsha" ]; then git -C "$D" fetch -q origin "$FIX_BRANCH" && git -C "$D" merge-base --is-ancestor "$rsha" HEAD ||
      { echo "kit-fix: origin/$FIX_BRANCH has commits that are not in the local branch; refusing (no force-push)" >&2; exit 2; }; fi
    git -C "$D" push -q origin "HEAD:refs/heads/$FIX_BRANCH" && pushed="origin/$FIX_BRANCH"     # no --force, no PR, no merge
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(ts)" "$FIX_ID" "$FIX_STEP" "$FIX_BRANCH" "$FIX_BASE" "$mode" "$committed/$pushed" "$P" "$(sha256_cmd "$P" | cut -c1-12)" >> "$LOG"
  : > "$FX/$FIX_ID.done"
  say "FINISH $FIX_ID patch=$P commit=$committed push=$pushed"
  echo "Diff summary:"; cat "$FX/$FIX_ID.diffstat"
  echo "Resume with:"
  if [ "$pushed" != no ]; then echo "  KIT_FIX_URL=$KIT_UPSTREAM KIT_FIX_REF=$FIX_BRANCH bash $HERE/run-plan.sh --resume-from auto --test-root $TR --reason kit-fix"
  else echo "  KIT_FIX_PATCH=$P KIT_FIX_BASE=$FIX_BASE bash $HERE/run-plan.sh --resume-from auto --test-root $TR --reason kit-fix"; fi;;
*) sed -n '2,13p' "$0"; exit 2;;
esac
