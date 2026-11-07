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
# Design: DST3, DST5, DST6.
#
# Usage:
#   sh .agents-v0/scripts/stories-status.sh [--json] [--all-copies] [--root <dir>] [--story <slug>] [<slug>]
#   sh .agents-v0/scripts/stories-status.sh steps | --steps
#     --json          print a JSON array instead of the table (or single JSON object with --story)
#     --all-copies    print every copy of a state file (one row per worktree that has it).
#                     Default: one row per story, read from the worktree on that story's branch
#                     (feature/<feature> or maintain/<id>) when one exists, otherwise from main.
#     --root <dir>    run as if started in <dir> (default: current directory)
#     --story <slug>  print a detailed read-only status summary and deterministic Next command for <slug>
#     steps|--steps   print the canonical step block for core/common/commands/v0-status.md
#
# Exit 0 always after printing in table/--json mode, even when a state file is missing or malformed
# (those rows say so in the note column). Exit 1 in --story <slug> mode when <slug> is not found.
# Exit 2 only for a usage error.

set -eu
export PYTHONDONTWRITEBYTECODE=1

as_json=0
all_copies=0
root=""
target_story=""
want_steps=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json) as_json=1; shift ;;
    --all-copies) all_copies=1; shift ;;
    steps|--steps) want_steps=1; shift ;;
    --root)
      [ $# -ge 2 ] || { printf 'usage: %s [--json] [--all-copies] [--root <dir>] [--story <slug>]\n' "$0" >&2; exit 2; }
      root="$2"; shift 2 ;;
    --story)
      [ $# -ge 2 ] || { printf 'usage: %s [--json] [--all-copies] [--root <dir>] [--story <slug>]\n' "$0" >&2; exit 2; }
      target_story="$2"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--json] [--all-copies] [--root <dir>] [--story <slug>] [steps]\n' "$0"
      exit 0 ;;
    -*)
      printf 'usage: %s [--json] [--all-copies] [--root <dir>] [--story <slug>]\n' "$0" >&2
      exit 2 ;;
    *)
      if [ -z "$target_story" ]; then
        target_story="$1"
        shift
      else
        printf 'usage: %s [--json] [--all-copies] [--root <dir>] [--story <slug>]\n' "$0" >&2
        exit 2
      fi
      ;;
  esac
done

if [ -n "$root" ]; then
  cd "$root" || { printf 'FAIL: --root not found: %s\n' "$root" >&2; exit 2; }
fi

if [ "$want_steps" = 1 ]; then
  cat <<'EOF'
1. **Cross-worktree overview (`stories-status.sh`, read-only):** Run `sh .agents-v0/scripts/stories-status.sh`. It reads `docs/agents-v0/program.state.json`, `docs/agents-v0/onboarding/state.json`, `docs/agents-v0/requirements/*.state.json`, and `docs/agents-v0/maintain/*/state.json` across the main checkout and every worktree from `git worktree list`, and prints one row per workstream (`story`, `kind`, `branch`, `worktree`, `activePhase`, `activeStatus`, `lastApprovedPhase`, `verifyPassed`, `reopenCount`, `tier`, `blockedReason`, `lastCommit`, `note`, and deterministic `nextCommand` in `--json`). It is strictly read-only and writes nothing; do not save its output to a file or repair a malformed state file automatically.
2. **Select the target workstream (`workflow-orchestration.mdc` Parallel Features):**
   - If the user named a `<feature>`, `<id>`, `program`, or `onboarding`, run `sh .agents-v0/scripts/stories-status.sh --story <slug>` (and `--json` when full JSON fields are needed).
   - If no workstream was named and exactly one open workstream exists in the table, inspect it with `sh .agents-v0/scripts/stories-status.sh --story <slug>`.
   - If multiple workstreams are open and none was named, present the `stories-status.sh` table and ask the user which `<feature>`, `<id>`, `program`, or `onboarding` workstream to inspect. Never guess or pick the newest state file.
   - If no state files exist at all, ask whether this is an existing repository (`/v0-onboard`), a new greenfield program (`/v0-roadmap`), or a trivial docs/patch edit (`/v0-triage <id>`).
3. **Inspect detailed state, release evidence & post-Verify drift (`--story <slug>`):**
   - `sh .agents-v0/scripts/stories-status.sh --story <slug>` reports `story`, `kind`, `tier`, `branch`, `worktree`, `stateFile`, `artifact`, `approvedPhases`, `lastApprovedPhase`, `activePhase`, `activeStatus`, `verifyPassed`, `reopenCount`, `baseCommit`, `blockedReason`, `note`, and `nextCommand`.
   - When `kind` is `feature` and `release` is in `approvedPhases`, `stories-status.sh` cross-checks `sh .agents-v0/scripts/check-release-evidence.sh docs/agents-v0/requirements/<feature>.md`. If `Release evidence OK: False` (`note` contains `unsupported by evidence`), report the state as **unsupported by evidence**, do not call the story complete, do not name a next story, and ask the user to restore `docs/agents-v0/requirements/<feature>.state.json` from version control (the kit cannot re-open a released story). When `docs/agents-v0/project-profile.md` has a configured **Deploy** table and no deploy record is on disk, report `release-deploy` as the next step.
   - When `note` reports an **uncommitted gate** (`uncommitted gate (<phase>): run sh .agents-v0/scripts/guard-<phase>.sh commit ...`), report that external TTY approval is already recorded on disk and the gate commit is the immediate next command before any new phase starts.
   - When `note` reports **post-Verify source drift** (`post-Verify source drift: re-run /v0-verify <slug>`), advise re-running `/v0-verify <slug>` before `/v0-local-release`.
4. **Report & stop (strictly read-only):** Report the state summary, any `blockedReason` or `note`, and the deterministic `Next:` command from `stories-status.sh --story <slug>`. Ignore `docs/agents-v0/backlog/tickets.csv` and `docs/agents-v0/presentations/`, and never name `/v0-export` or `/v0-deck` as the next command. Do not mutate any file or advance any phase during `/v0-status`.
EOF
  exit 0
fi

ss_approvals_dir=""
# >>> kit-test-override (Design: DST3; install.sh removes this block; kit test copies only)
ss_approvals_dir="${AGENTS_V0_APPROVALS_DIR:-}"
# <<< kit-test-override
[ -n "$ss_approvals_dir" ] || ss_approvals_dir="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')/.agents-v0-approvals"

ss_script_dir="$(cd "$(dirname "$0")" && pwd)"
SS_JSON="$as_json" SS_ALL="$all_copies" SS_STORY="$target_story" SS_APPROVALS_DIR="$ss_approvals_dir" SS_SCRIPT_DIR="$ss_script_dir" python3 - <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

as_json = os.environ.get("SS_JSON") == "1"
all_copies = os.environ.get("SS_ALL") == "1"
target_story = os.environ.get("SS_STORY", "").strip()
approvals_root = os.environ.get("SS_APPROVALS_DIR", "").strip()
script_dir = os.environ.get("SS_SCRIPT_DIR", "").strip()
caller_cwd = os.path.abspath(".")


def git(args, cwd="."):
    """Run a read-only git command; return stdout or "" on any failure."""
    try:
        r = subprocess.run(["git", "--no-optional-locks", *args], cwd=cwd, capture_output=True, text=True, check=False)
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

# Compute repo_id matching guard-common.sh gc_repo_id
repo_id = ""
if not worktrees[0].get("nogit"):
    common_dir = git(["rev-parse", "--git-common-dir"], cwd=main_path).strip()
    if common_dir:
        abs_cd = os.path.realpath(os.path.join(main_path, common_dir))
        base_name = os.path.basename(os.path.dirname(abs_cd)) if os.path.basename(abs_cd) == ".git" else os.path.basename(abs_cd)
        base_name = re.sub(r"[^A-Za-z0-9._-]", "_", base_name) or "repo"
        repo_id = f"{base_name}-{hashlib.sha256(abs_cd.encode()).hexdigest()[:12]}"


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


def phase_result_rel(kind, story, phase, data):
    if kind == "onboarding":
        return "docs/agents-v0/onboarding/phase-result.md"
    if kind == "program":
        if phase == "roadmap":
            art = (data or {}).get("artifact") or ""
            stem = os.path.basename(art)[:-3] if art.endswith(".md") else "program"
            return f"docs/agents-v0/roadmap/{stem}.phase-result.md"
        if phase == "architecture":
            return "docs/agents-v0/architecture.phase-result.md"
        if phase == "plan":
            return "docs/agents-v0/milestones/plan.phase-result.md"
        if phase == "scaffold":
            return "docs/agents-v0/milestones/scaffold.phase-result.md"
    if kind == "feature":
        return f"docs/agents-v0/requirements/{story}.phase-result.md"
    if kind == "maintain":
        return f"docs/agents-v0/maintain/{story}/phase-result.md"
    return ""


def approval_record_path(kind, story, phase):
    if not approvals_root or not repo_id:
        return ""
    if kind in ("program", "onboarding"):
        return os.path.join(approvals_root, repo_id, f"{phase}.json")
    return os.path.join(approvals_root, repo_id, f"{phase}-{story}.json")


def detect_uncommitted_gate(wt, kind, story, state_rel, data):
    """Detect if the user externally approved a gate that has not been committed via guard-<phase>.sh commit yet."""
    if not data or wt.get("nogit") or not wt.get("exists"):
        return "", ""
    wt_path = wt["path"]
    active_phase = (data.get("activePhase") or "").strip()
    active_status = (data.get("activeStatus") or "").strip()
    last_app = (data.get("lastApprovedPhase") or "").strip()
    tier = (data.get("tier") or "").strip()

    # Case B: local-release keeps activePhase="release", activeStatus="awaiting_approval" when approved externally
    if active_phase == "release" and active_status == "awaiting_approval":
        rec_p = approval_record_path(kind, story, "local-release")
        if rec_p and os.path.isfile(rec_p):
            try:
                rec = json.loads(Path(rec_p).read_text(encoding="utf-8"))
                base_c = (data.get("baseCommit") or "").strip()
                if not base_c or rec.get("baseCommit") == base_c:
                    flag_m = " --maintain" if kind == "maintain" else ""
                    cmd = f"sh .agents-v0/scripts/guard-local-release.sh commit {story}{flag_m}"
                    return "local-release", cmd
            except Exception:
                pass
        return "", ""

    # Case A: lastApprovedPhase is set and activePhase is empty
    if active_phase or not last_app or last_app == "release":
        return "", ""

    # Check if HEAD:<state_rel> already has this lastApprovedPhase committed
    head_raw = git(["show", f"HEAD:{state_rel}"], cwd=wt_path)
    if head_raw:
        try:
            head_data = json.loads(head_raw)
            head_app = (head_data.get("lastApprovedPhase") or "").strip()
            head_phases = head_data.get("approvedPhases") or []
            if head_app == last_app or last_app in head_phases:
                return "", ""
        except Exception:
            pass

    # Verify evidence that external approve actually ran (either approval record on disk or phase-result awaiting_approval)
    has_evidence = False
    rec_p = approval_record_path(kind, story, last_app)
    if rec_p and os.path.isfile(rec_p):
        has_evidence = True
    else:
        pr_rel = phase_result_rel(kind, story, last_app, data)
        if pr_rel:
            pr_full = os.path.join(wt_path, pr_rel)
            if os.path.isfile(pr_full):
                try:
                    pr_txt = Path(pr_full).read_text(encoding="utf-8", errors="replace")
                    if re.search(r"(?im)^-?\s*status:\s*awaiting_approval\b", pr_txt):
                        has_evidence = True
                except Exception:
                    pass

    if not has_evidence:
        return "", ""

    if kind in ("program", "onboarding"):
        return last_app, f"sh .agents-v0/scripts/guard-{last_app}.sh commit"
    if kind == "maintain":
        if last_app == "maintain" and tier == "trivial":
            return "maintain", f"sh .agents-v0/scripts/guard-triage.sh commit {story}"
        if last_app == "verify":
            return "verify", f"sh .agents-v0/scripts/guard-verify.sh commit {story} --maintain"
        return last_app, f"sh .agents-v0/scripts/guard-{last_app}.sh commit {story}"
    return last_app, f"sh .agents-v0/scripts/guard-{last_app}.sh commit {story} (or /v0-deliver {story})"


def compute_next_command(row, data, wt_path):
    """Compute the deterministic next command for a story/program/onboarding/maintain row."""
    if row.get("note") and any(k in row["note"] for k in ("malformed", "unreadable", "no state file", "worktree folder missing")):
        return "Fix or restore the state file / worktree reported in note"

    uncommitted_cmd = row.get("_uncommittedCmd") or ""
    if uncommitted_cmd:
        return uncommitted_cmd

    kind = row["kind"]
    story = row["story"]
    active_phase = (row.get("activePhase") or "").strip()
    active_status = (row.get("activeStatus") or "").strip()
    last_app = (row.get("lastApprovedPhase") or "").strip()
    tier = (row.get("tier") or "").strip()
    app_phases = (data or {}).get("approvedPhases") or []
    if not isinstance(app_phases, list):
        app_phases = []
    is_released = ("release" in app_phases) or (last_app == "release")

    # Worktree switch hint when story has its own worktree and caller is not inside it
    wt_rel = row.get("worktree") or "."
    wt_abs = os.path.abspath(wt_path)
    in_other_checkout = (wt_rel != ".") and (not caller_cwd.startswith(wt_abs))

    if kind == "feature" and is_released:
        return "COMPLETE (start a new /v0-intake <feature>, /v0-triage <id>, or /v0-maintain <id>)"

    if kind == "maintain" and is_released:
        if tier == "emergency" and "verify" not in app_phases and last_app != "verify":
            if active_phase == "verify" and active_status == "blocked":
                return "Start /v0-maintain with a new <id> (owed emergency verify is blocked by a Critical finding)"
            return f"/v0-verify {story} --maintain"
        return "COMPLETE (start a new /v0-triage <id> or /v0-maintain <id>)"

    if active_status in ("in_progress", "blocked"):
        if kind in ("program", "onboarding"):
            return f"/v0-{active_phase}"
        if active_phase == "release":
            flag_m = " --maintain" if kind == "maintain" else ""
            base_cmd = f"/v0-local-release {story}{flag_m}"
        elif kind == "maintain" and active_phase == "maintain" and tier == "trivial":
            base_cmd = f"/v0-triage {story}"
        elif kind == "maintain" and active_phase == "verify":
            base_cmd = f"/v0-verify {story} --maintain"
        else:
            base_cmd = f"/v0-{active_phase} {story}"
        if in_other_checkout and kind in ("feature", "maintain") and tier != "trivial":
            return f"Open worktree {wt_rel} and run {base_cmd} (or /v0-deliver {story})"
        return base_cmd

    if active_status == "awaiting_approval":
        ap_cmd = "local-release" if active_phase == "release" else active_phase
        if kind in ("program", "onboarding"):
            return f"Run in external terminal: sh .agents-v0/scripts/guard-common.sh approve {ap_cmd} — then run: sh .agents-v0/scripts/guard-{ap_cmd}.sh commit"
        if kind == "maintain" and ap_cmd == "maintain" and tier == "trivial":
            return f"Run in external terminal: sh .agents-v0/scripts/guard-common.sh approve triage {story} — then run: sh .agents-v0/scripts/guard-triage.sh commit {story}"
        flag_m = " --maintain" if (kind == "maintain" and ap_cmd in ("verify", "local-release")) else ""
        return f"Run in external terminal: sh .agents-v0/scripts/guard-common.sh approve {ap_cmd} {story} — then run: sh .agents-v0/scripts/guard-{ap_cmd}.sh commit {story}{flag_m}"

    # No activePhase: route from lastApprovedPhase
    if kind == "onboarding":
        if last_app == "onboard" or "onboard" in app_phases:
            return "/v0-roadmap (program), /v0-intake <feature> (single story), /v0-triage <id> (trivial), or /v0-maintain <id> (fix)"
        return "/v0-onboard"

    if kind == "program":
        if not last_app:
            return "/v0-roadmap"
        if last_app == "roadmap":
            return "/v0-architecture"
        if last_app == "architecture":
            return "/v0-plan"
        if last_app == "plan":
            onb_st = os.path.join(main_path, "docs", "agents-v0", "onboarding", "state.json")
            if not os.path.isfile(onb_st) and "scaffold" not in app_phases:
                return "/v0-scaffold"
            return "/v0-intake <first-story> (or /v0-deliver <first-story>)"
        if last_app == "scaffold":
            return "/v0-intake <first-story> (or /v0-deliver <first-story>)"
        return "/v0-status"

    if kind == "feature":
        nxt_map = {
            "": f"/v0-intake {story}",
            "intake": f"/v0-design {story}",
            "design": f"/v0-build {story}",
            "build": f"/v0-verify {story}",
            "verify": f"/v0-local-release {story}",
        }
        base_cmd = nxt_map.get(last_app, f"/v0-deliver {story}")
        if in_other_checkout and last_app in ("intake", "design", "build", "verify"):
            return f"Open worktree {wt_rel} and run {base_cmd} (or /v0-deliver {story})"
        return f"{base_cmd} (or /v0-deliver {story})"

    if kind == "maintain":
        if not last_app:
            return f"/v0-triage {story}" if tier == "trivial" else f"/v0-maintain {story}"
        if last_app == "maintain":
            if tier == "emergency":
                base_cmd = f"/v0-local-release {story} --maintain"
            else:
                base_cmd = f"/v0-verify {story} --maintain"
        elif last_app == "verify":
            base_cmd = f"/v0-local-release {story} --maintain"
        else:
            base_cmd = f"/v0-maintain {story}"
        if in_other_checkout and tier != "trivial":
            return f"Open worktree {wt_rel} and run {base_cmd} (or /v0-deliver {story} --maintain)"
        return base_cmd

    return "/v0-status"


def is_source_path(p):
    p = (p or "").strip().strip('"')
    if not p:
        return False
    for prefix in ("docs/agents-v0/", ".agents-v0/", ".cursor/", ".agents/"):
        if p.startswith(prefix):
            return False
    if p in (".gitignore", ".cursorignore"):
        return False
    return True


def check_release_and_deploy(wt, kind, story, data):
    """Cross-check release evidence and optional deploy record when kind == 'feature' and 'release' in approvedPhases."""
    if not data or not isinstance(data, dict) or kind != "feature":
        return None, False, "", ""
    app_phases = data.get("approvedPhases") or []
    if not isinstance(app_phases, list) or "release" not in app_phases:
        return None, False, "", ""
    wt_path = wt["path"]
    art_rel = f"docs/agents-v0/requirements/{story}.md"
    art_full = os.path.join(wt_path, art_rel)
    if not os.path.isfile(art_full):
        return (
            False,
            False,
            "unsupported by evidence (requirements doc missing; restore state file)",
            f"UNSUPPORTED BY EVIDENCE: restore docs/agents-v0/requirements/{story}.state.json (sync-feature-state.sh cannot re-open a released story)",
        )
    cre = os.path.join(wt_path, ".agents-v0", "scripts", "check-release-evidence.sh")
    if not os.path.isfile(cre) and script_dir:
        cre = os.path.join(script_dir, "check-release-evidence.sh")
    if os.path.isfile(cre):
        try:
            r = subprocess.run(["sh", cre, art_rel], cwd=wt_path, capture_output=True, text=True, check=False)
            if r.returncode != 0:
                return (
                    False,
                    False,
                    "unsupported by evidence (restore state file)",
                    f"UNSUPPORTED BY EVIDENCE: restore docs/agents-v0/requirements/{story}.state.json (sync-feature-state.sh cannot re-open a released story)",
                )
        except OSError:
            pass
    # Optional deploy-table check in docs/agents-v0/project-profile.md
    prof_full = os.path.join(wt_path, "docs", "agents-v0", "project-profile.md")
    if os.path.isfile(prof_full):
        try:
            prof_txt = re.sub(r"<!--.*?-->", "", Path(prof_full).read_text(encoding="utf-8", errors="replace"), flags=re.S)
            m_dep = re.search(r"(?ims)^##\s+Deploy\b(.*?)(?=^##\s+|\Z)", prof_txt)
            deploy_envs = []
            if m_dep:
                for line in m_dep.group(1).splitlines():
                    line_s = line.strip()
                    if not line_s.startswith("|"):
                        continue
                    cells = [c.strip() for c in line_s.strip("|").split("|")]
                    if len(cells) >= 2:
                        env_name = cells[0]
                        if env_name and env_name.lower() not in ("env", "environment") and not re.match(r"^[-:]+$", env_name) and not env_name.startswith("<"):
                            deploy_envs.append(env_name)
            if deploy_envs:
                req_txt = re.sub(r"<!--.*?-->", "", Path(art_full).read_text(encoding="utf-8", errors="replace"), flags=re.S)
                if not re.search(r"(?im)^\|\s*release\s*\([^|\n]+\)\s*\|", req_txt):
                    return (
                        True,
                        True,
                        "local-release complete; deploy record pending (release-deploy)",
                        f"Follow release-deploy skill for {story} (configured Deploy row in docs/agents-v0/project-profile.md)",
                    )
        except OSError:
            pass
    return True, False, "", ""


def check_post_verify_drift(wt, kind, story, data):
    """Detect source modifications after Verify passed while the story is not yet released."""
    if not data or not isinstance(data, dict) or wt.get("nogit") or not wt.get("exists"):
        return False, "", ""
    if data.get("verifyPassed") is not True:
        return False, "", ""
    app_phases = data.get("approvedPhases") or []
    last_app = (data.get("lastApprovedPhase") or "").strip()
    active_phase = (data.get("activePhase") or "").strip()
    if (isinstance(app_phases, list) and "release" in app_phases) or last_app == "release":
        return False, "", ""
    if active_phase and active_phase not in ("verify", "release"):
        return False, "", ""
    wt_path = wt["path"]
    changed = []
    porc = git(["status", "--porcelain"], cwd=wt_path)
    for line in porc.splitlines():
        if len(line) > 3:
            p = line[3:].strip()
            if " -> " in p:
                p = p.split(" -> ", 1)[1].strip()
            if is_source_path(p):
                changed.append(p)
    base_c = (data.get("baseCommit") or "").strip()
    if base_c and last_app == "verify" and not active_phase:
        diff_out = git(["diff", "--name-only", f"{base_c}..HEAD"], cwd=wt_path)
        for p in diff_out.splitlines():
            if is_source_path(p):
                changed.append(p.strip())
    if changed:
        flag_m = " --maintain" if kind == "maintain" else ""
        return (
            True,
            f"post-Verify source drift: re-run /v0-verify {story}{flag_m}",
            f"/v0-verify {story}{flag_m} (post-Verify source drift detected)",
        )
    return False, "", ""


copies = {}  # (kind, story) -> list of rows
for wt in worktrees:
    if not wt["exists"]:
        continue
    for story, kind, path in find_state_files(wt["path"]):
        data, err = read_state(path)
        own = bool(owner_branch(kind, story)) and wt["branch"] == owner_branch(kind, story)
        state_rel = os.path.relpath(str(path), wt["path"])
        u_phase, u_cmd = detect_uncommitted_gate(wt, kind, story, state_rel, data)
        rel_ok, dep_pend, rel_note, rel_cmd = check_release_and_deploy(wt, kind, story, data)
        drift_ok, drift_note, drift_cmd = check_post_verify_drift(wt, kind, story, data)
        note_parts = [err] if err else []
        if u_phase:
            note_parts.append(f"uncommitted gate ({u_phase}): run {u_cmd}")
        if rel_note:
            note_parts.append(rel_note)
        if drift_note:
            note_parts.append(drift_note)
        row = {
            "story": story,
            "kind": kind,
            "branch": wt["branch"],
            "worktree": rel_wt(wt["path"]),
            "stateFile": state_rel,
        }
        for f in FIELDS:
            row[f] = (data or {}).get(f, None) if data is not None else None
        row["lastCommit"] = last_commit(wt, path, own)
        row["note"] = "; ".join(note_parts)
        row["_own"] = own
        row["_uncommittedPhase"] = u_phase
        row["_uncommittedCmd"] = u_cmd
        row["_relOk"] = rel_ok
        row["_depPend"] = dep_pend
        row["_drift"] = drift_ok
        row["_wtPath"] = wt["path"]
        row["_data"] = data or {}
        nxt = compute_next_command(row, data, wt["path"])
        if not u_cmd:
            if rel_cmd:
                nxt = rel_cmd
            elif drift_cmd:
                nxt = drift_cmd
        row["nextCommand"] = nxt
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
                   "stateFile": "", "lastCommit": "", "note": note, "_own": True,
                   "_uncommittedPhase": "", "_uncommittedCmd": "", "_wtPath": wt["path"], "_data": {}}
            for f in FIELDS:
                row[f] = None
            if wt["exists"] and not wt.get("nogit"):
                row["lastCommit"] = git(["log", "-1", "--format=%cs"], cwd=wt["path"]).strip()
            row["nextCommand"] = compute_next_command(row, None, wt["path"])
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
    bad = [label(r) for r in others if r["note"] and not r["note"].startswith("uncommitted gate")]
    if bad:
        notes.append("unreadable copy in: " + ", ".join(bad))
    pick = dict(pick)
    pick["note"] = "; ".join(notes)
    rows.append(pick)

if target_story:
    matches = [r for r in rows if r["story"] == target_story]
    if not matches:
        open_names = ", ".join(r["story"] for r in rows) if rows else "none"
        print(f"REFUSED status: no state file found for '{target_story}' (available workstreams: {open_names})", file=sys.stderr)
        raise SystemExit(1)
    chosen = dict(matches[0])
    raw_data = chosen.pop("_data", {})
    rel_ok = chosen.pop("_relOk", None)
    dep_pend = chosen.pop("_depPend", False)
    drift_ok = chosen.pop("_drift", False)
    chosen.pop("_own", None)
    chosen.pop("_uncommittedPhase", None)
    chosen.pop("_uncommittedCmd", None)
    chosen.pop("_wtPath", None)
    if as_json:
        chosen["approvedPhases"] = raw_data.get("approvedPhases") or []
        chosen["phaseDates"] = raw_data.get("phaseDates") or {}
        chosen["baseCommit"] = raw_data.get("baseCommit") or ""
        chosen["artifact"] = raw_data.get("artifact") or ""
        chosen["artifacts"] = raw_data.get("artifacts") or {}
        chosen["releaseEvidenceOk"] = rel_ok
        chosen["deployPending"] = dep_pend
        chosen["postVerifyDrift"] = drift_ok
        print(json.dumps(chosen, indent=2))
        raise SystemExit(0)
    app_list = ", ".join(raw_data.get("approvedPhases") or []) or "none"
    print(f"Story: {chosen['story']} (kind: {chosen['kind']}, tier: {chosen.get('tier') or '-'})")
    print(f"Branch: {chosen.get('branch') or '-'} (worktree: {chosen.get('worktree') or '.'})")
    print(f"State file: {chosen.get('stateFile') or '-'}")
    print(f"Artifact: {raw_data.get('artifact') or '-'}")
    print(f"Approved phases: {app_list} (lastApprovedPhase: {chosen.get('lastApprovedPhase') or 'none'})")
    print(f"Active phase: {chosen.get('activePhase') or 'none'} (activeStatus: {chosen.get('activeStatus') or 'none'})")
    print(f"Verify passed: {chosen.get('verifyPassed')} (reopenCount: {chosen.get('reopenCount') or 0}, baseCommit: {raw_data.get('baseCommit') or '-'})")
    if rel_ok is not None:
        print(f"Release evidence OK: {rel_ok}")
    if chosen.get("blockedReason"):
        print(f"Blocked reason: {chosen['blockedReason']}")
    if chosen.get("note"):
        print(f"Note: {chosen['note']}")
    print(f"Next: {chosen['nextCommand']}")
    raise SystemExit(0)

for r in rows:
    r.pop("_own", None)
    r.pop("_uncommittedPhase", None)
    r.pop("_uncommittedCmd", None)
    r.pop("_relOk", None)
    r.pop("_depPend", None)
    r.pop("_drift", None)
    r.pop("_wtPath", None)
    r.pop("_data", None)

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
