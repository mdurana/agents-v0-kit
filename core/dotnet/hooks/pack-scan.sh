#!/bin/sh
# Sourced by after-edit.sh. ASP.NET mutating actions need [Authorize] or [AllowAnonymous].
hook_pack_scan() {
  path="$1"
  case "$path" in
    *.cs) ;;
    *) return 0 ;;
  esac
  case "$path" in
    *Test.cs|*Tests.cs|*/tests/*|*/Tests/*|*.Tests/*) return 0 ;;
  esac
  pack_warns="$(mktemp)"
  HOOK_PACK_FILE="$path" hook_py -c '
import os, re
path = os.environ.get("HOOK_PACK_FILE", "")
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    raise SystemExit(0)
lines = text.splitlines()
mapping_re = re.compile(r"\[Http(Post|Put|Patch|Delete)\b|\.Map(Post|Put|Patch|Delete)\s*\(")
auth_re = re.compile(r"\[Authorize|\[AllowAnonymous\]|RequireAuthorization|AllowAnonymous")
ctrl_m = re.search(r"\[ApiController\]|\bclass\s+\w+Controller\b", text)
first_m = mapping_re.search(text)
class_auth = False
if first_m and ctrl_m and ctrl_m.start() < first_m.start():
    class_auth = bool(auth_re.search(text[max(0, ctrl_m.start() - 300):first_m.start()]))
for i, line in enumerate(lines):
    if not mapping_re.search(line):
        continue
    window = "\n".join(lines[max(0, i - 12): min(len(lines), i + 9)])
    if auth_re.search(window) or class_auth:
        continue
    print(f"{path}:{i + 1}: mutating action without [Authorize]/RequireAuthorization or [AllowAnonymous]/AllowAnonymous (vapt.mdc F4; heuristic only).")
if "AllowAnyOrigin" in text and "AllowCredentials" in text:
    print(f"{path}: AllowAnyOrigin combined with AllowCredentials — insecure CORS configuration (vapt.mdc; heuristic only).")
' 2>/dev/null >"$pack_warns" || true
  while IFS= read -r line; do
    [ -n "$line" ] && warn "$line"
  done <"$pack_warns"
  rm -f "$pack_warns"
}
