#!/bin/sh
# generate-plan-steps.sh (plan redo, Design: DP6): copy `guard-plan.sh steps` into the generated block of
# core/common/commands/v0-plan.md between the BEGIN and END marker lines, byte for byte.
# Run: sh scripts/generate-plan-steps.sh          rewrite the blocks
#      sh scripts/generate-plan-steps.sh --check  exit 1 when a block differs from the guard's output
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS="$ROOT/core/common/commands/v0-plan.md"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-plan.sh" steps)" || { printf 'FAIL: guard-plan.sh steps failed\n' >&2; exit 2; }
for DOC in $DOCS; do
python3 - "$DOC" "${1:-}" "$steps" <<'PY' || exit $?
import os, sys
doc, mode, steps = sys.argv[1], sys.argv[2], sys.argv[3]
name = os.path.basename(doc)
begin = "<!-- BEGIN generated: sh .agents-v0/scripts/guard-plan.sh steps (scripts/generate-plan-steps.sh); do not edit -->"
end = "<!-- END generated -->"
text = open(doc, encoding="utf-8").read()
if text.count(begin) != 1 or text.count(end) != 1 or text.index(begin) > text.index(end):
    print(f"FAIL: {doc} needs one BEGIN and one END generated marker line", file=sys.stderr); sys.exit(2)
head, rest = text.split(begin, 1)
_, tail = rest.split(end, 1)
new = head + begin + "\n" + steps + "\n" + end + tail
if mode == "--check":
    if new != text:
        print(f"FAIL: the {name} step block differs from guard-plan.sh steps; run sh scripts/generate-plan-steps.sh", file=sys.stderr); sys.exit(1)
    print(f"OK: the {name} step block matches guard-plan.sh steps"); sys.exit(0)
if mode:
    print("usage: generate-plan-steps.sh [--check]", file=sys.stderr); sys.exit(2)
open(doc, "w", encoding="utf-8").write(new)
print(f"OK: wrote the {name} step block")
PY
done
