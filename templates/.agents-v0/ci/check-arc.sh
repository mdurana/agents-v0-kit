#!/bin/sh
# check-arc.sh — material stories cite an approved ARC record (workflow-orchestration.mdc).
#
# Usage: sh check-arc.sh <requirements-artifact>
# A story whose Material line is not "yes" passes without an ARC record.
# Material: yes requires ARC: docs/agents-v0/design/system/<record>.md and a Fitness
# functions section. The record is approved when it has an Approved arc row, or when
# docs/agents-v0/architecture.md has an Approved architecture row that names that file.

set -eu

art="${1:-}"
if [ -z "$art" ]; then
  printf 'usage: %s <requirements-artifact>\n' "$0" >&2
  exit 1
fi
[ -f "$art" ] || { printf 'FAIL: requirements artifact not found: %s\n' "$art" >&2; exit 1; }

material="$(sed -n 's/^[[:space:]]*Material:[[:space:]]*//p' "$art" | head -n 1 | tr -d '[:space:]')"
case "$material" in
  yes|Yes|YES) ;;
  *)
    printf 'OK: %s is not a material change\n' "$art"
    exit 0
    ;;
esac

arc="$(sed -n 's/^[[:space:]]*ARC:[[:space:]]*//p' "$art" | head -n 1 | sed 's/[[:space:]]*$//')"
case "$arc" in
  docs/agents-v0/design/system/*.md) ;;
  *)
    printf 'FAIL: %s is Material: yes and needs "ARC: docs/agents-v0/design/system/<record>.md"\n' "$art" >&2
    exit 1
    ;;
esac
[ -f "$arc" ] || { printf 'FAIL: ARC record missing: %s\n' "$arc" >&2; exit 1; }
grep -Eq '^#+[[:space:]]*Fitness functions' "$arc" || {
  printf 'FAIL: %s has no Fitness functions section\n' "$arc" >&2
  exit 1
}

here="$(cd "$(dirname "$0")" && pwd)"
if sh "$here/check-approvals.sh" "$arc" arc; then
  printf 'OK: %s cites an approved arc row\n' "$art"
  exit 0
fi
arch_file="docs/agents-v0/architecture.md"
if [ -f "$arch_file" ] && sh "$here/check-approvals.sh" "$arch_file" architecture >/dev/null 2>&1; then
  if grep -F "$arc" "$arch_file" >/dev/null 2>&1; then
    printf 'OK: %s is covered by the approved architecture pack\n' "$art"
    exit 0
  fi
fi
printf 'FAIL: %s needs an Approved arc row, or an Approved architecture row that names %s\n' "$art" "$arc" >&2
exit 1
