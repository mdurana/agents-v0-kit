#!/bin/sh
# strip-test-overrides.sh — print a kit script without its test-only override blocks
# (kitfix-20261031-installed-no-overrides).
#   sh scripts/strip-test-overrides.sh <file>        writes the stripped text to stdout
# A block starts at a line containing `# >>> kit-test-override` and ends at the next line containing
# `# <<< kit-test-override`; both marker lines and everything between them are dropped. The blocks hold
# the code that reads AGENTS_V0_* env overrides (skip flags, clock pin, time zone, trace mode), which only
# the kit's own test suites may use. install.sh runs every installed .agents-v0/scripts file through
# this filter (unless --test-overrides), and check-installed-kit.sh uses it to compute the expected hash.
# Exit 1 (and no output promise) when a block is not closed or a marker is nested.
set -eu
[ -f "${1:-}" ] || { printf 'usage: %s <file>\n' "$0" >&2; exit 2; }
awk '
  /# >>> kit-test-override/ { if (skip) { bad = 1 } skip = 1; next }
  /# <<< kit-test-override/ { if (!skip) { bad = 1 } skip = 0; next }
  !skip { print }
  END { if (skip || bad) { print "strip-test-overrides: unbalanced kit-test-override markers in " FILENAME > "/dev/stderr"; exit 1 } }
' "$1"
