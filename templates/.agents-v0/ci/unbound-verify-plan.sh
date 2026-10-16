#!/bin/sh
# unbound-verify-plan.sh — choose a verify command when the profile Pack cell is empty.
#
# Prints one plan the build job can run. An empty Pack does not default to Maven.
#   java                  the only marker is the java example; the caller runs Maven
#   <id>                  then one "root<TAB>command" line per layout root
# Exit 2 when no backend marker is present. Exit 3 when more than one pack matches.
#
# Usage: sh .agents-v0/ci/unbound-verify-plan.sh
# Reads BACKEND_ROOT, BFF_ROOT, and SERVICE_ROOTS from the environment.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
PACKLIB_DIR="$DIR" python3 - <<'PY'
import os
import re
import sys

sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib

found = packlib.detect(".")
if not found:
    print("no backend marker; bind a Pack before verify", file=sys.stderr)
    raise SystemExit(2)
if len(found) > 1:
    print("ambiguous backend markers: " + ", ".join(sorted(found)) + "; bind a Pack", file=sys.stderr)
    raise SystemExit(3)
pack_id = sorted(found)[0]
if pack_id == "java":
    print("java")
    raise SystemExit(0)
data = packlib.load(pack_id)
if data is None or packlib.errors_of(data, "backend"):
    print(f"Pack {pack_id} has no complete manifest", file=sys.stderr)
    raise SystemExit(1)

def strip_cd(command):
    return re.sub(r"^cd\s+\S+\s+&&\s+", "", command or "")

service_roots = os.environ.get("SERVICE_ROOTS", "").split()
roots = []
for name in ("BACKEND_ROOT", "BFF_ROOT"):
    value = os.environ.get(name, "").strip()
    if value:
        roots.append(value)
if service_roots:
    roots.extend(service_roots)
if not roots:
    roots = [item for item in packlib.marker_roots(".", 4)] or ["."]

print(pack_id)
template = data.get("serviceVerify") if service_roots and data.get("serviceVerify") else ""
for root in roots:
    if template:
        command = template.replace("{root}", root)
        command = strip_cd(command)
    else:
        command = strip_cd(data.get("verify") or "")
    if not command:
        print(f"Pack {pack_id} has no verify command", file=sys.stderr)
        raise SystemExit(1)
    print(f"{root}\t{command}")
PY
