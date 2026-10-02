#!/bin/sh
# check-ux-spec.sh — the UX spec and its static mockups agree (ux-design.mdc).
#
# Usage: sh .agents-v0/ci/check-ux-spec.sh <feature>
# Reads docs/agents-v0/design/<feature>/ux-spec.md, mockups/*.html, and the contract draft openapi.yaml.
# The component table (columns Component, Screen, Mockup, Operation, Default behavior, Override)
# and the mockups must agree:
#   - every row's mockup file exists and its Default behavior is not empty;
#   - every row's Operation is "—" or names an operationId (or an /api/v1 path) of the draft;
#   - every interactive element in a mockup (a[href], button, input except hidden, select,
#     textarea, summary, role=button|link|tab|menuitem|checkbox|switch) carries data-component="Name";
#   - every such Name has a row, and every row's Component appears in its own mockup;
#   - every mockup is referenced by a row or named in the spec;
#   - a mockup does not call the API (no fetch, XMLHttpRequest, axios).
# A no-UI story has no ux-spec.md: the script passes and says so.

set -eu

feature="${1:-}"
[ -n "$feature" ] || { printf 'usage: %s <feature>\n' "$0" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

FEATURE="$feature" python3 - <<'PY'
import os
import re
import sys
from html.parser import HTMLParser

feature = os.environ["FEATURE"]
base = os.path.join("docs", "agents-v0", "design", feature)
spec_path = os.path.join(base, "ux-spec.md")
failures = []


def fail(msg):
    failures.append(msg)


if not os.path.isfile(spec_path):
    print(f"OK: no {spec_path} (a no-UI story has no UX spec)")
    raise SystemExit(0)

with open(spec_path, encoding="utf-8") as handle:
    spec = handle.read()

# --- component table -------------------------------------------------------
rows, header = [], None
for line in spec.splitlines():
    if not line.strip().startswith("|"):
        header = None if not line.strip() else header
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    lowered = [c.lower() for c in cells]
    if "component" in lowered and "mockup" in lowered and "operation" in lowered:
        header = lowered
        continue
    if header is None or all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
        continue
    rows.append(dict(zip(header, cells)))

if not rows:
    fail(f"{spec_path}: no component table (columns Component, Screen, Mockup, Operation, Default behavior, Override)")


def clean(text):
    return re.sub(r"[`*]", "", text or "").strip()


def norm(name):
    return re.sub(r"\s+", " ", clean(name)).lower()


draft_text = ""
for name in ("openapi.yaml", "openapi.yml", "openapi.json"):
    p = os.path.join(base, name)
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as handle:
            draft_text = handle.read()
        break
op_ids = set(re.findall(r"""["']?operationId["']?\s*:\s*["']?([\w.\-]+)""", draft_text))

INTERACTIVE_ROLES = {"button", "link", "tab", "menuitem", "checkbox", "switch"}


class Scan(HTMLParser):
    def __init__(self):
        super().__init__()
        self.names, self.missing, self.api_calls = set(), [], 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        interactive = (
            (tag == "a" and "href" in a) or tag in ("button", "select", "textarea", "summary")
            or (tag == "input" and a.get("type", "").lower() != "hidden")
            or a.get("role", "").lower() in INTERACTIVE_ROLES
        )
        if not interactive:
            return
        if a.get("data-component"):
            self.names.add(norm(a["data-component"]))
        else:
            self.missing.append(f"<{tag}{(' ' + a['id']) if a.get('id') else ''}>")


mockup_names, referenced = {}, set()
for row in rows:
    comp = clean(row.get("component"))
    mock = clean(row.get("mockup"))
    where = f"{spec_path}: row '{comp or '?'}'"
    if not comp:
        fail(f"{spec_path}: a component row has no Component name")
    if not clean(row.get("default behavior")):
        fail(f"{where}: Default behavior is empty")
    op = clean(row.get("operation"))
    if op and op not in ("—", "-", "–", "n/a", "N/A"):
        tokens = re.findall(r"[\w.\-]+|/api/v1/\S+", op)
        if not (set(tokens) & op_ids or any(t.startswith("/api/v1/") and t in draft_text for t in tokens)):
            fail(f"{where}: operation '{op}' is not in the contract draft")
    if not mock or mock in ("—", "-"):
        fail(f"{where}: no Mockup")
        continue
    mock_path = mock if os.path.exists(mock) else os.path.join(base, mock)
    if not os.path.isfile(mock_path):
        mock_path = os.path.join(base, "mockups", os.path.basename(mock))
    if not os.path.isfile(mock_path):
        fail(f"{where}: mockup does not exist: {mock}")
        continue
    referenced.add(os.path.abspath(mock_path))
    if mock_path not in mockup_names:
        with open(mock_path, encoding="utf-8", errors="replace") as handle:
            html = handle.read()
        scan = Scan()
        scan.feed(html)
        mockup_names[mock_path] = scan.names
        for bad in scan.missing:
            fail(f"{mock_path}: interactive element {bad} has no data-component")
        if re.search(r"\bfetch\s*\(|XMLHttpRequest|\baxios\b", html):
            fail(f"{mock_path}: a mockup does not call the API")
    if comp and norm(comp) not in mockup_names[mock_path]:
        fail(f"{where}: no element data-component=\"{comp}\" in {mock_path}")

row_names = {norm(r.get("component")) for r in rows}
for path, names in mockup_names.items():
    for name in sorted(names - row_names):
        fail(f"{path}: data-component=\"{name}\" has no row in the component table")

mock_dir = os.path.join(base, "mockups")
if os.path.isdir(mock_dir):
    for name in sorted(os.listdir(mock_dir)):
        full = os.path.abspath(os.path.join(mock_dir, name))
        if name.endswith(".html") and full not in referenced and name not in spec:
            fail(f"{mock_dir}/{name}: not referenced by a row or the spec")

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: ux spec and mockups agree for {feature} ({len(rows)} component rows)")
PY
