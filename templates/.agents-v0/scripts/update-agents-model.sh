#!/bin/sh
# update-agents-model.sh — rewrite .cursor/agents/*/model:, .agents/agents/*/model:,
# and sync Cursor + Antigravity IDs in docs/agents-v0/model-routing-matrix.md from
# .cursor/model-config.json and .agents/model-config.json.
#
# Usage (from the target repo root, or via this path):
#   sh .agents-v0/scripts/update-agents-model.sh
#
# Agent-to-role mapping is the Kit agent mapping table. Skill rows name a Role column.
# KIT_MODEL_<ROLE> overrides the Cursor JSON value; KIT_AGY_MODEL_<ROLE> overrides the
# Antigravity JSON value. Hyphens in the role become underscores (ux-designer -> KIT_MODEL_UX_DESIGNER).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

cfg=".cursor/model-config.json"
agy_cfg=".agents/model-config.json"
matrix="docs/agents-v0/model-routing-matrix.md"
agents=".cursor/agents"

if [ ! -f "$matrix" ]; then
  printf 'error: %s is missing. Install kit docs first.\n' "$matrix" >&2
  exit 1
fi
if [ ! -d "$agents" ]; then
  printf 'error: %s is missing. Install the kit agents first.\n' "$agents" >&2
  exit 1
fi

python3 - "$cfg" "$agy_cfg" "$matrix" "$agents" <<'PY'
import json, os, re, sys

cfg_path, agy_cfg_path, matrix_path, agents_dir = sys.argv[1:5]
cfg = {}
if os.path.isfile(cfg_path):
    with open(cfg_path, encoding="utf-8") as handle:
        raw = json.load(handle)
    if not isinstance(raw, dict):
        sys.exit("error: .cursor/model-config.json must be a JSON object of role -> model ID")
    cfg = {str(key): str(value).strip() for key, value in raw.items()}
else:
    has_env = any(
        key.startswith("KIT_MODEL_") and os.environ.get(key, "").strip()
        for key in os.environ
    )
    if not has_env:
        sys.exit(
            "error: .cursor/model-config.json is missing. "
            "Re-run install.sh to seed it from templates/.cursor/model-config.json, then edit role IDs."
        )

agy_cfg = {}
if os.path.isfile(agy_cfg_path):
    with open(agy_cfg_path, encoding="utf-8") as handle:
        raw_agy = json.load(handle)
    if not isinstance(raw_agy, dict):
        sys.exit("error: .agents/model-config.json must be a JSON object of role -> model ID")
    agy_cfg = {str(key): str(value).strip() for key, value in raw_agy.items()}

role_key = {
    "plan": "plan",
    "build": "build",
    "review": "review",
    "explore": "explore",
    "debug": "debug",
    "schemas": "schemas",
    "docs": "docs",
    "documenter": "documenter",
    "orchestrator": "orchestrator",
    "ux designer": "ux-designer",
}


def label_key(label):
    name = re.sub(r"[*_]", "", label).strip().lower()
    if not name or name in ("role", "kit agent", "skill") or set(name) <= set("-: "):
        return ""
    if name == "build (critical)":
        return ""
    key = role_key.get(name)
    if not key:
        sys.exit(f"error: unknown role label in {matrix_path}: {label!r}")
    return key


def model_for(role):
    value = os.environ.get(f"KIT_MODEL_{role.upper().replace('-', '_')}", "").strip()
    if value:
        return value
    return cfg.get(role, "").strip()


def agy_model_for(role):
    env_key = role.upper().replace("-", "_")
    value = os.environ.get(f"KIT_AGY_MODEL_{env_key}", "").strip()
    if value:
        return value
    value = os.environ.get(f"KIT_MODEL_{env_key}", "").strip()
    if value and not agy_cfg:
        return value
    return agy_cfg.get(role, "").strip() or model_for(role)


def replace_row_ids(line, section_name, cursor_id, agy_id):
    if "`" not in line:
        return line
    ending = "\r\n" if line.endswith("\r\n") else ("\n" if line.endswith("\n") else "")
    bare = line.rstrip("\r\n")
    parts = bare.split("|")
    # parts[0] is leading empty before first '|', parts[-1] is trailing empty after last '|'
    cursor_col_idx = 3 if section_name == "intro" else 4
    agy_col_idx = 4 if section_name == "intro" else 5
    if len(parts) > cursor_col_idx and "`" in parts[cursor_col_idx]:
        parts[cursor_col_idx] = re.sub(r"`[^`]*`", f"`{cursor_id}`", parts[cursor_col_idx], count=1)
    if agy_id and len(parts) > agy_col_idx and "`" in parts[agy_col_idx]:
        parts[agy_col_idx] = re.sub(r"`[^`]*`", f"`{agy_id}`", parts[agy_col_idx], count=1)
    return "|".join(parts) + ending


def table_cols(line):
    return [col.strip() for col in line.strip().strip("|").split("|")]


text = open(matrix_path, encoding="utf-8").read()
if "## Kit agent mapping" not in text:
    sys.exit(f"error: {matrix_path} has no Kit agent mapping section")
section = text.split("## Kit agent mapping", 1)[1].split("## Skill-launched", 1)[0]
roles = []
for line in section.splitlines():
    if not line.startswith("|"):
        continue
    cols = table_cols(line)
    if len(cols) < 2:
        continue
    agent = cols[0].strip()
    role = label_key(cols[1])
    if not agent or not role:
        continue
    roles.append((agent, role))

if not roles:
    sys.exit(f"error: no agents parsed from {matrix_path}")

updated = 0
for name, role in roles:
    model = model_for(role)
    if not model:
        sys.exit(
            f"error: no model ID for role {role} ({name}). "
            f"Set it in {cfg_path} or KIT_MODEL_{role.upper().replace('-', '_')}."
        )
    agy_model = agy_model_for(role)
    path = os.path.join(agents_dir, name + ".md")
    if not os.path.isfile(path):
        sys.exit(f"error: missing agent file {path}")
    targets = [(path, model, True)]
    agy_path = os.path.join(".agents/agents", name + ".md")
    if os.path.isfile(agy_path) and not os.path.samefile(path, agy_path):
        targets.append((agy_path, agy_model, False))
    for tpath, target_model, is_cursor in targets:
        with open(tpath, encoding="utf-8") as handle:
            lines = handle.readlines()
        in_frontmatter = bool(lines) and lines[0].strip() == "---"
        replaced = False
        out = []
        for index, line in enumerate(lines):
            if index == 0 and line.strip() == "---":
                out.append(line)
                continue
            if in_frontmatter and line.strip() == "---":
                in_frontmatter = False
                out.append(line)
                continue
            if in_frontmatter and (not replaced) and line.startswith("model:"):
                ending = "\n" if line.endswith("\n") else ""
                if line.endswith("\r\n"):
                    ending = "\r\n"
                previous = line.split(":", 1)[1].strip()
                out.append(f"model: {target_model}{ending}")
                replaced = True
                if is_cursor and previous != target_model:
                    print(f"{name}: {previous} -> {target_model}")
                    updated += 1
                continue
            out.append(line)
        if not replaced:
            sys.exit(f"error: {tpath} has no model: line in frontmatter")
        with open(tpath, "w", encoding="utf-8") as handle:
            handle.writelines(out)

lines_out = []
section_name = "intro"
matrix_updated = 0
for line in text.splitlines(keepends=True):
    bare = line.rstrip("\r\n")
    if bare.startswith("## Critical units"):
        section_name = "after_roles"
    elif bare.startswith("## Kit agent mapping"):
        section_name = "agents"
    elif bare.startswith("## Skill-launched"):
        section_name = "skills"
    elif bare.startswith("## Notes"):
        section_name = "notes"

    new_line = line
    if section_name in ("intro", "skills") and bare.startswith("|") and "`" in bare:
        cols = table_cols(bare)
        label = cols[0] if section_name == "intro" else (cols[1] if len(cols) > 1 else "")
        role = label_key(label) if label else ""
        if role:
            model = model_for(role)
            if not model:
                sys.exit(f"error: no model ID for role {role}. Set it in {cfg_path}.")
            agy_model = agy_model_for(role)
            new_line = replace_row_ids(line, section_name, model, agy_model)
    if new_line != line:
        matrix_updated += 1
    lines_out.append(new_line)

new_text = "".join(lines_out)
if new_text != text:
    with open(matrix_path, "w", encoding="utf-8") as handle:
        handle.write(new_text)
    print(f"Updated {matrix_path} ({matrix_updated} row/cell change(s)).")

print(f"Updated {updated} agent model(s).")
PY
