#!/bin/sh
# install.sh — install the agents-v0 delivery kit into a target repo (Cursor).
#
# Usage:
#   install.sh [--with-starters] <target-repo>
#       First install: seeds .cursor/ adapter tree and project templates only where missing.
#
#   install.sh --update <target-repo>
#       Syncs kit docs -> templates/, runs validate-kit.sh, then refreshes
#       kit-managed files (rules, agents, commands, skills, hooks, CI scripts,
#       reference docs). Target-owned templates are seeded only when missing.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE=0
WITH_STARTERS=0
TARGET=""

usage() {
  printf 'usage: %s [--with-starters] [--update] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

sync_templates_from_docs() {
  for doc in compliance-matrix.md model-routing-matrix.md user-guide.md agents-v0-kit.md greenfield-onboarding.md brownfield-onboarding.md benchmark/reference-project.md; do
    src="$KIT/docs/$doc"
    [ -f "$src" ] || { printf 'error: missing %s\n' "$src" >&2; exit 1; }
    mkdir -p "$KIT/templates/docs/agents-v0/$(dirname "$doc")"
    cp "$src" "$KIT/templates/docs/agents-v0/$doc"
  done
  printf 'Synced kit docs -> templates/docs/agents-v0/\n'
}

strip_frontmatter() {
  awk 'NR==1 && /^---[[:space:]]*$/{fm=1; next} fm && /^---[[:space:]]*$/{fm=0; next} fm{next} {print}' "$1"
}

emit_agent() {
  src="$1"
  dst="$2"
  target_root="$3"
  python3 - "$src" "$dst" "$target_root" "$KIT/core/model-roles.tsv" <<'PY'
import json, os, sys
src, dst, target_root, roles_path = sys.argv[1:5]
roles = {}
with open(roles_path, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, role = line.split()
        roles[name] = role
name = os.path.splitext(os.path.basename(src))[0]
role = roles.get(name, "")
override = os.environ.get(f"KIT_MODEL_{role.upper()}", "").strip() if role else ""
cfg = os.path.join(target_root, ".cursor", "model-config.json")
if not override and role and os.path.isfile(cfg):
    with open(cfg, encoding="utf-8") as handle:
        override = str((json.load(handle).get(role) or "")).strip()
out = []
for line in open(src, encoding="utf-8"):
    if line.startswith(("mode:", "model_kilo:", "model_claude:")):
        continue
    if override and line.startswith("model:"):
        out.append(f"model: {override}\n")
    else:
        out.append(line)
with open(dst, "w", encoding="utf-8") as handle:
    handle.writelines(out)
PY
}

emit_command() {
  src="$1"
  dst="$2"
  strip_frontmatter "$src" > "$dst"
}

install_rules() {
  dstdir="$1"
  mkdir -p "$dstdir"
  for f in "$KIT"/core/rules/*.mdc; do
    name="$(basename "$f" .mdc)"
    cp "$f" "$dstdir/$name.mdc"
  done
}

install_skills() {
  dstdir="$1"
  mkdir -p "$dstdir"
  for skill_dir in "$KIT"/core/skills/*/; do
    name="$(basename "$skill_dir")"
    mkdir -p "$dstdir/$name"
    cp "$skill_dir/SKILL.md" "$dstdir/$name/SKILL.md"
  done
}

seed_agent_ignore() {
  t="$1"
  name="$2"
  src="$KIT/templates/$name"
  [ -f "$src" ] || return 0
  [ -f "$t/$name" ] || cp "$src" "$t/$name"
}

install_cursor() {
  t="$1"
  seed_agent_ignore "$t" .cursorignore
  mkdir -p "$t/.cursor/rules/org" "$t/.cursor/agents" "$t/.cursor/commands" "$t/.cursor/skills" "$t/.cursor/hooks"
  install_rules "$t/.cursor/rules/org"
  for f in "$KIT"/core/agents/*.md; do
    emit_agent "$f" "$t/.cursor/agents/$(basename "$f")" "$t"
  done
  for f in "$KIT"/core/commands/*.md; do
    emit_command "$f" "$t/.cursor/commands/$(basename "$f")"
  done
  install_skills "$t/.cursor/skills"
  cp "$KIT"/core/hooks/*.sh "$KIT"/core/hooks/hook-policy.py "$t/.cursor/hooks/"
  rm -f "$t/.cursor/hooks/pre-mcp.sh" "$t/.cursor/hooks/mcp-policy.json"
  chmod +x "$t"/.cursor/hooks/*.sh "$t/.cursor/hooks/hook-policy.py"
  cp "$KIT/core/adapters/cursor/hooks.json" "$t/.cursor/hooks.json"
  if [ -f "$KIT/templates/.cursor/model-config.json.example" ]; then
    cp "$KIT/templates/.cursor/model-config.json.example" "$t/.cursor/model-config.json.example"
  fi
}

install_templates() {
  t="$1"
  [ -f "$t/README.md" ] || cp "$KIT/README.md" "$t/README.md"
  [ -f "$t/.gitignore" ] || cp "$KIT/templates/.gitignore" "$t/.gitignore"
  minimal="
.gitignore
.gitlab-ci.yml
.gitlab/merge_request_templates/default.md
.gitlab/CODEOWNERS
.agents-v0/ci/check-approvals.sh
.agents-v0/ci/check-evidence.sh
.agents-v0/ci/check-milestone.sh
.agents-v0/ci/check-delivery-linkage.sh
.agents-v0/ci/check-approver-gitlab.sh
.agents-v0/ci/check-coverage-ratchet.sh
.agents-v0/ci/check-gate-metrics.sh
.agents-v0/ci/check-event-schemas.sh
.agents-v0/ci/check-layout-roots.sh
.agents-v0/ci/check-known-failures.sh
.agents-v0/ci/resolve-layout.sh
.agents-v0/ci/classify-change.sh
.agents-v0/ci/check-openapi.sh
.agents-v0/ci/check-design.sh
.agents-v0/ci/check-design-contracts.sh
.agents-v0/ci/check-ux-spec.sh
.agents-v0/ci/check-build-plan.sh
.agents-v0/ci/check-endpoint-auth.sh
.agents-v0/ci/check-frontend-calls.sh
.agents-v0/ci/check-asyncapi.sh
.agents-v0/ci/check-feature-state.sh
.agents-v0/scripts/generate-repo-map.sh
.agents-v0/scripts/collect-dependency-graphs.sh
.agents-v0/scripts/sync-feature-state.sh
.agents-v0/scripts/delivery-metrics.sh
.agents-v0/scripts/feature-worktree.sh
.agents-v0/scripts/check-attempt-budget.sh
.agents-v0/scripts/discover-codebase.sh
.agents-v0/scripts/check-onboarding-docs.sh
.agents-v0/scripts/render-mr-body.sh
.agents-v0/scripts/release-notes.sh
.agents-v0/scripts/check-delivery-gate-local.sh
.agents-v0/scripts/verify-gitlab-ci-prereqs.sh
.agents-v0/scripts/export-audit-pack.sh
.agents-v0/hooks/pre-push
docs/agents-v0/compliance-matrix.md
docs/agents-v0/model-routing-matrix.md
docs/agents-v0/user-guide.md
docs/agents-v0/agents-v0-kit.md
docs/agents-v0/greenfield-onboarding.md
docs/agents-v0/brownfield-onboarding.md
docs/agents-v0/benchmark/reference-project.md
docs/agents-v0/project-profile.md
docs/agents-v0/repo-map.md
docs/agents-v0/onboarding/_report.template.md
docs/agents-v0/onboarding/_module.template.md
docs/agents-v0/maintain/_note.template.md
docs/agents-v0/design/_design.template.md
docs/agents-v0/design/_amendments.template.md
docs/agents-v0/architecture.md
docs/agents-v0/network.md
CHANGELOG.md
"
  always_on_update="
docs/agents-v0/compliance-matrix.md
docs/agents-v0/model-routing-matrix.md
docs/agents-v0/user-guide.md
docs/agents-v0/agents-v0-kit.md
docs/agents-v0/greenfield-onboarding.md
docs/agents-v0/brownfield-onboarding.md
docs/agents-v0/benchmark/reference-project.md
.gitlab-ci.yml
.gitlab/merge_request_templates/default.md
.agents-v0/hooks/pre-push
"
  copy_template_file() {
    rel="$1"
    dest="$t/$rel"
    overwrite=0
    if [ "$UPDATE" = 1 ]; then
      for always in $always_on_update \
        .agents-v0/ci/check-approvals.sh .agents-v0/ci/check-evidence.sh .agents-v0/ci/check-milestone.sh \
        .agents-v0/ci/check-delivery-linkage.sh .agents-v0/ci/check-approver-gitlab.sh .agents-v0/ci/check-coverage-ratchet.sh \
        .agents-v0/ci/check-known-failures.sh .agents-v0/ci/resolve-layout.sh .agents-v0/ci/check-feature-state.sh \
        .agents-v0/ci/check-gate-metrics.sh .agents-v0/ci/check-event-schemas.sh .agents-v0/ci/check-layout-roots.sh \
        .agents-v0/scripts/check-attempt-budget.sh .agents-v0/scripts/generate-repo-map.sh .agents-v0/scripts/collect-dependency-graphs.sh \
        .agents-v0/scripts/discover-codebase.sh .agents-v0/scripts/check-onboarding-docs.sh .agents-v0/scripts/sync-feature-state.sh \
        .agents-v0/scripts/delivery-metrics.sh docs/agents-v0/onboarding/_report.template.md docs/agents-v0/onboarding/_module.template.md \
        docs/agents-v0/maintain/_note.template.md .agents-v0/ci/classify-change.sh .agents-v0/ci/check-openapi.sh .agents-v0/ci/check-design.sh \
        .agents-v0/ci/check-design-contracts.sh .agents-v0/ci/check-ux-spec.sh .agents-v0/ci/check-build-plan.sh .agents-v0/ci/check-endpoint-auth.sh \
        .agents-v0/ci/check-frontend-calls.sh .agents-v0/ci/check-asyncapi.sh docs/agents-v0/design/_design.template.md docs/agents-v0/design/_amendments.template.md \
        .agents-v0/scripts/render-mr-body.sh .agents-v0/scripts/release-notes.sh .agents-v0/scripts/check-delivery-gate-local.sh \
        .agents-v0/scripts/verify-gitlab-ci-prereqs.sh .agents-v0/scripts/export-audit-pack.sh; do
        [ "$rel" = "$always" ] && overwrite=1 && break
      done
    fi
    if [ "$overwrite" = 1 ] || [ ! -f "$dest" ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$KIT/templates/$rel" "$dest"
    fi
  }
  if [ "$WITH_STARTERS" = 1 ]; then
    (
      cd "$KIT/templates"
      find . -type f ! -name '.DS_Store' | while IFS= read -r f; do
        copy_template_file "${f#./}"
      done
    )
  else
    printf '%s' "$minimal" | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -f "$KIT/templates/$rel" ] || continue
      copy_template_file "$rel"
    done
  fi
  chmod +x "$t/.agents-v0/ci/"*.sh 2>/dev/null || true
  chmod +x "$t/.agents-v0/scripts/"*.sh 2>/dev/null || true
}

while [ $# -gt 0 ]; do
  case "$1" in
    --update)
      UPDATE=1
      shift
      ;;
    --with-starters)
      WITH_STARTERS=1
      shift
      ;;
    --tool)
      printf 'error: --tool is removed; this kit installs Cursor only (.cursor/)\n' >&2
      exit 1
      ;;
    -h|--help)
      usage
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { printf 'error: target not found: %s\n' "$TARGET" >&2; exit 1; }
TARGET_ABS="$(cd "$TARGET" && pwd)"

require_pyyaml() {
  python3 -c 'import yaml' >/dev/null 2>&1 || {
    printf 'error: PyYAML is required for OpenAPI checks. Install it with: pip install pyyaml   or: apk add py3-yaml\n' >&2
    exit 1
  }
}

if [ "$UPDATE" = 1 ]; then
  require_pyyaml
  sync_templates_from_docs
  "$KIT/scripts/validate-kit.sh"
  if [ "$TARGET_ABS" = "$KIT" ]; then
    printf 'Kit repo: docs synced to templates/docs/agents-v0/; validate-kit passed.\n'
    exit 0
  fi
fi
if [ "$TARGET_ABS" = "$KIT" ]; then
  printf 'error: use --update when target is the kit repo\n' >&2
  exit 1
fi

require_pyyaml
install_cursor "$TARGET_ABS"
install_templates "$TARGET_ABS"

if [ -f "$KIT/VERSION" ]; then
  cp "$KIT/VERSION" "$TARGET_ABS/.agents-kit-version"
fi

printf 'Installed agents-v0 (cursor) into %s\n' "$TARGET_ABS"
if [ -f "$TARGET_ABS/.gitlab/CODEOWNERS" ] && grep -q '@your-team' "$TARGET_ABS/.gitlab/CODEOWNERS"; then
  printf 'WARN: .gitlab/CODEOWNERS still uses the @your-team placeholder — replace it with a real GitLab group and enable Code Owner approval, including /.gitlab-ci.yml. Scope GITLAB_TOKEN to the delivery-approval environment (read_api, masked), or that token is visible to every job.\n' >&2
fi
printf 'Next: model routing per docs/agents-v0/model-routing-matrix.md; wire .agents-v0/ci/check-approvals.sh + .agents-v0/ci/check-evidence.sh into CI (see templates/.gitlab-ci.yml).\n'
printf 'Greenfield: %s/bootstrap-greenfield.sh — see docs/agents-v0/greenfield-onboarding.md. Brownfield: %s/audit-brownfield-baseline.sh — see docs/agents-v0/brownfield-onboarding.md.\n' "$(dirname "$0")" "$(dirname "$0")"
if [ "$UPDATE" = 0 ]; then
  printf 'To refresh after kit changes: %s --update <target-repo>\n' "$(basename "$0")"
fi
