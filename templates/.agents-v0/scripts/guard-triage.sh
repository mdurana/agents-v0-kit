#!/bin/sh
# guard-triage.sh — state-machine guard for /v0-triage (Trivial lane: docs-only or 1-for-1 patch bump).
#
# Subcommands:
#   check  [<id>] [--reopen]
#   start  <id>   [--reopen]
#   block  <id>   "<reason>"
#   ready  <id>
#   commit <id>
#   steps
#
# Design: DST1, DST2, DSTA, DST6.

set -eu
export PYTHONDONTWRITEBYTECODE=1

GC_HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD_COMMON_LIB=1 . "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-triage.sh"

gt_usage() {
  cat >&2 <<'EOF'
usage:
  sh .agents-v0/scripts/guard-triage.sh check [<id>] [--reopen]
  sh .agents-v0/scripts/guard-triage.sh start <id> [--reopen]
  sh .agents-v0/scripts/guard-triage.sh block <id> "<reason>"
  sh .agents-v0/scripts/guard-triage.sh ready <id>
  sh .agents-v0/scripts/guard-triage.sh commit <id>
  sh .agents-v0/scripts/guard-triage.sh steps
EOF
  exit 2
}

gt_rule() {
  gt_sub="$1"; gt_key="$2"; gt_slug="${3:-<id>}"
  gt_raw="$(gc_rule triage "$gt_key")"
  [ -n "$gt_raw" ] || gc_refuse "$gt_sub" "missing 'triage $gt_key' in $GC_RULES"
  gt_val="$(printf '%s' "$gt_raw" | sed "s|<feature>|$gt_slug|g; s|<id>|$gt_slug|g")"
}

gt_validate_slug() {
  gt_v_sub="$1"
  gt_v_slug="${2:-}"
  [ -n "$gt_v_slug" ] || gc_refuse "$gt_v_sub" "missing maintenance <id>; ask the user for <id> first"
  case "$gt_v_slug" in
    *[!a-z0-9-]*|-*|![a-z0-9]*)
      gc_refuse "$gt_v_sub" "invalid <id> '$gt_v_slug': must match ^[a-z0-9][a-z0-9-]*$ (lowercase letters, digits, hyphens)"
      ;;
  esac
  case "$gt_v_slug" in
    p0-a*)
      gc_refuse "$gt_v_sub" "'$gt_v_slug' is the platform skeleton; route to /v0-scaffold instead of /v0-triage"
      ;;
  esac
}

# Verify that any existing note.md or state.json for <id> is Tier: trivial (never standard or emergency).
gt_verify_trivial_tier() {
  gt_t_sub="$1"
  gt_t_slug="$2"
  gt_t_state="docs/agents-v0/maintain/${gt_t_slug}/state.json"
  gt_t_note="docs/agents-v0/maintain/${gt_t_slug}/note.md"
  if [ -f "$gt_t_state" ]; then
    gt_st_tier="$(gc_state_get "$gt_t_state" tier 2>/dev/null || true)"
    if [ -n "$gt_st_tier" ] && [ "$gt_st_tier" != "trivial" ]; then
      gc_refuse "$gt_t_sub" "maintenance note '$gt_t_slug' has tier '$gt_st_tier' in $gt_t_state (/v0-triage is exclusively for Tier: trivial; use /v0-maintain $gt_t_slug)"
    fi
  fi
  if [ -f "$gt_t_note" ]; then
    gt_nt_tier="$(GT_NOTE="$gt_t_note" python3 - <<'PY'
import os, re
raw = open(os.environ["GT_NOTE"], encoding="utf-8", errors="replace").read()
clean = re.sub(r"<!--.*?-->", "", raw, flags=re.S)
m = re.search(r"(?im)^\s*(?:-\s*)?(?:\*\*)?Tier(?:\*\*)?\s*:\s*`?([^\n`]+)`?\s*$", clean)
if m:
    val = m.group(1).strip().lower()
    if "|" not in val:
        print(val)
PY
)"
    if [ -n "$gt_nt_tier" ] && [ "$gt_nt_tier" != "trivial" ]; then
      gc_refuse "$gt_t_sub" "maintenance note '$gt_t_slug' declares 'Tier: $gt_nt_tier' in $gt_t_note (/v0-triage is exclusively for Tier: trivial; use /v0-maintain $gt_t_slug)"
    fi
  fi
}

# Deterministically inspect working-tree, staged, and since-base diffs against Trivial qualification criteria:
# - Only documentation edits (*.md, *.txt, *.rst, *.adoc, README, CHANGELOG, LICENSE, or docs/ excluding contracts)
# - Or 1-for-1 patch version bumps in dependency manifests/lockfiles (major.minor unchanged, equal +/- version lines)
# - Zero changes to controllers, auth/RBAC, security/deployment config, schemas/migrations, or API/event contracts.
gt_check_trivial_diff() {
  gt_d_sub="$1"
  gt_d_slug="${2:-}"
  gt_d_base="${3:-HEAD}"

  if ! gt_diff_err="$(GT_SLUG="$gt_d_slug" GT_BASE="$gt_d_base" python3 - <<'PYDIFF'
import os, re, subprocess, sys

slug = os.environ.get("GT_SLUG", "")
base_ref = os.environ.get("GT_BASE", "HEAD")

def run_git(args):
    r = subprocess.run(["git", "--no-optional-locks", *args], capture_output=True, text=True, check=False)
    return r.stdout if r.returncode == 0 else ""

has_head = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD"], capture_output=True, check=False).returncode == 0
if not has_head:
    sys.exit(0)

ref = base_ref if subprocess.run(["git", "rev-parse", "--verify", "-q", base_ref], capture_output=True, check=False).returncode == 0 else "HEAD"

paths = set()
for out in (
    run_git(["diff", "--name-only", ref]),
    run_git(["diff", "--cached", "--name-only"]),
    run_git(["ls-files", "--others", "--exclude-standard"]),
):
    for line in out.splitlines():
        p = line.strip()
        if p:
            paths.add(p)

if not paths:
    sys.exit(0)

LOCKFILES = {
    "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Cargo.lock", "go.sum",
    "poetry.lock", "uv.lock", "Pipfile.lock", "gradle.lockfile", "composer.lock", "Gemfile.lock"
}
MANIFESTS = {
    "pom.xml", "build.gradle", "build.gradle.kts", "package.json", "pyproject.toml",
    "requirements.txt", "Cargo.toml", "go.mod"
}

CONTRACT_RE = re.compile(
    r"(^|/)(openapi[^/]*\.(ya?ml|json)|asyncapi[^/]*\.(ya?ml|json)|[^/]+\.(proto|graphql|gql|avro|sql))$",
    re.I,
)
SECURITY_OR_SCHEMA_RE = re.compile(
    r"(^|/)(migrations?|flyway|liquibase|schema|auth|rbac|security|controllers?|Dockerfile|docker-compose[^/]*\.ya?ml|compose\.ya?ml)(/|$)",
    re.I,
)

def is_own_note_or_build(p):
    if not slug:
        return False
    return (
        p.startswith(f"docs/agents-v0/maintain/{slug}/")
        or p.startswith(f"docs/agents-v0/build/{slug}/")
    )

def is_other_story_artifact(p):
    m = re.match(r"^docs/agents-v0/(requirements|design|build|verify|release|maintain)/([^/]+)", p)
    if not m:
        return False
    kind_dir, item = m.group(1), m.group(2)
    if item.startswith("_"):
        return False
    if slug and kind_dir in ("maintain", "build") and item == slug:
        return False
    return True

def is_doc_file(p):
    bn = os.path.basename(p)
    if CONTRACT_RE.search(p) or p.startswith("openapi/"):
        return False
    if p.startswith("docs/"):
        return True
    if bn.endswith((".md", ".txt", ".rst", ".adoc")) or bn in ("README", "CHANGELOG", "LICENSE"):
        return True
    return False

def is_manifest_file(p):
    bn = os.path.basename(p)
    return bn in MANIFESTS or (bn.startswith("requirements") and bn.endswith(".txt"))

def check_manifest_patch_only(p):
    diff_txt = run_git(["diff", "-U0", ref, "--", p])
    if not diff_txt.strip():
        diff_txt = run_git(["diff", "--cached", "-U0", "--", p])
    if not diff_txt.strip():
        return None
    rem_lines = []
    add_lines = []
    for line in diff_txt.splitlines():
        if line.startswith("--- ") or line.startswith("+++ ") or line.startswith("@@"):
            continue
        if line.startswith("-") and line[1:].strip():
            rem_lines.append(line[1:].strip())
        elif line.startswith("+") and line[1:].strip():
            add_lines.append(line[1:].strip())
    if not rem_lines and not add_lines:
        return None
    if len(rem_lines) != len(add_lines):
        return (
            f"non-trivial dependency manifest change in '{p}' ({len(rem_lines)} removed vs {len(add_lines)} added lines; "
            f"/v0-triage only allows 1-for-1 patch version bumps — route to /v0-maintain with Tier: standard)"
        )
    ver_re = re.compile(r"(?<![0-9])([0-9]+)\.([0-9]+)\.([0-9]+)(?:-[A-Za-z0-9._-]+)?(?![0-9])")
    for r_line, a_line in zip(rem_lines, add_lines):
        r_vers = ver_re.findall(r_line)
        a_vers = ver_re.findall(a_line)
        if not r_vers or not a_vers or len(r_vers) != len(a_vers):
            return (
                f"non-trivial manifest edit in '{p}' ('{r_line}' -> '{a_line}' is not a 1-for-1 x.y.z patch version bump; "
                f"route to /v0-maintain with Tier: standard)"
            )
        # Ensure non-version text on the line is identical (same package/dependency name)
        r_skeleton = ver_re.sub("<VER>", r_line)
        a_skeleton = ver_re.sub("<VER>", a_line)
        if r_skeleton != a_skeleton:
            return (
                f"non-trivial manifest edit in '{p}' ('{r_line}' -> '{a_line}' changes dependency name or structure; "
                f"route to /v0-maintain with Tier: standard)"
            )
        for (rmaj, rmin, rpat), (amaj, amin, apat) in zip(r_vers, a_vers):
            if (rmaj, rmin) != (amaj, amin):
                return (
                    f"non-trivial version bump in '{p}' ({rmaj}.{rmin}.{rpat} -> {amaj}.{amin}.{apat} changes major/minor version; "
                    f"/v0-triage only allows 1-for-1 patch version bumps — route to /v0-maintain with Tier: standard)"
                )
            if rpat == apat:
                return (
                    f"manifest line in '{p}' ('{r_line}' -> '{a_line}') does not change patch version; "
                    f"route to /v0-maintain with Tier: standard"
                )
    return None

for p in sorted(paths):
    if is_own_note_or_build(p):
        continue
    if p.endswith(".lock") and ("state" in p or ".record." in p):
        continue
    if CONTRACT_RE.search(p) or p.startswith("openapi/"):
        print(
            f"ineligible for /v0-triage (Tier: trivial): contract or schema file '{p}' is modified "
            f"(API/event/schema contracts must route to /v0-maintain with Tier: standard or /v0-intake)"
        )
        sys.exit(1)
    if is_other_story_artifact(p):
        print(
            f"uncommitted changes belong to another story or note: '{p}' "
            f"(commit or stash other story files before running /v0-triage)"
        )
        sys.exit(1)
    bn = os.path.basename(p)
    if bn in LOCKFILES:
        continue
    if is_manifest_file(p):
        err = check_manifest_patch_only(p)
        if err:
            print(err)
            sys.exit(1)
        continue
    if is_doc_file(p):
        continue
    if SECURITY_OR_SCHEMA_RE.search(p):
        print(
            f"ineligible for /v0-triage (Tier: trivial): security, controller, schema, or deployment file '{p}' is modified "
            f"(route to /v0-maintain with Tier: standard or /v0-intake)"
        )
        sys.exit(1)
    print(
        f"ineligible for /v0-triage (Tier: trivial): non-documentation / non-patch file '{p}' is modified "
        f"(/v0-triage only allows documentation-only edits or 1-for-1 patch version bumps — route to /v0-maintain with Tier: standard or /v0-intake)"
    )
    sys.exit(1)
PYDIFF
)"; then
    gc_refuse "$gt_d_sub" "$gt_diff_err"
  fi
}

# Design: DST1 (/v0-triage check with pre-start trivial diff qualification and delegation to guard-maintain.sh).
gt_check() {
  gt_c_slug=""
  gt_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen) gt_c_reopen=1; shift ;;
      -*) gt_usage ;;
      *)
        [ -z "$gt_c_slug" ] || gt_usage
        gt_c_slug="$1"
        shift
        ;;
    esac
  done

  gc_to_root check
  [ -x .agents-v0/scripts/guard-maintain.sh ] || gc_refuse check "missing .agents-v0/scripts/guard-maintain.sh"

  if [ -z "$gt_c_slug" ]; then
    gt_check_trivial_diff check "" "HEAD"
    gc_ok check "working tree qualifies for /v0-triage (Tier: trivial); ask the user for <id> and run: $G check <id>"
    return 0
  fi

  gt_validate_slug check "$gt_c_slug"
  gt_verify_trivial_tier check "$gt_c_slug"
  gt_check_trivial_diff check "$gt_c_slug" "HEAD"

  if [ "$gt_c_reopen" = 1 ]; then
    gt_out="$(sh "$GC_HERE/guard-maintain.sh" check "$gt_c_slug" --tier trivial --reopen 2>&1)" || {
      printf '%s\n' "$gt_out" >&2
      exit 1
    }
  else
    gt_out="$(sh "$GC_HERE/guard-maintain.sh" check "$gt_c_slug" --tier trivial 2>&1)" || {
      printf '%s\n' "$gt_out" >&2
      exit 1
    }
  fi
  printf '%s\n' "$gt_out"
}

# Design: DST2 (/v0-triage start, block, ready, and commit delegating to guard-maintain.sh).
gt_start() {
  gt_s_slug=""
  gt_s_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen) gt_s_reopen=1; shift ;;
      -*) gt_usage ;;
      *)
        [ -z "$gt_s_slug" ] || gt_usage
        gt_s_slug="$1"
        shift
        ;;
    esac
  done

  gc_to_root start
  [ -x .agents-v0/scripts/guard-maintain.sh ] || gc_refuse start "missing .agents-v0/scripts/guard-maintain.sh"
  gt_validate_slug start "$gt_s_slug"
  gt_verify_trivial_tier start "$gt_s_slug"
  gt_check_trivial_diff start "$gt_s_slug" "HEAD"

  if [ "$gt_s_reopen" = 1 ]; then
    gt_out="$(sh "$GC_HERE/guard-maintain.sh" start "$gt_s_slug" --tier trivial --reopen 2>&1)" || {
      printf '%s\n' "$gt_out" >&2
      exit 1
    }
  else
    gt_out="$(sh "$GC_HERE/guard-maintain.sh" start "$gt_s_slug" --tier trivial 2>&1)" || {
      printf '%s\n' "$gt_out" >&2
      exit 1
    }
  fi

  gt_state="docs/agents-v0/maintain/${gt_s_slug}/state.json"
  gt_rule start start.next "$gt_s_slug"; gt_next="$gt_val"
  if [ -f "$gt_state" ]; then
    GT_ST="$gt_state" GT_NEXT="$gt_next" python3 - <<'PY'
import json, os
p = os.environ["GT_ST"]
d = json.load(open(p, encoding="utf-8"))
d["triageGuardManaged"] = True
d["nextStep"] = os.environ["GT_NEXT"]
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi

  gc_ok start "triage is in_progress for $gt_s_slug (tier=trivial, note=docs/agents-v0/maintain/${gt_s_slug}/note.md, report=docs/agents-v0/build/${gt_s_slug}/build-report.md)"
  printf 'Next: %s\n' "$gt_next"
}

gt_block() {
  gt_b_slug="${1:-}"
  shift || true
  gt_b_reason="${*:-}"
  gc_to_root block
  [ -x .agents-v0/scripts/guard-maintain.sh ] || gc_refuse block "missing .agents-v0/scripts/guard-maintain.sh"
  gt_validate_slug block "$gt_b_slug"
  [ -n "$(printf '%s' "$gt_b_reason" | tr -d '[:space:]')" ] || gc_refuse block "missing block reason"
  gt_verify_trivial_tier block "$gt_b_slug"

  gt_out="$(sh "$GC_HERE/guard-maintain.sh" block "$gt_b_slug" "$gt_b_reason" 2>&1)" || {
    printf '%s\n' "$gt_out" >&2
    exit 1
  }
  gt_state="docs/agents-v0/maintain/${gt_b_slug}/state.json"
  gt_rule block block.next "$gt_b_slug"; gt_next="$gt_val"
  if [ -f "$gt_state" ]; then
    GT_ST="$gt_state" GT_NEXT="$gt_next" python3 - <<'PY'
import json, os
p = os.environ["GT_ST"]
d = json.load(open(p, encoding="utf-8"))
d["nextStep"] = os.environ["GT_NEXT"]
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi
  gc_ok block "triage blocked for $gt_b_slug: $gt_b_reason"
  printf 'Next: %s\n' "$gt_next"
}

gt_ready() {
  [ $# -eq 1 ] || gt_usage
  gt_r_slug="$1"
  gc_to_root ready
  [ -x .agents-v0/scripts/guard-maintain.sh ] || gc_refuse ready "missing .agents-v0/scripts/guard-maintain.sh"
  gt_validate_slug ready "$gt_r_slug"
  gt_verify_trivial_tier ready "$gt_r_slug"

  gt_state="docs/agents-v0/maintain/${gt_r_slug}/state.json"
  gt_base="$(gc_state_get "$gt_state" baseCommit 2>/dev/null || true)"
  [ -n "$gt_base" ] || gt_base="HEAD"
  gt_check_trivial_diff ready "$gt_r_slug" "$gt_base"

  gt_out="$(sh "$GC_HERE/guard-maintain.sh" ready "$gt_r_slug" 2>&1)" || {
    printf '%s\n' "$gt_out" >&2
    exit 1
  }
  gt_rule ready ready.next "$gt_r_slug"; gt_next="$gt_val"
  if [ -f "$gt_state" ]; then
    GT_ST="$gt_state" GT_NEXT="$gt_next" python3 - <<'PY'
import json, os
p = os.environ["GT_ST"]
d = json.load(open(p, encoding="utf-8"))
d["triageGuardManaged"] = True
d["nextStep"] = os.environ["GT_NEXT"]
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  fi
  gc_ok ready "triage for $gt_r_slug is verified and awaiting the user's external approval"
  printf 'Next: %s\n' "$gt_next"
}

gt_commit() {
  [ $# -eq 1 ] || gt_usage
  gt_m_slug="$1"
  gc_to_root commit
  [ -x .agents-v0/scripts/guard-maintain.sh ] || gc_refuse commit "missing .agents-v0/scripts/guard-maintain.sh"
  gt_validate_slug commit "$gt_m_slug"
  gt_verify_trivial_tier commit "$gt_m_slug"

  gt_state="docs/agents-v0/maintain/${gt_m_slug}/state.json"
  gt_base="$(gc_state_get "$gt_state" baseCommit 2>/dev/null || true)"
  [ -n "$gt_base" ] || gt_base="HEAD"
  gt_check_trivial_diff commit "$gt_m_slug" "$gt_base"

  gt_out="$(sh "$GC_HERE/guard-maintain.sh" commit "$gt_m_slug" 2>&1)" || {
    printf '%s\n' "$gt_out" >&2
    exit 1
  }
  printf '%s\n' "$gt_out"
}

gt_steps() {
  [ $# -eq 0 ] || gt_usage
  cat <<'EOF'
1. **Resolve `<id>` & pre-qualify (`check`):** Ask for `<id>` when the user did not name one (`workflow-orchestration.mdc` Parallel Features); do not invent a slug or pick the newest note. Once `<id>` is named, read `docs/agents-v0/lessons.md` (`## Active lessons`) and run `sh .agents-v0/scripts/guard-triage.sh check <id>` (pass `--reopen` only when re-entering an already-approved trivial note with the user's explicit consent). The guard verifies the repo/kit prerequisites, confirms `Tier: trivial` when `docs/agents-v0/maintain/<id>/note.md` exists, and pre-qualifies any dirty or staged diff on the integration branch as documentation-only (`*.md`, `docs/**` excluding API/event/schema contracts) or a 1-for-1 `x.y.z` patch version bump in dependency manifests/lockfiles with zero controller, auth/RBAC, session, upload, CORS, security/deployment config, schema/migration, or API/event contract changes. If the guard refuses, stop and route to `/v0-maintain <id>` (`Tier: standard`) or `/v0-intake`.
2. **Start on the integration branch (`start`):** Run `sh .agents-v0/scripts/guard-triage.sh start <id>` (pass `--reopen` when reopening). The guard delegates to `guard-maintain.sh start <id> --tier trivial` on the integration branch (no `maintain/<id>` worktree is created for `Tier: trivial`), seeds `docs/agents-v0/maintain/<id>/note.md` (`Tier: trivial`) and `docs/agents-v0/build/<id>/build-report.md`, and sets `docs/agents-v0/maintain/<id>/state.json` to `activePhase: "maintain"`, `activeStatus: "in_progress"` with `triageGuardManaged: true`. Ask the user in chat to confirm the `trivial` tier (`Tier confirmed by: <person> on <YYYY-MM-DD>`); that chat confirmation is a note field, not external gate approval.
3. **Author via shell-less `maintenance-engineer`:** Once the user confirms the `trivial` tier in chat, record `Tier confirmed by: <person> on <YYYY-MM-DD>` in `docs/agents-v0/maintain/<id>/note.md` and launch the shell-less `maintenance-engineer` subagent (`doc-sync` for documentation updates; `dependency-upgrade` for 1-for-1 patch version bumps). If the subagent writes `docs/agents-v0/maintain/<id>/helper-brief.md` (`helper: docs-author`), launch the named helper from the main session and return its draft. For a 1-for-1 patch bump, run the profile native verification command (`sh .agents-v0/scripts/run-backend-verify.sh` or stack equivalent, teeing output to `docs/agents-v0/build/<id>/build-output.txt`) so `maintenance-engineer` records the command-result card in `docs/agents-v0/build/<id>/build-report.md` and authors `## Lessons` -> `### maintain` in `docs/agents-v0/maintain/<id>/phase-result.md`. If a blocker occurs, run `sh .agents-v0/scripts/guard-triage.sh block <id> "<reason>"` and stop.
4. **Verify trivial scope & mark awaiting approval (`ready`):** Run `sh .agents-v0/scripts/guard-triage.sh ready <id>`. The guard re-verifies the entire diff since `baseCommit` (rejecting any non-doc/non-lockfile file, any contract file under `docs/`, or any non-patch manifest edit), checks `Tier confirmed by`, runs onboarding citation checks when `docs/agents-v0/onboarding/report.md` exists, writes `docs/agents-v0/maintain/<id>/phase-result.md` (`status: awaiting_approval`), and sets `state.json` to `awaiting_approval`. Present the diff and `docs/agents-v0/maintain/<id>/note.md` to the user and **stop the turn**. Do not run `approve` or `commit` in the same turn.
5. **External approval & gate commit (`approve` -> `commit`, `kitfix-20261031-gate-commit`):** The user approves from an external terminal outside Cursor via `sh .agents-v0/scripts/guard-common.sh approve triage <id>` (or `approve maintain <id>`). On the next turn, run `sh .agents-v0/scripts/guard-triage.sh commit <id>` to verify the external approval record, re-verify the trivial diff scope, scan staged files for secrets, and create the `maintain(<id>): approve trivial triage gate` commit. Next is `/v0-verify <id> --maintain` (Abbreviated Verify: native build/test command without `security-reviewer` or `code-reviewer`), then `/v0-local-release <id> --maintain` (or `/v0-deliver <id> --maintain`).
EOF
}

cmd="${1:-}"
[ -n "$cmd" ] || gt_usage
shift || true

case "$cmd" in
  check)  gt_check "$@" ;;
  start)  gt_start "$@" ;;
  block)  gt_block "$@" ;;
  ready)  gt_ready "$@" ;;
  commit) gt_commit "$@" ;;
  steps)  gt_steps "$@" ;;
  *)      gt_usage ;;
esac
