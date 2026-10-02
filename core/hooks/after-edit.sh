#!/bin/sh
# after-edit.sh — afterFileEdit guardrail.
# Scans the edited file for machine-checkable VAPT/security-baseline violations.
# Warnings are heuristics only; Verify (vapt-review) and CI/Sonar own merge evidence.
# Emits additional_context / additionalContext so the agent can act on findings.

set -eu

. "$(dirname "$0")/lib.sh"

payload="$(cat || true)"
path="$(hook_extract_file_path "$payload")"
[ -n "$path" ] || path="$(printf '%s' "$payload" | tr -d '\n')"
[ -f "$path" ] || exit 0

WARN_LINES=""
warn() {
  line="$1"
  printf 'VAPT-WARN: %s\n' "$line" >&2
  if [ -z "$WARN_LINES" ]; then
    WARN_LINES="$line"
  else
    WARN_LINES="$WARN_LINES
$line"
  fi
}

# Delivery artifacts: approvals must reflect a real human decision (CI binds the
# Approver column to a GitLab MR approval via ci/check-approver-gitlab.sh).
case "$path" in
  *docs/agents-v0/requirements/*.md|*docs/agents-v0/milestones/*.md)
    if grep -Eqi '^\|[^|]*\|[^|]*\|[^|]*\|[[:space:]]*(approved|approve|yes|pass)' "$path"; then
      hook_emit_additional_context "Kit hook (after-edit): $path records gate approvals. Only record an Approved row after the user explicitly approved in chat, and name that person in the Approver column — CI requires a matching GitLab merge request approval."
    fi
    exit 0
    ;;
esac

# Only scan text files
case "$path" in
  *.yml|*.yaml|*.java|*.ts|*.tsx|*.svelte|*.js|*.json|*.properties) ;;
  *) exit 0 ;;
esac

# permit-all / MethodSecurityBypass in non-local config (vapt-spring F4, security-baseline §1)
case "$path" in
  *application*.yml|*application*.yaml)
    if grep -Eq 'permit-all[[:space:]]*:[[:space:]]*true' "$path"; then
      warn "$path: permit-all: true found — local dev only, never lab/SIT/UAT/prod (vapt-spring F4)."
    fi
    if grep -Eqi 'MethodSecurityBypass|methodSecurityBypass.isEnabled' "$path"; then
      warn "$path: authz bypass flag found — not allowed in shared environments (vapt-spring F4)."
    fi
    ;;
esac

# PUBLIC_/VITE_ leaking internal URLs or role names (vapt-webapp F2, security-baseline §3)
if grep -Eq 'PUBLIC_[A-Z_]*|VITE_[A-Z_]*' "$path"; then
  if grep -Eq 'https?://[a-z0-9.-]*(internal|staging|dev|sit|uat|prod)[a-z0-9.-]*|role|permission|admin' "$path"; then
    warn "$path: possible internal URL/role in PUBLIC_/VITE_ env (vapt-webapp F2)."
  fi
fi

# document.cookie writes (vapt-webapp F7, security-baseline §4)
if grep -Eq 'document\.cookie[[:space:]]*=' "$path"; then
  warn "$path: document.cookie write — use HttpOnly cookies for auth tokens (vapt-webapp F7)."
fi

# Sourcemaps enabled in production (vapt-webapp F2, security-baseline §8)
if grep -Eq 'sourcemap[[:space:]]*:[[:space:]]*true' "$path"; then
  warn "$path: sourcemap:true — disable in production builds (vapt-webapp F2)."
fi

# Wrong X-Content-Type-Options (security-baseline §6)
if grep -Eqi 'X-Content-Type-Options' "$path"; then
  if ! grep -Eq 'X-Content-Type-Options[^\n]*nosniff' "$path"; then
    warn "$path: X-Content-Type-Options should be 'nosniff' (security-baseline §6)."
  fi
fi

case "$path" in
  *.java)
    # Capture Java preauthorize warnings into WARN_LINES via temp file
    java_warns="$(mktemp)"
    HOOK_JAVA_FILE="$path" python3 -c '
import os, re, sys

path = os.environ.get("HOOK_JAVA_FILE", "")
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)

if not re.search(r"@(?:RestController|Controller)\b", text):
    sys.exit(0)

mapping_re = re.compile(r"@(Post|Put|Patch|Delete)Mapping\b")
preauth_re = re.compile(
    r"@(?:PreAuthorize|Secured|RolesAllowed|"
    r"jakarta\.annotation\.security\.RolesAllowed)\b"
)

controller_m = re.search(r"@(RestController|Controller)\b", text)
first_mapping = mapping_re.search(text)
class_preauth = False
if first_mapping and controller_m.start() < first_mapping.start():
    header = text[controller_m.start() : first_mapping.start()]
    class_preauth = bool(preauth_re.search(header))

lines = text.splitlines()
for i, line in enumerate(lines):
    if not mapping_re.search(line):
        continue
    window = "\n".join(lines[max(0, i - 25) : min(len(lines), i + 16)])
    if preauth_re.search(window) or class_preauth:
        continue
    lineno = i + 1
    print(
        f"{path}:{lineno}: mutating endpoint without method/class "
        f"security annotation (vapt-spring F4; heuristic only — confirm in Verify/Sonar)."
    )
' 2>/dev/null >"$java_warns" || true
    while IFS= read -r jw; do
      [ -n "$jw" ] && warn "$jw"
    done <"$java_warns"
    rm -f "$java_warns"

    if grep -Eq 'getOriginalFilename' "$path"; then
      if ! grep -Eq 'Tika|magic|Magic|content-type|ContentType|MimeType' "$path"; then
        warn "$path: upload validation may rely on filename only — add content sniff + structure parse (vapt-spring F3)."
      fi
    fi
    if grep -Eq '\+\s*".*(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE)|(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE).*"\s*\+' "$path"; then
      warn "$path: possible SQL string concatenation — use parameterized queries (security-baseline §7)."
    fi
    ;;
esac

if [ -n "$WARN_LINES" ]; then
  hook_emit_additional_context "Kit hook (after-edit) — address or confirm in Verify:
$WARN_LINES"
fi

exit 0
