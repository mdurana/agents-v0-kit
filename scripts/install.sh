#!/bin/sh
# install.sh — install the agents-v0 delivery kit into a target repo.
# Vendor-neutral core with per-tool adapters: Cursor (.cursor/), Kilo Code (.kilo/),
# Claude Code (.claude/).
#
# Usage:
#   install.sh [--tool cursor|kilo|claude|all] <target-repo>
#       First install: seeds adapter trees, project templates, and entry files
#       (AGENTS.md / CLAUDE.md / .kilo/kilo.json) only where missing.
#
#   install.sh [--tool ...] [--with-starters] <target-repo>
#       Default templates: CI, GitHub workflows, reference docs, project-profile.
#       --with-starters also seeds maven/, docker/, openapi/, and other starters.
#
#   install.sh [--tool ...] --update <target-repo>
#       Syncs kit docs -> templates/, runs validate-kit.sh, then refreshes
#       kit-managed files (rules, agents, commands, skills, hooks, CI scripts,
#       reference docs). Target-owned files (AGENTS.md, CLAUDE.md, kilo.json,
#       project templates) are seeded only when missing, never
#       clobbered.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="all"
UPDATE=0
WITH_STARTERS=0
TARGET=""

usage() {
  printf 'usage: %s [--tool cursor|kilo|claude|all] [--with-starters] [--update] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

# Claude Code: `tools:` is a comma-separated string of Claude tool names.
map_claude_tools() {
  awk '
    function cname(t) {
      if (t == "read") return "Read"; if (t == "grep") return "Grep"; if (t == "glob") return "Glob"
      if (t == "edit") return "Edit, MultiEdit"; if (t == "write") return "Write"
      if (t == "shell") return "Bash"; if (t == "task") return "Task"
      return t
    }
    /^tools:[[:space:]]*$/ { intools = 1; list = ""; next }
    intools && /^  - / { t = $0; sub(/^  - /, "", t); list = list (list == "" ? "" : ", ") cname(t); next }
    intools { print "tools: " list; intools = 0 }
    { print }
  '
}

# Kilo Code: `tools:` is a boolean map; tools absent from the kit list are disabled.
map_kilo_tools() {
  awk '
    /^tools:[[:space:]]*$/ { intools = 1; delete have; next }
    intools && /^  - / { t = $0; sub(/^  - /, "", t); have[t] = 1; next }
    intools {
      print "tools:"
      print "  write: " (("write" in have) ? "true" : "false")
      print "  edit: " (("edit" in have) ? "true" : "false")
      print "  patch: " (("edit" in have) ? "true" : "false")
      print "  bash: " (("shell" in have) ? "true" : "false")
      print "  task: " (("task" in have) ? "true" : "false")
      intools = 0
    }
    { print }
  '
}

sync_templates_from_docs() {
  for doc in docs/compliance-matrix.md docs/model-routing-matrix.md docs/user-guide.md docs/greenfield-onboarding.md docs/brownfield-onboarding.md docs/mcp-baseline.md; do
    [ -f "$KIT/$doc" ] || { printf 'error: missing %s\n' "$KIT/$doc" >&2; exit 1; }
    mkdir -p "$KIT/templates/$(dirname "$doc")"
    cp "$KIT/$doc" "$KIT/templates/$doc"
  done
  printf 'Synced kit docs -> templates/\n'
}

# --- Frontmatter helpers ---------------------------------------------------

# Strip a leading --- frontmatter block.
strip_frontmatter() {
  awk 'NR==1 && /^---[[:space:]]*$/{fm=1; next} fm && /^---[[:space:]]*$/{fm=0; next} fm{next} {print}' "$1"
}

# Emit an agent file for a tool: keep shared keys, swap model, drop foreign keys.
emit_agent() {
  src="$1"
  dst="$2"
  tool="$3"
  if [ "$tool" = "cursor" ]; then
    grep -Ev '^(mode|model_kilo|model_claude):' "$src" > "$dst"
  elif [ "$tool" = "kilo" ]; then
    km="$(grep -E '^model_kilo:' "$src" | head -n1 | sed 's/^model_kilo:[[:space:]]*//')"
    awk -v km="$km" '
      /^model:/ { if (km != "") print "model: " km; next }
      /^(model_kilo|model_claude):/ { next }
      { print }' "$src" | map_kilo_tools > "$dst"
  else
    cm="$(grep -E '^model_claude:' "$src" | head -n1 | sed 's/^model_claude:[[:space:]]*//')"
    awk -v cm="$cm" '
      /^model:/ { if (cm != "") print "model: " cm; next }
      /^(model_kilo|model_claude|mode):/ { next }
      { print }' "$src" | map_claude_tools > "$dst"
  fi
}

# Emit a command file for a tool (Cursor commands carry no frontmatter).
emit_command() {
  src="$1"
  dst="$2"
  tool="$3"
  if [ "$tool" = "cursor" ]; then
    strip_frontmatter "$src" > "$dst"
  else
    cp "$src" "$dst"
  fi
}

install_rules() {
  dstdir="$1"
  tool="$2"
  ext="$3"
  mkdir -p "$dstdir"
  for f in "$KIT"/core/rules/*.mdc; do
    name="$(basename "$f" .mdc)"
    if [ "$tool" = "cursor" ]; then
      cp "$f" "$dstdir/$name.$ext"
    else
      strip_frontmatter "$f" > "$dstdir/$name.md"
    fi
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
  install_rules "$t/.cursor/rules/org" cursor mdc
  for f in "$KIT"/core/agents/*.md; do
    emit_agent "$f" "$t/.cursor/agents/$(basename "$f")" cursor
  done
  for f in "$KIT"/core/commands/*.md; do
    emit_command "$f" "$t/.cursor/commands/$(basename "$f")" cursor
  done
  install_skills "$t/.cursor/skills"
  cp "$KIT"/core/hooks/*.sh "$KIT"/core/hooks/hook-policy.py "$t/.cursor/hooks/"
  [ -f "$t/.cursor/hooks/mcp-policy.json" ] || cp "$KIT/core/hooks/mcp-policy.json" "$t/.cursor/hooks/mcp-policy.json"
  chmod +x "$t"/.cursor/hooks/*.sh "$t/.cursor/hooks/hook-policy.py"
  cp "$KIT/core/adapters/cursor/hooks.json" "$t/.cursor/hooks.json"
}

install_kilo() {
  t="$1"
  seed_agent_ignore "$t" .kiloignore
  mkdir -p "$t/.kilo/command" "$t/.kilo/agent" "$t/.kilo/skills" "$t/.kilo/rules"
  install_rules "$t/.kilo/rules" kilo md
  for f in "$KIT"/core/agents/*.md; do
    emit_agent "$f" "$t/.kilo/agent/$(basename "$f")" kilo
  done
  for f in "$KIT"/core/commands/*.md; do
    emit_command "$f" "$t/.kilo/command/$(basename "$f")" kilo
  done
  install_skills "$t/.kilo/skills"
  [ -f "$t/AGENTS.md" ] || cp "$KIT/AGENTS.md" "$t/AGENTS.md"
  if [ -f "$t/.kilo/kilo.json" ]; then
    printf 'note: %s/.kilo/kilo.json exists — merge "instructions" and "permission" from %s/core/adapters/kilo/kilo.json\n' "$t" "$KIT" >&2
  else
    cp "$KIT/core/adapters/kilo/kilo.json" "$t/.kilo/kilo.json"
  fi
}

install_claude() {
  t="$1"
  seed_agent_ignore "$t" .claudeignore
  mkdir -p "$t/.claude/commands" "$t/.claude/agents" "$t/.claude/skills" "$t/.claude/rules" "$t/.claude/hooks"
  install_rules "$t/.claude/rules" claude md
  for f in "$KIT"/core/agents/*.md; do
    emit_agent "$f" "$t/.claude/agents/$(basename "$f")" claude
  done
  for f in "$KIT"/core/commands/*.md; do
    emit_command "$f" "$t/.claude/commands/$(basename "$f")" claude
  done
  install_skills "$t/.claude/skills"
  cp "$KIT"/core/hooks/*.sh "$KIT"/core/hooks/hook-policy.py "$t/.claude/hooks/"
  [ -f "$t/.claude/hooks/mcp-policy.json" ] || cp "$KIT/core/hooks/mcp-policy.json" "$t/.claude/hooks/mcp-policy.json"
  chmod +x "$t"/.claude/hooks/*.sh "$t/.claude/hooks/hook-policy.py"
  if [ -f "$t/.claude/settings.json" ]; then
    printf 'note: %s/.claude/settings.json exists — merge "hooks" from %s/core/adapters/claude/settings.json\n' "$t" "$KIT" >&2
  else
    cp "$KIT/core/adapters/claude/settings.json" "$t/.claude/settings.json"
  fi
  if [ ! -f "$t/CLAUDE.md" ]; then
    cp "$KIT/AGENTS.md" "$t/CLAUDE.md"
    printf '\n## Rules (auto-imported)\n\n' >> "$t/CLAUDE.md"
    for f in "$KIT"/core/rules/*.mdc; do
      printf '@.claude/rules/%s.md\n' "$(basename "$f" .mdc)" >> "$t/CLAUDE.md"
    done
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
.github/pull_request_template.md
.github/workflows/delivery-approvals.yml
.github/workflows/build-and-security.yml
CODEOWNERS
ci/check-approvals.sh
ci/check-evidence.sh
ci/check-milestone.sh
ci/check-delivery-linkage.sh
ci/check-approver-github.sh
ci/check-approver-gitlab.sh
ci/check-coverage-ratchet.sh
docs/compliance-matrix.md
docs/model-routing-matrix.md
docs/user-guide.md
docs/greenfield-onboarding.md
docs/brownfield-onboarding.md
docs/project-profile.md
docs/mcp-baseline.md
docs/repo-map.md
ci/check-known-failures.sh
ci/resolve-layout.sh
scripts/generate-repo-map.sh
scripts/collect-dependency-graphs.sh
scripts/sync-feature-state.sh
scripts/delivery-metrics.sh
ci/check-feature-state.sh
"
  copy_template_file() {
    rel="$1"
    dest="$t/$rel"
    overwrite=0
    if [ "$UPDATE" = 1 ]; then
        for always in docs/compliance-matrix.md docs/model-routing-matrix.md docs/user-guide.md docs/greenfield-onboarding.md docs/brownfield-onboarding.md docs/mcp-baseline.md ci/check-approvals.sh ci/check-evidence.sh ci/check-milestone.sh ci/check-delivery-linkage.sh ci/check-approver-github.sh ci/check-approver-gitlab.sh ci/check-coverage-ratchet.sh ci/check-known-failures.sh ci/resolve-layout.sh ci/check-feature-state.sh .gitlab-ci.yml .gitlab/merge_request_templates/default.md .github/workflows/delivery-approvals.yml .github/workflows/build-and-security.yml; do
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
    --tool)
      [ $# -ge 2 ] || usage
      TOOL="$2"
      shift 2
      ;;
    --update)
      UPDATE=1
      shift
      ;;
    --with-starters)
      WITH_STARTERS=1
      shift
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

case "$TOOL" in
  cursor|kilo|claude|all) ;;
  *)
    printf 'error: unknown tool: %s\n' "$TOOL" >&2
    usage
    ;;
esac
[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { printf 'error: target not found: %s\n' "$TARGET" >&2; exit 1; }
TARGET_ABS="$(cd "$TARGET" && pwd)"

if [ "$UPDATE" = 1 ]; then
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

case "$TOOL" in
  cursor|all) install_cursor "$TARGET_ABS" ;;
esac
case "$TOOL" in
  kilo|all) install_kilo "$TARGET_ABS" ;;
esac
case "$TOOL" in
  claude|all) install_claude "$TARGET_ABS" ;;
esac
install_templates "$TARGET_ABS"

if [ -f "$KIT/VERSION" ]; then
  cp "$KIT/VERSION" "$TARGET_ABS/.agents-kit-version"
fi

printf 'Installed agents-v0 (%s) into %s\n' "$TOOL" "$TARGET_ABS"
if [ -f "$TARGET_ABS/CODEOWNERS" ] && grep -q '@your-team' "$TARGET_ABS/CODEOWNERS"; then
  printf 'WARN: CODEOWNERS still uses the @your-team placeholder — replace it with a real GitLab group and enable Code Owner approval, including /.gitlab-ci.yml. Scope GITLAB_TOKEN to the delivery-approval environment (read_api, masked), or that token is visible to every job.\n' >&2
fi
printf 'Next: model routing per docs/model-routing-matrix.md; wire ci/check-approvals.sh + ci/check-evidence.sh into CI (example: .github/workflows/delivery-approvals.yml).\n'
printf 'Greenfield: %s/bootstrap-greenfield.sh — see docs/greenfield-onboarding.md. Brownfield: %s/audit-brownfield-baseline.sh — see docs/brownfield-onboarding.md.\n' "$(dirname "$0")" "$(dirname "$0")"
if [ "$UPDATE" = 0 ]; then
  printf 'To refresh after kit changes: %s --update <target-repo>\n' "$(basename "$0")"
fi