#!/bin/sh
# resolve-kit-root.sh — print the kit checkout named by docs/agents-v0/kit-pin.
#
# The pin is a commit SHA plus either a path (a local checkout) or a url whose
# submodule is kit/. The checkout's HEAD must be that commit. Kit file contents
# stay in the kit repository.

set -eu

pin="${1:-docs/agents-v0/kit-pin}"
[ -f "$pin" ] || { printf 'FAIL: missing %s\n' "$pin" >&2; exit 1; }

url=""
path=""
commit=""
while IFS= read -r line; do
  case "$line" in
    url:*) url="${line#url:}" ;;
    path:*) path="${line#path:}" ;;
    commit:*) commit="${line#commit:}" ;;
  esac
done < "$pin"
url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
path="$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
commit="$(printf '%s' "$commit" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[ -n "$commit" ] || { printf 'FAIL: %s has no commit\n' "$pin" >&2; exit 1; }

if [ -n "$path" ]; then
  [ -d "$path" ] || { printf 'FAIL: kit path not found: %s\n' "$path" >&2; exit 1; }
  root="$(cd "$path" && pwd)"
elif [ -d kit ]; then
  root="$(cd kit && pwd)"
else
  printf 'FAIL: %s names a url but there is no kit/ checkout\n' "$pin" >&2
  exit 1
fi

head="$(git -C "$root" rev-parse HEAD)"
want="$(git -C "$root" rev-parse --verify "${commit}^{commit}")" || {
  printf 'FAIL: %s is not a commit in %s\n' "$commit" "$root" >&2
  exit 1
}
[ "$head" = "$want" ] || { printf 'FAIL: kit HEAD %s is not pin %s\n' "$head" "$want" >&2; exit 1; }
printf '%s\n' "$root"
