#!/bin/sh
# bootstrap-greenfield.sh — install agents-v0 into a new repo and seed the P0 milestone manifest.
#
# Usage:
#   bootstrap-greenfield.sh [--profile service|ui|app] [--pack <id>] [--scaffold-app] <target-repo>
#
# Prerequisite: <target-repo> is a new, empty git repo of its own: `git init` output only, no commit, no
# other file or folder (design rev 6 "Greenfield record": 5A, N2A, N9A). Bootstrap never runs `git init`.
# It refuses, before writing anything, a folder with no .git (N67, N78: hint `git init`), a folder inside a
# parent repo (N79), a folder holding anything beside .git (N65), a repo with a commit (N66), a used gate
# ledger, and a missing git identity. It then installs the kit and makes the repo's one root commit by exact
# path: everything it wrote plus .agents-v0/greenfield-record.json, scanned for secrets, its message ending
# with the lines=0 ledger trailer from gate-checks.sh greenfield_trailer; greenfield_record_ok must pass.
# --scaffold-app extracts
# templates/app/p0-platform-skeleton.tar.gz when --pack is omitted or is java.
# Any other --pack skips that archive and points at that pack's scaffold-service skill.
# Guide in the kit repo:
# templates/docs/agents-v0/greenfield-onboarding.md (installed as
# docs/agents-v0/greenfield-onboarding.md).
# --profile fills docs/agents-v0/project-profile.md Layout and verify commands when those
# cells are still placeholders. Omit it to infer service, ui, or app from the tree.
set -eu
# Bootstrap works on <target-repo> only: no git variable from the caller may point it at another repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY 2>/dev/null || true

KIT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE=""
PACK=""
SCAFFOLD_APP=0
TARGET=""

usage() {
  printf 'usage: %s [--profile service|ui|app] [--pack <id>] [--scaffold-app] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      [ $# -ge 2 ] || usage
      PROFILE="$2"
      shift 2
      ;;
    --pack)
      [ $# -ge 2 ] || usage
      PACK="$2"
      shift 2
      ;;
    --scaffold-app)
      SCAFFOLD_APP=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

case "$PROFILE" in
  ''|service|ui|app) ;;
  *)
    printf 'error: unknown profile: %s\n' "$PROFILE" >&2
    usage
    ;;
esac

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || {
  printf 'error: target not found: %s (create/scaffold the repo first)\n' "$TARGET" >&2
  exit 1
}

TARGET_ABS="$(cd "$TARGET" && pwd -P)"

# ---- entry check (N9A, N2A): refuse before anything is written -----------------------------------------
# E34 allow-list: the tool folders Cursor or agy create when they open an empty folder. Empty until Iruka's
# open-empty-folder test records them (with the tool versions); until then any entry beside .git is refused.
E34_ALLOW=""
BROWNFIELD_HINT="Greenfield bootstrap is for a new repo only: create the repo empty (git init, or a hosted repo with no README, .gitignore or license), or use brownfield onboarding (docs/agents-v0/brownfield-onboarding.md, then /v0-onboard)."
refuse_entry() {
  printf 'REFUSED bootstrap-greenfield: %s\n' "$1" >&2
  printf 'Nothing was written.\n' >&2
  exit 1
}
G() { git -C "$TARGET_ABS" "$@"; }

entry_check() {
  entries=""
  for e in "$TARGET_ABS"/* "$TARGET_ABS"/.[!.]* "$TARGET_ABS"/..?*; do
    { [ -e "$e" ] || [ -L "$e" ]; } || continue
    name="${e##*/}"
    [ "$name" = .git ] && continue
    case " $E34_ALLOW " in *" $name "*) continue ;; esac
    if [ -d "$e" ] && [ ! -L "$e" ]; then name="$name/"; fi
    entries="${entries:+$entries, }$name"
  done
  if [ ! -e "$TARGET_ABS/.git" ] && [ ! -L "$TARGET_ABS/.git" ]; then
    top="$(G rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ]; then
      # N79 (Sasuke): the root commit and the record would land in the parent repo.
      refuse_entry "$TARGET_ABS has no .git of its own and sits inside the git repo $top, so the root commit and the greenfield record would land in that repo (N79). Create the new repo in a folder outside $top, then rerun."
    fi
    # N67 (empty folder), N78 (files, no .git): bootstrap never runs git init (N9A).
    if [ -n "$entries" ]; then
      refuse_entry "$TARGET_ABS has no .git (N78). Bootstrap never runs git init. It also holds $entries, and greenfield bootstrap needs an empty folder. $BROWNFIELD_HINT For a new repo: empty the folder (or pick a new one), run git init in it ( git -C $TARGET_ABS init ), then rerun."
    fi
    refuse_entry "$TARGET_ABS has no .git (N67). Bootstrap never runs git init: run git init in the folder ( git -C $TARGET_ABS init ), then rerun."
  fi
  top="$(G rev-parse --show-toplevel 2>/dev/null || true)"
  top_p="$( [ -n "$top" ] && cd "$top" 2>/dev/null && pwd -P || true)"
  if [ "$top_p" != "$TARGET_ABS" ]; then
    refuse_entry "$TARGET_ABS/.git does not make $TARGET_ABS a git work tree of its own (git reports the top level as '${top:-none}'; N79). Run git init in the folder, or create the new repo in a folder outside any other repo, then rerun."
  fi
  if G rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1 || [ -n "$(G rev-list -n 1 --all 2>/dev/null)" ]; then
    refuse_entry "the repo $TARGET_ABS already has a commit (N66); the greenfield record belongs in the repo's only root commit. $BROWNFIELD_HINT"
  fi
  if [ -n "$(G for-each-ref --count=1 2>/dev/null)" ]; then
    refuse_entry "the repo $TARGET_ABS already has refs ($(G for-each-ref --count=1 --format='%(refname)')); it is not a new repo (N66). $BROWNFIELD_HINT"
  fi
  if [ -n "$entries" ]; then
    refuse_entry "$TARGET_ABS is not empty (N65): it holds $entries beside .git. $BROWNFIELD_HINT"
  fi
  if [ -n "$(G ls-files 2>/dev/null | head -n 1)" ]; then
    refuse_entry "the index of $TARGET_ABS already holds staged paths (N65); a new repo has an empty index. $BROWNFIELD_HINT"
  fi
  gcd="$(G rev-parse --git-common-dir 2>/dev/null)" || refuse_entry "git cannot read the repo in $TARGET_ABS"
  case "$gcd" in /*) ;; *) gcd="$TARGET_ABS/$gcd" ;; esac
  led="$gcd/agents-v0/gate-ledger"
  if [ -e "$led" ] || [ -L "$led" ]; then
    { [ -f "$led" ] && [ ! -L "$led" ] && [ ! -s "$led" ]; } || refuse_entry "the gate ledger $led is not an empty regular file; a new repo starts with an empty ledger. $BROWNFIELD_HINT"
  fi
  if [ -e "$gcd/agents-v0/untrusted-root" ] || [ -L "$gcd/agents-v0/untrusted-root" ]; then
    refuse_entry "$gcd/agents-v0/untrusted-root exists: an earlier bootstrap marked a root commit in this repo as not trusted. $BROWNFIELD_HINT"
  fi
  # The root commit is made by this script, so a missing identity must stop it before the install.
  if ! G var GIT_AUTHOR_IDENT >/dev/null 2>&1 || ! G var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    refuse_entry "git has no user name and email for $TARGET_ABS, so the root commit cannot be made. Set them (git -C $TARGET_ABS config user.name \"Your Name\" and git -C $TARGET_ABS config user.email you@example.com), then rerun."
  fi
  command -v python3 >/dev/null 2>&1 || refuse_entry "python3 is missing; the install, the secret scan and the record check need it."
}
entry_check

if [ -n "$PACK" ]; then
  "$KIT/scripts/install.sh" --with-starters --pack "$PACK" "$TARGET_ABS"
else
  "$KIT/scripts/install.sh" --with-starters "$TARGET_ABS"
fi
# The root commit carries the kit (H7: kit files plus the record and nothing else): the paths the install
# wrote, listed now, before --scaffold-app adds the app. The later steps below fill some of these files.
# Bootstrap's own work files (these path lists, the commit message) live in .git/agents-v0-bootstrap/: git
# never stages anything under .git, each run overwrites them, and bootstrap deletes none of them.
GF_WORK="$(git -C "$TARGET_ABS" rev-parse --path-format=absolute --git-path agents-v0-bootstrap)"
mkdir -p "$GF_WORK" || { printf 'error: cannot create %s\n' "$GF_WORK" >&2; exit 1; }
GF_KIT_PATHS="$GF_WORK/kit-paths"
git -C "$TARGET_ABS" ls-files -z --others --exclude-standard > "$GF_KIT_PATHS" || { printf 'error: cannot list the paths the install wrote\n' >&2; exit 1; }

if [ "$SCAFFOLD_APP" = 1 ]; then
  if [ -z "$PACK" ] || [ "$PACK" = "java" ]; then
    scaffold_profile="$PROFILE"
    case "$scaffold_profile" in
      service|ui|app) ;;
      *) scaffold_profile=app ;;
    esac
    sh "$KIT/scripts/scaffold-app-template.sh" --profile "$scaffold_profile" "$TARGET_ABS"
  else
    printf 'Pack %s does not use the Java archive. Follow core/%s/skills/scaffold-service/SKILL.md for P0-A.\n' "$PACK" "$PACK"
  fi
fi

mkdir -p "$TARGET_ABS/docs/agents-v0/milestones"
for m in plan p0-platform-skeleton p1-contracts-and-data-models p2-mvp-core-features p3-feature-expansion p4-hardening p5-release-readiness; do
  dest="$TARGET_ABS/docs/agents-v0/milestones/$m.md"
  if [ ! -f "$dest" ]; then
    cp "$KIT/templates/docs/agents-v0/milestones/$m.md" "$dest"
    printf 'Seeded %s\n' "$dest"
  fi
done

load_markers() {
  MARKERS=""
  if [ ! -f "$TARGET_ABS/.agents-v0/scripts/packlib.py" ]; then
    return 0
  fi
  MARKERS="$(PACKLIB_DIR="$TARGET_ABS/.agents-v0/scripts" python3 - "$TARGET_ABS" <<'PY'
import os
import sys
os.chdir(sys.argv[1])
sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib
print("\n".join(packlib.marker_roots(".", 4)))
PY
)"
}

has_backend_at() {
  rel="$1"
  case "$rel" in
    "$TARGET_ABS") rel="." ;;
    "$TARGET_ABS"/*) rel="${rel#"$TARGET_ABS"/}" ;;
  esac
  rel="${rel%/}"
  [ -n "${MARKERS:-}" ] || return 1
  printf '%s\n' "$MARKERS" | grep -Fxq -- "$rel"
}

apply_root() {
  cmd="$1"
  root="${2%/}"
  body="$(printf '%s\n' "$cmd" | sed -E 's/^cd[[:space:]]+[^[:space:]]+[[:space:]]+&&[[:space:]]+//')"
  printf 'cd %s && %s' "$root" "$body"
}

CLI_PACK="$PACK"

detect_pack() {
  if [ -n "$PACK" ]; then
    return 0
  fi
  if [ "$SCAFFOLD_APP" = 1 ]; then
    PACK="java"
    return 0
  fi
  if [ ! -f "$TARGET_ABS/.agents-v0/scripts/packlib.py" ]; then
    return 0
  fi
  PACK="$(PACKLIB_DIR="$TARGET_ABS/.agents-v0/scripts" python3 - "$TARGET_ABS" <<'PY'
import os
import sys
os.chdir(sys.argv[1])
sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib
found = packlib.detect(".")
if len(found) == 1:
    print(sorted(found)[0])
PY
)"
}

load_pack_commands() {
  PACK_VERIFY=""
  PACK_VERIFY_FAST=""
  UI_VERIFY=""
  UI_VERIFY_FAST=""
  if [ -z "$PACK" ] || [ ! -f "$KIT/core/$PACK/pack.json" ]; then
    return 0
  fi
  eval "$(python3 - "$KIT/core/$PACK/pack.json" "$KIT/core/ui" <<'PY'
import json
import os
import sys
pack = json.load(open(sys.argv[1], encoding="utf-8"))
ui = {}
ui_id = pack.get("ui") if isinstance(pack.get("ui"), str) else ""
ui_path = os.path.join(sys.argv[2], ui_id, "pack.json") if ui_id else ""
if ui_path and os.path.isfile(ui_path):
    ui = json.load(open(ui_path, encoding="utf-8"))

def quote(value):
    return "'" + str(value).replace("'", "'\"'\"'") + "'"

print("PACK_VERIFY=" + quote(pack.get("verify") or ""))
print("PACK_VERIFY_FAST=" + quote(pack.get("verifyFast") or ""))
print("UI_VERIFY=" + quote(ui.get("verify") or ""))
print("UI_VERIFY_FAST=" + quote(ui.get("verifyFast") or ""))
PY
)"
}

backend_verify_for() {
  root="$1"
  if [ -n "${PACK_VERIFY:-}" ]; then
    apply_root "$PACK_VERIFY" "$root"
  else
    printf ''
  fi
}

backend_fast_for() {
  root="$1"
  if [ -n "${PACK_VERIFY_FAST:-}" ]; then
    apply_root "$PACK_VERIFY_FAST" "$root"
  else
    printf ''
  fi
}

frontend_verify_for() {
  root="$1"
  if [ -n "${UI_VERIFY:-}" ]; then
    apply_root "$UI_VERIFY" "$root"
  else
    printf 'cd %s && npm run verify' "${root%/}"
  fi
}

frontend_fast_for() {
  root="$1"
  if [ -n "${UI_VERIFY_FAST:-}" ]; then
    apply_root "$UI_VERIFY_FAST" "$root"
  else
    printf 'cd %s && npm test' "${root%/}"
  fi
}

infer_profile() {
  be=0
  fe=0
  bff=0
  if has_backend_at "$TARGET_ABS/app/backend" || has_backend_at "$TARGET_ABS/backend"; then be=1; fi
  if [ -f "$TARGET_ABS/app/frontend/package.json" ] || [ -f "$TARGET_ABS/frontend/package.json" ]; then fe=1; fi
  if has_backend_at "$TARGET_ABS/app/bff" || has_backend_at "$TARGET_ABS/bff"; then bff=1; fi
  if [ "$be" = 1 ] && [ "$fe" = 1 ] && [ "$bff" = 1 ]; then
    printf 'app-bff\n'
  elif [ "$be" = 1 ] && [ "$fe" = 1 ]; then
    printf 'app\n'
  elif [ "$be" = 1 ] && [ "$bff" = 1 ]; then
    printf 'service-bff\n'
  elif [ "$be" = 1 ]; then
    printf 'service\n'
  elif [ "$fe" = 1 ]; then
    printf 'ui\n'
  elif [ "$bff" = 1 ]; then
    printf 'bff\n'
  else
    printf '\n'
  fi
}

layout_cell() {
  label="$1"
  file="$2"
  [ -f "$file" ] || return 0
  awk -F'|' -v label="$label" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      n = 0
      for (i = 1; i <= NF; i++) {
        c = trim($i)
        if (c != "") { n++; cell[n] = c }
      }
      if (n == 2 && cell[1] == label) { print cell[2]; exit }
    }
  ' "$file"
}

# Prefer an existing app/<name> module, else the repo-root module, else app/<name>.
module_root() {
  name="$1"
  kind="$2"
  if [ "$kind" = ui ]; then
    if [ -f "$TARGET_ABS/app/$name/package.json" ]; then
      printf 'app/%s/' "$name"
      return 0
    fi
    if [ -f "$TARGET_ABS/$name/package.json" ]; then
      printf '%s/' "$name"
      return 0
    fi
  else
    if has_backend_at "$TARGET_ABS/app/$name"; then
      printf 'app/%s/' "$name"
      return 0
    fi
    if has_backend_at "$TARGET_ABS/$name"; then
      printf '%s/' "$name"
      return 0
    fi
  fi
  printf 'app/%s/' "$name"
}

fill_layout() {
  chosen="$1"
  file="$TARGET_ABS/docs/agents-v0/project-profile.md"
  [ -f "$file" ] || {
    printf 'WARN: %s missing — Layout profile not recorded\n' "$file" >&2
    return 0
  }
  current="$(layout_cell Profile "$file" || true)"
  case "$current" in
    service|ui|app)
      printf 'Layout profile already set to %s (left unchanged)\n' "$current"
      return 0
      ;;
  esac
  case "$current" in
    *'<!--'*) ;;
    *)
      printf 'WARN: Layout Profile cell is not a placeholder — left unchanged\n' >&2
      return 0
      ;;
  esac
  if [ -z "$chosen" ]; then
    if has_backend_at "$TARGET_ABS" || [ -f "$TARGET_ABS/package.json" ]; then
      printf 'Source at the repo root is not a greenfield layout. Move it under app/backend/, app/bff/, or app/frontend/, then re-run with --profile service|ui|app\n'
    else
      printf 'Layout profile not inferred. Re-run with --profile service|ui|app\n'
    fi
    return 0
  fi
  case "$chosen" in
    service)
      profile_name='service'
      backend_root="$(module_root backend jvm)"
      frontend_root='n/a'
      bff_root='n/a'
      backend_verify="$(backend_verify_for "$backend_root")"
      backend_fast="$(backend_fast_for "$backend_root")"
      frontend_verify='n/a'
      frontend_fast='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    service-bff)
      profile_name='service'
      backend_root="$(module_root backend jvm)"
      frontend_root='n/a'
      bff_root="$(module_root bff jvm)"
      backend_verify="$(backend_verify_for "$backend_root")"
      backend_fast="$(backend_fast_for "$backend_root")"
      frontend_verify='n/a'
      frontend_fast='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    bff)
      profile_name='service'
      backend_root='n/a'
      frontend_root='n/a'
      bff_root="$(module_root bff jvm)"
      backend_verify="$(backend_verify_for "$bff_root")"
      backend_fast="$(backend_fast_for "$bff_root")"
      frontend_verify='n/a'
      frontend_fast='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    ui)
      profile_name='ui'
      backend_root='n/a'
      frontend_root="$(module_root frontend ui)"
      bff_root='n/a'
      backend_verify='n/a'
      backend_fast='n/a'
      frontend_verify="$(frontend_verify_for "$frontend_root")"
      frontend_fast="$(frontend_fast_for "$frontend_root")"
      openapi='n/a'
      ;;
    app|app-bff)
      profile_name='app'
      backend_root="$(module_root backend jvm)"
      frontend_root="$(module_root frontend ui)"
      if [ "$chosen" = app-bff ]; then bff_root="$(module_root bff jvm)"; else bff_root='n/a'; fi
      backend_verify="$(backend_verify_for "$backend_root")"
      backend_fast="$(backend_fast_for "$backend_root")"
      frontend_verify="$(frontend_verify_for "$frontend_root")"
      frontend_fast="$(frontend_fast_for "$frontend_root")"
      openapi='openapi/api-v1.yaml'
      ;;
  esac
  tmp="$(mktemp)"
  awk -F'|' \
    -v profile="$profile_name" \
    -v backend_root="$backend_root" \
    -v frontend_root="$frontend_root" \
    -v bff_root="$bff_root" \
    -v backend_verify="$backend_verify" \
    -v backend_fast="$backend_fast" \
    -v frontend_verify="$frontend_verify" \
    -v frontend_fast="$frontend_fast" \
    -v openapi="$openapi" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      n = 0
      for (i = 1; i <= NF; i++) {
        c = trim($i)
        if (c != "") { n++; a[n] = c }
      }
      if (n == 2 && a[2] ~ /<!--/) {
        repl = ""
        if (a[1] == "Profile") repl = profile
        else if (a[1] == "Backend root") repl = backend_root
        else if (a[1] == "Frontend root") repl = frontend_root
        else if (a[1] == "BFF root") repl = bff_root
        else if (a[1] == "OpenAPI") repl = openapi
        else if (a[1] == "Backend verify") repl = backend_verify
        else if (a[1] == "Backend verify (fast, no OWASP)") repl = backend_fast
        else if (a[1] == "Frontend verify") repl = frontend_verify
        else if (a[1] == "Frontend verify (fast)") repl = frontend_fast
        if (repl != "") {
          printf "| %s | %s |\n", a[1], repl
          next
        }
      }
      if ($0 ~ /Approved OpenAPI:/ && $0 ~ /<!--/) {
        sub(/<!--[^>]*-->/, openapi)
      }
      print
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  printf 'Recorded layout profile %s in %s\n' "$chosen" "$file"
}

load_markers
detect_pack
load_pack_commands
if [ -z "$PROFILE" ]; then
  PROFILE="$(infer_profile)"
fi
fill_layout "$PROFILE"
if [ -n "$PACK" ] && [ -f "$TARGET_ABS/.agents-v0/scripts/activate-stack-pack.sh" ]; then
  (cd "$TARGET_ABS" && sh .agents-v0/scripts/activate-stack-pack.sh "$PACK" >/dev/null)
fi

# ---- the greenfield root commit (5A, N2A, N3A; gate-checks.sh greenfield_trailer and greenfield_record_ok) ---
GF_RECORD=".agents-v0/greenfield-record.json"
# The untrusted-root marker: written when a root commit exists but failed a check, in .git/agents-v0/ (the
# folder the hooks protect, beside the gate ledger). The folder is created only if missing; the marker is
# written with noclobber, so an existing marker and every other file there are left as they are.
mark_untrusted() {
  m_dir="$(git -C "$TARGET_ABS" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/agents-v0"
  UNTRUSTED_MARKER="$m_dir/untrusted-root"
  [ -d "$m_dir" ] || mkdir -p "$m_dir" 2>/dev/null || { printf 'error: cannot create %s; the untrusted-root marker was not written\n' "$m_dir" >&2; return 0; }
  if [ -e "$UNTRUSTED_MARKER" ] || [ -L "$UNTRUSTED_MARKER" ]; then
    printf 'note: %s already exists; left as it is\n' "$UNTRUSTED_MARKER" >&2; return 0
  fi
  ( set -C; printf 'rootCommit=%s\nreason=%s\nmarkedAt=%s\n' "$(git -C "$TARGET_ABS" rev-parse HEAD 2>/dev/null || echo unknown)" "$1" \
      "$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')" > "$UNTRUSTED_MARKER" ) 2>/dev/null \
    || printf 'error: cannot write %s\n' "$UNTRUSTED_MARKER" >&2
}
stop_commit() {
  printf 'error: %s\n' "$1" >&2
  # Nothing stays staged in a repo with no commit (the record and the kit files stay in the work tree).
  git -C "$TARGET_ABS" rev-parse -q --verify HEAD >/dev/null 2>&1 || git -C "$TARGET_ABS" read-tree --empty 2>/dev/null || true
  if git -C "$TARGET_ABS" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    mark_untrusted "post-commit check failed: $(printf '%s' "$1" | tr '\n' ' ' | cut -c1-300)"
    printf 'The kit is installed in %s and a root commit exists, but it failed the check above: it is not a trusted greenfield root commit (marked in %s). Do not build on it; start again in a new empty repo (git init) and rerun.\n' "$TARGET_ABS" "$UNTRUSTED_MARKER" >&2
  else
    printf 'The kit is installed in %s, but the greenfield root commit was not completed. Fix the cause; to start again, use a new empty repo (git init) and rerun.\n' "$TARGET_ABS" >&2
  fi
  exit 1
}
# A commit hook (pre-commit, prepare-commit-msg, commit-msg) can stage or change files after the secret scan:
# the committed tree must be the tree that was scanned. Bootstrap never rewrites history or deletes the commit.
refuse_hook_tree() {
  mark_untrusted "commit hooks changed the tree: scanned $2, committed $3; paths: $4"
  printf 'REFUSED bootstrap-greenfield: the commit hooks changed the tree of the root commit %s: git committed tree %s, but the secret scan and the staged-path check read tree %s. Paths the hooks added, changed or removed: %s\n' "$1" "$3" "$2" "$4" >&2
  printf 'The root commit %s is not trusted: it holds content the secret scan never read and is not the kit plus the greenfield record (H7). greenfield_record_ok cannot see this, so do not rely on it for this repo; bootstrap marked it in %s. Bootstrap left the commit in place (it never rewrites history) and stopped: do not push or onboard this repo. Move this repo aside, create a new empty repo (git init), turn off for it the hooks that stage files at commit time (core.hooksPath, .git/hooks/pre-commit, prepare-commit-msg, commit-msg), then rerun bootstrap.\n' "$1" "$UNTRUSTED_MARKER" >&2
  exit 1
}
kit_sha_of() {
  # The same form as install.sh writes into .agents-kit-version: 12 hex, -dirty when the kit has changes.
  ks="$(git -C "$KIT" rev-parse --short=12 HEAD 2>/dev/null || true)"
  case "$ks" in
    ''|*[!0-9a-f]*) printf 'unknown'; return 0 ;;
  esac
  [ -z "$(git -C "$KIT" status --porcelain 2>/dev/null | head -n 1)" ] || ks="$ks-dirty"
  printf '%s' "$ks"
}
greenfield_root_commit() {
  cd "$TARGET_ABS"
  gc=".agents-v0/scripts/gate-checks.sh"
  [ -f "$gc" ] || stop_commit "$gc is missing after the install"
  gt_rc=0; trailer="$(sh "$gc" greenfield_trailer)" || gt_rc=$?
  [ "$gt_rc" = 0 ] || stop_commit "gate-checks.sh greenfield_trailer refused (exit $gt_rc): $trailer"
  case "$trailer" in
    *'
'*|'') stop_commit "gate-checks.sh greenfield_trailer did not print one trailer line" ;;
    'Agents-V0-Ledger: lines=0 sha256='*) ;;
    *) stop_commit "gate-checks.sh greenfield_trailer printed an unexpected trailer: $trailer" ;;
  esac
  at="$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')"
  ks="$(kit_sha_of)"
  [ ! -e "$GF_RECORD" ] && [ ! -L "$GF_RECORD" ] || stop_commit "$GF_RECORD already exists; the install must not write it"
  printf '{"kind": "greenfield", "bootstrapAt": "%s", "kitSha": "%s"}\n' "$at" "$ks" > "$GF_RECORD" || stop_commit "cannot write $GF_RECORD"
  chmod 644 "$GF_RECORD"
  # Add by exact path (JO-8 chain; never git add -A): the paths the install wrote, then the record.
  lst="$GF_WORK/commit-paths"
  { cat "$GF_KIT_PATHS" && printf '%s\0' "$GF_RECORD"; } | LC_ALL=C sort -z -u > "$lst" || stop_commit "cannot write the path list $lst"
  [ -s "$GF_KIT_PATHS" ] || stop_commit "the install wrote no path to commit"
  git --literal-pathspecs add --pathspec-from-file="$lst" --pathspec-file-nul || stop_commit "git add of the bootstrap paths failed"
  # Staged-path check: the index holds exactly those paths, the record among them.
  git ls-files -z | LC_ALL=C sort -z | cmp -s - "$lst" || stop_commit "the index does not hold exactly the paths the install wrote plus $GF_RECORD"
  git ls-files --error-unmatch -- "$GF_RECORD" >/dev/null 2>&1 || stop_commit "$GF_RECORD is not staged"
  msg="$GF_WORK/commit-msg.txt"
  printf 'agents-v0: greenfield bootstrap (kit %s)\n\n%s\n' "$ks" "$trailer" > "$msg" || stop_commit "cannot write the commit message file $msg"
  [ -f .agents-v0/scripts/secret_scan.py ] || stop_commit ".agents-v0/scripts/secret_scan.py is missing after the install"
  sc_rc=0; python3 .agents-v0/scripts/secret_scan.py --staged --root "$TARGET_ABS" --message-file "$msg" || sc_rc=$?
  [ "$sc_rc" = 0 ] || stop_commit "secret_scan.py exited $sc_rc (1: a hit, 2: it could not scan); nothing was committed"
  scanned_tree="$(git write-tree)" || stop_commit "git write-tree of the scanned index failed; nothing was committed"
  git commit -q -F "$msg" || stop_commit "git commit of the greenfield root commit failed"
  root="$(git rev-parse --short=12 HEAD)"
  committed_tree="$(git rev-parse 'HEAD^{tree}')" || stop_commit "cannot read the tree of the root commit $root"
  if [ "$committed_tree" != "$scanned_tree" ]; then
    changed="$(git diff-tree -r --no-renames --name-status "$scanned_tree" "$committed_tree" | head -n 20 | tr '\t' ' ' | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
    refuse_hook_tree "$root" "$scanned_tree" "$committed_tree" "${changed:-unknown}"
  fi
  # The trailer must be the message's last line, and the only Agents-V0-Ledger line (a commit-msg hook could add lines).
  body="$(git log -1 --format=%B)"
  [ "$(printf '%s\n' "$body" | sed '/^[[:space:]]*$/d' | tail -n 1)" = "$trailer" ] || stop_commit "the root commit's message does not end with $trailer (a commit-msg hook may have added lines)"
  [ "$(printf '%s\n' "$body" | grep -c '^Agents-V0-Ledger:')" = 1 ] || stop_commit "the root commit's message holds more than one Agents-V0-Ledger line"
  gr_rc=0; gr_out="$(sh "$gc" greenfield_record_ok)" || gr_rc=$?
  [ "$gr_rc" = 0 ] || stop_commit "gate-checks.sh greenfield_record_ok exited $gr_rc after the root commit: $gr_out"
  printf 'Greenfield root commit %s (%s); %s\n' "$(git rev-parse --short=12 HEAD)" "$trailer" "$gr_out"
  left="$(git ls-files --others --exclude-standard --directory | head -n 20 | tr '\n' ' ')"
  [ -z "$left" ] || printf 'Not in the root commit (the scaffolded app and what it changed; commit it with your first story): %s\n' "$left"
  [ -z "$(git diff --name-only | head -n 1)" ] || printf 'Changed after the install and not in the root commit: %s\n' "$(git diff --name-only | head -n 20 | tr '\n' ' ')"
}
greenfield_root_commit

printf '\nGreenfield bootstrap complete.\n'
if [ "$SCAFFOLD_APP" = 1 ] && [ -z "$CLI_PACK" ]; then
  printf 'No --pack was given. Extracted the java example archive templates/app/p0-platform-skeleton.tar.gz.\n'
  printf 'P0-A: prove AC-1–AC-4 with /v0-build (scaffold-service verifies; does not reinvent the skeleton).\n'
elif [ "$SCAFFOLD_APP" = 1 ] && [ "$CLI_PACK" = "java" ]; then
  printf 'Extracted the java example archive templates/app/p0-platform-skeleton.tar.gz.\n'
  printf 'P0-A: prove AC-1–AC-4 with /v0-build (scaffold-service verifies; does not reinvent the skeleton).\n'
elif [ "$SCAFFOLD_APP" = 1 ]; then
  printf 'P0-A: follow the %s scaffold-service skill. The Java archive was not extracted.\n' "$CLI_PACK"
else
  printf 'Next: add --scaffold-app on bootstrap, or scaffold externally, then harden with scaffold-service.\n'
  printf '      wire the reports named in pack.json; Pack java uses maven/. See docker/README.md\n'
fi
printf 'Then start P0-A with /v0-build or /v0-deliver. Guide: docs/agents-v0/greenfield-onboarding.md\n'
