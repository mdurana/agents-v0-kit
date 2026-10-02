#!/bin/sh
# delivery-metrics.sh — summarize gate approvals and hook decisions as markdown.
#
# Usage: sh .agents-v0/scripts/delivery-metrics.sh [repo-root] > docs/delivery-metrics.md
# Reads docs/agents-v0/requirements/*.md "Delivery approvals" tables (phase dates → cycle time)
# and .cursor/hooks/audit.jsonl (allow/ask/block counts).

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
for art in sorted(glob.glob("docs/agents-v0/requirements/*.md")):
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

def failed_cards(report):
    """Command-result cards (Command, Exit, Attempt, ...) whose Exit is not 0."""
    failed, total, inside = 0, 0, False
    with open(report, encoding="utf-8") as f:
        for line in f:
            if not line.strip().startswith("|"):
                inside = False
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[0].lower() == "command" and cells[1].lower() == "exit":
                inside = True
                continue
            if not inside or set("".join(cells)) <= set("-: "):
                continue
            total += 1
            if cells[1].isdigit() and cells[1] != "0":
                failed += 1
    return failed, total


print("\n## Delivery effort\n")
print("| Feature | Approved gates | Failed attempts / cards | Active phase | Status | Blocked reason |")
print("|---------|----------------|-------------------------|--------------|--------|----------------|")
effort_rows = []
for art in sorted(glob.glob("docs/agents-v0/requirements/*.md")):
    rows = approvals(art)
    slug = os.path.basename(art)[:-3]
    if slug.endswith(".phase-result") or not rows:
        continue
    state = {}
    state_path = f"docs/agents-v0/requirements/{slug}.state.json"
    if os.path.isfile(state_path):
        try:
            state = json.load(open(state_path, encoding="utf-8"))
        except ValueError:
            state = {}
    report = f"docs/agents-v0/build/{slug}/build-report.md"
    failed, total = failed_cards(report) if os.path.isfile(report) else (0, 0)
    effort_rows.append((slug, len([p for p in PHASES if p in rows]), failed, total, state))
    print(
        f"| `{slug}` | {effort_rows[-1][1]} | {failed} / {total} | {state.get('activePhase') or '-'} "
        f"| {state.get('activeStatus') or '-'} | {state.get('blockedReason') or ''} |"
    )
if effort_rows:
    n = len(effort_rows)
    blocked = sum(1 for r in effort_rows if r[4].get("activeStatus") == "blocked")
    print(
        f"\n{n} feature(s); {sum(r[1] for r in effort_rows) / n:.1f} approved gates and "
        f"{sum(r[2] for r in effort_rows) / n:.1f} failed attempts per feature; {blocked} blocked."
    )
else:
    print("| - | - | - | - | - | - |")

print("\n## Maintenance notes\n")
print("| Id | Tier | Maintain approved | Verify approved | Follow-up verify due | Status |")
print("|----|------|-------------------|-----------------|----------------------|--------|")
note_rows = 0
today = dt.date.today()
for note in sorted(glob.glob("docs/agents-v0/maintain/*/note.md")):
    text = open(note, encoding="utf-8").read()
    tier_m = re.search(r"^\s*Tier:\s*(\w+)", text, re.I | re.M)
    due_m = re.search(r"^\s*Follow-up verify due:\s*(\d{4}-\d{2}-\d{2})", text, re.I | re.M)
    tier = tier_m.group(1).lower() if tier_m else "?"
    rows = approvals(note)
    due = dt.date.fromisoformat(due_m.group(1)) if due_m else None
    verified = "verify" in rows
    status = "done" if verified else ("in progress" if "maintain" not in rows else "awaiting verify")
    if tier == "emergency" and not verified and due and today > due:
        status = f"OVERDUE by {(today - due).days} day(s)"
    note_rows += 1
    print(
        f"| `{os.path.basename(os.path.dirname(note))}` | {tier} | "
        f"{rows['maintain'].isoformat() if 'maintain' in rows else '-'} | "
        f"{rows['verify'].isoformat() if verified else '-'} | {due.isoformat() if due else '-'} | {status} |"
    )
if not note_rows:
    print("| - | - | - | - | - | - |")

print("\n## Hook decisions (local audit log)\n")
counts = {}
for log in (".cursor/hooks/audit.jsonl",):
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
