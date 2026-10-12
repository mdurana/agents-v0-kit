#!/bin/sh
# check-endpoint-auth.sh — a new endpoint is explicitly authorized or explicitly public.
#
# Usage:
#   sh .agents-v0/ci/check-endpoint-auth.sh <base> [<head>]   fail on a mapping the change adds without a security annotation
#   sh .agents-v0/ci/check-endpoint-auth.sh --list [<root>...]  print every mapping: file:line  VERB /path  annotated|NO-ANNOTATION
#
# Scanners live in endpoint_scan.py, which discover-codebase.sh imports too.
# The Pack row selects the built-in scanner. java (and a missing Pack) scans *.java.
# dotnet, node, python, and go use the BUILTINS table in that module. Extra rows under
# "## Endpoint authorization" add file types. A row whose mapping the active pack
# already scans is skipped, so discovery does not double-count a built-in stack.
# <head> omitted compares <base> with the working tree.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }
[ $# -ge 1 ] || { printf 'usage: %s <base> [<head>] | --list [<root>...]\n' "$0" >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS="$(printf '%s\n' "$@")" ENDPOINT_SCAN_DIR="$DIR" python3 - <<'PY'
import os
import sys

sys.path.insert(0, os.environ["ENDPOINT_SCAN_DIR"])
import endpoint_scan

raise SystemExit(endpoint_scan.main(os.environ["ARGS"].splitlines()))
PY
