#!/bin/sh
# check-release-evidence.sh — before /v0-status (or any command) calls a story "complete",
# cross-check that `release` in approvedPhases is backed by evidence on disk. The state file
# alone is self-attested: `sync-feature-state.sh --approve release` backfills every phase.
#
# Usage:
#   sh .agents-v0/scripts/check-release-evidence.sh docs/agents-v0/requirements/<feature>.md
#
# Exit 0: release is approved and the evidence agrees, or release is not approved (nothing to check).
# Exit 1: release is approved but the evidence does not support it. Report the state as
#         "unsupported by evidence", do not call the story complete, do not name a next story,
#         and tell the user to restore the state file (the kit cannot re-open a released story).
#         Also exit 1 when feature/<feature> still exists and is not fully merged into the
#         integration branch (resolve-integration-branch.sh): commits were made on the feature
#         branch after the merge (kitfix-20261029-step4-p1e). Report it; the human decides how to reconcile.
set -eu

art="${1:-}"
if [ -z "$art" ] || [ ! -f "$art" ]; then
  printf 'usage: %s docs/agents-v0/requirements/<feature>.md\n' "$0" >&2
  exit 2
fi

ART="$art" RESOLVER="$(dirname "$0")/resolve-integration-branch.sh" python3 - <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

art = Path(os.environ["ART"])
slug = art.stem
state = Path(str(art)[:-3] + ".state.json")
if not state.is_file():
    print(f"OK: no state file for {slug}")
    raise SystemExit(0)
data = json.loads(state.read_text(encoding="utf-8"))
if "release" not in (data.get("approvedPhases") or []):
    print(f"OK: release not approved for {slug} (nothing to cross-check)")
    raise SystemExit(0)

missing = []
if data.get("verifyPassed") is not True:
    missing.append("verifyPassed is not true")
qg = Path(f"docs/agents-v0/verify/{slug}/quality-gate.md")
if not qg.is_file():
    missing.append(f"{qg} missing")
plan = Path(f"docs/agents-v0/build/{slug}/plan.md")
if plan.is_file() and re.search(r"^\|[^|\n]*\|\s*pending\s*\|", plan.read_text(encoding="utf-8"), re.M | re.I):
    missing.append(f"{plan} still has pending rows")
text = re.sub(r"<!--.*?-->", "", art.read_text(encoding="utf-8"), flags=re.S)
has_row = re.search(r"^\|\s*release\s*\|[^|\n]*\|[^|\n]*\|\s*approved\b", text, re.M | re.I)
pr = Path(str(art)[:-3] + ".phase-result.md")
pr_ok = pr.is_file() and re.search(r"^\s*status:\s*approved\b", pr.read_text(encoding="utf-8"), re.M | re.I)
if not has_row and not pr_ok:
    missing.append("no uncommented Approved release row in Delivery approvals and no approved phase-result")

if missing:
    print(f"FAIL: {slug} has release in approvedPhases, but the evidence does not support it:", file=sys.stderr)
    for item in missing:
        print(f"  - {item}", file=sys.stderr)
    print("Report the state as unsupported by evidence. Do not call it complete or name the next story. "
          "The human restores the state file; sync-feature-state.sh cannot re-open a released story.", file=sys.stderr)
    raise SystemExit(1)

# kitfix-20261029-step4-p1e: a released story's branch must be fully contained in the integration branch.
# P0-A (no feature branch) and a branch deleted after the merge have nothing to check.
def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False)

branch = f"feature/{slug}"
if git("rev-parse", "--is-inside-work-tree").returncode == 0 \
        and git("show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0:
    resolver = os.environ["RESOLVER"]
    if not os.path.isfile(resolver):
        print(f"FAIL: {resolver} is missing; cannot check that {branch} is merged", file=sys.stderr)
        raise SystemExit(1)
    integration = subprocess.run(["sh", resolver], capture_output=True, text=True, check=False).stdout.strip() or "HEAD"
    if git("merge-base", "--is-ancestor", branch, integration).returncode != 0:
        ahead = git("rev-list", "--oneline", f"{integration}..{branch}").stdout.strip().splitlines()
        print(f"FAIL: {slug} is released, but {branch} is not fully merged into {integration} "
              f"({len(ahead)} commit(s) on {branch} only):", file=sys.stderr)
        for line in ahead[:10]:
            print(f"  - {line}", file=sys.stderr)
        print(f"Report the story as not cleanly released. Do not commit to {branch} after the merge, "
              f"do not merge it again, and do not name the next story; the human decides how to "
              f"reconcile {branch} with {integration}.", file=sys.stderr)
        raise SystemExit(1)
print(f"OK: release evidence present for {slug}")
PY
