#!/bin/sh
# resolve-integration-branch.sh — branch the next story builds on, and the local gate's base.
#
# Usage: sh .agents-v0/scripts/resolve-integration-branch.sh
# Order: the profile "Integration branch" row when it names a branch, else the local
# branch behind origin/HEAD, else main, else master, else HEAD.
# A placeholder cell (starts with "<") is ignored. Prints one ref and exits 0.
set -eu

profile="docs/agents-v0/project-profile.md"
branch=""
if [ -f "$profile" ]; then
  branch="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    tolower($0) ~ /integration branch/ {
      v = trim($3)
      if (v != "" && v !~ /^</ && tolower(v) != "n/a" && v !~ /[[:space:]]/) { print v; exit }
    }' "$profile")"
fi
if [ -n "$branch" ]; then
  printf '%s\n' "$branch"
  exit 0
fi

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  origin="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  case "$origin" in
    origin/*)
      local_name="${origin#origin/}"
      if git show-ref --verify --quiet "refs/heads/$local_name"; then
        printf '%s\n' "$local_name"
        exit 0
      fi
      printf '%s\n' "$origin"
      exit 0
      ;;
  esac
  if git show-ref --verify --quiet refs/heads/main; then
    printf 'main\n'
    exit 0
  fi
  if git show-ref --verify --quiet refs/heads/master; then
    printf 'master\n'
    exit 0
  fi
fi
printf 'HEAD\n'
