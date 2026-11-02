#!/bin/sh
# gate-checks.sh — the shared gate helper of the onboard fix (step 0 skeleton).
#   sh .agents-v0/scripts/gate-checks.sh <check> [arg]      run one check
#   sh .agents-v0/scripts/gate-checks.sh rules [key]        print the validated gate-rules (or one value)
#   sh .agents-v0/scripts/gate-checks.sh paths              print the git common dir, ledger and grant paths
#   sh .agents-v0/scripts/gate-checks.sh list               print every check and whether it is wired
#   sh .agents-v0/scripts/gate-checks.sh commit_chain       print the onboard gate commit chain (JO-8); runs nothing
#   sh .agents-v0/scripts/gate-checks.sh ledger_mark        print the gate ledger's mark (N84: lines=<n> sha256=<h>, or absent)
#   sh .agents-v0/scripts/gate-checks.sh greenfield_trailer create the empty ledger, print the greenfield root trailer
#   sh .agents-v0/scripts/gate-checks.sh adopt_legacy_tags  the person only, once per repo: adopt the onboard-v<n> tags
#                                                           made before the gate ledger (adopt_legacy_tags --help)
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
#   NONE <check>: <reason>                 exit 4, greenfield_record_ok only: there is no valid record to judge
#                                          (no record, or two root commits); the content rule decides
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
# bootstrap-greenfield.sh writes this marker (rootCommit=, reason=, markedAt= lines) beside the ledger when a root
# commit exists but failed a check; greenfield_record_ok refuses while it exists (round 18).
UNTRUSTED_REL="agents-v0/untrusted-root"
# adopt_legacy_tags writes this record once, when the person adopts the onboard-v<n> tags that have no
# Agents-V0-Ledger trailer (made before the kit had the ledger; round 19, legacy option A). The ledger check then
# counts each adopted tag as an anchor of the ledger the record pinned; any other tag without a trailer refuses.
ADOPT_REL="agents-v0/legacy-adoption"
# Every gate commit carries this trailer (N3A): Agents-V0-Ledger: lines=<n> sha256=<hash of the first n lines>.
LEDGER_TRAILER="Agents-V0-Ledger"

# Checks whose logic is built (a wired check may still carry TODOs for later fixes; see its comment).
WIRED="approval_evidence gate_committed prereq_approved no_restart_without_reopen staged_secret_scan commit_msg_ok reopen_grant_ok ledger_ok ledger_turn_ok greenfield_record_ok"
CHECKS="approval_evidence gate_committed prereq_approved no_restart_without_reopen staged_secret_scan commit_msg_ok reopen_grant_ok greenfield_record_ok baseline_ok ledger_ok ledger_turn_ok"

usage() {
  printf 'usage: sh .agents-v0/scripts/gate-checks.sh <check> [arg] | rules [key] | paths | list | commit_chain | ledger_mark | greenfield_trailer\n' >&2
  printf '       sh .agents-v0/scripts/gate-checks.sh ledger_turn_ok <mark> <fails seen> <refusals seen>\n' >&2
  printf '       sh .agents-v0/scripts/gate-checks.sh adopt_legacy_tags [--help]   (the person only, once per repo)\n' >&2
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
adopt_path() { gcd="$(git_common_dir)" || exit 2; printf '%s/%s\n' "$gcd" "$ADOPT_REL"; }

# --- checks ---------------------------------------------------------------------------------------------
ok() { printf 'OK %s: %s\n' "$1" "$2"; exit 0; }
refuse() { printf 'REFUSED %s: %s\n' "$1" "$2"; exit 1; }
none() { printf 'NONE %s: %s\n' "$1" "$2"; exit 4; }
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
#                             a second reopen appends its grant, so an older GRANT-USED line still finds its own),
#                             and the grant file (a regular file, never a symlink) still starts with the grant lines
#                             the ledger named, in ledger order (no named line edited, removed or reordered)
#   trailer                   check, mark every grant line no ledger line names yet as stale (REOPEN-REFUSED
#                             grant=<sha> stale: ...), then print the trailer for the next gate commit (creates the
#                             empty ledger when no gate commit exists yet and nothing has written it). A stale line
#                             counts only once it is pinned: it sits in the run of stale lines that ends a landed
#                             onboard-v<n> gate commit's trailer count. Then a grant that was in the file at that
#                             gate commit can never be used after it. A stale line that no landed gate commit pins
#                             (the scan was refused, or no commit followed) is void and names nothing
#   reopen <phase> <max age>  check, then judge the last grant line (reopen_grant_ok) and append GRANT-USED on
#                             success or one REOPEN-REFUSED line on refusal
#   commit <msg file>         check, and the message's own trailer still anchors the ledger (commit_msg_ok)
#   mark                      print "lines=<n> sha256=<hash>" or "absent" (the harness, before an unattended turn)
#   turn <mark> <fails> <refusals>
#                             since <mark>: nothing cut, edited or deleted; only FAIL and REOPEN-REFUSED lines
#                             appended, exactly as many as the harness saw (N84)
# Lines are newline-terminated; the line grammar (the kit writers must follow it):
#   FAIL[ <text>]   GRANT-USED <sha256 of the grant line, without its newline> count=<n>   REOPEN-REFUSED <text>
#   REOPEN-REFUSED grant=<sha256 of the grant line> <text>   (a refused grant line: named, so used up; with
#   <text> "stale: ..." it names the grant only when pinned, see trailer above)
# The grant file holds one grant line per approved reopen, appended, the newest last (the grant in force):
#   grant <YYYY-MM-DDTHH:MM:SS+HH:MM> phase=<phase> reason="<text>" by=<name>
# Each grant line is named by exactly one ledger line (GRANT-USED or REOPEN-REFUSED grant=; pinned stale lines
# of one gate commit may repeat a grant, void stale lines are ignored) and the named lines are the start of the
# grant file, in ledger order; only the last line may still be unnamed, and only it is used.
# where <text> has no control characters. The newest anchor is the highest onboard-v<n> tag, and no tag records
# fewer lines than an older one (the ledger is shared by every worktree, so is every tag).
ledger_py() {
  lp_l="$(ledger_path)" || exit 2
  lp_g="$(grant_path)" || exit 2
  lp_a="$(adopt_path)" || exit 2
  python3 - "$lp_l" "$lp_g" "$lp_a" "$LEDGER_TRAILER" "$@" <<'PYLG'
import hashlib, os, re, subprocess, sys
ledger, grant, adopt, key, mode, args = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6:]
TRAILER_RE = re.compile(r"^" + re.escape(key) + r": lines=(0|[1-9][0-9]*) sha256=([0-9a-f]{64})$")
KEY_RE = re.compile(r"^\s*" + re.escape(key) + r"\s*:", re.I)
FAIL_RE = re.compile(r"^FAIL(?: [^\x00-\x1f\x7f]+)?$")
GRANT_RE = re.compile(r"^GRANT-USED ([0-9a-f]{64}) count=(0|[1-9][0-9]*)$")
REFUSED_RE = re.compile(r"^REOPEN-REFUSED [^\x00-\x1f\x7f]+$")
REFGRANT_RE = re.compile(r"^REOPEN-REFUSED grant=([0-9a-f]{64}) [^\x00-\x1f\x7f]+$")
GLINE_RE = re.compile(r'^grant ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})([+-][0-9]{2}):?([0-9]{2}) '
                      r'phase=([a-z][a-z-]*) reason=("[^"\x00-\x1f\x7f]+"|[^"\s\x00-\x1f\x7f]+) '
                      r'by=("[^"\x00-\x1f\x7f]+"|[^"\s\x00-\x1f\x7f]+)$')
STALE_TEXT = "stale: "
FUTURE_SKEW = 120  # seconds a grant may be ahead of this clock (two machines' clocks; see reopen_grant_ok)
MARK_RE = re.compile(r"^lines=(0|[1-9][0-9]*) sha256=([0-9a-f]{64})$")
EMPTY = hashlib.sha256(b"").hexdigest()
RECORD = ".agents-v0/greenfield-record.json"  # GF_RECORD below

SIM = None  # trailer mode: the prefix of a refusal found while checking the ledger as the gate commit would pin it

def out(code, msg):
    print(SIM + msg if SIM and code == 1 else msg)
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

def root_anchor():
    # 5A, N2A: a greenfield repo's only root commit holds the record and anchors the empty ledger (lines=0, the
    # empty hash); bootstrap-greenfield.sh writes that trailer (greenfield_trailer). With two or more roots (E31)
    # the record is not valid and the root anchors nothing.
    if git("rev-parse", "-q", "--verify", "HEAD^{commit}").returncode != 0:
        return []
    r = git("rev-list", "--max-parents=0", "HEAD")
    if r.returncode != 0:
        out(1, "git could not list the root commits")
    roots = r.stdout.decode().split()
    if len(roots) != 1 or git("cat-file", "-e", roots[0] + ":" + RECORD).returncode != 0:
        return []
    b = git("cat-file", "commit", roots[0])
    if b.returncode != 0:
        out(1, "git could not read the root commit %s" % roots[0][:12])
    body = b.stdout.decode("utf-8", "surrogateescape")
    where = "the greenfield root commit %s" % roots[0][:12]
    n, h = trailer_of(body.split("\n\n", 1)[1] if "\n\n" in body else "", where)
    if n != 0 or h != EMPTY:
        out(1, "%s must record lines=0 sha256=%s (the empty ledger), not lines=%d" % (where, EMPTY, n))
    return [(where, 0, EMPTY)]

LZ_TEXT = ("the tag %s has a leading zero; onboard-v<n> tags are numbered without one, because the kit reads the "
           "number as decimal in python and as octal in the shell. Stop and show the user: a person (never an agent) "
           "replaces that tag")

# The legacy adoption record (round 19, legacy option A): written once by the person with adopt_legacy_tags, in
# the git common dir next to the ledger (the hooks protect .git/agents-v0/). Strict format, one key per line:
#   ADOPT_HEAD / adoptedAt=<local time> / kitSha=<7-40 hex[-dirty]|unknown> / head=<commit> / ledgerLines=<n> /
#   ledgerSha256=<64 hex of the first n ledger lines> / tag=onboard-v<n> <commit> (one or more, ascending)
ADOPT_HEAD = ("# agents-v0 legacy tag adoption record: written once by the person with gate-checks.sh "
              "adopt_legacy_tags; never edit, never commit")
ADOPT_KEYS = ["adoptedAt", "kitSha", "head", "ledgerLines", "ledgerSha256"]
OID = r"(?:[0-9a-f]{40}|[0-9a-f]{64})"
ADOPT_VAL = {
    "adoptedAt": r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}",
    "kitSha": r"unknown|[0-9a-f]{7,40}(?:-dirty)?",
    "head": OID,
    "ledgerLines": r"0|[1-9][0-9]*",
    "ledgerSha256": r"[0-9a-f]{64}",
}
ADOPTED = {}  # tag -> the record, for the anchors the record adopted (anchor_name)

def read_adoption():
    if not os.path.lexists(adopt):
        return None
    def bad(why):
        out(1, "the legacy adoption record %s is not valid (%s); the person writes it once with sh "
               ".agents-v0/scripts/gate-checks.sh adopt_legacy_tags and nobody edits it. Stop and show the user"
               % (adopt, why))
    if os.path.islink(adopt) or not os.path.isfile(adopt):
        bad("it is not a regular file")
    with open(adopt, "rb") as f:
        data = f.read()
    if not data.endswith(b"\n"):
        bad("its last line has no newline")
    if b"\r" in data:
        bad("it holds a carriage return")
    s = text(data)
    if s is None:
        bad("it is not UTF-8")
    L = s.split("\n")[:-1]
    if not L or L[0] != ADOPT_HEAD:
        bad("line 1 is not the record header")
    if len(L) < len(ADOPT_KEYS) + 2:
        bad("it has %d lines; it needs the header, %s and at least one tag= line" % (len(L), ", ".join(ADOPT_KEYS)))
    rec = {"path": adopt, "tags": {}}
    for i, (k, x) in enumerate(zip(ADOPT_KEYS, L[1:]), 2):
        if not x.startswith(k + "=") or not re.fullmatch(ADOPT_VAL[k], x[len(k) + 1:]):
            bad("line %d must be %s=<%s>" % (i, k, ADOPT_VAL[k]))
        rec[k] = x[len(k) + 1:]
    last = -1
    for i, x in enumerate(L[len(ADOPT_KEYS) + 1:], len(ADOPT_KEYS) + 2):
        m = re.fullmatch(r"tag=onboard-v(0|[1-9][0-9]*) (%s)" % OID, x)
        if not m:
            bad("line %d must be tag=onboard-v<n> <commit sha>" % i)
        if int(m.group(1)) <= last:
            bad("line %d: the tag= lines must be in ascending order, each tag once" % i)
        last = int(m.group(1))
        rec["tags"]["onboard-v" + m.group(1)] = m.group(2)
    rec["n"] = int(rec["ledgerLines"])
    return rec

def adopted_list(rec):
    return ", ".join(sorted(rec["tags"], key=lambda x: int(x[len("onboard-v"):])))

def legacy_hint(t, sha, rec):
    where = "the gate commit %s (%s) has no %s trailer" % (t, sha[:12], key)
    if rec is None:
        return ("%s; if this repo's onboard-v<n> tags were made before the kit kept the gate ledger, the person (never "
                "an agent) adopts them once in their own terminal with sh .agents-v0/scripts/gate-checks.sh "
                "adopt_legacy_tags (in a fresh clone of a repo that already adopted them, the person copies "
                "legacy-adoption, gate-ledger and reopen-grant from the original checkout's agents-v0/ instead). Stop "
                "and show the user" % where)
    return ("%s, and it is not one of the tags the legacy adoption record %s adopted (%s, at %s); adoption runs once, "
            "so a tag made after it must carry the trailer (replace it with the gate commit chain from sh "
            ".agents-v0/scripts/gate-checks.sh commit_chain). Stop and show the user"
            % (where, rec["path"], adopted_list(rec), rec["adoptedAt"]))

def tag_no(anc):
    return [int(a[0][len("onboard-v"):]) for a in anc if a[0].startswith("onboard-v")]

def anchors(adopting=False):
    # adopting (adopt mode): returns (root anchor, [(tag, commit)] of the trailer-less tags) and refuses any tag
    # that has a trailer, so the record only ever adopts a repo whose every tag predates the ledger.
    rec = None if adopting else read_adoption()
    legacy = []
    r = git("tag", "-l", "onboard-v*")
    if r.returncode != 0:
        out(1, "git could not list the onboard-v<n> tags")
    # onboard-v<n> with n = 0 or no leading zero (round 18): git and int() read onboard-v011 as 11, but the shell's
    # $(( )) reads 011 as octal 9 and stops on 08, so a leading-zero tag is refused here and in commit_chain.
    names = r.stdout.decode("utf-8", "replace").split("\n")
    for t in names:
        if re.fullmatch(r"onboard-v0[0-9]+", t):
            out(1, LZ_TEXT % t)
    tags = [t for t in names if re.fullmatch(r"onboard-v(0|[1-9][0-9]*)", t)]
    found = root_anchor()
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
        where = "the gate commit %s (%s)" % (t, sha[:12])
        if not any(KEY_RE.match(x) for x in msg.split("\n")):
            if adopting:
                legacy.append((t, sha))
                continue
            if rec is not None and t in rec["tags"]:
                if rec["tags"][t] != sha:
                    out(1, "the tag %s names %s, but the legacy adoption record %s adopted it at %s (the tag was moved "
                           "after the adoption). Stop and show the user: a person (never an agent) puts the tag back"
                           % (t, sha[:12], rec["path"], rec["tags"][t][:12]))
                ADOPTED[t] = rec
                found.append((t, rec["n"], rec["ledgerSha256"]))
                continue
            out(1, legacy_hint(t, sha, rec))
        if adopting:
            out(1, "%s carries an %s trailer, so this repo is not a legacy repo: adoption is only for a repo whose "
                   "every onboard-v<n> tag was made before the kit kept the gate ledger, and nothing was written"
                   % (where, key))
        n, h = trailer_of(msg, where)
        found.append((t, n, h))
    if adopting:
        return found, legacy
    if rec is not None:
        for t in sorted(rec["tags"], key=lambda x: int(x[len("onboard-v"):])):
            if t not in ADOPTED:
                out(1, "the legacy adoption record %s adopted %s (%s), but that tag is gone, moved or no longer names a "
                       "commit. Stop and show the user: a person (never an agent) puts the tag back"
                       % (rec["path"], t, rec["tags"][t][:12]))
    return found

def clone_hint(anc):
    # round 17 (fresh-clone option A): the ledger and the grant file live in the git common dir, so a clone has
    # neither. The refusal stays; the hint says how the person starts the ledger. Nothing here copies or creates it.
    if not tag_no(anc):
        return ("if this checkout is a fresh clone of a greenfield repo with no onboard-v<n> tag yet, the person (never "
                "an agent) creates the empty ledger file %s (the root commit recorded lines=0), or copies gate-ledger "
                "from the original checkout to keep the lines written there since" % ledger)
    return ("if this checkout is a fresh clone, the person (never an agent) copies gate-ledger and, when it exists, "
            "reopen-grant from the original checkout's git common dir (agents-v0/; sh .agents-v0/scripts/gate-checks.sh "
            "paths prints both paths in each checkout) to %s and %s, and copies them only after every pending (unused) "
            "grant line in the original's reopen-grant has been used or refused there (a pending grant copied into the "
            "clone could be used once in each checkout; a grant used before the copy is refused as already used); the "
            "kit has no other way to start the ledger in a clone, so if the original checkout is gone, stop and tell "
            "the user" % (ledger, grant))

def anchor_name(t):
    # an anchor is a gate commit (its onboard-v<n> tag), a legacy tag the adoption record adopted (the record pins
    # the ledger then), or "the greenfield root commit <sha>" (root_anchor)
    if t in ADOPTED:
        return "the legacy adoption record %s (adopted tag %s)" % (ADOPTED[t]["path"], t)
    return "the gate commit " + t if t.startswith("onboard-v") else t

def check_anchors(lines, anc):
    if lines is None:
        if anc:
            t, n, _ = anc[-1]
            out(1, "the ledger %s is missing, but %s recorded lines=%d; a missing ledger never reads as zero failures; %s" % (ledger, anchor_name(t), n, clone_hint(anc)))
        return None, 0
    for t, n, h in anc:
        if len(lines) < n:
            out(1, "the ledger has %d lines, fewer than the %d that %s recorded" % (len(lines), n, anchor_name(t)))
        if prefix_sha(lines, n) != h:
            out(1, "the first %d lines of the ledger no longer match the sha256 that %s recorded (an earlier line was edited)" % (n, anchor_name(t)))
    if not anc:
        return None, 0
    # the newest gate commit is the highest onboard-v<n> (anchors() sorts by number; the reopen time check and the
    # next tag number use the same rule). Each gate commit pins the whole ledger and the ledger only grows, so a
    # gate never records fewer lines than an older one.
    for (t0, n0, _), (t1, n1, _) in zip(anc, anc[1:]):
        if n1 < n0:
            out(1, "%s recorded lines=%d, fewer than the %d of the older %s (the ledger only grows)" % (anchor_name(t1), n1, n0, anchor_name(t0).replace("the ", "", 1)))
    t, n, _ = anc[-1]
    return t, n

def sha(x):
    return hashlib.sha256(x).hexdigest()

def read_grant():
    # the grant file's lines (each without its newline) and its bytes, or (None, None) when there is no file.
    # The person writes it in their own terminal; a symlink or anything but a regular file is refused.
    if not os.path.lexists(grant):
        return None, None
    if os.path.islink(grant):
        out(1, "the grant file %s is a symlink; it must be a regular file that the person appends to" % grant)
    if not os.path.isfile(grant):
        out(1, "the grant file %s is not a regular file" % grant)
    with open(grant, "rb") as f:
        data = f.read()
    parts = data.split(b"\n")
    return (parts[:-1] if data.endswith(b"\n") else parts) if data else [], data

def is_stale(s):
    m = REFGRANT_RE.match(s) if s is not None else None
    return bool(m) and s[len("REOPEN-REFUSED grant=") + 65:].startswith(STALE_TEXT)

def pinned_stale(lines, anc):
    # the 0-based ledger indexes of pinned stale lines: for each landed gate commit (onboard-v<n> tag) with trailer
    # count n, the run of stale lines that ends at line n (the gate's own scan writes them right before its trailer)
    pins = set()
    for _, n, _ in anc:
        i = min(n, len(lines)) - 1
        while i >= 0 and is_stale(text(lines[i])):
            pins.add(i)
            i -= 1
    return pins

def named_grants(lines, anc):
    # (ledger line number, grant sha, kind) of the line that names each grant, in ledger order: a GRANT-USED or
    # non-stale REOPEN-REFUSED grant= line, or a pinned stale line. Void (unpinned) stale lines are skipped. A grant
    # named twice is refused, except by several pinned stale lines (repeated scans before one gate commit).
    pins = pinned_stale(lines, anc)
    found, first, dup = [], {}, None
    for i, x in enumerate(lines):
        s = text(x)
        m = GRANT_RE.match(s) if s is not None else None
        kind = "GRANT-USED" if m else None
        if not m:
            m = REFGRANT_RE.match(s) if s is not None else None
            if not m:
                continue
            kind = "REOPEN-REFUSED"
            if is_stale(s):
                if i not in pins:
                    continue
                kind = "stale"
        h = m.group(1)
        if h in first:
            j, k0 = first[h]
            if k0 == "stale" and kind == "stale":
                continue
            if dup is None:
                if k0 == "GRANT-USED" and kind == "GRANT-USED":
                    dup = "ledger line %d names a grant that another GRANT-USED line already used" % j
                elif "stale" in (k0, kind):
                    dup = ("ledger line %d names a grant that ledger line %d also names, and the stale one is pinned by a gate "
                           "commit (a grant in the grant file at a gate commit is never usable after it)" % (i + 1, j))
                else:
                    dup = "ledger line %d names a grant that another ledger line already named (each grant line is named once)" % j
            continue
        first[h] = (i + 1, kind)
        found.append((i + 1, h, "REOPEN-REFUSED" if kind == "stale" else kind))
    return found, dup

def check_grants(lines, anc):
    # every named grant is a grant-file line, named once, and the named lines are the start of the grant file in
    # ledger order. Returns (grant lines, grant bytes, named).
    named, dup = named_grants(lines, anc)
    g, data = read_grant()
    if not named:
        return g, data, named
    if g is None:
        i, _, k = named[0]
        out(1, "ledger line %d is a %s line, but there is no grant file (%s)" % (i, k, grant))
    if dup:
        out(1, dup)
    hs = [sha(x) for x in g]
    where = {}
    for j, h in enumerate(hs):
        where.setdefault(h, j)
    for o, (i, h, k) in enumerate(named):
        if h in where:
            continue
        msg = "ledger line %d is a %s line that names no grant in %s" % (i, k, grant)
        if not g:
            msg += " (the grant file is empty)"
        elif any(h2 in where and where[h2] < o2 for o2, (i2, h2, _) in enumerate(named) if o2 > o):
            # a grant named after this one now sits higher in the file than its place: either this line names a hash
            # that was never a grant line here (a forged or foreign line, Iruka R1), or lines above it are gone. The
            # two read the same from the files, so the hint names both.
            msg += (" (this line names a hash that is not a grant line here, or an earlier grant line is gone: the grant "
                    "file was overwritten instead of appended, or a line was removed)")
        out(1, msg)
    for o, (i, h, k) in enumerate(named):
        if o >= len(hs) or hs[o] != h:
            out(1, "grant line %d of %s is not the grant that ledger line %d named (grant lines were reordered, or a line was inserted or duplicated before it)" % (o + 1, grant, i))
    return g, data, named

def check_appended(lines, start):
    fails = 0
    for i, x in enumerate(lines):
        s = text(x)
        if i >= start:
            bad = "ledger line %d is not a well-formed FAIL, GRANT-USED or REOPEN-REFUSED line" % (i + 1)
            if s is None:
                out(1, bad)
            m = GRANT_RE.match(s)
            if m:
                if int(m.group(2)) != fails:
                    out(1, "ledger line %d says count=%s, but the FAIL lines before it give %d" % (i + 1, m.group(2), fails))
            elif not FAIL_RE.match(s) and not REFUSED_RE.match(s):
                out(1, bad)
            elif s.startswith("REOPEN-REFUSED grant=") and not REFGRANT_RE.match(s):
                out(1, bad)
        if s is not None and FAIL_RE.match(s):
            fails += 1

def append_ledger(entries):
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    with open(ledger, "ab") as f:
        for e in entries:
            f.write(e.encode("utf-8") + b"\n")

def clean(msg):
    return re.sub(r"[\x00-\x1f\x7f]", "?", msg)[:300]

def full_check():
    anc = anchors()
    lines = read_ledger()
    t, n = check_anchors(lines, anc)
    if lines is not None:
        check_appended(lines, n)
    check_grants(lines if lines is not None else [], anc)
    return anc, lines, t, n

if mode == "check":
    anc, lines, t, n = full_check()
    if lines is None:
        out(0, "no gate commit yet and no ledger")
    if t is None:
        out(0, "no gate commit yet; the ledger's %d line(s) are well formed" % len(lines))
    if t in ADOPTED:
        out(0, "the ledger matches %s (lines=%d) and its %d later line(s) are well formed" % (anchor_name(t), n, len(lines) - n))
    out(0, "the ledger matches the %s trailer of %s (lines=%d) and its %d later line(s) are well formed" % (key, t, n, len(lines) - n))
elif mode == "adopt" and len(args) == 1:
    # read-only: prints the record that adopt_legacy_tags writes (the shell checks the record and the untrusted-root
    # marker first, asks the person, then writes it with noclobber). args[0] is the kit version file's text.
    import datetime
    anc, legacy = anchors(adopting=True)
    if not legacy:
        out(1, "there is no onboard-v<n> tag to adopt: adoption is only for a repo whose onboard-v<n> tags were made "
               "before the kit kept the gate ledger, and nothing was written")
    hd = git("rev-parse", "-q", "--verify", "HEAD^{commit}")
    if hd.returncode != 0:
        out(1, "HEAD names no commit, so the legacy tags cannot be checked; nothing was written")
    head = hd.stdout.decode().strip()
    for t, c in legacy:
        if git("merge-base", "--is-ancestor", c, head).returncode != 0:
            out(1, "the tag %s (%s) is not reachable from HEAD (%s): adopt from the branch that holds every onboard "
                   "gate commit; nothing was written" % (t, c[:12], head[:12]))
    lines = read_ledger()
    if lines is None:
        out(1, "the ledger %s is missing, so there is nothing to pin: if this repo never had one, the person (never "
               "an agent) creates it as an empty file first; if another checkout of this repo kept one, the person "
               "copies gate-ledger (and reopen-grant) from there. Nothing was written" % ledger)
    SIM = "nothing was written: the ledger cannot be adopted: "
    t, n = check_anchors(lines, anc)
    check_appended(lines, n)
    check_grants(lines, anc)
    pinned = [(t, len(lines), prefix_sha(lines, len(lines))) for t, _ in legacy]
    check_anchors(lines, anc + pinned)
    check_grants(lines, anc + pinned)
    SIM = None
    m = re.fullmatch(r"[^+\s]*\+([0-9a-f]{7,40}(?:-dirty)?)\s*", args[0])
    kit = m.group(1) if m else "unknown"
    at = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()
    body = [ADOPT_HEAD, "adoptedAt=" + at, "kitSha=" + kit, "head=" + head, "ledgerLines=%d" % len(lines),
            "ledgerSha256=" + prefix_sha(lines, len(lines))] + ["tag=%s %s" % x for x in legacy]
    out(0, "\n".join(body))
elif mode == "trailer":
    anc, lines, t, n = full_check()
    if lines is None:
        os.makedirs(os.path.dirname(ledger), exist_ok=True)
        with open(ledger, "xb"):
            pass
        lines = []
    g, data, named = check_grants(lines, anc)
    if g:
        nxt = max(tag_no(anc) + [0]) + 1
        stale = ["REOPEN-REFUSED grant=%s %sin the grant file when the scan for gate commit onboard-v%d wrote its trailer; "
                 "void unless that gate commit lands with this line in its trailer" % (sha(x), STALE_TEXT, nxt)
                 for x in g[len(named):]]
    else:
        stale, nxt = [], max(tag_no(anc) + [0]) + 1
    # check the ledger as the gate commit would leave it, before writing anything: the new stale lines added and a
    # gate commit pinning every line. A void stale line already at the end of the ledger joins the pinned run, so
    # one that names no grant line (or a grant another line names) would make every later check refuse.
    new = lines + [x.encode("utf-8") for x in stale]
    SIM = ("nothing was written: with the trailer of gate commit onboard-v%d the ledger would read "
           "as refused: " % nxt)
    check_grants(new, anc + [("onboard-v%d" % nxt, len(new), prefix_sha(new, len(new)))])
    SIM = None
    if stale:
        append_ledger(stale)
        lines = read_ledger()
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
    if mn != len(lines) or prefix_sha(lines, mn) != mh:
        # the trailer pins the whole ledger: a line appended after the scan (a used grant, a FAIL) needs a rescan,
        # so a stale line the scan wrote can never be pinned after its grant was used
        out(1, "the commit message's %s trailer (lines=%d) no longer matches the ledger (%d lines); run the whole chain again (it rescans)" % (key, mn, len(lines)))
    out(0, "the commit message's %s trailer matches the ledger" % key)
elif mode == "reopen" and len(args) == 2:
    import datetime, time
    phase, max_age = args[0], int(args[1])
    anc, lines, t, n = full_check()
    lines = lines if lines is not None else []
    g, data, named = check_grants(lines, anc)
    cmd = ("To grant a reopen, the person appends one new line in their own terminal (append with >>, never >; "
           "an overwrite is refused): printf '%%s\\n' \"grant $(date +%%Y-%%m-%%dT%%H:%%M:%%S%%z) phase=%s "
           "reason=\\\"<why>\\\" by=<your-name>\" >> '%s'" % (phase, grant))
    def refused(reason, name=None, how=cmd):
        append_ledger(["REOPEN-REFUSED " + ("grant=%s " % name if name else "") + clean(reason)])
        out(1, "%s. One REOPEN-REFUSED line was written to the ledger%s; the retry count is kept. %s"
            % (reason, " (it names this grant line, so it can never be used)" if name else "", how))
    if g is None:
        refused("there is no grant file (%s)" % grant)
    if not g:
        refused("the grant file %s has no grant line" % grant)
    last = len(g)
    if len(named) >= last:
        i, h, k = named[last - 1]
        if k == "GRANT-USED":
            refused("the last grant line (grant line %d) was already used (ledger line %d); each grant is used once" % (last, i))
        refused("the last grant line (grant line %d) was already refused or went stale at a landed gate commit (ledger line %d)" % (last, i))
    if not data.endswith(b"\n"):
        refused("the last grant line (grant line %d) has no newline, so it was not written whole by the printf command" % last,
                how="The person first ends it with: printf '\\n' >> '%s'; then appends a new grant. %s" % (grant, cmd))
    if last - len(named) > 1:
        refused("grant line %d is an unused grant line before the last one; only the last grant line may be used, and each "
                "earlier line must be used or refused first (this refusal names grant line %d)" % (len(named) + 1, len(named) + 1),
                name=sha(g[len(named)]))
    cand = g[-1]
    h = sha(cand)
    if b"\r" in cand:
        refused("grant line %d holds a carriage return (a CRLF line ending, as some editors write); the kit refuses it "
                "rather than strip it" % last, name=h)
    s = text(cand)
    m = GLINE_RE.match(s) if s is not None else None
    dt = None
    if m:
        try:
            dt = datetime.datetime.fromisoformat("%s%s:%s" % (m.group(1), m.group(2), m.group(3)))
        except ValueError:
            dt = None
    if dt is None:
        refused("grant line %d is not a well-formed grant line (it must read exactly: grant <YYYY-MM-DDTHH:MM:SS+HH:MM> "
                "phase=<phase> reason=\"<text>\" by=<name>)" % last, name=h)
    if m.group(4) != phase:
        refused("grant line %d grants phase=%s, not %s" % (last, m.group(4), phase), name=h)
    ts, now = dt.timestamp(), time.time()
    if ts > now + FUTURE_SKEW:
        refused("grant line %d is dated in the future (%s, more than %ds ahead of this clock)" % (last, m.group(1), FUTURE_SKEW), name=h)
    if now - ts > max_age:
        refused("grant line %d is %ds old, older than gate-rules grant_max_age_seconds (%d)" % (last, int(now - ts), max_age), name=h)
    if tag_no(anc):
        gt = anc[-1][0]
        r = git("log", "-1", "--format=%ct", gt + "^{commit}")
        try:
            gts = int(r.stdout.decode().strip())
        except ValueError:
            out(1, "git could not read the time of the gate commit %s" % gt)
        if ts < gts:
            refused("grant line %d (%s) is older than the last gate commit %s; a grant must be newer than the last gate" % (last, m.group(1), gt), name=h)
    for blob in (cand + b"\n", data):
        r = subprocess.run(["git", "hash-object", "--stdin"], input=blob, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        oid = r.stdout.decode().strip()
        if r.returncode != 0 or not oid:
            out(1, "git could not hash the grant line")
        r = git("log", "--all", "-1", "--format=%h", "--find-object=" + oid)
        if r.returncode != 0 or r.stdout.strip():
            refused("grant line %d is in git history (commit %s); a committed grant is not a fresh grant" % (last, r.stdout.decode().strip() or "?"), name=h)
    fails = sum(1 for x in lines if text(x) is not None and FAIL_RE.match(text(x)))
    append_ledger(["GRANT-USED %s count=%d" % (h, fails)])
    out(0, "grant line %d (%s, by=%s) is the last line, unused, newer than the last gate, %ds old (at most %d) and not in git history; "
        "GRANT-USED was written with count=%d" % (last, m.group(1), m.group(6), int(now - ts), max_age, fails))
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
# onb_tag_n prints the highest n of the onboard-v<n> tags (n is 0 or has no leading zero), or nothing.
# onb_tag_zero <check> refuses as <check> when an onboard-v<n> tag has a leading zero (round 18): $(( )) reads
# onboard-v011 as octal 9 and stops on 08, while the ledger check reads 11 (the same text as LZ_TEXT there).
onb_tag_n() { git tag -l 'onboard-v*' | grep -E '^onboard-v(0|[1-9][0-9]*)$' | sed 's/^onboard-v//' | sort -n | tail -n 1; }
onb_tag_zero() {
  oz_t="$(git tag -l 'onboard-v*' | grep -E '^onboard-v0[0-9]+$' | head -n 1)"
  [ -z "$oz_t" ] || refuse "$1" "the tag $oz_t has a leading zero; onboard-v<n> tags are numbered without one, because the kit reads the number as decimal in python and as octal in the shell. Stop and show the user: a person (never an agent) replaces that tag"
}
# onb_tag_check <check>: the newest onboard-v<n> tag is on this branch and holds the current onboard approval
# (state.json approval at the tag equals HEAD's). Sets gc_tag; refuses as <check> otherwise.
onb_tag_check() {
  onb_tag_zero "$1"
  gc_n="$(onb_tag_n)"
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
# Greenfield record (round 18): gf_gate runs greenfield_record_ok first; REFUSED stops here, OK and NONE go on.
# TODO(gap 9 / N2A, 5A): the content-rule fallback (a brownfield repo where onboard was skipped and no record was
#   written) is not built; until then a repo with no record passes.
PA_AUDIT="docs/agents-v0/discovery/baseline-audit.txt"
# gf_gate <check> <what stops>: run greenfield_record_ok (round 18). OK (0, a valid greenfield record) and NONE
# (4, no record: the content rule decides) return and the caller goes on as before; REFUSED (1: a changed record,
# the untrusted-root marker, or the ledger) refuses as <check>; anything else is an error (exit 2). The ledger
# check runs first as <check>, so a changed ledger reads as before ("REFUSED <check>: ledger changed, ...").
gf_gate() {
  ledger_guard "$1"
  gg_rc=0; gg_out="$(greenfield_record_ok 2>&1)" || gg_rc=$?
  case "$gg_rc" in
    0|4) return 0 ;;
    1) refuse "$1" "$2: the greenfield record check refused (gate-checks.sh greenfield_record_ok: ${gg_out#REFUSED greenfield_record_ok: }). Stop and show the user this output" ;;
    *) die "$1: the greenfield record check could not run: ${gg_out:-no output}" ;;
  esac
}
prereq_approved() {
  need_phase prereq_approved "${1:-}"
  pa_phases="$(rule prereq_approved_phases)" || exit 2
  case " $pa_phases " in
    *" $1 "*) ;;
    *) ok prereq_approved "$1 is not in gate-rules prereq_approved_phases ($pa_phases), so it needs no onboard approval" ;;
  esac
  to_root
  pa_need="$1 needs onboard approved and committed first"
  gf_gate prereq_approved "$1 cannot start"
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
  pa_n="$(onb_tag_n)"
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
  gf_gate no_restart_without_reopen "onboard changes no state"
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
  onb_tag_zero commit_chain
  cc_n="$(onb_tag_n)"
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
  # N3A: the ledger check runs first. The trailer (and the stale marks of unnamed grant lines) is written only
  # after the path and scanner checks pass, and goes into the message before the scan reads the message and the
  # record takes its hash (so commit_msg_ok compares the message with the trailer in it). A stale mark that no
  # landed gate commit pins (a refused scan, or no commit) is void, so it never uses up a grant.
  ss_rc=0; ss_led="$(ledger_py check)" || ss_rc=$?
  [ "$ss_rc" = 0 ] || refuse staged_secret_scan "ledger changed, ask the user (${ss_led:-the ledger check could not run}); no commit message was written and the commit is refused"
  ss_rc=0
  ss_bad="$(staged_path_check "$ss_allowed")" || ss_rc=$?
  case "$ss_rc" in
    0) ;;
    1) refuse staged_secret_scan "the index holds paths outside gate-rules onboard_commit_paths ($ss_allowed) or lock files: $ss_bad. Nothing was unstaged; unstage them yourself (git restore --staged -- <path>) or ask the user" ;;
    3) refuse staged_secret_scan "nothing is staged; run the add of the commit chain first (gate-checks.sh commit_chain)" ;;
    *) refuse staged_secret_scan "git could not read the index" ;;
  esac
  [ -f .agents-v0/scripts/secret_scan.py ] || refuse staged_secret_scan ".agents-v0/scripts/secret_scan.py is missing; reinstall the kit (install.sh --update)"
  ss_rc=0; ss_trailer="$(ledger_py trailer)" || ss_rc=$?
  [ "$ss_rc" = 0 ] || refuse staged_secret_scan "ledger changed, ask the user (${ss_trailer:-the ledger check could not run}); no commit message was written and the commit is refused"
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
# 4A, N5A, 1A (1A-gap B): the last line of the grant file (a regular file) is the grant; it parses strictly (no CR,
# no control characters), names <phase>, is not in the future, is newer than the last onboard gate commit and was
# not in the grant file at it (the gate commit pins a stale mark of every unnamed line), is at most grant_max_age_seconds
# old, is unused (no ledger line names it, not in git history) and every earlier grant line is named in order.
# Success appends GRANT-USED <sha> count=<FAIL lines>; a refusal after the ledger check appends one REOPEN-REFUSED
# line and prints the person's grant command (>>, never >). "The run is attended" is not visible here: the harness
# catches a GRANT-USED line written in an unattended turn (ledger_turn_ok, N84). Only onboard is wired.
reopen_grant_ok() {
  need_phase reopen_grant_ok "${1:-}"
  ledger_guard reopen_grant_ok
  age="$(rule grant_max_age_seconds)"
  [ "$1" = onboard ] || not_wired reopen_grant_ok "the grant for $1 must be newer than the last $1 gate and at most ${age}s old, unused and attended" "the fix turn of phase $1"
  git rev-parse --git-common-dir >/dev/null 2>&1 || refuse reopen_grant_ok "not a git repository, so there is no grant file or gate ledger"
  rg_rc=0; rg_out="$(ledger_py reopen "$1" "$age")" || rg_rc=$?
  case "$rg_rc" in
    0) ok reopen_grant_ok "$rg_out" ;;
    1) refuse reopen_grant_ok "$rg_out" ;;
    *) die "reopen_grant_ok: ${rg_out:-the grant check could not run}" ;;
  esac
}
# 5A, N2A (design rev 6 "Greenfield record"; E31): .agents-v0/greenfield-record.json is valid only when the
# repo's only root commit added it, nothing changed it since (HEAD, the index and the work tree hold the same
# bytes, mode 100644) and it reads exactly {"kind": "greenfield", "bootstrapAt": "<YYYY-MM-DDTHH:MM:SS+HH:MM>",
# "kitSha": "<7-40 hex>[-dirty]" or "unknown"} (no hash field: the commit that holds it is the proof).
#   OK       exit 0  a valid record: greenfield, onboard stops and suggests /v0-intake
#   NONE     exit 4  no record anywhere, or two or more root commits (E31): the content rule decides
#   REFUSED  exit 1  any other record: "record changed, ask the user"; or the untrusted-root marker exists
#                    (<git common dir>/agents-v0/untrusted-root, written by bootstrap-greenfield.sh)
# Root commits are counted over every ref (git rev-list --all), so an orphan branch's root is a second root.
# prereq_approved and no_restart_without_reopen (every onboard state change) call it through gf_gate.
# The ledger check runs first (ledger_guard), so the root commit's trailer must be lines=0 and the empty hash.
GF_RECORD=".agents-v0/greenfield-record.json"
greenfield_record_ok() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || none greenfield_record_ok "not a git work tree, so there is no greenfield record"
  to_root
  gf_mark="$(git_common_dir)/$UNTRUSTED_REL"
  if [ -e "$gf_mark" ] || [ -L "$gf_mark" ]; then
    gf_mroot="$(sed -n 's/^rootCommit=//p' "$gf_mark" 2>/dev/null | head -n 1 | grep -E '^[0-9a-f]{7,64}$' || :)"
    refuse greenfield_record_ok "the untrusted-root marker $gf_mark exists: bootstrap-greenfield.sh marked ${gf_mroot:+the root commit $gf_mroot of }this repo as not trusted, so the root commit is not trusted and no greenfield record counts here. Stop and show the user: do not onboard or push this repo. Follow bootstrap's recovery steps: move this repo aside, create a new empty repo (git init), then rerun bootstrap"
  fi
  ledger_guard greenfield_record_ok
  gf_rc=0; gf_out="$(python3 - "$GF_RECORD" <<'PYGF'
import datetime, json, os, re, subprocess, sys
rec = sys.argv[1]
def git(*a):
    return subprocess.run(["git"] + list(a), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
def done(code, msg):
    print(msg)
    sys.exit(code)
def changed(why):
    done(1, "record changed, ask the user (%s %s)" % (rec, why))
born = git("rev-parse", "-q", "--verify", "HEAD^{commit}").returncode == 0
wt = os.path.lexists(rec)
adds = []
if born:
    r = git("log", "--no-renames", "--diff-filter=A", "--format=%H", "HEAD", "--", rec)
    if r.returncode != 0:
        done(1, "git could not read the history of %s" % rec)
    adds = r.stdout.decode().split()
if not adds:
    if wt or (born and git("cat-file", "-e", "HEAD:" + rec).returncode == 0):
        changed("is not in any commit of HEAD's history: a copy that no root commit added")
    if git("ls-files", "--error-unmatch", "--", rec).returncode == 0:
        changed("is staged but not committed")
    done(4, "no greenfield record (%s): the content rule decides" % rec)
# every root commit in the repo, not only HEAD's (round 18, Iruka T3): an orphan branch in a repo that already
# has commits makes a second root, and a record there must not read as greenfield
r = git("rev-list", "--max-parents=0", "--all", "HEAD")
roots = r.stdout.decode().split()
if r.returncode != 0 or not roots:
    done(1, "git could not list the root commits")
if len(roots) != 1:
    done(4, "the repo has %d root commits (git rev-list --all: unrelated history was merged or another branch has its own root, E31), so the greenfield record is not valid: the content rule decides" % len(roots))
root = roots[0]
if adds[-1] != root:
    changed("was added by commit %s, not by the root commit %s" % (adds[-1][:12], root[:12]))
if len(adds) != 1:
    changed("was removed and added again after the root commit %s" % root[:12])
def entry(rev):
    r = git("ls-tree", rev, "--", rec)
    f = r.stdout.decode().split()
    return (f[0], f[2]) if r.returncode == 0 and len(f) >= 3 else None
want = entry(root)
if want is None or want[0] != "100644":
    changed("is not a regular file (mode 100644) in the root commit %s" % root[:12])
if entry("HEAD") != want:
    changed("is missing at HEAD or differs from the root commit %s" % root[:12])
r = git("ls-files", "-s", "--", rec)
f = r.stdout.decode().split()
if r.returncode != 0 or len(f) < 2 or (f[0], f[1]) != want or len(r.stdout.decode().strip().split("\n")) != 1:
    changed("in the index differs from the root commit %s" % root[:12])
if not wt or os.path.islink(rec) or not os.path.isfile(rec):
    changed("is missing in the work tree or is not a regular file")
r = subprocess.run(["git", "hash-object", "--no-filters", "--", rec], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if r.returncode != 0 or r.stdout.decode().strip() != want[1]:
    changed("in the work tree differs from the root commit %s" % root[:12])
try:
    d = json.loads(git("cat-file", "blob", want[1]).stdout.decode("utf-8"))
except (UnicodeDecodeError, ValueError):
    changed("is not valid JSON")
if not isinstance(d, dict) or sorted(d) != ["bootstrapAt", "kind", "kitSha"]:
    changed("must hold exactly the keys kind, bootstrapAt and kitSha")
if d["kind"] != "greenfield":
    changed("kind is not \"greenfield\"")
ok_at = isinstance(d["bootstrapAt"], str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}", d["bootstrapAt"])
if ok_at:
    try:
        datetime.datetime.fromisoformat(d["bootstrapAt"])
    except ValueError:
        ok_at = None
if not ok_at:
    changed("bootstrapAt is not a time like 2026-11-02T08:00:00+08:00")
if not (isinstance(d["kitSha"], str) and re.fullmatch(r"unknown|[0-9a-f]{7,40}(-dirty)?", d["kitSha"])):
    changed("kitSha is not a kit commit (7-40 hex, optional -dirty) or unknown")
done(0, "greenfield: %s was added by the only root commit %s and is unchanged (bootstrapAt %s, kit %s); onboard stops, writes nothing and suggests /v0-intake" % (rec, root[:12], d["bootstrapAt"], d["kitSha"]))
PYGF
)" || gf_rc=$?
  case "$gf_rc" in
    0) ok greenfield_record_ok "$gf_out" ;;
    4) none greenfield_record_ok "$gf_out" ;;
    1) refuse greenfield_record_ok "$gf_out" ;;
    *) die "greenfield_record_ok: ${gf_out:-the record check could not run}" ;;
  esac
}
# greenfield_trailer (for bootstrap-greenfield.sh, N9A): before the greenfield root commit, create the empty ledger
# and print the trailer that commit's message must end with: Agents-V0-Ledger: lines=0 sha256=<empty hash>. Refuses
# (exit 1) unless HEAD is unborn, no ref holds a commit, no onboard-v<n> tag exists and the ledger is absent or empty.
greenfield_trailer() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse greenfield_trailer "not a git work tree"
  git rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1 && refuse greenfield_trailer "HEAD already has a commit; the greenfield record belongs in the root commit only"
  # round 18 (Iruka T3): an orphan branch has an unborn HEAD too; any commit on any ref means this is not a new repo
  [ -z "$(git rev-list -n 1 --all 2>/dev/null)" ] || refuse greenfield_trailer "the repo already has commits (git rev-list --all), for example on another branch; the greenfield root commit belongs in a new, empty repo only"
  [ -z "$(git tag -l 'onboard-v*')" ] || refuse greenfield_trailer "an onboard-v<n> tag exists; this is not a new repo"
  gt_l="$(ledger_path)" || exit 2
  if [ -e "$gt_l" ] || [ -L "$gt_l" ]; then
    { [ -f "$gt_l" ] && [ ! -L "$gt_l" ] && [ ! -s "$gt_l" ]; } || refuse greenfield_trailer "the ledger $gt_l is not an empty regular file; a new repo starts with an empty ledger"
  else
    mkdir -p "$(dirname "$gt_l")" && : > "$gt_l" || refuse greenfield_trailer "could not create the empty ledger $gt_l"
  fi
  printf '%s: lines=0 sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n' "$LEDGER_TRAILER"
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

# adopt_legacy_tags (round 19, legacy option A; the person only, once per repo, in their own terminal; the hook
# denies it to the agent). A repo onboarded before the kit kept the gate ledger has onboard-v<n> tags with no
# Agents-V0-Ledger trailer, and every ledger check refuses them. This writes the record ADOPT_REL in the git common
# dir (shared by every worktree; not in the repo, so a commit or tag cannot make one) naming each tag and its commit,
# when, the kit version and the ledger lines it pins. After that, the adopted tags count as anchors of that ledger;
# any other trailer-less tag still refuses. Writes nothing unless the person types adopt.
adopt_help() {
  cat <<'ADOPTHELP'
usage: sh .agents-v0/scripts/gate-checks.sh adopt_legacy_tags [--help]

The person runs this once per repo, in their own terminal; an agent never runs it (the hook denies it).

A repo onboarded before the kit kept the gate ledger has onboard-v<n> tags without an Agents-V0-Ledger trailer,
and every ledger check (ledger_ok, gate_committed, ...) refuses them. This adopts those tags: it writes the record
<git common dir>/agents-v0/legacy-adoption (sh .agents-v0/scripts/gate-checks.sh paths prints the common dir) with
the tags and their commits, the time, the kit version (.agents-kit-version), HEAD, and the number and sha256 of the
gate ledger lines it pins. The ledger checks then count each adopted tag as an anchor of those lines. A tag made
later must carry the trailer (the gate commit chain from commit_chain), and a moved adopted tag refuses.

It refuses, and writes nothing, when: the record already exists (adoption runs once; a second run names it); the
untrusted-root marker exists; there is no onboard-v<n> tag; any onboard-v<n> tag carries the trailer (the repo is
not a legacy repo); a tag has a leading zero, does not name a commit, or is not reachable from HEAD; the ledger
is missing (create it as an empty file first if this repo never had one, or copy it from the checkout that kept
it), is not a regular file, lacks its final newline, holds a line that is not a FAIL, GRANT-USED or
REOPEN-REFUSED line, or names grants that do not match the grant file. It shows the record and writes it only
when you type adopt and press Enter. Review the ledger first: an edit made before the adoption cannot be detected
afterwards. A fresh clone has no record; copy legacy-adoption, gate-ledger and reopen-grant from the original
checkout's agents-v0/ to the clone's (never rerun the adoption there).
ADOPTHELP
}
adopt_legacy_tags() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse adopt_legacy_tags "not a git work tree, so there are no tags to adopt"
  to_root
  al_gcd="$(git_common_dir)" || exit 2
  al_rec="$al_gcd/$ADOPT_REL"
  if [ -e "$al_rec" ] || [ -L "$al_rec" ]; then
    al_at="$(sed -n 's/^adoptedAt=//p' "$al_rec" 2>/dev/null | head -n 1 | grep -E '^[0-9T:+-]{10,30}$' || :)"
    refuse adopt_legacy_tags "the legacy adoption record $al_rec already exists${al_at:+ (adopted at $al_at)}: adoption runs once per repo, so nothing was written. If the ledger check refuses, stop and show the user; nobody edits or replaces that record"
  fi
  al_mark="$al_gcd/$UNTRUSTED_REL"
  if [ -e "$al_mark" ] || [ -L "$al_mark" ]; then
    refuse adopt_legacy_tags "the untrusted-root marker $al_mark exists: bootstrap-greenfield.sh marked this repo as not trusted, so nothing in it is adopted and nothing was written. Stop and show the user"
  fi
  al_kit=""; [ -f .agents-kit-version ] && [ ! -L .agents-kit-version ] && al_kit="$(head -n 1 .agents-kit-version 2>/dev/null || :)"
  al_rc=0; al_body="$(ledger_py adopt "$al_kit")" || al_rc=$?
  case "$al_rc" in
    0) ;;
    1) refuse adopt_legacy_tags "$al_body" ;;
    *) die "adopt_legacy_tags: ${al_body:-the ledger check could not run}" ;;
  esac
  printf 'adopt_legacy_tags: this writes %s, once, with:
' "$al_rec"
  printf '%s
' "$al_body" | sed 's/^/  /'
  printf 'Type adopt and press Enter to write it (anything else writes nothing): '
  al_ans=""; IFS= read -r al_ans || :
  printf '
'
  [ "$al_ans" = adopt ] || refuse adopt_legacy_tags "not confirmed (the answer was not adopt), so nothing was written"
  mkdir -p "$al_gcd/agents-v0" || die "adopt_legacy_tags: cannot create $al_gcd/agents-v0"
  # noclobber: the shell creates the record with O_EXCL, so a record that appeared meanwhile is never overwritten
  if ! (set -C; printf '%s
' "$al_body" > "$al_rec") 2>/dev/null; then
    refuse adopt_legacy_tags "could not create $al_rec (it appeared meanwhile, or the folder is not writable); nothing was overwritten. Stop and show the user"
  fi
  al_rc=0; al_chk="$(ledger_py check)" || al_rc=$?
  [ "$al_rc" = 0 ] || refuse adopt_legacy_tags "wrote $al_rec, but the ledger check still refuses ($al_chk). Stop and show the user"
  ok adopt_legacy_tags "wrote $al_rec; $al_chk"
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
  greenfield_trailer)
    [ "$#" = 0 ] || usage
    greenfield_trailer ;;
  adopt_legacy_tags)
    if [ "$#" = 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then adopt_help; exit 0; fi
    [ "$#" = 0 ] || { adopt_help >&2; exit 2; }
    adopt_legacy_tags ;;
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
