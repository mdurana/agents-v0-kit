#!/bin/sh
# feature-worktree.sh — one git worktree and branch per feature, so features in flight
# never share a working tree (workflow-orchestration.mdc Parallel features).
#
# Usage: sh .agents-v0/scripts/feature-worktree.sh <feature> [<base-ref>]
#        sh .agents-v0/scripts/feature-worktree.sh --maintain <id> [<base-ref>]
#   <feature>   slug used for docs/agents-v0/requirements/<feature>.md: lowercase letters, digits, hyphens
#   <id>        maintenance note id; branch is maintain/<id>, not feature/<id>
#   <base-ref>  start point (default: resolve-integration-branch.sh)
#
# Creates ../<repo>-<feature> on branch feature/<feature>, or ../<repo>-maintain-<id>
# on branch maintain/<id>. Run it only after the user explicitly authorized creating
# the branch: hooks ask before this script runs.
# A second run reuses that branch. An existing worktree is left in place. A branch
# whose worktree was removed is attached again, without -b. A new branch is created
# only when that branch does not exist.
# A branch already contained in the integration ref (tip differs) is not checked out.
# Untracked docs/agents-v0/requirements/<feature>.* or docs/agents-v0/maintain/<id>/
# in the primary checkout move into the worktree. Tracked files stay where they are.
# Remove the worktree after the merge: git worktree remove <path>. The branch itself is kept for reference and
# backtracking (kitfix-20261031-keep-branches): never delete feature/<feature> or maintain/<id>.

set -eu

prefix="feature"
if [ "${1:-}" = "--maintain" ]; then
  prefix="maintain"
  shift
fi
feature="${1:-}"
base="${2:-}"
if [ -z "$feature" ]; then
  printf 'usage: %s [--maintain] <feature> [<base-ref>]\n' "$0" >&2
  exit 1
fi
case "$feature" in
  [a-z0-9]*) ;;
  *)
    printf 'FAIL: feature slug must start with a lowercase letter or digit: %s\n' "$feature" >&2
    exit 1
    ;;
esac
case "$feature" in
  *[!a-z0-9-]*)
    printf 'FAIL: feature slug may hold only lowercase letters, digits, and hyphens: %s\n' "$feature" >&2
    exit 1
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
repo_name="$(basename "$repo_root")"
here="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$base" ]; then
  base="$(cd "$repo_root" && sh "$here/resolve-integration-branch.sh")"
fi
if [ "$prefix" = "maintain" ]; then
  dest="$(dirname "$repo_root")/${repo_name}-maintain-${feature}"
else
  dest="$(dirname "$repo_root")/${repo_name}-${feature}"
fi
branch="${prefix}/${feature}"

# Move new untracked intake or maintain docs into the worktree that will continue the work.
relocate_untracked() {
  target="$1"
  primary="$(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')"
  [ -n "$primary" ] || return 0
  if [ "$primary" = "$target" ]; then
    return 0
  fi
  if [ "$prefix" = "maintain" ]; then
    rel="docs/agents-v0/maintain/${feature}"
    src="${primary}/${rel}"
    dst="${target}/${rel}"
    if [ -d "$src" ] && [ ! -e "$dst" ] && [ -z "$(git -C "$primary" ls-files -- "$rel")" ]; then
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
      printf 'Moved uncommitted %s into the worktree.\n' "$rel"
    fi
    return 0
  fi
  src_dir="${primary}/docs/agents-v0/requirements"
  [ -d "$src_dir" ] || return 0
  found=0
  for src in "$src_dir"/"${feature}".*; do
    [ -f "$src" ] || continue
    rel="docs/agents-v0/requirements/$(basename "$src")"
    if git -C "$primary" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      continue
    fi
    dst="${target}/${rel}"
    if [ -e "$dst" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    found=1
  done
  if [ "$found" = 1 ]; then
    printf 'Moved uncommitted docs/agents-v0/requirements/%s.* into the worktree.\n' "$feature"
  fi
}

if git show-ref --verify --quiet "refs/heads/${branch}"; then
  tip="$(git rev-parse "refs/heads/${branch}")"
  base_tip="$(git rev-parse "$base")"
  if [ "$tip" != "$base_tip" ] && git merge-base --is-ancestor "$tip" "$base_tip"; then
    if [ "$prefix" = "feature" ]; then
      printf 'FAIL: %s is already contained in %s. Do not check it out. Start /v0-maintain for a fix or a small change.\n' "$branch" "$base" >&2
    else
      printf 'FAIL: %s is already contained in %s. Do not check it out. Start a new maintenance id.\n' "$branch" "$base" >&2
    fi
    exit 1
  fi
fi

# kitfix-20261031-gate-commit: a squash-released branch is never an ancestor of the integration branch;
# its squash commit names it (Story-Branch trailer). Do not check it out again.
if git show-ref --verify --quiet "refs/heads/${branch}" \
   && git log --first-parent --format=%B "$base" 2>/dev/null | grep -Eq "^Story-Branch:[[:space:]]*${branch}[[:space:]]*\$"; then
  printf 'FAIL: %s was already squash-merged into %s. Do not check it out. Start /v0-maintain for a fix or a small change.\n' "$branch" "$base" >&2
  exit 1
fi
existing=""
if git show-ref --verify --quiet "refs/heads/${branch}"; then
  existing="$(git worktree list --porcelain | awk -v want="branch refs/heads/${branch}" '
    /^worktree / { path = substr($0, 10) }
    $0 == want { print path; exit }
  ')"
fi
if [ -n "$existing" ]; then
  relocate_untracked "$existing"
  printf 'Worktree already exists: %s on branch %s. Continue there. Do not create another branch.\n' "$existing" "$branch"
  exit 0
fi
if [ -e "$dest" ]; then
  printf 'FAIL: worktree path already exists: %s\n' "$dest" >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/heads/${branch}"; then
  git worktree add "$dest" "$branch"
  relocate_untracked "$dest"
  printf 'Attached worktree %s to existing branch %s.\n' "$dest" "$branch"
else
  git worktree add -b "$branch" "$dest" "$base"
  relocate_untracked "$dest"
  printf 'Created worktree %s on branch %s (from %s).\n' "$dest" "$branch" "$base"
fi
printf 'Open that folder in the IDE, then run /v0-status %s or the next phase command there.\n' "$feature"
