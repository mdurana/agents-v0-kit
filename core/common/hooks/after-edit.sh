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

# Delivery documents: run the phase gate the file belongs to (.agents-v0/ci/gate.sh --for-path) and
# hand any failure to the agent right away. Advisory only — pre-commit blocks an Approved row that
# fails the gate (install.sh --git-hooks), and CI repeats the checks.
GATE_CTX=""
case "$path" in
  *docs/agents-v0/*)
    hook_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    if [ -f "$hook_root/.agents-v0/ci/gate.sh" ]; then
      if ! gate_out="$(sh "$hook_root/.agents-v0/ci/gate.sh" --for-path "$path" 2>&1)"; then
        GATE_CTX="Kit hook (after-edit): the phase gate for $path is failing. Fix it before presenting the gate or recording an Approved row (pre-commit blocks a failing approval):
$(printf '%s\n' "$gate_out" | head -n 60)"
      fi
    fi
    ;;
esac

join_ctx() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    printf '%s\n\n%s' "$1" "$2"
  else
    printf '%s%s' "$1" "$2"
  fi
}

# Delivery artifacts: approvals must reflect a real human decision (CI binds the
# Approver column to a GitLab MR approval via ci/check-approver-gitlab.sh).
case "$path" in
  *docs/agents-v0/requirements/*.md|*docs/agents-v0/milestones/*.md)
    approval_ctx=""
    if grep -Eqi '^\|[^|]*\|[^|]*\|[^|]*\|[[:space:]]*(approved|approve|yes|pass)' "$path"; then
      approval_ctx="Kit hook (after-edit): $path records gate approvals. Only record an Approved row after the user explicitly approved in chat, and name that person in the Approver column — CI requires a matching GitLab merge request approval."
    fi
    hook_emit_additional_context "$(join_ctx "$approval_ctx" "$GATE_CTX")"
    exit 0
    ;;
esac

# Only scan text files
case "$path" in
  *.yml|*.yaml|*.java|*.cs|*.py|*.go|*.ts|*.tsx|*.svelte|*.js|*.json|*.properties) ;;
  *)
    hook_emit_additional_context "$GATE_CTX"
    exit 0
    ;;
esac

# permit-all / MethodSecurityBypass in non-local config (vapt.mdc F4, security-baseline §1)
case "$path" in
  *application*.yml|*application*.yaml)
    if grep -Eq 'permit-all[[:space:]]*:[[:space:]]*true' "$path"; then
      warn "$path: permit-all: true found — local dev only, never lab/SIT/UAT/prod (vapt.mdc F4)."
    fi
    if grep -Eqi 'MethodSecurityBypass|methodSecurityBypass.isEnabled' "$path"; then
      warn "$path: authz bypass flag found — not allowed in shared environments (vapt.mdc F4)."
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

pack_scan="$(dirname "$0")/pack-scan.sh"
if [ -f "$pack_scan" ]; then
  # shellcheck source=/dev/null
  . "$pack_scan"
  hook_pack_scan "$path"
fi

vapt_ctx=""
if [ -n "$WARN_LINES" ]; then
  vapt_ctx="Kit hook (after-edit) — address or confirm in Verify:
$WARN_LINES"
fi
hook_emit_additional_context "$(join_ctx "$vapt_ctx" "$GATE_CTX")"

exit 0
