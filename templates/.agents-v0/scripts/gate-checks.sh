#!/bin/sh
# gate-checks.sh — the shared gate helper of the onboard fix (step 0 skeleton).
#   sh .agents-v0/scripts/gate-checks.sh <check> [arg]      run one check
#   sh .agents-v0/scripts/gate-checks.sh rules [key]        print the validated gate-rules (or one value)
#   sh .agents-v0/scripts/gate-checks.sh paths              print the git common dir, ledger and grant paths
#   sh .agents-v0/scripts/gate-checks.sh list               print every check and whether it is wired
#   sh .agents-v0/scripts/gate-checks.sh commit_chain       print the onboard gate commit chain (JO-8); runs nothing
#   sh .agents-v0/scripts/gate-checks.sh ledger_mark        print the gate ledger's mark (N84: lines=<n> sha256=<h>, or absent)
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
WIRED="approval_evidence gate_committed prereq_approved no_restart_without_reopen staged_secret_scan commit_msg_ok ledger_ok ledger_turn_ok"
CHECKS="approval_evidence gate_committed prereq_approved no_restart_without_reopen staged_secret_scan commit_msg_ok reopen_grant_ok greenfield_record_ok baseline_ok ledger_ok ledger_turn_ok"

usage() {
  printf 'usage: sh .agents-v0/scripts/gate-checks.sh <check> [arg] | rules [key] | paths | list | commit_chain | ledger_mark\n' >&2
  printf '       sh .agents-v0/scripts/gate-checks.sh ledger_turn_ok <mark> <fails seen> <refusals seen>\n' >&2
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
      if (key == "onboard_gate_docs" && val ~ /[*?[]/) {
        printf "gate-rules line %d: glob characters (* ? [) are not allowed in onboard_gate_docs; list each path\n", NR; bad = 1; exit
      }
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

# --- N3A ledger integrity -------------------------------------------------------------------------------
# ledger_py <mode> [args]: read the gate ledger against the Agents-V0-Ledger trailers (design rev 6, "Ledger
# integrity (N3A)"). Exit 0 prints a summary (or, for trailer/mark, the value); exit 1 prints the refusal reason;
# exit 2 a usage error. Modes:
#   check                     every onboard-v<n> gate commit has one well-formed trailer, the ledger exists once
#                             any gate commit does, is at least as long as each recorded count, its first n lines
#                             hash to each recorded sha256, and every line after the newest anchor is well formed
#                             (each GRANT-USED names a line of the grant file, once, with the FAIL count before it;
#                             a second reopen appends its grant, so an older GRANT-USED line still finds its own)
#   trailer                   check, then print the trailer for the next gate commit (creates the empty ledger
#                             when no gate commit exists yet and nothing has written it)
#   commit <msg file>         check, and the message's own trailer still anchors the ledger (commit_msg_ok)
#   mark                      print "lines=<n> sha256=<hash>" or "absent" (the harness, before an unattended turn)
#   turn <mark> <fails> <refusals>
#                             since <mark>: nothing cut, edited or deleted; only FAIL and REOPEN-REFUSED lines
#                             appended, exactly as many as the harness saw (N84)
# Lines are newline-terminated; the line grammar (the kit writers must follow it):
#   FAIL[ <text>]   GRANT-USED <sha256 of the grant line, without its newline> count=<n>   REOPEN-REFUSED <text>
# The grant file holds one grant line per approved reopen, appended, the newest last (the grant in force).
# where <text> has no control characters. The newest anchor is the largest recorded count over all onboard-v<n>
# tags (the ledger is shared by every worktree, so is every tag).
ledger_py() {
  lp_l="$(ledger_path)" || exit 2
  lp_g="$(grant_path)" || exit 2
  python3 - "$lp_l" "$lp_g" "$LEDGER_TRAILER" "$@" <<'PYLG'
import hashlib, os, re, subprocess, sys
ledger, grant, key, mode, args = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
TRAILER_RE = re.compile(r"^" + re.escape(key) + r": lines=(0|[1-9][0-9]*) sha256=([0-9a-f]{64})$")
KEY_RE = re.compile(r"^\s*" + re.escape(key) + r"\s*:", re.I)
FAIL_RE = re.compile(r"^FAIL(?: [^\x00-\x1f\x7f]+)?$")
GRANT_RE = re.compile(r"^GRANT-USED ([0-9a-f]{64}) count=(0|[1-9][0-9]*)$")
REFUSED_RE = re.compile(r"^REOPEN-REFUSED [^\x00-\x1f\x7f]+$")
MARK_RE = re.compile(r"^lines=(0|[1-9][0-9]*) sha256=([0-9a-f]{64})$")
EMPTY = hashlib.sha256(b"").hexdigest()

def out(code, msg):
    print(msg)
    sys.exit(code)

def git(*a):
    return subprocess.run(["git"] + list(a), stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def prefix_sha(lines, n):
    return hashlib.sha256(b"".join(x + b"\n" for x in lines[:n])).hexdigest()

def text(x):
    try:
        return x.decode("utf-8")
    except UnicodeDecodeError:
        return None

def read_ledger():
    if not os.path.lexists(ledger):
        return None
    if os.path.islink(ledger) or not os.path.isfile(ledger):
        out(1, "the ledger %s is not a regular file" % ledger)
    with open(ledger, "rb") as f:
        data = f.read()
    if data and not data.endswith(b"\n"):
        out(1, "the last line of the ledger %s has no newline (every kit write ends in one)" % ledger)
    return data.split(b"\n")[:-1] if data else []

def trailer_of(body, where):
    hits = [x for x in body.split("\n") if KEY_RE.match(x)]
    if not hits:
        out(1, "%s has no %s trailer" % (where, key))
    if len(hits) > 1:
        out(1, "%s has more than one %s trailer" % (where, key))
    m = TRAILER_RE.match(hits[0])
    if not m:
        out(1, "%s has a malformed %s trailer" % (where, key))
    return int(m.group(1)), m.group(2)

def anchors():
    r = git("tag", "-l", "onboard-v*")
    if r.returncode != 0:
        out(1, "git could not list the onboard-v<n> tags")
    tags = [t for t in r.stdout.decode("utf-8", "replace").split("\n") if re.match(r"^onboard-v[0-9]+$", t)]
    found = []
    for t in sorted(tags, key=lambda x: int(x[len("onboard-v"):])):
        c = git("rev-parse", "-q", "--verify", t + "^{commit}")
        if c.returncode != 0:
            out(1, "the tag %s does not name a commit" % t)
        sha = c.stdout.decode().strip()
        b = git("cat-file", "commit", sha)
        if b.returncode != 0:
            out(1, "git could not read the gate commit %s" % t)
        body = b.stdout.decode("utf-8", "surrogateescape")
        msg = body.split("\n\n", 1)[1] if "\n\n" in body else ""
        n, h = trailer_of(msg, "the gate commit %s (%s)" % (t, sha[:12]))
        found.append((t, n, h))
    return found

def check_anchors(lines, anc):
    if lines is None:
        if anc:
            t, n, _ = max(anc, key=lambda a: a[1])
            out(1, "the ledger %s is missing, but the gate commit %s recorded lines=%d; a missing ledger never reads as zero failures" % (ledger, t, n))
        return None, 0
    for t, n, h in anc:
        if len(lines) < n:
            out(1, "the ledger has %d lines, fewer than the %d that the gate commit %s recorded" % (len(lines), n, t))
        if prefix_sha(lines, n) != h:
            out(1, "the first %d lines of the ledger no longer match the sha256 that the gate commit %s recorded (an earlier line was edited)" % (n, t))
    if not anc:
        return None, 0
    t, n, _ = max(anc, key=lambda a: a[1])
    return t, n

def grant_hashes():
    # every grant line in the grant file, each hashed without its newline. The person appends each new grant as
    # its own line (the newest last), so the grant that was in force for each GRANT-USED line is still there.
    if not os.path.isfile(grant):
        return None
    with open(grant, "rb") as f:
        return set(hashlib.sha256(x).hexdigest() for x in f.read().split(b"\n") if x)

def check_appended(lines, start):
    fails, used, gh = 0, {}, False
    for x in lines:
        s = text(x)
        m = GRANT_RE.match(s) if s is not None else None
        if m:
            used[m.group(1)] = used.get(m.group(1), 0) + 1
    for i, x in enumerate(lines):
        s = text(x)
        if i >= start:
            bad = "ledger line %d is not a well-formed FAIL, GRANT-USED or REOPEN-REFUSED line" % (i + 1)
            if s is None:
                out(1, bad)
            m = GRANT_RE.match(s)
            if m:
                if gh is False:
                    gh = grant_hashes()
                if gh is None:
                    out(1, "ledger line %d is a GRANT-USED line, but there is no grant file (%s)" % (i + 1, grant))
                if m.group(1) not in gh:
                    out(1, "ledger line %d is a GRANT-USED line that names no grant in %s (each grant stays there as its own line; a grant that was overwritten instead of appended cannot be checked)" % (i + 1, grant))
                if used[m.group(1)] > 1:
                    out(1, "ledger line %d names a grant that another GRANT-USED line already used" % (i + 1))
                if int(m.group(2)) != fails:
                    out(1, "ledger line %d says count=%s, but the FAIL lines before it give %d" % (i + 1, m.group(2), fails))
            elif not FAIL_RE.match(s) and not REFUSED_RE.match(s):
                out(1, bad)
        if s is not None and FAIL_RE.match(s):
            fails += 1

def full_check():
    anc = anchors()
    lines = read_ledger()
    t, n = check_anchors(lines, anc)
    if lines is not None:
        check_appended(lines, n)
    return anc, lines, t, n

if mode == "check":
    anc, lines, t, n = full_check()
    if lines is None:
        out(0, "no gate commit yet and no ledger")
    if t is None:
        out(0, "no gate commit yet; the ledger's %d line(s) are well formed" % len(lines))
    out(0, "the ledger matches the %s trailer of %s (lines=%d) and its %d later line(s) are well formed" % (key, t, n, len(lines) - n))
elif mode == "trailer":
    anc, lines, t, n = full_check()
    if lines is None:
        os.makedirs(os.path.dirname(ledger), exist_ok=True)
        with open(ledger, "xb"):
            pass
        lines = []
    out(0, "%s: lines=%d sha256=%s" % (key, len(lines), prefix_sha(lines, len(lines))))
elif mode == "commit" and len(args) == 1:
    anc, lines, t, n = full_check()
    if lines is None:
        out(1, "the ledger %s is missing, but the commit message carries a %s trailer" % (ledger, key))
    try:
        with open(args[0], "rb") as f:
            body = f.read().decode("utf-8", "surrogateescape")
    except OSError:
        out(1, "cannot read the commit message file")
    mn, mh = trailer_of(body, "the commit message")
    if mn < n or mn > len(lines) or prefix_sha(lines, mn) != mh:
        out(1, "the commit message's %s trailer (lines=%d) no longer matches the ledger (%d lines)" % (key, mn, len(lines)))
    out(0, "the commit message's %s trailer matches the ledger" % key)
elif mode == "mark" and not args:
    lines = read_ledger()
    out(0, "absent" if lines is None else "lines=%d sha256=%s" % (len(lines), prefix_sha(lines, len(lines))))
elif mode == "turn" and len(args) == 3:
    mark, want_f, want_r = args
    m = MARK_RE.match(mark)
    if mark != "absent" and not m:
        out(2, "the mark must be the output of ledger_mark (lines=<n> sha256=<hash>, or absent), got: %s" % mark[:80])
    if not re.match(r"^(0|[1-9][0-9]*)$", want_f) or not re.match(r"^(0|[1-9][0-9]*)$", want_r):
        out(2, "the FAIL and REOPEN-REFUSED counts the harness saw must be whole numbers")
    n, h = (0, EMPTY) if mark == "absent" else (int(m.group(1)), m.group(2))
    lines = read_ledger()
    if lines is None:
        if mark != "absent":
            out(1, "the ledger was deleted during the turn (it had %d lines)" % n)
        lines = []
    if len(lines) < n:
        out(1, "the ledger was cut during the turn (%d lines, it had %d)" % (len(lines), n))
    if prefix_sha(lines, n) != h:
        out(1, "the first %d lines of the ledger changed during the turn" % n)
    f = r = 0
    for i in range(n, len(lines)):
        s = text(lines[i])
        if s is not None and FAIL_RE.match(s):
            f += 1
        elif s is not None and REFUSED_RE.match(s):
            r += 1
        elif s is not None and GRANT_RE.match(s):
            out(1, "ledger line %d is a GRANT-USED line appended during an unattended turn (grants are never used unattended)" % (i + 1))
        else:
            out(1, "ledger line %d, appended during the turn, is not a well-formed FAIL or REOPEN-REFUSED line" % (i + 1))
    if f != int(want_f) or r != int(want_r):
        out(1, "the turn appended %d FAIL and %d REOPEN-REFUSED line(s), but the harness saw %s docs-check failure(s) and %s refused --reopen run(s)" % (f, r, want_f, want_r))
    out(0, "the turn only appended %d FAIL and %d REOPEN-REFUSED line(s), as the harness saw" % (f, r))
else:
    out(2, "ledger_py: bad mode or arguments: %s" % " ".join([mode] + args))
PYLG
}
# ledger_guard <check>: N3A, run before <check>'s own rule. Refuses as <check> with "ledger changed, ask the user"
# when ledger_py check refuses. Outside a git repository there is no ledger, and the check's own rule decides.
ledger_guard() {
  git rev-parse --git-common-dir >/dev/null 2>&1 || return 0
  lg_rc=0; lg_out="$(ledger_py check)" || lg_rc=$?
  [ "$lg_rc" = 0 ] || refuse "$1" "ledger changed, ask the user (${lg_out:-the ledger check could not run})"
}

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
# passes in gate mode (`check-onboarding-docs.sh --gate`, JO-3/JO-4), which reads the gate-rules
# onboard_gate_docs list itself. The helper runs the docs check (read-only) and judges no doc content.
approval_evidence() {
  need_phase approval_evidence "${1:-}"
  [ "$1" = onboard ] || not_wired approval_evidence "phase $1 needs recorded approval evidence before its gate (only onboard is wired)" "the fix turn for $1"
  to_root
  ledger_guard approval_evidence
  [ -f "$ONB_STATE" ] || refuse approval_evidence "there is no onboarding state ($ONB_STATE); onboard has not run"
  ae_phase="$(state_field "$ONB_STATE" activePhase)" || refuse approval_evidence "$ONB_STATE is not valid JSON; stop and ask the user"
  ae_status="$(state_field "$ONB_STATE" activeStatus)" || refuse approval_evidence "$ONB_STATE is not valid JSON; stop and ask the user"
  [ "$ae_phase" = onboard ] || refuse approval_evidence "the active phase is ${ae_phase:-none}, not onboard awaiting_approval"
  [ "$ae_status" = awaiting_approval ] || refuse approval_evidence "onboard status is ${ae_status:-none}, not awaiting_approval"
  [ -s "$ONB_RESULT" ] || refuse approval_evidence "$ONB_RESULT is missing or empty"
  [ -f "$HERE/check-onboarding-docs.sh" ] || refuse approval_evidence "$HERE/check-onboarding-docs.sh is missing; reinstall the kit (install.sh --update)"
  if ! ae_docs="$(sh "$HERE/check-onboarding-docs.sh" --gate 2>&1)"; then
    printf '%s\n' "$ae_docs" | grep -E '^(FAIL|error|usage)' | sed 's/^/  /' >&2
    refuse approval_evidence "the onboarding docs check failed (check-onboarding-docs.sh --gate); run it, fix the docs, and ask again"
  fi
  ok approval_evidence "onboard is awaiting_approval, $ONB_RESULT exists and the onboarding docs check passed (--gate)"
}
# onb_tag_check <check>: the newest onboard-v<n> tag is on this branch and holds the current onboard approval
# (state.json approval at the tag equals HEAD's). Sets gc_tag; refuses as <check> otherwise.
onb_tag_check() {
  gc_n="$(git tag -l 'onboard-v*' | sed -n 's/^onboard-v\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)"
  [ -n "$gc_n" ] || refuse "$1" "no onboard-v<n> tag on the onboard gate commit; tag it: git tag -a onboard-v1 -m \"onboard approved\""
  gc_tag="onboard-v$gc_n"
  git merge-base --is-ancestor "$gc_tag^{commit}" HEAD 2>/dev/null || refuse "$1" "$gc_tag is not on this branch (not an ancestor of HEAD)"
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
    refuse "$1" "$gc_tag does not hold the current onboard approval; tag the new gate commit onboard-v$((gc_n + 1))"
  fi
}
# JO-1 (design rev 6 lines 69, 84, 96, 168): the approved <phase> has its gate commit. For onboard: onboard is in
# approvedPhases, check-gate-commit.sh (unchanged) passes on the onboarding report (the approval is in HEAD and
# the tree is clean), and the newest onboard-v<n> tag is on this branch and holds the current approval.
# Consumers: prereq_approved (JO-9) and the JO-8 commit chain; nothing in sync calls this check yet.
# TODO(JO-8): the commit's paths are a subset of gate-rules onboard_commit_paths plus the recorded pack paths, and
#   the range re-scan (design line 27) belong to the JO-8 commit chain and its secret scanner; not checked here.
# N3A: the ledger check (ledger_guard, the rule of ledger_ok) runs first: every onboard-v<n> gate commit must carry
# a well-formed Agents-V0-Ledger trailer that still anchors the ledger.
gate_committed() {
  need_phase gate_committed "${1:-}"
  [ "$1" = onboard ] || not_wired gate_committed "phase $1 must have its gate commit (only onboard is wired)" "the fix turn for $1"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse gate_committed "not a git work tree, so the onboard gate cannot be committed"
  to_root
  ledger_guard gate_committed
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
    refuse gate_committed "check-gate-commit.sh skipped its check (kit test override); a skipped check is not a gate commit" ;;
  esac
  onb_tag_check gate_committed
  ok gate_committed "onboard is approved, committed (check-gate-commit.sh) and tagged $gc_tag (path subset and range re-scan: JO-8, not checked yet)"
}
# JO-9 (design rev 6 flow step 9, lines 29, 73, 84, 97, 171; gap 1 brownfield only; gap 9): a <next-phase> listed
# in gate-rules prereq_approved_phases starts only after onboard is approved (onboarding/state.json) and its gate
# is committed (gate_committed onboard, which runs check-gate-commit.sh). A phase not in the list has no
# prerequisite here. Brownfield signal (any one): the onboarding state, the onboarding report, or the baseline-audit
# record (discovery/baseline-audit.txt, JO-15a). With none of them the repo is treated as not brownfield and the
# check passes.
# TODO(gap 9 / N2A, 5A): the content-rule fallback (a brownfield repo where onboard was skipped and no record was
#   written) and the greenfield record (greenfield_record_ok) are not built; until then a repo with no record passes.
PA_AUDIT="docs/agents-v0/discovery/baseline-audit.txt"
prereq_approved() {
  need_phase prereq_approved "${1:-}"
  pa_phases="$(rule prereq_approved_phases)" || exit 2
  case " $pa_phases " in
    *" $1 "*) ;;
    *) ok prereq_approved "$1 is not in gate-rules prereq_approved_phases ($pa_phases), so it needs no onboard approval" ;;
  esac
  to_root
  pa_need="$1 needs onboard approved and committed first"
  if [ ! -e "$ONB_STATE" ] && [ ! -e "$ONB_REPORT" ] && [ ! -e "$PA_AUDIT" ]; then
    ok prereq_approved "no brownfield record ($ONB_STATE, $ONB_REPORT, $PA_AUDIT), so $1 needs no onboard approval (brownfield only)"
  fi
  ledger_guard prereq_approved
  [ -f "$ONB_STATE" ] || refuse prereq_approved "$pa_need; onboard has not run ($ONB_STATE is missing). Run /v0-onboard first"
  pa_approved="$(state_field "$ONB_STATE" approvedPhases)" || refuse prereq_approved "$pa_need; $ONB_STATE is not valid JSON; stop and ask the user"
  case " $pa_approved " in
    *" onboard "*) ;;
    *) refuse prereq_approved "$pa_need; onboard is not approved in $ONB_STATE. Finish /v0-onboard and its approval first" ;;
  esac
  # The onboard gate commit: the approval in state.json is committed and unchanged since HEAD, and the newest
  # onboard-v<n> tag on this branch holds it. Unlike gate_committed, other uncommitted files do not refuse here:
  # the next command writes its own artifact (requirements/<feature>.md, roadmap/<program>.md, ...) before it
  # sets in_progress, and check-gate-commit.sh would count that file as uncommitted onboard work.
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse prereq_approved "$pa_need; not a git work tree, so the onboard gate cannot be committed"
  pa_committed=0
  if git ls-files --error-unmatch -- "$ONB_STATE" >/dev/null 2>&1 && git diff --quiet HEAD -- "$ONB_STATE" 2>/dev/null; then pa_committed=1; fi
  [ "$pa_committed" = 1 ] || refuse prereq_approved "$pa_need; the onboard approval in $ONB_STATE is not committed. Commit the onboard gate and tag it onboard-v<n> first"
  if ! pa_msg="$(onb_tag_check prereq_approved)"; then
    printf '%s\n' "$pa_msg" | sed "s/^REFUSED prereq_approved: /REFUSED prereq_approved: $pa_need; /"; exit 1
  fi
  pa_n="$(git tag -l 'onboard-v*' | sed -n 's/^onboard-v\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)"
  ok prereq_approved "$1: onboard is approved and committed (state.json committed, tagged onboard-v$pa_n)"
}
# JO-10 (design rev 6 flow step 2; Sakura SKO-1/2/3; N8 N28 N29 N30 E9): no state change on an onboard report
# that is awaiting review or approved. sync-feature-state.sh calls this on every onboard path but --approve
# (set in_progress, set blocked, --clear-active, a plain sync) and skips it only after reopen_grant_ok passes
# (4A, N5A, 1A; not built, so every --reopen onboard is refused for now). A missing or corrupt state is a
# refusal, never a new run, once an earlier run left a trace: phase-result.md (step 6) or an onboard-v<n> tag.
# report.md alone is not a trace: step 1 writes it before the first sync, so it cannot tell a new run from a
# lost state (reading of SKO-3; the report-only case is an open gap).
no_restart_without_reopen() {
  to_root
  ledger_guard no_restart_without_reopen
  nr_rule="no state change on an onboard report awaiting review or approved without a granted --reopen onboard"
  if [ ! -f "$ONB_STATE" ]; then
    nr_trace=""
    [ ! -f "$ONB_RESULT" ] || nr_trace="$ONB_RESULT"
    nr_tags="$(git tag -l 'onboard-v*' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    [ -z "$nr_tags" ] || nr_trace="${nr_trace:+$nr_trace }tags $nr_tags"
    [ -z "$nr_trace" ] || refuse no_restart_without_reopen "$ONB_STATE is missing but an earlier onboard run left $nr_trace; state missing or corrupt, stop and ask the user (this is not a new run)"
    ok no_restart_without_reopen "$nr_rule (no onboarding state and no earlier run: a new run)"
  fi
  nr_status="$(state_field "$ONB_STATE" activeStatus)" || refuse no_restart_without_reopen "$ONB_STATE is not valid JSON; state missing or corrupt, stop and ask the user (this is not a new run)"
  nr_approved="$(state_field "$ONB_STATE" approvedPhases)" || refuse no_restart_without_reopen "$ONB_STATE is not valid JSON; state missing or corrupt, stop and ask the user (this is not a new run)"
  case " $nr_approved " in
    *" onboard "*) refuse no_restart_without_reopen "onboard is approved in $ONB_STATE; a state change needs --reopen onboard with a grant that passes reopen_grant_ok. Stop and ask the user" ;;
  esac
  [ "$nr_status" != awaiting_approval ] || refuse no_restart_without_reopen "onboard is awaiting_approval in $ONB_STATE; wait for the user's approval (--approve onboard), or a --reopen onboard with a grant that passes reopen_grant_ok. Stop and ask the user"
  ok no_restart_without_reopen "$nr_rule (onboard is ${nr_status:-not started})"
}
# JO-8 (design rev 6 flow step 8, N7A; Sasuke SOC-2/3/9/13): the one commit chain of the onboard gate.
# onb_paths prints the onboard paths of gate-rules onboard_commit_paths that exist or are tracked (README.md is
# skipped when it is neither, so the add never fails on it).
# The rule values are split on spaces with globbing off, and each must be a plain path (letters, digits, . _ - /)
# so the printed chain needs no quoting (gate-rules is kit-owned; anything else is an error, not a guess).
onb_paths() {
  op_list="$(rule onboard_commit_paths)"
  set -f
  for op_ in $op_list; do
    case "$op_" in *[!A-Za-z0-9._/-]* | -* | /*) set +f; die "gate-rules onboard_commit_paths holds a path that is not plain: $op_" ;; esac
    if [ -e "$op_" ] || [ -n "$(GIT_LITERAL_PATHSPECS=1 git ls-files -- "$op_" 2>/dev/null | head -n 1)" ]; then printf '%s\n' "$op_"; fi
  done
  set +f
}
# onb_msg_file prints the commit message file in the git dir (the scan reads it; the commit uses it);
# onb_rec_file the scan record beside it (the sha256 of that message and the index tree the scan passed).
onb_msg_file() { git rev-parse --git-path agents-v0-onboard-commit-msg.txt; }
onb_rec_file() { git rev-parse --git-path agents-v0-onboard-commit-msg.scan; }
# onb_scan_state: print "msg_sha256=<hash of the message file> tree=<git write-tree of the index> head=<HEAD>"
# (exit 1 when the message file is missing or the index has no tree, e.g. unmerged entries).
onb_scan_state() {
  os_msg="$(onb_msg_file)"
  [ -f "$os_msg" ] || return 1
  os_sha="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$os_msg")" || return 1
  os_tree="$(git write-tree 2>/dev/null)" || return 1
  os_head="$(git rev-parse -q --verify HEAD 2>/dev/null || echo none)"
  printf 'msg_sha256=%s tree=%s head=%s\n' "$os_sha" "$os_tree" "$os_head"
}
# staged_path_check <allowed paths>: read the index NUL-separated (`git diff --cached --name-only -z
# --no-renames`) and check each path whole: no word splitting, no glob expansion, no pathspec magic (Iruka
# probe 8). A path is allowed when it equals an onboard path or sits under one, and is not a *.lock file.
# Exit 0 all allowed; 1 prints the refused paths (a name with a space, quote, backslash or control character is
# printed JSON-quoted); 3 nothing is staged; 2 git could not read the index.
staged_path_check() {
  python3 - "$1" <<'PYSP'
import json, subprocess, sys
allowed = sys.argv[1].split()
p = subprocess.Popen(["git", "diff", "--cached", "--name-only", "-z", "--no-renames"],
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
out, _ = p.communicate()
if p.returncode != 0:
    sys.exit(2)
paths = [x.decode("utf-8", "surrogateescape") for x in out.split(b"\0") if x]
if not paths:
    sys.exit(3)
def show(x):
    return x if all(c.isprintable() and c not in ' "\\' for c in x) else json.dumps(x)
bad = [x for x in paths
       if x.endswith(".lock") or not any(x == a or x.startswith(a + "/") for a in allowed)]
if bad:
    print(" ".join(show(x) for x in bad))
    sys.exit(1)
PYSP
}
# other_dirty: the uncommitted files outside the index's staged set, read NUL-separated from git status (named
# the same way as staged_path_check names them).
other_dirty() {
  python3 - <<'PYOD'
import json, subprocess, sys
p = subprocess.Popen(["git", "status", "--porcelain=v1", "-z", "-uall"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
out, _ = p.communicate()
if p.returncode != 0:
    sys.exit(2)
items = out.split(b"\0")
names, i = set(), 0
while i < len(items):
    e = items[i]; i += 1
    if len(e) < 4:
        continue
    xy, path = e[:2].decode("ascii", "replace"), e[3:].decode("utf-8", "surrogateescape")
    if xy[0] in "RC":
        i += 1  # the rename/copy source follows
    if xy == "??" or xy[1] != " ":
        names.add(path)
def show(x):
    return x if all(c.isprintable() and c not in ' "\\' for c in x) else json.dumps(x)
print(" ".join(show(x) for x in sorted(names)))
PYOD
}
# commit_chain: print the onboard gate commit chain, in order (narrowed add, staged-path check and secret scan,
# the commit step's re-check of the scan record (commit_msg_ok), commit with no pathspec, no -a and never --amend,
# the next onboard-v<n> tag). It runs nothing.
commit_chain() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git work tree"
  to_root
  cc_paths="$(onb_paths | tr '\n' ' ')"
  [ -n "$cc_paths" ] || die "none of gate-rules onboard_commit_paths exists"
  cc_n="$(git tag -l 'onboard-v*' | sed -n 's/^onboard-v\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)"
  cc_n=$(( ${cc_n:-0} + 1 ))
  printf "git add --all -- %s':(exclude,glob)**/*.lock' && sh .agents-v0/scripts/gate-checks.sh staged_secret_scan && sh .agents-v0/scripts/gate-checks.sh commit_msg_ok && git commit -F %s && git tag -a onboard-v%s -m \"onboard approved\"\n" \
    "$cc_paths" "$(onb_msg_file)" "$cc_n"
}
# staged_secret_scan: after the narrowed add and before the commit. Refuses when the index holds a path outside
# the onboard paths or a *.lock file (named; nothing is unstaged), when nothing is staged, or when
# secret_scan.py exits non-zero (1 hit, 2 could not scan: fail closed). The scanner's output passes through
# unchanged (it never prints the secret; its allow-list is read from HEAD). Other dirty files are listed, not
# swept in. Not here yet: the gate_committed range re-scan after the commit (design step 8, N40).
staged_secret_scan() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse staged_secret_scan "not a git work tree, so nothing can be scanned"
  to_root
  ss_root="$(pwd)"
  ss_allowed="$(rule onboard_commit_paths)"
  command -v python3 >/dev/null 2>&1 || refuse staged_secret_scan "python3 is missing, so the staged-path check and the secret scan cannot run"
  # N3A: the ledger check runs first, and its trailer goes into the message before the scan reads the message
  # and the record takes its hash (so commit_msg_ok compares the message with the trailer in it).
  ss_rc=0; ss_trailer="$(ledger_py trailer)" || ss_rc=$?
  [ "$ss_rc" = 0 ] || refuse staged_secret_scan "ledger changed, ask the user (${ss_trailer:-the ledger check could not run}); no commit message was written and the commit is refused"
  ss_rc=0
  ss_bad="$(staged_path_check "$ss_allowed")" || ss_rc=$?
  case "$ss_rc" in
    0) ;;
    1) refuse staged_secret_scan "the index holds paths outside gate-rules onboard_commit_paths ($ss_allowed) or lock files: $ss_bad. Nothing was unstaged; unstage them yourself (git restore --staged -- <path>) or ask the user" ;;
    3) refuse staged_secret_scan "nothing is staged; run the add of the commit chain first (gate-checks.sh commit_chain)" ;;
    *) refuse staged_secret_scan "git could not read the index" ;;
  esac
  [ -f .agents-v0/scripts/secret_scan.py ] || refuse staged_secret_scan ".agents-v0/scripts/secret_scan.py is missing; reinstall the kit (install.sh --update)"
  ss_msg="$(onb_msg_file)"
  printf 'onboarding: onboard approved\n\n%s\n' "$ss_trailer" > "$ss_msg" || refuse staged_secret_scan "cannot write the commit message file $ss_msg"
  ss_rc=0
  python3 .agents-v0/scripts/secret_scan.py --staged --root "$ss_root" --message-file "$ss_msg" || ss_rc=$?
  [ "$ss_rc" = 0 ] || refuse staged_secret_scan "secret_scan.py exited $ss_rc (1: a hit, 2: it could not scan); the commit is refused"
  ss_state="$(onb_scan_state)" || refuse staged_secret_scan "cannot record the scan (message file or index tree unreadable); the commit is refused"
  printf '%s\n' "$ss_state" > "$(onb_rec_file)" || refuse staged_secret_scan "cannot write the scan record $(onb_rec_file); the commit is refused"
  ss_other="$(other_dirty)" || ss_other=""
  [ -z "$ss_other" ] || printf 'other uncommitted files, not in this commit: %s\n' "$ss_other"
  ok staged_secret_scan "the index holds only onboard paths and no secret; commit with: git commit -F $ss_msg"
}
# commit_msg_ok: the commit step of the chain, right before `git commit -F` (Jiraiya; Sasuke's gap). Passes only
# when the scan record staged_secret_scan wrote matches now: the same message file bytes (sha256), the same
# index tree (git write-tree) and the same HEAD. A message or index changed after the scan, a missing record or a
# record from an earlier commit is refused; nothing is printed from the message. N3A: then the ledger check, and
# the message's Agents-V0-Ledger trailer must still anchor the ledger (a ledger cut or edited after the scan).
commit_msg_ok() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse commit_msg_ok "not a git work tree"
  to_root
  command -v python3 >/dev/null 2>&1 || refuse commit_msg_ok "python3 is missing, so the scan record cannot be checked"
  cm_rec="$(onb_rec_file)"
  [ -f "$cm_rec" ] || refuse commit_msg_ok "no scan record ($cm_rec); run the whole chain from gate-checks.sh commit_chain"
  cm_want="$(cat "$cm_rec")"
  cm_now="$(onb_scan_state)" || refuse commit_msg_ok "the commit message file $(onb_msg_file) is missing or the index has no tree; run the whole chain again"
  cm_w_msg="$(printf '%s\n' "$cm_want" | sed -n 's/^msg_sha256=\([0-9a-f]*\) .*/\1/p')"
  cm_n_msg="$(printf '%s\n' "$cm_now" | sed -n 's/^msg_sha256=\([0-9a-f]*\) .*/\1/p')"
  [ -n "$cm_w_msg" ] && [ "$cm_w_msg" = "$cm_n_msg" ] || refuse commit_msg_ok "the commit message file changed after staged_secret_scan; run the whole chain again (it rescans)"
  cm_w_rest="${cm_want#* }"; cm_n_rest="${cm_now#* }"
  [ "${cm_w_rest%% *}" = "${cm_n_rest%% *}" ] || refuse commit_msg_ok "the index changed after staged_secret_scan; run the whole chain again (it rescans)"
  [ "$cm_want" = "$cm_now" ] || refuse commit_msg_ok "HEAD moved after staged_secret_scan (the record is from an earlier commit); run the whole chain again"
  cm_rc=0; cm_led="$(ledger_py commit "$(onb_msg_file)")" || cm_rc=$?
  [ "$cm_rc" = 0 ] || refuse commit_msg_ok "ledger changed, ask the user (${cm_led:-the ledger check could not run}); the commit is refused"
  ok commit_msg_ok "the commit message and the index are the ones staged_secret_scan passed"
}
# 4A, N5A, 1A (1A-gap B): the grant parses, names <phase>, is newer than the last gate of <phase>, is at most
# grant_max_age_seconds old, is unused (no GRANT-USED line, not in git history) and the run is attended.
reopen_grant_ok() {
  need_phase reopen_grant_ok "${1:-}"
  ledger_guard reopen_grant_ok
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
# N3A (design rev 6 "Ledger integrity (N3A)"; N80-N83): the ledger still starts with the lines every gate commit's
# $LEDGER_TRAILER trailer anchored, and the lines after the newest anchor are well formed (ledger_py check).
# The same rule runs first in approval_evidence, gate_committed, prereq_approved, no_restart_without_reopen,
# staged_secret_scan, commit_msg_ok and reopen_grant_ok (ledger_guard). Not wired yet: the docs-check count
# (check-onboarding-docs.sh does not count or write FAIL lines yet, gap 10).
ledger_ok() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse ledger_ok "not a git work tree, so there is no gate ledger"
  lo_rc=0; lo_out="$(ledger_py check)" || lo_rc=$?
  [ "$lo_rc" = 0 ] || refuse ledger_ok "ledger changed, ask the user (${lo_out:-the ledger check could not run})"
  ok ledger_ok "$lo_out"
}
# N84 (unattended runs): the harness prints ledger_mark before each turn and runs ledger_turn_ok after it with the
# FAIL (docs check) and REOPEN-REFUSED (refused --reopen) runs it saw. Anything else (a GRANT-USED line, an edit, a
# cut, a deleted ledger, a count that differs) refuses: stop the run.
ledger_turn_ok() {
  git rev-parse --git-common-dir >/dev/null 2>&1 || refuse ledger_turn_ok "not a git repository, so there is no gate ledger"
  lt_rc=0; lt_out="$(ledger_py turn "$1" "$2" "$3")" || lt_rc=$?
  case "$lt_rc" in
    0) ok ledger_turn_ok "$lt_out" ;;
    1) refuse ledger_turn_ok "ledger changed during the unattended turn, stop the run and ask the user ($lt_out)" ;;
    *) die "ledger_turn_ok: ${lt_out:-the ledger check could not run}" ;;
  esac
}

# --- dispatch -------------------------------------------------------------------------------------------
[ "$#" -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
  -h|--help) usage ;;
  rules)
    [ "$#" -le 1 ] || usage
    if [ "$#" = 1 ]; then rule "$1"; else load_rules; fi ;;
  commit_chain)
    [ "$#" = 0 ] || usage
    load_rules > /dev/null
    commit_chain ;;
  ledger_mark)
    [ "$#" = 0 ] || usage
    lm_rc=0; lm_out="$(ledger_py mark)" || lm_rc=$?
    [ "$lm_rc" = 0 ] || die "ledger_mark: ${lm_out:-the ledger could not be read}"
    printf '%s\n' "$lm_out" ;;
  ledger_turn_ok)
    [ "$#" = 3 ] || usage
    ledger_turn_ok "$1" "$2" "$3" ;;
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
  no_restart_without_reopen|staged_secret_scan|commit_msg_ok|greenfield_record_ok|ledger_ok)
    [ "$#" = 0 ] || usage
    load_rules > /dev/null
    "$cmd" ;;
  *) printf 'error: unknown check: %s\n' "$cmd" >&2; usage ;;
esac
