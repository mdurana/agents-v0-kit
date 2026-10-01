#!/bin/sh
# test-onboard.sh — behavior tests for the /onboard scripts on a fixture repo (no network).
# Covers: discover-codebase.sh, generate-repo-map.sh, collect-dependency-graphs.sh,
# check-onboarding-docs.sh, sync-feature-state.sh (onboarding), check-approvals.sh (onboard),
# check-gate-metrics.sh (GATE_REPORT_ONLY). Run by validate-kit.sh. Needs python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }

# has <description> <file> <fixed-string>   lacks <description> <file> <fixed-string>
has() { if grep -Fq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1 (missing '$3' in $2)"; fi; }
lacks() { if grep -Fq -- "$3" "$2" 2>/dev/null; then fail "$1 ('$3' found in $2)"; else pass "$1"; fi; }
expect_pass() { desc="$1"; dir="$2"; shift 2; if (cd "$dir" && "$@") >/dev/null 2>&1; then pass "$desc"; else fail "$desc (expected exit 0)"; fi; }
expect_fail() { desc="$1"; dir="$2"; shift 2; if (cd "$dir" && "$@") >/dev/null 2>&1; then fail "$desc (expected non-zero)"; else pass "$desc"; fi; }

# --- fixture ------------------------------------------------------------------
r="$tmp/repo"
mkdir -p "$r/ci" "$r/scripts" "$r/docs"
cp "$KIT"/templates/ci/resolve-layout.sh "$KIT"/templates/ci/check-gate-metrics.sh "$KIT"/templates/ci/check-approvals.sh "$r/ci/"
cp "$KIT"/templates/scripts/discover-codebase.sh "$KIT"/templates/scripts/generate-repo-map.sh \
   "$KIT"/templates/scripts/collect-dependency-graphs.sh "$KIT"/templates/scripts/check-onboarding-docs.sh \
   "$KIT"/templates/scripts/sync-feature-state.sh "$r/scripts/"
cat > "$r/docs/project-profile.md" <<'EOF'
| This repo | Value |
|-----------|--------|
| Profile | app |
| Backend root | n/a |
| Frontend root | frontend |
| BFF root | n/a |
| Service roots | services/order, services/inventory |
EOF

o="$r/services/order"
mkdir -p "$o/src/main/java/com/acme/order" "$o/src/main/resources/db/migration" "$o/src/test/java/com/acme/order"
: > "$o/pom.xml"
cat > "$o/src/main/java/com/acme/order/OrderController.java" <<'EOF'
package com.acme.order;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

  @PreAuthorize("hasRole('ADMIN')")
  @PostMapping
  public void create() {}

  @GetMapping("/{id}")
  public String get() { return ""; }

  @DeleteMapping("/{id}")
  public void remove() {}

  @PreAuthorize("hasRole('ADMIN')")
  @PutMapping("/{id}")
  public void update() {}
}
EOF
cat > "$o/src/main/java/com/acme/order/Order.java" <<'EOF'
package com.acme.order;

@Entity
@Table(name = "orders")
public class Order {}
EOF
cat > "$o/src/main/java/com/acme/order/Listener.java" <<'EOF'
package com.acme.order;

public class Listener {
  private final WebClient client = null;

  @KafkaListener(topics = "orders")
  void onOrder() {}

  @Scheduled(fixedRate = 1000)
  void tick() {}
}
EOF
cat > "$o/src/main/resources/application.yml" <<'EOF'
spring:
  datasource:
    url: ${DB_URL}
    password: hunter2-literal
security:
  permit-all: true
EOF
printf 'create table orders(id int);\n' > "$o/src/main/resources/db/migration/V1__init.sql"
printf 'class OrderControllerTest {}\n' > "$o/src/test/java/com/acme/order/OrderControllerTest.java"
mkdir -p "$r/services/inventory"
: > "$r/services/inventory/pom.xml"
mkdir -p "$r/frontend/src/routes/orders"
printf '{}\n' > "$r/frontend/package.json"
: > "$r/frontend/src/routes/orders/+page.svelte"
printf '<Route path="/orders" element={x} />\nfetch("/api/v1/orders");\n' > "$r/frontend/src/App.tsx"
printf 'FROM eclipse-temurin:21\n' > "$r/Dockerfile"
mkdir -p "$o/api"
cat > "$o/api/routes.py" <<'EOF'
from fastapi import APIRouter, Depends
router = APIRouter()

@router.get("/health")
def health():
    return {}
EOF

# --- discover-codebase.sh ----------------------------------------------------
expect_pass "discover-codebase runs on the fixture" "$r" sh scripts/discover-codebase.sh
d="$r/docs/discovery"
has "endpoints: annotated POST with the class base path" "$d/endpoints.txt" "POST /api/v1/orders  annotated"
has "endpoints: GET without an annotation is flagged" "$d/endpoints.txt" "GET /api/v1/orders/{id}  NO-ANNOTATION"
has "endpoints: a method before an annotated method is not credited with its annotation" "$d/endpoints.txt" "DELETE /api/v1/orders/{id}  NO-ANNOTATION"
has "endpoints: an annotation above the mapping is attributed to it" "$d/endpoints.txt" "PUT /api/v1/orders/{id}  annotated"
has "entities: class and table" "$d/entities.txt" "Entity Order  table orders"
has "migrations: Flyway file listed" "$d/migrations.txt" "V1__init.sql"
has "messaging: Kafka listener" "$d/messaging.txt" "@KafkaListener"
has "scheduled: @Scheduled" "$d/scheduled.txt" "@Scheduled"
has "outbound: WebClient" "$d/outbound.txt" "WebClient"
has "config: key path" "$d/config.txt" "spring.datasource.password"
has "config: literal secret is classified" "$d/config.txt" "LITERAL-IN-FILE"
has "config: environment reference name" "$d/config.txt" "DB_URL"
lacks "config: no secret value is printed" "$d/config.txt" "hunter2"
lacks "security baseline: no secret value is printed" "$d/security-baseline.md" "hunter2"
has "security baseline: permit-all finding" "$d/security-baseline.md" "permit-all"
has "endpoint stacks: FastAPI row proposed" "$d/endpoint-stacks.md" "| fastapi | .py |"
has "frontend: SvelteKit route" "$d/frontend.txt" "SvelteKit route /orders"
has "frontend: React route" "$d/frontend.txt" "React route /orders"
has "frontend: API call" "$d/frontend.txt" "API call /api/v1/orders"
has "ci-deploy: Dockerfile" "$d/ci-deploy.txt" "Dockerfile"
has "tests: per-root counts" "$d/tests.txt" "services/order  java test files 1"
has "baseline: unmeasured root is said so" "$d/baseline.md" "not measured"
has "every inventory carries the commit" "$d/endpoints.txt" "commit:"

(cd "$r" && DISCOVER_MAX=1 sh scripts/discover-codebase.sh >/dev/null 2>&1)
has "a capped list says it was cut" "$d/endpoints.txt" "TRUNCATED: showing 1 of 4"

# baseline numbers from target/ reports
mkdir -p "$o/target/surefire-reports" "$o/target/site/jacoco"
printf '<testsuite tests="4" failures="1" errors="0" skipped="0"/>\n' > "$o/target/surefire-reports/TEST-a.xml"
cat > "$o/target/site/jacoco/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="x"><counter type="LINE" missed="1" covered="1"/></report>
EOF
(cd "$r" && sh scripts/discover-codebase.sh >/dev/null 2>&1)
has "baseline: coverage read from jacoco.xml" "$d/baseline.md" "50.0%"
has "baseline: proposed coverage ratchet row" "$d/baseline.md" "| services/order | 50% |"
has "baseline: proposed known_failures row" "$d/baseline.md" "| 1 | services/order |"
expect_pass "gate metrics: GATE_REPORT_ONLY exits 0 on a failing module" "$r" env GATE_REPORT_ONLY=1 sh ci/check-gate-metrics.sh services/order
expect_fail "gate metrics: the same module fails without GATE_REPORT_ONLY" "$r" sh ci/check-gate-metrics.sh services/order

# --- generate-repo-map.sh ----------------------------------------------------
expect_pass "generate-repo-map runs on the fixture" "$r" sh scripts/generate-repo-map.sh
has "repo map: resolved service roots" "$r/docs/repo-map.md" '`services/inventory`'
has "repo map: Maven build file under a service root" "$r/docs/repo-map.md" 'services/order/pom.xml'
has "repo map: controller found" "$r/docs/repo-map.md" "OrderController.java"
has "repo map: commit stamped" "$r/docs/repo-map.md" "commit:"

# --- collect-dependency-graphs.sh --------------------------------------------
g="$tmp/graphs"
mkdir -p "$g/ci" "$g/scripts" "$g/docs" "$g/services/order" "$g/services/inventory"
cp "$KIT"/templates/ci/resolve-layout.sh "$g/ci/"
cp "$KIT"/templates/scripts/collect-dependency-graphs.sh "$g/scripts/"
: > "$g/services/order/pom.xml"
: > "$g/services/inventory/pom.xml"
cat > "$g/services/order/mvnw" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in -DoutputFile=*) out="${a#-DoutputFile=}" ;; esac; done
printf 'com.acme:order:jar:1\n' >> "$out"
EOF
printf '#!/bin/sh\nexit 1\n' > "$g/services/inventory/mvnw"
chmod +x "$g/services/order/mvnw" "$g/services/inventory/mvnw"
expect_fail "dependency graphs: a failing root makes the script exit non-zero" "$g" sh scripts/collect-dependency-graphs.sh
has "dependency graphs: a working root writes its own graph" "$g/docs/discovery/dependency-graph.services-order.txt" "com.acme:order"
if (cd "$g" && sh scripts/collect-dependency-graphs.sh 2>&1) | grep -Fq "dependency:tree failed under services/inventory"; then
  pass "dependency graphs: the failing root is named"
else
  fail "dependency graphs: the failing root is named"
fi

# --- check-onboarding-docs.sh ------------------------------------------------
mkdir -p "$r/docs/onboarding/modules"
cite='`services/order/src/main/java/com/acme/order/OrderController.java:7`'
cat > "$r/docs/onboarding/report.md" <<EOF
# Onboarding report

commit: abcdef1234567

The controller is at $cite. The database is reached at db.internal:5432 and \`example.com:8080\`.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| onboard | docs/onboarding/report.md | dev | Approved | 2026-01-01 |
EOF
expect_pass "onboarding docs: a real citation passes and hostnames are not citations" "$r" sh scripts/check-onboarding-docs.sh
printf 'Also see `services/order/src/Missing.java:3`.\n' >> "$r/docs/onboarding/report.md"
expect_fail "onboarding docs: a citation to a missing file fails" "$r" sh scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/onboarding/report.md" && rm -f "$r/docs/onboarding/report.md.bak"
printf 'Out of range: `services/order/src/main/java/com/acme/order/OrderController.java:999`.\n' >> "$r/docs/onboarding/report.md"
expect_fail "onboarding docs: a line past the end of the file fails" "$r" sh scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/onboarding/report.md" && rm -f "$r/docs/onboarding/report.md.bak"
printf '<!-- TEMPLATE: replace -->\n' >> "$r/docs/onboarding/report.md"
expect_fail "onboarding docs: a TEMPLATE: marker fails" "$r" sh scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/onboarding/report.md" && rm -f "$r/docs/onboarding/report.md.bak"
printf 'Retention is UNVERIFIED.\n' >> "$r/docs/onboarding/report.md"
expect_pass "onboarding docs: UNVERIFIED is counted, not failed, by default" "$r" sh scripts/check-onboarding-docs.sh
expect_fail "onboarding docs: MAX_UNVERIFIED=0 fails on an unknown" "$r" env MAX_UNVERIFIED=0 sh scripts/check-onboarding-docs.sh
printf '# Module: order\n\nNo commit line here.\n' > "$r/docs/onboarding/modules/order.md"
expect_fail "onboarding docs: a module document needs a commit line" "$r" sh scripts/check-onboarding-docs.sh
rm -f "$r/docs/onboarding/modules/order.md"
mv "$r/docs/onboarding/report.md" "$r/docs/onboarding/report.keep"
expect_fail "onboarding docs: the default run needs the report" "$r" sh scripts/check-onboarding-docs.sh
mv "$r/docs/onboarding/report.keep" "$r/docs/onboarding/report.md"

# --- onboarding state and approval -------------------------------------------
expect_pass "check-approvals accepts an Approved onboard row" "$r" sh ci/check-approvals.sh docs/onboarding/report.md onboard
expect_pass "state: onboarding in progress" "$r" sh scripts/sync-feature-state.sh docs/onboarding/report.md --active-phase onboard --status in_progress
has "state: written beside the report" "$r/docs/onboarding/state.json" '"activePhase": "onboard"'
has "state: feature is onboarding" "$r/docs/onboarding/state.json" '"feature": "onboarding"'
expect_pass "state: approval clears the active phase" "$r" sh scripts/sync-feature-state.sh docs/onboarding/report.md
has "state: last approved phase is onboard" "$r/docs/onboarding/state.json" '"lastApprovedPhase": "onboard"'
expect_fail "state: an intake phase is not valid for onboarding" "$r" sh scripts/sync-feature-state.sh docs/onboarding/report.md --active-phase intake --status in_progress

if [ "$status" -ne 0 ]; then
  echo "test-onboard: FAILED" >&2
  exit 1
fi
echo "test-onboard: OK"
