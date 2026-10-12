#!/bin/sh
# Sourced by after-edit.sh. Java mutating mappings need a security annotation.
hook_pack_scan() {
  path="$1"
  case "$path" in
    *.java) ;;
    *) return 0 ;;
  esac
  case "$path" in
    *Test.java|*Tests.java|*/test/*|*/it/*) return 0 ;;
  esac
  pack_warns="$(mktemp)"
  HOOK_PACK_FILE="$path" python3 -c '
import os, re, sys
path = os.environ.get("HOOK_PACK_FILE", "")
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)
if not re.search(r"@(?:RestController|Controller)\b", text):
    sys.exit(0)
mapping_re = re.compile(r"@(Post|Put|Patch|Delete)Mapping\b")
preauth_re = re.compile(r"@(?:PreAuthorize|Secured|RolesAllowed|jakarta\.annotation\.security\.RolesAllowed)\b")
controller_m = re.search(r"@(RestController|Controller)\b", text)
first_mapping = mapping_re.search(text)
class_preauth = False
if first_mapping and controller_m and controller_m.start() < first_mapping.start():
    class_preauth = bool(preauth_re.search(text[controller_m.start():first_mapping.start()]))
lines = text.splitlines()
for i, line in enumerate(lines):
    if not mapping_re.search(line):
        continue
    window = "\n".join(lines[max(0, i - 25): min(len(lines), i + 16)])
    if preauth_re.search(window) or class_preauth:
        continue
    print(f"{path}:{i + 1}: mutating endpoint without method/class security annotation (vapt.mdc F4; heuristic only).")
' 2>/dev/null >"$pack_warns" || true
  while IFS= read -r line; do
    [ -n "$line" ] && warn "$line"
  done <"$pack_warns"
  rm -f "$pack_warns"
  if grep -Eq 'getOriginalFilename' "$path"; then
    if ! grep -Eq 'Tika|magic|Magic|content-type|ContentType|MimeType' "$path"; then
      warn "$path: upload validation may rely on filename only — add content sniff + structure parse (vapt.mdc F3)."
    fi
  fi
  if grep -Eq '\+\s*".*(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE)|(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE).*"\s*\+' "$path"; then
    warn "$path: possible SQL string concatenation — use parameterized queries (security-baseline §7)."
  fi
}
