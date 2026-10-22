#!/bin/sh
# check-story-dependencies.sh — deterministic milestone dependency gate for /v0-build.
# Every story ID in this story's Dependency column (docs/agents-v0/milestones/*.md) must have
# a state file with `verify` in approvedPhases and verifyPassed: true. A missing state file,
# a missing manifest row, or a commented-out approval row means NOT verified. Code already on
# the integration branch, a scaffold, or a "planned" status never counts as verified.
#
# Usage:
#   sh .agents-v0/scripts/check-story-dependencies.sh docs/agents-v0/requirements/<feature>.md
#
# Exit 0: no `Story:` line (not a milestone story), the story has no dependencies, or all are verified.
# Exit 1: a dependency is not verified, or the story is missing from every manifest. The first
#         line names the dependency; the printed `Next:` line is the exact blocked-state command.
# Exit 2: usage error.
set -eu

art="${1:-}"
if [ -z "$art" ] || [ ! -f "$art" ]; then
  printf 'usage: %s docs/agents-v0/requirements/<feature>.md\n' "$0" >&2
  exit 2
fi

ART="$art" python3 - <<'PY'
import json, os, re, sys
from pathlib import Path

art = os.environ["ART"]
text = re.sub(r"<!--.*?-->", "", open(art, encoding="utf-8").read(), flags=re.S)
m = re.search(r"^\s*Story:\s*([A-Za-z0-9][A-Za-z0-9-]*)\s*$", text, re.M)
if not m:
    print(f"OK: {art} has no Story: line (not a milestone story)")
    raise SystemExit(0)
story = m.group(1).upper()

root = Path("docs/agents-v0/milestones")
rows = {}
if root.is_dir():
    for man in sorted(root.glob("*.md")):
        if man.name.startswith("_") or man.name == "plan.md":
            continue
        clean = re.sub(r"<!--.*?-->", "", man.read_text(encoding="utf-8", errors="replace"), flags=re.S)
        header = None
        for line in clean.splitlines():
            s = line.strip()
            if not s.startswith("|"):
                header = None
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            low = [c.lower() for c in cells]
            if "story id" in low and "dependency" in low:
                header = low
                continue
            if header is None or set(s.replace("|", "").strip()) <= set("-: "):
                continue
            rec = dict(zip(header, cells))
            sid = rec.get("story id", "").strip("` ").upper()
            if sid:
                rows[sid] = (rec, str(man))

def blocked(dep, why):
    print(f"FAIL: Dependency {dep} not verified ({why})", file=sys.stderr)
    print("Do not start Build, do not create a branch, and do not reason around this check.", file=sys.stderr)
    print(f'Next: sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status blocked '
          f'--reason "Dependency {dep} not verified" {art}', file=sys.stderr)
    raise SystemExit(1)

if story not in rows:
    print(f"FAIL: Story {story} is not in any docs/agents-v0/milestones/*.md Stories table", file=sys.stderr)
    print(f'Next: sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status blocked '
          f'--reason "Story {story} not in a milestone manifest" {art}', file=sys.stderr)
    raise SystemExit(1)

rec, man = rows[story]
deps_cell = rec.get("dependency", "")
deps = [d.strip("` ").upper() for d in re.split(r"[,;/ ]+", deps_cell) if d.strip("` ")]
deps = [d for d in deps if d not in ("—", "-", "NONE", "N/A", "NA")]
if not deps:
    print(f"OK: {story} has no dependencies ({man})")
    raise SystemExit(0)

for dep in deps:
    if dep not in rows:
        blocked(dep, f"not in any milestone manifest")
    dep_art = rows[dep][0].get("feature artifact", "").strip("` ")
    if not dep_art.endswith(".md"):
        blocked(dep, "manifest row has no Feature artifact")
    state = Path(dep_art[:-3] + ".state.json")
    if not state.is_file():
        blocked(dep, f"{state} does not exist")
    try:
        data = json.loads(state.read_text(encoding="utf-8"))
    except ValueError:
        blocked(dep, f"{state} is not valid JSON")
    if "verify" not in (data.get("approvedPhases") or []) or data.get("verifyPassed") is not True:
        blocked(dep, f"{state}: approvedPhases={data.get('approvedPhases')}, verifyPassed={data.get('verifyPassed')}")
print(f"OK: dependencies verified for {story}: {', '.join(deps)}")
PY
