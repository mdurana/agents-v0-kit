#!/bin/sh
# Deterministic guard for /v0-deck (Step 5.2 export & deck redo, Design: DEX1..DEX8, DEXA).
#
# Subcommands:
#   sh .agents-v0/scripts/guard-deck.sh check intake <feature> <audience> <decision>
#   sh .agents-v0/scripts/guard-deck.sh check product <audience> <decision>
#   sh .agents-v0/scripts/guard-deck.sh check delivery <audience> <decision>
#   sh .agents-v0/scripts/guard-deck.sh verify intake <feature>
#   sh .agents-v0/scripts/guard-deck.sh verify product
#   sh .agents-v0/scripts/guard-deck.sh verify delivery
#   sh .agents-v0/scripts/guard-deck.sh commit intake <feature>
#   sh .agents-v0/scripts/guard-deck.sh commit product
#   sh .agents-v0/scripts/guard-deck.sh commit delivery
#   sh .agents-v0/scripts/guard-deck.sh steps
#
# Output protocol (inherited from guard-common.sh):
#   OK <step>: <one-line summary>
#   REFUSED <step>: <why — and the next action>
#   ERROR <step>: <internal/usage failure>
#
# Exit codes: 0 passed, 1 refused, 2 usage/internal error.

set -eu

GD_HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD_COMMON_LIB=1 . "$GD_HERE/guard-common.sh"

gd_need_kit() {
  [ -f .agents-v0/gate-rules ] || gc_refuse "$1" ".agents-v0/gate-rules is missing; reinstall the kit (install.sh --update)"
}

gd_check() {
  gc_to_root check
  gd_need_kit check
  command -v python3 >/dev/null 2>&1 || gc_refuse check "python3 is required for guard-deck.sh"

  [ $# -ge 1 ] || gc_refuse check "missing deck kind (expected intake, product, or delivery)"
  gd_kind="$1"; shift
  gd_feature=""
  case "$gd_kind" in
    intake)
      [ $# -ge 1 ] || gc_refuse check "intake deck requires <feature> <audience> <decision>"
      gd_feature="$1"; shift
      ;;
    product|delivery)
      ;;
    *)
      gc_refuse check "invalid deck kind '$gd_kind' (expected intake, product, or delivery)"
      ;;
  esac

  [ $# -ge 1 ] || gc_refuse check "missing <audience> (expected Technical, Non-technical, or Mixed)"
  gd_audience="$1"; shift
  case "$gd_audience" in
    Technical|Non-technical|Mixed) ;;
    *) gc_refuse check "invalid audience '$gd_audience' (expected Technical, Non-technical, or Mixed)" ;;
  esac

  gd_decision="$*"
  gd_decision_trimmed="$(printf '%s' "$gd_decision" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "$gd_decision_trimmed" ] || gc_refuse check "missing <decision> sentence for the meeting"

  gd_out="$(python3 - "$gd_kind" "$gd_feature" "$gd_audience" "$gd_decision_trimmed" <<'PY'
import glob
import json
import os
import re
import sys

kind, feature, audience, decision = sys.argv[1:5]
prog_state = "docs/agents-v0/program.state.json"

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

sources = []

if kind == "intake":
    req_md = f"docs/agents-v0/requirements/{feature}.md"
    req_st = f"docs/agents-v0/requirements/{feature}.state.json"
    if not os.path.isfile(req_md):
        print(f"REFUSED:{req_md} does not exist")
        sys.exit(1)
    dt = phase_approval_date(req_st, req_md, ["intake"])
    if not dt:
        print(f"REFUSED:{req_md} does not have intake approved in {req_st} or an Approved intake row")
        sys.exit(1)
    sources.append({"path": req_md, "approvalDate": dt, "role": "intake"})

    req_txt = open(req_md, encoding="utf-8").read()
    m_story = re.search(r"^Story:[ \t]*([^\r\n]+)$", req_txt, re.M)
    story_id = m_story.group(1).strip() if m_story else ""
    m_mf = re.search(r"^Milestone file:[ \t]*([^\r\n]+)$", req_txt, re.M)
    mf_path = m_mf.group(1).strip().strip("`") if m_mf else ""
    if mf_path and mf_path.lower() not in ("none", "n/a", "-", "<path>"):
        if not os.path.isfile(mf_path):
            print(f"REFUSED:Milestone file '{mf_path}' referenced by {req_md} does not exist")
            sys.exit(1)
        mf_txt = open(mf_path, encoding="utf-8").read()
        if not story_id or story_id not in mf_txt:
            print(f"REFUSED:Milestone file '{mf_path}' does not contain Story '{story_id}' from {req_md}")
            sys.exit(1)
        mdt = phase_approval_date(prog_state, mf_path, ["plan"])
        if not mdt:
            print(f"REFUSED:Milestone file '{mf_path}' does not have plan approved in {prog_state} or an Approved plan row")
            sys.exit(1)
        sources.append({"path": mf_path, "approvalDate": mdt, "role": "plan"})

    stem = f"{feature}-intake"
else:
    roadmaps = sorted(
        p for p in glob.glob("docs/agents-v0/roadmap/*.md")
        if not os.path.basename(p).startswith("_")
    )
    rm_path = None
    rm_dt = None
    for cand in roadmaps:
        dt = phase_approval_date(prog_state, cand, ["roadmap"])
        if dt:
            rm_path = cand
            rm_dt = dt
            break
    if not rm_path:
        print("REFUSED:no approved roadmap found under docs/agents-v0/roadmap/*.md (roadmap must be approved in program.state.json or carry an Approved roadmap row)")
        sys.exit(1)
    sources.append({"path": rm_path, "approvalDate": rm_dt, "role": "roadmap"})
    rm_txt = open(rm_path, encoding="utf-8").read()
    m_disc = re.search(r"^Discovery:[ \t]*([^\r\n]+)$", rm_txt, re.M)
    disc_path = m_disc.group(1).strip().strip("`") if m_disc else ""
    if disc_path and disc_path.lower() not in ("none", "n/a", "-", "<path>"):
        if not os.path.isfile(disc_path):
            print(f"REFUSED:Discovery file '{disc_path}' referenced by {rm_path} does not exist")
            sys.exit(1)
        sources.append({"path": disc_path, "approvalDate": rm_dt, "role": "discovery"})

    ctx_path = "docs/agents-v0/design/system/context-map.md"
    if not os.path.isfile(ctx_path):
        print(f"REFUSED:{ctx_path} is missing")
        sys.exit(1)
    ctx_dt = phase_approval_date(prog_state, ctx_path, ["plan", "architecture"])
    if not ctx_dt:
        for mf in sorted(glob.glob("docs/agents-v0/milestones/*.md")):
            if os.path.basename(mf).startswith("_"):
                continue
            dt = phase_approval_date(prog_state, mf, ["plan"])
            if dt and "context-map.md" in open(mf, encoding="utf-8").read():
                ctx_dt = dt
                break
    if not ctx_dt:
        print(f"REFUSED:{ctx_path} is not admitted by an approved plan or architecture phase")
        sys.exit(1)
    sources.append({"path": ctx_path, "approvalDate": ctx_dt, "role": "context-map"})

    arc_path = "docs/agents-v0/design/system/arc-record.md"
    if os.path.isfile(arc_path):
        arc_dt = phase_approval_date(prog_state, arc_path, ["architecture", "arc"])
        if not arc_dt and os.path.isfile("docs/agents-v0/architecture.md"):
            arch_txt = open("docs/agents-v0/architecture.md", encoding="utf-8").read()
            if "arc-record.md" in arch_txt:
                arc_dt = phase_approval_date(prog_state, "docs/agents-v0/architecture.md", ["architecture"])
        if not arc_dt:
            print(f"REFUSED:{arc_path} exists on disk but is not admitted by an approved architecture or arc phase")
            sys.exit(1)
        sources.append({"path": arc_path, "approvalDate": arc_dt, "role": "arc"})

    for req_md in sorted(glob.glob("docs/agents-v0/requirements/*.md")):
        base = os.path.basename(req_md)
        if base.startswith("_") or base.endswith(".phase-result.md") or base.endswith(".helper-brief.md") or base.endswith(".failure-brief.md"):
            continue
        slug = base[:-3]
        req_st = f"docs/agents-v0/requirements/{slug}.state.json"
        rdt = phase_approval_date(req_st, req_md, ["intake"])
        if rdt:
            sources.append({"path": req_md, "approvalDate": rdt, "role": "intake"})

    rm_stem = os.path.splitext(os.path.basename(rm_path))[0]
    if kind == "product":
        stem = rm_stem
    else:
        stem = f"{rm_stem}-delivery"
        manifests = sorted(
            p for p in glob.glob("docs/agents-v0/milestones/*.md")
            if not os.path.basename(p).startswith("_")
        )
        any_manifest = False
        for mf in manifests:
            mdt = phase_approval_date(prog_state, mf, ["plan"])
            if mdt:
                any_manifest = True
                sources.append({"path": mf, "approvalDate": mdt, "role": "plan"})
        if not any_manifest:
            print("REFUSED:delivery deck requires at least one approved milestone manifest under docs/agents-v0/milestones/*.md")
            sys.exit(1)

        for req_md in sorted(glob.glob("docs/agents-v0/requirements/*.md")):
            base = os.path.basename(req_md)
            if base.startswith("_") or base.endswith(".phase-result.md") or base.endswith(".helper-brief.md") or base.endswith(".failure-brief.md"):
                continue
            slug = base[:-3]
            req_st = f"docs/agents-v0/requirements/{slug}.state.json"
            reldt = phase_approval_date(req_st, req_md, ["release"])
            if not reldt:
                continue
            v_art = f"docs/agents-v0/verify/{slug}/quality-gate.md"
            b_art = f"docs/agents-v0/build/{slug}/build-report.md"
            pr_art = f"docs/agents-v0/requirements/{slug}.phase-result.md"
            if os.path.isfile(req_st):
                try:
                    st = json.load(open(req_st, encoding="utf-8"))
                    arts = st.get("artifacts") or {}
                    v_art = arts.get("verify") or v_art
                    b_art = arts.get("buildReport") or b_art
                except Exception:
                    pass
            for ev in (v_art, b_art, pr_art):
                if not os.path.isfile(ev):
                    print(f"REFUSED:release-approved story '{slug}' is missing release evidence '{ev}'")
                    sys.exit(1)
                sources.append({"path": ev, "approvalDate": reldt, "role": "release-evidence"})

payload = {
    "kind": kind,
    "feature": feature,
    "audience": audience,
    "decision": decision,
    "stem": stem,
    "deckPath": f"docs/agents-v0/presentations/{stem}.md",
    "paramsPath": f"docs/agents-v0/presentations/{stem}.params.md",
    "sources": sources,
}
print("OK:" + json.dumps(payload, sort_keys=True))
PY
)" || true

  case "$gd_out" in
    REFUSED:*)
      gc_refuse check "${gd_out#REFUSED:}"
      ;;
    OK:*)
      gd_json="${gd_out#OK:}"
      gc_ok check "$gd_kind deck arguments and approved sources verified; launch docs-author (skill: leadership-deck)"
      printf '%s\n' "$gd_json"
      ;;
    *)
      gc_refuse check "failed to inspect deck sources ($gd_out)"
      ;;
  esac
}

gd_resolve_stem() {
  python3 - "$1" "${2:-}" <<'PY'
import glob
import json
import os
import re
import sys

kind, feature = sys.argv[1], sys.argv[2]
if kind == "intake":
    if not feature:
        sys.exit(1)
    print(f"{feature}-intake")
    sys.exit(0)

prog_state = "docs/agents-v0/program.state.json"
roadmaps = sorted(
    p for p in glob.glob("docs/agents-v0/roadmap/*.md")
    if not os.path.basename(p).startswith("_")
)
if not roadmaps:
    sys.exit(1)
rm_stem = os.path.splitext(os.path.basename(roadmaps[0]))[0]
print(rm_stem if kind == "product" else f"{rm_stem}-delivery")
PY
}

gd_verify() {
  gc_to_root verify
  gd_need_kit verify
  [ $# -ge 1 ] || gc_refuse verify "missing deck kind (expected intake, product, or delivery)"
  gd_kind="$1"; shift
  gd_feature=""
  case "$gd_kind" in
    intake)
      [ $# -eq 1 ] || gc_refuse verify "usage: guard-deck.sh verify intake <feature>"
      gd_feature="$1"
      ;;
    product|delivery)
      [ $# -eq 0 ] || gc_refuse verify "usage: guard-deck.sh verify $gd_kind"
      ;;
    *)
      gc_refuse verify "invalid deck kind '$gd_kind' (expected intake, product, or delivery)"
      ;;
  esac

  gd_stem="$(gd_resolve_stem "$gd_kind" "$gd_feature" 2>/dev/null || true)"
  [ -n "$gd_stem" ] || gc_refuse verify "could not resolve deck stem for '$gd_kind' (ensure approved roadmap exists for product/delivery)"

  gd_deck="docs/agents-v0/presentations/${gd_stem}.md"
  gd_params="docs/agents-v0/presentations/${gd_stem}.params.md"
  [ -f "$gd_deck" ] || gc_refuse verify "$gd_deck is missing"
  [ -f "$gd_params" ] || gc_refuse verify "$gd_params is missing"

  gd_ptxt="$(cat "$gd_params")"
  gd_pkind="$(printf '%s\n' "$gd_ptxt" | sed -n 's/^Kind:[[:space:]]*//p' | head -n 1 | tr -d '\r')"
  gd_paud="$(printf '%s\n' "$gd_ptxt" | sed -n 's/^Audience:[[:space:]]*//p' | head -n 1 | tr -d '\r')"
  gd_pdec="$(printf '%s\n' "$gd_ptxt" | sed -n 's/^Decision:[[:space:]]*//p' | head -n 1 | tr -d '\r')"

  [ "$gd_pkind" = "$gd_kind" ] || gc_refuse verify "$gd_params Kind must be '$gd_kind' (got '$gd_pkind')"
  case "$gd_paud" in
    Technical|Non-technical|Mixed) ;;
    *) gc_refuse verify "$gd_params Audience must be Technical, Non-technical, or Mixed (got '$gd_paud')" ;;
  esac
  [ -n "$gd_pdec" ] && [ "$gd_pdec" != "<the question the meeting must answer, in the user's words>" ] || gc_refuse verify "$gd_params Decision is empty or still holds template placeholder"

  if [ "$gd_kind" = "intake" ]; then
    gd_chk_json="$(gd_check intake "$gd_feature" "$gd_paud" "$gd_pdec" | tail -n 1)" || exit 1
  else
    gd_chk_json="$(gd_check "$gd_kind" "$gd_paud" "$gd_pdec" | tail -n 1)" || exit 1
  fi

  gd_vout="$(python3 - "$gd_params" "$gd_chk_json" <<'PY'
import json
import re
import subprocess
import sys

params_path, chk_json = sys.argv[1:3]
payload = json.loads(chk_json)
allowed = {s["path"] for s in payload.get("sources") or []}

ptxt = open(params_path, encoding="utf-8").read()
cited = set(re.findall(r"(docs/agents-v0/[A-Za-z0-9._/-]+\.md)", ptxt))
cited.discard(params_path)
cited.discard(payload.get("deckPath", ""))

if not cited:
    print(f"REFUSED:{params_path} cites no source paths under ## Sources")
    sys.exit(1)

for p in sorted(cited):
    if p not in allowed:
        print(f"REFUSED:{params_path} cites unapproved or disallowed source '{p}'")
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
    if not raw.startswith("docs/agents-v0/presentations/"):
        outside.append(raw)

if outside:
    print("REFUSED:/v0-deck is read-only outside docs/agents-v0/presentations/; modified or untracked paths found: " + ", ".join(outside))
    sys.exit(1)

print("OK:verified")
PY
)" || true

  case "$gd_vout" in
    REFUSED:*)
      gc_refuse verify "${gd_vout#REFUSED:}"
      ;;
    OK:*)
      gc_ok verify "$gd_deck and $gd_params verified; source tree outside docs/agents-v0/presentations/ is untouched"
      ;;
    *)
      gc_refuse verify "deck verification failed ($gd_vout)"
      ;;
  esac
}

gd_commit() {
  gc_to_root commit
  gd_need_kit commit
  gd_b="$(gc_branch)" || gc_refuse commit "HEAD is detached; check out a branch first"
  gd_verify "$@" >/dev/null

  gd_kind="$1"
  gd_feature="${2:-}"
  gd_stem="$(gd_resolve_stem "$gd_kind" "$gd_feature")"
  gd_deck="docs/agents-v0/presentations/${gd_stem}.md"
  gd_params="docs/agents-v0/presentations/${gd_stem}.params.md"
  gd_paths="$gd_deck $gd_params"
  gd_msg="v0(deck): write ${gd_stem} briefing"

  gd_out="$(gc_outside_paths "$gd_paths")" || gc_refuse commit "the index already holds paths outside deck commit.paths: $gd_out"
  # shellcheck disable=SC2086
  git add --all -- $gd_paths || gc_refuse commit "git add of deck paths failed"
  if git diff --cached --quiet --no-ext-diff 2>/dev/null; then
    gc_ok commit "$gd_deck and $gd_params are already up to date on $gd_b (nothing new to commit)"
    return 0
  fi
  gc_scan_staged
  git commit -q -m "$gd_msg" || gc_refuse commit "git commit failed"
  gc_ok commit "deck committed on $gd_b as $(git rev-parse --short HEAD) ($gd_msg)"
}

gd_steps() {
  cat <<'EOF'
1. **Pre-flight check & source-approval validation** — run:
   ```sh
   sh .agents-v0/scripts/guard-deck.sh check <kind> [<feature>] <audience> <decision>
   ```
   Wait for exit `0` (`OK check: ...` + JSON manifest of `kind`, `audience`, `decision`, `deckPath`, `paramsPath`, and `sources`). When `<kind>`, `<feature>` (for `intake`), `<audience>` (`Technical`, `Non-technical`, or `Mixed`), or `<decision>` is missing or any required source is not yet approved in `.state.json` (or legacy `Approved` row), stop and report the refusal verbatim.
2. **Draft deck and `.params.md`** — launch the shell-less **`docs-author`** subagent (`core/common/agents/docs-author.md`, `shell: false`) with skill `leadership-deck` (`core/common/skills/leadership-deck/SKILL.md`) and the JSON manifest from Step 1. `docs-author` writes only `docs/agents-v0/presentations/<stem>.md` and `docs/agents-v0/presentations/<stem>.params.md`, copying figures, dates, and scenario text strictly from the admitted sources. Do not edit any source or `.state.json` files.
3. **Verify deck, provenance params, & read-only source tree** — run:
   ```sh
   sh .agents-v0/scripts/guard-deck.sh verify <kind> [<feature>]
   ```
   Wait for exit `0` (`OK verify: ...`). Confirms `<stem>.md` and `<stem>.params.md` exist, `Kind:`, `Audience:`, `Decision:`, and `## Sources` in `<stem>.params.md` cite only approved sources, and `git status --porcelain -uall` shows zero modifications outside `docs/agents-v0/presentations/`.
4. **Safe-staged commit** — run:
   ```sh
   sh .agents-v0/scripts/guard-deck.sh commit <kind> [<feature>]
   ```
   Stages only `docs/agents-v0/presentations/<stem>.md` and `docs/agents-v0/presentations/<stem>.params.md`, scans staged content for secrets, and commits `v0(deck): write <stem> briefing`.
EOF
}

gd_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-deck.sh check <kind> [<feature>] <audience> <decision> | verify <kind> [<feature>] | commit <kind> [<feature>] | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || gd_usage
gd_cmd="$1"; shift
case "$gd_cmd" in
  check)  gd_check "$@" ;;
  verify) gd_verify "$@" ;;
  commit) gd_commit "$@" ;;
  steps)  [ $# -eq 0 ] || gd_usage; gd_steps ;;
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  *) gd_usage ;;
esac
