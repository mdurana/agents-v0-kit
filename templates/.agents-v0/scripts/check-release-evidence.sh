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
#         A squash merge (kitfix-20261031-gate-commit: trailers Story-Branch / Story-Tip on the integration
#         branch) counts as merged when the branch still ends at Story-Tip and the squash holds its files.
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
# P0-A (no feature branch) has nothing to check; a deleted branch (not allowed: kitfix-20261031-keep-branches) only WARNs.
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
    # kitfix-20261031-gate-commit: the kit squash-merges. A squash commit on the integration branch carries
    # "Story-Branch: feature/<feature>" and "Story-Tip: <sha>"; the branch must still end at that tip and the
    # squash commit must hold the branch's files (outside docs/agents-v0/, which the release approval edits).
    tip = git("rev-parse", branch).stdout.strip()
    squash = None
    for rec in git("log", "--first-parent", "--format=%H%x1f%B%x1e", integration).stdout.split("\x1e"):
        if "\x1f" not in rec: continue
        sha, body = rec.strip("\n").split("\x1f", 1)
        if re.search(rf"^Story-Branch:\s*{re.escape(branch)}\s*$", body, re.M):
            m = re.search(r"^Story-Tip:\s*([0-9a-f]{7,40})\s*$", body, re.M)
            squash = (sha, m.group(1) if m else "")
            break
    if squash and git("merge-base", "--is-ancestor", branch, integration).returncode != 0:
        sha, stip = squash
        if not stip or not tip.startswith(stip):
            ahead = git("rev-list", "--oneline", f"{stip}..{branch}").stdout.strip().splitlines() if stip else []
            print(f"FAIL: {slug} was squash-merged at {sha[:12]} from {branch}@{(stip or '?')[:12]}, but {branch} now ends at "
                  f"{tip[:12]} ({len(ahead)} commit(s) after the squash):", file=sys.stderr)
            for line in ahead[:10]:
                print(f"  - {line}", file=sys.stderr)
            print(f"Do not commit to {branch} after the release, do not merge it again, and do not name the next story; "
                  f"the human decides how to reconcile it.", file=sys.stderr)
            raise SystemExit(1)
        base = git("merge-base", f"{sha}^", tip).stdout.strip()
        differ = [p for p in git("diff", "--name-only", base, tip).stdout.splitlines()
                  if p and not p.startswith("docs/agents-v0/")
                  and git("diff", "--quiet", sha, tip, "--", p).returncode != 0]
        if differ:
            print(f"FAIL: squash commit {sha[:12]} of {branch} does not hold the branch's version of: "
                  + ", ".join(differ[:10]), file=sys.stderr)
            raise SystemExit(1)
        print(f"OK: release evidence present for {slug} (squash-merged at {sha[:12]})")
        raise SystemExit(0)
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
# kitfix-20261031-keep-branches: story branches are kept after release. When feature/<feature> is gone the
#   squash/merge cross-check above cannot run; say so (exit code unchanged, so old projects that deleted
#   their branches still pass).
if git("rev-parse", "--is-inside-work-tree").returncode == 0 \
        and git("show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode != 0 \
        and art.parent.name == "requirements" and not slug.startswith("p0-a") \
        and not re.search(r"^Story:\s*P0-A\b", art.read_text(encoding="utf-8", errors="replace"), re.M):
    print(f"WARN: {branch} not found: the squash/merge cross-check was skipped. Story branches are kept after "
          f"release (never delete them); restore the branch from its Story-Tip if it was deleted.", file=sys.stderr)
print(f"OK: release evidence present for {slug}")
PY
