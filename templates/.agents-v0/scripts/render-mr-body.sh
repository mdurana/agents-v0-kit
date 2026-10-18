#!/bin/sh
# render-mr-body.sh — build the merge request description from the evidence.
#
# Usage: sh .agents-v0/scripts/render-mr-body.sh <feature> [--base <ref>] [--template <file>]
#        sh .agents-v0/scripts/render-mr-body.sh --note docs/agents-v0/maintain/<id>/note.md [--base <ref>] [--template <file>]
# Prints the description on stdout. Start from the repository's template
# (.gitlab/merge_request_templates/default.md) and:
#   - sets the Feature-Artifact (or Maintain-Note) line that ci/check-delivery-linkage.sh reads;
#   - fills the Summary from the user story (or the note title);
#   - lists the changed files when --base is given (git diff --name-status <ref>...HEAD);
#   - appends "Evidence (generated)": the commit stamp of each report, the VAPT result rows copied
#     verbatim from vapt-checklist.md, the Critical findings from review-notes.md, and the coverage
#     lines of test-report.md.
# The checkboxes and the sign-off table stay unticked: a reviewer ticks them. Nothing is invented;
# a missing report is listed as MISSING.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }
[ $# -ge 1 ] || { printf 'usage: %s <feature> | --note <note.md> [--base <ref>] [--template <file>]\n' "$0" >&2; exit 1; }

ARGS="$(printf '%s\n' "$@")" python3 - <<'PY'
import os
import re
import subprocess
import sys

args = os.environ["ARGS"].splitlines()
feature = note = base = template = None
i = 0
while i < len(args):
    a = args[i]
    if a == "--note":
        note = args[i + 1]; i += 2
    elif a == "--base":
        base = args[i + 1]; i += 2
    elif a == "--template":
        template = args[i + 1]; i += 2
    elif not a.startswith("-") and feature is None:
        feature = a; i += 1
    else:
        print(f"FAIL: unknown argument {a}", file=sys.stderr)
        raise SystemExit(1)
if bool(feature) == bool(note):
    print("FAIL: give a feature or --note, not both", file=sys.stderr)
    raise SystemExit(1)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


template = template or (".gitlab/merge_request_templates/default.md" if os.path.isfile(".gitlab/merge_request_templates/default.md") else None)
body = read(template) if template else None
if body is None:
    print("FAIL: no merge request template found (pass --template)", file=sys.stderr)
    raise SystemExit(1)

if note:
    ident = os.path.basename(os.path.dirname(note))
    line = f"**Maintain-Note:** {note}"
    source = read(note) or ""
    m = re.search(r"^#\s*Maintenance note:\s*(.+)$", source, re.M)
    summary = (m.group(1).strip() if m else ident)
else:
    ident = feature
    line = f"**Feature-Artifact:** docs/agents-v0/requirements/{feature}.md"
    source = read(f"docs/agents-v0/requirements/{feature}.md") or ""
    m = re.search(r"As an? .+?, I want .+?, so that .+?\.", source)
    summary = m.group(0).strip() if m else f"{feature} (no user story sentence found in the requirements artifact)"

# Replace the linkage line.
body = re.sub(r"^\*{0,2}(Feature-Artifact|Maintain-Note):\*{0,2}.*$", "", body, flags=re.M | re.I, count=0)
body = re.sub(r"<!--[^\n]*(Feature-Artifact|Maintain-Note)[^\n]*-->\n?", "", body, flags=re.I)
body = re.sub(r"<!--[^\n]*Do not give both[^\n]*-->\n?", "", body, flags=re.I)

# Summary and changed files.
body = re.sub(r"<!-- One-line description of the change\. -->", lambda _m: summary + "\n\n" + line, body, count=1)
changed = "(pass --base <ref> to list the changed files)"
if base:
    eff_base = base
    mb = subprocess.run(["git", "merge-base", base, "HEAD"], capture_output=True, text=True)
    hd = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD^{commit}"], capture_output=True, text=True)
    if mb.returncode == 0 and hd.returncode == 0 and mb.stdout.strip() == hd.stdout.strip():
        state_path = f"docs/agents-v0/maintain/{ident}/state.json" if note else f"docs/agents-v0/requirements/{ident}.state.json"
        st_text = read(state_path) or ""
        m_bc = re.search(r'"baseCommit"\s*:\s*"([0-9a-fA-F]{7,40})"', st_text)
        if m_bc and m_bc.group(1) != hd.stdout.strip():
            eff_base = m_bc.group(1)
        else:
            paths = [note, f"docs/agents-v0/maintain/{ident}", f"docs/agents-v0/verify/{ident}"] if note else [
                f"docs/agents-v0/requirements/{ident}.md", f"docs/agents-v0/design/{ident}",
                f"docs/agents-v0/build/{ident}", f"docs/agents-v0/verify/{ident}",
            ]
            lg = subprocess.run(["git", "log", "--reverse", "--format=%H", "HEAD", "--", *paths], capture_output=True, text=True)
            first_c = (lg.stdout.splitlines() or [""])[0].strip() if lg.returncode == 0 else ""
            if first_c:
                par = subprocess.run(["git", "rev-parse", "--verify", "-q", f"{first_c}^"], capture_output=True, text=True)
                if par.returncode == 0 and par.stdout.strip():
                    eff_base = par.stdout.strip()
    proc = subprocess.run(["git", "diff", "--name-status", f"{eff_base}...HEAD"], capture_output=True, text=True)
    lines = proc.stdout.splitlines() if proc.returncode == 0 else []
    shown = [f"- `{ln.split(chr(9), 1)[0]}` {ln.split(chr(9), 1)[1]}" for ln in lines[:100] if "\t" in ln]
    changed = "\n".join(shown) + (f"\n- ... {len(lines) - 100} more" if len(lines) > 100 else "") if shown else "(no changes against " + base + ")"
body = re.sub(r"<!-- Bullet list of files and what changed\. -->", lambda _m: changed, body, count=1)

# Evidence appendix.
out = [body.rstrip("\n"), "", "## Evidence (generated)", "",
       "> Generated by `scripts/render-mr-body.sh` from the files below; nothing here is typed by hand. Reviewers tick the checklists above.", ""]
reports = [("Build", f"docs/agents-v0/build/{ident}/build-report.md"), ("Test", f"docs/agents-v0/verify/{ident}/test-report.md"),
           ("VAPT", f"docs/agents-v0/verify/{ident}/vapt-checklist.md"), ("Review", f"docs/agents-v0/verify/{ident}/review-notes.md")]
out += ["| Report | Path | commit |", "|--------|------|--------|"]
texts = {}
for label, path in reports:
    text = read(path)
    texts[label] = text
    if text is None:
        out.append(f"| {label} | `{path}` | MISSING |")
    else:
        m = re.search(r"^commit:\s*(\S+)", text, re.M)
        out.append(f"| {label} | `{path}` | {m.group(1) if m else 'NO commit: LINE'} |")

vapt = texts.get("VAPT")
out += ["", "### VAPT results (copied from vapt-checklist.md)", ""]
if vapt is None:
    out.append("MISSING: no VAPT checklist for this change.")
else:
    rows = [ln for ln in vapt.splitlines() if ln.strip().startswith("|")]
    out += rows if rows else ["(the checklist has no table rows)"]

review = texts.get("Review")
out += ["", "### Critical findings (from review-notes.md)", ""]
if review is None:
    out.append("MISSING: no review notes for this change.")
else:
    crit = [ln for ln in review.splitlines() if re.search(r"\bCritical\b", ln, re.I) and ln.strip().startswith("|")
            and not re.search(r"\|\s*Label\s*\|", ln, re.I)]
    out += crit if crit else ["None recorded."]

tests = texts.get("Test")
out += ["", "### Coverage and CVE lines (from test-report.md)", ""]
if tests is None:
    out.append("MISSING: no test report for this change.")
else:
    lines = [ln.strip() for ln in tests.splitlines() if re.search(r"coverage|CVE|vulnerab", ln, re.I)][:8]
    out += lines if lines else ["(no coverage or CVE lines found)"]

print("\n".join(out))
PY
