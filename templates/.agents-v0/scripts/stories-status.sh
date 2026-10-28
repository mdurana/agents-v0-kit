#!/bin/sh
# stories-status.sh — read-only view of every story, maintenance note, and program record
# across the main checkout and all git worktrees.
#
# MEM-01: /v0-status used to read one checkout. A story in flight lives in its own worktree
# (../<repo>-<feature> on feature/<feature>, ../<repo>-maintain-<id> on maintain/<id>), so its
# current state.json is not visible from main. This script reads the state files in every
# worktree from `git worktree list` and prints one table. It writes no files and keeps no cache:
# each run reads the state files again.
#
# Usage:
#   sh .agents-v0/scripts/stories-status.sh [--json] [--all-copies] [--root <dir>]
#     --json        print a JSON array instead of the table
#     --all-copies  print every copy of a state file (one row per worktree that has it).
#                   Default: one row per story, read from the worktree on that story's branch
#                   (feature/<feature> or maintain/<id>) when one exists, otherwise from main.
#     --root <dir>  run as if started in <dir> (default: current directory)
#
# Reads:
#   docs/agents-v0/program.state.json
#   docs/agents-v0/onboarding/state.json
#   docs/agents-v0/requirements/<feature>.state.json
#   docs/agents-v0/maintain/<id>/state.json
# in each worktree (uncommitted working-tree content, which is what the phase agents write).
#
# Columns: story, kind, branch, worktree (relative to the main checkout), activePhase,
# activeStatus, lastApprovedPhase, verifyPassed, reopenCount, tier, blockedReason,
# lastCommit (YYYY-MM-DD: branch tip for a story read from its own worktree; otherwise the
# last commit that touched its state file), note (malformed JSON, missing state file, copies
# that disagree, missing worktree folder).
#
# Exit 0 always after printing, even when a state file is missing or malformed (those rows say
# so in the note column). Exit 2 only for a usage error.

set -eu

as_json=0
all_copies=0
root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) as_json=1; shift ;;
    --all-copies) all_copies=1; shift ;;
    --root)
      [ $# -ge 2 ] || { printf 'usage: %s [--json] [--all-copies] [--root <dir>]\n' "$0" >&2; exit 2; }
      root="$2"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--json] [--all-copies] [--root <dir>]\n' "$0"
      exit 0 ;;
    *)
      printf 'usage: %s [--json] [--all-copies] [--root <dir>]\n' "$0" >&2
      exit 2 ;;
  esac
done
if [ -n "$root" ]; then
  cd "$root" || { printf 'FAIL: --root not found: %s\n' "$root" >&2; exit 2; }
fi

SS_JSON="$as_json" SS_ALL="$all_copies" python3 - <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

as_json = os.environ.get("SS_JSON") == "1"
all_copies = os.environ.get("SS_ALL") == "1"


def git(args, cwd="."):
    """Run a read-only git command; return stdout or "" on any failure."""
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=False)
    except OSError:
        return ""
    return r.stdout if r.returncode == 0 else ""


# 1. Worktrees. The first entry of `git worktree list` is the main checkout.
worktrees = []  # dicts: path, branch, exists
porcelain = git(["worktree", "list", "--porcelain"])
cur = None
for line in porcelain.splitlines():
    if line.startswith("worktree "):
        cur = {"path": line[len("worktree "):], "branch": "", "exists": True}
        worktrees.append(cur)
    elif cur is not None and line.startswith("branch "):
        cur["branch"] = line[len("branch "):].replace("refs/heads/", "", 1)
    elif cur is not None and line == "detached":
        cur["branch"] = "(detached)"
    elif cur is not None and line.startswith("prunable"):
        cur["exists"] = False
if not worktrees:
    # Not a git repository (or git missing): read the current directory only.
    worktrees = [{"path": os.path.abspath("."), "branch": "", "exists": True, "nogit": True}]
for wt in worktrees:
    if not os.path.isdir(wt["path"]):
        wt["exists"] = False
main_path = worktrees[0]["path"]


def rel_wt(path):
    if path == main_path:
        return "."
    try:
        return os.path.relpath(path, main_path)
    except ValueError:
        return path


# 2. State files in each worktree.
FIELDS = ("activePhase", "activeStatus", "lastApprovedPhase", "verifyPassed", "reopenCount", "tier", "blockedReason")


def find_state_files(wt_path):
    base = Path(wt_path) / "docs" / "agents-v0"
    out = []
    if (base / "program.state.json").is_file():
        out.append(("program", "program", base / "program.state.json"))
    if (base / "onboarding" / "state.json").is_file():
        out.append(("onboarding", "onboarding", base / "onboarding" / "state.json"))
    req = base / "requirements"
    if req.is_dir():
        for p in sorted(req.glob("*.state.json")):
            if p.name.startswith("_"):
                continue  # _state.template.json
            out.append((p.name[: -len(".state.json")], "feature", p))
    mnt = base / "maintain"
    if mnt.is_dir():
        for p in sorted(mnt.glob("*/state.json")):
            if p.parent.name.startswith("_"):
                continue
            out.append((p.parent.name, "maintain", p))
    return out


def read_state(path):
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, f"unreadable: {exc.strerror or exc}"
    try:
        data = json.loads(raw)
    except ValueError as exc:
        where = f" (line {exc.lineno}, column {exc.colno})" if hasattr(exc, "lineno") else ""
        return None, f"malformed JSON{where}"
    if not isinstance(data, dict):
        return None, "malformed: top level is not an object"
    return data, ""


def last_commit(wt, path, own_branch):
    if wt.get("nogit"):
        return ""
    if own_branch:
        return git(["log", "-1", "--format=%cs"], cwd=wt["path"]).strip()
    rel = os.path.relpath(str(path), wt["path"])
    return git(["log", "-1", "--format=%cs", "--", rel], cwd=wt["path"]).strip()


def owner_branch(kind, story):
    if kind == "feature":
        return f"feature/{story}"
    if kind == "maintain":
        return f"maintain/{story}"
    return ""


copies = {}  # (kind, story) -> list of rows
for wt in worktrees:
    if not wt["exists"]:
        continue
    for story, kind, path in find_state_files(wt["path"]):
        data, err = read_state(path)
        own = bool(owner_branch(kind, story)) and wt["branch"] == owner_branch(kind, story)
        row = {
            "story": story,
            "kind": kind,
            "branch": wt["branch"],
            "worktree": rel_wt(wt["path"]),
            "stateFile": os.path.relpath(str(path), wt["path"]),
        }
        for f in FIELDS:
            row[f] = (data or {}).get(f, None) if data is not None else None
        row["lastCommit"] = last_commit(wt, path, own)
        row["note"] = err
        row["_own"] = own
        copies.setdefault((kind, story), []).append(row)

# Story branches whose worktree has no state file yet (e.g. intake doc not moved yet).
for wt in worktrees:
    b = wt["branch"]
    for prefix, kind in (("feature/", "feature"), ("maintain/", "maintain")):
        if b.startswith(prefix):
            story = b[len(prefix):]
            if (kind, story) in copies and any(r["_own"] for r in copies[(kind, story)]):
                continue
            note = "worktree folder missing (git worktree prune?)" if not wt["exists"] else "no state file in its worktree"
            row = {"story": story, "kind": kind, "branch": b, "worktree": rel_wt(wt["path"]),
                   "stateFile": "", "lastCommit": "", "note": note, "_own": True}
            for f in FIELDS:
                row[f] = None
            if wt["exists"] and not wt.get("nogit"):
                row["lastCommit"] = git(["log", "-1", "--format=%cs"], cwd=wt["path"]).strip()
            copies.setdefault((kind, story), []).append(row)


def summary(r):
    return tuple(json.dumps(r.get(f), sort_keys=True) for f in FIELDS)


kind_order = {"program": 0, "onboarding": 1, "feature": 2, "maintain": 3}
rows = []
for key in sorted(copies, key=lambda k: (kind_order.get(k[0], 9), k[1])):
    group = copies[key]
    if all_copies:
        rows.extend(group)
        continue
    # One row per story: its own worktree wins, then the main checkout, then the first copy found.
    pick = next((r for r in group if r["_own"]), None) \
        or next((r for r in group if r["worktree"] == "."), None) \
        or group[0]
    others = [r for r in group if r is not pick and r["stateFile"]]
    label = lambda r: "main checkout" if r["worktree"] == "." else r["worktree"]
    differ = [label(r) for r in others if not r["note"] and summary(r) != summary(pick)]
    notes = [pick["note"]] if pick["note"] else []
    if differ:
        notes.append("other copy differs: " + ", ".join(differ))
    bad = [label(r) for r in others if r["note"]]
    if bad:
        notes.append("unreadable copy in: " + ", ".join(bad))
    pick = dict(pick)
    pick["note"] = "; ".join(notes)
    rows.append(pick)

for r in rows:
    r.pop("_own", None)

if as_json:
    print(json.dumps(rows, indent=2))
    raise SystemExit(0)


def cell(v, width=None):
    if v is None:
        s = "-"
    elif isinstance(v, bool):
        s = "true" if v else "false"
    else:
        s = str(v) if str(v) != "" else "-"
    s = s.replace("\n", " ").replace("|", "/")
    if width and len(s) > width:
        s = s[: width - 1] + "…"
    return s


cols = [("story", "story", 28), ("kind", "kind", 10), ("branch", "branch", 30), ("worktree", "worktree", 30),
        ("activePhase", "activePhase", 12), ("activeStatus", "activeStatus", 17),
        ("lastApprovedPhase", "lastApproved", 12), ("verifyPassed", "verifyPassed", 12),
        ("reopenCount", "reopens", 7), ("tier", "tier", 9), ("blockedReason", "blockedReason", 40),
        ("lastCommit", "lastCommit", 10), ("note", "note", 60)]
print(f"Stories across {sum(1 for w in worktrees if w['exists'])} checkout(s) (main: {main_path}); read-only, nothing stored.")
if worktrees[0].get("nogit"):
    print("note: not a git repository; read the current directory only.")
gone = [rel_wt(w["path"]) for w in worktrees if not w["exists"]]
if gone:
    print("note: worktree folder missing: " + ", ".join(gone))
if not rows:
    print("No state files found (docs/agents-v0/program.state.json, onboarding/state.json, requirements/*.state.json, maintain/*/state.json).")
    raise SystemExit(0)
table = [[cell(r.get(k), w) for k, _, w in cols] for r in rows]
widths = [max(len(h), *(len(t[i]) for t in table)) for i, (_, h, _) in enumerate(cols)]
print("| " + " | ".join(h.ljust(widths[i]) for i, (_, h, _) in enumerate(cols)) + " |")
print("|" + "|".join("-" * (w + 2) for w in widths) + "|")
for t in table:
    print("| " + " | ".join(t[i].ljust(widths[i]) for i in range(len(cols))) + " |")
PY
