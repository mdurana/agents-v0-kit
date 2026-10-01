#!/bin/sh
# validate-kit.sh — validate the agents-v0 kit (vendor-neutral core + adapters),
# optionally an installed target repo.
# Usage:
#   validate-kit.sh                 validate the kit itself (no arguments allowed)
#   validate-kit.sh --target <dir>  also validate the installed kit in a target repo
# Kit checks: rule frontmatter, cross-references, required commands/artifacts,
# approval wording, per-phase evidence contracts, Cursor model fields and
# routing-matrix rows, adapter config (cursor hooks.json), entry files (README.md),
# template parity, hook
# classifications, and shell syntax. Target checks: adapter trees, entry files,
# CI scripts, seeded docs, ignore negations, exec bits. Model availability in
# each tool is not verified.
set -eu

usage() {
  printf 'usage: %s                validate the kit itself (no arguments)\n' "$(basename "$0")" >&2
  printf '       %s --target <dir>  also validate the installed kit in a target repo\n' "$(basename "$0")" >&2
  exit 1
}

KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KIT"
fail=0

err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

TARGET_MODE=0
TARGET_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || usage
      TARGET_MODE=1
      TARGET_DIR="$2"
      shift 2
      ;;
    *)
      printf 'error: unexpected argument: %s\n' "$1" >&2
      usage
      ;;
  esac
done
if [ "$TARGET_MODE" = 1 ] && [ ! -d "$TARGET_DIR" ]; then
  printf 'FAIL: target directory not found: %s\n' "$TARGET_DIR" >&2
  exit 1
fi

# Validate an installed target repo: adapter trees, entry files, CI scripts,
# seeded docs, ignore negations, and executable bits.
validate_target() {
  t="$(cd "$1" && pwd)"
  if [ ! -d "$t/.cursor" ]; then
    err "target has no .cursor/ tree — run scripts/install.sh first"
    return 0
  fi
  [ -f "$t/.cursor/hooks.json" ] || err "target .cursor/hooks.json missing"
  [ -f "$t/.cursor/rules/org/workflow-orchestration.mdc" ] || err "target .cursor/rules/org missing"
  [ -f "$t/.cursor/commands/build.md" ] || err "target .cursor/commands missing"
  [ -f "$t/.cursor/agents/backend-engineer.md" ] || err "target .cursor/agents missing"
  [ -f "$t/.cursor/skills/spec-intake/SKILL.md" ] || err "target .cursor/skills missing"
  [ -x "$t/.cursor/hooks/pre-shell.sh" ] || err "target .cursor/hooks/pre-shell.sh missing or not executable"
  [ -f "$t/README.md" ] || err "target README.md missing (install.sh seeds it)"
  [ -f "$t/ci/check-approvals.sh" ] || err "target ci/check-approvals.sh missing"
  [ -f "$t/ci/check-evidence.sh" ] || err "target ci/check-evidence.sh missing"
  [ -x "$t/ci/check-evidence.sh" ] || err "target ci/check-evidence.sh not executable"
  [ -f "$t/.gitlab/merge_request_templates/default.md" ] || err "target GitLab MR template missing"
  grep -Fq 'check-evidence' "$t/.gitlab/merge_request_templates/default.md" || err "target MR template lacks the evidence-check reference"
  [ -f "$t/docs/compliance-matrix.md" ] || err "target docs/compliance-matrix.md missing"
  [ -f "$t/docs/model-routing-matrix.md" ] || err "target docs/model-routing-matrix.md missing"
  [ -f "$t/docs/user-guide.md" ] || err "target docs/user-guide.md missing"
  if [ -f "$t/.gitignore" ]; then
    grep -Fq '!docs/build/' "$t/.gitignore" || err "target .gitignore lacks the !docs/build/ negation (build evidence would be ignored)"
  fi
  if [ -f "$t/.cursorignore" ]; then
    grep -Fq '!docs/build/' "$t/.cursorignore" || err "target .cursorignore lacks the !docs/build/ negation"
  fi
}

# 1. Rules: valid frontmatter (single source of truth in core/rules/*.mdc).
for f in core/rules/*.mdc; do
  [ -e "$f" ] || continue
  head -n1 "$f" | grep -qx -- '---' || err "$f: missing opening ---"
  awk 'NR<=20 && /^---$/ && NR>1 {found=1; exit} END{exit !found}' "$f" || err "$f: missing closing ---"
done
for phase in intake design build verify release; do
  grep -Fq "\`/$phase\`" core/rules/workflow-orchestration.mdc || err "workflow rule does not reference /$phase"
done
grep -Fq 'docs/build/' core/rules/workflow-orchestration.mdc || err "workflow rule does not mandate persisted Build evidence"
grep -Fq 'docs/verify/' core/rules/workflow-orchestration.mdc || err "workflow rule does not mandate persisted Verify evidence"
grep -Fq 'docs/project-profile.md' core/rules/workflow-orchestration.mdc || err "workflow rule does not reference docs/project-profile.md"
grep -Fq '/triage' core/rules/workflow-orchestration.mdc || err "workflow rule does not reference /triage"

# 2. Cross-references: every rule/doc named by kit content resolves.
for ref in $(grep -rhoE '`[a-z-]+\.mdc`' core/rules core/agents core/commands core/skills | tr -d '`' | sort -u); do
  [ -f "core/rules/$ref" ] || err "kit content references missing rule $ref"
done
for ref in $(grep -rhoE '`docs/[a-zA-Z0-9/_.-]+\.md`' core/rules core/agents core/commands core/skills | tr -d '`' | sort -u); do
  # Outputs that /onboard writes in the target repo are not seeded templates.
  case "$ref" in docs/onboarding/report.md|docs/adr/0000-inherited-decisions.md|docs/discovery/*) continue ;; esac
  [ -f "$ref" ] || [ -f "templates/$ref" ] || err "referenced doc missing (seed templates/$ref): $ref"
done

# 3. Commands: every phase command exists; workflow rule references the phases; evidence contracts.
for command in plan intake design build verify maintain release deliver status onboard triage; do
  [ -f "core/commands/$command.md" ] || err "missing /$command command"
done
grep -Fq '`/plan`' core/rules/workflow-orchestration.mdc || err "workflow rule does not reference /plan"
grep -Fq 'docs/requirements/<feature>.md' core/commands/intake.md || err "/intake does not name its requirements artifact"
grep -Fq 'docs/build/' core/commands/build.md || err "/build does not name persisted build evidence paths"
grep -Fq 'docs/verify/' core/commands/verify.md || err "/verify does not name persisted evidence paths"
grep -Fqi 'exist on disk' core/commands/deliver.md || err "/deliver does not verify recorded evidence existence"

# 4. Agents: name matches file, subagent mode, Cursor model field, referenced.
for f in core/agents/*.md; do
  name="$(basename "$f" .md)"
  grep -Eq "^name:[[:space:]]*$name$" "$f" || err "$f: frontmatter name must match filename"
  grep -Eq '^mode:[[:space:]]*subagent' "$f" || err "$f: missing mode: subagent"
  grep -Eq '^model:[[:space:]]*[a-z0-9.-]+$' "$f" || err "$f: missing cursor model"
  if grep -Eq '^model_kilo:' "$f" || grep -Eq '^model_claude:' "$f"; then
    err "$f: must not carry model_kilo or model_claude (Cursor-only kit)"
  fi
  grep -Fqr -- "$name" core/commands core/agents core/skills || err "$name is not referenced by a command, agent, or skill"
done

# 5. Skills: standard frontmatter, referenced, no rule fields.
for f in core/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$f")")"
  grep -Eq "^name:[[:space:]]*$name$" "$f" || err "$f: frontmatter name must match directory"
  grep -Fqr -- "$name" core/commands core/agents || err "$name is not referenced by a command or agent"
  if awk 'NR==1 && /^---/{f=1;next} f && /^---/{f=0} f && (/^globs:/||/^alwaysApply:/){print;exit}' "$f" | grep -q .; then
    err "$f: skill frontmatter has rule fields (globs/alwaysApply)"
  fi
done

# 6. Phase commands carry explicit approval wording.
for command in intake design build verify release; do
  grep -Eqi 'explicit.*approval|approval.*explicit' "core/commands/$command.md" || err "/$command lacks explicit approval wording"
done

# 7. Model routing: each agent's cursor model appears in its matrix row; per-tool columns exist.
[ -f docs/model-routing-matrix.md ] || err "docs/model-routing-matrix.md missing"
for f in core/agents/*.md; do
  name="$(basename "$f" .md)"
  m="$(grep -E '^model:' "$f" | head -n1 | sed 's/^model:[[:space:]]*//; s/[[:space:]]*$//')"
  grep -E "\\|[[:space:]]*${name}[[:space:]]*\\|" docs/model-routing-matrix.md | grep -Fq "\`$m\`" || err "$name cursor model $m does not match its routing-matrix row"
done
# 8. Adapter config exists and wires the right entry points.
[ -f core/adapters/cursor/hooks.json ] || err "cursor hooks.json missing"
grep -Fq 'pre-shell.sh' core/adapters/cursor/hooks.json || err "cursor hooks.json does not wire pre-shell"
grep -Fq '"version": 1' core/adapters/cursor/hooks.json || err "cursor hooks.json must declare version 1"
[ ! -f core/adapters/claude/settings.json ] && [ ! -f core/adapters/kilo/kilo.json ] || err "remove legacy claude/kilo adapter files (Cursor-only kit)"
[ -d .claude ] && err "remove .claude/ from the kit repo (Cursor-only)"
[ -d core/adapters/claude ] && err "remove core/adapters/claude/ (Cursor-only)"
[ -d core/adapters/kilo ] && err "remove core/adapters/kilo/ (Cursor-only)"

# 9. Hook classifications are deliberate: pre-shell blocks; after-edit warns; stop is evidence-based.
grep -Fq 'exit 2' core/hooks/pre-shell.sh || err "pre-shell hook has no blocking exit"
grep -Eq 'ASK:|ask\\t' core/hooks/pre-shell.sh core/hooks/lib.sh || err "pre-shell hook lacks commit/push approval prompt"
grep -Fq 'exit 0' core/hooks/after-edit.sh || err "after-edit hook must remain warning-only"
grep -Fq 'hook_emit_additional_context' core/hooks/after-edit.sh || err "after-edit hook must surface warnings to the agent"
grep -Fq 'hook_emit_session_context' core/hooks/lib.sh || err "lib.sh must provide session-start context emitter"
grep -Fq 'agents-v0-stop-reminder' core/hooks/stop.sh || err "stop hook must rate-limit reminders"
[ -f core/hooks/hook-policy.py ] || err "hook-policy.py missing"
[ -f core/hooks/pre-edit.sh ] || err "pre-edit.sh missing"
grep -Fq 'pre-edit.sh' core/adapters/cursor/hooks.json || err "cursor hooks.json must wire pre-edit"
grep -Fq 'beforeMCPExecution' core/adapters/cursor/hooks.json && err "cursor hooks.json must not wire MCP (kit does not ship MCP)"
[ -f core/hooks/pre-mcp.sh ] && err "remove core/hooks/pre-mcp.sh (kit does not ship MCP)"
[ -f core/hooks/mcp-policy.json ] && err "remove core/hooks/mcp-policy.json (kit does not ship MCP)"
[ -f docs/mcp-baseline.md ] && err "remove docs/mcp-baseline.md (kit does not ship MCP)"
[ -f templates/.cursor/mcp.json.example ] && err "remove the MCP example config (kit does not ship MCP)"
grep -Fq 'session-start.sh' core/adapters/cursor/hooks.json || err "cursor hooks.json must wire session-start"
grep -Fq 'pipefail' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run with pipefail (tee masks failures)"
[ -f templates/ci/check-approver-github.sh ] && err "remove templates/ci/check-approver-github.sh (GitLab-only kit)"
[ -d templates/.github ] && err "remove templates/.github (GitLab-only kit)"
grep -Fq 'hook_shell_permission_allow' core/hooks/lib.sh || err "lib.sh must emit Cursor permission allow JSON"
grep -Fq 'hook_shell_permission_allow' core/hooks/pre-edit.sh || err "pre-edit must call hook_shell_permission_allow on allow"
grep -Fq 'CI_MERGE_REQUEST_IID' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must pass CI_MERGE_REQUEST_IID to check-delivery-linkage.sh"
grep -Fq 'check-approver-gitlab.sh' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage.sh must invoke check-approver-gitlab.sh"
grep -Fq 'review_phases' templates/ci/check-delivery-linkage.sh || err "MR approval must accept an Approved release or verify approver"
grep -Fq 'CHECK_MR_APPROVER: "0"' templates/.gitlab-ci.yml || err "delivery-gate must skip the live approver check"
grep -Fq 'read_api' templates/.gitlab-ci.yml || err "delivery-approval token must be read_api"
grep -Fq 'FETCH_HEAD:ci/' templates/.gitlab-ci.yml || err "delivery jobs must run ci scripts from the default branch"
grep -Fq 'node:20-bookworm' templates/.gitlab-ci.yml || err "frontend job must use a Node image"
grep -Fq 'Security/SAST.gitlab-ci.yml' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must include GitLab SAST"
grep -Fq 'ENABLE_GITLAB_SAST' templates/.gitlab-ci.yml || err "SAST include must be conditional so a missing template does not block pipelines"
grep -Fq 'name: delivery-approval' templates/.gitlab-ci.yml || err "delivery-approval must declare its environment so GITLAB_TOKEN can be scoped to that job"
grep -Fq 'bootstrap merge request is not checked' templates/.gitlab-ci.yml || err "delivery-approval must skip when trusted ci scripts are not on the default branch yet"
grep -Fq 'using merge request copies of ci scripts' templates/.gitlab-ci.yml || err "delivery-gate may use merge request ci scripts only before they exist on the default branch"
if grep -Fq 'deb.nodesource.com' templates/.gitlab-ci.yml; then err "frontend install must not curl nodesource"; fi
grep -Fq 'when: manual' templates/.gitlab-ci.yml || err "delivery-approval must be a manual job so it can run after MR approval"
grep -Fq 'ci-artifacts/verify.log' templates/.gitlab-ci.yml || err "GitLab verify log must be uploaded from the project directory"
grep -Fq 'CI_JOB_TOKEN cannot read' templates/ci/check-approver-gitlab.sh || err "job-token 403 must say CI_JOB_TOKEN cannot read approvals"
grep -Fq '/var/run/docker.sock' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must document the non-dind Docker socket option"
grep -Fq '.m2/repository' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must cache the Maven repository"
grep -Fq 'npm_config_cache' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must cache the npm download directory"
grep -Fq 'endpoint-stacks.md' templates/scripts/discover-codebase.sh || err "discover-codebase.sh must propose non-Spring endpoint rows"
grep -Fq 'check-delivery-gate-local.sh' templates/hooks/pre-push || err "hooks/pre-push must run the local delivery gate"
grep -Fq 'read_api' templates/scripts/verify-gitlab-ci-prereqs.sh || err "verify-gitlab-ci-prereqs.sh must check the read_api token"
grep -Fq 'check-delivery-linkage.sh' templates/scripts/check-delivery-gate-local.sh || err "check-delivery-gate-local.sh must run linkage"
grep -Fq 'check-design-contracts.sh' templates/scripts/check-delivery-gate-local.sh || err "check-delivery-gate-local.sh must run design contracts"
grep -Fq 'check-build-plan.sh' templates/scripts/check-delivery-gate-local.sh || err "check-delivery-gate-local.sh must run the build plan"
grep -Fq 'check-endpoint-auth.sh' templates/scripts/check-delivery-gate-local.sh || err "check-delivery-gate-local.sh must run endpoint auth"
python3 -c 'import yaml' >/dev/null 2>&1 || err "PyYAML is required (pip install pyyaml, or apk add py3-yaml). OpenAPI checks do not run without it."
[ -f core/model-roles.tsv ] || err "core/model-roles.tsv missing"
grep -Fq 'model-config.json' scripts/install.sh || err "install.sh must remap agent models from .cursor/model-config.json"
for f in core/agents/*.md; do
  name="$(basename "$f" .md)"
  grep -Eq "^${name}[[:space:]]+" core/model-roles.tsv || err "$name missing from core/model-roles.tsv"
done
grep -Fq '## Endpoint authorization' docs/project-profile.md templates/docs/project-profile.md || err "project profile must document extra endpoint-authorization stacks"
grep -Fq 'Secret-Detection.gitlab-ci.yml' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must use GitLab Secret Detection"
grep -Fq 'check-coverage-ratchet.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run the coverage ratchet check"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error core/hooks/*.sh templates/ci/*.sh templates/scripts/*.sh scripts/*.sh || err "shellcheck -S error failed"
fi
[ -f core/hooks/session-start.sh ] || err "session-start.sh missing"
[ -f scripts/test-hooks.sh ] || err "scripts/test-hooks.sh missing"
[ -f scripts/test-hook-policy.py ] || err "scripts/test-hook-policy.py missing"
sh scripts/test-hooks.sh || err "scripts/test-hooks.sh failed"
[ -f scripts/test-ci-checks.sh ] || err "scripts/test-ci-checks.sh missing"
sh scripts/test-ci-checks.sh || err "scripts/test-ci-checks.sh failed"
[ -f scripts/test-onboard.sh ] || err "scripts/test-onboard.sh missing"
sh scripts/test-onboard.sh || err "scripts/test-onboard.sh failed"
[ -f scripts/test-maintain.sh ] || err "scripts/test-maintain.sh missing"
sh scripts/test-maintain.sh || err "scripts/test-maintain.sh failed"
[ -f scripts/test-design-build.sh ] || err "scripts/test-design-build.sh missing"
sh scripts/test-design-build.sh || err "scripts/test-design-build.sh failed"
[ -f scripts/test-release.sh ] || err "scripts/test-release.sh missing"
sh scripts/test-release.sh || err "scripts/test-release.sh failed"
grep -Fq 'git status --porcelain' core/hooks/stop.sh || err "stop hook is not evidence-based (expected git status check)"

# 10. Entry files: AGENTS.md states the lifecycle and precedence; README documents
# the kit and is seeded into target workspaces.
[ -f AGENTS.md ] || err "AGENTS.md missing"
[ -f README.md ] || err "README.md missing"
grep -Fq 'Delivery approvals' AGENTS.md || err "AGENTS.md does not describe the approvals contract"
grep -Fq 'the repository wins' AGENTS.md || err "AGENTS.md does not state rule precedence"
grep -Fq 'README.md' scripts/install.sh || err "install.sh does not seed README.md into target workspaces"

# 11. Required template artifacts + docs/templates parity.
for artifact in templates/.gitlab-ci.yml templates/.gitlab/merge_request_templates/default.md templates/docs/architecture.md templates/docs/network.md templates/docs/project-profile.md templates/docs/requirements/_state.template.json templates/CODEOWNERS templates/ci/check-approvals.sh templates/ci/check-evidence.sh templates/ci/check-milestone.sh templates/ci/check-delivery-linkage.sh templates/ci/check-approver-gitlab.sh templates/ci/check-coverage-ratchet.sh templates/ci/check-known-failures.sh templates/ci/resolve-layout.sh templates/ci/check-gate-metrics.sh templates/ci/check-event-schemas.sh templates/scripts/feature-worktree.sh templates/scripts/check-attempt-budget.sh templates/scripts/check-delivery-gate-local.sh templates/scripts/verify-gitlab-ci-prereqs.sh templates/hooks/pre-push templates/.cursor/model-config.json.example templates/docs/milestones/_template.md templates/docs/milestones/p0-platform-skeleton.md templates/docs/milestones/p1-contracts-and-data-models.md templates/docs/milestones/p2-mvp-core-features.md templates/docs/milestones/p3-feature-expansion.md templates/docs/milestones/p4-hardening.md templates/docs/milestones/p5-release-readiness.md templates/docs/repo-map.md templates/docs/workspace.manifest.json templates/scripts/generate-repo-map.sh templates/scripts/collect-dependency-graphs.sh templates/scripts/sync-feature-state.sh templates/scripts/delivery-metrics.sh templates/ci/check-feature-state.sh templates/docs/greenfield-onboarding.md templates/docs/brownfield-onboarding.md templates/scripts/run-local-container.sh templates/docker-compose.yml templates/docker/README.md templates/docker/Dockerfile.spring-boot templates/docker/Dockerfile.node templates/docker/Dockerfile.static-nginx templates/docker/nginx-spa.conf templates/docker/docker-compose.postgres.yml templates/maven/checkstyle.xml templates/maven/dependency-check-suppressions.xml templates/maven/quality-plugins-ci-security.xml templates/maven/contract-conformance.xml templates/maven/archunit/LayerRulesTest.java templates/docs/design/ux-spec.md templates/docs/design/system/context-map.md templates/docs/design/system/nfr-slo.md templates/docs/design/system/threat-model.md templates/docs/design/system/slo-evidence.md templates/ci/check-gate-metrics.sh templates/ci/check-event-schemas.sh templates/scripts/feature-worktree.sh templates/scripts/check-attempt-budget.sh; do
  [ -f "$artifact" ] || err "required artifact template missing: $artifact"
done
for doc in docs/compliance-matrix.md docs/model-routing-matrix.md docs/user-guide.md docs/agents-v0-kit.md docs/greenfield-onboarding.md docs/brownfield-onboarding.md; do
  [ -f "templates/$doc" ] || err "templates/$doc missing (install.sh will not seed $doc)"
  if [ -f "templates/$doc" ]; then
    cmp -s "$doc" "templates/$doc" || err "$doc differs from templates/$doc — run: ./scripts/install.sh --update ."
  fi
done

# 12. Compliance matrix contracts.
grep -Fq '| Phase | Artifacts | Approver | Decision | Date |' core/skills/spec-intake/SKILL.md || err "spec-intake lacks the canonical Delivery approvals table format"
grep -Fq 'check-approvals' templates/.gitlab/merge_request_templates/default.md || err "MR template does not reference the CI approval check"
grep -Fq 'check-evidence' templates/.gitlab/merge_request_templates/default.md || err "MR template does not reference the CI evidence check"
grep -Fq 'docs/build/' core/skills/spec-intake/SKILL.md || err "spec-intake does not record per-phase evidence paths"
grep -Fq 'check-evidence' core/agents/requirements-analyst.md || err "requirements-analyst does not reference the CI evidence check"
grep -Fq 'check-evidence.sh' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage must invoke check-evidence.sh"
grep -Fq 'check-milestone.sh' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage must invoke check-milestone.sh"

# 14. Milestone delivery contracts.
grep -Fq 'milestone' templates/ci/check-approvals.sh || err "check-approvals does not accept the milestone phase"
grep -Fq 'Milestone/Story links' core/skills/spec-intake/SKILL.md || err "spec-intake does not record milestone/story links"
grep -Fq 'so that' core/skills/spec-intake/SKILL.md || err "spec-intake does not require the As a / I want / so that user story"
grep -Fq 'AC-8' core/skills/spec-intake/SKILL.md || err "spec-intake lacks the acceptance-criteria cap"
grep -Fq 'Vertical slice' core/rules/workflow-orchestration.mdc || err "workflow rule lacks the story-size budget"
grep -Fq 'helper-brief' core/rules/workflow-orchestration.mdc || err "workflow rule lacks helper briefs"
grep -Fq 'docs/build/<feature>/plan.md' core/rules/workflow-orchestration.mdc || err "workflow rule lacks the build plan"
grep -Fq 'failure-brief.md' core/commands/build.md || err "/build does not send the second failure to debug-investigator"
grep -Fq 'phase-result.md' core/agents/orchestrator.md || err "orchestrator does not write the phase result"
grep -Fq 'together' core/commands/verify.md || err "/verify does not run the read-only reviewers together"
grep -Fq 'build-output.txt' core/rules/workflow-orchestration.mdc || err "workflow rule does not keep raw verify logs out of the next attempt"
grep -Fq 'docs/design/<feature>/openapi.yaml' core/skills/contract-first-design/SKILL.md || err "contract-first-design does not draft a feature-local contract"
grep -Fq 'Backend verify (fast' core/skills/implement-spring-service/SKILL.md || err "implement-spring-service does not use the fast verify loop"
grep -Fq 'slo-evidence' core/commands/verify.md || err "/verify does not run slo-evidence"
grep -Fq 'docs/design/system/slo-evidence.md' templates/ci/check-milestone.sh || err "check-milestone does not check SLO evidence"
grep -Fq 'slo-evidence' templates/docs/milestones/p4-hardening.md || err "P4 milestone does not name slo-evidence"
grep -Fq 'As a [role], I want [goal], so that [benefit].' templates/docs/milestones/_template.md || err "milestone template user story is not As a / I want / so that"
grep -Fq 'so that' templates/docs/milestones/p0-platform-skeleton.md || err "P0 stories are not As a / I want / so that"
grep -Fq 'so that' docs/user-guide.md || err "user guide intake example lacks so that"
grep -Fq 'milestone' core/commands/intake.md || err "/intake does not mention milestone programs"
grep -Fq 'Milestone programs' core/rules/workflow-orchestration.mdc || err "workflow rule does not describe milestone programs"
grep -Fq 'H-B pre-shell.sh' docs/compliance-matrix.md || err "compliance matrix lacks pre-shell blocking classification"
grep -Fq 'H-W after-edit.sh' docs/compliance-matrix.md || err "compliance matrix lacks after-edit warning classification"

# 15. Agent context ignore file.
ignore="templates/.cursorignore"
[ -f "$ignore" ] || err "missing $ignore"
grep -Fq '!docs/build/' "$ignore" || err "$ignore lacks !docs/build/ negation"
grep -Fq '!docs/verify/' "$ignore" || err "$ignore lacks !docs/verify/ negation"
[ -f templates/.claudeignore ] && err "templates/.claudeignore must be removed (Cursor-only kit)"
[ -f templates/.kiloignore ] && err "templates/.kiloignore must be removed (Cursor-only kit)"

# 16. UI/UX design contracts.
grep -Fq 'ux-designer' core/commands/design.md || err "/design does not launch the ux-designer"
grep -Fq 'docs/design/' core/commands/design.md || err "/design does not name the UX spec path"
grep -Fq 'ux-design' core/rules/workflow-orchestration.mdc || err "workflow rule lacks the UX design gate criteria"
grep -Fq 'docs/design/<feature>/ux-spec.md' core/commands/build.md || err "/build does not require the approved UX spec"
grep -Fq 'mockups/' core/commands/design.md || err "/design does not require HTML mockups"
grep -Fq 'Component defaults' core/skills/ux-design/SKILL.md || err "ux-design skill lacks per-component defaults"
grep -Fq 'mockups/' templates/docs/design/ux-spec.md || err "UX spec template lacks mockup links"
grep -Fq 'ux-report.md' core/commands/verify.md || err "/verify does not name the persisted UX report"
grep -Fq 'axe-core' core/skills/quality-gate/SKILL.md || err "quality-gate lacks the automated a11y check"
grep -Fq 'UX/a11y' core/skills/pr-review/SKILL.md || err "pr-review lacks the UX/a11y checklist item"
grep -Fq 'UX spec' core/skills/implement-frontend/SKILL.md || err "implement-frontend does not implement the UX spec"
grep -Fq 'ux-designer' core/rules/workflow-orchestration.mdc || err "workflow rule does not list the ux-designer for Design"
[ -f core/rules/ux-design.mdc ] || err "core/rules/ux-design.mdc missing"

# 13. Shell syntax.
for f in core/hooks/*.sh templates/ci/*.sh templates/scripts/*.sh scripts/audit-brownfield-baseline.sh; do
  [ -e "$f" ] || continue
  sh -n "$f" || err "$f: shell syntax error"
done
sh -n scripts/install.sh || err "scripts/install.sh: shell syntax error"
sh -n scripts/bootstrap-greenfield.sh || err "scripts/bootstrap-greenfield.sh: shell syntax error"
sh -n scripts/audit-brownfield-baseline.sh || err "scripts/audit-brownfield-baseline.sh: shell syntax error"
[ -f scripts/bootstrap-greenfield.sh ] || err "scripts/bootstrap-greenfield.sh missing"
grep -Fq 'p0-platform-skeleton' scripts/bootstrap-greenfield.sh || err "bootstrap-greenfield.sh does not seed P0 milestone"
grep -Fq 'p5-release-readiness' scripts/bootstrap-greenfield.sh || err "bootstrap-greenfield.sh does not seed P5 milestone"
grep -Fq -- '--profile' scripts/bootstrap-greenfield.sh || err "bootstrap-greenfield.sh does not accept --profile"
grep -Fq 'Directory profiles' core/rules/project-delivery-core.mdc || err "project-delivery-core.mdc does not define directory profiles"
grep -Fq 'resolve-layout.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must resolve the directory profile"
grep -Fq 'backend/pom.xml' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must build an app-profile backend/"
grep -Fq 'lastApprovedPhase' templates/docs/requirements/_state.template.json || err "state template must record lastApprovedPhase"
grep -Fq 'lastApprovedPhase' templates/scripts/sync-feature-state.sh || err "sync-feature-state.sh must derive lastApprovedPhase"
grep -Fq 'Phase resume' core/rules/workflow-orchestration.mdc || err "workflow rule must describe phase resume"
grep -Fq 'Parallel features' core/rules/workflow-orchestration.mdc || err "workflow rule must describe parallel-feature collisions"
grep -Fq 'Parallel features' core/commands/build.md || err "/build must stop on a shared-file collision"
grep -Fq 'Parallel features' core/commands/status.md || err "/status must use the feature the user names"
grep -Fq 'updatedAt' core/hooks/session-start.sh || err "session-start.sh must pick the newest state file by updatedAt"
grep -Fq 'brownfield-onboarding' scripts/audit-brownfield-baseline.sh || err "audit-brownfield-baseline.sh does not reference brownfield onboarding"
grep -Fq 'docker-compose' templates/scripts/run-local-container.sh || err "run-local-container.sh must use docker compose"
grep -Fq 'Dockerfile' templates/scripts/run-local-container.sh || err "run-local-container.sh must support Dockerfile fallback"
grep -Fq 'run-local-container' templates/docs/gold-standards.md || err "gold-standards must document run-local-container.sh"
grep -Fq 'docker-compose.yml' templates/docs/gold-standards.md || err "gold-standards must document docker-compose.yml"
grep -Fq 'scripts/' scripts/install.sh || err "install.sh must chmod seeded scripts"
grep -Fq 'P0-D' templates/docs/milestones/p0-platform-skeleton.md || err "P0 milestone must include local container story P0-D"

# 14. Build-hardening contracts survive in core.
grep -Fq 'TDD' core/skills/implement-spring-service/SKILL.md || err "implement-spring-service lacks the red–green (TDD) requirement"
grep -Fq 'bounded' core/skills/implement-spring-service/SKILL.md || err "implement-spring-service lacks bounded fix attempts"
grep -Fq 'docs/build/' core/agents/backend-engineer.md || err "backend-engineer does not persist build evidence"

# 17. Consistency between prose and the files it describes (catches drift).
agent_count="$(ls core/agents/*.md | wc -l | tr -d ' ')"
command_count="$(ls core/commands/*.md | wc -l | tr -d ' ')"
skill_count="$(ls -d core/skills/*/ | wc -l | tr -d ' ')"
grep -Fq "$agent_count subagents" README.md || err "README.md must say $agent_count subagents"
grep -Fq "$command_count entry points" README.md || err "README.md must say $command_count entry points"
grep -Fq "$skill_count playbooks" README.md || err "README.md must say $skill_count playbooks"
grep -Fq "($agent_count agents)" docs/model-routing-matrix.md || err "routing matrix must say ($agent_count agents)"
for f in core/agents/*.md; do
  name="$(basename "$f" .md)"
  grep -Eq "^\\|[[:space:]]*${name}[[:space:]]*\\|" docs/model-routing-matrix.md || err "$name has no row in the agent mapping of docs/model-routing-matrix.md"
done
# Every skill named as `(skill: x)` or `(skills: x, y)` in a command or agent exists.
for ref in $(grep -rhoE '\(skills?: [^)]*\)' core/commands core/agents | grep -oE '`[a-z-]+`' | tr -d '`' | sort -u); do
  [ -f "core/skills/$ref/SKILL.md" ] || err "a command or agent names skill $ref, which does not exist"
done
# Every engineer agent defers to the loop in its implement-* skill instead of restating it.
grep -Fq 'implement-spring-service` step 6' core/agents/backend-engineer.md || err "backend-engineer must defer to implement-spring-service step 6"
grep -Fq 'implement-bff` step 6' core/agents/bff-engineer.md || err "bff-engineer must defer to implement-bff step 6"
grep -Fq 'implement-frontend` step 6' core/agents/frontend-engineer.md || err "frontend-engineer must defer to implement-frontend step 6"
for f in core/skills/implement-spring-service/SKILL.md core/skills/implement-bff/SKILL.md core/skills/implement-frontend/SKILL.md; do
  grep -Fq 'check-attempt-budget.sh' "$f" || err "$f must run the phase attempt budget check"
done
# GitLab-only kit: conduct rule names glab; must not document GitHub/gh as a supported host.
grep -Fq 'glab' core/rules/ai-agent-conduct.mdc || err "ai-agent-conduct.mdc must name glab (GitLab is the default host)"
grep -Fq 'gh ' core/rules/ai-agent-conduct.mdc && err "ai-agent-conduct.mdc must not reference gh (GitLab-only kit)"
grep -Eiq 'github|pull request via gh' README.md AGENTS.md docs/agents-v0-kit.md && err "kit docs must not advertise GitHub/gh support"

# 18. Scale contracts: planning, ordering, multi-service layout, machine-read gates, budgets.
grep -Fq 'Program planning' core/rules/workflow-orchestration.mdc || err "workflow rule lacks Program planning"
grep -Fq 'Worktree per feature' core/rules/workflow-orchestration.mdc || err "workflow rule lacks the worktree-per-feature convention"
grep -Fq 'Batch approval' core/rules/workflow-orchestration.mdc || err "workflow rule lacks batch approval"
grep -Fq 'Phase attempt budget' core/rules/workflow-orchestration.mdc || err "workflow rule lacks the phase attempt budget"
grep -Fq 'check-gate-metrics' core/rules/workflow-orchestration.mdc || err "workflow rule does not name the machine-read gate metrics"
grep -Fq '`/plan`' core/agents/orchestrator.md || err "orchestrator does not route /plan"
grep -Fq 'program-planning' core/agents/program-planner.md || err "program-planner does not follow program-planning"
grep -Fq 'check_story_order' templates/ci/check-milestone.sh || err "check-milestone does not enforce story order"
grep -Fq 'SERVICE_ROOTS' templates/ci/resolve-layout.sh || err "resolve-layout does not print SERVICE_ROOTS"
grep -Fq 'SERVICE_ROOTS' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must build each service root"
grep -Fq 'services/*/pom.xml' templates/.gitlab-ci.yml || err ".gitlab-ci.yml build rules must include services/*/pom.xml"
grep -Fq 'check-gate-metrics.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run check-gate-metrics.sh"
grep -Fq 'check-event-schemas.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run check-event-schemas.sh"
grep -Fq 'docker:' templates/.gitlab-ci.yml || err ".gitlab-ci.yml build job needs a Docker daemon for Testcontainers"
grep -Fq 'Service roots' templates/docs/project-profile.md || err "project-profile template lacks the Service roots row"
grep -Fq 'Phase attempt budget' templates/docs/project-profile.md || err "project-profile template lacks the Phase attempt budget row"
grep -Fq 'Deploy' templates/docs/project-profile.md || err "project-profile template lacks the Deploy table"
grep -Fq '"worktree"' core/hooks/hook-policy.py || err "hook-policy must ask before creating a worktree"
grep -Fq 'ci/[^/]+' core/hooks/hook-policy.py || err "hook-policy must protect every ci/*.sh script, not a named list"
grep -Fq 'kit.maven.dir' templates/maven/quality-plugins.xml || err "maven quality snippets must read kit.maven.dir (per-service config)"
grep -Fq 'kit.openapi.catalog' templates/maven/contract-conformance.xml || err "contract-conformance must read kit.openapi.catalog (per-service catalog)"
grep -Fq 'Service verify' templates/docs/project-profile.md || err "project-profile template lacks the Service verify rows"
grep -Fq 'FETCH_HEAD:ci/check-gate-metrics.sh' templates/.gitlab-ci.yml || err "gate-metrics job must run the script from the default branch"
[ -f templates/ci/check-layout-roots.sh ] || err "templates/ci/check-layout-roots.sh missing"
grep -Fq 'ci/check-layout-roots.sh' scripts/install.sh || err "install.sh does not seed ci/check-layout-roots.sh"
grep -Fq 'check-layout-roots.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must fail when a JVM module resolves no root"
grep -Fq '\.cursor/(commands|skills)' core/hooks/hook-policy.py || err "hook-policy must protect .cursor commands and skills (phase procedures and gate checklists)"
for dir in /.cursor/commands/ /.cursor/skills/; do
  grep -Fq "$dir @" templates/CODEOWNERS || err "CODEOWNERS must cover $dir"
done
# Onboarding: layout-aware, cited, verified, gated.
for onboard_file in templates/scripts/discover-codebase.sh templates/scripts/check-onboarding-docs.sh templates/docs/onboarding/_report.template.md templates/docs/onboarding/_module.template.md; do
  [ -f "$onboard_file" ] || err "required onboarding file missing: $onboard_file"
done
grep -Fq 'codebase-documenter' core/commands/onboard.md || err "/onboard must launch the codebase-documenter"
grep -Fq 'check-onboarding-docs.sh' core/commands/onboard.md || err "/onboard gate must run check-onboarding-docs.sh"
grep -Fq 'check-onboarding-docs.sh' core/skills/onboard-discovery/SKILL.md || err "onboard-discovery must run check-onboarding-docs.sh"
grep -Fq 'discover-codebase.sh' core/skills/onboard-discovery/SKILL.md || err "onboard-discovery must run discover-codebase.sh"
grep -Fq 'UNVERIFIED' core/agents/codebase-documenter.md || err "codebase-documenter must mark unknowns UNVERIFIED"
grep -Fq 'onboard' templates/ci/check-approvals.sh || err "check-approvals must accept the onboard phase"
grep -Fq 'onboard' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage must check the onboard approval"
grep -Fq 'docs/onboarding/report.md' core/commands/intake.md || err "/intake must wait for the onboard approval on a brownfield repo"
grep -Fq 'docs/onboarding/report.md' core/commands/plan.md || err "/plan must wait for the onboard approval on a brownfield repo"
grep -Fq 'check-onboarding-docs' core/hooks/hook-policy.py || err "hook-policy must protect scripts/check-onboarding-docs.sh"
for onboard_script in discover-codebase.sh check-onboarding-docs.sh; do
  grep -Fq "scripts/$onboard_script" scripts/install.sh || err "install.sh does not seed scripts/$onboard_script"
done
if grep -q 'TEMPLATE:' templates/docs/architecture.md && ! grep -q 'Brownfield' templates/docs/architecture.md; then err "architecture.md template must say /onboard replaces it"; fi
# Maintenance lane: own record, tier confirmed by a person, classifier-qualified, CI-checked.
for maintain_file in templates/ci/classify-change.sh templates/docs/maintain/_note.template.md; do
  [ -f "$maintain_file" ] || err "required maintenance file missing: $maintain_file"
done
grep -Fq 'Maintain-Note' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage must accept a Maintain-Note"
grep -Fq 'classify-change.sh' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage must run the classifier for a trivial note"
grep -Fq 'classify-change.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must fetch classify-change.sh from the default branch"
grep -Fq 'Maintain-Note' templates/.gitlab/merge_request_templates/default.md || err "merge request template must offer Maintain-Note"
grep -Fq 'docs/maintain/' templates/CODEOWNERS || err "CODEOWNERS must cover docs/maintain/"
grep -Fq 'Tier confirmed by' templates/docs/maintain/_note.template.md || err "maintenance note template must require a confirmed tier"
grep -Fq 'Abbreviated Verify' core/commands/verify.md || err "/verify must define the abbreviated Verify"
grep -Fq 'classify-change.sh' core/commands/triage.md || err "/triage must qualify a change with the classifier"
grep -Fq 'classify-change.sh' core/commands/maintain.md || err "/maintain must classify the result"
grep -Fq 'check-attempt-budget.sh' core/commands/maintain.md || err "/maintain must use the attempt budget"
grep -Fq 'docs/maintain/<id>/note.md' core/agents/maintenance-engineer.md || err "maintenance-engineer must work from the maintenance note"
grep -Fq 'graph' core/skills/dependency-upgrade/SKILL.md || err "dependency-upgrade must diff the dependency graph"
grep -Fq 'check-onboarding-docs.sh' core/skills/doc-sync/SKILL.md || err "doc-sync must re-check onboarding citations"
grep -Fq 'maintain' templates/scripts/sync-feature-state.sh || err "sync-feature-state must handle maintenance notes"
for maintain_script in classify-change.sh; do
  grep -Fq "ci/$maintain_script" scripts/install.sh || err "install.sh does not seed ci/$maintain_script"
done
grep -Fq '_note.template.md' scripts/install.sh || err "install.sh does not seed the maintenance note template"
# Design and Build: mechanical checks, an independent review, a pinned design, a real plan.
for design_file in check-openapi.sh check-design.sh check-design-contracts.sh check-ux-spec.sh check-build-plan.sh check-endpoint-auth.sh check-frontend-calls.sh; do
  [ -f "templates/ci/$design_file" ] || err "required Design/Build check missing: templates/ci/$design_file"
  grep -Fq "ci/$design_file" scripts/install.sh || err "install.sh does not seed ci/$design_file"
done
for design_file in docs/design/_design.template.md docs/design/_amendments.template.md; do
  [ -f "templates/$design_file" ] || err "required design template missing: templates/$design_file"
  grep -Fq "$design_file" scripts/install.sh || err "install.sh does not seed $design_file"
done
grep -Fq 'design-reviewer' core/commands/design.md || err "/design must launch the design-reviewer"
grep -Fq 'Amending an approved design' core/commands/design.md || err "/design must define the design amendment path"
grep -Fq 'check-design.sh' core/commands/design.md || err "/design gate must run check-design.sh"
grep -Fq 'check-openapi.sh' core/commands/design.md || err "/design gate must run check-openapi.sh"
grep -Fq 'verify-lock' core/commands/build.md || err "/build must verify the design lock"
grep -Fq 'check-build-plan.sh' core/commands/build.md || err "/build gate must run check-build-plan.sh"
grep -Fq 'check-endpoint-auth.sh' core/commands/build.md || err "/build gate must run check-endpoint-auth.sh"
grep -Fq 'check-frontend-calls.sh' core/commands/build.md || err "/build gate must run check-frontend-calls.sh"
grep -Fq 'ci/check-openapi.sh merged' core/commands/build.md || err "/build must prove the catalog merge"
grep -Fq 'feature_design_and_plan' templates/ci/check-delivery-linkage.sh || err "check-delivery-linkage must check the design lock and the build plan"
grep -Fq 'check-design-contracts.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run the design checks"
grep -Fq 'check-endpoint-auth.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run check-endpoint-auth.sh"
grep -Fq 'check-frontend-calls.sh' templates/.gitlab-ci.yml || err ".gitlab-ci.yml must run check-frontend-calls.sh"
grep -Fq 'spring-boot-maven-plugin' templates/maven/contract-conformance.xml || err "contract-conformance must start the service it reads the spec from"
grep -Fq 'generated-to-approved' templates/maven/contract-conformance.xml || err "contract-conformance must also diff generated against approved (undocumented endpoints)"
grep -Fq '/docs/design/' templates/CODEOWNERS || err "CODEOWNERS must cover docs/design/"
grep -Fq '/openapi/' templates/CODEOWNERS || err "CODEOWNERS must cover openapi/"
grep -Fq 'data-component' core/skills/ux-design/SKILL.md || err "ux-design must require data-component on mockup controls"
grep -Fq 'migration-safety' core/skills/implement-spring-service/SKILL.md || err "implement-spring-service must follow migration-safety for migrations"
grep -Fq 'design-reviewer' docs/model-routing-matrix.md || err "routing matrix lacks the design-reviewer"
# Release and /deliver: thin chain, human merge enforced on the default host, dry run, versioned notes.
for release_file in templates/scripts/render-mr-body.sh templates/scripts/release-notes.sh templates/CHANGELOG.md; do
  [ -f "$release_file" ] || err "required release file missing: $release_file"
done
for release_script in render-mr-body.sh release-notes.sh; do
  grep -Fq "scripts/$release_script" scripts/install.sh || err "install.sh does not seed scripts/$release_script"
done
grep -Fq 'CHANGELOG.md' scripts/install.sh || err "install.sh does not seed CHANGELOG.md"
grep -Fq 'bin0 == "glab"' core/hooks/hook-policy.py || err "hook-policy must cover glab (merge and approve are human acts)"
grep -Fq 'sub == "tag"' core/hooks/hook-policy.py || err "hook-policy must ask before creating a git tag"
grep -Fq 'render-mr-body.sh' core/commands/release.md || err "/release must render the MR description from the evidence"
grep -Fq 'check-delivery-linkage.sh' core/commands/release.md || err "/release must dry-run the delivery gate locally"
grep -Fq 'GitLab username' core/commands/release.md || err "/release must record the GitLab username as the release Approver"
grep -Fq 'glab ci trigger delivery-approval' core/commands/release.md || err "/release must say how the delivery-approval job is played"
grep -Fq 'three rounds' core/commands/release.md || err "/release must cap the CI fix loop"
grep -Fq 'docs-only follow-up' core/commands/release.md || err "/release must keep deploy records off the default branch"
grep -Fq 'release-notes.sh' core/commands/release.md || err "/release must produce release notes"
for phase_command in intake design build verify release; do
  grep -Fq "\`/$phase_command\`" core/commands/deliver.md || err "/deliver must run /$phase_command rather than restate it"
done
grep -Fq 'Re-opened' core/commands/deliver.md || err "/deliver must define re-entry after a Critical"
grep -Fqi 'subagents cannot launch subagents' core/commands/deliver.md || err "/deliver must state the fallback when subagents cannot launch subagents"
if [ "$(wc -l < core/commands/deliver.md | tr -d ' ')" -gt 60 ]; then err "/deliver has grown past 60 lines: it should point at the phase commands, not restate them"; fi
grep -Fq '## Maintenance change' core/commands/release.md || err "/release must handle a maintenance note"
grep -Fq 'GitLab username' core/commands/verify.md || err "/verify must record the GitLab username as the approver"
grep -Fq 'GitLab username' core/commands/maintain.md || err "/maintain must record the GitLab username as the approver"
grep -Fq 'docs/maintain/*/state.json' core/commands/status.md || err "/status must read maintenance state files"
grep -Fq 'check-design.sh' core/commands/status.md || err "/status must report a drifted design lock"
grep -Fq 'check-gate-metrics.sh' core/commands/verify.md || err "/verify must run the machine checks CI runs"
grep -Fq 'Service root:' core/commands/intake.md || err "/intake gate must record Service root for a multi-service repo"
grep -Fq 'Dependency column' core/commands/intake.md || err "/intake must check milestone story order"
for cmd in onboard plan; do
  grep -Fq '## Collision' "core/commands/$cmd.md" || err "/$cmd must stop on a shared-file collision"
done
for cmd in design build verify; do
  grep -Fq 'Re-opened' "core/commands/$cmd.md" || err "/$cmd must say what a Re-opened approval row means"
done
grep -Fq 'Release owner' templates/docs/project-profile.md || err "project-profile template lacks the Release rows"
# Always-on context budget: the rules every session loads must not creep past this size.
always_on_bytes="$(cat core/rules/workflow-orchestration.mdc core/rules/project-delivery-core.mdc core/rules/ai-agent-conduct.mdc AGENTS.md | wc -c | tr -d ' ')"
[ "$always_on_bytes" -le 32000 ] || err "always-on rules are $always_on_bytes bytes (limit 32000): move detail into a command, agent, or skill"
for ci_script in check-gate-metrics.sh check-event-schemas.sh; do
  grep -Fq "ci/$ci_script" scripts/install.sh || err "install.sh does not seed ci/$ci_script"
done
for sc_script in feature-worktree.sh check-attempt-budget.sh; do
  grep -Fq "scripts/$sc_script" scripts/install.sh || err "install.sh does not seed scripts/$sc_script"
done

if [ "$TARGET_MODE" = 1 ]; then
  validate_target "$TARGET_DIR"
fi

if [ "$fail" -eq 1 ]; then
  echo "validate-kit: FAILED" >&2
  exit 1
fi
if [ "$TARGET_MODE" = 1 ]; then
  echo "validate-kit: OK (kit + target $TARGET_DIR; Cursor model availability not checked)"
else
  echo "validate-kit: OK (Cursor model availability not checked)"
fi