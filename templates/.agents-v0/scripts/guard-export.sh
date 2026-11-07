#!/bin/sh
# Deterministic guard for /v0-export (Step 5.2 export & deck redo, Design: DEX1..DEX8, DEXA).
#
# Subcommands:
#   sh .agents-v0/scripts/guard-export.sh check
#   sh .agents-v0/scripts/guard-export.sh verify
#   sh .agents-v0/scripts/guard-export.sh commit
#   sh .agents-v0/scripts/guard-export.sh steps
#
# Output protocol (inherited from guard-common.sh):
#   OK <step>: <one-line summary>
#   REFUSED <step>: <why — and the next action>
#   ERROR <step>: <internal/usage failure>
#
# Exit codes: 0 passed, 1 refused, 2 usage/internal error.

set -eu

GE_HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD_COMMON_LIB=1 . "$GE_HERE/guard-common.sh"

ge_need_kit() {
  [ -f .agents-v0/gate-rules ] || gc_refuse "$1" ".agents-v0/gate-rules is missing; reinstall the kit (install.sh --update)"
}

ge_check() {
  gc_to_root check
  ge_need_kit check
  command -v python3 >/dev/null 2>&1 || gc_refuse check "python3 is required for guard-export.sh"

  ge_out="$(python3 - <<'PY'
import glob
import json
import os
import re
import sys

params_path = "docs/agents-v0/backlog/export-params.md"
if not os.path.isfile(params_path):
    print("REFUSED:docs/agents-v0/backlog/export-params.md is missing; run /v0-onboard or restore the backlog template")
    sys.exit(1)

with open(params_path, encoding="utf-8") as fh:
    params_text = fh.read()

m_proj = re.search(r"^Project key:[ \t]*(.*)$", params_text, re.M)
m_type = re.search(r"^Issue type:[ \t]*(.*)$", params_text, re.M)
proj_key = (m_proj.group(1).strip() if m_proj else "")
issue_type = (m_type.group(1).strip() if m_type else "")

if not proj_key or not issue_type:
    missing = []
    if not proj_key:
        missing.append("Project key")
    if not issue_type:
        missing.append("Issue type")
    print(f"REFUSED:docs/agents-v0/backlog/export-params.md has empty {', '.join(missing)}; ask the user once to confirm Project key and Issue type before writing tickets.csv")
    sys.exit(1)

def phase_approval_date(state_path, md_path, phase_names):
    if state_path and os.path.isfile(state_path):
        try:
            st = json.load(open(state_path, encoding="utf-8"))
            approved = st.get("approvedPhases") or []
            dates = st.get("phaseDates") or {}
            upd = (st.get("updatedAt") or "")[:10] or "approved"
            for p in phase_names:
                if p in approved:
                    return str(dates.get(p) or upd)[:10]
        except Exception:
            pass
    if md_path and os.path.isfile(md_path):
        try:
            txt = open(md_path, encoding="utf-8").read()
            for line in txt.splitlines():
                if "|" not in line:
                    continue
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if len(cells) >= 2 and any(cells[0].lower() == p.lower() for p in phase_names):
                    if any(c.lower().startswith("approved") for c in cells[1:]):
                        for c in cells[1:]:
                            m = re.search(r"\b(20\d\d-\d\d-\d\d)\b", c)
                            if m:
                                return m.group(1)
                        return "approved"
        except Exception:
            pass
    return None

prog_state = "docs/agents-v0/program.state.json"
manifests = sorted(
    p for p in glob.glob("docs/agents-v0/milestones/*.md")
    if not os.path.basename(p).startswith("_")
)

approved_manifests = []
approved_requirements = []
seen_reqs = set()

for mf in manifests:
    dt = phase_approval_date(prog_state, mf, ["plan"])
    if not dt:
        continue
    approved_manifests.append({"path": mf, "approvalDate": dt})
    try:
        txt = open(mf, encoding="utf-8").read()
        for m in re.finditer(r"docs/agents-v0/requirements/([A-Za-z0-9._-]+)\.md", txt):
            slug = m.group(1)
            if slug.startswith("_"):
                continue
            req_md = f"docs/agents-v0/requirements/{slug}.md"
            req_st = f"docs/agents-v0/requirements/{slug}.state.json"
            if req_md not in seen_reqs and os.path.isfile(req_md):
                seen_reqs.add(req_md)
                rdt = phase_approval_date(req_st, req_md, ["intake"])
                if rdt:
                    approved_requirements.append({"path": req_md, "feature": slug, "approvalDate": rdt})
    except Exception:
        pass

if not approved_manifests:
    print("REFUSED:no approved milestone manifest found under docs/agents-v0/milestones/*.md (plan must be approved in docs/agents-v0/program.state.json or carry an Approved plan row)")
    sys.exit(1)

payload = {
    "projectKey": proj_key,
    "issueType": issue_type,
    "paramsPath": params_path,
    "sourcesPath": "docs/agents-v0/backlog/tickets-sources.md",
    "outputPath": "docs/agents-v0/backlog/tickets.csv",
    "approvedManifests": approved_manifests,
    "approvedRequirements": approved_requirements,
}
print("OK:" + json.dumps(payload, sort_keys=True))
PY
)" || true

  case "$ge_out" in
    REFUSED:*)
      gc_refuse check "${ge_out#REFUSED:}"
      ;;
    OK:*)
      ge_json="${ge_out#OK:}"
      gc_ok check "export-params.md and approved plan manifests verified; launch docs-author (skill: jira-export)"
      printf '%s\n' "$ge_json"
      ;;
    *)
      gc_refuse check "failed to inspect export sources ($ge_out)"
      ;;
  esac
}

ge_verify() {
  gc_to_root verify
  ge_need_kit verify
  ge_check >/dev/null

  [ -f docs/agents-v0/backlog/tickets-sources.md ] || gc_refuse verify "docs/agents-v0/backlog/tickets-sources.md is missing; write tickets-sources.md before tickets.csv"
  [ -f docs/agents-v0/backlog/tickets.csv ] || gc_refuse verify "docs/agents-v0/backlog/tickets.csv is missing"

  ge_hdr="$(head -n 1 docs/agents-v0/backlog/tickets.csv | tr -d '\r')"
  ge_exp_hdr="Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact"
  [ "$ge_hdr" = "$ge_exp_hdr" ] || gc_refuse verify "docs/agents-v0/backlog/tickets.csv header must be exactly '$ge_exp_hdr' with no preamble (got '$ge_hdr')"

  ge_vout="$(python3 - <<'PY'
import json
import os
import re
import subprocess
import sys

def is_approved_source(path):
    if path == "docs/agents-v0/backlog/export-params.md":
        return os.path.isfile(path)
    prog_state = "docs/agents-v0/program.state.json"
    if path.startswith("docs/agents-v0/milestones/") and path.endswith(".md"):
        if os.path.isfile(prog_state):
            try:
                st = json.load(open(prog_state, encoding="utf-8"))
                if "plan" in (st.get("approvedPhases") or []):
                    return True
            except Exception:
                pass
        if os.path.isfile(path):
            txt = open(path, encoding="utf-8").read()
            for line in txt.splitlines():
                if "|" in line and "plan" in line.lower() and "approved" in line.lower():
                    return True
        return False
    m = re.match(r"^docs/agents-v0/requirements/([A-Za-z0-9._-]+)\.md$", path)
    if m:
        slug = m.group(1)
        st_path = f"docs/agents-v0/requirements/{slug}.state.json"
        if os.path.isfile(st_path):
            try:
                st = json.load(open(st_path, encoding="utf-8"))
                if "intake" in (st.get("approvedPhases") or []):
                    return True
            except Exception:
                pass
        if os.path.isfile(path):
            txt = open(path, encoding="utf-8").read()
            for line in txt.splitlines():
                if "|" in line and "intake" in line.lower() and "approved" in line.lower():
                    return True
        return False
    return False

src_txt = open("docs/agents-v0/backlog/tickets-sources.md", encoding="utf-8").read()
cited = set(re.findall(r"(docs/agents-v0/[A-Za-z0-9._/-]+\.md)", src_txt))
cited.discard("docs/agents-v0/backlog/tickets-sources.md")
if not cited:
    print("REFUSED:docs/agents-v0/backlog/tickets-sources.md cites no source paths under docs/agents-v0/")
    sys.exit(1)

for p in sorted(cited):
    if not is_approved_source(p):
        print(f"REFUSED:docs/agents-v0/backlog/tickets-sources.md cites unapproved or disallowed source '{p}'")
        sys.exit(1)

st = subprocess.run(["git", "status", "--porcelain", "-uall"], capture_output=True, text=True, check=True)
outside = []
for line in st.stdout.splitlines():
    if not line.strip():
        continue
    raw = line[3:].strip()
    if " -> " in raw:
        raw = raw.split(" -> ", 1)[1].strip()
    raw = raw.strip('"')
    if raw.endswith(".lock"):
        continue
    if not raw.startswith("docs/agents-v0/backlog/"):
        outside.append(raw)

if outside:
    print("REFUSED:/v0-export is read-only outside docs/agents-v0/backlog/; modified or untracked paths found: " + ", ".join(outside))
    sys.exit(1)

print("OK:verified")
PY
)" || true

  case "$ge_vout" in
    REFUSED:*)
      gc_refuse verify "${ge_vout#REFUSED:}"
      ;;
    OK:*)
      gc_ok verify "tickets-sources.md and tickets.csv verified; source tree outside docs/agents-v0/backlog/ is untouched"
      ;;
    *)
      gc_refuse verify "verification failed ($ge_vout)"
      ;;
  esac
}

ge_commit() {
  gc_to_root commit
  ge_need_kit commit
  ge_b="$(gc_branch)" || gc_refuse commit "HEAD is detached; check out a branch first"
  ge_verify >/dev/null

  ge_paths="$(gc_rule export commit.paths)" || gc_refuse commit "gate-rules has no 'export commit.paths' rule"
  ge_msg="$(gc_rule export commit.message)" || gc_refuse commit "gate-rules has no 'export commit.message' rule"

  ge_out="$(gc_outside_paths "$ge_paths")" || gc_refuse commit "the index already holds paths outside export commit.paths: $ge_out"
  # shellcheck disable=SC2086
  git add --all -- $ge_paths || gc_refuse commit "git add of export paths failed"
  if git diff --cached --quiet --no-ext-diff 2>/dev/null; then
    gc_ok commit "tickets.csv and tickets-sources.md are already up to date on $ge_b (nothing new to commit)"
    return 0
  fi
  gc_scan_staged
  git commit -q -m "$ge_msg" || gc_refuse commit "git commit failed"
  gc_ok commit "export committed on $ge_b as $(git rev-parse --short HEAD) ($ge_msg)"
}

ge_steps() {
  cat <<'EOF'
1. **Pre-flight check & source discovery** — run:
   ```sh
   sh .agents-v0/scripts/guard-export.sh check
   ```
   Wait for exit `0` (`OK check: ...` + JSON manifest of `projectKey`, `issueType`, `approvedManifests`, and `approvedRequirements`). If it exits `1` because `Project key` or `Issue type` in `docs/agents-v0/backlog/export-params.md` is empty, ask the user once in chat (`yes` or explicit values), update `docs/agents-v0/backlog/export-params.md`, and re-run `check`. If no approved plan manifest exists, stop and direct the user to `/v0-plan`.
2. **Draft `tickets-sources.md` and `tickets.csv`** — launch the shell-less **`docs-author`** subagent (`core/common/agents/docs-author.md`, `shell: false`) with skill `jira-export` (`core/common/skills/jira-export/SKILL.md`) and the JSON manifest from Step 1. `docs-author` writes only `docs/agents-v0/backlog/tickets-sources.md` and `docs/agents-v0/backlog/tickets.csv` (with exact header `Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact` and no preamble). Do not edit any requirements, design, milestone, or `.state.json` files.
3. **Verify outputs & read-only source tree** — run:
   ```sh
   sh .agents-v0/scripts/guard-export.sh verify
   ```
   Wait for exit `0` (`OK verify: ...`). Confirms the 11-column CSV header, verifies every path cited in `tickets-sources.md` is approved, and verifies `git status --porcelain -uall` shows zero modifications outside `docs/agents-v0/backlog/`.
4. **Safe-staged commit** — run:
   ```sh
   sh .agents-v0/scripts/guard-export.sh commit
   ```
   Stages only `docs/agents-v0/backlog/export-params.md`, `docs/agents-v0/backlog/tickets-sources.md`, and `docs/agents-v0/backlog/tickets.csv`, scans staged content for secrets, and commits `v0(export): regenerate tickets.csv`.
EOF
}

ge_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-export.sh check | verify | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || ge_usage
ge_cmd="$1"; shift
case "$ge_cmd" in
  check)  [ $# -eq 0 ] || ge_usage; ge_check ;;
  verify) [ $# -eq 0 ] || ge_usage; ge_verify ;;
  commit) [ $# -eq 0 ] || ge_usage; ge_commit ;;
  steps)  [ $# -eq 0 ] || ge_usage; ge_steps ;;
  -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
  *) ge_usage ;;
esac
