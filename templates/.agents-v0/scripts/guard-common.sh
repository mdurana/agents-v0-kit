#!/bin/sh
# guard-common.sh: the shared guard of the onboard redo (design: kit-eval/reviews/jiraiya-onboard-redo-design-20261102.md,
# "The split"). It is meant to be the only writer of workflow state (state file, approval record, secret scan, commit and
# tag, branch checks). D1 built the base and the secret scan; D2 adds the gate-rules reader and the state writer
# (gc_rule, gc_state_get, gc_state_set). DA adds the approval record (approve, gc_approval_ok). D4 adds the commit
# and tag (gc_commit_tag, called by the guard scripts after their own approval checks).
#
# Run:
#   sh .agents-v0/scripts/guard-common.sh scan-staged [--message-file FILE]
#        scan what is staged for the next commit (secret_scan.py --staged); run it right before `git commit`.
#   sh .agents-v0/scripts/guard-common.sh scan-push [<remote name>]  < pre-push input lines
#        scan every commit a push would send (secret_scan.py --commits); the pre-push hook runs it.
#   sh .agents-v0/scripts/guard-common.sh branch-check [<branch>]
#        print the current branch; refuse a detached HEAD, or a branch other than <branch> when given.
#   sh .agents-v0/scripts/guard-common.sh paths
#        print the repository root, the git common dir, the onboarding state file path and the approval folder.
#   sh .agents-v0/scripts/guard-common.sh approve <command>          (Design: DA/DRA/DAA; Sensei only, in his own terminal)
#        Sensei approves <command> (onboard, roadmap, architecture) himself, in his own terminal outside Cursor. It needs the command's
#        state at awaiting_approval, shows the repo, HEAD and baseCommit, and reads the approver's words from the
#        terminal (/dev/tty; there is no flag for them). It writes the approval record, then marks the phase
#        approved in the state (approvedPhases, lastApprovedPhase, phaseDates, phaseTimes; active phase cleared).
#        The Cursor hook denies an agent running it, and any agent write or shell command on the approval folder.
#        Approval folder (outside the repo, keyed per repo):
#          <home>/.agents-v0-approvals/<repo id>/<command>.json
#        <home> is the user's home from the password database (not $HOME); <repo id> is
#        <main checkout folder name>-<first 12 hex of sha256 of the absolute git common dir>, so every worktree of a
#        repository shares one folder. Folder mode 700, record mode 600, written atomically under <record>.lock.
#        Record (JSON): command, phase, repo (work tree root), repoId, gitCommonDir, head (HEAD when approved),
#        baseCommit (the state's baseCommit it approves), approvedAt (local time with offset), approver (login
#        name), words (exactly as typed). Kit test copies only: AGENTS_V0_APPROVALS_DIR replaces
#        <home>/.agents-v0-approvals (install.sh strips that override from installed copies).
# Use as a library (other guard scripts): GC_HERE=<dir> GUARD_COMMON_LIB=1 . "<dir>/guard-common.sh", then call the gc_* functions.
#   gc_approval_ok <command> (DA, for D4): OK when this repo's approval record for <command> matches the state's baseCommit.
#   gc_commit_tag <command> (D4): stage <command>'s gate-rules commit.paths, scan, commit once, tag the next <tag><n>.
#
# Output: `OK <step>: <what passed>` (exit 0) or `REFUSED <step>: <reason>` (exit 1) on stdout; usage errors on
# stderr (exit 2). The scanner's own lines (HIT, ALLOWED, SECRET-SCAN ...) pass through; it never prints a secret.
# Every exit code but 0 is a stop (fail closed).
set -eu

# A library user sets GC_HERE to the scripts dir before sourcing; $0 is then the caller.
GC_HERE="${GC_HERE:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
GC_ZERO="0000000000000000000000000000000000000000"

gc_ok() { printf 'OK %s: %s\n' "$1" "$2"; return 0; }
gc_refuse() { printf 'REFUSED %s: %s\n' "$1" "$2"; exit 1; }
gc_die() { printf 'error: %s\n' "$1" >&2; exit 2; }

# --- base: repository root, git paths, state file paths ---------------------------------------------------------
# gc_root: the work tree root (exit 1 outside a work tree).
gc_root() { git rev-parse --show-toplevel 2>/dev/null; }
# gc_to_root <step>: cd to the work tree root or refuse <step>.
gc_to_root() {
  gc_r="$(gc_root)" || gc_refuse "$1" "not inside a git work tree"
  [ -n "$gc_r" ] || gc_refuse "$1" "not inside a git work tree"
  cd "$gc_r"
}
# gc_common_dir: the absolute git common dir (shared by every worktree of the repository).
gc_common_dir() {
  gc_cd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  (cd "$gc_cd" && pwd)
}
# gc_git_path <name>: a file in this worktree's git dir (git rev-parse --git-path).
gc_git_path() { git rev-parse --git-path "$1"; }
# gc_state_file <kind> [<name>]: the state file path, relative to the root, for onboarding, program, feature <name>
# or maintain <id> (the paths sync-feature-state.sh and the pre-push hook use).
gc_state_file() {
  case "${1:-}" in
    onboarding|onboard) printf 'docs/agents-v0/onboarding/state.json\n' ;;
    program) printf 'docs/agents-v0/program.state.json\n' ;;
    feature) [ -n "${2:-}" ] || return 2; printf 'docs/agents-v0/requirements/%s.state.json\n' "$2" ;;
    maintain) [ -n "${2:-}" ] || return 2; printf 'docs/agents-v0/maintain/%s/state.json\n' "$2" ;;
    *) return 2 ;;
  esac
}

# --- gate rules and state (Design: D2, DIA) ---------------------------------------------------------------------------
# gc_rule <command> <key> [<feature>]: print the value of `<command> <key> <value>` from .agents-v0/gate-rules (data only);
# exit 1 when the file or the rule is missing. When <feature> is given, substitutes `<feature>` in the value.
gc_rule() {
  gc_rules="${GC_RULES:-$GC_HERE/../gate-rules}"
  [ -f "$gc_rules" ] || return 1
  gc_r_val="$(awk -v c="$1" -v k="$2" '
    /^[[:space:]]*#/ || NF < 3 { next }
    $1 == c && $2 == k { sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, ""); print; found = 1; exit }
    END { exit found ? 0 : 1 }' "$gc_rules")" || return 1
  if [ -n "${3:-}" ]; then
    gc_r_val="$(printf '%s' "$gc_r_val" | sed "s/<feature>/$3/g")"
  fi
  printf '%s\n' "$gc_r_val"
}
# gc_state_get <state file> <key>: print a top-level value of a state file (empty when the file or key is missing).
gc_state_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    v = json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], "")
except FileNotFoundError:
    v = ""
if isinstance(v, (list, dict)):
    print(json.dumps(v))
elif isinstance(v, bool):
    print("true" if v else "false")
else:
    print(v)
PY
}
# gc_state_set <state file> <feature> <artifact> <key>=<value>...: the one state writer (design: "guard-common.sh is
# the only writer of state"). Sets the given string keys (activePhase, activeStatus, blockedReason, nextStep) and
# updatedAt, keeps every other key, and writes atomically under <state file>.lock (the lock sync-feature-state.sh
# takes). A missing file is created with the keys sync-feature-state.sh writes, so stories-status.sh reads it.
# approvePhase=<phase> (DA) marks <phase> approved the way sync-feature-state.sh --approve does: appended to
# approvedPhases, lastApprovedPhase, phaseDates (today) and phaseTimes (now). An empty activeStatus clears it.
# Not a CLI step on purpose: only guard scripts call it, after their own checks.
gc_state_set() {
  [ $# -ge 4 ] || gc_die "gc_state_set: needs <state file> <feature> <artifact> <key>=<value>..."
  python3 - "$@" <<'PY'
import datetime, fcntl, json, os, subprocess, sys, tempfile

out, feature, artifact = sys.argv[1], sys.argv[2], sys.argv[3]
keys = {"activePhase", "activeStatus", "blockedReason", "nextStep", "approvePhase"}
statuses = {"in_progress", "awaiting_approval", "blocked", ""}
sets = {}
for pair in sys.argv[4:]:
    k, sep, v = pair.partition("=")
    if not sep or k not in keys:
        print(f"error: gc_state_set: cannot set {k!r} (allowed: {', '.join(sorted(keys))})", file=sys.stderr)
        raise SystemExit(2)
    sets[k] = v
if "activeStatus" in sets and sets["activeStatus"] not in statuses:
    print(f"error: gc_state_set: activeStatus must be one of {', '.join(sorted(statuses))}", file=sys.stderr)
    raise SystemExit(2)
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
lock = open(out + ".lock", "w", encoding="utf-8")
fcntl.flock(lock, fcntl.LOCK_EX)
try:
    if os.path.isfile(out):
        try:
            data = json.load(open(out, encoding="utf-8"))
        except ValueError as exc:
            print(f"REFUSED state: corrupt JSON in {out}: {exc}")
            raise SystemExit(1)
    else:
        head = subprocess.run(["git", "rev-parse", "-q", "--verify", "HEAD"], capture_output=True, text=True).stdout.strip()
        data = {"feature": feature, "tier": "standard", "lastApprovedPhase": "", "approvedPhases": [],
                "phaseDates": {}, "phaseTimes": {}, "activePhase": "", "activeStatus": "", "blockedReason": "",
                "verifyPassed": False, "reopenCount": 0, "helperBriefHashes": [], "artifact": artifact,
                "baseCommit": head, "updatedAt": "", "artifacts": {"primary": artifact},
                "evidence": {"build": [], "verify": []}}
    now = datetime.datetime.now().astimezone()
    phase = sets.pop("approvePhase", "")
    if phase:
        approved = [p for p in (data.get("approvedPhases") or []) if p != phase] + [phase]
        data["approvedPhases"] = approved
        data["lastApprovedPhase"] = phase
        data.setdefault("phaseDates", {})[phase] = now.date().isoformat()
        data.setdefault("phaseTimes", {})[phase] = now.isoformat(timespec="seconds")
    data.update(sets)
    data["updatedAt"] = now.isoformat(timespec="seconds")
    if artifact:
        data["artifact"] = artifact
        data.setdefault("artifacts", {})["primary"] = artifact
        if sets.get("activePhase") == "roadmap" or phase == "roadmap":
            data["artifacts"]["roadmap"] = artifact
        elif sets.get("activePhase") == "architecture" or phase == "architecture":
            data["artifacts"]["architecture"] = artifact
        elif sets.get("activePhase") == "plan" or phase == "plan":
            data["artifacts"]["plan"] = artifact
        elif sets.get("activePhase") == "scaffold" or phase == "scaffold":
            data["artifacts"]["scaffold"] = artifact
    fd, tmp = tempfile.mkstemp(prefix=".state.", suffix=".tmp", dir=os.path.dirname(out) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, out)
finally:
    fcntl.flock(lock, fcntl.LOCK_UN)
    lock.close()
PY
}

# --- approval record (Design: DA) --------------------------------------------------------------------------------
# gc_approvals_root: the approval folder root (see the header). Real home from the password database, so a changed
# $HOME does not move it.
gc_approvals_root() {
  gc_ar=""
  # >>> kit-test-override (Design: DA; install.sh removes this block; kit test copies only)
  gc_ar="${AGENTS_V0_APPROVALS_DIR:-}"
  # <<< kit-test-override
  [ -n "$gc_ar" ] || gc_ar="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')/.agents-v0-approvals"
  printf '%s\n' "$gc_ar"
}
# gc_repo_id: <main checkout folder name>-<sha256(absolute git common dir)[:12]>.
gc_repo_id() {
  gc_ri_cd="$(gc_common_dir)" || return 1
  python3 - "$(cd "$gc_ri_cd" && pwd -P)" <<'PY'
import hashlib, os, re, sys
cd = sys.argv[1]
name = os.path.basename(os.path.dirname(cd)) if os.path.basename(cd) == ".git" else os.path.basename(cd)
name = re.sub(r"[^A-Za-z0-9._-]", "_", name) or "repo"
print(f"{name}-{hashlib.sha256(cd.encode()).hexdigest()[:12]}")
PY
}
# gc_approval_file <command> [<feature>]: the record path for this repository and <command> (and <feature> when story-scoped).
gc_approval_file() {
  gc_af_root="$(gc_approvals_root)" && gc_af_id="$(gc_repo_id)" || return 1
  if [ -n "${2:-}" ]; then
    printf '%s/%s/%s-%s.json\n' "$gc_af_root" "$gc_af_id" "$1" "$2"
  else
    printf '%s/%s/%s.json\n' "$gc_af_root" "$gc_af_id" "$1"
  fi
}

gc_check_feature_slug() {
  gc_cfs_step="$1"
  gc_cfs_slug="$2"
  case "$gc_cfs_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gc_cfs_step" "feature slug '$gc_cfs_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gc_cfs_slug" in
    *[!a-z0-9-]*) gc_refuse "$gc_cfs_step" "feature slug '$gc_cfs_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
}

# approve <command> [<feature>]: Sensei's own step, in his own terminal (see the header). Never call it from an agent.
# Design: DLRA, DMA, DDLA, DSTA (local-release, maintain, deliver, and triage external approval normalization, maintain/worktree state resolution, and story-branch state preservation).
gc_approve() {
  [ $# -ge 1 ] && [ $# -le 2 ] || gc_usage
  gc_to_root approve
  gc_a_cmd="$1"
  gc_a_slug="${2:-}"
  [ "$gc_a_cmd" != "release" ] || gc_a_cmd="local-release"
  if [ -n "$gc_a_slug" ]; then
    gc_check_feature_slug approve "$gc_a_slug"
  fi
  if [ "$gc_a_cmd" = "triage" ]; then
    [ -n "$gc_a_slug" ] || gc_refuse approve "triage requires an <id> slug (usage: sh .agents-v0/scripts/guard-common.sh approve triage <id>)"
    gc_t_st="docs/agents-v0/maintain/${gc_a_slug}/state.json"
    gc_t_note="docs/agents-v0/maintain/${gc_a_slug}/note.md"
    if [ ! -f "$gc_t_st" ] || [ "$(gc_state_get "$gc_t_st" activeStatus 2>/dev/null || true)" != "awaiting_approval" ]; then
      gc_t_wt="$(git worktree list --porcelain 2>/dev/null | awk -v m="branch refs/heads/maintain/${gc_a_slug}" '
        /^worktree / { p = substr($0, 10) }
        $0 == m { print p; exit }
      ')"
      if [ -n "$gc_t_wt" ] && [ -d "$gc_t_wt" ] && [ -f "$gc_t_wt/docs/agents-v0/maintain/${gc_a_slug}/state.json" ]; then
        gc_t_st="$gc_t_wt/docs/agents-v0/maintain/${gc_a_slug}/state.json"
        gc_t_note="$gc_t_wt/docs/agents-v0/maintain/${gc_a_slug}/note.md"
      fi
    fi
    [ -f "$gc_t_st" ] || gc_refuse approve "no triage state yet for '$gc_a_slug' ($gc_t_st); nothing to approve"
    [ -f "$gc_t_note" ] || gc_refuse approve "missing maintenance note '$gc_t_note'; nothing to approve"
    gc_t_tier="$(sed -n 's/^[[:space:]]*[-*][[:space:]]*Tier:[[:space:]]*\([A-Za-z-]*\).*/\1/p; s/^Tier:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$gc_t_note" 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')"
    gc_t_st_tier="$(gc_state_get "$gc_t_st" tier 2>/dev/null || true)"
    [ "$gc_t_tier" = "trivial" ] && { [ -z "$gc_t_st_tier" ] || [ "$gc_t_st_tier" = "trivial" ]; } \
      || gc_refuse approve "triage approve only applies to Tier: trivial notes ('$gc_a_slug' has Tier: ${gc_t_tier:-${gc_t_st_tier:-missing}}); run: sh .agents-v0/scripts/guard-common.sh approve maintain $gc_a_slug"
    gc_a_cmd="maintain"
  fi
  if [ "$gc_a_cmd" = "deliver" ]; then
    [ -n "$gc_a_slug" ] || gc_refuse approve "deliver requires a <feature> slug (usage: sh .agents-v0/scripts/guard-common.sh approve deliver <feature>)"
    gc_d_st="docs/agents-v0/requirements/${gc_a_slug}.state.json"
    [ -f "$gc_d_st" ] || [ ! -f "docs/agents-v0/maintain/${gc_a_slug}/state.json" ] || gc_d_st="docs/agents-v0/maintain/${gc_a_slug}/state.json"
    if [ ! -f "$gc_d_st" ] || [ "$(gc_state_get "$gc_d_st" activeStatus 2>/dev/null || true)" != "awaiting_approval" ]; then
      gc_d_wt="$(git worktree list --porcelain 2>/dev/null | awk -v f="branch refs/heads/feature/${gc_a_slug}" -v m="branch refs/heads/maintain/${gc_a_slug}" '
        /^worktree / { p = substr($0, 10) }
        $0 == f || $0 == m { print p; exit }
      ')"
      if [ -n "$gc_d_wt" ] && [ -d "$gc_d_wt" ]; then
        if [ -f "$gc_d_wt/docs/agents-v0/requirements/${gc_a_slug}.state.json" ]; then
          gc_d_st="$gc_d_wt/docs/agents-v0/requirements/${gc_a_slug}.state.json"
        elif [ -f "$gc_d_wt/docs/agents-v0/maintain/${gc_a_slug}/state.json" ]; then
          gc_d_st="$gc_d_wt/docs/agents-v0/maintain/${gc_a_slug}/state.json"
        fi
      fi
    fi
    [ -f "$gc_d_st" ] || gc_refuse approve "no deliver state yet for '$gc_a_slug' ($gc_d_st); nothing to approve"
    gc_d_act="$(gc_state_get "$gc_d_st" activePhase 2>/dev/null || true)"
    gc_d_stat="$(gc_state_get "$gc_d_st" activeStatus 2>/dev/null || true)"
    [ "$gc_d_stat" = "awaiting_approval" ] && [ -n "$gc_d_act" ] \
      || gc_refuse approve "deliver ($gc_a_slug) is not awaiting approval (activePhase: ${gc_d_act:-none}, state: ${gc_d_stat:-none}); nothing to approve"
    gc_a_cmd="$gc_d_act"
    [ "$gc_a_cmd" != "release" ] || gc_a_cmd="local-release"
  fi
  gc_a_state="$(gc_rule "$gc_a_cmd" state "$gc_a_slug")" || gc_refuse approve "gate-rules has no '$gc_a_cmd state' rule; nothing to approve"
  case "$gc_a_state" in
    *"<feature>"*) gc_refuse approve "$gc_a_cmd requires a <feature> slug (usage: sh .agents-v0/scripts/guard-common.sh approve $gc_a_cmd <feature>)" ;;
  esac
  gc_a_phase="$(gc_rule "$gc_a_cmd" phase "$gc_a_slug")" || gc_refuse approve "gate-rules has no '$gc_a_cmd phase' rule"
  gc_a_feature="$(gc_rule "$gc_a_cmd" feature "$gc_a_slug")" || gc_refuse approve "gate-rules has no '$gc_a_cmd feature' rule"
  gc_a_artifact="$(gc_rule "$gc_a_cmd" artifact "$gc_a_slug")" || gc_refuse approve "gate-rules has no '$gc_a_cmd artifact' rule"
  # If the state file already records an exact artifact for a directory rule (e.g. dynamic roadmap/<program>.md), preserve it (T2)
  if [ "$gc_a_artifact" = "docs/agents-v0/roadmap" ] && [ -f "$gc_a_state" ]; then
    gc_existing_art="$(gc_state_get "$gc_a_state" artifact 2>/dev/null || true)"
    [ -n "$gc_existing_art" ] && [ "$gc_existing_art" != "docs/agents-v0/roadmap" ] && gc_a_artifact="$gc_existing_art"
  fi
  gc_a_wt_dir=""
  if [ -n "$gc_a_slug" ]; then
    if [ ! -f "$gc_a_state" ] && [ -f "docs/agents-v0/maintain/${gc_a_slug}/state.json" ]; then
      gc_a_state="docs/agents-v0/maintain/${gc_a_slug}/state.json"
      gc_a_artifact="docs/agents-v0/maintain/${gc_a_slug}/note.md"
    fi
    if [ ! -f "$gc_a_state" ] || [ "$(gc_state_get "$gc_a_state" activeStatus 2>/dev/null || true)" != "awaiting_approval" ]; then
      gc_a_wt_cand="$(git worktree list --porcelain 2>/dev/null | awk -v f="branch refs/heads/feature/${gc_a_slug}" -v m="branch refs/heads/maintain/${gc_a_slug}" '
        /^worktree / { p = substr($0, 10) }
        $0 == f || $0 == m { print p; exit }
      ')"
      if [ -n "$gc_a_wt_cand" ] && [ -d "$gc_a_wt_cand" ]; then
        if [ -f "$gc_a_wt_cand/docs/agents-v0/requirements/${gc_a_slug}.state.json" ]; then
          gc_a_state="$gc_a_wt_cand/docs/agents-v0/requirements/${gc_a_slug}.state.json"
          gc_a_wt_dir="$gc_a_wt_cand"
        elif [ -f "$gc_a_wt_cand/docs/agents-v0/maintain/${gc_a_slug}/state.json" ]; then
          gc_a_state="$gc_a_wt_cand/docs/agents-v0/maintain/${gc_a_slug}/state.json"
          gc_a_artifact="docs/agents-v0/maintain/${gc_a_slug}/note.md"
          gc_a_wt_dir="$gc_a_wt_cand"
        fi
      fi
    fi
  fi
  [ -f "$gc_a_state" ] || gc_refuse approve "no $gc_a_cmd state yet ($gc_a_state); nothing to approve"
  gc_a_active_phase="$(gc_state_get "$gc_a_state" activePhase)"
  [ -z "$gc_a_active_phase" ] || [ "$gc_a_active_phase" = "$gc_a_phase" ] \
    || gc_refuse approve "$gc_a_cmd is not the active phase (activePhase: $gc_a_active_phase); nothing to approve"
  gc_a_status="$(gc_state_get "$gc_a_state" activeStatus)"
  [ "$gc_a_status" = awaiting_approval ] \
    || gc_refuse approve "$gc_a_cmd is not awaiting approval (state: ${gc_a_status:-none}); nothing to approve"
  gc_a_base="$(gc_state_get "$gc_a_state" baseCommit)"
  [ -n "$gc_a_base" ] || gc_refuse approve "the $gc_a_cmd state has no baseCommit"
  if [ -n "$gc_a_wt_dir" ]; then
    gc_a_head="$(git -C "$gc_a_wt_dir" rev-parse -q --verify HEAD)" || gc_refuse approve "this repository has no commit yet"
  else
    gc_a_head="$(git rev-parse -q --verify HEAD)" || gc_refuse approve "this repository has no commit yet"
  fi
  gc_a_id="$(gc_repo_id)" || gc_refuse approve "cannot compute the repo id"
  gc_a_file="$(gc_approval_file "$gc_a_cmd" "$gc_a_slug")" || gc_refuse approve "cannot find the approval folder"
  if ! ( : </dev/tty ) 2>/dev/null; then
    gc_refuse approve "approve reads your words from your own terminal; run it there, outside Cursor (no terminal found)"
  fi
  gc_a_label="$gc_a_cmd"
  [ -z "$gc_a_slug" ] || gc_a_label="$gc_a_cmd ($gc_a_slug)"
  {
    printf 'Approve %s in %s\n' "$gc_a_label" "$(pwd)"
    printf '  HEAD:       %s\n  baseCommit: %s\n  record:     %s\n' "$gc_a_head" "$gc_a_base" "$gc_a_file"
    printf 'Type your approval words, then Enter (an empty line approves nothing): '
  } >/dev/tty
  gc_a_words=""
  IFS= read -r gc_a_words </dev/tty || :
  [ -n "$(printf '%s' "$gc_a_words" | tr -d '[:space:]')" ] || gc_refuse approve "no approval words typed; nothing approved"
  python3 - "$gc_a_file" "$gc_a_cmd" "$gc_a_phase" "$(pwd)" "$gc_a_id" "$(gc_common_dir)" "$gc_a_head" \
    "$gc_a_base" "$gc_a_words" "$gc_a_slug" <<'PY'
import datetime, fcntl, json, os, pwd, sys, tempfile
out, command, phase, repo, repo_id, common, head, base, words, slug = sys.argv[1:11]
os.umask(0o077)
os.makedirs(os.path.dirname(out), mode=0o700, exist_ok=True)
record = {"command": command, "phase": phase, "repo": repo, "repoId": repo_id, "gitCommonDir": common,
          "head": head, "baseCommit": base,
          "approvedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
          "approver": pwd.getpwuid(os.getuid()).pw_name, "words": words}
if slug:
    record["feature"] = slug
lock = open(out + ".lock", "w", encoding="utf-8")
fcntl.flock(lock, fcntl.LOCK_EX)
try:
    fd, tmp = tempfile.mkstemp(prefix=".record.", suffix=".tmp", dir=os.path.dirname(out))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, out)
finally:
    fcntl.flock(lock, fcntl.LOCK_UN)
    lock.close()
PY
  # For local-release, keep story-branch state at activePhase=release, activeStatus=awaiting_approval, and preserve
  # baseCommit so Step A (story branch commit) and Step B (integration branch merge + --approve release) succeed
  # without marking release approved on the story branch (kitfix-20261029-step4-p1e / kitfix-20261031-gate-commit).
  if [ "$gc_a_cmd" != "local-release" ]; then
    gc_state_set "$gc_a_state" "$gc_a_feature" "$gc_a_artifact" "approvePhase=$gc_a_phase" \
      "activePhase=" "activeStatus=" "blockedReason=" "nextStep=" || exit 1
  fi
  gc_ok approve "$gc_a_label approved at baseCommit $gc_a_base"
  printf 'Record: %s\n' "$gc_a_file"
}

# gc_approval_ok <command> [<feature>]: library check for D4/DIA/DLRA/DMA/DDLA/DSTA. Prints `OK approval: ...` and returns 0 only when this
# repository's record for <command> (and <feature> when given) exists, names this command and repository, and its
# baseCommit equals the state's baseCommit; else prints `REFUSED approval: <reason>` and returns 1.
gc_approval_ok() {
  [ $# -ge 1 ] && [ $# -le 2 ] || { printf 'REFUSED approval: usage gc_approval_ok <command> [<feature>]\n'; return 1; }
  gc_ok_cmd="$1"
  gc_ok_slug="${2:-}"
  [ "$gc_ok_cmd" != "release" ] || gc_ok_cmd="local-release"
  if [ -n "$gc_ok_slug" ]; then
    case "$gc_ok_slug" in
      [a-z0-9]* )
        case "$gc_ok_slug" in *[!a-z0-9-]*) printf "REFUSED approval: invalid feature slug '%s'\n" "$gc_ok_slug"; return 1 ;; esac ;;
      *) printf "REFUSED approval: invalid feature slug '%s'\n" "$gc_ok_slug"; return 1 ;;
    esac
  fi
  gc_ok_root="$(gc_root)" || { printf 'REFUSED approval: not inside a git work tree\n'; return 1; }
  if [ "$gc_ok_cmd" = "triage" ]; then
    [ -n "$gc_ok_slug" ] || { printf 'REFUSED approval: triage requires an <id> slug\n'; return 1; }
    gc_ok_t_st="$gc_ok_root/docs/agents-v0/maintain/${gc_ok_slug}/state.json"
    gc_ok_t_note="$gc_ok_root/docs/agents-v0/maintain/${gc_ok_slug}/note.md"
    if [ ! -f "$gc_ok_t_st" ]; then
      gc_ok_t_wt="$(git -C "$gc_ok_root" worktree list --porcelain 2>/dev/null | awk -v m="branch refs/heads/maintain/${gc_ok_slug}" '
        /^worktree / { p = substr($0, 10) }
        $0 == m { print p; exit }
      ')"
      if [ -n "$gc_ok_t_wt" ] && [ -d "$gc_ok_t_wt" ] && [ -f "$gc_ok_t_wt/docs/agents-v0/maintain/${gc_ok_slug}/state.json" ]; then
        gc_ok_t_st="$gc_ok_t_wt/docs/agents-v0/maintain/${gc_ok_slug}/state.json"
        gc_ok_t_note="$gc_ok_t_wt/docs/agents-v0/maintain/${gc_ok_slug}/note.md"
      fi
    fi
    [ -f "$gc_ok_t_st" ] || { printf "REFUSED approval: no triage state for '%s'\n" "$gc_ok_slug"; return 1; }
    [ -f "$gc_ok_t_note" ] || { printf "REFUSED approval: missing maintenance note '%s'\n" "$gc_ok_t_note"; return 1; }
    gc_ok_t_tier="$(sed -n 's/^[[:space:]]*[-*][[:space:]]*Tier:[[:space:]]*\([A-Za-z-]*\).*/\1/p; s/^Tier:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$gc_ok_t_note" 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')"
    gc_ok_t_st_tier="$(gc_state_get "$gc_ok_t_st" tier 2>/dev/null || true)"
    if [ "$gc_ok_t_tier" != "trivial" ] || { [ -n "$gc_ok_t_st_tier" ] && [ "$gc_ok_t_st_tier" != "trivial" ]; }; then
      printf "REFUSED approval: triage approval only applies to Tier: trivial notes ('%s' has Tier: %s)\n" "$gc_ok_slug" "${gc_ok_t_tier:-${gc_ok_t_st_tier:-missing}}"
      return 1
    fi
    gc_ok_cmd="maintain"
  fi
  if [ "$gc_ok_cmd" = "deliver" ]; then
    [ -n "$gc_ok_slug" ] || { printf 'REFUSED approval: deliver requires a <feature> slug\n'; return 1; }
    gc_ok_d_st="$gc_ok_root/docs/agents-v0/requirements/${gc_ok_slug}.state.json"
    [ -f "$gc_ok_d_st" ] || [ ! -f "$gc_ok_root/docs/agents-v0/maintain/${gc_ok_slug}/state.json" ] || gc_ok_d_st="$gc_ok_root/docs/agents-v0/maintain/${gc_ok_slug}/state.json"
    if [ ! -f "$gc_ok_d_st" ]; then
      gc_ok_d_wt="$(git -C "$gc_ok_root" worktree list --porcelain 2>/dev/null | awk -v f="branch refs/heads/feature/${gc_ok_slug}" -v m="branch refs/heads/maintain/${gc_ok_slug}" '
        /^worktree / { p = substr($0, 10) }
        $0 == f || $0 == m { print p; exit }
      ')"
      if [ -n "$gc_ok_d_wt" ] && [ -d "$gc_ok_d_wt" ]; then
        if [ -f "$gc_ok_d_wt/docs/agents-v0/requirements/${gc_ok_slug}.state.json" ]; then
          gc_ok_d_st="$gc_ok_d_wt/docs/agents-v0/requirements/${gc_ok_slug}.state.json"
        elif [ -f "$gc_ok_d_wt/docs/agents-v0/maintain/${gc_ok_slug}/state.json" ]; then
          gc_ok_d_st="$gc_ok_d_wt/docs/agents-v0/maintain/${gc_ok_slug}/state.json"
        fi
      fi
    fi
    [ -f "$gc_ok_d_st" ] || { printf "REFUSED approval: no deliver state for '%s'\n" "$gc_ok_slug"; return 1; }
    gc_ok_d_act="$(gc_state_get "$gc_ok_d_st" activePhase 2>/dev/null || true)"
    gc_ok_d_last="$(gc_state_get "$gc_ok_d_st" lastApprovedPhase 2>/dev/null || true)"
    gc_ok_cmd="${gc_ok_d_act:-$gc_ok_d_last}"
    [ -n "$gc_ok_cmd" ] || { printf "REFUSED approval: no active or approved phase in '%s'\n" "$gc_ok_d_st"; return 1; }
    [ "$gc_ok_cmd" != "release" ] || gc_ok_cmd="local-release"
  fi
  gc_ok_state="$(gc_rule "$gc_ok_cmd" state "$gc_ok_slug")" || { printf "REFUSED approval: gate-rules has no '%s state' rule\n" "$gc_ok_cmd"; return 1; }
  case "$gc_ok_state" in
    *"<feature>"*) printf "REFUSED approval: %s requires a <feature> slug\n" "$gc_ok_cmd"; return 1 ;;
  esac
  gc_ok_state_full="$gc_ok_root/$gc_ok_state"
  if [ -n "$gc_ok_slug" ]; then
    if [ ! -f "$gc_ok_state_full" ] && [ -f "$gc_ok_root/docs/agents-v0/maintain/${gc_ok_slug}/state.json" ]; then
      gc_ok_state_full="$gc_ok_root/docs/agents-v0/maintain/${gc_ok_slug}/state.json"
    fi
    if [ ! -f "$gc_ok_state_full" ]; then
      gc_ok_wt="$(git -C "$gc_ok_root" worktree list --porcelain 2>/dev/null | awk -v f="branch refs/heads/feature/${gc_ok_slug}" -v m="branch refs/heads/maintain/${gc_ok_slug}" '
        /^worktree / { p = substr($0, 10) }
        $0 == f || $0 == m { print p; exit }
      ')"
      if [ -n "$gc_ok_wt" ] && [ -d "$gc_ok_wt" ]; then
        if [ -f "$gc_ok_wt/docs/agents-v0/requirements/${gc_ok_slug}.state.json" ]; then
          gc_ok_state_full="$gc_ok_wt/docs/agents-v0/requirements/${gc_ok_slug}.state.json"
        elif [ -f "$gc_ok_wt/docs/agents-v0/maintain/${gc_ok_slug}/state.json" ]; then
          gc_ok_state_full="$gc_ok_wt/docs/agents-v0/maintain/${gc_ok_slug}/state.json"
        fi
      fi
    fi
  fi
  gc_ok_id="$(cd "$gc_ok_root" && gc_repo_id)" || { printf 'REFUSED approval: cannot compute the repo id\n'; return 1; }
  gc_ok_file="$(cd "$gc_ok_root" && gc_approval_file "$gc_ok_cmd" "$gc_ok_slug")" || { printf 'REFUSED approval: cannot find the approval folder\n'; return 1; }
  python3 - "$gc_ok_file" "$gc_ok_cmd" "$gc_ok_id" "$gc_ok_state_full" "$gc_ok_slug" <<'PY'
import json, sys
rec_path, command, repo_id, state_path, slug = sys.argv[1:6]
label = f"{command} ({slug})" if slug else command
def refuse(why):
    print(f"REFUSED approval: {why}")
    raise SystemExit(1)
try:
    base = (json.load(open(state_path, encoding="utf-8")).get("baseCommit") or "").strip()
except (OSError, ValueError) as exc:
    refuse(f"cannot read the {label} state ({exc})")
if not base:
    refuse(f"the {label} state has no baseCommit")
try:
    rec = json.load(open(rec_path, encoding="utf-8"))
except FileNotFoundError:
    refuse(f"no approval record for {label} ({rec_path}); Sensei runs approve in his own terminal")
except (OSError, ValueError) as exc:
    refuse(f"cannot read the approval record {rec_path} ({exc})")
if not isinstance(rec, dict) or rec.get("command") != command or rec.get("repoId") != repo_id:
    refuse(f"the approval record {rec_path} is for another command or repository")
if slug and rec.get("feature") not in (None, "", slug):
    refuse(f"the approval record {rec_path} is for feature '{rec.get('feature')}', not '{slug}'")
if rec.get("baseCommit") != base:
    refuse(f"the approval record approves baseCommit {rec.get('baseCommit')}, but the state's baseCommit is {base}; "
           "Sensei approves again")
print(f"OK approval: {label} approved by {rec.get('approver')} at {rec.get('approvedAt')} (baseCommit {base})")
PY
}

# --- branch check ---------------------------------------------------------------------------------------------------
# gc_branch: the current branch name (exit 1 on a detached HEAD).
gc_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null; }
# gc_branch_check [<branch>]: refuse a detached HEAD, or a branch other than <branch> when one is given.
gc_branch_check() {
  gc_to_root branch-check
  gc_b="$(gc_branch)" || gc_refuse branch-check "HEAD is detached; check out a branch first"
  if [ -n "${1:-}" ] && [ "$gc_b" != "$1" ]; then
    gc_refuse branch-check "on branch $gc_b, expected $1"
  fi
  gc_ok branch-check "on branch $gc_b"
}

# --- secret scan --------------------------------------------------------------------------------------------------
# gc_scanner <step>: refuse <step> unless python3 and secret_scan.py are there; set gc_py to the scanner path.
gc_scanner() {
  command -v python3 >/dev/null 2>&1 || gc_refuse "$1" "python3 is missing, so the secret scan cannot run"
  [ -f "$GC_HERE/secret_scan.py" ] || gc_refuse "$1" "$GC_HERE/secret_scan.py is missing; reinstall the kit (install.sh --update)"
  gc_py="$GC_HERE/secret_scan.py"
}

# Carried from ec12d6d2/c31fca77 (workflow-fixes-onboard), Design: D1. Adapted: the onboard path list, the scan record
#   and commit_msg_ok are left to the commit step (D4); this is the scan itself, with the same fail-closed exits.
# gc_scan_staged [--message-file FILE]: refuse when nothing is staged, or when secret_scan.py --staged exits non-zero
# (1 a hit, 2 it could not scan).
gc_scan_staged() {
  gc_msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --message-file) [ $# -ge 2 ] || gc_die "--message-file needs a file"; gc_msg="$2"; shift 2 ;;
      *) gc_die "scan-staged: unknown option: $1" ;;
    esac
  done
  if [ -n "$gc_msg" ]; then
    case "$gc_msg" in /*) ;; *) gc_msg="$(pwd)/$gc_msg" ;; esac
  fi
  gc_to_root scan-staged
  gc_scanner scan-staged
  if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    gc_rc=0
    git diff --cached --quiet --no-ext-diff 2>/dev/null || gc_rc=$?
    case "$gc_rc" in
      0) gc_refuse scan-staged "nothing is staged" ;;
      1) ;;
      *) gc_refuse scan-staged "git could not read the index" ;;
    esac
  else
    [ -n "$(git ls-files)" ] || gc_refuse scan-staged "nothing is staged"
  fi
  gc_rc=0
  if [ -n "$gc_msg" ]; then
    python3 "$gc_py" --staged --root "$(pwd)" --message-file "$gc_msg" || gc_rc=$?
  else
    python3 "$gc_py" --staged --root "$(pwd)" || gc_rc=$?
  fi
  [ "$gc_rc" = 0 ] || gc_refuse scan-staged "secret_scan.py exited $gc_rc (1: a hit, 2: it could not scan); do not commit"
  gc_ok scan-staged "the staged content holds no secret"
}

# Design: D1 (new). gc_scan_push [<remote>]: read the pre-push lines (<local ref> <local sha> <remote ref> <remote sha>)
# on stdin and scan every commit the push sends: <remote sha>..<local sha> when the remote tip is known here, else
# every commit not on a remote-tracking branch of <remote> (of any remote when no name is given). Deletions send
# nothing. Fails closed when a range cannot be listed.
gc_scan_push() {
  gc_remote="${1:-}"
  gc_to_root scan-push
  gc_scanner scan-push
  gc_list=""
  gc_n=0
  while read -r gc_lref gc_lsha gc_rref gc_rsha; do
    [ -n "${gc_lref:-}" ] || continue
    [ "${gc_lsha:-}" != "$GC_ZERO" ] || continue
    gc_tip="$(git rev-parse -q --verify "${gc_lsha}^{commit}" 2>/dev/null)" || continue  # a tag on a tree or blob
    gc_n=$((gc_n + 1))
    if [ -n "${gc_rsha:-}" ] && [ "$gc_rsha" != "$GC_ZERO" ] && git cat-file -e "${gc_rsha}^{commit}" 2>/dev/null; then
      gc_revs="$(git rev-list --reverse "$gc_rsha..$gc_tip")" || gc_refuse scan-push "cannot list the commits of $gc_lref"
    elif [ -n "$gc_remote" ]; then
      gc_revs="$(git rev-list --reverse "$gc_tip" --not --remotes="$gc_remote")" || gc_refuse scan-push "cannot list the commits of $gc_lref"
    else
      gc_revs="$(git rev-list --reverse "$gc_tip" --not --remotes)" || gc_refuse scan-push "cannot list the commits of $gc_lref"
    fi
    gc_list="$gc_list$gc_revs
"
  done
  gc_list="$(printf '%s' "$gc_list" | awk 'NF && !seen[$0]++')"
  if [ -z "$gc_list" ]; then
    gc_ok scan-push "no new commits to scan (refs: $gc_n)"
    return 0
  fi
  gc_rc=0
  printf '%s\n' "$gc_list" | python3 "$gc_py" --commits - --root "$(pwd)" || gc_rc=$?
  [ "$gc_rc" = 0 ] || gc_refuse scan-push "secret_scan.py exited $gc_rc (1: a hit, 2: it could not scan); the push is refused"
  gc_ok scan-push "the commits being pushed hold no secret"
}

# --- commit and tag (Design: D4) -----------------------------------------------------------------------------------
# gc_commit_tag <command>: the gate commit. Stages the gate-rules `<command> commit.paths` that exist or are tracked
# (git add --all, *.lock excluded), refuses when the index also holds a path outside them (nothing is unstaged), runs
# the staged secret scan (gc_scan_staged), commits once with `<command> commit.message` (hooks run; never --amend),
# and tags the next free `<command> commit.tag`<n> (annotated). Prints `OK commit: ...`, then a NOTE naming anything
# still uncommitted. The caller checks the approval first.
gc_commit_tag() {
  [ $# -eq 1 ] || gc_die "gc_commit_tag: needs <command>"
  gc_to_root commit
  gc_ct_branch="$(gc_branch)" || gc_refuse commit "HEAD is detached; check out the integration branch first"
  gc_ct_paths="$(gc_rule "$1" commit.paths)" || gc_refuse commit "gate-rules has no '$1 commit.paths' rule; reinstall the kit (install.sh --update)"
  gc_ct_msg="$(gc_rule "$1" commit.message)" || gc_refuse commit "gate-rules has no '$1 commit.message' rule"
  gc_ct_tag="$(gc_rule "$1" commit.tag)" || gc_refuse commit "gate-rules has no '$1 commit.tag' rule"
  gc_ct_list=""
  for gc_ct_p in $gc_ct_paths; do
    if [ -e "$gc_ct_p" ] || [ -n "$(git ls-files -- "$gc_ct_p" 2>/dev/null)" ]; then gc_ct_list="$gc_ct_list $gc_ct_p"; fi
  done
  [ -n "$gc_ct_list" ] || gc_refuse commit "none of the $1 commit paths exists ($gc_ct_paths)"
  gc_ct_out="$(gc_outside_paths "$gc_ct_paths")" || gc_refuse commit "the index already holds paths outside the $1 commit paths: $gc_ct_out; unstage them (git restore --staged <path>), then run commit again"
  # shellcheck disable=SC2086
  git add --all -- $gc_ct_list || gc_refuse commit "git add of the $1 commit paths failed"
  git reset -q -- '*.lock' '**/*.lock' 2>/dev/null || true
  gc_scan_staged
  gc_ct_n="$(git tag -l "${gc_ct_tag}*" | sed -n "s/^${gc_ct_tag}\([1-9][0-9]*\)\$/\1/p" | sort -n | tail -n 1)"
  gc_ct_n=$(( ${gc_ct_n:-0} + 1 ))
  git commit -q -m "$gc_ct_msg" || gc_refuse commit "git commit failed; the $1 files are still staged"
  git tag -a "${gc_ct_tag}${gc_ct_n}" -m "$1 approved" || gc_refuse commit "committed, but tagging ${gc_ct_tag}${gc_ct_n} failed; tag it by hand"
  gc_ok commit "$1 committed on $gc_ct_branch as $(git rev-parse --short HEAD), tagged ${gc_ct_tag}${gc_ct_n}"
  gc_ct_left="$(git status --porcelain --untracked-files=all | grep -v '\.lock$' || :)"
  [ -z "$gc_ct_left" ] || printf 'NOTE commit: still uncommitted (outside the %s commit paths):\n%s\n' "$1" "$gc_ct_left"
  return 0
}
# gc_outside_paths <allowed paths>: return 1 and print the staged paths that are not an allowed path or under one.
gc_outside_paths() {
  python3 -c '
import subprocess, sys
allowed = sys.argv[1].split()
out = subprocess.run(["git", "diff", "--cached", "--name-only", "-z", "--no-renames"], capture_output=True)
if out.returncode != 0:
    print("(git could not read the index)"); sys.exit(1)
bad = [p for p in out.stdout.decode("utf-8", "replace").split("\0") if p
       and not any(p == a or p.startswith(a.rstrip("/") + "/") for a in allowed)]
if bad:
    print(" ".join(bad)); sys.exit(1)
' "$1"
}

# --- export & deck source-approval and read-only tree helpers (Design: DEXA) ---------------------------------------
# gc_source_approval_date <state_path> <md_path> <phase_csv>: print approval date (YYYY-MM-DD or approved) and exit 0
# when any phase in <phase_csv> is in <state_path>.approvedPhases or has an Approved row in <md_path>; else exit 1.
gc_source_approval_date() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, re, sys
state_path, md_path, phase_csv = sys.argv[1:4]
phases = [p.strip() for p in phase_csv.split(",") if p.strip()]
if state_path and os.path.isfile(state_path):
    try:
        st = json.load(open(state_path, encoding="utf-8"))
        approved = st.get("approvedPhases") or []
        dates = st.get("phaseDates") or {}
        upd = (st.get("updatedAt") or "")[:10] or "approved"
        for p in phases:
            if p in approved:
                print(str(dates.get(p) or upd)[:10])
                sys.exit(0)
    except Exception:
        pass
if md_path and os.path.isfile(md_path):
    try:
        txt = open(md_path, encoding="utf-8").read()
        for line in txt.splitlines():
            if "|" not in line:
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and any(cells[0].lower() == p.lower() for p in phases):
                if any(c.lower().startswith("approved") for c in cells[1:]):
                    for c in cells[1:]:
                        m = re.search(r"\b(20\d\d-\d\d-\d\d)\b", c)
                        if m:
                            print(m.group(1))
                            sys.exit(0)
                    print("approved")
                    sys.exit(0)
    except Exception:
        pass
sys.exit(1)
PY
}

# gc_readonly_outside <allowed_prefix_dir>: exit 0 when git status --porcelain -uall has no modified/untracked files
# outside <allowed_prefix_dir> (ignoring *.lock); otherwise print the offending paths and exit 1.
gc_readonly_outside() {
  python3 - "$1" <<'PY'
import subprocess, sys
prefix = sys.argv[1].rstrip("/") + "/"
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
    if not raw.startswith(prefix):
        outside.append(raw)
if outside:
    print(", ".join(outside))
    sys.exit(1)
PY
}

gc_paths() {
  gc_to_root paths
  printf 'root=%s\n' "$(pwd)"
  printf 'git_common_dir=%s\n' "$(gc_common_dir)"
  printf 'onboarding_state=%s\n' "$(gc_state_file onboarding)"
  printf 'approvals=%s\n' "$(gc_approvals_root)/$(gc_repo_id)"
}

gc_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-common.sh scan-staged [--message-file FILE] | scan-push [<remote>] | branch-check [<branch>] | paths | approve <command>\n' >&2
  exit 2
}

gc_main() {
  [ $# -ge 1 ] || gc_usage
  gc_cmd="$1"; shift
  case "$gc_cmd" in
    scan-staged) gc_scan_staged "$@" ;;
    scan-push) [ $# -le 1 ] || gc_usage; gc_scan_push "$@" ;;
    branch-check) [ $# -le 1 ] || gc_usage; gc_branch_check "$@" ;;
    paths) [ $# -eq 0 ] || gc_usage; gc_paths ;;
    approve) gc_approve "$@" ;;
    -h|--help) sed -n '2,38p' "$GC_HERE/guard-common.sh"; exit 0 ;;
    *) gc_usage ;;
  esac
}

[ "${GUARD_COMMON_LIB:-}" = 1 ] || gc_main "$@"
