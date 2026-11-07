#!/bin/sh
# validate-kit.sh — validate the agents-v0 kit ("Skills + State JSON + Native Build"),
# optionally an installed target repo.
# Usage:
#   validate-kit.sh                 validate the kit itself (no arguments allowed)
#   validate-kit.sh --target <dir>  also validate the installed kit in a target repo
set -eu
export PYTHONDONTWRITEBYTECODE=1
export KIT_VALIDATING=1

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

# Validate an installed target repo: adapter trees, entry files, scripts,
# seeded docs, ignore negations, and executable bits.
validate_target() {
  t="$(cd "$1" && pwd)"
  if [ ! -d "$t/.cursor" ]; then
    err "target has no .cursor/ tree — run scripts/install.sh first"
    return 0
  fi
  [ -f "$t/.cursor/hooks.json" ] || err "target .cursor/hooks.json missing"
  [ -f "$t/.cursor/cli.json" ] || err "target .cursor/cli.json missing"
  [ -f "$t/.cursor/rules/org/workflow-orchestration.mdc" ] || err "target .cursor/rules/org missing"
  [ -f "$t/.cursor/commands/v0-build.md" ] || err "target .cursor/commands missing (expected v0-* command files)"
  [ -f "$t/.cursor/agents/backend-engineer.md" ] || err "target .cursor/agents missing"
  [ -f "$t/.cursor/skills/spec-intake/SKILL.md" ] || err "target .cursor/skills missing"
  [ -x "$t/.cursor/hooks/pre-shell.sh" ] || err "target .cursor/hooks/pre-shell.sh missing or not executable"
  [ -f "$t/.agents/hooks.json" ] || err "target .agents/hooks.json missing"
  [ -f "$t/.agents/rules/org/workflow-orchestration.mdc" ] || err "target .agents/rules/org missing"
  [ -f "$t/.agents/commands/v0-build.md" ] || err "target .agents/commands missing (expected v0-* command files)"
  [ -f "$t/.agents/agents/backend-engineer.md" ] || err "target .agents/agents missing"
  [ -f "$t/.agents/skills/spec-intake/SKILL.md" ] || err "target .agents/skills missing"
  [ -f "$t/.agents/skills/v0-build/SKILL.md" ] || err "target .agents/skills/v0-build/SKILL.md missing"
  [ -x "$t/.agents/hooks/pre-shell.sh" ] || err "target .agents/hooks/pre-shell.sh missing or not executable"
  [ -f "$t/.cursor/model-config.json" ] || err "target .cursor/model-config.json missing (install.sh seeds it from templates/.cursor/model-config.json)"
  [ -x "$t/.agents-v0/scripts/update-agents-model.sh" ] || err "target .agents-v0/scripts/update-agents-model.sh missing or not executable"
  [ -x "$t/.agents-v0/scripts/sync-feature-state.sh" ] || err "target .agents-v0/scripts/sync-feature-state.sh missing or not executable"
  [ -x "$t/.agents-v0/scripts/resolve-layout.sh" ] || err "target .agents-v0/scripts/resolve-layout.sh missing or not executable"
  [ -x "$t/.agents-v0/scripts/run-backend-verify.sh" ] || err "target .agents-v0/scripts/run-backend-verify.sh missing or not executable"
  [ -f "$t/.agents-v0/scripts/packlib.py" ] || err "target .agents-v0/scripts/packlib.py missing"
  [ -f "$t/.agents-v0/scripts/endpoint_scan.py" ] || err "target .agents-v0/scripts/endpoint_scan.py missing"
  [ -f "$t/AGENTS.md" ] || err "target AGENTS.md missing (install.sh seeds it)"
  [ -f "$t/README.md" ] || err "target README.md missing (install.sh seeds it)"
  [ -f "$t/.gitlab/merge_request_templates/default.md" ] || err "target GitLab MR template missing"
  [ -f "$t/docs/agents-v0/model-routing-matrix.md" ] || err "target docs/agents-v0/model-routing-matrix.md missing"
  [ -f "$t/docs/agents-v0/user-guide.md" ] || err "target docs/agents-v0/user-guide.md missing"
  # MEM-10: an installed project has the cross-story memory scripts and its seeded lessons files.
  [ -x "$t/.agents-v0/scripts/stories-status.sh" ] || err "target .agents-v0/scripts/stories-status.sh missing or not executable"
  [ -x "$t/.agents-v0/scripts/check-lessons.sh" ] || err "target .agents-v0/scripts/check-lessons.sh missing or not executable"
  [ -f "$t/docs/agents-v0/lessons.md" ] || err "target docs/agents-v0/lessons.md missing (install.sh seeds it)"
  [ -f "$t/docs/agents-v0/lessons-archive.md" ] || err "target docs/agents-v0/lessons-archive.md missing (install.sh seeds it)"
  if [ -f "$t/.gitignore" ]; then
    grep -Fq '!docs/agents-v0/build/' "$t/.gitignore" || err "target .gitignore lacks the !docs/agents-v0/build/ negation (build evidence would be ignored)"
  fi
  if [ -f "$t/.cursorignore" ]; then
    grep -Fq '!docs/agents-v0/build/' "$t/.cursorignore" || err "target .cursorignore lacks the !docs/agents-v0/build/ negation"
  fi
}

# 1. Rules: valid frontmatter (kernel in core/common/rules, pack rules in core/<pack>/rules).
for f in core/*/rules/*.mdc; do
  [ -e "$f" ] || continue
  head -n1 "$f" | grep -qx -- '---' || err "$f: missing opening ---"
  awk 'NR<=20 && /^---$/ && NR>1 {found=1; exit} END{exit !found}' "$f" || err "$f: missing closing ---"
done
for phase in intake design build verify local-release; do
  grep -Fq "\`/v0-$phase\`" core/common/rules/workflow-orchestration.mdc || err "workflow rule does not reference /v0-$phase"
done
grep -Fq 'docs/agents-v0/build/' core/common/rules/workflow-orchestration.mdc || err "workflow rule does not mandate persisted Build evidence"
grep -Fq 'verify/<feature>/' core/common/rules/workflow-orchestration.mdc || err "workflow rule does not mandate persisted Verify evidence"
grep -Fq 'docs/agents-v0/project-profile.md' core/common/rules/workflow-orchestration.mdc || err "workflow rule does not reference docs/agents-v0/project-profile.md"
grep -Fq '/v0-triage' core/common/rules/workflow-orchestration.mdc || err "workflow rule does not reference /v0-triage"

# 2. Cross-references: every rule/doc named by kit content resolves.
for ref in $(grep -rhoE '`[a-z-]+\.mdc`' core/common core/java core/dotnet core/node core/python core/go | tr -d '`' | sort -u); do
  find core -path "*/rules/$ref" | grep -q . || err "kit content references missing rule $ref"
done
for ref in $(grep -rhoE '`docs/[a-zA-Z0-9/_.-]+\.md`' core/common core/java core/dotnet core/node core/python core/go | tr -d '`' | sort -u); do
  case "$ref" in docs/agents-v0/onboarding/report.md|docs/agents-v0/adr/0000-inherited-decisions.md|docs/agents-v0/discovery/*|docs/agents-v0/design/system/architecture-review.md|docs/agents-v0/*/p0-a-platform-skeleton*|*phase-result.md) continue ;; esac
  if [ -f "$ref" ]; then
    continue
  fi
  case "$ref" in docs/agents-v0/*) tpl="templates/$ref";; *) tpl="templates/docs/agents-v0/${ref#docs/}";; esac
  [ -f "$tpl" ] || err "referenced doc missing (seed $tpl): $ref"
done

# 3. Commands: every phase command exists; workflow rule references the phases; evidence contracts.
for command in roadmap architecture plan scaffold intake design build verify maintain local-release deliver status onboard triage export deck; do
  [ -f "core/common/commands/v0-$command.md" ] || err "missing /v0-$command command"
done
for f in core/common/commands/v0-*.md; do
  c="$(basename "$f" .md)"
  grep -Fq "\`/$c\`" AGENTS.md || err "AGENTS.md lifecycle table does not list /$c"
done
grep -Fq '`/v0-plan`' core/common/rules/workflow-orchestration.mdc || err "workflow rule does not reference /v0-plan"
grep -Fq '`/v0-scaffold`' core/common/rules/workflow-orchestration.mdc || err "workflow rule does not reference /v0-scaffold"
grep -Fq 'docs/agents-v0/requirements/<feature>.md' core/common/commands/v0-intake.md || err "/v0-intake does not name its requirements artifact"
grep -Fq 'docs/agents-v0/build/' core/common/commands/v0-build.md || err "/v0-build does not name persisted build evidence paths"
grep -Fq 'docs/agents-v0/verify/' core/common/commands/v0-verify.md || err "/v0-verify does not name persisted evidence paths"

# 4. Agents: closed frontmatter, name matches file, subagent mode, Cursor model field, shell tool on phase agents, referenced.
for f in core/*/agents/*.md; do
  name="$(basename "$f" .md)"
  head -n1 "$f" | grep -qx -- '---' || err "$f: missing opening ---"
  awk 'NR<=20 && /^---$/ && NR>1 {found=1; exit} END{exit !found}' "$f" || err "$f: missing closing ---"
  grep -Eq "^name:[[:space:]]*$name$" "$f" || err "$f: frontmatter name must match filename"
  grep -Eq '^mode:[[:space:]]*subagent' "$f" || err "$f: missing mode: subagent"
  grep -Eq '^model:[[:space:]]*[a-z0-9.-]+(\[[^]]+\])?$' "$f" || err "$f: missing cursor model"
  case "$name" in
    explore-researcher|schema-author|docs-author|codebase-documenter|roadmap-planner|solution-architect|design-reviewer|program-planner|platform-engineer|requirements-analyst|ux-designer|backend-engineer|bff-engineer|frontend-engineer|debug-investigator|test-engineer|security-reviewer|code-reviewer|release-manager|maintenance-engineer|orchestrator)
      if awk 'NR==1 && /^---$/{fm=1;next} fm && /^---$/{exit} fm && /^[[:space:]]*-[[:space:]]*shell$/{found=1;exit} END{exit !found}' "$f"; then
        err "$f: subagent $name must NOT declare '- shell' in tools frontmatter"
      fi
      ;;  # no shell (DR4, DA4, DP4, DS4, DI4, DD4, DB4, DV4, DLR4, DM4, DDL4 — 100% of subagents are shell-less)

    *)
      err "$f: unknown subagent $name; all kit subagents must be registered in the shell-less enforcement list"
      ;;
  esac
  grep -Fqr -- "$name" core/common core/java core/dotnet core/node core/python core/go || err "$name is not referenced by a command, agent, or skill"
done

# 5. Skills: standard frontmatter, referenced, no rule fields.
for f in core/*/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$f")")"
  grep -Eq "^name:[[:space:]]*$name$" "$f" || err "$f: frontmatter name must match directory"
  grep -Fqr -- "$name" core/common core/java core/dotnet core/node core/python core/go || err "$name is not referenced by a command or agent"
  if awk 'NR==1 && /^---/{f=1;next} f && /^---/{f=0} f && (/^globs:/||/^alwaysApply:/){print;exit}' "$f" | grep -q .; then
    err "$f: skill frontmatter has rule fields (globs/alwaysApply)"
  fi
done

# 6. Phase commands carry explicit approval wording.
for command in intake design build verify local-release maintain deliver; do
  grep -Eqi 'explicit.*approval|approval.*explicit' "core/common/commands/v0-$command.md" || err "/v0-$command lacks explicit approval wording"
done

# 7. Model routing: each agent's cursor model matches the Cursor ID of its role row.
[ -f templates/docs/agents-v0/model-routing-matrix.md ] || err "templates/docs/agents-v0/model-routing-matrix.md missing"
python3 - <<'PY' || err "agent model: does not match the routing-matrix role ID"
import re, sys
from pathlib import Path

matrix = Path("templates/docs/agents-v0/model-routing-matrix.md").read_text(encoding="utf-8")
role_key = {
    "plan": "plan", "build": "build", "review": "review", "explore": "explore",
    "debug": "debug", "schemas": "schemas", "docs": "docs", "documenter": "documenter",
    "orchestrator": "orchestrator", "ux designer": "ux-designer",
}

def cols(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]

ids = {}
for line in matrix.split("## Critical units", 1)[0].splitlines():
    if not line.startswith("|"):
        continue
    c = cols(line)
    if len(c) < 3:
        continue
    label = re.sub(r"[*_]", "", c[0]).strip().lower()
    key = role_key.get(label)
    if not key:
        continue
    match = re.search(r"`([^`]+)`", c[2])
    if not match:
        sys.exit(f"role row has no Cursor ID: {label}")
    ids[key] = match.group(1)

section = matrix.split("## Kit agent mapping", 1)[1].split("## Skill-launched", 1)[0]
agents = {}
for line in section.splitlines():
    if not line.startswith("|"):
        continue
    c = cols(line)
    if len(c) < 2:
        continue
    name = c[0].strip()
    label = re.sub(r"[*_]", "", c[1]).strip().lower()
    key = role_key.get(label)
    if name and key and name != "Kit agent":
        agents[name] = key

for path in sorted(Path("core").glob("*/agents/*.md")):
    name = path.stem
    model = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("model:"):
            model = line.split(":", 1)[1].strip()
            break
    role = agents.get(name)
    if not role:
        sys.exit(f"{name} has no Kit agent mapping row")
    if ids.get(role) != model:
        sys.exit(f"{name} model {model!r} != {role} Cursor ID {ids.get(role)!r}")
PY

# 8. Adapter config and hooks.
[ -f core/common/adapters/cursor/hooks.json ] || err "cursor hooks.json missing"
[ -f core/common/adapters/cursor/cli.json ] || err "cursor cli.json missing"
[ -f core/common/adapters/antigravity/hooks.json ] || err "antigravity hooks.json missing"
# Design: DA: supervised Cursor CLI must ask before every command, so the shipped cli.json allows nothing (pre-shell.sh still sees each one).
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["permissions"]["allow"] == [] else 1)' core/common/adapters/cursor/cli.json || err "cursor cli.json must ship an empty permissions.allow (no Shell(*)) so supervised runs ask before every command"
grep -Fq '\.cursor/cli\.json' core/common/hooks/hook-policy.py || err "hook-policy must protect .cursor/cli.json"
grep -Fq '\.agents/hooks\.json' core/common/hooks/hook-policy.py || err "hook-policy must protect .agents/hooks.json"
grep -Fq 'pre-shell.sh' core/common/adapters/cursor/hooks.json || err "cursor hooks.json does not wire pre-shell"
grep -Fq 'pre-edit.sh' core/common/adapters/cursor/hooks.json || err "cursor hooks.json must wire pre-edit"
grep -Fq 'session-start.sh' core/common/adapters/cursor/hooks.json || err "cursor hooks.json must wire session-start"
grep -Fq 'pre-shell.sh' core/common/adapters/antigravity/hooks.json || err "antigravity hooks.json does not wire pre-shell"
grep -Fq 'pre-edit.sh' core/common/adapters/antigravity/hooks.json || err "antigravity hooks.json must wire pre-edit"
grep -Fq 'session-start.sh' core/common/adapters/antigravity/hooks.json || err "antigravity hooks.json must wire session-start"
grep -Fq '"version": 1' core/common/adapters/cursor/hooks.json || err "cursor hooks.json must declare version 1"
grep -Fq '"version": 1' core/common/adapters/antigravity/hooks.json || err "antigravity hooks.json must declare version 1"
grep -Fq 'afterFileEdit' core/common/adapters/cursor/hooks.json && err "cursor hooks.json must not wire afterFileEdit (removed in Skills + State JSON + Native Build)"
[ -f core/common/hooks/after-edit.sh ] && err "core/common/hooks/after-edit.sh must be removed"
[ -d templates/.agents-v0/ci ] && err "templates/.agents-v0/ci/ must be removed"
[ -f templates/.agents-v0/hooks/pre-commit ] && err "templates/.agents-v0/hooks/pre-commit must be removed"

# 9. Hook classifications and helper scripts.
grep -Fq 'exit 2' core/common/hooks/pre-shell.sh || err "pre-shell hook has no blocking exit"
grep -Eq 'ASK:|ask\\t' core/common/hooks/pre-shell.sh core/common/hooks/lib.sh || err "pre-shell hook lacks commit/push approval prompt"
grep -Fq 'hook_emit_session_context' core/common/hooks/lib.sh || err "lib.sh must provide session-start context emitter"
grep -Fq 'agents-v0-stop-reminder' core/common/hooks/stop.sh || err "stop hook must rate-limit reminders"
[ -f core/common/hooks/hook-policy.py ] || err "hook-policy.py missing"
[ -f core/common/hooks/pre-edit.sh ] || err "pre-edit.sh missing"
grep -Fq 'hook_shell_permission_allow' core/common/hooks/lib.sh || err "lib.sh must emit Cursor permission allow JSON"
grep -Fq 'hook_shell_permission_allow' core/common/hooks/pre-edit.sh || err "pre-edit must call hook_shell_permission_allow on allow"
grep -Fq '0000000000000000000000000000000000000000' templates/.agents-v0/hooks/pre-push || err "pre-push must skip branch-delete pushes"
grep -Fq 'export-audit-pack.sh' templates/.agents-v0/scripts/export-audit-pack.sh || err "export-audit-pack.sh must exist"
grep -Fq 'agents-v0-audit-manifest' templates/.agents-v0/scripts/export-audit-pack.sh || err "export-audit-pack must emit schema agents-v0-audit-manifest"
grep -Fq '.agents-v0/scripts/[^/]+\.(sh|py)$' core/common/hooks/hook-policy.py || err "hook-policy must protect every .agents-v0/scripts/*.{sh,py} script"
grep -Fq '.agents-v0/hooks/' core/common/hooks/hook-policy.py || err "hook-policy must protect every .agents-v0/hooks/ git hook"
grep -Fq 'AGENTS\.md$' core/common/hooks/hook-policy.py || err "hook-policy must protect AGENTS.md"
grep -Fq '${CI_IMAGE_PREFIX}node:22-bookworm' templates/.gitlab-ci.yml || err "frontend job must use a Node 22 image with CI_IMAGE_PREFIX"
python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' templates/.gitlab-ci.yml >/dev/null 2>&1 || err ".gitlab-ci.yml does not parse as YAML"
for ci_ref in $(grep -oE '\.agents-v0/scripts/[A-Za-z0-9_-]+\.sh' templates/.gitlab-ci.yml | sort -u); do
  [ -f "templates/$ci_ref" ] || err ".gitlab-ci.yml names $ci_ref but templates/$ci_ref does not exist"
done
grep -Fq 'endpoint-stacks.md' templates/.agents-v0/scripts/discover-codebase.sh || err "discover-codebase.sh must propose non-Spring endpoint rows"
grep -Fq 'import endpoint_scan' templates/.agents-v0/scripts/discover-codebase.sh || err "discover-codebase.sh must use the shared endpoint scanner"
grep -Fq 'endpoint_scan.py' scripts/install.sh || err "install.sh does not seed endpoint_scan.py"
grep -Fq 'packlib.py' scripts/install.sh || err "install.sh does not seed packlib.py"
grep -Fq 'resolve-layout.sh' scripts/install.sh || err "install.sh does not seed resolve-layout.sh"
grep -Fq 'run-backend-verify.sh' scripts/install.sh || err "install.sh does not seed run-backend-verify.sh"
grep -Fq 'AGENTS.md' scripts/install.sh || err "install.sh does not seed AGENTS.md"
grep -Fq 'model-config.json' scripts/install.sh || err "install.sh must remap agent models from .cursor/model-config.json"
grep -Fq 'templates/.cursor/model-config.json' scripts/install.sh || err "install.sh must seed .cursor/model-config.json from templates/.cursor/model-config.json"
grep -Fq 'update-agents-model.sh' scripts/install.sh || err "install.sh must seed and run .agents-v0/scripts/update-agents-model.sh"
grep -Fq 'host-tools-macports.sh' scripts/install.sh || err "install.sh must seed .agents-v0/scripts/host-tools-macports.sh"
[ -x templates/.agents-v0/scripts/host-tools-macports.sh ] || err "templates/.agents-v0/scripts/host-tools-macports.sh missing or not executable"
grep -Fq 'openjdk21' templates/docs/agents-v0/gold-standards.md || err "gold-standards must document MacPorts openjdk21 for Intel Macs"
grep -Fq 'host-tools-macports.sh' core/common/commands/v0-build.md || err "v0-build must run host-tools-macports.sh on Intel Macs"
# kitfix 2026-10-22: deterministic gates and no-root database runtime discovery.
for ks in check-story-dependencies.sh check-release-evidence.sh check-database-runtime.sh check-tests-ran.sh check-gate-commit.sh check-traceability.sh; do
  [ -x "templates/.agents-v0/scripts/$ks" ] || err "templates/.agents-v0/scripts/$ks missing or not executable"
  grep -Fq ".agents-v0/scripts/$ks" scripts/install.sh || err "install.sh must seed .agents-v0/scripts/$ks"
done
grep -Fq 'check-story-dependencies.sh' core/common/commands/v0-build.md || err "v0-build must run check-story-dependencies.sh (dependency gate)"
grep -Fq 'check-story-dependencies.sh' templates/.agents-v0/scripts/sync-feature-state.sh || err "sync-feature-state must enforce the dependency gate on build"
grep -Fq 'check-database-runtime.sh' core/common/commands/v0-build.md || err "v0-build must run check-database-runtime.sh before DB-backed tests"
grep -Fq 'check-database-runtime.sh' core/common/commands/v0-verify.md || err "v0-verify must run check-database-runtime.sh before DB-backed verify"
grep -Fq 'check-release-evidence.sh' core/common/commands/v0-status.md || err "v0-status must cross-check release evidence before calling a story complete"
# kitfix-20261031-branch-guard: the feature-branch rule is a script check, and every phase command says so.
grep -Fq 'kitfix-20261031-branch-guard' templates/.agents-v0/scripts/sync-feature-state.sh || err "sync-feature-state must refuse design/build/verify/release off feature/<feature> (kitfix-20261031-branch-guard)"
for bgc in v0-design v0-build v0-verify; do
  grep -Fq 'If no worktree has branch `feature/<feature>`' "core/common/commands/$bgc.md" || err "$bgc must stop when no feature/<feature> worktree exists"
done
grep -Fq 'kitfix-20261031-branch-guard' core/common/commands/v0-local-release.md || err "v0-local-release must stop when the story has no feature/<feature> branch"
grep -Fq 'Do not run the script in the same turn as the Intake approval' core/common/commands/v0-intake.md || err "v0-intake must ask for branch authorisation in its own turn"
# kitfix-20261031-skeleton: the P0 archive must hold no macOS AppleDouble (._*) entries.
if tar tzf templates/app/p0-platform-skeleton.tar.gz 2>/dev/null | grep -Eq '(^|/)\._'; then
  err "templates/app/p0-platform-skeleton.tar.gz holds macOS ._* entries; repack with scripts/pack-app-template.sh"
fi
grep -Fq "exclude '._*'" scripts/pack-app-template.sh || err "pack-app-template.sh must exclude macOS ._* files"
grep -Eq '^\._\*$' templates/.gitignore || err "templates/.gitignore must ignore macOS AppleDouble files (._*)"
[ -f templates/.cursor/model-config.json ] || err "templates/.cursor/model-config.json missing"
[ -x templates/.agents-v0/scripts/update-agents-model.sh ] || err "templates/.agents-v0/scripts/update-agents-model.sh missing or not executable"
[ -f scripts/test-update-agents-model.sh ] || err "scripts/test-update-agents-model.sh missing"
sh scripts/test-update-agents-model.sh || err "scripts/test-update-agents-model.sh failed"
grep -Fq '## Endpoint authorization' templates/docs/agents-v0/project-profile.md || err "project profile must document extra endpoint-authorization stacks"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error core/common/hooks/*.sh core/*/hooks/*.sh templates/.agents-v0/scripts/*.sh scripts/*.sh || err "shellcheck -S error failed"
fi
[ -f core/common/hooks/session-start.sh ] || err "session-start.sh missing"
[ -f scripts/test-hooks.sh ] || err "scripts/test-hooks.sh missing"
[ -f scripts/test-hook-policy.py ] || err "scripts/test-hook-policy.py missing"
sh scripts/test-hooks.sh || err "scripts/test-hooks.sh failed"
[ -f scripts/test-ci-checks.sh ] || err "scripts/test-ci-checks.sh missing"
sh scripts/test-ci-checks.sh || err "scripts/test-ci-checks.sh failed"
[ -f scripts/test-onboard.sh ] || err "scripts/test-onboard.sh missing"
sh scripts/test-onboard.sh || err "scripts/test-onboard.sh failed"
# Onboard redo, Design: D6. Drift check A: the /v0-onboard step block matches `guard-onboard.sh steps` byte for byte.
sh scripts/generate-onboard-steps.sh --check >/dev/null || err "core/common/commands/v0-onboard.md step block drifted from guard-onboard.sh steps (run sh scripts/generate-onboard-steps.sh)"
[ -f scripts/test-onboard-steps.sh ] || err "scripts/test-onboard-steps.sh missing"
sh scripts/test-onboard-steps.sh >/dev/null || err "scripts/test-onboard-steps.sh failed"
# Drift check B: the /v0-onboard prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh audit-brownfield-baseline.sh check-onboarding-docs.sh check-gate-commit.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-onboard.md; then
    err "core/common/commands/v0-onboard.md names the internal '$internal' (the guard runs it; keep the prose to guard-onboard.sh steps)"
  fi
done
# Onboard follow-up V5-4B, Design: D8. Ignore lines (__pycache__/, audit.jsonl, state.json.lock) + brownfield migration.
[ -f scripts/test-onboard-ignore.sh ] || err "scripts/test-onboard-ignore.sh missing (V5-4B, Design: D8)"
sh scripts/test-onboard-ignore.sh >/dev/null || err "scripts/test-onboard-ignore.sh failed"
# Roadmap redo, Design: DR8. Drift check A: the /v0-roadmap step block matches `guard-roadmap.sh steps` byte for byte.
sh scripts/generate-roadmap-steps.sh --check >/dev/null || err "core/common/commands/v0-roadmap.md step block drifted from guard-roadmap.sh steps (run sh scripts/generate-roadmap-steps.sh)"
[ -f scripts/test-roadmap-steps.sh ] || err "scripts/test-roadmap-steps.sh missing"
sh scripts/test-roadmap-steps.sh >/dev/null || err "scripts/test-roadmap-steps.sh failed"
[ -f scripts/test-guard-roadmap.sh ] || err "scripts/test-guard-roadmap.sh missing"
sh scripts/test-guard-roadmap.sh >/dev/null || err "scripts/test-guard-roadmap.sh failed"
# Drift check B: the /v0-roadmap prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-roadmap.md; then
    err "core/common/commands/v0-roadmap.md names the internal '$internal' (the guard runs it; keep the prose to guard-roadmap.sh steps)"
  fi
done
# Architecture redo, Design: DA8. Drift check A: the /v0-architecture step block matches `guard-architecture.sh steps` byte for byte.
sh scripts/generate-architecture-steps.sh --check >/dev/null || err "core/common/commands/v0-architecture.md step block drifted from guard-architecture.sh steps (run sh scripts/generate-architecture-steps.sh)"
[ -f scripts/test-architecture-steps.sh ] || err "scripts/test-architecture-steps.sh missing"
sh scripts/test-architecture-steps.sh >/dev/null || err "scripts/test-architecture-steps.sh failed"
[ -f scripts/test-guard-architecture.sh ] || err "scripts/test-guard-architecture.sh missing"
sh scripts/test-guard-architecture.sh >/dev/null || err "scripts/test-guard-architecture.sh failed"
# Drift check B: the /v0-architecture prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-architecture.md; then
    err "core/common/commands/v0-architecture.md names the internal '$internal' (the guard runs it; keep the prose to guard-architecture.sh steps)"
  fi
done
# Plan redo, Design: DP8. Drift check A: the /v0-plan step block matches `guard-plan.sh steps` byte for byte.
sh scripts/generate-plan-steps.sh --check >/dev/null || err "core/common/commands/v0-plan.md step block drifted from guard-plan.sh steps (run sh scripts/generate-plan-steps.sh)"
[ -f scripts/test-plan-steps.sh ] || err "scripts/test-plan-steps.sh missing"
sh scripts/test-plan-steps.sh >/dev/null || err "scripts/test-plan-steps.sh failed"
[ -f scripts/test-guard-plan.sh ] || err "scripts/test-guard-plan.sh missing"
sh scripts/test-guard-plan.sh >/dev/null || err "scripts/test-guard-plan.sh failed"
# Drift check B: the /v0-plan prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-plan.md; then
    err "core/common/commands/v0-plan.md names the internal '$internal' (the guard runs it; keep the prose to guard-plan.sh steps)"
  fi
done
# Scaffold redo, Design: DS8. Drift check A: the /v0-scaffold step block matches `guard-scaffold.sh steps` byte for byte.
sh scripts/generate-scaffold-steps.sh --check >/dev/null || err "core/common/commands/v0-scaffold.md step block drifted from guard-scaffold.sh steps (run sh scripts/generate-scaffold-steps.sh)"
[ -f scripts/test-scaffold-steps.sh ] || err "scripts/test-scaffold-steps.sh missing"
sh scripts/test-scaffold-steps.sh >/dev/null || err "scripts/test-scaffold-steps.sh failed"
[ -f scripts/test-guard-scaffold.sh ] || err "scripts/test-guard-scaffold.sh missing"
sh scripts/test-guard-scaffold.sh >/dev/null || err "scripts/test-guard-scaffold.sh failed"
# Drift check B: the /v0-scaffold prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-scaffold.md; then
    err "core/common/commands/v0-scaffold.md names the internal '$internal' (the guard runs it; keep the prose to guard-scaffold.sh steps)"
  fi
done
# Intake redo, Design: DI8. Drift check A: the /v0-intake step block matches `guard-intake.sh steps` byte for byte.
sh scripts/generate-intake-steps.sh --check >/dev/null || err "core/common/commands/v0-intake.md step block drifted from guard-intake.sh steps (run sh scripts/generate-intake-steps.sh)"
[ -f scripts/test-intake-steps.sh ] || err "scripts/test-intake-steps.sh missing"
sh scripts/test-intake-steps.sh >/dev/null || err "scripts/test-intake-steps.sh failed"
[ -f scripts/test-guard-intake.sh ] || err "scripts/test-guard-intake.sh missing"
sh scripts/test-guard-intake.sh >/dev/null || err "scripts/test-guard-intake.sh failed"
# Drift check B: the /v0-intake prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-intake.md; then
    err "core/common/commands/v0-intake.md names the internal '$internal' (the guard runs it; keep the prose to guard-intake.sh steps)"
  fi
done
# Design redo, Design: DD8. Drift check A: the /v0-design step block matches `guard-design.sh steps` byte for byte.
sh scripts/generate-design-steps.sh --check >/dev/null || err "core/common/commands/v0-design.md step block drifted from guard-design.sh steps (run sh scripts/generate-design-steps.sh)"
[ -f scripts/test-design-steps.sh ] || err "scripts/test-design-steps.sh missing"
sh scripts/test-design-steps.sh >/dev/null || err "scripts/test-design-steps.sh failed"
[ -f scripts/test-guard-design.sh ] || err "scripts/test-guard-design.sh missing"
sh scripts/test-guard-design.sh >/dev/null || err "scripts/test-guard-design.sh failed"
# Drift check B: the /v0-design prose names no internal script; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-design.md; then
    err "core/common/commands/v0-design.md names the internal '$internal' (the guard runs it; keep the prose to guard-design.sh steps)"
  fi
done
# Build redo, Design: DB8. Drift check A: the /v0-build step block matches `guard-build.sh steps` byte for byte.
sh scripts/generate-build-steps.sh --check >/dev/null || err "core/common/commands/v0-build.md step block drifted from guard-build.sh steps (run sh scripts/generate-build-steps.sh)"
[ -f scripts/test-build-steps.sh ] || err "scripts/test-build-steps.sh missing"
sh scripts/test-build-steps.sh >/dev/null || err "scripts/test-build-steps.sh failed"
[ -f scripts/test-guard-build.sh ] || err "scripts/test-guard-build.sh missing"
sh scripts/test-guard-build.sh >/dev/null || err "scripts/test-guard-build.sh failed"
# Drift check B: the /v0-build prose names no internal state writer or git add -A; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh check-attempt-budget.sh check-failure-brief.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-build.md; then
    err "core/common/commands/v0-build.md names the internal '$internal' (the guard runs it; keep the prose to guard-build.sh steps)"
  fi
done
# Verify redo, Design: DV8. Drift check A: the /v0-verify step block matches `guard-verify.sh steps` byte for byte.
sh scripts/generate-verify-steps.sh --check >/dev/null || err "core/common/commands/v0-verify.md step block drifted from guard-verify.sh steps (run sh scripts/generate-verify-steps.sh)"
[ -f scripts/test-verify-steps.sh ] || err "scripts/test-verify-steps.sh missing"
sh scripts/test-verify-steps.sh >/dev/null || err "scripts/test-verify-steps.sh failed"
[ -f scripts/test-guard-verify.sh ] || err "scripts/test-guard-verify.sh missing"
sh scripts/test-guard-verify.sh >/dev/null || err "scripts/test-guard-verify.sh failed"
# Drift check B: the /v0-verify prose names no internal state writer or git add -A; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-verify.md; then
    err "core/common/commands/v0-verify.md names the internal '$internal' (the guard runs it; keep the prose to guard-verify.sh steps)"
  fi
done
# Local-release redo, Design: DLR8. Drift check A: the /v0-local-release step block matches `guard-local-release.sh steps` byte for byte.
sh scripts/generate-local-release-steps.sh --check >/dev/null || err "core/common/commands/v0-local-release.md step block drifted from guard-local-release.sh steps (run sh scripts/generate-local-release-steps.sh)"
[ -f scripts/test-local-release-steps.sh ] || err "scripts/test-local-release-steps.sh missing"
sh scripts/test-local-release-steps.sh >/dev/null || err "scripts/test-local-release-steps.sh failed"
[ -f scripts/test-guard-local-release.sh ] || err "scripts/test-guard-local-release.sh missing"
sh scripts/test-guard-local-release.sh >/dev/null || err "scripts/test-guard-local-release.sh failed"
# Drift check B: the /v0-local-release prose names no internal state writer or git add -A; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-local-release.md; then
    err "core/common/commands/v0-local-release.md names the internal '$internal' (the guard runs it; keep the prose to guard-local-release.sh steps)"
  fi
done
[ ! -e core/common/commands/v0-release.md ] || err "core/common/commands/v0-release.md must be removed (unified on /v0-local-release)"
[ ! -e core/common/skills/release-pr/SKILL.md ] || err "core/common/skills/release-pr/SKILL.md must be removed (unified on local-release)"
# Maintain redo, Design: DM8. Drift check A: the /v0-maintain step block matches `guard-maintain.sh steps` byte for byte.
sh scripts/generate-maintain-steps.sh --check >/dev/null || err "core/common/commands/v0-maintain.md step block drifted from guard-maintain.sh steps (run sh scripts/generate-maintain-steps.sh)"
[ -f scripts/test-maintain-steps.sh ] || err "scripts/test-maintain-steps.sh missing"
sh scripts/test-maintain-steps.sh >/dev/null || err "scripts/test-maintain-steps.sh failed"
[ -f scripts/test-guard-maintain.sh ] || err "scripts/test-guard-maintain.sh missing"
sh scripts/test-guard-maintain.sh >/dev/null || err "scripts/test-guard-maintain.sh failed"
# Drift check B: the /v0-maintain prose names no internal state writer or git add -A; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh check-attempt-budget.sh check-failure-brief.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-maintain.md; then
    err "core/common/commands/v0-maintain.md names the internal '$internal' (the guard runs it; keep the prose to guard-maintain.sh steps)"
  fi
done
# Deliver redo, Design: DDL8. Drift check A: the /v0-deliver step block matches `guard-deliver.sh steps` byte for byte.
sh scripts/generate-deliver-steps.sh --check >/dev/null || err "core/common/commands/v0-deliver.md step block drifted from guard-deliver.sh steps (run sh scripts/generate-deliver-steps.sh)"
[ -f scripts/test-deliver-steps.sh ] || err "scripts/test-deliver-steps.sh missing"
sh scripts/test-deliver-steps.sh >/dev/null || err "scripts/test-deliver-steps.sh failed"
[ -f scripts/test-guard-deliver.sh ] || err "scripts/test-guard-deliver.sh missing"
sh scripts/test-guard-deliver.sh >/dev/null || err "scripts/test-guard-deliver.sh failed"
# Drift check B: the /v0-deliver prose names no internal state writer or git add -A; the guard runs these, the prose does not.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh check-attempt-budget.sh check-failure-brief.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-deliver.md; then
    err "core/common/commands/v0-deliver.md names the internal '$internal' (the guard runs it; keep the prose to guard-deliver.sh steps)"
  fi
done
# Triage & Status redo, Design: DST8. Drift check A: the /v0-triage and /v0-status step blocks match `guard-triage.sh steps` and `stories-status.sh steps` byte for byte.
sh scripts/generate-triage-steps.sh --check >/dev/null || err "core/common/commands/v0-triage.md step block drifted from guard-triage.sh steps (run sh scripts/generate-triage-steps.sh)"
sh scripts/generate-status-steps.sh --check >/dev/null || err "core/common/commands/v0-status.md step block drifted from stories-status.sh steps (run sh scripts/generate-status-steps.sh)"
[ -f scripts/test-triage-steps.sh ] || err "scripts/test-triage-steps.sh missing"
sh scripts/test-triage-steps.sh >/dev/null || err "scripts/test-triage-steps.sh failed"
[ -f scripts/test-status-steps.sh ] || err "scripts/test-status-steps.sh missing"
sh scripts/test-status-steps.sh >/dev/null || err "scripts/test-status-steps.sh failed"
[ -f scripts/test-guard-triage-status.sh ] || err "scripts/test-guard-triage-status.sh missing"
sh scripts/test-guard-triage-status.sh >/dev/null || err "scripts/test-guard-triage-status.sh failed"
# Drift check B: the /v0-triage and /v0-status prose names no internal state writer or git add -A.
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh check-attempt-budget.sh check-failure-brief.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-triage.md; then
    err "core/common/commands/v0-triage.md names the internal '$internal' (the guard runs it; keep the prose to guard-triage.sh steps)"
  fi
  if grep -Fq -- "$internal" core/common/commands/v0-status.md; then
    err "core/common/commands/v0-status.md names the internal '$internal' (keep the prose to stories-status.sh steps)"
  fi
done

# Design: line check: every commit on the onboard redo line (after its base 36b86cfe) names exactly one design line.
# Same rule as the kit's commit-msg hook (scripts/hooks/commit-msg). Skipped where the base is not in history.
[ -x scripts/hooks/commit-msg ] || err "scripts/hooks/commit-msg missing or not executable (Design: line hook)"
redo_base=36b86cfe
if git rev-parse --git-dir >/dev/null 2>&1 && git cat-file -e "$redo_base^{commit}" 2>/dev/null \
  && git merge-base --is-ancestor "$redo_base" HEAD 2>/dev/null; then
  for c in $(git rev-list --no-merges "$redo_base..HEAD"); do
    dl_all="$(git log -1 --format=%B "$c" | grep -c '^Design:' || true)"
    dl_good="$(git log -1 --format=%B "$c" | grep -Ec '^Design: (D[0-9]+|DA|DR[0-9]+|DRA|DA[0-9]+|DAA|DP[0-9]+|DPA|DS[0-9]+|DSA|DI[0-9]+|DIA|DD[0-9]+|DDA|DB[0-9]+|DBA|DV[0-9]+|DVA|DLR[0-9]+|DLRA|DM[0-9]+|DMA|DDL[0-9]+|DDLA|DST[0-9]+|DSTA|DEX[0-9]+|DEXA)$' || true)"
    [ "$dl_all" = 1 ] && [ "$dl_good" = 1 ] || err "commit $(git rev-parse --short "$c") needs exactly one line 'Design: D<n>' (or DA, DR<n>, DRA, DA<n>, DAA, DP<n>, DPA, DS<n>, DSA, DI<n>, DIA, DD<n>, DDA, DB<n>, DBA, DV<n>, DVA, DLR<n>, DLRA, DM<n>, DMA, DDL<n>, DDLA, DST<n>, DSTA, DEX<n>, DEXA); found $dl_all, $dl_good well-formed"
  done

else
  printf 'SKIP: Design: line check (redo base %s is not in this history)\n' "$redo_base"
fi
[ -f scripts/test-maintain.sh ] || err "scripts/test-maintain.sh missing"
[ -f scripts/test-clock.sh ] || err "scripts/test-clock.sh missing (kitfix-20261031-single-clock)"
sh scripts/test-clock.sh || err "scripts/test-clock.sh failed"
grep -Fq 'kitfix-20261031-single-clock' core/common/rules/workflow-orchestration.mdc || err "workflow-orchestration must state the one-clock rule"
grep -Fq 'check-tests-ran.sh' core/common/commands/v0-build.md || err "v0-build must run check-tests-ran.sh after the native verify (kitfix-20261031-tests-ran)"
grep -Fq 'check-tests-ran.sh' core/common/commands/v0-verify.md || err "v0-verify must run check-tests-ran.sh after the native verify"
grep -Fq 'maven-failsafe-plugin' templates/app/backend/pom.xml || err "the P0 skeleton pom must run *IT tests with maven-failsafe-plugin"
grep -Fq 'maven-failsafe-plugin' core/java/starters/maven/quality-plugins.xml || err "the Java quality-plugins starter must include maven-failsafe-plugin"
sh scripts/test-tests-ran.sh || err "scripts/test-tests-ran.sh failed"
# kitfix-20261031-gate-commit / -traceability: one commit per approved gate, squash release, gate-to-gate checks.
grep -Fq 'check-gate-commit.sh' templates/.agents-v0/scripts/sync-feature-state.sh || err "sync-feature-state must run check-gate-commit.sh (kitfix-20261031-gate-commit)"
grep -Fq 'check-traceability.sh' templates/.agents-v0/scripts/sync-feature-state.sh || err "sync-feature-state must run check-traceability.sh at design/build/verify approval"
grep -Fq 'Story-Branch' templates/.agents-v0/scripts/check-release-evidence.sh || err "check-release-evidence must accept a squash release (Story-Branch trailer)"
grep -Fq 'already squash-merged' templates/.agents-v0/scripts/feature-worktree.sh || err "feature-worktree must refuse a squash-released branch"
for c in v0-intake v0-design v0-build v0-verify v0-local-release v0-maintain v0-triage v0-deliver v0-roadmap v0-architecture v0-plan v0-onboard v0-scaffold; do
  grep -Fq 'kitfix-20261031-gate-commit' "core/common/commands/$c.md" || err "$c.md must state the gate commit (kitfix-20261031-gate-commit)"
done
for c in v0-design v0-build v0-verify; do
  grep -Fq 'kitfix-20261031-traceability' "core/common/commands/$c.md" || err "$c.md must state its traceability check (kitfix-20261031-traceability)"
done
grep -Fq 'git merge --squash feature/<feature>' core/common/commands/v0-local-release.md || err "v0-local-release must squash-merge a feature story"
[ -f scripts/test-gate-commit.sh ] || err "scripts/test-gate-commit.sh missing"
sh scripts/test-gate-commit.sh || err "scripts/test-gate-commit.sh failed"
# kitfix-20261031-installed-no-overrides: installed scripts carry no AGENTS_V0_* override code
for f in scripts/strip-test-overrides.sh scripts/check-installed-kit.sh scripts/test-installed-overrides.sh; do
  [ -f "$f" ] || err "$f missing (kitfix-20261031-installed-no-overrides)"
done
sh scripts/test-installed-overrides.sh || err "scripts/test-installed-overrides.sh failed"
sh scripts/test-maintain.sh || err "scripts/test-maintain.sh failed"
[ -f scripts/test-design-build.sh ] || err "scripts/test-design-build.sh missing"
sh scripts/test-design-build.sh || err "scripts/test-design-build.sh failed"
[ -f scripts/test-release.sh ] || err "scripts/test-release.sh missing"
sh scripts/test-release.sh || err "scripts/test-release.sh failed"
[ -f scripts/test-command-flows.sh ] || err "scripts/test-command-flows.sh missing"
sh scripts/test-command-flows.sh || err "scripts/test-command-flows.sh failed"
# MEM-10: behavior tests for stories-status.sh and check-lessons.sh, and the prompt wiring they need.
[ -f scripts/test-memory.sh ] || err "scripts/test-memory.sh missing"
sh scripts/test-memory.sh || err "scripts/test-memory.sh failed"
grep -Fq 'stories-status.sh' core/common/commands/v0-status.md || err "/v0-status does not use stories-status.sh"
grep -Fq 'check-lessons.sh' core/common/commands/v0-local-release.md || err "/v0-local-release does not run check-lessons.sh"
grep -Fq '## Proposed lessons' core/common/skills/local-release/SKILL.md || err "local-release does not collect Proposed lessons"
for c in plan scaffold intake design build verify maintain triage deliver; do
  grep -Fq 'docs/agents-v0/lessons.md' "core/common/commands/v0-$c.md" || err "/v0-$c does not read docs/agents-v0/lessons.md"
done
for s in stories-status.sh check-lessons.sh; do
  grep -Fq ".agents-v0/scripts/$s" scripts/install.sh || err "install.sh does not install .agents-v0/scripts/$s"
done
for doc in lessons.md lessons-archive.md; do
  grep -Fq "docs/agents-v0/$doc" scripts/install.sh || err "install.sh does not seed docs/agents-v0/$doc"
done
grep -Fq 'git status --porcelain' core/common/hooks/stop.sh || err "stop hook is not evidence-based (expected git status check)"

# 10. Entry files: AGENTS.md states the lifecycle and precedence; README documents
# the kit and is seeded into target workspaces.
[ -f AGENTS.md ] || err "AGENTS.md missing"
[ -f README.md ] || err "README.md missing"
grep -Fq 'sync-feature-state.sh' AGENTS.md || err "AGENTS.md does not describe the state and approvals contract"
grep -Fq 'the repository wins' AGENTS.md || err "AGENTS.md does not state rule precedence"
grep -Fq 'README.md' scripts/install.sh || err "install.sh does not seed README.md into target workspaces"

# 11. Required template artifacts.
for artifact in \
  templates/.gitlab-ci.yml \
  templates/.gitlab/merge_request_templates/default.md \
  templates/.gitlab/CODEOWNERS \
  templates/docs/agents-v0/architecture.md \
  templates/docs/agents-v0/network.md \
  templates/docs/agents-v0/project-profile.md \
  templates/docs/agents-v0/requirements/_state.template.json \
  templates/.agents-v0/scripts/resolve-layout.sh \
  templates/.agents-v0/scripts/run-backend-verify.sh \
  templates/.agents-v0/scripts/packlib.py \
  templates/.agents-v0/scripts/endpoint_scan.py \
  templates/.agents-v0/scripts/feature-worktree.sh \
  templates/.agents-v0/scripts/check-attempt-budget.sh \
  templates/.agents-v0/scripts/check-failure-brief.sh \
  templates/.agents-v0/scripts/verify-gitlab-ci-prereqs.sh \
  templates/.agents-v0/scripts/export-audit-pack.sh \
  templates/.agents-v0/scripts/generate-repo-map.sh \
  templates/.agents-v0/scripts/collect-dependency-graphs.sh \
  templates/.agents-v0/scripts/sync-feature-state.sh \
  templates/.agents-v0/scripts/delivery-metrics.sh \
  templates/.agents-v0/scripts/run-local-container.sh \
  templates/.agents-v0/scripts/stories-status.sh \
  templates/.agents-v0/scripts/check-lessons.sh \
  templates/docs/agents-v0/lessons.md \
  templates/docs/agents-v0/lessons-archive.md \
  templates/.agents-v0/hooks/pre-push \
  templates/.cursor/model-config.json \
  templates/docs/agents-v0/milestones/_template.md \
  templates/docs/agents-v0/milestones/p0-platform-skeleton.md \
  templates/docs/agents-v0/milestones/p1-contracts-and-data-models.md \
  templates/docs/agents-v0/milestones/p2-mvp-core-features.md \
  templates/docs/agents-v0/milestones/p3-feature-expansion.md \
  templates/docs/agents-v0/milestones/p4-hardening.md \
  templates/docs/agents-v0/milestones/p5-release-readiness.md \
  templates/docs/agents-v0/repo-map.md \
  templates/docs/agents-v0/workspace.manifest.json \
  templates/docs/agents-v0/greenfield-onboarding.md \
  templates/docs/agents-v0/brownfield-onboarding.md \
  templates/docker-compose.yml \
  templates/docker/README.md \
  core/java/starters/docker/Dockerfile.spring-boot \
  templates/docker/Dockerfile.node \
  templates/docker/Dockerfile.static-nginx \
  templates/docker/nginx-spa.conf \
  templates/docker/docker-compose.postgres.yml \
  core/java/starters/maven/checkstyle.xml \
  core/java/starters/maven/dependency-check-suppressions.xml \
  core/java/starters/maven/quality-plugins-ci-security.xml \
  core/java/starters/maven/contract-conformance.xml \
  core/java/starters/maven/archunit/LayerRulesTest.java \
  templates/docs/agents-v0/design/ux-spec.md \
  templates/docs/agents-v0/design/system/context-map.md \
  templates/docs/agents-v0/design/system/nfr-slo.md \
  templates/docs/agents-v0/design/system/threat-model.md \
  templates/docs/agents-v0/design/system/slo-evidence.md; do
  [ -f "$artifact" ] || err "required artifact template missing: $artifact"
done
for doc in model-routing-matrix.md user-guide.md agents-v0-kit.md greenfield-onboarding.md brownfield-onboarding.md; do
  tpl="templates/docs/agents-v0/$doc"
  [ -f "$tpl" ] || err "$tpl missing (install.sh will not seed docs/agents-v0/$doc)"
done
for doc in quality-gates.md quality-gates-engineering-principles.md gold-standards.md; do
  grep -Fq "docs/agents-v0/$doc" scripts/install.sh || err "install.sh does not seed docs/agents-v0/$doc"
done
for doc in quality-gates-engineering-principles.md; do
  awk '/always_on_update="/,/^"/' scripts/install.sh | grep -Fq "docs/agents-v0/$doc" || err "install.sh --update does not refresh docs/agents-v0/$doc"
done

# 12. Shell syntax.
for f in core/common/hooks/*.sh core/*/hooks/*.sh templates/.agents-v0/scripts/*.sh scripts/*.sh; do
  [ -e "$f" ] || continue
  sh -n "$f" || err "$f: shell syntax error"
done

# 13. Build-hardening contracts survive in core.
for p in java dotnet node python go; do
  grep -Fq 'TDD' "core/$p/skills/implement-service/SKILL.md" || err "$p implement-service lacks the red–green (TDD) requirement"
  grep -Fq 'bounded' "core/$p/skills/implement-service/SKILL.md" || err "$p implement-service lacks bounded fix attempts"
  grep -Fq 'migration-safety' "core/$p/skills/implement-service/SKILL.md" || err "$p implement-service must follow migration-safety for migrations"
  grep -Fq 'docs/agents-v0/build/' "core/$p/agents/backend-engineer.md" || err "$p backend-engineer does not persist build evidence"
done

# 14. Consistency between prose and the files it describes.
agent_count="$(find core -path '*/agents/*.md' -exec basename {} \; | sort -u | wc -l | tr -d ' ')"
command_count="$(ls core/common/commands/v0-*.md | wc -l | tr -d ' ')"
skill_count="$(find core -name SKILL.md | wc -l | tr -d ' ')"
grep -Fq "$agent_count subagents" README.md || err "README.md must say $agent_count subagents"
grep -Fq "$command_count entry points" README.md || err "README.md must say $command_count entry points"
grep -Fq "$skill_count playbooks" README.md || err "README.md must say $skill_count playbooks"
grep -Fq "($agent_count agents)" templates/docs/agents-v0/model-routing-matrix.md || err "routing matrix must say ($agent_count agents)"
for f in core/*/agents/*.md; do
  name="$(basename "$f" .md)"
  grep -Eq "^\\|[[:space:]]*${name}[[:space:]]*\\|" templates/docs/agents-v0/model-routing-matrix.md || err "$name has no row in the agent mapping of model-routing-matrix.md"
done
for ref in $(grep -rhoE '\(skills?: [^)]*\)' core/common/commands core/*/agents | grep -oE '`[a-z-]+`' | tr -d '`' | sort -u); do
  find core -path "*/skills/$ref/SKILL.md" | grep -q . || err "a command or agent names skill $ref, which does not exist"
done
for p in java dotnet node python go; do
  grep -Fq 'implement-service` step 6' "core/$p/agents/backend-engineer.md" || err "$p backend-engineer must defer to implement-service step 6"
  grep -Fq 'implement-bff` step 6' "core/$p/agents/bff-engineer.md" || err "$p bff-engineer must defer to implement-bff step 6"
  for f in "core/$p/skills/implement-service/SKILL.md" "core/$p/skills/implement-bff/SKILL.md"; do
    grep -Fq 'check-attempt-budget.sh' "$f" || err "$f must run the phase attempt budget check"
  done
done
grep -Fq 'implement-frontend` step 6' core/common/agents/frontend-engineer.md || err "frontend-engineer must defer to implement-frontend step 6"
grep -Fq 'check-attempt-budget.sh' core/common/skills/implement-frontend/SKILL.md || err "implement-frontend must run the phase attempt budget check"

# 15. P0 app codebase template (archive for greenfield --scaffold-app).
[ -f templates/app/p0-platform-skeleton.tar.gz ] || err "missing templates/app/p0-platform-skeleton.tar.gz — run scripts/pack-app-template.sh"
if [ "${KIT_SKIP_APP_TEMPLATE_TEST:-0}" = 1 ]; then
  printf 'SKIP: scripts/test-app-template.sh (KIT_SKIP_APP_TEMPLATE_TEST=1; the app build needs Maven and network)\n'
else
  sh scripts/test-app-template.sh || err "scripts/test-app-template.sh failed (offline or air-gapped? set KIT_SKIP_APP_TEMPLATE_TEST=1, or use install.sh --update --quick)"
fi

# 16. Always-on context budget.
always_on_bytes="$(cat core/common/rules/workflow-orchestration.mdc core/common/rules/project-delivery-core.mdc core/common/rules/ai-agent-conduct.mdc | wc -c | tr -d ' ')"
[ "$always_on_bytes" -le 32000 ] || err "always-on rules are $always_on_bytes bytes (limit 32000): move detail into a command, agent, or skill"

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
