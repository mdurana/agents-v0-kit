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
  for doc in docs/compliance-matrix.md docs/model-routing-matrix.md docs/user-guide.md docs/agents-v0-kit.md docs/greenfield-onboarding.md docs/brownfield-onboarding.md; do
    [ -f "$KIT/$doc" ] || { printf 'error: missing %s\n' "$KIT/$doc" >&2; exit 1; }
    mkdir -p "$KIT/templates/$(dirname "$doc")"
    cp "$KIT/$doc" "$KIT/templates/$doc"
  done
  printf 'Synced kit docs -> templates/\n'
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
}

install_templates() {
  t="$1"
  [ -f "$t/README.md" ] || cp "$KIT/README.md" "$t/README.md"
  [ -f "$t/.gitignore" ] || cp "$KIT/templates/.gitignore" "$t/.gitignore"
  minimal="
.gitignore
.gitlab-ci.yml
.gitlab/merge_request_templates/default.md
CODEOWNERS
ci/check-approvals.sh
ci/check-evidence.sh
ci/check-milestone.sh
ci/check-delivery-linkage.sh
ci/check-approver-gitlab.sh
ci/check-coverage-ratchet.sh
ci/check-gate-metrics.sh
ci/check-event-schemas.sh
ci/check-layout-roots.sh
docs/compliance-matrix.md
docs/model-routing-matrix.md
docs/user-guide.md
docs/agents-v0-kit.md
docs/greenfield-onboarding.md
docs/brownfield-onboarding.md
docs/project-profile.md
docs/repo-map.md
ci/check-known-failures.sh
ci/resolve-layout.sh
scripts/generate-repo-map.sh
scripts/collect-dependency-graphs.sh
scripts/sync-feature-state.sh
scripts/delivery-metrics.sh
scripts/feature-worktree.sh
scripts/check-attempt-budget.sh
scripts/discover-codebase.sh
scripts/check-onboarding-docs.sh
docs/onboarding/_report.template.md
docs/onboarding/_module.template.md
docs/maintain/_note.template.md
ci/classify-change.sh
ci/check-openapi.sh
ci/check-design.sh
ci/check-design-contracts.sh
ci/check-ux-spec.sh
ci/check-build-plan.sh
ci/check-endpoint-auth.sh
ci/check-frontend-calls.sh
docs/design/_design.template.md
docs/design/_amendments.template.md
scripts/render-mr-body.sh
scripts/release-notes.sh
scripts/check-delivery-gate-local.sh
scripts/verify-gitlab-ci-prereqs.sh
hooks/pre-push
CHANGELOG.md
docs/architecture.md
docs/network.md
ci/check-feature-state.sh
"
  copy_template_file() {
    rel="$1"
    dest="$t/$rel"
    overwrite=0
    if [ "$UPDATE" = 1 ]; then
        for always in docs/compliance-matrix.md docs/model-routing-matrix.md docs/user-guide.md docs/agents-v0-kit.md docs/greenfield-onboarding.md docs/brownfield-onboarding.md ci/check-approvals.sh ci/check-evidence.sh ci/check-milestone.sh ci/check-delivery-linkage.sh ci/check-approver-gitlab.sh ci/check-coverage-ratchet.sh ci/check-known-failures.sh ci/resolve-layout.sh ci/check-feature-state.sh ci/check-gate-metrics.sh ci/check-event-schemas.sh ci/check-layout-roots.sh scripts/check-attempt-budget.sh scripts/generate-repo-map.sh scripts/collect-dependency-graphs.sh scripts/discover-codebase.sh scripts/check-onboarding-docs.sh scripts/sync-feature-state.sh scripts/delivery-metrics.sh docs/onboarding/_report.template.md docs/onboarding/_module.template.md docs/maintain/_note.template.md ci/classify-change.sh ci/check-openapi.sh ci/check-design.sh ci/check-design-contracts.sh ci/check-ux-spec.sh ci/check-build-plan.sh ci/check-endpoint-auth.sh ci/check-frontend-calls.sh docs/design/_design.template.md docs/design/_amendments.template.md scripts/render-mr-body.sh scripts/release-notes.sh scripts/check-delivery-gate-local.sh scripts/verify-gitlab-ci-prereqs.sh hooks/pre-push .gitlab-ci.yml .gitlab/merge_request_templates/default.md; do
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
  chmod +x "$t/ci/"*.sh 2>/dev/null || true
  chmod +x "$t/scripts/"*.sh 2>/dev/null || true
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
    printf 'Kit repo: docs synced to templates/; validate-kit passed.\n'
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
if [ -f "$TARGET_ABS/CODEOWNERS" ] && grep -q '@your-team' "$TARGET_ABS/CODEOWNERS"; then
  printf 'WARN: CODEOWNERS still uses the @your-team placeholder — replace it with a real GitLab group and enable Code Owner approval, including /.gitlab-ci.yml. Scope GITLAB_TOKEN to the delivery-approval environment (read_api, masked), or that token is visible to every job.\n' >&2
fi
printf 'Next: model routing per docs/model-routing-matrix.md; wire ci/check-approvals.sh + ci/check-evidence.sh into CI (see templates/.gitlab-ci.yml).\n'
printf 'Greenfield: %s/bootstrap-greenfield.sh — see docs/greenfield-onboarding.md. Brownfield: %s/audit-brownfield-baseline.sh — see docs/brownfield-onboarding.md.\n' "$(dirname "$0")" "$(dirname "$0")"
if [ "$UPDATE" = 0 ]; then
  printf 'To refresh after kit changes: %s --update <target-repo>\n' "$(basename "$0")"
fi
