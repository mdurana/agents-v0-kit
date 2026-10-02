#!/bin/sh
# export-audit-pack.sh — SHA-256 manifest of delivery evidence for compliance archives.
#
# Usage: sh .agents-v0/scripts/export-audit-pack.sh <feature> [--out <directory>]
# Default output: docs/agents-v0/release/<feature>/audit-manifest.json
#
# Collects the requirements artifact, design/build/verify paths recorded in Delivery
# approvals, and standard per-feature directories. Does not include secret files.
set -eu

feature=""
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || { printf 'usage: %s <feature> [--out <dir>]\n' "$0" >&2; exit 1; }
      out="$2"
      shift 2
      ;;
    -h|--help)
      printf 'usage: %s <feature> [--out <directory>]\n' "$0" >&2
      exit 0
      ;;
    *)
      feature="$1"
      shift
      ;;
  esac
done
[ -n "$feature" ] || { printf 'usage: %s <feature> [--out <dir>]\n' "$0" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

artifact="docs/agents-v0/requirements/${feature}.md"
[ -f "$artifact" ] || { printf 'FAIL: requirements artifact not found: %s\n' "$artifact" >&2; exit 1; }

if [ -z "$out" ]; then
  out="docs/agents-v0/release/${feature}"
fi
mkdir -p "$out"
manifest="${out}/audit-manifest.json"

FEATURE="$feature" ARTIFACT="$artifact" MANIFEST="$manifest" ROOT="$root" python3 - <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
import time

feature = os.environ["FEATURE"]
artifact = os.environ["ARTIFACT"]
manifest = os.environ["MANIFEST"]
root = os.environ["ROOT"]

SECRET_NAMES = {".env", "credentials.json", "secrets.yml", "secrets.yaml"}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def git_head():
    proc = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        cwd=root,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def approval_paths(path):
    text = open(path, encoding="utf-8").read()
    if "## Delivery approvals" not in text and "## delivery approvals" not in text.lower():
        return []
    section = re.split(r"(?mi)^#+[ \t]+delivery approvals", text, maxsplit=1)
    if len(section) < 2:
        return []
    body = re.split(r"(?m)^#+[ \t]+", section[1], maxsplit=1)[0]
    paths = set()
    for line in body.splitlines():
        if "|" not in line:
            continue
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cols) < 3:
            continue
        for token in re.findall(r"docs/[^\s`,|]+", cols[2]):
            token = token.rstrip(").,;")
            if ">" in token or "<" in token:
                continue
            paths.add(token)
    return sorted(paths)


def collect_tree(base_dir):
    found = []
    if not os.path.isdir(base_dir):
        return found
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "target")]
        for name in filenames:
            if name in SECRET_NAMES or name.startswith(".env"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            found.append(rel.replace("\\", "/"))
    return sorted(found)


candidates = set(approval_paths(artifact))
for prefix in (
    f"docs/agents-v0/design/{feature}",
    f"docs/agents-v0/build/{feature}",
    f"docs/agents-v0/verify/{feature}",
):
    for p in collect_tree(os.path.join(root, prefix)):
        candidates.add(p)
candidates.add(artifact.replace("\\", "/"))

entries = []
missing = []
for rel in sorted(candidates):
    abspath = os.path.join(root, rel)
    if not os.path.isfile(abspath):
        missing.append(rel)
        continue
    commit = ""
    proc = subprocess.run(
        ["git", "log", "-1", "--format=%H", "--", rel],
        capture_output=True,
        text=True,
        cwd=root,
    )
    if proc.returncode == 0:
        commit = proc.stdout.strip()
    entries.append(
        {
            "path": rel,
            "sha256": sha256_file(abspath),
            "bytes": os.path.getsize(abspath),
            "last_commit": commit,
        }
    )

pack = {
    "schema": "agents-v0-audit-manifest/1",
    "feature": feature,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "repo_head": git_head(),
    "requirements_artifact": artifact,
    "files": entries,
    "missing_paths": missing,
}

with open(manifest, "w", encoding="utf-8") as handle:
    json.dump(pack, handle, indent=2)
    handle.write("\n")

print(f"OK: wrote {manifest} ({len(entries)} files, {len(missing)} missing)")
if missing:
    for m in missing:
        print(f"WARN: missing {m}", file=sys.stderr)
PY
