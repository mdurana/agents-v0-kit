#!/bin/sh
# test-maintain.sh — behavior tests for the maintenance lane (no network).
# Covers: ci/classify-change.sh, the maintenance-note checks in ci/check-delivery-linkage.sh
# (trivial, standard, emergency, borrowed feature artifact), sync-feature-state.sh for notes,
# and delivery-metrics.sh follow-ups. Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }

r="$tmp/repo"
mkdir -p "$r/ci" "$r/scripts" "$r/src/main/java/com/acme" "$r/src/main/resources" "$r/docs/requirements" "$r/docs/build/old"
cp "$KIT"/templates/ci/*.sh "$r/ci/"
cp "$KIT"/templates/scripts/sync-feature-state.sh "$KIT"/templates/scripts/delivery-metrics.sh "$r/scripts/"

git_c() { git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }

cat > "$r/pom.xml" <<'EOF'
<project>
  <dependencies>
    <dependency>
      <artifactId>lib</artifactId>
      <version>3.2.5</version>
    </dependency>
  </dependencies>
</project>
EOF
printf 'package com.acme;\npublic class Foo {\n  int a() { return 1; }\n}\n' > "$r/src/main/java/com/acme/Foo.java"
printf '@RestController\npublic class BarController {\n  @GetMapping("/x") String x() { return "a"; }\n}\n' > "$r/src/main/java/com/acme/BarController.java"
printf '# Readme\n' > "$r/README.md"
printf '{\n  "scripts": {\n    "test": "jest"\n  },\n  "dependencies": {\n    "express": "^4.18.2"\n  }\n}\n' > "$r/package.json"
printf 'dependencies {\n  implementation '"'"'org.a:b:1.0.0'"'"'\n}\n' > "$r/build.gradle"
cat > "$r/docs/requirements/old.md" <<'EOF'
# Old feature

AC-1: the first acceptance criterion

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/requirements/old.md | dev | Approved | 2025-01-01 |
| Build | docs/build/old/build-report.md | dev | Approved | 2025-01-02 |
EOF
printf 'commit: abcdef1234567\n' > "$r/docs/build/old/build-report.md"
(cd "$r" && git init -q && git add -A && git_c commit -q -m base)
main="$(cd "$r" && git rev-parse --abbrev-ref HEAD)"
base_sha="$(cd "$r" && git rev-parse HEAD)"

branch() { (cd "$r" && git checkout -q "$main" && git checkout -q -b "$1"); }
commit() { (cd "$r" && git add -A && git_c commit -q -m "$1"); }
sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

# classified <description> <expected line> [classify args...]   (run on the current branch)
classified() {
  desc="$1"; want="$2"; shift 2
  if (cd "$r" && sh ci/classify-change.sh "$base_sha" HEAD "$@" 2>/dev/null) | grep -Fxq "$want"; then pass "$desc"; else fail "$desc (missing '$want')"; fi
}
classify_exit() {
  desc="$1"; want="$2"; shift 2
  if (cd "$r" && sh ci/classify-change.sh "$base_sha" HEAD "$@" >/dev/null 2>&1); then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (exit $got, wanted $want)"; fi
}

# --- ci/classify-change.sh ---------------------------------------------------
branch c-docs; printf 'more\n' >> "$r/README.md"; commit docs
classified "classify: README only is docs-only" "class=docs-only"
classified "classify: docs-only is trivial-eligible" "trivial-eligible=yes"

branch c-patch; sedi 's/3.2.5/3.2.6/' "$r/pom.xml"; commit patch
classified "classify: a pom version bump is dependency-version" "class=dependency-version"
classified "classify: a patch bump is not a major bump" "major-bump=no"
classified "classify: a patch bump is trivial-eligible" "trivial-eligible=yes"

branch c-major; sedi 's/3.2.5/4.0.0/' "$r/pom.xml"; commit major
classified "classify: a major bump is flagged" "major-bump=yes"
classify_exit "classify: --require-trivial fails on a major bump" 1 --require-trivial

branch c-newdep
sedi 's|</dependencies>|<dependency><artifactId>other</artifactId></dependency></dependencies>|' "$r/pom.xml"; commit newdep
classified "classify: a new dependency is code, not a version bump" "class=code"

branch c-foo; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit foo
classified "classify: a source edit is code" "class=code"
classified "classify: a plain source edit is not a security surface" "security-surface=no"
classified "classify: code is not trivial-eligible" "trivial-eligible=no"
classify_exit "classify: --max-lines 1 rejects a 2-line edit" 1 --max-lines 1
classify_exit "classify: --max-lines 50 accepts it" 0 --max-lines 50

branch c-ctrl; sedi 's/"a"/"b"/' "$r/src/main/java/com/acme/BarController.java"; commit ctrl
classified "classify: a controller edit is a security surface" "security-surface=yes"

branch c-sql; mkdir -p "$r/src/main/resources/db/migration"; printf 'create table t(id int);\n' > "$r/src/main/resources/db/migration/V1__t.sql"; commit sql
classified "classify: a migration is a schema change" "schema=yes"

branch c-req; printf 'x\n' >> "$r/docs/requirements/old.md"; commit req
classified "classify: a delivery artifact is not trivial-eligible" "trivial-eligible=no"

branch c-npm; sedi 's/\^4.18.2/^4.19.0/' "$r/package.json"; commit npm
classified "classify: a package.json dependency bump is dependency-version" "class=dependency-version"
branch c-npm-script; sedi 's/"jest"/"jest --ci"/' "$r/package.json"; commit npmscript
classified "classify: a package.json script change is code" "class=code"

branch c-gradle; sedi "s|^}|  implementation 'org.c:d:2.0.0'\n}|" "$r/build.gradle"; commit gradle
classified "classify: an added gradle dependency line is code" "class=code"

branch c-wt; sedi 's/3.2.5/3.2.7/' "$r/pom.xml"
if (cd "$r" && sh ci/classify-change.sh "$base_sha" 2>/dev/null) | grep -Fxq "class=dependency-version"; then pass "classify: the working tree is read when no head is given"; else fail "classify: the working tree is read when no head is given"; fi
(cd "$r" && git checkout -q -- pom.xml)

# --- maintenance notes in ci/check-delivery-linkage.sh ----------------------
make_note() { # id tier extra-lines(\n separated) with-verify(yes|no) rollback-text
  id="$1"; tier="$2"; extra="$3"; with_verify="$4"; rollback="$5"
  mkdir -p "$r/docs/maintain/$id" "$r/docs/verify/$id"
  {
    printf '# Maintenance note: test\n\nId: %s\nTier: %s\n' "$id" "$tier"
    [ -z "$extra" ] || printf '%b\n' "$extra"
    printf '\n## Rollback\n\n%s\n\n## Delivery approvals\n\n' "$rollback"
    printf '| Phase | Artifacts | Approver | Decision | Date |\n|---|---|---|---|---|\n'
    printf '| maintain | docs/maintain/%s/note.md | dev | Approved | 2026-01-01 |\n' "$id"
    if [ "$with_verify" = yes ]; then printf '| verify | docs/verify/%s/test-report.md | dev | Approved | 2026-01-02 |\n' "$id"; fi
  } > "$r/docs/maintain/$id/note.md"
  printf 'commit: abcdef1234567\n' > "$r/docs/verify/$id/test-report.md"
}
link() { # expect(pass|fail) description body-text [ENV=VAL ...]
  want="$1"; desc="$2"; text="$3"; shift 3
  printf '%s\n' "$text" > "$tmp/body.md"
  if (cd "$r" && env VERIFY_STALE=0 CHECK_MR_APPROVER=0 "$@" sh ci/check-delivery-linkage.sh "$base_sha" HEAD "$tmp/body.md") >"$tmp/link.out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (wanted $want, got $got: $(tail -n 2 "$tmp/link.out" | tr '\n' ' '))"; fi
  # TEST_VERBOSE=1 shows why a check said no.
  if [ -n "${TEST_VERBOSE:-}" ] && [ "$want" = fail ]; then grep '^FAIL' "$tmp/link.out" | sed 's/^/    | /'; fi
}
confirmed='Tier confirmed by: Ada on 2026-01-01'
rollback='Revert the commit.'

branch m-trivial; make_note fix-1 trivial "$confirmed" yes "$rollback"; sedi 's/3.2.5/3.2.6/' "$r/pom.xml"; commit trivial
link pass "trivial note with a version-only change passes" "Maintain-Note: docs/maintain/fix-1/note.md"
link pass "the note is found from the diff when the body does not name it" ""

branch m-trivial-code; make_note fix-2 trivial "$confirmed" yes "$rollback"; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit trivialcode
link fail "trivial note with a source change is rejected by the classifier" "Maintain-Note: docs/maintain/fix-2/note.md"

branch m-unconfirmed; make_note fix-3 trivial "" yes "$rollback"; sedi 's/3.2.5/3.2.6/' "$r/pom.xml"; commit unconfirmed
link fail "trivial note without a person's confirmation is rejected" "Maintain-Note: docs/maintain/fix-3/note.md"

branch m-notverify; make_note fix-4 trivial "$confirmed" no "$rollback"; sedi 's/3.2.5/3.2.6/' "$r/pom.xml"; commit notverify
link fail "trivial note without a verify row is rejected" "Maintain-Note: docs/maintain/fix-4/note.md"

branch m-standard; make_note fix-5 standard "" yes "$rollback"; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit standard
link pass "standard note with a small source change and a verify row passes" "Maintain-Note: docs/maintain/fix-5/note.md"
link fail "standard note over the line limit is rejected" "Maintain-Note: docs/maintain/fix-5/note.md" MAINTAIN_MAX_LINES=1

branch m-emergency; make_note fix-6 emergency "$confirmed\nFollow-up verify due: 2026-02-01" no "$rollback"; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit emergency
link pass "emergency note merges on the maintain row with a due date and a rollback" "Maintain-Note: docs/maintain/fix-6/note.md"

branch m-emergency-nodue; make_note fix-7 emergency "$confirmed" no "$rollback"; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit nodue
link fail "emergency note without a follow-up due date is rejected" "Maintain-Note: docs/maintain/fix-7/note.md"

branch m-emergency-norollback; make_note fix-8 emergency "$confirmed\nFollow-up verify due: 2026-02-01" no "<!-- TEMPLATE: how to undo -->"; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit norollback
link fail "emergency note without a rollback is rejected" "Maintain-Note: docs/maintain/fix-8/note.md"

branch m-both; make_note fix-9 standard "" yes "$rollback"; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit both
link fail "a note and a feature artifact together are rejected" "Maintain-Note: docs/maintain/fix-9/note.md
Feature-Artifact: docs/requirements/old.md"

# Borrowed feature artifact: an old Build row is not evidence for a new change.
branch f-borrow; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"; commit borrow
link fail "a code change that borrows an old feature artifact is rejected" "Feature-Artifact: docs/requirements/old.md"
link pass "ALLOW_ARTIFACT_WITHOUT_EVIDENCE=1 restores the old behavior" "Feature-Artifact: docs/requirements/old.md" ALLOW_ARTIFACT_WITHOUT_EVIDENCE=1

branch f-real; sedi 's/return 1/return 2/' "$r/src/main/java/com/acme/Foo.java"
mkdir -p "$r/src/test/java"
printf 'class FooTest {\n  void a_returns_two() {}\n}\n' > "$r/src/test/java/FooTest.java"
printf '# Build plan\n\n| AC | Status | Test |\n|----|--------|------|\n| AC-1 | done | FooTest#a_returns_two |\n' > "$r/docs/build/old/plan.md"
printf 'commit: abcdef1234567\n\n| Command | Exit | Attempt | Failing test | Location |\n|---|---|---|---|---|\n| mvn verify | 1 | 1 | FooTest#a_returns_two | Foo.java:3 |\n| mvn verify | 0 | 2 | | |\n' > "$r/docs/build/old/build-report.md"
commit real
link pass "a feature change that carries its own build evidence still passes" "Feature-Artifact: docs/requirements/old.md"
(cd "$r" && printf 'commit: abcdef1234567\n' > docs/build/old/build-report.md && git add -A && git_c commit -q -m nored)
link fail "a feature change whose plan test has no red card fails" "Feature-Artifact: docs/requirements/old.md"
link pass "REQUIRE_BUILD_PLAN=0 turns the plan check off" "Feature-Artifact: docs/requirements/old.md" REQUIRE_BUILD_PLAN=0
printf 'commit: abcdef1234567\n\n| Command | Exit | Attempt | Failing test | Location |\n|---|---|---|---|---|\n| mvn verify | 1 | 1 | FooTest#a_returns_two | Foo.java:3 |\n' > "$r/docs/build/old/build-report.md"
mkdir -p "$r/docs/design/old"; printf '# Design\n' > "$r/docs/design/old/design.md"
commit design
link fail "a feature with a design and no design.lock fails" "Feature-Artifact: docs/requirements/old.md"
(cd "$r" && printf '2026-01-01 %s approved\n' "$(sh ci/check-design.sh old --hash)" > docs/design/old/design.lock && git add -A && git_c commit -q -m lock)
link pass "a feature whose design matches its lock passes" "Feature-Artifact: docs/requirements/old.md"
printf 'changed\n' >> "$r/docs/design/old/design.md"; commit drift
link fail "a design that drifted from its lock fails" "Feature-Artifact: docs/requirements/old.md"

# --- state and metrics for notes ---------------------------------------------
branch s-state; make_note fix-10 standard "" no "$rollback"; commit state
if (cd "$r" && sh scripts/sync-feature-state.sh docs/maintain/fix-10/note.md --active-phase maintain --status in_progress >/dev/null 2>&1) \
   && grep -Fq '"feature": "fix-10"' "$r/docs/maintain/fix-10/state.json" \
   && grep -Fq '"activePhase": "maintain"' "$r/docs/maintain/fix-10/state.json" \
   && grep -Fq '"tier": "standard"' "$r/docs/maintain/fix-10/state.json"; then
  pass "state: a note keeps docs/maintain/<id>/state.json with its tier"
else
  fail "state: a note keeps docs/maintain/<id>/state.json with its tier"
fi
if (cd "$r" && sh scripts/sync-feature-state.sh docs/maintain/fix-10/note.md --active-phase release --status in_progress >/dev/null 2>&1); then
  fail "state: release is not a phase of a maintenance note"
else
  pass "state: release is not a phase of a maintenance note"
fi
if (cd "$r" && sh scripts/sync-feature-state.sh docs/maintain/fix-10/note.md >/dev/null 2>&1) && grep -Fq '"lastApprovedPhase": "maintain"' "$r/docs/maintain/fix-10/state.json"; then
  pass "state: the maintain approval is derived"
else
  fail "state: the maintain approval is derived"
fi

branch s-metrics; make_note fix-11 emergency "$confirmed\nFollow-up verify due: 2020-01-01" no "$rollback"; commit metrics
if (cd "$r" && sh scripts/delivery-metrics.sh . 2>/dev/null) | grep -F 'fix-11' | grep -Fq 'OVERDUE'; then
  pass "metrics: an emergency note past its follow-up date is OVERDUE"
else
  fail "metrics: an emergency note past its follow-up date is OVERDUE"
fi

if [ "$status" -ne 0 ]; then
  echo "test-maintain: FAILED" >&2
  exit 1
fi
echo "test-maintain: OK"
