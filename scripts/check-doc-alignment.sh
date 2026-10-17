#!/bin/sh
# check-doc-alignment.sh — the closed check that the docs match the workflow.
#
# scripts/doc-alignment.ledger is the list. This script exits 0 only when:
#   every R row's phrase is in that file,
#   every F row's phrase is absent,
#   every T row's phrase is in that test or implementation file,
#   every templates/.agents-v0/ci/*.sh and core/common/commands/v0-*.md is listed,
#   every non-comment FAIL: line in those CI scripts has its hash listed.
# A new check or command fails here until its row is added. That is the boundary
# of the 100% claim. Pack skills that no command names are outside it.
set -eu

KIT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
cd "$KIT"
ledger="scripts/doc-alignment.ledger"
[ -f "$ledger" ] || { printf 'FAIL: missing %s\n' "$ledger" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

LEDGER="$ledger" python3 - <<'PY'
import hashlib
import os
import pathlib
import sys

ledger_path = os.environ["LEDGER"]
root = pathlib.Path(".")
ci = root / "templates" / ".agents-v0" / "ci"
cmds = root / "core" / "common" / "commands"
failures = []

def fail(msg):
    failures.append(msg)

rows = {"R": [], "F": [], "T": [], "S": set(), "C": set(), "H": {}}
for raw in pathlib.Path(ledger_path).read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    parts = raw.split("\t")
    kind = parts[0]
    if kind in ("R", "F", "T"):
        if len(parts) != 4:
            fail(f"ledger {kind} row needs id, path, phrase: {raw}")
            continue
        rows[kind].append(parts[1:])
    elif kind == "S" and len(parts) == 2:
        rows["S"].add(parts[1])
    elif kind == "C" and len(parts) == 2:
        rows["C"].add(parts[1])
    elif kind == "H" and len(parts) == 3:
        rows["H"][parts[1]] = parts[2]
    else:
        fail(f"ledger row not understood: {raw}")

def contains(path, phrase):
    file = root / path
    if not file.is_file():
        return False
    return phrase in file.read_text(encoding="utf-8")

for fact, path, phrase in rows["R"]:
    if not contains(path, phrase):
        fail(f"{fact}: {path} does not contain {phrase!r}")
for fact, path, phrase in rows["F"]:
    if contains(path, phrase):
        fail(f"{fact}: {path} still contains {phrase!r}")
for fact, path, phrase in rows["T"]:
    if not contains(path, phrase):
        fail(f"{fact}: evidence {path} does not contain {phrase!r}")

for path in sorted(ci.glob("*.sh")):
    if path.name not in rows["S"]:
        fail(f"CI script {path.name} has no S row")
for name in sorted(rows["S"]):
    if not (ci / name).is_file():
        fail(f"S row names missing script {name}")

for path in sorted(cmds.glob("v0-*.md")):
    if path.name not in rows["C"]:
        fail(f"command {path.name} has no C row")
for name in sorted(rows["C"]):
    if not (cmds / name).is_file():
        fail(f"C row names missing command {name}")

found = {}
for path in sorted(ci.glob("*.sh")):
    for line in path.read_text(encoding="utf-8").splitlines():
        if "FAIL:" not in line or line.strip().startswith("#"):
            continue
        norm = " ".join(line.split())
        digest = hashlib.sha256(f"{path.name}:{norm}".encode()).hexdigest()[:12]
        found[digest] = path.name

for digest, name in sorted(found.items()):
    if digest not in rows["H"]:
        fail(f"FAIL line in {name} has no H row {digest}")
for digest, name in sorted(rows["H"].items()):
    if digest not in found:
        fail(f"stale H row {digest} for {name}")
    elif found[digest] != name:
        fail(f"H row {digest} says {name} but the line is in {found[digest]}")

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print(
    "doc-alignment: ok "
    f"({len(rows['R'])} requires, {len(rows['F'])} forbids, {len(rows['T'])} evidence, "
    f"{len(rows['S'])} scripts, {len(rows['C'])} commands, {len(rows['H'])} fail lines)"
)
PY
