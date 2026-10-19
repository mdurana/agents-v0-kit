#!/bin/sh
# gate.sh — run the document gate for a delivery phase from one manifest (ci/gates.json).
#
# Usage:
#   sh .agents-v0/ci/gate.sh <phase> [--approved] <artifact>
#       Run every check gates.json lists for <phase> ("draft" list, or "approved" with --approved).
#       <artifact> is the file that holds the phase's Delivery approvals row (roadmap file,
#       docs/agents-v0/architecture.md, milestone manifest, requirements artifact, onboarding report).
#   sh .agents-v0/ci/gate.sh --staged
#       Pre-commit mode. For each staged approval file, run the "approved" list of every phase whose
#       Approved row this commit adds or changes (and, for phases with "sealedEdits", any edit to an
#       already-approved file). Exit 1 blocks the commit.
#   sh .agents-v0/ci/gate.sh --for-path <path>
#       Advisory mode for the after-edit hook: run the gate that the edited file belongs to.
#   sh .agents-v0/ci/gate.sh --list
#       Print each phase and its checks.
#
# Every check runs even after one fails, so the full list of problems is printed at once.
# Exit codes: 0 = all checks passed (or nothing to check); 1 = a check failed; 2 = usage error.
# Checks read the working tree. In --staged mode a warning is printed when a gated file also has
# unstaged changes, because the gate then checks content that is not the content being committed.
set -eu

GATE_SELF="$0"
export GATE_SELF
exec python3 - "$@" <<'PY'
import fnmatch
import json
import os
import re
import subprocess
import sys

SELF = os.path.abspath(os.environ["GATE_SELF"])
CI_DIR = os.path.dirname(SELF)
AGENTS_DIR = os.path.dirname(CI_DIR)
MANIFEST = os.path.join(CI_DIR, "gates.json")
APPROVED_RE = re.compile(r"(approved|approve|yes|pass)[\s.!]*", re.I)


def usage(code=2):
    sys.stderr.write(
        "usage: gate.sh <phase> [--approved] <artifact> | --staged | --for-path <path> | --list\n"
    )
    sys.exit(code)


def load_manifest():
    try:
        with open(MANIFEST, encoding="utf-8") as fh:
            return json.load(fh)["phases"]
    except (OSError, ValueError, KeyError) as exc:
        sys.stderr.write(f"FAIL: cannot read {MANIFEST}: {exc}\n")
        sys.exit(1)


def git(*args, check=False):
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and proc.returncode != 0:
        return None
    return proc


def repo_root():
    proc = git("rev-parse", "--show-toplevel")
    if proc.returncode == 0 and proc.stdout.strip():
        return proc.stdout.strip()
    return os.getcwd()


def excluded(path):
    base = os.path.basename(path)
    return base.startswith("_") or base.endswith(".phase-result.md") or not base.endswith(".md")


def matches(path, patterns):
    if excluded(path):
        return False
    for pat in patterns:
        if os.path.dirname(pat) == os.path.dirname(path) and fnmatch.fnmatch(os.path.basename(path), os.path.basename(pat)):
            return True
    return False


def approval_rows(text, phase):
    """Decisions of every Delivery approvals row for <phase>, in file order."""
    out = []
    in_section = False
    for line in (text or "").splitlines():
        if re.match(r"^#+\s*delivery approvals", line, re.I):
            in_section = True
            continue
        if re.match(r"^#+\s", line):
            in_section = False
        if not in_section or not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 4 and cells[0].lower() == phase:
            out.append((cells[3], line.strip()))
    return out


def is_approved(rows):
    return bool(rows) and bool(APPROVED_RE.fullmatch(rows[-1][0].strip()))


def expand(token, artifact):
    feature = os.path.splitext(os.path.basename(artifact))[0] if artifact else ""
    return token.replace("{artifact}", artifact or "").replace("{feature}", feature)


def run_list(phase, mode, artifact, entries, staged_mode=""):
    """Run one gate list. Returns True when every check passed."""
    label = f"gate {phase}{' --approved' if mode == 'approved' else ''}" + (f" {artifact}" if artifact else "")
    if not entries:
        print(f"{label}: no document checks for this phase")
        return True
    ok = True
    print(f"{label}:")
    child_env = os.environ.copy()
    if staged_mode:
        child_env["CHECK_EVIDENCE_STAGED"] = staged_mode
    for entry in entries:
        cond = entry.get("ifExists")
        conds = [cond] if isinstance(cond, str) else (cond or [])
        if any(not os.path.exists(expand(c, artifact)) for c in conds):
            continue
        args = [expand(a, artifact) for a in entry["run"]]
        script = os.path.join(AGENTS_DIR, args[0])
        shown = " ".join(args)
        if not os.path.isfile(script):
            print(f"  FAIL {shown}\n      script not found: {script}")
            ok = False
            continue
        proc = subprocess.run(["sh", script, *args[1:]], capture_output=True, text=True, env=child_env)
        if proc.returncode == 0:
            print(f"  PASS {shown}")
        else:
            ok = False
            print(f"  FAIL {shown}")
            detail = (proc.stderr.strip() + "\n" + proc.stdout.strip()).strip().splitlines()
            for line in detail[-20:]:
                print(f"      {line}")
    return ok


def cmd_phase(phases, argv):
    phase = argv[0]
    rest = argv[1:]
    mode = "draft"
    if "--approved" in rest:
        mode = "approved"
        rest = [a for a in rest if a != "--approved"]
    if phase not in phases or len(rest) != 1:
        if phase not in phases:
            sys.stderr.write(f"FAIL: unknown phase \"{phase}\" (expected {'|'.join(phases)})\n")
        usage()
    artifact = rest[0]
    if not os.path.isfile(artifact):
        sys.stderr.write(f"FAIL: artifact not found: {artifact}\n")
        sys.exit(1)
    return 0 if run_list(phase, mode, artifact, phases[phase].get(mode, []), staged_mode="staged" if mode == "approved" else "") else 1


def cmd_staged(phases):
    proc = git("diff", "--cached", "--name-only", "--diff-filter=ACMR")
    if proc.returncode != 0:
        sys.stderr.write("FAIL: git diff --cached failed (not a git repository?)\n")
        return 1
    staged = [p for p in proc.stdout.splitlines() if p.strip()]
    ok = True
    ran = False
    for path in staged:
        new = git("show", f":{path}").stdout
        old_proc = git("show", f"HEAD:{path}")
        old = old_proc.stdout if old_proc.returncode == 0 else ""
        for phase, spec in phases.items():
            if not matches(path, spec.get("approvalFile", [])):
                continue
            new_rows = approval_rows(new, phase)
            if not is_approved(new_rows):
                continue
            old_rows = approval_rows(old, phase)
            row_changed = [r[1] for r in new_rows] != [r[1] for r in old_rows]
            sealed_edit = spec.get("sealedEdits") and is_approved(old_rows) and new != old
            if not (row_changed or sealed_edit):
                continue
            if git("diff", "--quiet", "--", path).returncode != 0:
                print(f"WARN: {path} has unstaged changes; the gate checks the working tree, not the staged content")
            ran = True
            if not run_list(phase, "approved", path, spec.get("approved", []), staged_mode="staged"):
                ok = False
    if ran and not ok:
        print("pre-commit: the delivery gate failed. Fix the files above, or withdraw the Approved row, then commit again.")
    return 0 if ok else 1


def approved_in(path, phase):
    try:
        with open(path, encoding="utf-8") as fh:
            return is_approved(approval_rows(fh.read(), phase))
    except OSError:
        return False


def cmd_for_path(phases, rel):
    path = os.path.normpath(rel).replace(os.sep, "/")
    if not path.startswith("docs/agents-v0/"):
        return 0
    jobs = []  # (phase, mode, artifact)
    parts = path.split("/")
    if path.startswith("docs/agents-v0/requirements/") and len(parts) == 4 and not excluded(path):
        if not approved_in(path, "intake"):
            jobs.append(("intake", "draft", path))
    elif path.startswith("docs/agents-v0/design/") and len(parts) >= 5 and parts[3] not in ("system",):
        req = f"docs/agents-v0/requirements/{parts[3]}.md"
        if os.path.isfile(req) and not approved_in(req, "design"):
            jobs.append(("design", "draft", req))
    elif matches(path, phases["roadmap"]["approvalFile"]):
        jobs.append(("roadmap", "approved" if approved_in(path, "roadmap") else "draft", path))
    elif path == "docs/agents-v0/architecture.md" or path.startswith("docs/agents-v0/design/system/"):
        arch = "docs/agents-v0/architecture.md"
        if os.path.isfile(arch):
            if approved_in(arch, "architecture"):
                jobs.append(("architecture", "approved", arch))
            else:
                roadmaps = [os.path.join("docs/agents-v0/roadmap", f) for f in sorted(os.listdir("docs/agents-v0/roadmap"))] if os.path.isdir("docs/agents-v0/roadmap") else []
                if any(matches(r, phases["roadmap"]["approvalFile"]) and approved_in(r, "roadmap") for r in roadmaps):
                    jobs.append(("architecture", "draft", arch))
    elif path.startswith("docs/agents-v0/adr/"):
        jobs.append(("adr", "draft", ""))
    elif matches(path, phases["plan"]["approvalFile"]):
        if not approved_in(path, "plan"):
            jobs.append(("plan", "draft", path))
    elif path.startswith("docs/agents-v0/onboarding/"):
        report = "docs/agents-v0/onboarding/report.md"
        if os.path.isfile(report) and not approved_in(report, "onboard"):
            jobs.append(("onboard", "draft", report))
    ok = True
    for phase, mode, artifact in jobs:
        if phase == "adr":
            entries = [{"run": ["ci/check-adr.sh"]}]
            ok = run_list("adr", "draft", "", entries) and ok
            continue
        ok = run_list(phase, mode, artifact, phases[phase].get(mode, [])) and ok
    return 0 if ok else 1


def cmd_list(phases):
    for phase, spec in phases.items():
        print(f"{phase}: approval file {', '.join(spec.get('approvalFile', []))}")
        for mode in ("draft", "approved"):
            for entry in spec.get(mode, []):
                c = entry.get("ifExists")
                c = " and ".join(c) if isinstance(c, list) else c
                cond = f"  (if {c} exists)" if c else ""
                print(f"  {mode}: {' '.join(entry['run'])}{cond}")
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        usage(0 if argv else 2)
    phases = load_manifest()
    if argv[0] == "--list":
        return cmd_list(phases)
    if argv[0] == "--staged":
        os.chdir(repo_root())
        return cmd_staged(phases)
    if argv[0] == "--for-path":
        if len(argv) != 2:
            usage()
        root = repo_root()
        rel = os.path.relpath(os.path.realpath(os.path.abspath(argv[1])), os.path.realpath(root))
        os.chdir(root)
        return cmd_for_path(phases, rel)
    return cmd_phase(phases, argv)


sys.exit(main(sys.argv[1:]))
PY
