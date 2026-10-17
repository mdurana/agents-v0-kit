#!/bin/sh
# Sourced by after-edit.sh. ASP.NET mutating actions need [Authorize] or [AllowAnonymous].
hook_pack_scan() {
  path="$1"
  case "$path" in
    *.cs) ;;
    *) return 0 ;;
  esac
  pack_warns="$(mktemp)"
  HOOK_PACK_FILE="$path" python3 -c '
import os, re
path = os.environ.get("HOOK_PACK_FILE", "")
try:
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    raise SystemExit(0)
mapping_re = re.compile(r"\[Http(Post|Put|Patch|Delete)\b|\.Map(Post|Put|Patch|Delete)\s*\(")
auth_re = re.compile(r"\[Authorize|\[AllowAnonymous\]|RequireAuthorization|AllowAnonymous")
for i, line in enumerate(lines):
    if not mapping_re.search(line):
        continue
    window = "\n".join(lines[max(0, i - 12): min(len(lines), i + 9)])
    if auth_re.search(window):
        continue
    print(f"{path}:{i + 1}: mutating action without [Authorize]/RequireAuthorization or [AllowAnonymous]/AllowAnonymous (vapt.mdc F4; heuristic only).")
full = "\n".join(lines)
if "AllowAnyOrigin" in full and "AllowCredentials" in full:
    print(f"{path}: AllowAnyOrigin combined with AllowCredentials — insecure CORS configuration (vapt.mdc; heuristic only).")
' 2>/dev/null >"$pack_warns" || true
  while IFS= read -r line; do
    [ -n "$line" ] && warn "$line"
  done <"$pack_warns"
  rm -f "$pack_warns"
}
