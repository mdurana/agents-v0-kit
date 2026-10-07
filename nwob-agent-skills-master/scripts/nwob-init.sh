#!/usr/bin/env bash
# NWOB quick-start initializer — persona-scoped Cursor integration.
# Usage: ./scripts/nwob-init.sh --here --persona product-owner
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NWOB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export NWOB_SKILLS_ROOT="${NWOB_ROOT}"

PERSONA="product-owner"
HERE=false
FORCE=false
INTEGRATION="cursor"
NO_SCAFFOLD_DOCS=false

usage() {
  cat <<'EOF'
Usage: nwob-init.sh [OPTIONS]

Options:
  --here              Initialize in the current directory
  --persona <id>      Persona bundle (default: product-owner)
  --integration <id>  Agent integration (default: cursor)
  --force             Overwrite managed files
  --no-scaffold-docs  Skip nwob-docs/ tree; use .nwob/artifact-paths.json
  -h, --help          Show this help

Personas: product-owner, solution-architect, lead-builder, builder, observer

Environment:
  NWOB_NO_SCAFFOLD_DOCS=1   Same as --no-scaffold-docs

Delegates to `nwob init` when the CLI is on PATH; otherwise uses Python module.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --here) HERE=true; shift ;;
    --persona) PERSONA="$2"; shift 2 ;;
    --integration) INTEGRATION="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --no-scaffold-docs) NO_SCAFFOLD_DOCS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

TARGET="."
if [[ "${HERE}" != true ]]; then
  echo "Note: use --here to initialize the current directory." >&2
fi

TARGET_ABS="$(pwd)"

FORCE_FLAG=""
if [[ "${FORCE}" == true ]]; then
  FORCE_FLAG="--force"
fi

if [[ "${NWOB_NO_SCAFFOLD_DOCS:-}" == "1" ]]; then
  NO_SCAFFOLD_DOCS=true
fi

SCAFFOLD_FLAG=""
if [[ "${NO_SCAFFOLD_DOCS}" == true ]]; then
  SCAFFOLD_FLAG="--no-scaffold-docs"
fi

install_setup_script() {
  local src="${SCRIPT_DIR}/setup-nwob.sh"
  local dest="${TARGET_ABS}/setup-nwob.sh"
  if [[ ! -f "${src}" ]]; then
    return 0
  fi
  if [[ -f "${dest}" && "${FORCE}" != true ]]; then
    return 0
  fi
  if ! cp "${src}" "${dest}"; then
    echo "Warning: could not copy setup-nwob.sh into ${TARGET_ABS}" >&2
    return 0
  fi
  chmod +x "${dest}"
  echo "  Bootstrap:    setup-nwob.sh (project root)"
}

run_python() {
  local py="python3"
  if [[ -x "${NWOB_ROOT}/.venv/bin/python" ]]; then
    py="${NWOB_ROOT}/.venv/bin/python"
  fi
  if command -v "${py}" >/dev/null 2>&1; then
    PYTHONPATH="${NWOB_ROOT}/src" "${py}" -m nwob_cli init "${TARGET}" \
      --here --persona "${PERSONA}" --integration "${INTEGRATION}" ${FORCE_FLAG} ${SCAFFOLD_FLAG}
    return $?
  fi
  echo "Error: python3 required when nwob CLI is not installed." >&2
  echo "  Create a venv: cd ${NWOB_ROOT} && python3 -m venv .venv && .venv/bin/pip install typer rich pyyaml" >&2
  return 1
}

if command -v nwob >/dev/null 2>&1; then
  nwob init "${TARGET}" --here --persona "${PERSONA}" --integration "${INTEGRATION}" ${FORCE_FLAG} ${SCAFFOLD_FLAG}
elif run_python; then
  :
else
  exit 1
fi

install_setup_script

echo ""
echo "NWOB initialized. Active persona: ${PERSONA}"
echo "  Constitution: .cursor/rules/constitution-core.mdc + constitution-custom.mdc"
echo "  Skills:       .cursor/skills/"
echo "  Rules:        .cursor/rules/ + nwob-references/rules/"
echo "  Switch persona: /persona or nwob persona switch <id>"
echo "  Add persona:    nwob persona add <id>"
