#!/bin/sh
# host-tools-macports.sh — on Intel macOS, report or install the host tools the kit runs locally.
# Apple Silicon, Linux, and CI images are unchanged.
#
# Usage:
#   sh .agents-v0/scripts/host-tools-macports.sh
#   sh .agents-v0/scripts/host-tools-macports.sh --install
#
# Exit 0 when this is not an Intel Mac, or JDK 21, Node, npm, and PyYAML are present.
# Exit 2 when an Intel Mac is missing a tool (or MacPorts) and --install was not used.
# Exit 1 on usage or a failed install.
# --install runs sudo port for missing ports, and python3 -m pip install pyyaml when
# Python is already present outside MacPorts. It does not change the default java select.
set -eu

install=0
if [ "${1:-}" = "--install" ]; then
  install=1
  shift
fi
if [ "$#" -ne 0 ]; then
  printf 'usage: %s [--install]\n' "$0" >&2
  exit 1
fi

case "$(uname -s)-$(uname -m)" in
  Darwin-x86_64|Darwin-i386) ;;
  *)
    printf 'host tools: not an Intel Mac; MacPorts not used\n'
    exit 0
    ;;
esac

export PATH="/opt/local/bin:/opt/local/sbin:${PATH:-}"

java_21() {
  if [ -x /usr/libexec/java_home ] && /usr/libexec/java_home -v 21 >/dev/null 2>&1; then
    return 0
  fi
  command -v java >/dev/null 2>&1 || return 1
  java -version 2>&1 | grep -q 'version "21'
}

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  ver="$(node -v 2>/dev/null | sed 's/^v//')"
  major="$(printf '%s' "$ver" | cut -d. -f1)"
  minor="$(printf '%s' "$ver" | cut -d. -f2)"
  case "$major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$minor" in
    ''|*[!0-9]*) minor=0 ;;
  esac
  if [ "$major" -eq 20 ] && [ "$minor" -ge 19 ]; then
    return 0
  fi
  if [ "$major" -gt 22 ]; then
    return 0
  fi
  if [ "$major" -eq 22 ] && [ "$minor" -ge 12 ]; then
    return 0
  fi
  return 1
}

yaml_ok() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c 'import yaml' >/dev/null 2>&1
}

port_bin=""
if command -v port >/dev/null 2>&1; then
  port_bin="$(command -v port)"
elif [ -x /opt/local/bin/port ]; then
  port_bin=/opt/local/bin/port
fi

need_java=0
need_node=0
need_npm=0
yaml_mode=""
java_21 || need_java=1
node_ok || need_node=1
command -v npm >/dev/null 2>&1 || need_npm=1
if ! yaml_ok; then
  if command -v python3 >/dev/null 2>&1 \
    && python3 -c 'import sys; raise SystemExit(0 if sys.prefix.startswith("/opt/local") else 1)'; then
    yaml_mode="port"
  elif command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
    yaml_mode="pip"
  else
    yaml_mode="python"
  fi
fi

java_home_hint() {
  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q 'version "21'; then
    return 0
  fi
  if [ -x /usr/libexec/java_home ] && /usr/libexec/java_home -v 21 >/dev/null 2>&1; then
    printf 'default java is not 21; for kit builds: export JAVA_HOME="$(/usr/libexec/java_home -v 21)"\n'
  fi
}

if [ "$need_java" -eq 0 ] && [ "$need_node" -eq 0 ] && [ "$need_npm" -eq 0 ] && [ -z "$yaml_mode" ]; then
  java_home_hint
  printf 'host tools: JDK 21, Node, npm, and PyYAML are present\n'
  exit 0
fi

set --
if [ "$need_java" -eq 1 ]; then
  set -- "$@" openjdk21
fi
if [ "$need_node" -eq 1 ]; then
  set -- "$@" nodejs22
fi
if [ "$need_npm" -eq 1 ]; then
  set -- "$@" npm11
fi
if [ "$yaml_mode" = "port" ]; then
  pyport="$(python3 -c 'import sys; print("py%d%d-yaml" % (sys.version_info[0], sys.version_info[1]))')"
  set -- "$@" "$pyport"
elif [ "$yaml_mode" = "python" ]; then
  set -- "$@" python313 py313-yaml
fi

printf 'Intel Mac host tools missing:\n'
if [ "$need_java" -eq 1 ]; then
  printf '  JDK 21 (MacPorts openjdk21). For kit builds set JAVA_HOME from /usr/libexec/java_home -v 21\n'
fi
if [ "$need_node" -eq 1 ]; then
  printf '  Node 20.19+ or 22.12+ (MacPorts nodejs22)\n'
fi
if [ "$need_npm" -eq 1 ]; then
  printf '  npm (MacPorts npm11)\n'
fi
if [ "$yaml_mode" = "pip" ]; then
  printf '  PyYAML: python3 -m pip install pyyaml\n'
elif [ -n "$yaml_mode" ]; then
  printf '  PyYAML via MacPorts\n'
fi
java_home_hint
printf 'Put /opt/local/bin before other package managers on PATH. Maven is ./mvnw. Docker and Podman are not MacPorts ports.\n'

if [ "$install" -eq 0 ]; then
  if [ "$#" -gt 0 ]; then
    printf 'Approve, then run: sh %s --install\n' "$0"
  elif [ "$yaml_mode" = "pip" ]; then
    printf 'Approve, then run: python3 -m pip install pyyaml\n'
  fi
  exit 2
fi

if [ "$#" -gt 0 ]; then
  if [ -z "$port_bin" ]; then
    printf 'MacPorts is not installed. Install the package for this macOS from https://www.macports.org/install.php and re-run.\n' >&2
    exit 2
  fi
  sudo "$port_bin" -N install "$@"
fi
if [ "$yaml_mode" = "pip" ]; then
  python3 -m pip install pyyaml
fi

java_21 || {
  printf 'JDK 21 is still missing after install\n' >&2
  exit 1
}
node_ok || {
  printf 'Node is still missing or too old after install\n' >&2
  exit 1
}
command -v npm >/dev/null 2>&1 || {
  printf 'npm is still missing after install\n' >&2
  exit 1
}
yaml_ok || {
  printf 'PyYAML is still missing after install\n' >&2
  exit 1
}
printf 'host tools: JDK 21, Node, npm, and PyYAML are present\n'
