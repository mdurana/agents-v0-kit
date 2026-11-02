#!/bin/sh
# guard-common.sh: the shared guard of the onboard redo (design: kit-eval/reviews/jiraiya-onboard-redo-design-20261102.md,
# "The split"). It is meant to be the only writer of workflow state (state file, approval record, secret scan, commit and
# tag, branch checks). Design line D1 builds only the base and the secret scan; the state writers, the commit and tag
# and the approval record come with later lines (D2 to D4, DA), which extend this file.
#
# Run:
#   sh .agents-v0/scripts/guard-common.sh scan-staged [--message-file FILE]
#        scan what is staged for the next commit (secret_scan.py --staged); run it right before `git commit`.
#   sh .agents-v0/scripts/guard-common.sh scan-push [<remote name>]  < pre-push input lines
#        scan every commit a push would send (secret_scan.py --commits); the pre-push hook runs it.
#   sh .agents-v0/scripts/guard-common.sh branch-check [<branch>]
#        print the current branch; refuse a detached HEAD, or a branch other than <branch> when given.
#   sh .agents-v0/scripts/guard-common.sh paths
#        print the repository root, the git common dir and the onboarding state file path.
# Use as a library (other guard scripts): GC_HERE=<dir> GUARD_COMMON_LIB=1 . "<dir>/guard-common.sh", then call the gc_* functions.
#
# Output: `OK <step>: <what passed>` (exit 0) or `REFUSED <step>: <reason>` (exit 1) on stdout; usage errors on
# stderr (exit 2). The scanner's own lines (HIT, ALLOWED, SECRET-SCAN ...) pass through; it never prints a secret.
# Every exit code but 0 is a stop (fail closed).
set -eu

# A library user sets GC_HERE to the scripts dir before sourcing; $0 is then the caller.
GC_HERE="${GC_HERE:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
GC_ZERO="0000000000000000000000000000000000000000"

gc_ok() { printf 'OK %s: %s\n' "$1" "$2"; return 0; }
gc_refuse() { printf 'REFUSED %s: %s\n' "$1" "$2"; exit 1; }
gc_die() { printf 'error: %s\n' "$1" >&2; exit 2; }

# --- base: repository root, git paths, state file paths ---------------------------------------------------------
# gc_root: the work tree root (exit 1 outside a work tree).
gc_root() { git rev-parse --show-toplevel 2>/dev/null; }
# gc_to_root <step>: cd to the work tree root or refuse <step>.
gc_to_root() {
  gc_r="$(gc_root)" || gc_refuse "$1" "not inside a git work tree"
  [ -n "$gc_r" ] || gc_refuse "$1" "not inside a git work tree"
  cd "$gc_r"
}
# gc_common_dir: the absolute git common dir (shared by every worktree of the repository).
gc_common_dir() {
  gc_cd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  (cd "$gc_cd" && pwd)
}
# gc_git_path <name>: a file in this worktree's git dir (git rev-parse --git-path).
gc_git_path() { git rev-parse --git-path "$1"; }
# gc_state_file <kind> [<name>]: the state file path, relative to the root, for onboarding, program, feature <name>
# or maintain <id> (the paths sync-feature-state.sh and the pre-push hook use).
gc_state_file() {
  case "${1:-}" in
    onboarding|onboard) printf 'docs/agents-v0/onboarding/state.json\n' ;;
    program) printf 'docs/agents-v0/program.state.json\n' ;;
    feature) [ -n "${2:-}" ] || return 2; printf 'docs/agents-v0/requirements/%s.state.json\n' "$2" ;;
    maintain) [ -n "${2:-}" ] || return 2; printf 'docs/agents-v0/maintain/%s/state.json\n' "$2" ;;
    *) return 2 ;;
  esac
}

# --- branch check ---------------------------------------------------------------------------------------------------
# gc_branch: the current branch name (exit 1 on a detached HEAD).
gc_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null; }
# gc_branch_check [<branch>]: refuse a detached HEAD, or a branch other than <branch> when one is given.
gc_branch_check() {
  gc_to_root branch-check
  gc_b="$(gc_branch)" || gc_refuse branch-check "HEAD is detached; check out a branch first"
  if [ -n "${1:-}" ] && [ "$gc_b" != "$1" ]; then
    gc_refuse branch-check "on branch $gc_b, expected $1"
  fi
  gc_ok branch-check "on branch $gc_b"
}

# --- secret scan --------------------------------------------------------------------------------------------------
# gc_scanner <step>: refuse <step> unless python3 and secret_scan.py are there; set gc_py to the scanner path.
gc_scanner() {
  command -v python3 >/dev/null 2>&1 || gc_refuse "$1" "python3 is missing, so the secret scan cannot run"
  [ -f "$GC_HERE/secret_scan.py" ] || gc_refuse "$1" "$GC_HERE/secret_scan.py is missing; reinstall the kit (install.sh --update)"
  gc_py="$GC_HERE/secret_scan.py"
}

# Carried from ec12d6d2/c31fca77 (workflow-fixes-onboard), Design: D1. Adapted: the onboard path list, the scan record
#   and commit_msg_ok are left to the commit step (D4); this is the scan itself, with the same fail-closed exits.
# gc_scan_staged [--message-file FILE]: refuse when nothing is staged, or when secret_scan.py --staged exits non-zero
# (1 a hit, 2 it could not scan).
gc_scan_staged() {
  gc_msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --message-file) [ $# -ge 2 ] || gc_die "--message-file needs a file"; gc_msg="$2"; shift 2 ;;
      *) gc_die "scan-staged: unknown option: $1" ;;
    esac
  done
  if [ -n "$gc_msg" ]; then
    case "$gc_msg" in /*) ;; *) gc_msg="$(pwd)/$gc_msg" ;; esac
  fi
  gc_to_root scan-staged
  gc_scanner scan-staged
  if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    gc_rc=0
    git diff --cached --quiet --no-ext-diff 2>/dev/null || gc_rc=$?
    case "$gc_rc" in
      0) gc_refuse scan-staged "nothing is staged" ;;
      1) ;;
      *) gc_refuse scan-staged "git could not read the index" ;;
    esac
  else
    [ -n "$(git ls-files)" ] || gc_refuse scan-staged "nothing is staged"
  fi
  gc_rc=0
  if [ -n "$gc_msg" ]; then
    python3 "$gc_py" --staged --root "$(pwd)" --message-file "$gc_msg" || gc_rc=$?
  else
    python3 "$gc_py" --staged --root "$(pwd)" || gc_rc=$?
  fi
  [ "$gc_rc" = 0 ] || gc_refuse scan-staged "secret_scan.py exited $gc_rc (1: a hit, 2: it could not scan); do not commit"
  gc_ok scan-staged "the staged content holds no secret"
}

# Design: D1 (new). gc_scan_push [<remote>]: read the pre-push lines (<local ref> <local sha> <remote ref> <remote sha>)
# on stdin and scan every commit the push sends: <remote sha>..<local sha> when the remote tip is known here, else
# every commit not on a remote-tracking branch of <remote> (of any remote when no name is given). Deletions send
# nothing. Fails closed when a range cannot be listed.
gc_scan_push() {
  gc_remote="${1:-}"
  gc_to_root scan-push
  gc_scanner scan-push
  gc_list=""
  gc_n=0
  while read -r gc_lref gc_lsha gc_rref gc_rsha; do
    [ -n "${gc_lref:-}" ] || continue
    [ "${gc_lsha:-}" != "$GC_ZERO" ] || continue
    gc_tip="$(git rev-parse -q --verify "${gc_lsha}^{commit}" 2>/dev/null)" || continue  # a tag on a tree or blob
    gc_n=$((gc_n + 1))
    if [ -n "${gc_rsha:-}" ] && [ "$gc_rsha" != "$GC_ZERO" ] && git cat-file -e "${gc_rsha}^{commit}" 2>/dev/null; then
      gc_revs="$(git rev-list --reverse "$gc_rsha..$gc_tip")" || gc_refuse scan-push "cannot list the commits of $gc_lref"
    elif [ -n "$gc_remote" ]; then
      gc_revs="$(git rev-list --reverse "$gc_tip" --not --remotes="$gc_remote")" || gc_refuse scan-push "cannot list the commits of $gc_lref"
    else
      gc_revs="$(git rev-list --reverse "$gc_tip" --not --remotes)" || gc_refuse scan-push "cannot list the commits of $gc_lref"
    fi
    gc_list="$gc_list$gc_revs
"
  done
  gc_list="$(printf '%s' "$gc_list" | awk 'NF && !seen[$0]++')"
  if [ -z "$gc_list" ]; then
    gc_ok scan-push "no new commits to scan (refs: $gc_n)"
    return 0
  fi
  gc_rc=0
  printf '%s\n' "$gc_list" | python3 "$gc_py" --commits - --root "$(pwd)" || gc_rc=$?
  [ "$gc_rc" = 0 ] || gc_refuse scan-push "secret_scan.py exited $gc_rc (1: a hit, 2: it could not scan); the push is refused"
  gc_ok scan-push "the commits being pushed hold no secret"
}

gc_paths() {
  gc_to_root paths
  printf 'root=%s\n' "$(pwd)"
  printf 'git_common_dir=%s\n' "$(gc_common_dir)"
  printf 'onboarding_state=%s\n' "$(gc_state_file onboarding)"
}

gc_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-common.sh scan-staged [--message-file FILE] | scan-push [<remote>] | branch-check [<branch>] | paths\n' >&2
  exit 2
}

gc_main() {
  [ $# -ge 1 ] || gc_usage
  gc_cmd="$1"; shift
  case "$gc_cmd" in
    scan-staged) gc_scan_staged "$@" ;;
    scan-push) [ $# -le 1 ] || gc_usage; gc_scan_push "$@" ;;
    branch-check) [ $# -le 1 ] || gc_usage; gc_branch_check "$@" ;;
    paths) [ $# -eq 0 ] || gc_usage; gc_paths ;;
    -h|--help) sed -n '2,20p' "$GC_HERE/guard-common.sh"; exit 0 ;;
    *) gc_usage ;;
  esac
}

[ "${GUARD_COMMON_LIB:-}" = 1 ] || gc_main "$@"
