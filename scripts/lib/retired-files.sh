# retired-files.sh: the --update cleanup of retired kit files (Sensei 2026-11-02 00:38, option A; N12A 00:52).
# Sourced by scripts/install.sh (rf_check_list, rf_cleanup) and scripts/check-installed-kit.sh (rf_status).
# Kit-only file: it is not installed into projects. POSIX sh; every name it sets starts with rf_.
#
# The list (scripts/lib/retired-files.txt) has the header `# agents-v0 retired-files v1`, then one entry per
# line, three fields separated by one space:
#   kit-managed <sha256> <path>   a file the kit installed and no longer ships. One line per released version:
#                                 the sha256 is of the bytes as installed. Unedited = the file matches one.
#   user-owned  -        <path>   a file the kit once seeded that now belongs to the project.
# <path> is relative to the project root: [A-Za-z0-9._/-] only, no `.` or `..` part, no leading `/` or `-`,
# not under trash/ or .git/. One path has one kind. Other `#` lines are comments; empty lines are skipped.
#
# A listed path (either kind) is no longer written by install.sh (copy_template_file skips it), so retiring a
# file takes only a list entry plus dropping its source. The rules, applied by rf_cleanup on --update:
#   user-owned:  never touched (byte-identical); one NOTE line says the kit no longer manages it.
#   kit-managed: when it matches a listed hash it is moved to trash/agents-v0-retired/<path> (a clash gets
#                .1, .2, ... and never overwrites). An edited copy stays in place with a WARN naming it.
#                A symlink, a path under a symlinked folder, a non-file, or an unusable trash/ is left in
#                place with a WARN. Nothing is ever deleted: this file holds no rm or unlink (validate-kit greps).

RF_HEADER='# agents-v0 retired-files v1'
RF_TRASH='trash/agents-v0-retired'

rf_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -d' ' -f1
  else return 1; fi
}

# rf_check_list <list>: exit 0 when the list is well formed; otherwise print each problem on stderr, exit 1.
rf_check_list() {
  if [ ! -f "$1" ] || [ -L "$1" ]; then printf 'retired-files list missing or not a regular file: %s\n' "$1" >&2; return 1; fi
  LC_ALL=C awk -v hdr="$RF_HEADER" -v src="$1" '
    function bad(m) { printf "%s:%d: %s\n", src, NR, m > "/dev/stderr"; nbad++ }
    NR == 1 { if ($0 != hdr) bad("first line must be \"" hdr "\""); next }
    $0 == "" { next }
    /^#/ { next }
    {
      if ($0 !~ /^[^ ]+ [^ ]+ [^ ]+$/) { bad("want three fields separated by one space"); next }
      split($0, f, " "); k = f[1]; h = f[2]; p = f[3]
      if (k == "kit-managed") { if (length(h) != 64 || h ~ /[^0-9a-f]/) bad("kit-managed needs a lowercase sha256: " h) }
      else if (k == "user-owned") { if (h != "-") bad("user-owned takes - in place of a hash") }
      else { bad("unknown kind: " k); next }
      if (p ~ /^\//) { bad("absolute path refused: " p); next }
      if (p !~ /^[A-Za-z0-9._][A-Za-z0-9._\/-]*$/) { bad("path has a character outside [A-Za-z0-9._/-] or starts with -: " p); next }
      if (("/" p "/") ~ /\/\.\.?\//) { bad("path with a . or .. part refused: " p); next }
      if (p ~ /\/\// || p ~ /\/$/) { bad("path with an empty part refused: " p); next }
      if (p ~ /^(trash|\.git)(\/|$)/ || p ~ /(^|\/)\.git(\/|$)/) { bad("path under trash/ or .git refused: " p); next }
      if ((p in kind) && kind[p] != k) bad("path listed as both kit-managed and user-owned: " p)
      kind[p] = k; n++
    }
    END { if (NR == 0) bad("empty list"); else if (n == 0) bad("no entries"); exit (nbad > 0) }
  ' "$1"
}

# rf_entries <list>: "<kind> <path>" once per path, in list order.
rf_entries() { LC_ALL=C awk 'NR > 1 && $0 != "" && !/^#/ && !seen[$3]++ { print $1, $3 }' "$1"; }

# rf_listed <path> <list>: the path is a retired entry (either kind), so install.sh no longer writes it.
rf_listed() { LC_ALL=C awk -v p="$1" 'NR > 1 && !/^#/ && $3 == p { f = 1; exit } END { exit !f }' "$2"; }

# rf_matches <list> <path> <file>: the file matches a listed kit hash for that path.
rf_matches() {
  rf_h="$(rf_hash "$3")" || return 1
  [ -n "$rf_h" ] && grep -Fqx "kit-managed $rf_h $2" "$1"
}

# rf_no_link <root> <rel>: no part of <rel> under <root>, the last included, is a symlink.
rf_no_link() {
  rf_d="$1"; rf_rest="$2"
  while :; do
    case "$rf_rest" in
      */*) rf_d="$rf_d/${rf_rest%%/*}"; rf_rest="${rf_rest#*/}" ;;
      *) rf_d="$rf_d/$rf_rest"; rf_rest="" ;;
    esac
    [ -L "$rf_d" ] && return 1
    [ -e "$rf_d" ] || return 0
    [ -n "$rf_rest" ] || return 0
  done
}

# rf_cleanup <project root> <list> [<keep prefix>]: apply the rules above. Exit 1 only when the list is bad
# (nothing moved). A path under <keep prefix> (install.sh passes .agents/ without --with-antigravity: the
# Antigravity tree is opt-in) is left exactly as it is, with a note.
rf_cleanup() {
  rf_t="$1"; rf_list="$2"; rf_keep="${3:-}"
  rf_check_list "$rf_list" || return 1
  rf_all="$(rf_entries "$rf_list")" || return 1
  while read -r rf_k rf_p; do
    [ -n "$rf_p" ] || continue
    rf_src="$rf_t/$rf_p"
    [ -e "$rf_src" ] || [ -L "$rf_src" ] || continue
    if [ -n "$rf_keep" ] && [ "$rf_k" = kit-managed ]; then
      case "$rf_p" in "$rf_keep"*)
        printf 'NOTE: retired kit file %s left as is (Antigravity adapter, opt-in); install.sh --update --with-antigravity moves it to trash/.\n' "$rf_p"
        continue ;;
      esac
    fi
    if [ "$rf_k" = user-owned ]; then
      printf 'NOTE: %s is your file: the kit no longer manages it, and --update left it unchanged.\n' "$rf_p"
      continue
    fi
    if ! rf_no_link "$rf_t" "$rf_p"; then
      printf 'WARN: retired kit file %s is a symlink or sits under one; left in place.\n' "$rf_p" >&2; continue
    fi
    if [ ! -f "$rf_src" ]; then
      printf 'WARN: retired kit path %s is not a regular file; left in place.\n' "$rf_p" >&2; continue
    fi
    if ! rf_matches "$rf_list" "$rf_p" "$rf_src"; then
      printf 'WARN: retired kit file %s was edited (it matches no kit version); left in place. Keep it as your own or move it to trash/.\n' "$rf_p" >&2
      continue
    fi
    rf_dst="$RF_TRASH/$rf_p"
    if ! rf_no_link "$rf_t" "$rf_dst" || { [ -e "$rf_t/trash" ] && [ ! -d "$rf_t/trash" ]; }; then
      printf 'WARN: trash/ is a symlink or not a folder; retired kit file %s left in place.\n' "$rf_p" >&2; continue
    fi
    mkdir -p "$rf_t/${rf_dst%/*}" || { printf 'WARN: cannot create %s; %s left in place.\n' "${rf_dst%/*}" "$rf_p" >&2; continue; }
    rf_n=0; rf_try="$rf_dst"
    while [ -e "$rf_t/$rf_try" ] || [ -L "$rf_t/$rf_try" ]; do
      rf_n=$((rf_n + 1)); rf_try="$rf_dst.$rf_n"
    done
    if mv "$rf_src" "$rf_t/$rf_try"; then
      printf 'RETIRED: %s moved to %s (unedited kit file the kit no longer ships).\n' "$rf_p" "$rf_try"
    else
      printf 'WARN: could not move retired kit file %s; left in place.\n' "$rf_p" >&2
    fi
  done <<RF_EOF
$rf_all
RF_EOF
}

# rf_status <project root> <list>: for check-installed-kit.sh (N12A). Prints RETIRED-LEFT <path> for an
# unedited retired kit file still in place (exit 1) and WARN RETIRED-EDITED <path> for an edited one.
rf_status() {
  rf_t="$1"; rf_list="$2"; rf_rc=0
  rf_check_list "$rf_list" 2>/dev/null || { printf 'RETIRED-LIST-BAD %s\n' "$rf_list"; return 1; }
  for rf_p in $(rf_entries "$rf_list" | awk '$1 == "kit-managed" { print $2 }'); do
    rf_src="$rf_t/$rf_p"
    [ -f "$rf_src" ] && [ ! -L "$rf_src" ] || continue
    if rf_matches "$rf_list" "$rf_p" "$rf_src"; then
      printf 'RETIRED-LEFT %s (unedited retired kit file still in place; run install.sh --update)\n' "$rf_p"; rf_rc=1
    else
      printf 'WARN RETIRED-EDITED %s (an edited copy of a retired kit file; kept, not a failure)\n' "$rf_p"
    fi
  done
  return "$rf_rc"
}
