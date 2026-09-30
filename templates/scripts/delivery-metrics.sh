#!/bin/sh
# delivery-metrics.sh — summarize gate approvals and hook decisions as markdown.
#
# Usage: sh scripts/delivery-metrics.sh [repo-root] > docs/delivery-metrics.md
# Reads docs/requirements/*.md "Delivery approvals" tables (phase dates → cycle time)
# and .cursor/hooks/audit.jsonl / .claude/hooks/audit.jsonl (allow/ask/block counts).

set -eu
root="${1:-.}"
cd "$root"

python3 - <<'PY'
import datetime as dt
import glob
import json
import os
import re
import time

PHASES = ["intake", "design", "build", "verify", "release"]
POSITIVE = re.compile(r"^(approved|approve|yes|pass)\b", re.I)


def approvals(path):
    rows, inside = {}, False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if re.match(r"^#+\s*delivery approvals", line, re.I):
                inside = True
                continue
            if inside and re.match(r"^#+\s", line):
                break
            if not inside or not line.strip().startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) < 5 or cells[0].lower() not in PHASES + ["maintain", "milestone"]:
                continue
            if not POSITIVE.match(cells[3]):
                continue
            try:
                rows.setdefault(cells[0].lower(), dt.date.fromisoformat(cells[4][:10]))
            except ValueError:
                pass
    return rows


print("# Delivery metrics\n")
print(f"_Generated {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} by scripts/delivery-metrics.sh_\n")
print("## Features\n")
print("| Feature | Last approved phase | Intake → last approval (days) | Phase dates |")
print("|---------|---------------------|-------------------------------|-------------|")
for art in sorted(glob.glob("docs/requirements/*.md")):
    rows = approvals(art)
    if not rows:
        continue
    done = [p for p in PHASES if p in rows]
    last = done[-1] if done else "-"
    span = ""
    if "intake" in rows and done:
        span = str((rows[last] - rows["intake"]).days)
    dates = ", ".join(f"{p} {rows[p].isoformat()}" for p in done)
    print(f"| `{os.path.basename(art)[:-3]}` | {last} | {span} | {dates} |")

print("\n## Hook decisions (local audit log)\n")
counts = {}
for log in (".cursor/hooks/audit.jsonl", ".claude/hooks/audit.jsonl"):
    if not os.path.isfile(log):
        continue
    with open(log, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            key = (e.get("event", "?"), e.get("decision", "?"))
            counts[key] = counts.get(key, 0) + 1
if counts:
    print("| Event | Decision | Count |")
    print("|-------|----------|-------|")
    for (event, decision), n in sorted(counts.items()):
        print(f"| {event} | {decision} | {n} |")
else:
    print("No audit log found.")
PY
