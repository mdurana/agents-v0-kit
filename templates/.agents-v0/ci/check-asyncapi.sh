#!/bin/sh
# check-asyncapi.sh — lint a feature AsyncAPI contract (optional alongside openapi.yaml).
#
# Usage: sh .agents-v0/ci/check-asyncapi.sh lint <file>
#
# lint checks: AsyncAPI 2.x or 3.x; info.title and info.version; at least one channel;
# each channel has publish or subscribe; each operation message names x-event-type or
# payload.properties.eventType (api-and-events.mdc envelope).
# Needs python3 and PyYAML for YAML files. Exit 0 when checks pass; 1 otherwise.

set -eu

mode="${1:-}"
[ "$mode" = "lint" ] && [ $# -eq 2 ] || {
  printf 'usage: %s lint <asyncapi.yaml>\n' "$0" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

FILE="$2" python3 - <<'PY'
import json
import os
import re
import sys

path = os.environ["FILE"]
failures = []


def fail(msg):
    failures.append(msg)


def load(p):
    if not os.path.isfile(p):
        print(f"FAIL: file not found: {p}", file=sys.stderr)
        raise SystemExit(1)
    with open(p, encoding="utf-8") as handle:
        text = handle.read()
    if p.endswith(".json"):
        return json.loads(text)
    try:
        import yaml
    except ImportError:
        print(
            "FAIL: PyYAML is required for YAML AsyncAPI (python3 -m pip install pyyaml, apk add py3-yaml, or on Intel macOS: sh .agents-v0/scripts/host-tools-macports.sh)",
            file=sys.stderr,
        )
        raise SystemExit(1)
    return yaml.safe_load(text)


def message_has_event_type(msg):
    if not isinstance(msg, dict):
        return False
    if msg.get("x-event-type"):
        return True
    payload = msg.get("payload")
    if isinstance(payload, dict):
        props = payload.get("properties")
        if isinstance(props, dict) and "eventType" in props:
            return True
        ref = payload.get("$ref")
        if isinstance(ref, str) and ref.startswith("#/"):
            return True
    bindings = msg.get("bindings")
    if isinstance(bindings, dict):
        for val in bindings.values():
            if isinstance(val, dict) and val.get("x-event-type"):
                return True
    return False


doc = load(path)
ver = doc.get("asyncapi")
if not isinstance(ver, str) or not re.match(r"^2\.\d+\.\d+$|^3\.\d+\.\d+$", ver):
    fail(f"asyncapi must be 2.x.x or 3.x.x (got {ver!r})")
info = doc.get("info")
if not isinstance(info, dict) or not info.get("title") or not info.get("version"):
    fail("info.title and info.version are required")
channels = doc.get("channels")
if not isinstance(channels, dict) or not channels:
    fail("at least one channel is required when asyncapi.yaml is present")
for ch_name, ch in channels.items():
    if not isinstance(ch, dict):
        fail(f"channel {ch_name}: must be an object")
        continue
    ops = []
    for key in ("publish", "subscribe"):
        if key in ch:
            ops.append((key, ch[key]))
    if not ops and ver.startswith("3."):
        for key in ("address", "messages"):
            pass
    if not ops:
        fail(f"channel {ch_name}: needs publish or subscribe")
        continue
    for op_name, op in ops:
        if not isinstance(op, dict):
            fail(f"channel {ch_name} {op_name}: must be an object")
            continue
        msg = op.get("message")
        if isinstance(msg, dict) and "oneOf" in msg:
            msgs = msg.get("oneOf") or []
        elif isinstance(msg, dict) and "allOf" in msg:
            msgs = msg.get("allOf") or []
        else:
            msgs = [msg] if msg else []
        if not msgs:
            fail(f"channel {ch_name} {op_name}: message is required")
            continue
        for m in msgs:
            if not message_has_event_type(m):
                fail(
                    f"channel {ch_name} {op_name}: message needs x-event-type or payload.properties.eventType"
                )

if failures:
    for line in failures:
        print(f"FAIL: {line}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: AsyncAPI lint passed: {path}")
PY
