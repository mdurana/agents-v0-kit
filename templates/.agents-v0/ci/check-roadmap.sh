#!/bin/sh
# check-roadmap.sh — discovery preflight and roadmap gate verification (workflow-orchestration.mdc).
#
# Usage:
#   sh .agents-v0/ci/check-roadmap.sh --preflight <discovery-file>
#     Validates that the discovery file contains all required canonical headings
#     (Problem, Success metric, Options, Chosen option, In scope, Out of scope)
#     with non-empty bodies and no placeholder tokens (<...>, [...], TBD, TODO, FIXME, XX, ???, __).
#
#   sh .agents-v0/ci/check-roadmap.sh [--approved] <roadmap-file>
#     Validates the roadmap artifact:
#       - When --approved is passed, Delivery approvals table records an explicit Approved roadmap row
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
  printf 'usage: %s [--preflight <discovery-file> | [--approved] <roadmap-file>]\n' "$0" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

MODE="roadmap"
REQUIRE_APPROVED=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --preflight)
      MODE="preflight"
      shift
      if [ $# -lt 1 ]; then
        printf 'usage: %s --preflight <discovery-file>\n' "$0" >&2
        exit 1
      fi
      TARGET="$1"
      shift
      ;;
    --approved)
      REQUIRE_APPROVED=1
      shift
      ;;
    -*)
      printf 'usage: %s [--preflight <discovery-file> | [--approved] <roadmap-file>]\n' "$0" >&2
      exit 1
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

[ -n "$TARGET" ] || { printf 'usage: %s [--preflight <discovery-file> | [--approved] <roadmap-file>]\n' "$0" >&2; exit 1; }
[ -f "$TARGET" ] || { printf 'FAIL: file not found: %s\n' "$TARGET" >&2; exit 1; }

HAS_APPROVED_ROW=0
if [ "$MODE" = "roadmap" ]; then
  if [ "$REQUIRE_APPROVED" = "1" ]; then
    sh "$here/check-approvals.sh" "$TARGET" roadmap || exit 1
    HAS_APPROVED_ROW=1
  elif sh "$here/check-approvals.sh" "$TARGET" roadmap >/dev/null 2>&1; then
    HAS_APPROVED_ROW=1
  fi
fi

CHECK_MODE="$MODE" CHECK_TARGET="$TARGET" HAS_APPROVED_ROW="$HAS_APPROVED_ROW" python3 - <<'PY'
import os
import re
import sys
import hashlib
from pathlib import Path

mode = os.environ["CHECK_MODE"]
target_path = Path(os.environ["CHECK_TARGET"])
has_approved_row = os.environ.get("HAS_APPROVED_ROW") == "1"

COMMENT = re.compile(r"<!--.*?-->", re.S)

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

ROADMAP_HEADINGS = [
    re.compile(r"^now$"),
    re.compile(r"^next$"),
    re.compile(r"^later$"),
    re.compile(r"^delivery\s+approvals?$"),
]


def is_top_section_title(clean_title):
    for _, pat in CANONICAL_HEADINGS:
        if pat.match(clean_title):
            return True
    for pat in ROADMAP_HEADINGS:
        if pat.match(clean_title):
            return True
    return False


def strip_comments(text):
    return COMMENT.sub("", text)


def parse_markdown_sections(text):
    sections = {}
    current_key = None
    current_level = 0
    buf = []
    fenced = False
    for line in strip_comments(text).splitlines():
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fenced = not fenced
        m = None if fenced else re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if m:
            level = len(m.group(1))
            raw_title = m.group(2)
            clean_title = re.sub(r"[*_`]", "", raw_title).strip().lower()
            is_new_section = (
                current_key is None
                or current_level == 1
                or level <= current_level
                or is_top_section_title(clean_title)
            )
            if is_new_section:
                if current_key is not None:
                    sections[current_key] = "\n".join(buf).strip()
                current_key = clean_title
                current_level = level
                buf = []
            else:
                buf.append(line)
        else:
            if current_key is not None:
                buf.append(line)
    if current_key is not None:
        sections[current_key] = "\n".join(buf).strip()
    return sections


def parse_bullet_tree(section_text):
    roots = []
    stack = []
    fenced = False
    for raw_line in strip_comments(section_text).splitlines():
        stripped = raw_line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fenced = not fenced
            continue
        if fenced or not stripped:
            continue
        m_head = re.match(r"^(#{1,6})\s+(.+)$", stripped)
        m_bold_para = re.match(r"^\s*(\*\*[^*]+\*\*)\s*$", raw_line)
        if m_head:
            clean = re.sub(r"\s+", " ", m_head.group(2).strip())
            node = {"text": clean, "indent": -1, "children": []}
            roots.append(node)
            stack = [node]
            continue
        elif m_bold_para:
            clean = re.sub(r"\s+", " ", raw_line.strip())
            node = {"text": clean, "indent": -1, "children": []}
            roots.append(node)
            stack = [node]
            continue
        m = re.match(r"^(\s*)(?:[-*+]|\d+\.)\s+(.+)$", raw_line)
        if m:
            indent = len(m.group(1).expandtabs(2))
            clean = re.sub(r"\s+", " ", m.group(2).strip())
            node = {"text": clean, "indent": indent, "children": []}
            while stack and stack[-1]["indent"] >= 0 and stack[-1]["indent"] >= indent:
                stack.pop()
            if stack:
                stack[-1]["children"].append(node)
            else:
                roots.append(node)
            stack.append(node)
        elif stack and stack[-1]["indent"] >= 0:
            indent = len(raw_line) - len(stripped)
            if indent > stack[-1]["indent"]:
                stack[-1]["text"] = re.sub(
                    r"\s+", " ", stack[-1]["text"] + " " + stripped.strip()
                )
    return roots


def tree_all_texts(nodes):
    out = []
    for n in nodes:
        out.append(n["text"])
        out.extend(tree_all_texts(n["children"]))
    return out


def tree_leaf_texts(nodes):
    out = []
    for n in nodes:
        if n["children"]:
            out.extend(tree_leaf_texts(n["children"]))
        else:
            out.append(n["text"])
    return out


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
        has_approved_row
        and recorded_hash is None
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

    in_scope_tree = parse_bullet_tree(disc_sections.get("In scope", ""))
    out_of_scope_tree = parse_bullet_tree(disc_sections.get("Out of scope", ""))

    in_scope_all_set = set(tree_all_texts(in_scope_tree))
    out_of_scope_set = set(tree_all_texts(out_of_scope_tree))

    roadmap_sections = parse_markdown_sections(roadmap_text)

    horizon_trees = [
        ("Now", parse_bullet_tree(roadmap_sections.get("now", ""))),
        ("Next", parse_bullet_tree(roadmap_sections.get("next", ""))),
        ("Later", parse_bullet_tree(roadmap_sections.get("later", ""))),
    ]

    all_roadmap_nodes = []
    scheduled_leaves = []
    for horizon, h_tree in horizon_trees:
        for item in tree_all_texts(h_tree):
            all_roadmap_nodes.append((horizon, item))
        for leaf in tree_leaf_texts(h_tree):
            scheduled_leaves.append((horizon, leaf))

    # 1. No invented themes: every horizon bullet (parent or leaf) must exist in discovery In scope
    for horizon, item in all_roadmap_nodes:
        if item not in in_scope_all_set:
            report_roadmap(
                f"roadmap horizon '{horizon}' contains item not found in discovery In scope: '{item}'"
            )

    # 2. Exclusivity: each scheduled leaf item must appear in at most one horizon
    seen_items = {}
    for horizon, item in scheduled_leaves:
        if item in seen_items:
            report_roadmap(
                f"in-scope item '{item}' is placed in multiple horizons "
                f"('{seen_items[item]}' and '{horizon}'). Each item must belong to exactly one horizon."
            )
        seen_items[item] = horizon

    # Also ensure a parent item is not scheduled as a standalone leaf in one horizon while its children are scheduled too
    for node in in_scope_tree:
        if node["children"] and node["text"] in seen_items:
            parent_h = seen_items[node["text"]]
            for child_leaf in tree_leaf_texts(node["children"]):
                if child_leaf in seen_items:
                    report_roadmap(
                        f"in-scope item '{child_leaf}' is placed in horizon '{seen_items[child_leaf]}' "
                        f"while its parent '{node['text']}' is also placed as a standalone item in '{parent_h}'."
                    )

    # 3. Completeness: every top-level In scope item (or all of its leaf sub-items) must be scheduled
    for node in in_scope_tree:
        if not node["children"]:
            if node["text"] not in seen_items:
                report_roadmap(
                    f"in-scope item '{node['text']}' is missing from all roadmap horizons (Now, Next, Later)"
                )
        else:
            if node["text"] in seen_items:
                continue
            for child_leaf in tree_leaf_texts(node["children"]):
                if child_leaf not in seen_items:
                    report_roadmap(
                        f"in-scope item '{child_leaf}' is missing from all roadmap horizons (Now, Next, Later)"
                    )

    # 4. Out of scope exclusivity: no out of scope item in horizons
    for horizon, item in all_roadmap_nodes:
        if item in out_of_scope_set:
            report_roadmap(
                f"out-of-scope item '{item}' appears in roadmap horizon '{horizon}'"
            )

    # 5. Out of scope completeness in roadmap: all out-of-scope items from discovery must be recorded in roadmap Out of scope
    disc_oos_leaves = tree_leaf_texts(out_of_scope_tree)
    if disc_oos_leaves:
        roadmap_oos_raw = roadmap_sections.get("out of scope", "")
        if not roadmap_oos_raw:
            report_roadmap("roadmap is missing required 'Out of scope' section")
        else:
            roadmap_oos_tree = parse_bullet_tree(roadmap_oos_raw)
            roadmap_oos_set = set(tree_all_texts(roadmap_oos_tree))
            for oos_leaf in disc_oos_leaves:
                if oos_leaf not in roadmap_oos_set:
                    report_roadmap(
                        f"out-of-scope item '{oos_leaf}' from discovery is missing from roadmap Out of scope section"
                    )

    # 6. Timing consistency: items with explicit horizon/timing indicators must not contradict their horizon
    for horizon, item in all_roadmap_nodes:
        lower_item = item.lower()
        if horizon == "Now":
            if re.search(r"\b(?:added\s+later|deferred|future\s+phase|planned\s+for\s+later)\b", lower_item) or re.match(r"^\*?\*?\s*later\b", lower_item):
                report_roadmap(
                    f"item '{item}' denotes later timing but is placed in horizon 'Now'"
                )
            elif re.search(r"\b(?:the\s+next\s+integration|next\s+phase)\b", lower_item):
                report_roadmap(
                    f"item '{item}' denotes next integration/phase but is placed in horizon 'Now'"
                )
        elif horizon == "Later":
            if re.search(r"\b(?:current\s+delivery|immediate\s+delivery)\b", lower_item):
                report_roadmap(
                    f"item '{item}' denotes current delivery but is placed in horizon 'Later'"
                )

    # 7. No leftover placeholders in roadmap content sections
    for sec_name in ["problem", "success metric", "chosen option", "now", "next", "later", "out of scope"]:
        sec_body = roadmap_sections.get(sec_name, "")
        if sec_body:
            ph = PLACEHOLDER.search(sec_body)
            if ph:
                report_roadmap(
                    f"roadmap section '{sec_name}' contains unresolved placeholder: '{ph.group(0)}'"
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
