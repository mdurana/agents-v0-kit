#!/bin/sh
# check-roadmap.sh — discovery preflight and roadmap gate verification (workflow-orchestration.mdc).
#
# Usage:
#   sh .agents-v0/ci/check-roadmap.sh --preflight <discovery-file>
#     Validates that the discovery file contains all required canonical headings
#     (Problem, Success metric, Options, Chosen option, In scope, Out of scope)
#     with non-empty bodies and no placeholder tokens (<...>, [...], TBD, TODO, FIXME, XX, ???, __).
#
#   sh .agents-v0/ci/check-roadmap.sh <roadmap-file>
#     Validates the roadmap artifact:
#       - Delivery approvals table records an explicit Approved roadmap row
#       - Discovery: path is recorded and exists
#       - sha256 checksum matches the discovery document (if recorded)
#       - Every item in Now, Next, Later is an in-scope item copied from discovery
#       - Each in-scope item is placed in exactly one horizon (no duplicates, no omissions)
#       - No out-of-scope items appear in any horizon
#
# Exit codes: 0 = valid; 1 = check failed. Needs python3.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"

if [ $# -lt 1 ]; then
  printf 'usage: %s [--preflight <discovery-file> | <roadmap-file>]\n' "$0" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

MODE="roadmap"
TARGET=""

if [ "$1" = "--preflight" ]; then
  MODE="preflight"
  if [ $# -lt 2 ]; then
    printf 'usage: %s --preflight <discovery-file>\n' "$0" >&2
    exit 1
  fi
  TARGET="$2"
else
  TARGET="$1"
fi

[ -f "$TARGET" ] || { printf 'FAIL: file not found: %s\n' "$TARGET" >&2; exit 1; }

# For roadmap mode, verify the approval row first
if [ "$MODE" = "roadmap" ]; then
  sh "$here/check-approvals.sh" "$TARGET" roadmap || exit 1
fi

CHECK_MODE="$MODE" CHECK_TARGET="$TARGET" python3 - <<'PY'
import os
import re
import sys
import hashlib
from pathlib import Path

mode = os.environ["CHECK_MODE"]
target_path = Path(os.environ["CHECK_TARGET"])

PLACEHOLDER = re.compile(
    r"(<[^>\n]+>|\[\.\.\.\]|\b(TBD|TODO|FIXME|XXX?)\b|__+|[?]{2,})",
    re.IGNORECASE
)

CANONICAL_HEADINGS = [
    ("Problem", re.compile(r"^problems?$")),
    ("Success metric", re.compile(r"^success\s+metrics?$")),
    ("Options", re.compile(r"^options?$")),
    ("Chosen option", re.compile(r"^chosen\s+options?$")),
    ("In scope", re.compile(r"^in\s+scope$")),
    ("Out of scope", re.compile(r"^out\s+of\s+scope$")),
]


def parse_markdown_sections(text):
    sections = {}
    current_key = None
    buf = []
    for line in text.splitlines():
        m = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
        if m:
            if current_key is not None:
                sections[current_key] = "\n".join(buf).strip()
            raw_title = m.group(1)
            clean_title = re.sub(r"[*_`]", "", raw_title).strip().lower()
            current_key = clean_title
            buf = []
        else:
            if current_key is not None:
                buf.append(line)
    if current_key is not None:
        sections[current_key] = "\n".join(buf).strip()
    return sections


def extract_bullets(section_text):
    bullets = []
    for line in section_text.splitlines():
        line = line.strip()
        m = re.match(r"^(?:[-*+]|\d+\.)\s+(.+)$", line)
        if m:
            clean = re.sub(r"\s+", " ", m.group(1).strip())
            bullets.append(clean)
    return bullets


def is_git_tracked_and_clean(paths):
    import subprocess
    for p in paths:
        try:
            r1 = subprocess.run(
                ["git", "ls-files", "--error-unmatch", "--", str(p)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if r1.returncode != 0:
                return False
            r2 = subprocess.run(
                ["git", "status", "--porcelain", "--", str(p)],
                capture_output=True,
                text=True,
            )
            if r2.returncode != 0 or r2.stdout.strip():
                return False
        except Exception:
            return False
    return True


def check_discovery_sections(disc_text, filename, issues=None):
    sections = parse_markdown_sections(disc_text)
    matched_sections = {}

    def report(msg):
        if issues is not None:
            issues.append(msg)
        else:
            sys.exit(f"FAIL: {msg}")

    for name, pattern in CANONICAL_HEADINGS:
        found_key = None
        for key in sections:
            if pattern.match(key):
                found_key = key
                break
        if not found_key:
            report(f"discovery document {filename} missing required heading: {name}")
            matched_sections[name] = ""
            continue

        body = sections[found_key]
        if not body:
            report(f"heading '{name}' in {filename} is empty")
            matched_sections[name] = ""
            continue

        ph = PLACEHOLDER.search(body)
        if ph:
            report(f"heading '{name}' in {filename} contains placeholder: '{ph.group(0)}'")

        matched_sections[name] = body

    return matched_sections


if mode == "preflight":
    text = target_path.read_text(encoding="utf-8")
    check_discovery_sections(text, str(target_path))
    print(f"OK: discovery document passed preflight check: {target_path}")
    sys.exit(0)

if mode == "roadmap":
    roadmap_text = target_path.read_text(encoding="utf-8")

    # Match Discovery line with optional sha256
    m_disc = re.search(r"(?im)^Discovery:\s*([^\s(]+)(?:\s+\(sha256:\s*([a-fA-F0-9]+)\))?", roadmap_text)
    if not m_disc:
        sys.exit(f"FAIL: {target_path} lacks a valid 'Discovery:' line")

    disc_path_str = m_disc.group(1).strip()
    recorded_hash = m_disc.group(2)

    if re.match(r"^<.*>$", disc_path_str):
        sys.exit(f"FAIL: {target_path} has placeholder Discovery path: {disc_path_str}")

    disc_path = Path(disc_path_str)
    if not disc_path.is_file():
        # Also check relative to workspace if run from subdirectory
        alt_path = target_path.parent.parent.parent / disc_path_str
        if alt_path.is_file():
            disc_path = alt_path
        else:
            sys.exit(f"FAIL: discovery document not found at: {disc_path_str}")

    disc_bytes = disc_path.read_bytes()
    actual_hash = hashlib.sha256(disc_bytes).hexdigest()

    if recorded_hash:
        if recorded_hash.lower() != actual_hash.lower():
            sys.exit(
                f"FAIL: discovery document '{disc_path_str}' was modified after roadmap creation "
                f"(recorded sha256: {recorded_hash}, current sha256: {actual_hash}). "
                f"Re-run /v0-roadmap --refresh."
            )

    sealed_legacy = (
        recorded_hash is None
        and os.environ.get("KIT_STRICT_ROADMAP") != "1"
        and is_git_tracked_and_clean([target_path, disc_path])
    )
    issues = [] if sealed_legacy else None

    def report_roadmap(msg):
        if issues is not None:
            issues.append(msg)
        else:
            sys.exit(f"FAIL: {msg}")

    disc_text = disc_bytes.decode("utf-8", errors="replace")
    disc_sections = check_discovery_sections(disc_text, str(disc_path), issues=issues)

    in_scope_bullets = extract_bullets(disc_sections.get("In scope", ""))
    out_of_scope_bullets = extract_bullets(disc_sections.get("Out of scope", ""))

    roadmap_sections = parse_markdown_sections(roadmap_text)

    now_bullets = extract_bullets(roadmap_sections.get("now", ""))
    next_bullets = extract_bullets(roadmap_sections.get("next", ""))
    later_bullets = extract_bullets(roadmap_sections.get("later", ""))

    all_roadmap_items = [("Now", b) for b in now_bullets] + \
                         [("Next", b) for b in next_bullets] + \
                         [("Later", b) for b in later_bullets]

    in_scope_set = set(in_scope_bullets)
    out_of_scope_set = set(out_of_scope_bullets)

    # 1. No invented themes: every horizon bullet must be in In scope
    for horizon, item in all_roadmap_items:
        if item not in in_scope_set:
            report_roadmap(
                f"roadmap horizon '{horizon}' contains item not found in discovery In scope: '{item}'"
            )

    # 2. Exclusivity: each in-scope item must be in at most one horizon
    seen_items = {}
    for horizon, item in all_roadmap_items:
        if item in seen_items:
            report_roadmap(
                f"in-scope item '{item}' is placed in multiple horizons "
                f"('{seen_items[item]}' and '{horizon}'). Each item must belong to exactly one horizon."
            )
        seen_items[item] = horizon

    # 3. Completeness: every In scope item must appear in at least one horizon
    for item in in_scope_bullets:
        if item not in seen_items:
            report_roadmap(
                f"in-scope item '{item}' is missing from all roadmap horizons (Now, Next, Later)"
            )

    # 4. Out of scope exclusivity: no out of scope item in horizons
    for horizon, item in all_roadmap_items:
        if item in out_of_scope_set:
            report_roadmap(
                f"out-of-scope item '{item}' appears in roadmap horizon '{horizon}'"
            )

    if issues:
        print(
            f"WARN: {target_path}: {issues[0]} "
            f"(tolerated for pre-sha256 Approved roadmap committed in git; re-opening or editing enforces strict validation)",
            file=sys.stderr,
        )
        print(f"OK: roadmap passed validation (pre-sha256 sealed roadmap): {target_path}")
        sys.exit(0)

    print(f"OK: roadmap passed validation: {target_path}")
    sys.exit(0)
PY
