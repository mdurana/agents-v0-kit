#!/bin/sh
# check-asyncapi.sh — lint a feature AsyncAPI contract (optional alongside openapi.yaml).
#
# Usage: sh .agents-v0/ci/check-asyncapi.sh lint <file>
#
# lint checks: AsyncAPI 2.x or 3.x; info.title and info.version; at least one channel.
# 2.x: each channel has publish or subscribe. 3.x: each operation has action send or
# receive, a channel, and a message. Each message names x-event-type or
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


def pointer(root, ref):
    if not isinstance(ref, str) or not ref.startswith("#/"):
        return None
    node = root
    for raw in ref[2:].split("/"):
        part = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, dict) and part in node:
            node = node[part]
        else:
            return None
    return node


def deref(node):
    seen = set()
    current = node
    while isinstance(current, dict) and isinstance(current.get("$ref"), str):
        ref = current["$ref"]
        if ref in seen:
            return None
        seen.add(ref)
        current = pointer(doc, ref)
        if current is None:
            return None
    return current


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


def check_message(where, msg):
    resolved = deref(msg) if isinstance(msg, dict) and "$ref" in msg else msg
    if resolved is None:
        fail(f"{where}: unresolved message $ref")
        return
    if not message_has_event_type(resolved):
        fail(f"{where}: message needs x-event-type or payload.properties.eventType")


doc = load(path)
ver = doc.get("asyncapi")
if not isinstance(ver, str) or not re.match(r"^2\.\d+\.\d+$|^3\.\d+\.\d+$", ver):
    fail(f"asyncapi must be 2.x.x or 3.x.x (got {ver!r})")
is_v3 = isinstance(ver, str) and ver.startswith("3.")
info = doc.get("info")
if not isinstance(info, dict) or not info.get("title") or not info.get("version"):
    fail("info.title and info.version are required")
channels = doc.get("channels")
if not isinstance(channels, dict) or not channels:
    fail("at least one channel is required when asyncapi.yaml is present")
    channels = {}
referenced = set()
for ch_name, ch in channels.items():
    if not isinstance(ch, dict):
        fail(f"channel {ch_name}: must be an object")
        continue
    ops = []
    for key in ("publish", "subscribe"):
        if key in ch:
            ops.append((key, ch[key]))
    if not ops and not is_v3:
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
            check_message(f"channel {ch_name} {op_name}", m)

if is_v3:
    operations = doc.get("operations")
    if not isinstance(operations, dict) or not operations:
        fail("at least one operation is required")
        operations = {}
    for op_name, op in operations.items():
        if not isinstance(op, dict):
            fail(f"operation {op_name}: must be an object")
            continue
        if op.get("action") not in ("send", "receive"):
            fail(f"operation {op_name}: action must be send or receive")
        channel = op.get("channel")
        ref = channel.get("$ref") if isinstance(channel, dict) else None
        if not isinstance(ref, str) or not ref.startswith("#/channels/"):
            fail(f"operation {op_name}: channel must reference #/channels/<name>")
        else:
            referenced.add(ref[len("#/channels/"):].split("/")[0].replace("~1", "/").replace("~0", "~"))
        raw_msgs = op.get("messages") or []
        if isinstance(raw_msgs, dict):
            raw_msgs = list(raw_msgs.values())
        if not isinstance(raw_msgs, list) or not raw_msgs:
            fail(f"operation {op_name}: message is required")
            continue
        for m in raw_msgs:
            check_message(f"operation {op_name}", m)
    for ch_name, ch in channels.items():
        if not isinstance(ch, dict):
            continue
        if "publish" in ch or "subscribe" in ch:
            continue
        if ch_name not in referenced:
            fail(f"channel {ch_name}: needs an operation")

if failures:
    for line in failures:
        print(f"FAIL: {line}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: AsyncAPI lint passed: {path}")
PY
