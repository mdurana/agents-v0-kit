#!/bin/sh
# check-milestone.sh — milestone go/no-go aggregation (workflow-orchestration.mdc).
# Given a milestone manifest (docs/agents-v0/milestones/<milestone>.md), verifies that every
# user story with a concrete feature-artifact path exists, records the phase
# approval in its canonical Delivery approvals table, and — for build/verify —
# that the recorded evidence paths exist. Rows with dynamic/placeholder paths
# (<...>) or no path are skipped: a milestone go/no-go passes only when every
# story row carries a concrete, approved artifact.
#
# A P4 manifest that names docs/agents-v0/design/system/slo-evidence.md accepts a waiver by default;
# SLO_ALLOW_WAIVERS=0 requires every row to be measured.
# Story order is checked too: a build-approved story fails when a story named in its
# Dependency column has no verify approval (MILESTONE_ORDER=0 disables that check).
#
# Usage: sh check-milestone.sh <manifest> <phase>
#   <manifest>  e.g. docs/agents-v0/milestones/p2-mvp-core-features.md
#   <phase>     plan | intake | design | build | verify | release
#   The milestone-level decision row itself is checked by
#   ci/check-approvals.sh <manifest> milestone.
#
# Exit codes: 0 = every concrete story artifact passed the phase gate; 1 = missing
# manifest, no Stories section, story artifact missing/unapproved, evidence
# missing, or no concrete story rows. Story status is prose; this script checks
# recorded evidence only.

set -eu

manifest="${1:-}"
phase="${2:-}"
if [ -z "$manifest" ] || [ -z "$phase" ]; then
  printf 'usage: %s <manifest> <phase>\n' "$0" >&2
  exit 1
fi
case "$phase" in
  plan|intake|design|build|verify|release) ;;
  *)
    printf 'FAIL: unknown phase "%s" (expected plan|intake|design|build|verify|release)\n' "$phase" >&2
    exit 1
    ;;
esac
[ -f "$manifest" ] || { printf 'FAIL: milestone manifest not found: %s\n' "$manifest" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"

roadmap="$(sed -n 's/^[[:space:]]*Roadmap:[[:space:]]*//p' "$manifest" | head -n 1 | sed 's/[[:space:]]*$//')"
if [ -n "$roadmap" ]; then
  sh "$here/check-approvals.sh" "$roadmap" roadmap || exit 1
fi
arch="$(sed -n 's/^[[:space:]]*Architecture:[[:space:]]*//p' "$manifest" | head -n 1 | sed 's/[[:space:]]*$//')"
if [ -n "$arch" ]; then
  sh "$here/check-approvals.sh" "$arch" architecture || exit 1
  sh "$here/check-architecture-pack.sh" --approved "$arch" || exit 1
fi

# Stories table: | Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
# In "plan" phase, User story, Dependency, Surface, and Size are validated against the Plan gate.
# A "Roadmap:" line names a file that must carry an Approved roadmap row.
# An "Architecture:" line names a file that must carry an Approved architecture row and a
# complete pack (check-architecture-pack.sh --approved).
section="$(awk '
  /^#+[[:space:]]*[Ss]tories/ { in_section = 1; next }
  /^#+[[:space:]]/ { in_section = 0 }
  in_section
' "$manifest")"
[ -n "$section" ] || { printf 'FAIL: %s has no "Stories" section\n' "$manifest" >&2; exit 1; }

artifacts="$(printf '%s\n' "$section" | awk -F'|' '
  /---/ { next }
  /Story [Ii][Dd]/ { next }
  /^[[:space:]]*\|/ {
    a = $4
    gsub(/^[ \t]+|[ \t]+$/, "", a)
    if (a != "") print a
  }')"

missing=0
checked=0
if [ "$phase" = "plan" ]; then
  for a in $artifacts; do
    case "$a" in
      *'<'*|*'>'*|*'['*|*']'*)
        printf 'FAIL: milestone story row still has placeholder artifact path: %s\n' "$a" >&2
        missing=1
        continue
        ;;
    esac
    checked=$((checked + 1))
  done
  [ "$checked" -gt 0 ] || { printf 'FAIL: %s has no story rows\n' "$manifest" >&2; missing=1; }
else
  for a in $artifacts; do
    case "$a" in
      *'<'*|*'>'*)
        printf 'FAIL: milestone story row still has placeholder artifact path: %s\n' "$a" >&2
        missing=1
        continue
        ;;
    esac
    if [ ! -f "$a" ]; then
      printf 'FAIL: milestone story artifact missing on disk: %s\n' "$a" >&2
      missing=1
      continue
    fi
    if ! sh "$here/check-approvals.sh" "$a" "$phase"; then
      missing=1
      continue
    fi
    case "$phase" in
      build|verify)
        sh "$here/check-evidence.sh" "$a" "$phase" || missing=1
        ;;
    esac
    checked=$((checked + 1))
  done
fi

# Story order: a story with a build approval needs a verify approval on every story
# it names in the Dependency column (including cross-milestone story dependencies).
# A dependency that is a manifest path (*.md) instead needs an Approved milestone row
# on that file.
# The story dependency graph is checked across all milestone manifests (excluding
# _template.md and plan.md) to reject duplicate/placeholder story IDs and enforce
# that the graph is strictly acyclic.
# In "plan" phase, every story row in the target manifest is also checked for a complete
# As a / I want / so that sentence without placeholders, concrete story-ID dependencies
# (rejecting bare milestone stubs like P0/P1/P3), valid Surface, and Size 1..8 (4 for P0-A).
# MILESTONE_ORDER=0 turns the check off.
has_approval() {
  sh "$here/check-approvals.sh" "$1" "$2" >/dev/null 2>&1
}

check_story_order() {
  [ "${MILESTONE_ORDER:-1}" != "0" ] || return 0
  rows="$(printf '%s\n' "$section" | awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /---/ { next }
    /Story [Ii][Dd]/ { next }
    /^[[:space:]]*\|/ {
      id = trim($2); story = trim($3); art = trim($4); status = trim($5); dep = trim($6); surf = trim($7); sz = trim($8)
      if (id != "") printf "%s^%s^%s^%s^%s^%s^%s\n", id, art, dep, story, surf, sz, status
    }')"
  ids="$(printf '%s\n' "$rows" | awk -F'^' '{ print $1 }')"

  # Gather story rows across all milestone manifests in the directory (excluding _*.md and plan.md)
  manifest_dir="$(dirname "$manifest")"
  all_manifests="$(find "$manifest_dir" -maxdepth 1 -name '*.md' ! -name '_*.md' ! -name 'plan.md' 2>/dev/null | tr '\n' ' ' || true)"
  case " $all_manifests " in
    *" $manifest "*) ;;
    *) all_manifests="$all_manifests $manifest" ;;
  esac
  all_rows="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    FNR == 1 { file_seen[FILENAME]++; in_section = 0 }
    file_seen[FILENAME] > 1 { next }
    /^#+[[:space:]]*[Ss]tories/ { in_section = 1; next }
    /^#+[[:space:]]/ { in_section = 0 }
    !in_section { next }
    /---/ { next }
    /Story [Ii][Dd]/ { next }
    /^[[:space:]]*\|/ {
      id = trim($2); art = trim($4); dep = trim($6)
      if (id != "") printf "%s^%s^%s^%s\n", id, art, dep, FILENAME
    }
  ' $all_manifests 2>/dev/null || true)"
  all_ids="$(printf '%s\n' "$all_rows" | awk -F'^' '{ print $1 }')"

  order_fail=0

  # 1. Enforce unique, non-placeholder story IDs, acyclic graph, and (in plan phase) full row rules
  if [ -n "$all_rows" ]; then
    cycle_out="$(ALL_ROWS="$all_rows" TARGET_ROWS="$rows" PHASE="$phase" MANIFEST="$manifest" python3 - <<'PY' 2>&1
import sys, os, re

rows_text = os.environ.get("ALL_ROWS", "")
target_text = os.environ.get("TARGET_ROWS", "")
phase = os.environ.get("PHASE", "")
manifest = os.environ.get("MANIFEST", "")

lines = [l.strip() for l in rows_text.strip().split("\n") if l.strip()]
target_lines = [l.strip() for l in target_text.strip().split("\n") if l.strip()]

errors = []
seen_ids = {}
all_ids = set()

for line in lines:
    parts = line.split("^")
    if len(parts) >= 4:
        sid = parts[0].strip()
        fname = parts[3].strip()
        if not sid:
            continue
        if re.search(r"[<>]|\[.*\]", sid):
            if os.path.abspath(fname) == os.path.abspath(manifest):
                errors.append(f"FAIL: story row in {fname} still has placeholder story ID: {sid}")
            continue
        if sid in seen_ids:
            errors.append(f"FAIL: duplicate story ID {sid} (in {seen_ids[sid]} and {fname})")
        else:
            seen_ids[sid] = fname
            all_ids.add(sid)

graph = {uid: [] for uid in all_ids}

for line in lines:
    parts = line.split("^")
    if len(parts) >= 3:
        sid = parts[0].strip()
        if sid not in graph:
            continue
        deps_raw = parts[2].strip()
        deps = [d.strip() for d in re.split(r'[,;\s]+', deps_raw) if d.strip()]
        for d in deps:
            if d == sid:
                errors.append(f"FAIL: story dependency cycle detected: {sid} -> {sid}")
            elif d in all_ids:
                graph[sid].append(d)

WHITE, GRAY, BLACK = 0, 1, 2
color = {u: WHITE for u in all_ids}

def dfs(u, path):
    color[u] = GRAY
    for v in graph.get(u, []):
        if color.get(v) == GRAY:
            cycle = path + [v]
            idx = cycle.index(v)
            cycle_str = " -> ".join(cycle[idx:])
            errors.append(f"FAIL: story dependency cycle detected: {cycle_str}")
        elif color.get(v) == WHITE:
            dfs(v, path + [v])
    color[u] = BLACK

for u in sorted(all_ids):
    if color[u] == WHITE:
        dfs(u, [u])

if phase == "plan":
    valid_surfaces = {"backend", "bff", "frontend", "vertical slice"}
    for line in target_lines:
        parts = line.split("^")
        while len(parts) < 7:
            parts.append("")
        sid, art, dep, story, surf, sz, status = [p.strip() for p in parts[:7]]
        if not sid:
            continue
        if re.search(r"<[^>]+>|\[[^\]]+\]", story):
            errors.append(f"FAIL: story {sid} user story still has placeholder tokens: {story}")
        elif not re.match(r"^As an?\s+\S.*,\s*I want\s+\S.*(?:,|\s+[—–-])\s*so that\s+\S+", story, re.I):
            errors.append(f"FAIL: story {sid} user story must follow 'As a <role>, I want <goal>, so that <benefit>.': {story}")
        if not dep:
            errors.append(f"FAIL: story {sid} has an empty Dependency cell (use — when there is no dependency)")
        else:
            for d in [x.strip() for x in re.split(r'[,;\s]+', dep) if x.strip()]:
                if d in {"-", "—", "None", "none"}:
                    continue
                if re.match(r"^P[0-9]+$", d):
                    errors.append(f"FAIL: story {sid} still has milestone-level dependency stub '{d}' (replace with concrete story IDs or —)")
                elif d.endswith(".md"):
                    if not os.path.isfile(d):
                        errors.append(f"FAIL: story {sid} names dependency manifest that does not exist: {d}")
                elif d not in all_ids:
                    errors.append(f"FAIL: story {sid} names unknown dependency story {d}")
        if surf.lower() not in valid_surfaces:
            errors.append(f"FAIL: story {sid} has invalid or missing Surface '{surf}' (expected backend|bff|frontend|vertical slice)")
        try:
            sz_int = int(sz)
            if sid == "P0-A" and sz_int != 4:
                errors.append(f"FAIL: seeded story P0-A Size must be 4 (got {sz_int})")
            elif sz_int < 1 or sz_int > 8:
                errors.append(f"FAIL: story {sid} Size must be between 1 and 8 (got {sz_int})")
        except ValueError:
            errors.append(f"FAIL: story {sid} has invalid or missing Size '{sz}' (expected integer 1..8)")

if errors:
    for e in errors:
        print(e)
    sys.exit(1)
PY
    )" || {
      printf '%s\n' "$cycle_out" >&2
      order_fail=1
    }
  fi

  if [ "$phase" = "plan" ]; then
    return "$order_fail"
  fi

  # 2. Build/verify/intake/design/release: check verify approval on build-approved stories
  while IFS='^' read -r sid sart sdep _rest; do
    [ -n "$sid" ] || continue
    case "$sart" in ''|*'<'*|*'>'*) continue ;; esac
    [ -f "$sart" ] || continue
    has_approval "$sart" build || continue

    for dep in $(printf '%s' "$sdep" | tr ',;' '  '); do
      case "$dep" in
        ''|'-'|'—'|'None'|'none') continue ;;
        P[0-9]|P[0-9][0-9]) continue ;;
        *.md)
          if [ ! -f "$dep" ] || ! has_approval "$dep" milestone; then
            printf 'FAIL: story %s is build-approved but dependency manifest %s has no approved milestone row\n' "$sid" "$dep" >&2
            order_fail=1
          fi
          continue
          ;;
      esac

      if printf '%s\n' "$all_ids" | grep -Fxq "$dep"; then
        dart="$(printf '%s\n' "$all_rows" | awk -F'^' -v d="$dep" '$1 == d { print $2; exit }')"
        case "$dart" in ''|*'<'*|*'>'*)
          printf 'FAIL: story %s is build-approved but its dependency %s has no concrete artifact\n' "$sid" "$dep" >&2
          order_fail=1
          continue
          ;;
        esac
        if [ ! -f "$dart" ] || ! has_approval "$dart" verify; then
          printf 'FAIL: story %s is build-approved but its dependency %s has no verify approval (%s)\n' "$sid" "$dep" "$dart" >&2
          order_fail=1
        fi
      else
        case "$dep" in
          *-*)
            printf 'FAIL: story %s is build-approved but its dependency %s was not found in any milestone manifest\n' "$sid" "$dep" >&2
            order_fail=1
            ;;
        esac
      fi
    done
  done <<EOF
$rows
EOF
  return "$order_fail"
}

if ! check_story_order; then
  missing=1
fi

check_slo_evidence() {
  grep -Fq 'docs/agents-v0/design/system/slo-evidence.md' "$manifest" || return 0
  case "$phase" in
    verify|release) ;;
    *) return 0 ;;
  esac
  ev="docs/agents-v0/design/system/slo-evidence.md"
  if [ ! -f "$ev" ]; then
    printf 'FAIL: SLO evidence file missing: %s (slo-evidence skill)\n' "$ev" >&2
    return 1
  fi
  slo_fail=0
  # awk prints one result line per evidence row:
  # ok, bad-kind, bad-fields, bad-path, missing-file. Measured files are
  # checked in the shell so the test does not depend on awk's system().
  parsed="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[[:space:]]*\|/ {
      if ($0 ~ /---/) next
      surface = trim($2)
      if (surface == "" || surface == "Surface") next
      kind = tolower(trim($3))
      cmd = trim($4)
      out = trim($5)
      date = trim($6)
      n++
      if (kind != "measured" && kind != "waiver") {
        printf "bad-kind\t%s\t%s\n", surface, kind
        next
      }
      if (cmd == "" || out == "" || date !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
        printf "bad-fields\t%s\n", surface
        next
      }
      if (kind == "measured" && (out ~ /(^|\/)\.\.(\/|$)/ || out ~ /^\//)) {
        printf "bad-path\t%s\t%s\n", surface, out
        next
      }
      printf "%s\t%s\t%s\n", kind, surface, out
    }
    END { if (n == 0) print "empty" }
  ' "$ev")"
  case "$parsed" in
    empty|"")
      printf 'FAIL: %s has no SLO evidence rows\n' "$ev" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$parsed" | while IFS= read -r line; do
    kind="${line%%	*}"
    rest="${line#*	}"
    surface="${rest%%	*}"
    out="${rest#*	}"
    case "$kind" in
      bad-kind)
        printf 'FAIL: SLO row "%s" kind must be measured or waiver (got "%s")\n' "$surface" "$out" >&2
        echo fail >>"$slo_mark"
        ;;
      bad-fields)
        printf 'FAIL: SLO row "%s" needs a command or reason, an output or approver, and a YYYY-MM-DD date\n' "$surface" >&2
        echo fail >>"$slo_mark"
        ;;
      bad-path)
        printf 'FAIL: SLO output path must be a repo-relative file without "..": %s\n' "$out" >&2
        echo fail >>"$slo_mark"
        ;;
      measured)
        if [ ! -f "$out" ]; then
          printf 'FAIL: SLO output file missing for "%s": %s\n' "$surface" "$out" >&2
          echo fail >>"$slo_mark"
        fi
        ;;
      waiver)
        if [ "${SLO_ALLOW_WAIVERS:-1}" = "0" ]; then
          printf 'FAIL: SLO row "%s" is a waiver and SLO_ALLOW_WAIVERS=0 requires a measurement\n' "$surface" >&2
          echo fail >>"$slo_mark"
        fi
        ;;
    esac
  done
  nfr="docs/agents-v0/design/system/nfr-slo.md"
  if [ -f "$nfr" ]; then
    awk -F'|' '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      /^[[:space:]]*\|/ {
        if ($0 ~ /---/) next
        name = trim($2)
        if (name == "" || name == "Surface" || name == "Tier") next
        rest = ""
        for (i = 3; i <= NF; i++) rest = rest $i
        gsub(/[ \t|]/, "", rest)
        if (rest != "") print name
      }
    ' "$nfr" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      if ! printf '%s\n' "$parsed" | awk -F'	' -v n="$name" '$2 == n { found = 1 } END { exit !found }'; then
        printf 'FAIL: filled NFR/SLO row "%s" has no row in %s\n' "$name" "$ev" >&2
        echo fail >>"$slo_mark"
      fi
    done
  fi
  if [ -f "$slo_mark" ]; then
    rm -f "$slo_mark"
    slo_fail=1
  fi
  return "$slo_fail"
}

slo_mark="$(mktemp)"
rm -f "$slo_mark"
if ! check_slo_evidence; then
  missing=1
fi
rm -f "$slo_mark"

if [ "$checked" -eq 0 ] && [ "$missing" -eq 0 ]; then
  printf 'FAIL: no concrete story artifact paths in %s (all rows are dynamic or empty)\n' "$manifest" >&2
  exit 1
fi
if [ "$missing" -eq 1 ]; then
  exit 1
fi
printf 'OK: %s story artifact(s) passed the "%s" gate for %s\n' "$checked" "$phase" "$manifest"