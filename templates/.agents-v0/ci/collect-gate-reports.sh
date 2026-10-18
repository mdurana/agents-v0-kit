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
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.environ["COLLECT_DIR"])
import packlib

roots = [item for item in os.environ.get("COLLECT_ROOTS", "").split() if item]
pack_id = packlib.profile_pack()
data = packlib.load(pack_id) if pack_id else None
patterns = []
cve = None
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


def ensure_cve_artifact(root_dir, cve_rel, pid):
    if not cve_rel or "*" in cve_rel:
        return 0
    if glob.glob(os.path.join(root_dir, cve_rel), recursive=True):
        return 0
    payload = None
    try:
        if pid == "dotnet" and shutil.which("dotnet"):
            proc = subprocess.run(
                ["dotnet", "list", "package", "--vulnerable", "--include-transitive", "--format", "json"],
                cwd=root_dir, capture_output=True, text=True, timeout=60,
            )
            if proc.returncode == 0 and proc.stdout.strip().startswith("{"):
                parsed = json.loads(proc.stdout)
                if "projects" in parsed:
                    payload = parsed
        elif pid == "node" and shutil.which("npm") and os.path.isfile(os.path.join(root_dir, "package-lock.json")):
            proc = subprocess.run(
                ["npm", "audit", "--omit=dev", "--json"],
                cwd=root_dir, capture_output=True, text=True, timeout=60,
            )
            if proc.stdout.strip().startswith("{"):
                parsed = json.loads(proc.stdout)
                if "vulnerabilities" in parsed:
                    payload = parsed
        elif pid == "python" and shutil.which("pip-audit"):
            proc = subprocess.run(
                ["pip-audit", "-f", "json"],
                cwd=root_dir, capture_output=True, text=True, timeout=60,
            )
            if proc.stdout.strip().startswith("{"):
                parsed = json.loads(proc.stdout)
                if "dependencies" in parsed:
                    payload = parsed
        elif pid == "go" and shutil.which("govulncheck"):
            proc = subprocess.run(
                ["govulncheck", "-json", "./..."],
                cwd=root_dir, capture_output=True, text=True, timeout=60,
            )
            if proc.returncode in (0, 3):
                deps = {}
                for line in proc.stdout.splitlines():
                    line = line.strip()
                    if not line.startswith("{"):
                        continue
                    msg = json.loads(line)
                    finding = msg.get("finding")
                    if not isinstance(finding, dict):
                        continue
                    trace = finding.get("trace") or []
                    mod = str(trace[0].get("module") or "?") if trace and isinstance(trace[0], dict) else "?"
                    deps.setdefault(mod, []).append({"name": str(finding.get("osv") or "?"), "severity": "HIGH"})
                payload = {"dependencies": [{"fileName": k, "vulnerabilities": v} for k, v in sorted(deps.items())]}
        elif pid == "java" and os.path.isfile(os.path.join(root_dir, "pom.xml")):
            mvn_cmd = None
            for cand in (os.path.join(root_dir, "mvnw"), os.path.join(os.getcwd(), "mvnw"), "mvn"):
                if os.path.isfile(cand) and os.access(cand, os.X_OK):
                    mvn_cmd = [os.path.abspath(cand)]
                    break
                elif shutil.which(cand):
                    mvn_cmd = [cand]
                    break
            if mvn_cmd:
                subprocess.run(
                    mvn_cmd + ["-B", "verify", "-Pci-security", "-DskipTests"],
                    cwd=root_dir, capture_output=True, text=True, timeout=300,
                )
                target_json = os.path.join(root_dir, cve_rel)
                if os.path.isfile(target_json):
                    dest = os.path.join("ci-artifacts", "gate", root_dir, cve_rel)
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    shutil.copy2(target_json, dest)
                    return 1
    except Exception:
        payload = None
    if payload is None:
        return 0
    dest = os.path.join("ci-artifacts", "gate", root_dir, cve_rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
        handle.write("\n")
    return 1


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
    if cve and data:
        copied += ensure_cve_artifact(root, cve, data.get("id") or "")
print(f"gate reports: copied {copied} file(s) into ci-artifacts/gate/")
PY
