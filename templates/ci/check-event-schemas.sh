#!/bin/sh
# check-event-schemas.sh — event schema evolution is additive (api-and-events.mdc).
#
# Usage: sh ci/check-event-schemas.sh <base-sha> <head-sha>
# Checks JSON Schema files matching EVENT_SCHEMA_GLOBS (default: docs/design/*/events/*.json,
# events/*.json, schemas/events/*.json; whitespace-separated pathspecs) that changed between
# merge-base(base, head) and head:
#   - every schema records eventVersion (a top-level key, or properties.eventVersion)
#   - a schema that existed at the base keeps every property, keeps each property's type,
#     and adds no new required field (a breaking change needs a new event type or a versioned subject)
# Avro and Protobuf schemas are not parsed here; use the schema registry's compatibility mode.
#
# Exit 0 when no schema changed or every changed schema is additive; 1 otherwise.

set -eu

base="${1:-}"
head="${2:-}"
if [ -z "$base" ] || [ -z "$head" ]; then
  printf 'usage: %s <base-sha> <head-sha>\n' "$0" >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

from="$(git merge-base "$base" "$head" 2>/dev/null || echo "$base")"
globs="${EVENT_SCHEMA_GLOBS:-docs/design/*/events/*.json events/*.json schemas/events/*.json}"

# Pass the globs to git as pathspecs; the shell must not expand them.
set -f
# shellcheck disable=SC2086
changed="$(git diff --name-only --diff-filter=AM "$from" "$head" -- $globs 2>/dev/null || true)"
set +f
if [ -z "$changed" ]; then
  printf 'OK: no event schema changed\n'
  exit 0
fi

FROM_REV="$from" HEAD_REV="$head" CHANGED="$changed" python3 - <<'PY'
import json
import os
import subprocess
import sys

from_rev = os.environ["FROM_REV"]
head_rev = os.environ["HEAD_REV"]
failures = []


def load(rev, path):
    proc = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return "invalid"


def has_version(schema):
    if not isinstance(schema, dict):
        return False
    if "eventVersion" in schema:
        return True
    props = schema.get("properties")
    return isinstance(props, dict) and "eventVersion" in props


def type_of(node):
    return node.get("type") if isinstance(node, dict) else None


def compare(old, new, where):
    """Report breaking differences between two schema nodes."""
    if not isinstance(old, dict) or not isinstance(new, dict):
        return
    old_props = old.get("properties") if isinstance(old.get("properties"), dict) else {}
    new_props = new.get("properties") if isinstance(new.get("properties"), dict) else {}
    for name, old_node in old_props.items():
        if name not in new_props:
            failures.append(f"{where}: property removed: {name}")
            continue
        if type_of(old_node) != type_of(new_props[name]):
            failures.append(f"{where}: type of {name} changed: {type_of(old_node)} -> {type_of(new_props[name])}")
        compare(old_node, new_props[name], f"{where}.{name}")
    added_required = set(new.get("required") or []) - set(old.get("required") or [])
    for name in sorted(added_required):
        if name in old_props:
            failures.append(f"{where}: field became required: {name}")
        else:
            failures.append(f"{where}: new required field: {name}")


for path in os.environ["CHANGED"].split():
    new = load(head_rev, path)
    if new is None:
        continue
    if new == "invalid":
        failures.append(f"{path}: not valid JSON")
        continue
    if not has_version(new):
        failures.append(f"{path}: missing eventVersion")
    old = load(from_rev, path)
    if isinstance(old, dict):
        compare(old, new, path)

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print("OK: changed event schemas record eventVersion and evolve additively")
PY
