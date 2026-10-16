#!/bin/sh
# run-backend-verify.sh — print a filled profile verify command.
#
# Usage: sh run-backend-verify.sh [row] [profile]
#   row      "Backend verify" (default) or "Frontend verify"
#   profile  docs/agents-v0/project-profile.md
# A placeholder cell prints nothing. The caller then uses its layout default.
# The command is the one activate-stack-pack wrote from pack.json.

set -eu

row="Backend verify"
profile="docs/agents-v0/project-profile.md"
if [ $# -ge 1 ]; then
  case "$1" in
    */*|*.md) profile="$1" ;;
    *)
      row="$1"
      if [ $# -ge 2 ]; then profile="$2"; fi
      ;;
  esac
fi
[ -f "$profile" ] || exit 0

python3 - "$profile" "$row" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
row = sys.argv[2]
if "## Commands" not in text:
    raise SystemExit(0)
body = text.split("## Commands", 1)[1].split("\n## ", 1)[0]
for line in body.splitlines():
    if not line.startswith("|"):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if cells and cells[0] == row and len(cells) > 1:
        value = cells[1]
        if value and "<!--" not in value and value.lower() != "n/a":
            print(value)
        break
PY
