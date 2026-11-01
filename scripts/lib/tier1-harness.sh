# tier1-harness.sh: shared helpers for the kit's tier 1 script tests (onboard fix, step 0).
# Source it from a test:   KIT="$(cd "$(dirname "$0")/.." && pwd)"; . "$KIT/scripts/lib/tier1-harness.sh"
# Tier 1 is offline and runs no agent. Every case runs on an installed copy (install.sh into a temp git
# repo), never on the kit's own copy. Cleanup removes only the one temp folder this run created
# (Sensei, 2026-11-01 12:04: the suites may remove only the temp folders they create in that same run).
# Kit-only file: it is not installed into projects.

[ -n "${KIT:-}" ] || { printf 'tier1-harness: set KIT before sourcing\n' >&2; exit 2; }

# The seven AGENTS_V0_* test switches (refs/kit-fixes.md, kitfix-20261031-installed-no-overrides).
T1_OVERRIDE_VARS="AGENTS_V0_SKIP_BRANCH_GUARD AGENTS_V0_SKIP_COMMIT_CHECK AGENTS_V0_COMMIT_CHECK_IGNORE AGENTS_V0_NOW AGENTS_V0_TZ AGENTS_V0_TRACE_MODE AGENTS_V0_TRACE_NO_WRITE"

# t1_guard_env: refuse to run when any test switch is set in the environment.
t1_guard_env() {
  for v in $T1_OVERRIDE_VARS; do
    if eval "[ -n \"\${$v+x}\" ]"; then
      printf 'tier1: refusing to run: %s is set in the environment (unset every AGENTS_V0_* test switch first)\n' "$v" >&2
      return 1
    fi
  done
  return 0
}

T1_TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-tier1.XXXXXX")"
: > "$T1_TMP/.kit-tier1-owned"
# t1_cleanup: remove only the folder made above, and only while it still carries this run's marker.
t1_cleanup() {
  case "$T1_TMP" in "${TMPDIR:-/tmp}"/kit-tier1.*) ;; *) return 0 ;; esac
  [ -f "$T1_TMP/.kit-tier1-owned" ] && rm -rf "$T1_TMP"
  return 0
}
trap 'rc=$?; t1_cleanup; exit $rc' EXIT
trap 't1_cleanup; exit 130' INT
trap 't1_cleanup; exit 143' TERM

T1_STATUS=0; T1_N=0; T1_FAILS=0
pass() { T1_N=$((T1_N + 1)); printf 'ok: %s\n' "$1"; }
fail() { T1_N=$((T1_N + 1)); T1_FAILS=$((T1_FAILS + 1)); printf 'FAIL: %s\n' "$1" >&2; T1_STATUS=1; }
has()   { if grep -Fq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1 (missing '$3' in $2)"; fi; }
lacks() { if grep -Fq -- "$3" "$2" 2>/dev/null; then fail "$1 ('$3' found in $2)"; else pass "$1"; fi; }
# expect_pass|expect_fail <description> <dir> <command...>: output goes to $T1_TMP/out.txt
expect_pass() { d_="$1"; w_="$2"; shift 2; if (cd "$w_" && "$@") > "$T1_TMP/out.txt" 2>&1; then pass "$d_"; else fail "$d_ (expected exit 0)"; fi; }
expect_fail() { d_="$1"; w_="$2"; shift 2; if (cd "$w_" && "$@") > "$T1_TMP/out.txt" 2>&1; then fail "$d_ (expected non-zero)"; else pass "$d_"; fi; }

# G <dir> <git args...>: git with a fixed test identity and no signing
G() { d_="$1"; shift; git -C "$d_" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }

# t1_repo <name> [--empty|--commit]: a new git repo under $T1_TMP; prints its path.
#   --empty (default): git init only, no commits. --commit: one README commit on main.
t1_repo() {
  r_="$T1_TMP/$1"; mode_="${2:---empty}"
  mkdir -p "$r_" && git -C "$r_" init -q -b main
  if [ "$mode_" = --commit ]; then printf '# fixture\n' > "$r_/README.md"; G "$r_" add README.md; G "$r_" commit -qm base; fi
  printf '%s\n' "$r_"
}

# t1_install <repo> [install.sh flags...]: real install (no --test-overrides unless passed); log in $T1_TMP/install.log
t1_install() {
  r_="$1"; shift
  sh "$KIT/scripts/install.sh" "$@" "$r_" > "$T1_TMP/install.log" 2>&1 || { cat "$T1_TMP/install.log" >&2; return 1; }
}

# t1_hash_ok <repo>: the installed copy must match the kit byte for byte (check-installed-kit.sh prints HASH-OK).
t1_hash_ok() {
  sh "$KIT/scripts/check-installed-kit.sh" "$1" > "$T1_TMP/hash.txt" 2>&1 && grep -q '^HASH-OK' "$T1_TMP/hash.txt"
}

# t1_snapshot <repo> <out>: one line per tracked and untracked file (sha256 + path), plus every ref and the
# staged entries (git ls-files -s, not the raw index, whose stat data git rewrites on any status) and the
# config hash. Two equal snapshots mean the repo is byte-identical (E37, E38).
t1_snapshot() {
  r_="$1"; o_="$2"
  ( cd "$r_" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f_; do
      printf 'F %s %s\n' "$(t1_sha < "$f_")" "$f_"; done
    git -C "$r_" for-each-ref --format='R %(objectname) %(refname)' | LC_ALL=C sort
    printf 'H %s\n' "$(git -C "$r_" symbolic-ref -q HEAD || git -C "$r_" rev-parse HEAD)"
    git -C "$r_" ls-files -s | sed 's/^/S /'
    [ -f "$r_/.git/config" ] && printf 'G %s config\n' "$(t1_sha < "$r_/.git/config")"
  ) > "$o_"
}
t1_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# t1_done <suite name>: print the summary and exit with the suite status.
t1_done() {
  if [ "$T1_STATUS" = 0 ]; then printf '%s: OK (%s checks)\n' "$1" "$T1_N"
  else printf '%s: FAILED (%s of %s checks)\n' "$1" "$T1_FAILS" "$T1_N" >&2; fi
  exit "$T1_STATUS"
}
