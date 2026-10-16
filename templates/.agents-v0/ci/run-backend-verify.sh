#!/bin/sh
# run-backend-verify.sh — print the profile Backend verify command when it is filled.
#
# A placeholder cell prints nothing. The caller then uses its layout default.
# The command is the one activate-stack-pack wrote from pack.json.

set -eu

profile="${1:-docs/agents-v0/project-profile.md}"
[ -f "$profile" ] || exit 0

python3 - "$profile" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if "## Commands" not in text:
    raise SystemExit(0)
body = text.split("## Commands", 1)[1].split("\n## ", 1)[0]
for line in body.splitlines():
    if not line.startswith("|"):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if cells and cells[0] == "Backend verify" and len(cells) > 1:
        value = cells[1]
        if value and "<!--" not in value and value != "n/a":
            print(value)
        break
PY
