#!/bin/sh
# install.sh — install the agents-v0 delivery kit into a target repo (Cursor).
#
# Usage:
#   install.sh [--pack <id>] [--with-starters] <target-repo>
#       First install: seeds .cursor/ adapter tree and project templates only where missing.
#       --pack chooses which example pack's rules and skills land in .cursor (default
#       java, the example cursor seed only). This does not set the profile Pack row.
#       Every example pack.json under core/ is copied to .agents-v0/packs. A project
#       pack whose id is not an example is left in place.
#
#   install.sh --link --commit <sha> (--url <git-url> | --path <kit-dir>) [--force] <target-repo>
#       Pin the kit commit in docs/agents-v0/kit-pin and symlink .cursor and
#       .agents-v0/scripts into that checkout. Kit files are not copied into the project.
#
#   install.sh --update [--quick] [--allow-in-flight] <target-repo>
#       Runs validate-kit.sh, then refreshes kit-managed files (rules, agents,
#       commands, skills, hooks, scripts, reference docs). Target-owned
#       templates are seeded only when missing. The full validation builds and
#       tests the bundled app, which needs Maven and network access. --quick skips
#       that one test (KIT_SKIP_APP_TEMPLATE_TEST=1) and keeps every other check,
#       for an offline or air-gapped machine. --update refuses while a story is in
#       progress (a state.json with a non-empty activePhase); --allow-in-flight overrides.
#
#   --git-hooks (with a first install or --update)
#       Sets core.hooksPath to .agents-v0/hooks in the target repo, so pre-commit
#       guards secrets and state files and pre-push verifies the branch's state.json
#       before pushing. Opt-in: it changes the target repo's git config.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE=0
QUICK=0
WITH_STARTERS=0
LINK=0
LINK_FORCE=0
LINK_URL=""
LINK_PATH=""
LINK_COMMIT=""
PACK=""
TARGET=""
GIT_HOOKS=0
ALLOW_IN_FLIGHT=0

usage() {
  printf 'usage: %s [--pack <id>] [--with-starters] [--git-hooks] [--update [--quick] [--allow-in-flight]] <target-repo>\n' "$(basename "$0")" >&2
  printf '       %s --link --commit <sha> (--url <git-url> | --path <kit-dir>) [--force] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

file_pack() {
  awk 'NR==1 && /^---[[:space:]]*$/{fm=1; next} fm && /^---[[:space:]]*$/{exit} fm && /^pack:/{print $2; exit}' "$1"
}

strip_frontmatter() {
  awk 'NR==1 && /^---[[:space:]]*$/{fm=1; next} fm && /^---[[:space:]]*$/{fm=0; next} fm{next} {print}' "$1"
}

emit_agent() {
  src="$1"
  dst="$2"
  # Model IDs stay as in core/agents (the routing matrix). Remaps are applied
  # after install by .agents-v0/scripts/update-agents-model.sh.
  python3 - "$src" "$dst" <<'PY'
import sys
src, dst = sys.argv[1:3]
out = []
for line in open(src, encoding="utf-8"):
    if line.startswith("mode:"):
        continue
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

install_pack_library() {
  t="$1"
  mkdir -p "$t/.agents-v0/packs" "$t/.agents-v0/ui"
  for manifest in "$KIT"/core/*/pack.json; do
    [ -f "$manifest" ] || continue
    id="$(basename "$(dirname "$manifest")")"
    [ "$id" = "ui" ] && continue
    rm -rf "$t/.agents-v0/packs/$id"
    mkdir -p "$t/.agents-v0/packs/$id"
    cp -R "$KIT/core/$id/." "$t/.agents-v0/packs/$id/"
  done
  for manifest in "$KIT"/core/ui/*/pack.json; do
    [ -f "$manifest" ] || continue
    id="$(basename "$(dirname "$manifest")")"
    rm -rf "$t/.agents-v0/ui/$id"
    mkdir -p "$t/.agents-v0/ui/$id"
    cp -R "$KIT/core/ui/$id/." "$t/.agents-v0/ui/$id/"
  done
}

install_tree() {
  src="$1"
  dest="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"
}

install_rules() {
  dstdir="$1"
  mkdir -p "$dstdir"
  install_tree "$KIT/core/common/rules" "$dstdir"
  if [ -n "$PACK" ]; then
    install_tree "$KIT/core/$PACK/rules" "$dstdir"
  fi
}

install_skills() {
  dstdir="$1"
  mkdir -p "$dstdir"
  install_tree "$KIT/core/common/skills" "$dstdir"
  if [ -n "$PACK" ]; then
    install_tree "$KIT/core/$PACK/skills" "$dstdir"
  fi
}

install_starters() {
  t="$1"
  src="$KIT/core/$PACK/starters"
  [ -d "$src" ] || return 0
  find "$src" -type f ! -name '.DS_Store' | while IFS= read -r f; do
    rel="${f#"$src"/}"
    mkdir -p "$t/$(dirname "$rel")"
    cp "$f" "$t/$rel"
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
  for f in "$KIT"/core/common/agents/*.md; do
    [ -f "$f" ] || continue
    emit_agent "$f" "$t/.cursor/agents/$(basename "$f")"
  done
  if [ -n "$PACK" ]; then
    for f in "$KIT"/core/"$PACK"/agents/*.md; do
      [ -f "$f" ] || continue
      emit_agent "$f" "$t/.cursor/agents/$(basename "$f")"
    done
  fi
  for f in "$KIT"/core/common/commands/*.md; do
    emit_command "$f" "$t/.cursor/commands/$(basename "$f")"
  done
  install_skills "$t/.cursor/skills"
  cp "$KIT"/core/common/hooks/*.sh "$KIT"/core/common/hooks/hook-policy.py "$t/.cursor/hooks/"
  if [ -n "$PACK" ] && [ -f "$KIT/core/$PACK/hooks/pack-scan.sh" ]; then
    cp "$KIT/core/$PACK/hooks/pack-scan.sh" "$t/.cursor/hooks/pack-scan.sh"
  fi
  rm -f "$t/.cursor/hooks/pre-mcp.sh" "$t/.cursor/hooks/mcp-policy.json" "$t/.cursor/hooks/after-edit.sh"
  chmod +x "$t"/.cursor/hooks/*.sh "$t/.cursor/hooks/hook-policy.py"
  cp "$KIT/core/common/adapters/cursor/hooks.json" "$t/.cursor/hooks.json"
  cp "$KIT/core/common/adapters/cursor/cli.json" "$t/.cursor/cli.json"
  if [ -f "$KIT/templates/.cursor/model-config.json" ] && [ ! -f "$t/.cursor/model-config.json" ]; then
    cp "$KIT/templates/.cursor/model-config.json" "$t/.cursor/model-config.json"
  fi
}

install_antigravity() {
  t="$1"
  mkdir -p "$t/.agents/rules/org" "$t/.agents/agents" "$t/.agents/commands" "$t/.agents/skills" "$t/.agents/hooks"
  install_rules "$t/.agents/rules/org"
  for f in "$KIT"/core/common/agents/*.md; do
    [ -f "$f" ] || continue
    emit_agent "$f" "$t/.agents/agents/$(basename "$f")"
  done
  if [ -n "$PACK" ]; then
    for f in "$KIT"/core/"$PACK"/agents/*.md; do
      [ -f "$f" ] || continue
      emit_agent "$f" "$t/.agents/agents/$(basename "$f")"
    done
  fi
  for f in "$KIT"/core/common/commands/*.md; do
    cname="$(basename "$f" .md)"
    emit_command "$f" "$t/.agents/commands/$(basename "$f")"
    mkdir -p "$t/.agents/skills/$cname"
    python3 - "$f" "$cname" "$t/.agents/skills/$cname/SKILL.md" <<'PY'
import re, sys
src, cname, dst = sys.argv[1:4]
raw = open(src, encoding="utf-8").read()
desc = f"Execute the /{cname} phase of the agents-v0 delivery lifecycle."
m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", raw, flags=re.S)
body = raw
if m:
    fm, body = m.group(1), m.group(2)
    dm = re.search(r"^description:\s*(.+)$", fm, flags=re.M)
    if dm:
        desc = dm.group(1).strip()
with open(dst, "w", encoding="utf-8") as fh:
    fh.write(f"---\nname: {cname}\ndescription: {desc}\n---\n\n{body}")
PY
  done
  install_skills "$t/.agents/skills"
  cp "$KIT"/core/common/hooks/*.sh "$KIT"/core/common/hooks/hook-policy.py "$t/.agents/hooks/"
  if [ -n "$PACK" ] && [ -f "$KIT/core/$PACK/hooks/pack-scan.sh" ]; then
    cp "$KIT/core/$PACK/hooks/pack-scan.sh" "$t/.agents/hooks/pack-scan.sh"
  fi
  chmod +x "$t"/.agents/hooks/*.sh "$t/.agents/hooks/hook-policy.py"
  cp "$KIT/core/common/adapters/antigravity/hooks.json" "$t/.agents/hooks.json"
}

install_templates() {
  t="$1"
  [ -f "$t/README.md" ] || cp "$KIT/README.md" "$t/README.md"
  [ -f "$t/AGENTS.md" ] || cp "$KIT/AGENTS.md" "$t/AGENTS.md"
  [ -f "$t/.gitignore" ] || cp "$KIT/templates/.gitignore" "$t/.gitignore"
  if [ "$UPDATE" = 1 ]; then
    rm -rf "$t/.agents-v0/ci" "$t/.agents-v0/hooks/pre-commit" "$t/.agents-v0/scripts/check-delivery-gate-local.sh"
    cp "$KIT/AGENTS.md" "$t/AGENTS.md"
    # macOS AppleDouble files (._*) break Checkstyle and test globs; an existing .gitignore gains the rule.
    if [ -f "$t/.gitignore" ] && ! grep -Eq '^\._\*$' "$t/.gitignore"; then
      printf '\n# --- macOS AppleDouble metadata ---\n._*\n.AppleDouble/\n' >> "$t/.gitignore"
      printf 'MIGRATED (project-owned file edited): .gitignore gained ._* and .AppleDouble/\n'
    fi
  fi
  # MEM-07: the cross-story memory adds two scripts (stories-status.sh, check-lessons.sh) and two
  # project-owned docs (lessons.md, lessons-archive.md). The scripts are kit-managed and are refreshed
  # by --update (always list below). The docs are seeded only when missing, so --update never
  # overwrites the lessons a project has accepted.
  minimal="
.gitignore
.gitlab-ci.yml
.gitlab/merge_request_templates/default.md
.gitlab/CODEOWNERS
.agents-v0/scripts/packlib.py
.agents-v0/scripts/endpoint_scan.py
.agents-v0/scripts/resolve-layout.sh
.agents-v0/scripts/run-backend-verify.sh
.agents-v0/scripts/generate-repo-map.sh
.agents-v0/scripts/collect-dependency-graphs.sh
.agents-v0/scripts/sync-feature-state.sh
.agents-v0/scripts/delivery-metrics.sh
.agents-v0/scripts/feature-worktree.sh
.agents-v0/scripts/check-attempt-budget.sh
.agents-v0/scripts/check-failure-brief.sh
.agents-v0/scripts/check-story-dependencies.sh
.agents-v0/scripts/check-release-evidence.sh
.agents-v0/scripts/check-database-runtime.sh
.agents-v0/scripts/check-tests-ran.sh
.agents-v0/scripts/discover-codebase.sh
.agents-v0/scripts/check-onboarding-docs.sh
.agents-v0/scripts/audit-brownfield-baseline.sh
.agents-v0/scripts/render-mr-body.sh
.agents-v0/scripts/release-notes.sh
.agents-v0/scripts/resolve-integration-branch.sh
.agents-v0/scripts/verify-gitlab-ci-prereqs.sh
.agents-v0/scripts/export-audit-pack.sh
.agents-v0/scripts/update-agents-model.sh
.agents-v0/scripts/host-tools-macports.sh
.agents-v0/scripts/activate-stack-pack.sh
.agents-v0/scripts/resolve-kit-root.sh
.agents-v0/scripts/stories-status.sh
.agents-v0/scripts/check-lessons.sh
.agents-v0/hooks/pre-push
docs/agents-v0/model-routing-matrix.md
docs/agents-v0/user-guide.md
docs/agents-v0/agents-v0-kit.md
docs/agents-v0/quality-gates.md
docs/agents-v0/quality-gates-engineering-principles.md
docs/agents-v0/gold-standards.md
docs/agents-v0/greenfield-onboarding.md
docs/agents-v0/brownfield-onboarding.md
docs/agents-v0/project-profile.md
docs/agents-v0/repo-map.md
docs/agents-v0/onboarding/_report.template.md
docs/agents-v0/onboarding/_module.template.md
docs/agents-v0/maintain/_note.template.md
docs/agents-v0/design/_design.template.md
docs/agents-v0/design/_amendments.template.md
docs/agents-v0/design/system/arc-record.md
docs/agents-v0/design/system/context-map.md
docs/agents-v0/design/system/nfr-slo.md
docs/agents-v0/design/system/threat-model.md
docs/agents-v0/design/system/ops-readiness.md
docs/agents-v0/design/system/_component.template.md
docs/agents-v0/roadmap/_template.md
docs/agents-v0/backlog/export-params.md
docs/agents-v0/backlog/tickets-sources.md
docs/agents-v0/presentations/_params.md
docs/agents-v0/architecture.md
docs/agents-v0/network.md
docs/agents-v0/lessons.md
docs/agents-v0/lessons-archive.md
CHANGELOG.md
"
  always_on_update="
docs/agents-v0/model-routing-matrix.md
docs/agents-v0/user-guide.md
docs/agents-v0/agents-v0-kit.md
docs/agents-v0/quality-gates-engineering-principles.md
docs/agents-v0/greenfield-onboarding.md
docs/agents-v0/brownfield-onboarding.md
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
        .agents-v0/scripts/packlib.py .agents-v0/scripts/endpoint_scan.py .agents-v0/scripts/resolve-layout.sh .agents-v0/scripts/run-backend-verify.sh \
        .agents-v0/scripts/check-attempt-budget.sh .agents-v0/scripts/check-failure-brief.sh .agents-v0/scripts/check-story-dependencies.sh \
        .agents-v0/scripts/check-release-evidence.sh .agents-v0/scripts/check-database-runtime.sh .agents-v0/scripts/check-tests-ran.sh .agents-v0/scripts/generate-repo-map.sh .agents-v0/scripts/collect-dependency-graphs.sh \
        .agents-v0/scripts/discover-codebase.sh .agents-v0/scripts/check-onboarding-docs.sh .agents-v0/scripts/audit-brownfield-baseline.sh .agents-v0/scripts/sync-feature-state.sh \
        .agents-v0/scripts/delivery-metrics.sh docs/agents-v0/onboarding/_report.template.md docs/agents-v0/onboarding/_module.template.md \
        docs/agents-v0/maintain/_note.template.md docs/agents-v0/design/system/_component.template.md docs/agents-v0/design/_design.template.md docs/agents-v0/design/_amendments.template.md \
        .agents-v0/scripts/render-mr-body.sh .agents-v0/scripts/release-notes.sh \
        .agents-v0/scripts/resolve-integration-branch.sh .agents-v0/scripts/feature-worktree.sh \
        .agents-v0/scripts/verify-gitlab-ci-prereqs.sh .agents-v0/scripts/export-audit-pack.sh \
        .agents-v0/scripts/update-agents-model.sh .agents-v0/scripts/host-tools-macports.sh \
        .agents-v0/scripts/activate-stack-pack.sh .agents-v0/scripts/resolve-kit-root.sh \
        .agents-v0/scripts/run-local-container.sh .agents-v0/scripts/stories-status.sh .agents-v0/scripts/check-lessons.sh \
        .agents-v0/hooks/pre-push; do
        [ "$rel" = "$always" ] && overwrite=1 && break
      done
    fi
    if [ -L "$dest" ]; then
      return 0
    fi
    if [ "$overwrite" = 1 ] || [ ! -f "$dest" ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$KIT/templates/$rel" "$dest"
    fi
  }
  if [ "$WITH_STARTERS" = 1 ]; then
    (
      cd "$KIT/templates"
      # app/ is the P0 codebase template (archive + editable tree). Install it via
      # scripts/scaffold-app-template.sh / bootstrap --scaffold-app, not as starters.
      find . -type f ! -name '.DS_Store' ! -path './app/*' ! -path '*/__pycache__/*' ! -name '*.bak' ! -name '*.pyc' | while IFS= read -r f; do
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
  chmod_regular() {
    for f in "$@"; do
      [ -e "$f" ] || continue
      [ -L "$f" ] && continue
      chmod +x "$f"
    done
  }
  chmod_regular "$t"/.agents-v0/scripts/*.sh "$t"/.agents-v0/hooks/*
  # A filled threat model is not replaced. An older copy gains the VAPT table.
  dest="$t/docs/agents-v0/design/system/threat-model.md"
  src="$KIT/templates/docs/agents-v0/design/system/threat-model.md"
  if [ -f "$dest" ] && ! grep -Fq '## Applicable VAPT findings' "$dest"; then
    printf '\n' >> "$dest"
    awk 'BEGIN{p=0} /^## Applicable VAPT findings/{p=1} p{print}' "$src" >> "$dest"
    printf 'MIGRATED (project-owned file edited): docs/agents-v0/design/system/threat-model.md gained the Applicable VAPT findings table.\n'
  fi
  prof="$t/docs/agents-v0/project-profile.md"
  if [ -f "$prof" ] && grep -Eq '^\|[[:space:]]*(Backend|Service) verify[[:space:]]*\|[^|]*mvnw -B ([^|]* )?clean verify`?[[:space:]]*\|' "$prof"; then
    python3 - "$prof" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
updated = re.sub(
    r"^(\|\s*(?:Backend|Service) verify\s*\|\s*`?[^|\n]*?\bmvnw\s+-B\s+(?:[^|\n]*?\s+)?clean\s+verify)(`?\s*\|)",
    r"\1 -Pci-security\2",
    text,
    flags=re.M,
)
if updated != text:
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(updated)
    print("MIGRATED (project-owned file edited): docs/agents-v0/project-profile.md Backend/Service verify rows now include -Pci-security. Review with git diff.")
PY
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --update)
      UPDATE=1
      shift
      ;;
    --quick)
      QUICK=1
      shift
      ;;
    --with-starters)
      WITH_STARTERS=1
      shift
      ;;
    --link)
      LINK=1
      shift
      ;;
    --force)
      LINK_FORCE=1
      shift
      ;;
    --url)
      [ $# -ge 2 ] || usage
      LINK_URL="$2"
      shift 2
      ;;
    --path)
      [ $# -ge 2 ] || usage
      LINK_PATH="$2"
      shift 2
      ;;
    --commit)
      [ $# -ge 2 ] || usage
      LINK_COMMIT="$2"
      shift 2
      ;;
    --pack)
      [ $# -ge 2 ] || usage
      PACK="$2"
      shift 2
      ;;
    --git-hooks)
      GIT_HOOKS=1
      shift
      ;;
    --allow-in-flight)
      ALLOW_IN_FLIGHT=1
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

[ -n "$TARGET" ] || usage
if [ -n "$PACK" ] && [ ! -f "$KIT/core/$PACK/pack.json" ]; then
  printf 'error: --pack %s has no core/%s/pack.json\n' "$PACK" "$PACK" >&2
  exit 1
fi
[ "$QUICK" = 0 ] || [ "$UPDATE" = 1 ] || { printf 'error: --quick applies to --update only\n' >&2; usage; }
[ "$ALLOW_IN_FLIGHT" = 0 ] || [ "$UPDATE" = 1 ] || { printf 'error: --allow-in-flight applies to --update only\n' >&2; usage; }
[ -d "$TARGET" ] || { printf 'error: target not found: %s\n' "$TARGET" >&2; exit 1; }
TARGET_ABS="$(cd "$TARGET" && pwd)"

# A kit update swaps rules and checks. Changing them while a story is mid-phase is how an approved
# step starts failing a check it never had to pass, so refuse unless the person opts in.
if [ "$UPDATE" = 1 ] && [ "$ALLOW_IN_FLIGHT" = 0 ] && [ "$TARGET_ABS" != "$KIT" ]; then
  in_flight="$(python3 - "$TARGET_ABS" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
paths = sorted(glob.glob(os.path.join(root, "docs/agents-v0/requirements/*.state.json")))
paths += sorted(glob.glob(os.path.join(root, "docs/agents-v0/maintain/*/state.json")))
paths.append(os.path.join(root, "docs/agents-v0/onboarding/state.json"))
paths.append(os.path.join(root, "docs/agents-v0/program.state.json"))
for p in paths:
    try:
        data = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    phase = str(data.get("activePhase") or "").strip()
    if phase:
        print(f"{os.path.relpath(p, root)} (activePhase={phase}, activeStatus={data.get('activeStatus', '')})")
PY
)"
  if [ -n "$in_flight" ]; then
    printf 'error: a story is in progress in %s:\n' "$TARGET_ABS" >&2
    printf '%s\n' "$in_flight" | sed 's/^/  /' >&2
    printf 'Finish or pause it before updating the kit, or re-run with --allow-in-flight (new checks may then block that story).\n' >&2
    exit 1
  fi
fi

require_pyyaml() {
  python3 -c 'import yaml' >/dev/null 2>&1 || {
    printf 'error: PyYAML is required for OpenAPI checks. Install it with: python3 -m pip install pyyaml   or: apk add py3-yaml   or on Intel macOS: sh templates/.agents-v0/scripts/host-tools-macports.sh --install\n' >&2
    exit 1
  }
}

if [ "$UPDATE" = 1 ]; then
  require_pyyaml
  if [ "${KIT_VALIDATING:-0}" != 1 ]; then
    if [ "$QUICK" = 1 ]; then
      printf 'Quick update: validate-kit skips the app-template build test (needs Maven and network).\n'
      KIT_SKIP_APP_TEMPLATE_TEST=1 "$KIT/scripts/validate-kit.sh"
    else
      "$KIT/scripts/validate-kit.sh"
    fi
  fi
  if [ "$TARGET_ABS" = "$KIT" ]; then
    printf 'Kit repo: validate-kit passed.\n'
    exit 0
  fi
fi
if [ "$TARGET_ABS" = "$KIT" ]; then
  printf 'error: use --update when target is the kit repo\n' >&2
  exit 1
fi

if [ "$LINK" = 1 ]; then
  [ -n "$LINK_COMMIT" ] || { printf 'error: --link requires --commit\n' >&2; exit 1; }
  [ -n "$LINK_URL" ] || [ -n "$LINK_PATH" ] || { printf 'error: --link requires --url or --path\n' >&2; exit 1; }
  set -- --commit "$LINK_COMMIT"
  [ -z "$LINK_URL" ] || set -- "$@" --url "$LINK_URL"
  [ -z "$LINK_PATH" ] || set -- "$@" --path "$LINK_PATH"
  [ "$LINK_FORCE" = 0 ] || set -- "$@" --force
  sh "$KIT/scripts/link-project.sh" "$@" "$TARGET_ABS"
  install_templates "$TARGET_ABS"
  if [ -f "$TARGET_ABS/.gitlab/CODEOWNERS" ] && grep -q '@your-team' "$TARGET_ABS/.gitlab/CODEOWNERS"; then
    printf 'WARN: .gitlab/CODEOWNERS still uses the @your-team placeholder — replace it with a real GitLab group and enable Code Owner approval, including /.gitlab-ci.yml.\n' >&2
  fi
  printf 'Linked agents-v0 into %s (kit files stay in the pinned checkout).\n' "$TARGET_ABS"
  exit 0
fi

require_pyyaml
if [ -z "$PACK" ] && [ -f "$TARGET_ABS/docs/agents-v0/project-profile.md" ]; then
  PACK="$(python3 - "$TARGET_ABS/docs/agents-v0/project-profile.md" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if "## Stack" not in text:
    raise SystemExit(0)
body = text.split("## Stack", 1)[1].split("\n## ", 1)[0]
for line in body.splitlines():
    if not line.startswith("|"):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if cells and cells[0] == "Pack" and len(cells) > 1 and re.match(r"^[a-z][a-z0-9_-]*$", cells[1]):
        print(cells[1])
        break
PY
)"
fi
# An empty profile Pack seeds the java example into .cursor. A project pack that
# is not an example in core/ keeps the rules activate-stack-pack already installed.
if [ -n "$PACK" ] && [ ! -f "$KIT/core/$PACK/pack.json" ]; then
  PACK=""
  SKIP_PACK_CURSOR=1
else
  SKIP_PACK_CURSOR=0
  PACK="${PACK:-java}"
fi

install_templates "$TARGET_ABS"
install_pack_library "$TARGET_ABS"
if [ "$WITH_STARTERS" = 1 ]; then
  install_starters "$TARGET_ABS"
fi
install_cursor "$TARGET_ABS"
install_antigravity "$TARGET_ABS"
sh "$TARGET_ABS/.agents-v0/scripts/update-agents-model.sh"

for hook in "$TARGET_ABS"/.agents-v0/hooks/*; do
  if [ -f "$hook" ] && [ ! -L "$hook" ]; then chmod +x "$hook"; fi
done
if [ "$GIT_HOOKS" = 1 ]; then
  if git -C "$TARGET_ABS" rev-parse --git-dir >/dev/null 2>&1; then
    prev_hooks="$(git -C "$TARGET_ABS" config --get core.hooksPath 2>/dev/null || true)"
    git -C "$TARGET_ABS" config core.hooksPath .agents-v0/hooks
    if [ -n "$prev_hooks" ] && [ "$prev_hooks" != ".agents-v0/hooks" ]; then
      printf 'WARN: core.hooksPath was %s; it is now .agents-v0/hooks. Move any hooks you still need into .agents-v0/hooks/.\n' "$prev_hooks" >&2
    fi
    printf 'Git hooks: core.hooksPath=.agents-v0/hooks (pre-push verifies feature state before push).\n'
  else
    printf 'WARN: --git-hooks skipped: %s is not a git repository.\n' "$TARGET_ABS" >&2
  fi
fi

if [ -f "$KIT/VERSION" ]; then
  kit_version="$(tr -d '\n' < "$KIT/VERSION")"
  kit_sha="$(git -C "$KIT" rev-parse --short=12 HEAD 2>/dev/null || true)"
  if [ -n "$kit_sha" ]; then
    kit_dirty="$(git -C "$KIT" status --porcelain 2>/dev/null | head -n 1)"
    [ -z "$kit_dirty" ] || kit_sha="${kit_sha}-dirty"
    printf '%s+%s\n' "$kit_version" "$kit_sha" > "$TARGET_ABS/.agents-kit-version"
  else
    cp "$KIT/VERSION" "$TARGET_ABS/.agents-kit-version"
  fi
fi

printf 'Installed agents-v0 into %s\n' "$TARGET_ABS"
printf 'Next: model routing per docs/agents-v0/model-routing-matrix.md. After editing .cursor/model-config.json, run sh .agents-v0/scripts/update-agents-model.sh.\n'
printf 'Greenfield: %s/bootstrap-greenfield.sh — see docs/agents-v0/greenfield-onboarding.md. Brownfield: %s/audit-brownfield-baseline.sh — see docs/agents-v0/brownfield-onboarding.md.\n' "$(dirname "$0")" "$(dirname "$0")"
if [ "$UPDATE" = 0 ]; then
  printf 'To refresh after kit changes: %s --update <target-repo>\n' "$(basename "$0")"
fi
