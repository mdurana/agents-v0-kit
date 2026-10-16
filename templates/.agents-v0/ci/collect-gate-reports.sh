#!/bin/sh
# collect-gate-reports.sh — copy pack coverage, test, and CVE reports into
# ci-artifacts/gate/<root>/ so a later CI job can read them.
#
# A bound Pack copies coverage.path, testsReport.path, and cve.path.
# With no Pack, the Java example paths under target/ are copied when present.
# Layout roots come from resolve-layout.sh. Pass module roots as arguments to
# copy only those.
#
# Usage: sh .agents-v0/ci/collect-gate-reports.sh [root...]

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" -eq 0 ]; then
  eval "$(sh "$DIR/resolve-layout.sh")"
  set -- ${BACKEND_ROOT:-} ${BFF_ROOT:-} ${SERVICE_ROOTS:-}
fi

COLLECT_DIR="$DIR" COLLECT_ROOTS="$*" python3 - <<'PY'
import glob
import os
import shutil
import sys

sys.path.insert(0, os.environ["COLLECT_DIR"])
import packlib

roots = [item for item in os.environ.get("COLLECT_ROOTS", "").split() if item]
pack_id = packlib.profile_pack()
data = packlib.load(pack_id) if pack_id else None
patterns = []
if data and not packlib.errors_of(data, "backend"):
    for key in ("coverage", "testsReport"):
        spec = data.get(key) or {}
        if spec.get("path"):
            patterns.append(spec["path"])
    cve = (data.get("cve") or {}).get("path")
    if cve:
        patterns.append(cve)
else:
    patterns = [
        "target/site/jacoco/jacoco.xml",
        "target/surefire-reports/TEST-*.xml",
        "target/failsafe-reports/TEST-*.xml",
        "target/dependency-check-report.json",
    ]

copied = 0
for root in roots:
    if not os.path.isdir(root):
        continue
    for pattern in patterns:
        for match in glob.glob(os.path.join(root, pattern), recursive=True):
            if not os.path.isfile(match):
                continue
            rel = os.path.relpath(match, root)
            dest = os.path.join("ci-artifacts", "gate", root, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(match, dest)
            copied += 1
print(f"gate reports: copied {copied} file(s) into ci-artifacts/gate/")
PY
