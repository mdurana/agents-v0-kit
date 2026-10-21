#!/bin/sh
# test-update-agents-model.sh — model-config.json matches the routing matrix,
# and update-agents-model.sh rewrites installed agent frontmatter and the matrix.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KIT"

MATRIX="templates/docs/agents-v0/model-routing-matrix.md"

python3 - "$MATRIX" <<'PY'
import json, re, sys
from pathlib import Path

matrix_path = Path(sys.argv[1])
matrix = matrix_path.read_text(encoding="utf-8")
head = matrix.split("## Critical units", 1)[0]
role_key = {
    "plan": "plan",
    "build": "build",
    "review": "review",
    "explore": "explore",
    "debug": "debug",
    "schemas": "schemas",
    "docs": "docs",
    "documenter": "documenter",
    "orchestrator": "orchestrator",
    "ux designer": "ux-designer",
}
found = {}
critical = ""
for line in head.splitlines():
    if not line.startswith("|"):
        continue
    cols = [col.strip() for col in line.strip().strip("|").split("|")]
    if len(cols) < 3:
        continue
    role = re.sub(r"[*_]", "", cols[0]).strip().lower()
    if not role or role == "role" or set(role) <= set("-: "):
        continue
    if role == "build (critical)":
        if "plan model" not in cols[2].lower():
            raise SystemExit("Build (critical) must name the Plan model")
        critical = "plan"
        continue
    match = re.search(r"`([^`]+)`", cols[2])
    if not match:
        raise SystemExit(f"role row has no Cursor ID: {role}")
    model = match.group(1)
    key = role_key.get(role)
    if not key:
        raise SystemExit(f"unknown role row in model-routing-matrix.md: {role}")
    found[key] = model
if not critical:
    raise SystemExit("matrix is missing the Build (critical) row")

path = Path("templates/.cursor/model-config.json")
data = json.loads(path.read_text(encoding="utf-8"))
if set(data) != set(found):
    raise SystemExit(f"{path} keys {sorted(data)} != matrix roles {sorted(found)}")
for key, model in found.items():
    if data[key] != model:
        raise SystemExit(f"{path} {key}={data[key]!r} != matrix {model!r}")

section = matrix.split("## Kit agent mapping", 1)[1].split("## Skill-launched", 1)[0]
roles = set()
for line in section.splitlines():
    if not line.startswith("|"):
        continue
    cols = [col.strip() for col in line.strip().strip("|").split("|")]
    if len(cols) < 2:
        continue
    agent = cols[0].strip()
    if not agent or agent == "Kit agent" or set(agent) <= set("-: "):
        continue
    role_label = re.sub(r"[*_]", "", cols[1]).strip().lower()
    key = role_key.get(role_label)
    if not key:
        raise SystemExit(f"unknown kit agent role label: {cols[1]}")
    roles.add(key)
missing = roles - set(found)
if missing:
    raise SystemExit(f"model-config.json is missing roles used by kit agents: {sorted(missing)}")
print("model-config.json matches the routing matrix")
PY

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/.cursor"
python3 - "$tmp/.cursor/model-config.json" <<'PY'
import json, sys
from pathlib import Path
cfg = json.loads(Path("templates/.cursor/model-config.json").read_text(encoding="utf-8"))
cfg["plan"] = "remap-plan-model"
cfg["ux-designer"] = "remap-ux-model"
Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PY

sh "$KIT/scripts/install.sh" "$tmp" >/dev/null
[ -x "$tmp/.agents-v0/scripts/update-agents-model.sh" ]
[ -f "$tmp/docs/agents-v0/model-routing-matrix.md" ]
grep -Fq 'model: remap-plan-model' "$tmp/.cursor/agents/program-planner.md"
grep -Fq 'model: remap-plan-model' "$tmp/.cursor/agents/requirements-analyst.md"
grep -Fq 'model: remap-ux-model' "$tmp/.cursor/agents/ux-designer.md"
grep -Fq 'model: composer-2.5[fast=false]' "$tmp/.cursor/agents/backend-engineer.md"
grep -Fq 'model: grok-4.7[context=500k,reasoning_effort=high,fast=false]' "$tmp/.cursor/agents/code-reviewer.md"
grep -Fq '`remap-plan-model`' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '| backend-engineer     | Build        |' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '| ux-design                           | UX Designer | UX spec authoring                | `remap-ux-model`' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '| **Build (critical)** | units that hit a security-review trigger, and sagas or consumers | the Plan model' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '`codebase-documenter` writes the report' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '| **Orchestrator**     | `/v0-deliver` and `/v0-status`. `/v0-onboard` is routed here; `codebase-documenter` writes the report | `composer-2.5[fast=false]`' "$tmp/docs/agents-v0/model-routing-matrix.md"

KIT_MODEL_BUILD='remap-build-model' sh "$tmp/.agents-v0/scripts/update-agents-model.sh" >/dev/null
grep -Fq 'model: remap-build-model' "$tmp/.cursor/agents/backend-engineer.md"
grep -Fq 'model: remap-build-model' "$tmp/.cursor/agents/maintenance-engineer.md"
grep -Fq 'model: remap-plan-model' "$tmp/.cursor/agents/program-planner.md"
grep -Fq '| backend-engineer     | Build        |' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '| **Build**            | services, BFF, frontend, tests, maintenance, release             | `remap-build-model`' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '| contract-first-design, quality-gate | Schemas     | schemas + single-file unit tests | `composer-2.5[fast=false]`' "$tmp/docs/agents-v0/model-routing-matrix.md"
grep -Fq '`codebase-documenter` writes the report' "$tmp/docs/agents-v0/model-routing-matrix.md"

plain="$(mktemp -d)"
trap 'rm -rf "$tmp" "$plain"' EXIT
sh "$KIT/scripts/install.sh" "$plain" >/dev/null
grep -Fq 'model: grok-4.7[context=500k,reasoning_effort=high,fast=false]' "$plain/.cursor/agents/program-planner.md"
rm -f "$plain/.cursor/model-config.json"
if sh "$plain/.agents-v0/scripts/update-agents-model.sh" >/dev/null 2>&1; then
  printf 'FAIL: update-agents-model.sh should fail when model-config.json is missing\n' >&2
  exit 1
fi

printf 'update-agents-model.sh ok\n'
