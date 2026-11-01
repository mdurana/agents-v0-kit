# tier1-harness.sh: shared helpers for the kit's tier 1 script tests (onboard fix, step 0).
# Source it from a test:   KIT="$(cd "$(dirname "$0")/.." && pwd)"; . "$KIT/scripts/lib/tier1-harness.sh"
# Tier 1 is offline and runs no agent. Every case runs on an installed copy (install.sh into a temp git
# repo), never on the kit's own copy. Cleanup removes only the one temp folder this run created
# (Sensei, 2026-11-01 12:04: the suites may remove only the temp folders they create in that same run).
# Kit-only file: it is not installed into projects.

[ -n "${KIT:-}" ] || { printf 'tier1-harness: set KIT before sourcing\n' >&2; exit 2; }

. "$KIT/scripts/lib/tier1-vars.sh"
# The switch guard runs first, as soon as the harness is sourced (N20).
t1_guard_env || exit 2

# One temp folder per run. T1_TMP is readonly, the folder must be a direct child of the temp root, and
# the marker holds a random token for this run, so cleanup can only ever remove this run's own folder.
T1_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || { printf 'tier1-harness: no temp folder\n' >&2; exit 2; }
T1_TMP="$(mktemp -d "$T1_ROOT/kit-tier1.XXXXXX")" || { printf 'tier1-harness: mktemp failed\n' >&2; exit 2; }
[ -d "$T1_TMP" ] || { printf 'tier1-harness: mktemp made no folder\n' >&2; exit 2; }
readonly T1_TMP T1_ROOT
T1_TOKEN="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')$$"
readonly T1_TOKEN
printf '%s\n' "$T1_TOKEN" > "$T1_TMP/.kit-tier1-owned"
# t1_cleanup: remove $T1_TMP only if it is still a real folder (not a symlink) named kit-tier1.<6 chars>
# directly under the temp root, with no `..`, and its marker still holds this run's token.
t1_cleanup() {
  case "$T1_TMP" in *..*|*//*) return 0 ;; esac
  [ "${T1_TMP%/*}" = "$T1_ROOT" ] || return 0
  b_="${T1_TMP##*/}"
  case "$b_" in kit-tier1.??????) ;; *) return 0 ;; esac
  case "${b_#kit-tier1.}" in */*) return 0 ;; esac
  [ -d "$T1_TMP" ] && [ ! -L "$T1_TMP" ] || return 0
  [ "$(cat "$T1_TMP/.kit-tier1-owned" 2>/dev/null)" = "$T1_TOKEN" ] || return 0
  rm -rf "$T1_TMP"
}
trap 'rc=$?; t1_cleanup; exit $rc' EXIT
trap 't1_cleanup; exit 130' INT
trap 't1_cleanup; exit 143' TERM
trap 't1_cleanup; exit 129' HUP

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

# t1_snapshot <repo> <out>: everything a kit run could change, for the byte-identical check (E37, E38):
#   F <sha256> <mode> <path>   every file in the work tree (tracked and untracked), with its mode
#   L <target> <path>          every symlink, with its target
#   A <sha256> <mode> <path>   every file under .git/agents-v0 (ledger, grant), .git/hooks and .git/info
#   R / H / S / G / T          every ref, HEAD, the staged entries (git ls-files -s, not the raw index,
#                              whose stat data git rewrites on any status), the config, and the stash list
# Works in a main checkout and in a linked worktree (it reads .git paths through git rev-parse).
t1_snapshot() {
  r_="$1"; o_="$2"
  gd_="$(git -C "$r_" rev-parse --absolute-git-dir)" || return 1
  cd_="$(cd "$r_" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" || return 1
  {
    ( cd "$r_" && find . -name .git -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f_; do
        if [ -L "$f_" ]; then printf 'L %s %s\n' "$(readlink "$f_")" "$f_"
        else printf 'F %s %s %s\n' "$(t1_sha < "$f_")" "$(t1_mode "$f_")" "$f_"; fi; done )
    for d_ in "$cd_/agents-v0" "$cd_/hooks" "$cd_/info" "$gd_/agents-v0"; do
      [ -d "$d_" ] || continue
      ( cd "$d_" && find . -type f -print | LC_ALL=C sort | while IFS= read -r f_; do
          printf 'A %s %s %s/%s\n' "$(t1_sha < "$f_")" "$(t1_mode "$f_")" "$d_" "$f_"; done )
    done
    git -C "$r_" for-each-ref --format='R %(objectname) %(refname)' | LC_ALL=C sort
    printf 'H %s\n' "$(git -C "$r_" symbolic-ref -q HEAD || git -C "$r_" rev-parse -q --verify HEAD || echo none)"
    git -C "$r_" ls-files -s | sed 's/^/S /'
    [ -f "$cd_/config" ] && printf 'G %s config\n' "$(t1_sha < "$cd_/config")"
    git -C "$r_" stash list --format='T %H' 2>/dev/null
  } > "$o_"
}
t1_mode() { if stat -c %a "$1" >/dev/null 2>&1; then stat -c %a "$1"; else stat -f %Lp "$1"; fi; }
t1_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# t1_done <suite name>: print the summary and exit with the suite status.
t1_done() {
  if [ "$T1_STATUS" = 0 ]; then printf '%s: OK (%s checks)\n' "$1" "$T1_N"
  else printf '%s: FAILED (%s of %s checks)\n' "$1" "$T1_FAILS" "$T1_N" >&2; fi
  exit "$T1_STATUS"
}
