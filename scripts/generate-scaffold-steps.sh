#!/bin/sh
# generate-scaffold-steps.sh (scaffold redo, Design: DS6): copy `guard-scaffold.sh steps` into the generated block of
# core/common/commands/v0-scaffold.md between the BEGIN and END marker lines, byte for byte.
# Run: sh scripts/generate-scaffold-steps.sh          rewrite the blocks
#      sh scripts/generate-scaffold-steps.sh --check  exit 1 when a block differs from the guard's output
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS="$ROOT/core/common/commands/v0-scaffold.md"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-scaffold.sh" steps)" || { printf 'FAIL: guard-scaffold.sh steps failed\n' >&2; exit 2; }
for DOC in $DOCS; do
python3 - "$DOC" "${1:-}" "$steps" <<'PY' || exit $?
import os, sys
doc, mode, steps = sys.argv[1], sys.argv[2], sys.argv[3]
name = os.path.basename(doc)
begin = "<!-- BEGIN generated: sh .agents-v0/scripts/guard-scaffold.sh steps (scripts/generate-scaffold-steps.sh); do not edit -->"
end = "<!-- END generated -->"
text = open(doc, encoding="utf-8").read()
if text.count(begin) != 1 or text.count(end) != 1 or text.index(begin) > text.index(end):
    print(f"FAIL: {doc} needs one BEGIN and one END generated marker line", file=sys.stderr); sys.exit(2)
head, rest = text.split(begin, 1)
_, tail = rest.split(end, 1)
new = head + begin + "\n" + steps + "\n" + end + tail
if mode == "--check":
    if new != text:
        print(f"FAIL: the {name} step block differs from guard-scaffold.sh steps; run sh scripts/generate-scaffold-steps.sh", file=sys.stderr); sys.exit(1)
    print(f"OK: the {name} step block matches guard-scaffold.sh steps"); sys.exit(0)
if mode:
    print("usage: generate-scaffold-steps.sh [--check]", file=sys.stderr); sys.exit(2)
open(doc, "w", encoding="utf-8").write(new)
print(f"OK: wrote the {name} step block")
PY
done
