# tier1-vars.sh: the one list of the seven AGENTS_V0_* test switches (refs/kit-fixes.md:121,
# kitfix-20261031-installed-no-overrides). Sourced by tier1-harness.sh and tier1.sh. Kit-only file.
T1_OVERRIDE_VARS="AGENTS_V0_SKIP_BRANCH_GUARD AGENTS_V0_SKIP_COMMIT_CHECK AGENTS_V0_COMMIT_CHECK_IGNORE AGENTS_V0_NOW AGENTS_V0_TZ AGENTS_V0_TRACE_MODE AGENTS_V0_TRACE_NO_WRITE"
# t1_guard_env: refuse to run when any test switch is set in the environment (even to an empty value).
t1_guard_env() {
  for v_ in $T1_OVERRIDE_VARS; do
    if eval "[ -n \"\${$v_+x}\" ]"; then
      printf 'tier1: refusing to run: %s is set in the environment (unset every AGENTS_V0_* test switch first)\n' "$v_" >&2
      return 1
    fi
  done
  return 0
}
