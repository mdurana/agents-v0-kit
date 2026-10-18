#!/bin/sh
# check-frontend-calls.sh — the frontend calls only operations the org catalog lists.
#
# Usage: sh .agents-v0/ci/check-frontend-calls.sh [<catalog>...]
# Catalogs default to openapi/*.yaml, openapi/*.yml, openapi/*.json. The frontend roots come from
# ci/resolve-layout.sh (FRONTEND_ROOT, else frontend/, else the repo root when it has a
# package.json). Every string literal that starts with /api/ in a source file (not a test) must
# match a catalog path: a {param} in the catalog matches one segment, and ${...} in a template
# literal matches a {param}. A literal that ends in "/" (concatenated with an id) matches a catalog
# path with one more segment. FRONTEND_CALLS_IGNORE is a regular expression of paths to skip
# (a third-party API under /api/, for example).
# Needs python3 and, for YAML catalogs, PyYAML.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

roots=""
if [ -f "$here/resolve-layout.sh" ]; then
  eval "$(sh "$here/resolve-layout.sh")"
  roots="${FRONTEND_ROOT:-}"
else
  if [ -d frontend ]; then roots="frontend"; elif [ -f package.json ]; then roots="."; fi
fi
if [ -z "$roots" ]; then
  printf 'OK: no frontend root, nothing to check\n'
  exit 0
fi

CATALOGS="$(printf '%s\n' "$@")" ROOTS="$roots" python3 - <<'PY'
import glob
import json
import os
import re
import sys

roots = os.environ["ROOTS"].split()
catalogs = [c for c in os.environ["CATALOGS"].splitlines() if c]
if not catalogs:
    catalogs = sorted(glob.glob("openapi/*.yaml") + glob.glob("openapi/*.yml") + glob.glob("openapi/*.json"))
ignore = os.environ.get("FRONTEND_CALLS_IGNORE")
SKIP = {"node_modules", "target", ".git", "dist", "build", ".svelte-kit", ".next", "docs", "coverage", ".venv", "venv", "__pycache__", "bin", "obj"}
TEST = re.compile(r"\.(test|spec)\.[A-Za-z]+$|(^|/)(__tests__|e2e|tests?)/")


def load(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if path.endswith(".json"):
        return json.loads(text)
    import yaml
    return yaml.safe_load(text)


if not catalogs:
    print("FAIL: no catalog found (openapi/*.yaml); the frontend has nothing to be checked against", file=sys.stderr)
    raise SystemExit(1)
try:
    cat_paths = []
    for c in catalogs:
        doc = load(c) or {}
        srv = [str((s or {}).get("url") or "").rstrip("/") for s in (doc.get("servers") or []) if isinstance(s, dict)]
        pfx = "/api/v1" if srv and all(u.endswith("/api/v1") for u in srv) else ""
        for p in (doc.get("paths") or {}).keys():
            cat_paths.append(pfx + (p if p.startswith("/") else "/" + p) if pfx and not p.startswith("/api/v1") else p)
except ImportError:
    print("FAIL: PyYAML is required for YAML catalogs (python3 -m pip install pyyaml, apk add py3-yaml, or on Intel macOS: sh .agents-v0/scripts/host-tools-macports.sh)", file=sys.stderr)
    raise SystemExit(1)
cat_segs = [[s for s in p.strip("/").split("/")] for p in cat_paths]


def matches(literal):
    trailing = literal.endswith("/")
    segs = [s for s in literal.strip("/").split("/")]
    for cs in cat_segs:
        if trailing:
            ok = len(cs) in (len(segs) + 1, len(segs)) and len(cs) >= len(segs)
            n = len(segs)
        else:
            ok, n = len(cs) == len(segs), len(segs)
        if not ok:
            continue
        if all(a == b or (a.startswith("{") and a.endswith("}")) or b == "{}" for a, b in zip(cs[:n], segs)):
            return True
    return False


LITERAL = re.compile(r"""["'`](/api/[^"'`\s)?#]*)""")
unmatched, calls = [], 0
for root in roots:
    for dirpath, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP]
        for name in names:
            full = os.path.join(dirpath, name)
            if not name.endswith((".ts", ".tsx", ".js", ".jsx", ".svelte", ".vue")) or TEST.search(full.replace(os.sep, "/")):
                continue
            with open(full, encoding="utf-8", errors="replace") as handle:
                for i, line in enumerate(handle, 1):
                    for m in LITERAL.finditer(line):
                        path = re.sub(r"\$\{[^}]*\}", "{}", m.group(1))
                        if ignore and re.search(ignore, path):
                            continue
                        calls += 1
                        if not matches(path):
                            unmatched.append(f"{os.path.normpath(full)}:{i}  {path}")
if unmatched:
    for item in unmatched:
        print(f"FAIL: {item} is not an operation in the catalog ({', '.join(catalogs)})", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: {calls} frontend /api call(s) match the catalog")
PY
