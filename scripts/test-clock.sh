#!/bin/sh
# test-clock.sh — kitfix-20261031-single-clock: every date sync-feature-state.sh writes comes from one
# clock in the project time zone, including the midnight case in a non-UTC zone (Asia/Manila, +08:00)
# that broke P2-A H3 in e2e run 20261029-1629. Run by validate-kit.sh. Needs python3 (zoneinfo).
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$KIT/templates/.agents-v0/scripts"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0
pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d
for k in sys.argv[2].split("."): v=(v or {}).get(k) if isinstance(v,dict) else None
print("" if v is None else v)' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (wanted '$3', got '$2')"; fi; }

fixture() {
  d="$tmp/$1"; mkdir -p "$d/.agents-v0/scripts" "$d/docs/agents-v0/requirements"
  cp "$SC/sync-feature-state.sh" "$SC/check-story-dependencies.sh" "$d/.agents-v0/scripts/"
  cat > "$d/docs/agents-v0/requirements/orders.md" <<'EOF'
# Orders
As a clerk, I want to place an order, so that stock is reserved.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/orders.md | mdurana | Approved | - |
EOF
  printf '%s\n' "$d"
}
ST=docs/agents-v0/requirements/orders.state.json
ART=docs/agents-v0/requirements/orders.md

# 1. 00:30 Asia/Manila on 2026-10-30 is 16:30 UTC on 2026-10-29; the process itself runs in UTC.
d="$(fixture manila-midnight)"
(cd "$d" && TZ=UTC AGENTS_V0_TZ=Asia/Manila AGENTS_V0_NOW=2026-10-29T16:30:00Z \
  sh .agents-v0/scripts/sync-feature-state.sh --approve intake "$ART" >/dev/null 2>"$tmp/err1")
check "midnight Asia/Manila: phaseDates.intake is the Manila date" "$(jget "$d/$ST" phaseDates.intake)" 2026-10-30
check "midnight Asia/Manila: phaseTimes.intake carries +08:00" "$(jget "$d/$ST" phaseTimes.intake)" 2026-10-30T00:30:00+08:00
case "$(jget "$d/$ST" updatedAt)" in *+08:00) pass "updatedAt uses the same clock (+08:00)";; *) fail "updatedAt uses the same clock (got $(jget "$d/$ST" updatedAt))";; esac
grep -Eq '^\| Intake \|.*\| Approved \| 2026-10-30 \|$' "$d/$ART" && pass "the script wrote the Date cell of the approved row (D2)" \
  || fail "the script wrote the Date cell of the approved row (D2): $(grep Intake "$d/$ART" | tail -1)"

# 2. A table date typed with `date -u` (the day before) does not move the recorded date.
sed -i.bak 's/| Approved | 2026-10-30 |/| Approved | 2026-10-29 |/' "$d/$ART" && rm -f "$d/$ART.bak"
(cd "$d" && AGENTS_V0_TZ=Asia/Manila sh .agents-v0/scripts/sync-feature-state.sh "$ART" >/dev/null 2>"$tmp/err2")
check "a UTC table date does not overwrite the recorded approval date" "$(jget "$d/$ST" phaseDates.intake)" 2026-10-30
grep -Fq 'WARN: Delivery approvals date for intake (2026-10-29) differs' "$tmp/err2" && pass "the mismatch is reported as a WARN" \
  || fail "the mismatch is reported as a WARN ($(cat "$tmp/err2"))"

# 3. Approvals 23:50 and 00:30 Manila across midnight: dates non-decreasing, times strictly increasing.
d="$(fixture across-midnight)"
(cd "$d" && TZ=UTC AGENTS_V0_TZ=Asia/Manila AGENTS_V0_NOW=2026-10-29T23:50:00+08:00 \
  sh .agents-v0/scripts/sync-feature-state.sh --approve intake "$ART" >/dev/null 2>&1)
printf '| Design | docs/agents-v0/design/orders/design.md | mdurana | Approved | - |\n' >> "$d/$ART"
(cd "$d" && TZ=UTC AGENTS_V0_TZ=Asia/Manila AGENTS_V0_NOW=2026-10-29T16:30:00Z \
  sh .agents-v0/scripts/sync-feature-state.sh --approve design "$ART" >/dev/null 2>&1)
check "across midnight: intake date" "$(jget "$d/$ST" phaseDates.intake)" 2026-10-29
check "across midnight: design date" "$(jget "$d/$ST" phaseDates.design)" 2026-10-30
python3 - "$d/$ST" <<'EOF' && pass "across midnight: phaseDates non-decreasing and phaseTimes increasing (H3)" || fail "across midnight: order"
import json, sys, datetime as dt
s = json.load(open(sys.argv[1])); d = s["phaseDates"]; t = s["phaseTimes"]
assert d["intake"] <= d["design"]
assert dt.datetime.fromisoformat(t["intake"]) < dt.datetime.fromisoformat(t["design"])
EOF

# 4. The project-profile Timezone row is used when AGENTS_V0_TZ is not set.
d="$(fixture profile-zone)"
printf '| Field | Value |\n|---|---|\n| Timezone | Asia/Manila |\n' > "$d/docs/agents-v0/project-profile.md"
(cd "$d" && TZ=UTC AGENTS_V0_NOW=2026-10-29T16:30:00Z sh .agents-v0/scripts/sync-feature-state.sh --approve intake "$ART" >/dev/null 2>&1)
check "project-profile Timezone row sets the zone" "$(jget "$d/$ST" phaseDates.intake)" 2026-10-30

# 5. No zone configured: the system zone (TZ) is used.
d="$(fixture system-zone)"
(cd "$d" && TZ=UTC AGENTS_V0_NOW=2026-10-29T16:30:00Z sh .agents-v0/scripts/sync-feature-state.sh --approve intake "$ART" >/dev/null 2>&1)
check "no zone configured: the system zone (UTC here) is used" "$(jget "$d/$ST" phaseDates.intake)" 2026-10-29

# 6. Old state files (no phaseTimes, updatedAt ending in Z) still load and keep their dates.
d="$(fixture old-state)"
printf '{"approvedPhases":["intake"],"lastApprovedPhase":"intake","phaseDates":{"intake":"2026-10-01"},"updatedAt":"2026-10-01T01:00:00Z"}\n' > "$d/$ST"
(cd "$d" && AGENTS_V0_TZ=Asia/Manila sh .agents-v0/scripts/sync-feature-state.sh "$ART" >/dev/null 2>&1) && pass "an old state file syncs" || fail "an old state file syncs"
check "an old state file keeps its intake date" "$(jget "$d/$ST" phaseDates.intake)" 2026-10-01

if [ "$status" -ne 0 ]; then echo "test-clock: FAILED" >&2; exit 1; fi
echo "test-clock: OK"
