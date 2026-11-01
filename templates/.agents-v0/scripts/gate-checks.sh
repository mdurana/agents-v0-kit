#!/bin/sh
# gate-checks.sh — the shared gate helper of the onboard fix (step 0 skeleton).
#   sh .agents-v0/scripts/gate-checks.sh <check> [arg]      run one check
#   sh .agents-v0/scripts/gate-checks.sh rules [key]        print the validated gate-rules (or one value)
#   sh .agents-v0/scripts/gate-checks.sh paths              print the git common dir, ledger and grant paths
#   sh .agents-v0/scripts/gate-checks.sh list               print every check and whether it is wired
#
# Design: kit-eval/kitfix-plan-20261031/proposals/jiraiya-onboard-fix-design-20261101.md (revision 6),
# "Keeping the scripts small" and gap 5. Each check is one function with one job and one refusal message, and
# it prints its own name and the rule it enforces. The helper never judges doc quality and never writes
# project state; sync-feature-state.sh only calls it. The rule values live in gate-rules beside this file.
#
# Output (one line per check, on stdout):
#   OK <check>: <rule>                     exit 0, the check passed
#   REFUSED <check>: <reason>              exit 1, the check refused
#   NOT-WIRED <check>: <rule> ...          exit 3, the check exists but its logic is not built yet
#   error: ...  (stderr)                   exit 2, usage error or unreadable/invalid gate-rules
# A caller treats every exit code but 0 as a stop (fail closed). Step 0 wired the plumbing (dispatch,
# gate-rules loading and validation, the ledger and grant paths); a check stays NOT-WIRED until its fix turn
# (wired so far: see WIRED below and `list`).
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
RULES="$HERE/gate-rules"
# Keys gate-rules must carry, each exactly once. Anything else is an error.
RULE_KEYS="onboard_gate_docs prereq_approved_phases onboard_commit_paths docs_check_cap grant_max_age_seconds"
# Ledger and grant live in the git common dir, so every worktree of the repo shares them (design, "Retry count
# and reopen"). Nothing in the kit writes the grant; only the person does, in their own terminal.
LEDGER_REL="agents-v0/gate-ledger"
GRANT_REL="agents-v0/reopen-grant"
# Every gate commit carries this trailer (N3A): Agents-V0-Ledger: lines=<n> sha256=<hash of the first n lines>.
LEDGER_TRAILER="Agents-V0-Ledger"

# Checks whose logic is built (a wired check may still carry TODOs for later fixes; see its comment).
WIRED="approval_evidence gate_committed"
CHECKS="approval_evidence gate_committed prereq_approved no_restart_without_reopen staged_secret_scan reopen_grant_ok greenfield_record_ok baseline_ok ledger_ok"

usage() {
  printf 'usage: sh .agents-v0/scripts/gate-checks.sh <check> [arg] | rules [key] | paths | list\n' >&2
  printf 'checks: %s\n' "$CHECKS" >&2
  exit 2
}

die() { printf 'error: %s\n' "$1" >&2; exit 2; }

# --- gate-rules ------------------------------------------------------------------------------------------
# load_rules prints the validated rules as key=value lines, or exits 2 naming the first problem.
load_rules() {
  [ -f "$RULES" ] || die "gate-rules not found at $RULES (reinstall the kit: install.sh --update)"
  [ -r "$RULES" ] || die "gate-rules is not readable: $RULES"
  out="$(awk -v keys="$RULE_KEYS" '
    BEGIN { n = split(keys, k, " "); for (i = 1; i <= n; i++) known[k[i]] = 1 }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      eq = index($0, "=")
      if (eq < 2) { printf "gate-rules line %d is not key=value: %s\n", NR, $0; bad = 1; exit }
      key = substr($0, 1, eq - 1); val = substr($0, eq + 1)
      if (key !~ /^[a-z_]+$/) { printf "gate-rules line %d has a bad key: %s\n", NR, key; bad = 1; exit }
      if (!(key in known)) { printf "gate-rules line %d has an unknown key: %s\n", NR, key; bad = 1; exit }
      if (key in seen) { printf "gate-rules line %d repeats key %s\n", NR, key; bad = 1; exit }
      if (val ~ /^[[:space:]]*$/) { printf "gate-rules line %d has an empty value for %s\n", NR, key; bad = 1; exit }
      if (val ~ /["'\''`$\\]/) { printf "gate-rules line %d: quotes, $, backquote and backslash are not allowed (%s)\n", NR, key; bad = 1; exit }
      if ((key == "docs_check_cap" || key == "grant_max_age_seconds") && val !~ /^[1-9][0-9]*$/) {
        printf "gate-rules line %d: %s must be a positive whole number, got %s\n", NR, key, val; bad = 1; exit
      }
      seen[key] = 1; out[++m] = key "=" val
    }
    END {
      if (bad) exit 1
      for (i = 1; i <= n; i++) if (!(k[i] in seen)) { printf "gate-rules is missing key %s\n", k[i]; exit 1 }
      for (i = 1; i <= m; i++) print out[i]
    }
  ' "$RULES")" || die "${out:-gate-rules could not be read}"
  printf '%s\n' "$out"
}

# rule <key> prints one validated value.
rule() {
  case " $RULE_KEYS " in *" $1 "*) ;; *) die "unknown gate-rules key: $1" ;; esac
  all="$(load_rules)" || exit 2
  printf '%s\n' "$all" | sed -n "s/^$1=//p"
}

# --- paths ----------------------------------------------------------------------------------------------
git_common_dir() {
  d="$(git rev-parse --git-common-dir 2>/dev/null)" || die "not inside a git repository"
  [ -n "$d" ] && [ -d "$d" ] || die "cannot resolve the git common dir"
  d="$(cd "$d" && pwd -P)" || die "cannot resolve the git common dir"
  printf '%s\n' "$d"
}
# Callers assign these to a variable first (v="$(ledger_path)") so a die in the subshell stops the script.
ledger_path() { gcd="$(git_common_dir)" || exit 2; printf '%s/%s\n' "$gcd" "$LEDGER_REL"; }
grant_path() { gcd="$(git_common_dir)" || exit 2; printf '%s/%s\n' "$gcd" "$GRANT_REL"; }

# --- checks ---------------------------------------------------------------------------------------------
ok() { printf 'OK %s: %s\n' "$1" "$2"; exit 0; }
refuse() { printf 'REFUSED %s: %s\n' "$1" "$2"; exit 1; }
# not_wired <check> <rule> <who wires it>: fail closed until the fix turn builds the logic.
not_wired() { printf 'NOT-WIRED %s: %s. Not yet wired (step 0 skeleton; built by %s). Stop: treat as refused.\n' "$1" "$2" "$3"; exit 3; }

need_phase() { [ -n "${2:-}" ] || die "$1 needs a phase argument"; case "$2" in *[!a-z-]*) die "$1: bad phase name: $2" ;; esac; }

# Onboarding paths, relative to the repo root (sync-feature-state.sh writes the state and reads the phase result
# at these paths; the agent writes the phase result).
ONB_DIR="docs/agents-v0/onboarding"
ONB_STATE="$ONB_DIR/state.json"
ONB_REPORT="$ONB_DIR/report.md"
ONB_RESULT="$ONB_DIR/phase-result.md"

# to_root: run from the repo root when inside a git work tree (sync and the docs check use root-relative paths).
to_root() {
  if top="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ]; then cd "$top" || die "cannot cd to $top"; fi
}

# state_field <file> <key>: one value of a state JSON file; a list prints space-separated. Exit 1 when the
# file is missing or not valid JSON (the caller refuses).
state_field() {
  python3 - "$1" "$2" <<'PYSF'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)
v = data.get(sys.argv[2])
print(" ".join(str(x) for x in v) if isinstance(v, list) else ("" if v is None else str(v)))
PYSF
}

# JO-2 (design rev 6 lines 25, 95, 167): --approve <phase> needs recorded evidence, never report text. For
# onboard: the state says onboard is awaiting_approval, phase-result.md exists, and the onboarding docs check
# passes. The helper runs the docs check itself (read-only) and judges no doc content.
# TODO(JO-3/JO-4): run `check-onboarding-docs.sh --gate` on the gate-rules onboard_gate_docs list once JO-3/JO-4
# build that mode; until then this proves only that today's default docs check passes, not that the gate
# docs are complete (design line 167). JO-2 stays open until then.
approval_evidence() {
  need_phase approval_evidence "${1:-}"
  [ "$1" = onboard ] || not_wired approval_evidence "phase $1 needs recorded approval evidence before its gate (only onboard is wired)" "the fix turn for $1"
  to_root
  [ -f "$ONB_STATE" ] || refuse approval_evidence "there is no onboarding state ($ONB_STATE); onboard has not run"
  ae_phase="$(state_field "$ONB_STATE" activePhase)" || refuse approval_evidence "$ONB_STATE is not valid JSON; stop and ask the user"
  ae_status="$(state_field "$ONB_STATE" activeStatus)" || refuse approval_evidence "$ONB_STATE is not valid JSON; stop and ask the user"
  [ "$ae_phase" = onboard ] || refuse approval_evidence "the active phase is ${ae_phase:-none}, not onboard awaiting_approval"
  [ "$ae_status" = awaiting_approval ] || refuse approval_evidence "onboard status is ${ae_status:-none}, not awaiting_approval"
  [ -s "$ONB_RESULT" ] || refuse approval_evidence "$ONB_RESULT is missing or empty"
  [ -f "$HERE/check-onboarding-docs.sh" ] || refuse approval_evidence "$HERE/check-onboarding-docs.sh is missing; reinstall the kit (install.sh --update)"
  sh "$HERE/check-onboarding-docs.sh" >/dev/null 2>&1 || refuse approval_evidence "the onboarding docs check failed (check-onboarding-docs.sh); run it, fix the docs, and ask again"
  ok approval_evidence "onboard is awaiting_approval, $ONB_RESULT exists and the onboarding docs check passed"
}
# JO-1 (design rev 6 lines 69, 84, 96, 168): the approved <phase> has its gate commit. For onboard: onboard is in
# approvedPhases, check-gate-commit.sh (unchanged) passes on the onboarding report (the approval is in HEAD and
# the tree is clean), and the newest onboard-v<n> tag is on this branch and holds the current approval.
# Consumers: prereq_approved (JO-9) and the JO-8 commit chain; nothing in sync calls this check yet.
# TODO(JO-8): the commit's paths are a subset of gate-rules onboard_commit_paths plus the recorded pack paths, and
#   the range re-scan (design line 27) belong to the JO-8 commit chain and its secret scanner; not checked here.
# Not here (N3A, blocked on Sasuke's hook work): the Agents-V0-Ledger trailer on the gate commit is ledger_ok's job.
gate_committed() {
  need_phase gate_committed "${1:-}"
  [ "$1" = onboard ] || not_wired gate_committed "phase $1 must have its gate commit (only onboard is wired)" "the fix turn for $1"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse gate_committed "not a git work tree, so the onboard gate cannot be committed"
  to_root
  [ -f "$ONB_STATE" ] || refuse gate_committed "onboard is not approved in $ONB_STATE, so it has no gate commit"
  gc_approved="$(state_field "$ONB_STATE" approvedPhases)" || refuse gate_committed "$ONB_STATE is not valid JSON; stop and ask the user"
  case " $gc_approved " in *" onboard "*) ;; *) refuse gate_committed "onboard is not approved in $ONB_STATE, so it has no gate commit" ;; esac
  [ -f "$ONB_REPORT" ] || refuse gate_committed "$ONB_REPORT is missing, so the onboard gate cannot be checked"
  [ -f "$HERE/check-gate-commit.sh" ] || refuse gate_committed "$HERE/check-gate-commit.sh is missing; reinstall the kit (install.sh --update)"
  if ! gc_out="$(sh "$HERE/check-gate-commit.sh" "$ONB_REPORT" 2>&1)"; then
    printf '%s\n' "$gc_out" | sed 's/^/  /' >&2
    refuse gate_committed "the onboard gate is not committed (check-gate-commit.sh); commit it, then tag it onboard-v<n>"
  fi
  case "$gc_out" in *"skipped (kit test override)"*)
    refuse gate_committed "check-gate-commit.sh skipped its check (AGENTS_V0_SKIP_COMMIT_CHECK); a skipped check is not a gate commit" ;;
  esac
  gc_n="$(git tag -l 'onboard-v*' | sed -n 's/^onboard-v\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)"
  [ -n "$gc_n" ] || refuse gate_committed "no onboard-v<n> tag on the onboard gate commit; tag it: git tag -a onboard-v1 -m \"onboard approved\""
  gc_tag="onboard-v$gc_n"
  git merge-base --is-ancestor "$gc_tag^{commit}" HEAD 2>/dev/null || refuse gate_committed "$gc_tag is not on this branch (not an ancestor of HEAD)"
  if ! python3 - "$gc_tag" "$ONB_STATE" <<'PYGT'
import json, subprocess, sys
tag, path = sys.argv[1], sys.argv[2]
def approval(rev):
    out = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True, check=False)
    try:
        d = json.loads(out.stdout) if out.returncode == 0 else None
    except ValueError:
        d = None
    if not isinstance(d, dict) or "onboard" not in (d.get("approvedPhases") or []):
        return None
    return ((d.get("lastApprovedPhase") or "").lower(), sorted(d.get("approvedPhases") or []),
            (d.get("phaseTimes") or {}).get("onboard"), (d.get("phaseDates") or {}).get("onboard"))
at_tag, at_head = approval(tag), approval("HEAD")
sys.exit(0 if at_tag is not None and at_tag == at_head else 1)
PYGT
  then
    refuse gate_committed "$gc_tag does not hold the current onboard approval; tag the new gate commit onboard-v$((gc_n + 1))"
  fi
  ok gate_committed "onboard is approved, committed (check-gate-commit.sh) and tagged $gc_tag (path subset and range re-scan: JO-8, not checked yet)"
}
# JO-9: <next-phase> in prereq_approved_phases needs onboard approved and committed (brownfield only).
prereq_approved() {
  need_phase prereq_approved "${1:-}"
  phases="$(rule prereq_approved_phases)"
  case " $phases " in
    *" $1 "*) not_wired prereq_approved "$1 needs onboard approved and committed first (gate-rules prereq_approved_phases)" "JO-9 with the gap 9 content rule" ;;
    *) not_wired prereq_approved "$1 is not in gate-rules prereq_approved_phases ($phases)" "JO-9" ;;
  esac
}
# JO-10: no state change on an onboard report awaiting review or approved, unless --reopen with a valid grant.
no_restart_without_reopen() {
  not_wired no_restart_without_reopen "no state change on a report awaiting review or approved without a granted --reopen" "JO-10 (Sensei 4A, 1A)"
}
# JO-8: the staged index holds no secret (secret_scan.py; exit 0 clean / 1 hits / 2 error).
staged_secret_scan() {
  not_wired staged_secret_scan "the staged index must hold no secret (secret_scan.py)" "JO-8 (N7A)"
}
# 4A, N5A, 1A (1A-gap B): the grant parses, names <phase>, is newer than the last gate of <phase>, is at most
# grant_max_age_seconds old, is unused (no GRANT-USED line, not in git history) and the run is attended.
reopen_grant_ok() {
  need_phase reopen_grant_ok "${1:-}"
  age="$(rule grant_max_age_seconds)"
  not_wired reopen_grant_ok "the grant for $1 must be newer than the last $1 gate and at most ${age}s old, unused and attended" "the reopen grant and ledger fix (4A, N5A, 1A; needs JO-10 and Sasuke's hook patterns)"
}
# 5A, N2A: .agents-v0/greenfield-record.json is valid only in the repo's single root commit.
greenfield_record_ok() {
  not_wired greenfield_record_ok "the greenfield record must sit in the repo's only root commit" "the greenfield record fix (5A, N2A, N9A)"
}
# 2A, N4B: the baseline record is green, or every failing test is in baseline-accepted.json read from HEAD.
# Built in the helper by onboard; build and maintain wire it in their own fix turns (N4B).
baseline_ok() {
  need_phase baseline_ok "${1:-}"
  not_wired baseline_ok "phase $1 needs a green baseline record or every failure accepted in HEAD's baseline-accepted.json" "the red baseline fix (2A, N4B; needs the JO-15a record)"
}
# N3A: the ledger still starts with the lines the last gate commit's $LEDGER_TRAILER trailer anchored.
ledger_ok() {
  not_wired ledger_ok "the gate ledger must match the $LEDGER_TRAILER trailer of the last gate commit" "the ledger integrity fix (N3A; needs the JO-8 commit chain)"
}

# --- dispatch -------------------------------------------------------------------------------------------
[ "$#" -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
  -h|--help) usage ;;
  rules)
    [ "$#" -le 1 ] || usage
    if [ "$#" = 1 ]; then rule "$1"; else load_rules; fi ;;
  paths)
    [ "$#" = 0 ] || usage
    gcd="$(git_common_dir)"; lp="$(ledger_path)"; gp="$(grant_path)"
    printf 'git_common_dir=%s\nledger=%s\ngrant=%s\n' "$gcd" "$lp" "$gp" ;;
  list)
    [ "$#" = 0 ] || usage
    for c in $CHECKS; do
      case " $WIRED " in *" $c "*) printf '%s wired\n' "$c" ;; *) printf '%s not-wired\n' "$c" ;; esac
    done ;;
  approval_evidence|gate_committed|prereq_approved|reopen_grant_ok|baseline_ok)
    [ "$#" = 1 ] || usage
    load_rules > /dev/null
    "$cmd" "$1" ;;
  no_restart_without_reopen|staged_secret_scan|greenfield_record_ok|ledger_ok)
    [ "$#" = 0 ] || usage
    load_rules > /dev/null
    "$cmd" ;;
  *) printf 'error: unknown check: %s\n' "$cmd" >&2; usage ;;
esac
