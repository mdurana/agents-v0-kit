#!/usr/bin/env bash
# Bootstrap NWOB in a target project from a local clone or Git remote URL.
#
# Usage (source to keep the venv active and stay in the project directory):
#   source setup-nwob.sh <SKILLS_SOURCE> <PROJECT_DIR> <PERSONA>
#
# SKILLS_SOURCE:
#   - local path to an nwob-agent-skills clone
#   - Git URL: https:// | http:// | ssh:// | git:// | file:// | git@host:org/repo.git
#
# Environment:
#   NWOB_PYTHON         Python 3.11+ interpreter (auto-detected when unset)
#   NWOB_CACHE_DIR      clone cache for Git URLs (default: ~/.cache/nwob-agent-skills)
#   NWOB_SKILLS_REF     branch or tag to check out for Git URLs (default: remote HEAD)
#   NWOB_SCAFFOLD_DOCS  set to 1 to scaffold nwob-docs/ (greenfield opt-out; default skips it)
#
# Safe to source: no shell options are changed in the calling shell.

_nwob_is_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file*) _nwob_is_sourced=1 ;;
  esac
elif [ -n "${BASH_VERSION:-}" ]; then
  # `return` only succeeds inside a sourced file.
  (return 0 2>/dev/null) && _nwob_is_sourced=1
fi

_nwob_log() { printf '%s\n' "$*" >&2; }
_nwob_err() { printf 'Error: %s\n' "$*" >&2; }

# Set by _nwob_find_python before path/venv helpers run.
_NWOB_PY=""

_nwob_python_ok() {
  local py="$1"
  "${py}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null
}

_nwob_python_version_line() {
  local py="$1"
  "${py}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")' 2>/dev/null
}

_nwob_find_python() {
  local candidates=()
  local c resolved=""

  if [ -n "${NWOB_PYTHON:-}" ]; then
    candidates+=("${NWOB_PYTHON}")
  fi
  candidates+=(python3.13 python3.12 python3.11 python3)

  for c in "${candidates[@]}"; do
    if ! command -v "${c}" >/dev/null 2>&1; then
      continue
    fi
    resolved="$(command -v "${c}")"
    if _nwob_python_ok "${resolved}"; then
      _NWOB_PY="${resolved}"
      return 0
    fi
  done

  _nwob_err "Python 3.11+ is required (nwob-cli requires-python >=3.11)"
  _nwob_log "Install Python 3.11+ and retry, for example:"
  _nwob_log "  macOS (Homebrew): brew install python@3.12"
  _nwob_log "  pyenv:            pyenv install 3.12 && pyenv local 3.12"
  _nwob_log "Or point to an interpreter explicitly:"
  _nwob_log "  NWOB_PYTHON=/path/to/python3.12 source setup-nwob.sh <SKILLS_SOURCE> <PROJECT_DIR> <PERSONA>"
  return 1
}

_nwob_usage() {
  _nwob_log "Usage: source setup-nwob.sh <SKILLS_SOURCE> <PROJECT_DIR> <PERSONA>"
  _nwob_log "  SKILLS_SOURCE  local nwob-agent-skills path or Git URL"
  _nwob_log "  PROJECT_DIR    project to initialize"
  _nwob_log "  PERSONA        product-owner | solution-architect | lead-builder | builder | observer"
  _nwob_log ""
  _nwob_log "Default: skips nwob-docs/ scaffold (--no-scaffold-docs). Greenfield: NWOB_SCAFFOLD_DOCS=1"
}

_nwob_is_git_url() {
  case "$1" in
    https://*|http://*|ssh://*|git://*|file://*|git@*) return 0 ;;
    *) return 1 ;;
  esac
}

_nwob_abspath() {
  "${_NWOB_PY}" -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

_nwob_cache_name() {
  "${_NWOB_PY}" -c '
import hashlib, re, sys
url = sys.argv[1]
base = re.sub(r"\.git$", "", url.rstrip("/").split("/")[-1])
name = re.sub(r"[^A-Za-z0-9._-]+", "-", base).strip("-")
digest = hashlib.sha256(url.encode()).hexdigest()[:12]
print(f"{name}-{digest}" if name else digest)
' "$1"
}

_nwob_default_branch() {
  local root="$1"
  local branch=""
  branch="$(git -C "${root}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  branch="${branch#origin/}"
  if [ -z "${branch}" ]; then
    branch="$(git -C "${root}" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')"
  fi
  printf '%s' "${branch}"
}

# Clone or refresh the cached skills repo. All progress goes to stderr so the
# caller can capture only the resolved path on stdout.
_nwob_sync_cache() {
  local url="$1"
  local dest="$2"
  local ref="${NWOB_SKILLS_REF:-}"

  if [ -d "${dest}/.git" ]; then
    _nwob_log "Updating cached nwob-agent-skills at ${dest}"
    git -C "${dest}" remote set-url origin "${url}" >&2 || return 1
    if [ -n "${ref}" ]; then
      git -C "${dest}" fetch --depth 1 origin "${ref}" >&2 || return 1
      git -C "${dest}" checkout --quiet --force FETCH_HEAD >&2 || return 1
      return 0
    fi
    git -C "${dest}" fetch --depth 1 origin >&2 || return 1
    local branch
    branch="$(_nwob_default_branch "${dest}")"
    if [ -z "${branch}" ]; then
      _nwob_err "Cannot determine the default branch of ${url}"
      return 1
    fi
    git -C "${dest}" reset --hard "origin/${branch}" >&2 || return 1
    return 0
  fi

  _nwob_log "Cloning nwob-agent-skills into ${dest}"
  rm -rf "${dest}"
  if [ -n "${ref}" ]; then
    git clone --depth 1 --branch "${ref}" "${url}" "${dest}" >&2 || { rm -rf "${dest}"; return 1; }
  else
    git clone --depth 1 "${url}" "${dest}" >&2 || { rm -rf "${dest}"; return 1; }
  fi
}

# Print the resolved skills repo root on stdout.
_nwob_resolve_skills_root() {
  local src="$1"

  if ! _nwob_is_git_url "${src}"; then
    _nwob_abspath "${src}"
    return $?
  fi

  if ! command -v git >/dev/null 2>&1; then
    _nwob_err "git is required when SKILLS_SOURCE is a Git URL"
    return 1
  fi

  local cache_base="${NWOB_CACHE_DIR:-${HOME}/.cache/nwob-agent-skills}"
  local cache_name
  cache_name="$(_nwob_cache_name "${src}")" || return 1
  local dest="${cache_base}/${cache_name}"

  mkdir -p "${cache_base}" || return 1
  _nwob_sync_cache "${src}" "${dest}" || {
    _nwob_err "Could not fetch nwob-agent-skills from ${src}"
    return 1
  }
  printf '%s\n' "${dest}"
}

_nwob_main() {
  if [ "$#" -ne 3 ]; then
    _nwob_usage
    _nwob_err "Expected exactly 3 arguments, got $#"
    return 2
  fi

  local skills_source="$1"
  local project_dir="$2"
  local persona="$3"

  if ! _nwob_find_python; then
    return 1
  fi
  printf 'Using Python %s at %s\n' "$(_nwob_python_version_line "${_NWOB_PY}")" "${_NWOB_PY}"

  local skills_root
  skills_root="$(_nwob_resolve_skills_root "${skills_source}")" || return 1
  if [ ! -f "${skills_root}/scripts/nwob-init.sh" ]; then
    _nwob_err "Not an nwob-agent-skills root: ${skills_root} (missing scripts/nwob-init.sh)"
    return 1
  fi

  local project_abs
  project_abs="$(_nwob_abspath "${project_dir}")" || return 1
  if [ ! -d "${project_abs}" ]; then
    _nwob_err "Project directory not found: ${project_abs}"
    return 1
  fi

  printf 'Resolved parameters:\n'
  printf '  SKILLS_ROOT: %s\n' "${skills_root}"
  printf '  PROJECT_DIR: %s\n' "${project_abs}"
  printf '  PERSONA:     %s\n' "${persona}"

  local start_pwd="${PWD}"

  cd "${skills_root}" || return 1
  if [ -d .venv ] && [ -x .venv/bin/python ] && ! _nwob_python_ok .venv/bin/python; then
    _nwob_log "Removing incompatible .venv (requires Python >= 3.11)..."
    rm -rf .venv
  fi
  if [ ! -d .venv ]; then
    printf 'Creating virtual environment...\n'
    if ! "${_NWOB_PY}" -m venv .venv; then
      cd "${start_pwd}" || :
      return 1
    fi
  fi
  # shellcheck disable=SC1091
  if ! . .venv/bin/activate; then
    _nwob_err "Could not activate ${skills_root}/.venv"
    cd "${start_pwd}" || :
    return 1
  fi

  printf 'Installing nwob CLI...\n'
  if ! python -m pip install -e . --quiet; then
    _nwob_err "pip install -e . failed in ${skills_root}"
    cd "${start_pwd}" || :
    return 1
  fi

  cd "${project_abs}" || return 1
  printf 'Initializing persona: %s\n' "${persona}"

  local init_extra_args=(--no-scaffold-docs)
  if [ "${NWOB_SCAFFOLD_DOCS:-}" = "1" ]; then
    init_extra_args=()
  fi

  if ! "${skills_root}/scripts/nwob-init.sh" --here --persona "${persona}" "${init_extra_args[@]}"; then
    _nwob_err "nwob-init.sh failed"
    return 1
  fi

  export NWOB_SKILLS_ROOT="${skills_root}"
  printf '\nSetup complete. Project: %s\n' "${project_abs}"
  printf 'Virtual environment active; NWOB_SKILLS_ROOT=%s\n' "${NWOB_SKILLS_ROOT}"
  if [ "${#init_extra_args[@]}" -gt 0 ]; then
    _nwob_log "Next: nwob config paths --init, edit .nwob/artifact-paths.json, nwob config paths --validate"
  fi
}

_nwob_main "$@"
_nwob_status=$?

unset -f _nwob_log _nwob_err _nwob_python_ok _nwob_python_version_line \
  _nwob_find_python _nwob_usage _nwob_is_git_url _nwob_abspath \
  _nwob_cache_name _nwob_default_branch _nwob_sync_cache \
  _nwob_resolve_skills_root _nwob_main 2>/dev/null
unset _NWOB_PY 2>/dev/null

if [ "${_nwob_is_sourced}" -eq 1 ]; then
  unset _nwob_is_sourced
  return "${_nwob_status}"
fi
unset _nwob_is_sourced
exit "${_nwob_status}"
