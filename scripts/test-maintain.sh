#!/bin/sh
# test-maintain.sh — behavior tests for the maintenance lane (no network).
# Covers: sync-feature-state.sh for maintenance notes (trivial, standard, emergency,
# --approve, --reopen, --verify-passed, artifacts map) and delivery-metrics.sh follow-ups.
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }

r="$tmp/repo"
mkdir -p "$r/.agents-v0/scripts" "$r/src/main/java/com/acme" "$r/docs/agents-v0/requirements" "$r/docs/agents-v0/build/old"
cp "$KIT"/templates/.agents-v0/scripts/sync-feature-state.sh \
   "$KIT"/templates/.agents-v0/scripts/delivery-metrics.sh \
   "$KIT"/templates/.agents-v0/scripts/packlib.py \
   "$KIT"/templates/.agents-v0/scripts/resolve-layout.sh \
   "$KIT"/templates/.agents-v0/scripts/resolve-integration-branch.sh "$r/.agents-v0/scripts/"

git_c() { git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }

printf 'package com.acme;\npublic class Foo {\n  int a() { return 1; }\n}\n' > "$r/src/main/java/com/acme/Foo.java"
(cd "$r" && git init -q && git add -A && git_c commit -q -m base)
main="$(cd "$r" && git rev-parse --abbrev-ref HEAD)"

branch() { (cd "$r" && git checkout -q "$main" && git checkout -q -b "$1"); }
commit() { (cd "$r" && git add -A && git_c commit -q -m "$1"); }
# Release is approved only on the integration branch (kitfix-20261029-step4-p1e): merge the story branch first.
merge_to_main() { (cd "$r" && b="$(git rev-parse --abbrev-ref HEAD)" && git checkout -q "$main" && git_c merge -q --no-ff -m "merge $b" "$b"); }

make_note() { # id tier extra-lines(\n separated) with-verify(yes|no) rollback-text [approve-maintain yes|no]
  id="$1"; tier="$2"; extra="$3"; with_verify="$4"; rollback="$5"
  approve_maintain="${6:-yes}"
  mkdir -p "$r/docs/agents-v0/maintain/$id" "$r/docs/agents-v0/verify/$id"
  {
    printf '# Maintenance note: test\n\nId: %s\nTier: %s\n' "$id" "$tier"
    [ -z "$extra" ] || printf '%b\n' "$extra"
    printf '\n## Rollback\n\n%s\n\n## Delivery approvals\n\n' "$rollback"
    printf '| Phase | Artifacts | Approver | Decision | Date |\n|---|---|---|---|---|\n'
    if [ "$approve_maintain" != no ]; then
      printf '| maintain | docs/agents-v0/maintain/%s/note.md | dev | Approved | 2026-01-01 |\n' "$id"
    fi
    if [ "$with_verify" = yes ]; then printf '| verify | docs/agents-v0/verify/%s/test-report.md | dev | Approved | 2026-01-02 |\n' "$id"; fi
  } > "$r/docs/agents-v0/maintain/$id/note.md"
  printf 'Line coverage 90%%\n' > "$r/docs/agents-v0/verify/$id/test-report.md"
}
confirmed='Tier confirmed by: Ada on 2026-01-01'
rollback='Revert the commit.'

# --- state and metrics for notes ---------------------------------------------
branch s-state; make_note fix-10 standard "" no "$rollback" no; commit state
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/fix-10/note.md --active-phase maintain --status in_progress >/dev/null 2>&1) \
   && grep -Fq '"feature": "fix-10"' "$r/docs/agents-v0/maintain/fix-10/state.json" \
   && grep -Fq '"activePhase": "maintain"' "$r/docs/agents-v0/maintain/fix-10/state.json" \
   && grep -Fq '"tier": "standard"' "$r/docs/agents-v0/maintain/fix-10/state.json"; then
  pass "state: a note keeps docs/agents-v0/maintain/<id>/state.json with its tier"
else
  fail "state: a note keeps docs/agents-v0/maintain/<id>/state.json with its tier"
fi
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/fix-10/note.md --active-phase intake --status in_progress >/dev/null 2>&1); then
  fail "state: intake is not a phase of a maintenance note"
else
  pass "state: intake is not a phase of a maintenance note"
fi
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/fix-10/note.md --active-phase release --status in_progress >/dev/null 2>&1) \
   && grep -Fq '"activePhase": "release"' "$r/docs/agents-v0/maintain/fix-10/state.json"; then
  pass "state: release is a valid phase of a maintenance note"
else
  fail "state: release is a valid phase of a maintenance note"
fi
printf '| maintain | docs/agents-v0/maintain/fix-10/note.md | dev | Approved | 2026-01-01 |\n' >> "$r/docs/agents-v0/maintain/fix-10/note.md"
(cd "$r" && git add docs/agents-v0/maintain/fix-10/note.md && git_c commit -q -m "approve maintain row")
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/fix-10/note.md >/dev/null 2>&1) && grep -Fq '"lastApprovedPhase": "maintain"' "$r/docs/agents-v0/maintain/fix-10/state.json"; then
  pass "state: the maintain approval is derived"
else
  fail "state: the maintain approval is derived"
fi
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/fix-10/note.md --approve verify --verify-passed true --clear-active >/dev/null 2>&1) \
   && grep -Fq '"lastApprovedPhase": "verify"' "$r/docs/agents-v0/maintain/fix-10/state.json" \
   && grep -Fq '"verifyPassed": true' "$r/docs/agents-v0/maintain/fix-10/state.json"; then
  pass "state: --approve verify --verify-passed true updates maintenance state.json"
else
  fail "state: --approve verify --verify-passed true updates maintenance state.json"
fi

branch s-metrics; make_note fix-11 emergency "$confirmed\nFollow-up verify due: 2020-01-01" no "$rollback"; commit metrics
if (cd "$r" && sh .agents-v0/scripts/delivery-metrics.sh . 2>/dev/null) | grep -F 'fix-11' | grep -Fq 'OVERDUE'; then
  pass "metrics: an emergency note past its follow-up date is OVERDUE"
else
  fail "metrics: an emergency note past its follow-up date is OVERDUE"
fi

phases_of() { # id
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(",".join(d["approvedPhases"])); print("true" if d["verifyPassed"] else "false")' \
    "$r/docs/agents-v0/maintain/$1/state.json"
}
branch s-emergency-release
make_note fix-12 emergency "$confirmed\nFollow-up verify due: 2026-12-31" no "$rollback"
commit emergency-release
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh --approve release docs/agents-v0/maintain/fix-12/note.md >/dev/null 2>&1); then
  fail "state: --approve release is refused on a story branch (kitfix-20261029-step4-p1e)"
else
  pass "state: --approve release is refused on a story branch (kitfix-20261029-step4-p1e)"
fi
merge_to_main
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh --approve release docs/agents-v0/maintain/fix-12/note.md >/dev/null) \
   && [ "$(phases_of fix-12)" = "$(printf 'maintain,release\nfalse')" ]; then
  pass "state: emergency --approve release does not backfill verify or set verifyPassed"
else
  fail "state: emergency --approve release does not backfill verify or set verifyPassed"
fi
branch s-standard-release; make_note fix-13 standard "" no "$rollback"
commit standard-release
merge_to_main
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh --approve release docs/agents-v0/maintain/fix-13/note.md >/dev/null) \
   && [ "$(phases_of fix-13)" = "$(printf 'maintain,verify,release\ntrue')" ]; then
  pass "state: standard --approve release still backfills verify and sets verifyPassed"
else
  fail "state: standard --approve release still backfills verify and sets verifyPassed"
fi
branch s-emergency-verified; make_note fix-14 emergency "$confirmed\nFollow-up verify due: 2026-12-31" yes "$rollback"
commit emergency-already-verified
merge_to_main
if (cd "$r" && sh .agents-v0/scripts/sync-feature-state.sh --approve release docs/agents-v0/maintain/fix-14/note.md >/dev/null) \
   && [ "$(phases_of fix-14)" = "$(printf 'maintain,verify,release\ntrue')" ]; then
  pass "state: emergency --approve release keeps verify when it was already approved"
else
  fail "state: emergency --approve release keeps verify when it was already approved"
fi

if [ "$status" -ne 0 ]; then
  echo "test-maintain: FAILED" >&2
  exit 1
fi
echo "test-maintain: OK"
