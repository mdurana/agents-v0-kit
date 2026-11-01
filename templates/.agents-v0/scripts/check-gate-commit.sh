#!/bin/sh
# check-gate-commit.sh — one commit per approved gate (kitfix-20261031-gate-commit).
# After every `--approve <phase>` the agent commits that phase's work before the next phase starts:
#   feature story  -> on feature/<feature> (intake is committed in the branch turn, in the new worktree);
#   P0-A, onboarding and program phases (roadmap, architecture, plan) -> on the integration branch;
#   release        -> the story branch gets its "<story>: release approved" commit, then the integration
#                     branch gets ONE squash commit of feature/<feature> (git merge --squash) with trailers
#                     Story-Branch: feature/<feature> and Story-Tip: <branch tip sha>.
# Never amend a gate commit; a revision is a new commit (and, for project phases, a new tag).
#
# Usage:
#   sh .agents-v0/scripts/check-gate-commit.sh <artifact>
#        before a new phase starts (sync-feature-state.sh runs it on --active-phase X --status in_progress):
#        exit 1 when the last approved phase is not committed (state file untracked or changed since HEAD,
#        or the working tree has uncommitted changes).
#   sh .agents-v0/scripts/check-gate-commit.sh --release <artifact>
#        in the integration checkout, after `git merge --squash feature/<feature>` and before
#        `--approve release` (sync-feature-state.sh runs it): the branch's committed state has verify approved,
#        verifyPassed true and release awaiting approval, its worktree is clean, and the index holds the branch.
#   sh .agents-v0/scripts/check-gate-commit.sh --message <phase> <artifact>
#        print the gate commit command for <phase>; for release (non-P0-A feature story) it also writes the
#        squash commit message with its trailers to a file in the git dir and prints `git commit -F <file>`.
# Ignored paths: *.lock, and (kit test copies only) every prefix in AGENTS_V0_COMMIT_CHECK_IGNORE (space-separated).
# AGENTS_V0_SKIP_COMMIT_CHECK=1 skips the checks in the kit's own test copies only; install.sh removes both
# env reads, so an installed copy always checks (kitfix-20261031-installed-no-overrides).
set -eu

mode=check
phase=""
case "${1:-}" in
  --release) mode=release; shift ;;
  --message) mode=message; phase="${2:-}"; shift 2 || true ;;
  -h|--help) sed -n '2,24p' "$0"; exit 2 ;;
esac
art="${1:-}"
if [ -z "$art" ] || [ ! -f "$art" ]; then
  printf 'usage: %s [--release | --message <phase>] <artifact>\n' "$0" >&2
  exit 2
fi
gc_skip=0
# >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
[ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gc_skip=1
# <<< kit-test-override
if [ "$mode" != message ] && [ "$gc_skip" = 1 ]; then
  printf 'OK: gate-commit check skipped (kit test override)\n'
  exit 0
fi
command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'OK: not a git work tree (nothing to check)\n'; exit 0; }

GC_MODE="$mode" GC_PHASE="$phase" GC_ART="$art" GC_HERE="$(dirname "$0")" python3 - <<'PYGC'
import json, os, re, subprocess, sys

mode, phase, art = os.environ["GC_MODE"], os.environ["GC_PHASE"].lower(), os.environ["GC_ART"].replace("\\", "/")
here = os.environ["GC_HERE"]
slug = os.path.basename(art)[:-3] if art.endswith(".md") else os.path.basename(art)

def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True, check=False)

def rel(p):
    top = git("rev-parse", "--show-toplevel").stdout.strip()
    return os.path.relpath(os.path.abspath(p), top).replace("\\", "/") if top else p

if "/requirements/" in "/" + art:
    state = re.sub(r"\.md$", ".state.json", art); kind = "feature"
elif "/onboarding/" in "/" + art:
    state = os.path.join(os.path.dirname(art), "state.json"); kind = "onboarding"
elif "/maintain/" in "/" + art:
    state = os.path.join(os.path.dirname(art), "state.json"); kind = "maintain"
else:
    m = re.search(r"(.*?)docs/agents-v0/", art)
    state = (m.group(1) if m else "") + "docs/agents-v0/program.state.json"; kind = "program"
state_rel = rel(state)

def story_id():
    if kind == "program": return "program"
    if kind == "onboarding": return "onboarding"
    if kind == "maintain": return "maintain/" + os.path.basename(os.path.dirname(art))
    text = open(art, encoding="utf-8").read()
    m = re.search(r"^\s*(?:\*\*)?Story(?:\*\*)?:\s*(?:\*\*)?`?([A-Z][A-Z0-9]*-[A-Z0-9]+)", text, re.M)
    if m: return m.group(1)
    top = git("rev-parse", "--show-toplevel").stdout.strip()
    mdir = os.path.join(top, "docs/agents-v0/milestones")
    if os.path.isdir(mdir):
        for f in sorted(os.listdir(mdir)):
            if not f.endswith(".md"): continue
            for line in open(os.path.join(mdir, f), encoding="utf-8"):
                if f"requirements/{slug}.md" in line and line.strip().startswith("|"):
                    cell = line.strip().strip("|").split("|")[0].strip().strip("`* ")
                    if cell: return cell
    return slug

def p0a():
    if slug.startswith("p0-a"): return True
    try: text = open(art, encoding="utf-8").read()
    except OSError: return False
    return bool(re.search(r"^\s*(\*\*)?Story(\*\*)?:\s*(\*\*)?P0-A([^A-Za-z0-9]|$)", text, re.M | re.I))

ignore = []
# >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
ignore = [p for p in os.environ.get("AGENTS_V0_COMMIT_CHECK_IGNORE", "").split() if p]
# <<< kit-test-override
SECRET = re.compile(r"(^|/)(\.env(\.[^/]*)?|[^/]*\.(pem|key|p12|pfx|jks|keystore)|id_(rsa|ed25519|ecdsa)|credentials[^/]*\.json|secrets\.ya?ml)$")
SECRET_OK = re.compile(r"\.env\.(example|sample|template|dist)$|\.example$")

def dirty(cwd=None):
    out = subprocess.run(["git", *(["-C", cwd] if cwd else []), "status", "--porcelain=v1", "-uall"],
                         capture_output=True, text=True, check=False).stdout
    paths = []
    for line in out.splitlines():
        p = line[3:].split(" -> ")[-1].strip('"')
        if p.endswith(".lock") or any(p.startswith(x) for x in ignore):
            continue
        paths.append(line[:2] + " " + p)
    return paths

def secrets(paths):
    return [p for p in paths if SECRET.search(p[3:]) and not SECRET_OK.search(p[3:])]

def load(text):
    try: return json.loads(text)
    except ValueError: return None

def commit_cmd(ph):
    if kind == "onboarding":  # JO-8: narrowed add, staged-path check and secret scan; never git add -A
        return "the chain that `sh .agents-v0/scripts/gate-checks.sh commit_chain` prints"
    return f"git add -A && git commit -m \"{story_id()}: {ph} approved\""

if mode == "message":
    if not phase:
        print("FAIL: --message needs a phase", file=sys.stderr); sys.exit(2)
    if phase == "release" and kind == "feature" and not p0a():
        tip = git("rev-parse", "--verify", "-q", f"refs/heads/feature/{slug}").stdout.strip()
        if not tip:
            print(f"FAIL: no feature/{slug} branch", file=sys.stderr); sys.exit(1)
        path = git("rev-parse", "--git-path", "agents-v0-gate-msg.txt").stdout.strip()
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"{story_id()}: release approved (squash-merge of feature/{slug})\n\n"
                     f"Story-Branch: feature/{slug}\nStory-Tip: {tip}\n")
        print(f"git add -A && git commit -F {path}")
    elif kind == "onboarding":
        print(commit_cmd(phase))
    elif kind == "program":
        print(commit_cmd(phase) + f" && git tag -a {phase}-v<n> -m \"{phase} approved\"   (n = 1, or the next free number for a revision)")
    else:
        print(commit_cmd(phase))
    sys.exit(0)

if mode == "check":
    cur = load(open(state, encoding="utf-8").read()) if os.path.isfile(state) else None
    last = ((cur or {}).get("lastApprovedPhase") or "").lower()
    if not last:
        print(f"OK: nothing approved yet for {slug}"); sys.exit(0)
    problems = []
    if git("ls-files", "--error-unmatch", "--", state_rel).returncode != 0:
        problems.append(f"{state_rel} is not committed")
    else:
        head = load(git("show", f"HEAD:{state_rel}").stdout) or {}
        if (head.get("lastApprovedPhase") or "").lower() != last or \
                sorted(head.get("approvedPhases") or []) != sorted(cur.get("approvedPhases") or []):
            problems.append(f"the {last} approval in {state_rel} is not in the last commit")
    d = dirty()
    if d:
        problems.append("uncommitted changes:\n" + "\n".join("    " + p for p in d[:15]) + ("\n    ..." if len(d) > 15 else ""))
    s = secrets(d)
    if problems:
        print(f"FAIL: {last} was approved for {slug}, but its work is not committed (kitfix-20261031-gate-commit):", file=sys.stderr)
        for p in problems: print("  - " + p, file=sys.stderr)
        if s:
            print("  These look like secrets; never commit them, add them to .gitignore first: " + ", ".join(x[3:] for x in s), file=sys.stderr)
        print(f"  Commit the {last} gate first: {commit_cmd(last)}", file=sys.stderr)
        print("  One commit per approved gate; never amend an earlier gate commit.", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {last} gate of {slug} is committed ({git('rev-parse', '--short', 'HEAD').stdout.strip()})")
    sys.exit(0)

# mode == release
if kind != "feature" or p0a():
    print(f"OK: {slug} has no story branch to squash (P0-A, maintenance or project phase)"); sys.exit(0)
br = f"feature/{slug}"
tip = git("rev-parse", "--verify", "-q", f"refs/heads/{br}").stdout.strip()
problems = []
if not tip:
    problems.append(f"no {br} branch")
else:
    bst = load(git("show", f"{br}:{state_rel}").stdout)
    if bst is None:
        problems.append(f"{br} has no committed {state_rel}")
    else:
        if "verify" not in (bst.get("approvedPhases") or []): problems.append(f"{br}: verify is not approved in the committed state")
        if bst.get("verifyPassed") is not True: problems.append(f"{br}: verifyPassed is not true in the committed state")
        if (bst.get("activePhase") or "") != "release":
            problems.append(f"{br}: the release preparation is not committed on the branch (activePhase is {bst.get('activePhase')!r}, want 'release'); "
                            f"in the feature worktree run: {commit_cmd('release')}")
    wt = ""
    for block in git("worktree", "list", "--porcelain").stdout.split("\n\n"):
        if f"branch refs/heads/{br}" in block:
            wt = block.splitlines()[0][len("worktree "):]
    if wt and dirty(wt):
        problems.append(f"the {br} worktree {wt} has uncommitted changes:\n" + "\n".join("    " + p for p in dirty(wt)[:10]))
    if git("merge-base", "--is-ancestor", tip, "HEAD").returncode == 0:
        print(f"WARN: {br} is already merged with a merge commit; the kit squash-merges (git merge --squash {br})", file=sys.stderr)
    else:
        base = git("merge-base", "HEAD", tip).stdout.strip()
        changed = [p for p in git("diff", "--name-only", base, tip).stdout.splitlines() if p]
        if not changed:
            problems.append(f"{br} changes nothing since it left the integration branch")
        elif git("diff", "--cached", "--quiet", tip, "--", *changed).returncode != 0:
            problems.append(f"the index does not hold {br}: run `git merge --squash {br}` in this checkout first (resolve conflicts, then stop if any remain)")
if problems:
    print(f"FAIL: release of {slug} is not ready to squash-merge (kitfix-20261031-gate-commit):", file=sys.stderr)
    for p in problems: print("  - " + p, file=sys.stderr)
    sys.exit(1)
print(f"OK: {br} ({tip[:12]}) is committed and staged for the squash commit")
PYGC
