#!/bin/sh
# test-bootstrap-greenfield.sh — bootstrap-greenfield.sh makes the greenfield root commit and refuses
# everything that is not a new, empty repo of its own (design rev 6 "Greenfield record": 5A, N2A, N9A;
# test cases H7, N65, N66, N67, N78, N79). The root commit carries the lines=0 ledger trailer from
# gate-checks.sh greenfield_trailer, and greenfield_record_ok passes on it. Run by validate-kit.sh.
# Needs git, python3. Every refusal must exit non-zero, say why, and leave the folder (and a parent repo)
# byte-identical.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0
pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (wanted '$3', got '$2')"; fi; }
expect_out() { if grep -Eq -- "$2" "$tmp/out.txt"; then pass "$1"; else fail "$1 (output lacks: $2)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi; }
# A fixed identity and no signing for every git run (the bootstrap commit included); git discovery stops
# at $tmp, so a repo around the temp folder can never act as a parent repo (N67/N78 stay "no repo").
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
tmp="$(cd "$tmp" && pwd -P)"
export GIT_CEILING_DIRECTORIES="$tmp"
BOOT="$KIT/scripts/bootstrap-greenfield.sh"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
TRAILER="Agents-V0-Ledger: lines=0 sha256=$EMPTY_SHA"

boot() { sh "$BOOT" "$@" >"$tmp/out.txt" 2>&1; }
# snap <dir>: every path and the checksum of every file under <dir> (.git included).
snap() { (cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort); }
# refused <case> <dir> [args...]: bootstrap exits non-zero and <dir> is byte-identical afterwards.
refused() { r_case="$1"; r_dir="$2"; shift 2
  snap "$r_dir" >"$tmp/before.snap"
  if boot "$@" "$r_dir"; then fail "$r_case: refused (expected non-zero exit)"; sed 's/^/    /' "$tmp/out.txt" >&2
  else pass "$r_case: refused"; fi
  snap "$r_dir" >"$tmp/after.snap"
  if cmp -s "$tmp/before.snap" "$tmp/after.snap"; then pass "$r_case: the folder is byte-identical"
  else fail "$r_case: the folder changed"; diff "$tmp/before.snap" "$tmp/after.snap" | head -n 8 | sed 's/^/    /' >&2; fi
}
newrepo() { mkdir -p "$1"; git -C "$1" init -q -b main; }

# ---- H7: the greenfield root commit ---------------------------------------------------------------
t="$tmp/green"; newrepo "$t"
if boot "$t"; then pass "H7: bootstrap in an empty git init folder"; else fail "H7: bootstrap in an empty git init folder (exit non-zero)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
cp "$tmp/out.txt" "$tmp/green.out"
check "H7: exactly one commit" "$(git -C "$t" rev-list --count HEAD 2>/dev/null || echo none)" 1
check "H7: the commit is the only root" "$(git -C "$t" rev-list --max-parents=0 HEAD 2>/dev/null | tr '\n' ' ')" "$(git -C "$t" rev-parse HEAD 2>/dev/null) "
check "H7: the trailer is the last line of the message" "$(git -C "$t" log -1 --format=%B 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 1)" "$TRAILER"
check "H7: exactly one Agents-V0-Ledger line" "$(git -C "$t" log -1 --format=%B 2>/dev/null | grep -c '^Agents-V0-Ledger:' || true)" 1
check "H7: the trailer is a git trailer" "$(git -C "$t" log -1 --format='%(trailers:key=Agents-V0-Ledger,valueonly)' 2>/dev/null | sed '/^$/d')" "lines=0 sha256=$EMPTY_SHA"
check "H7: the record is in the root commit, mode 100644" "$(git -C "$t" ls-tree HEAD -- .agents-v0/greenfield-record.json 2>/dev/null | cut -c1-6)" 100644
kit_sha="$(git -C "$KIT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
[ "$kit_sha" = unknown ] || [ -z "$(git -C "$KIT" status --porcelain 2>/dev/null | head -n 1)" ] || kit_sha="$kit_sha-dirty"
git -C "$t" show HEAD:.agents-v0/greenfield-record.json >"$tmp/rec.json" 2>/dev/null || : >"$tmp/rec.json"
check "H7: the record has exactly kind, bootstrapAt and kitSha (greenfield, the kit commit)" "$(python3 - "$tmp/rec.json" <<'PY'
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except ValueError:
    print("bad json"); sys.exit(0)
at = d.get("bootstrapAt", "")
ok = isinstance(at, str) and re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$", at)
print("%s %s %s %s" % (",".join(sorted(d)), d.get("kind"), d.get("kitSha"), "at-ok" if ok else "at-bad:%s" % at))
PY
)" "bootstrapAt,kind,kitSha greenfield $kit_sha at-ok"
(cd "$t" && sh .agents-v0/scripts/gate-checks.sh greenfield_record_ok) >"$tmp/gf.txt" 2>&1 && gf=0 || gf=$?
check "H7: greenfield_record_ok passes (exit 0)" "$gf" 0
(cd "$t" && sh .agents-v0/scripts/gate-checks.sh ledger_ok) >"$tmp/lo.txt" 2>&1 && lo=0 || lo=$?
check "H7: ledger_ok passes under the root anchor" "$lo" 0
check "H7: the gate ledger exists and is empty" "$(l="$(git -C "$t" rev-parse --git-common-dir 2>/dev/null)"; case "$l" in /*) ;; *) l="$t/$l" ;; esac; [ -f "$l/agents-v0/gate-ledger" ] && wc -c <"$l/agents-v0/gate-ledger" | tr -d ' ' || echo missing)" 0
check "H7: everything bootstrap wrote is committed (clean work tree)" "$(git -C "$t" status --porcelain 2>/dev/null | head -n 3 | tr '\n' ' ')" ""
cp "$tmp/green.out" "$tmp/out.txt"
# install.sh's own Greenfield/Brownfield pointer line stays; the removed line is bootstrap's step "run ./scripts/audit-brownfield-baseline.sh <target>".
if grep -q 'run \./scripts/audit-brownfield-baseline\.sh' "$tmp/out.txt"; then fail "H7: the brownfield audit hint (:445) is not printed"; else pass "H7: the brownfield audit hint (:445) is not printed"; fi
expect_out "H7: bootstrap reports the root commit and the record check" 'greenfield_record_ok'
# A second run on the bootstrapped repo is refused (N66: it has a commit now) and changes nothing.
refused "H7: a rerun" "$t"
expect_out "H7: a rerun says the repo already has a commit" 'already has a commit'

# bootstrap keeps its own work files (path lists, message) in .git/agents-v0-bootstrap/, overwritten by the
# next run and never deleted; nothing of its own is left loose in .git (Jiraiya review of cb70d10f).
check "H7: the work files are kept in .git/agents-v0-bootstrap/" "$(ls "$t/.git/agents-v0-bootstrap" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')" "commit-msg.txt commit-paths kit-paths "
check "H7: no work file loose in .git" "$(ls "$t/.git" | grep -c '^agents-v0-greenfield' || true)" 0

# ---- H7 MUST-FIX (Jiraiya review of cb70d10f): a pre-commit hook that stages a file the scan never read ----
# The hook writes sneaky.txt holding an AWS-style key id and git adds it. The key is fake and built here at
# run time, so this file never holds one. bootstrap must compare the committed tree with the scanned one and
# refuse loudly: non-zero, REFUSED, never a success line, and the key is never printed.
fake_key="AKIA""FAKE0TEST0KEY000"
t="$tmp/hook-sneak"; newrepo "$t"; mkdir -p "$tmp/hooks-sneak"
printf '#!/bin/sh\nprintf "aws_access_key_id = %%s\\n" "%s" > sneaky.txt\ngit add sneaky.txt\n' "$fake_key" > "$tmp/hooks-sneak/pre-commit"
chmod +x "$tmp/hooks-sneak/pre-commit"
git -C "$t" config core.hooksPath "$tmp/hooks-sneak"
if boot "$t"; then fail "H7 hook: a pre-commit hook that stages sneaky.txt: refused (exit 0)"; else pass "H7 hook: a pre-commit hook that stages sneaky.txt: refused"; fi
expect_out "H7 hook: the refusal says REFUSED and that the commit hooks changed the tree" 'REFUSED bootstrap-greenfield: .*commit hooks changed the tree'
expect_out "H7 hook: the refusal names sneaky.txt" 'sneaky\.txt'
expect_out "H7 hook: the refusal says the root commit is not trusted" 'not trusted'
if grep -Eq 'Greenfield bootstrap complete|Greenfield root commit [0-9a-f]|OK greenfield_record_ok' "$tmp/out.txt"; then fail "H7 hook: the output never says success"; sed 's/^/    /' "$tmp/out.txt" >&2; else pass "H7 hook: the output never says success"; fi
if grep -q "$fake_key" "$tmp/out.txt"; then fail "H7 hook: the key is never printed"; else pass "H7 hook: the key is never printed"; fi
# The untrusted-root marker goes in .git/agents-v0/ beside the gate ledger (the folder the hooks protect),
# and writing it leaves the ledger as it was: empty, a regular file.
m="$t/.git/agents-v0/untrusted-root"
[ -f "$m" ] && pass "H7 hook: .git/agents-v0/untrusted-root is written" || fail "H7 hook: .git/agents-v0/untrusted-root is written"
check "H7 hook: the marker names the root commit" "$(sed -n 's/^rootCommit=//p' "$m" 2>/dev/null)" "$(git -C "$t" rev-parse HEAD 2>/dev/null)"
check "H7 hook: no marker under .git/agents-v0-bootstrap/" "$(ls "$t/.git/agents-v0-bootstrap" 2>/dev/null | grep -c untrusted || true)" 0
check "H7 hook: the gate ledger is still an empty regular file" "$([ -f "$t/.git/agents-v0/gate-ledger" ] && [ ! -s "$t/.git/agents-v0/gate-ledger" ] && echo empty)" empty
expect_out "H7 hook: the refusal names the marker" 'marked it in .*\.git/agents-v0/untrusted-root'
check "H7: a successful bootstrap writes no untrusted-root marker" "$([ -e "$tmp/green/.git/agents-v0/untrusted-root" ] && echo present || echo absent)" absent
# The marker cannot be written (Jiraiya review of 13585735): the hook stages sneaky.txt and makes
# .git/agents-v0 read-only after the ledger is there. The refusal must not claim a marker: no "marked it in",
# a plain "NO marker was written", still non-zero and no success line. As root, chmod does not stop a write,
# so the case is skipped with a note.
if [ "$(id -u)" = 0 ]; then
  printf 'skip: the read-only .git/agents-v0 case (running as root, chmod does not stop the write)\n'
else
  t="$tmp/hook-ro"; newrepo "$t"; mkdir -p "$tmp/hooks-ro"
  printf '#!/bin/sh\nprintf "aws_access_key_id = %%s\\n" "%s" > sneaky.txt\ngit add sneaky.txt\nchmod a-w "$(git rev-parse --git-common-dir)/agents-v0"\n' "$fake_key" > "$tmp/hooks-ro/pre-commit"
  chmod +x "$tmp/hooks-ro/pre-commit"
  git -C "$t" config core.hooksPath "$tmp/hooks-ro"
  if boot "$t"; then fail "H7 read-only marker folder: refused (exit 0)"; else pass "H7 read-only marker folder: refused"; fi
  chmod u+w "$t/.git/agents-v0" 2>/dev/null || true
  [ ! -e "$t/.git/agents-v0/untrusted-root" ] && pass "H7 read-only marker folder: no marker file" || fail "H7 read-only marker folder: no marker file"
  if grep -q 'marked it in' "$tmp/out.txt"; then fail "H7 read-only marker folder: never says 'marked it in'"; sed 's/^/    /' "$tmp/out.txt" >&2; else pass "H7 read-only marker folder: never says 'marked it in'"; fi
  expect_out "H7 read-only marker folder: says NO marker was written and not to onboard" 'NO marker was written.*do not onboard this repo'
  expect_out "H7 read-only marker folder: still REFUSED" 'REFUSED bootstrap-greenfield: .*commit hooks changed the tree'
  if grep -Eq 'Greenfield bootstrap complete|Greenfield root commit [0-9a-f]|OK greenfield_record_ok' "$tmp/out.txt"; then fail "H7 read-only marker folder: no success line"; else pass "H7 read-only marker folder: no success line"; fi
fi
# A leftover marker in an unborn repo is refused before anything is written.
d="$tmp/marker"; newrepo "$d"; mkdir -p "$d/.git/agents-v0"; printf 'rootCommit=x\n' > "$d/.git/agents-v0/untrusted-root"
refused "an untrusted-root marker in an unborn repo" "$d"
expect_out "the refusal names the untrusted-root marker" 'untrusted-root'

# ---- H7 with --scaffold-app: the root commit is the kit plus the record; the extracted app stays out -------
# (the app is the first story's to commit; the skeleton's app/backend/mvnw is a secret-scan hit, and the
# allow-list Sensei approves can only be committed after the root commit)
t="$tmp/green-app"; newrepo "$t"
if boot --pack java --scaffold-app "$t"; then pass "H7 --scaffold-app: bootstrap exits 0"; else fail "H7 --scaffold-app: bootstrap exits 0"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
check "H7 --scaffold-app: exactly one commit" "$(git -C "$t" rev-list --count HEAD 2>/dev/null || echo none)" 1
check "H7 --scaffold-app: no app/ path in the root commit" "$(git -C "$t" ls-tree -r --name-only HEAD -- app 2>/dev/null | head -n 1)" ""
check "H7 --scaffold-app: the record is in the root commit" "$(git -C "$t" ls-tree --name-only HEAD -- .agents-v0/greenfield-record.json 2>/dev/null)" .agents-v0/greenfield-record.json
check "H7 --scaffold-app: the app is in the work tree, untracked" "$(git -C "$t" status --porcelain --untracked-files=normal -- app 2>/dev/null)" "?? app/"
check "H7 --scaffold-app: greenfield_record_ok returns 0" "$(cd "$t" && sh .agents-v0/scripts/gate-checks.sh greenfield_record_ok >/dev/null 2>&1; echo $?)" 0
expect_out "H7 --scaffold-app: bootstrap names what it left out of the root commit" 'Not in the root commit.*app/'

# ---- N67, N78: no .git of its own, outside any repo: git init hint, nothing created ------------------
d="$tmp/n67"; mkdir -p "$d"
refused "N67: empty folder, no .git" "$d"
expect_out "N67: the hint says git init" 'git init'
[ ! -e "$d/.git" ] && pass "N67: bootstrap never runs git init" || fail "N67: bootstrap never runs git init (.git was created)"
d="$tmp/n78"; mkdir -p "$d"; printf 'TOKEN=x\n' >"$d/.env"; printf '# app\n' >"$d/README.md"
refused "N78: files (.env, README.md), no .git" "$d"
expect_out "N78: the hint says git init" 'git init'

# ---- N79: inside a parent repo (Sasuke) ----------------------------------------------------------------
p="$tmp/parent"; newrepo "$p"; printf 'x\n' >"$p/a.txt"; git -C "$p" add a.txt; git -C "$p" commit -qm base
printf 'y\n' >"$p/dirty.txt"
parent_state() { printf '%s\n' "$(git -C "$p" rev-parse HEAD)"; cksum <"$p/.git/index"; git -C "$p" status --porcelain --untracked-files=all; }
mkdir -p "$p/sub"
before="$(parent_state)"
refused "N79: empty folder inside a parent repo" "$p/sub"
expect_out "N79: the refusal names the parent repo" "$p"
check "N79: the parent's HEAD, index and status are unchanged" "$(parent_state)" "$before"
[ ! -e "$p/sub/.git" ] && pass "N79: no .git is created" || fail "N79: no .git is created"
mkdir -p "$p/sub2/deep"
before="$(parent_state)"
refused "N79: a nested folder of a parent repo" "$p/sub2/deep"
check "N79: the parent is unchanged (nested folder)" "$(parent_state)" "$before"

# ---- N65: an empty .git plus anything else (E34 allow-list is empty until Iruka's test records it) -----
n=0
for extra in README.md src/main.py .editorconfig emptydir/ .cursor/; do
  n=$((n + 1)); d="$tmp/n65-$n"; newrepo "$d"
  case "$extra" in
    */) mkdir -p "$d/$extra" ;;
    *) mkdir -p "$(dirname "$d/$extra")"; printf 'x\n' >"$d/$extra" ;;
  esac
  refused "N65: .git plus $extra" "$d"
  expect_out "N65: the refusal names ${extra%%/*} and points to brownfield" "${extra%%/*}.*brownfield|brownfield.*${extra%%/*}"
done
d="$tmp/n65-staged"; newrepo "$d"; printf 'x\n' >"$tmp/s.txt"
git -C "$d" update-index --add --cacheinfo "100644,$(git -C "$d" hash-object -w "$tmp/s.txt"),staged.txt"
refused "N65: a staged path in an unborn repo" "$d"

# ---- N66: a repo with a commit ------------------------------------------------------------------------
d="$tmp/n66-readme"; newrepo "$d"; printf '# x\n' >"$d/README.md"; git -C "$d" add README.md; git -C "$d" commit -qm init
refused "N66: one commit with a README" "$d"
expect_out "N66: the refusal says create the repo empty or use brownfield" 'empty.*brownfield|brownfield.*empty'
d="$tmp/n66-empty"; newrepo "$d"; git -C "$d" commit -q --allow-empty -m init
refused "N66: one empty commit" "$d"
d="$tmp/n66-gi"; newrepo "$d"; printf '*.log\n' >"$d/.gitignore"; git -C "$d" add .gitignore; git -C "$d" commit -qm init
refused "N66: one commit holding only .gitignore" "$d"
d="$tmp/n66-other"; newrepo "$d"; git -C "$d" commit -q --allow-empty -m init; git -C "$d" checkout -q --orphan fresh; git -C "$d" rm -rq --cached . 2>/dev/null || true
refused "N66: HEAD unborn but another branch has a commit" "$d"

# ---- a used gate ledger and a missing committer identity: refused before anything is written -----------
d="$tmp/ledger"; newrepo "$d"; mkdir -p "$d/.git/agents-v0"; printf 'FAIL x\n' >"$d/.git/agents-v0/gate-ledger"
refused "a non-empty gate ledger in an unborn repo" "$d"
expect_out "the refusal names the ledger" 'ledger'
d="$tmp/noid"; newrepo "$d"
snap "$d" >"$tmp/before.snap"
# user.useConfigOnly makes git refuse to guess a name and email, whatever the host name is.
if env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u EMAIL GIT_CONFIG_GLOBAL=/dev/null \
   GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
   sh "$BOOT" "$d" >"$tmp/out.txt" 2>&1; then fail "no git identity: refused (expected non-zero exit)"; else pass "no git identity: refused"; fi
snap "$d" >"$tmp/after.snap"
cmp -s "$tmp/before.snap" "$tmp/after.snap" && pass "no git identity: the folder is byte-identical" || fail "no git identity: the folder changed"
expect_out "no git identity: the hint names user.email" 'user\.email'

if [ "$status" = 0 ]; then printf 'test-bootstrap-greenfield: all passed\n'; else printf 'test-bootstrap-greenfield: FAILED\n' >&2; fi
exit "$status"
