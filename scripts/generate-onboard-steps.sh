#!/bin/sh
# generate-onboard-steps.sh (onboard redo, Design: D5): copy `guard-onboard.sh steps` into the generated block of
# core/common/commands/v0-onboard.md, between the BEGIN and END marker lines, byte for byte.
# Run: sh scripts/generate-onboard-steps.sh          rewrite the block
#      sh scripts/generate-onboard-steps.sh --check  exit 1 when the block differs from the guard's output
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/core/common/commands/v0-onboard.md"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-onboard.sh" steps)" || { printf 'FAIL: guard-onboard.sh steps failed\n' >&2; exit 2; }
python3 - "$DOC" "${1:-}" "$steps" <<'PY'
import sys
doc, mode, steps = sys.argv[1], sys.argv[2], sys.argv[3]
begin = "<!-- BEGIN generated: sh .agents-v0/scripts/guard-onboard.sh steps (scripts/generate-onboard-steps.sh); do not edit -->"
end = "<!-- END generated -->"
text = open(doc, encoding="utf-8").read()
if text.count(begin) != 1 or text.count(end) != 1 or text.index(begin) > text.index(end):
    print(f"FAIL: {doc} needs one BEGIN and one END generated marker line", file=sys.stderr); sys.exit(2)
head, rest = text.split(begin, 1)
_, tail = rest.split(end, 1)
new = head + begin + "\n" + steps + "\n" + end + tail
if mode == "--check":
    if new != text:
        print("FAIL: the v0-onboard.md step block differs from guard-onboard.sh steps; run sh scripts/generate-onboard-steps.sh", file=sys.stderr); sys.exit(1)
    print("OK: the v0-onboard.md step block matches guard-onboard.sh steps"); sys.exit(0)
if mode:
    print("usage: generate-onboard-steps.sh [--check]", file=sys.stderr); sys.exit(2)
open(doc, "w", encoding="utf-8").write(new)
print("OK: wrote the v0-onboard.md step block")
PY
