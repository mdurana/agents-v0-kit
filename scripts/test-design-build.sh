#!/bin/sh
# test-design-build.sh — behavior tests for the Design and Build checks (no network).
# Covers: ci/check-openapi.sh, ci/check-design.sh (checks, pin, lock, amendments),
# ci/check-ux-spec.sh, ci/check-build-plan.sh, ci/check-endpoint-auth.sh, ci/check-frontend-calls.sh.
# Run by validate-kit.sh. Needs git and python3; the OpenAPI and frontend-call cases need PyYAML
# and are skipped (with a notice) when it is missing.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
CI="$KIT/templates/ci"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
status=0
HAVE_YAML=0
python3 -c 'import yaml' >/dev/null 2>&1 && HAVE_YAML=1

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
skip() { printf 'skip: %s (PyYAML not installed)\n' "$1"; }
# run <expect pass|fail> <description> <dir> <command...>
run() {
  want="$1"; desc="$2"; dir="$3"; shift 3
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (wanted $want, got $got: $(tail -n 2 "$tmp/out.txt" | tr '\n' ' '))"; fi
  if [ -n "${TEST_VERBOSE:-}" ] && [ "$want" = fail ]; then grep '^FAIL' "$tmp/out.txt" | sed 's/^/    | /'; fi
}
yaml_run() {
  if [ "$HAVE_YAML" = 1 ]; then run "$@"; else skip "$2"; fi
}
sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }
git_c() { git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }

# --- ci/check-openapi.sh -----------------------------------------------------
o="$tmp/openapi"
mkdir -p "$o"
cat > "$o/draft.yaml" <<'EOF'
openapi: 3.0.3
info: {title: Orders, version: "1"}
security:
  - bearerAuth: []
paths:
  /api/v1/orders:
    post:
      operationId: createOrder
      parameters:
        - {name: Idempotency-Key, in: header, required: true, schema: {type: string}}
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: '#/components/schemas/CreateOrder'}
      responses:
        "201": {description: created, content: {application/json: {schema: {$ref: '#/components/schemas/Order'}}}}
        "400": {description: bad, content: {application/problem+json: {schema: {type: object}}}}
  /api/v1/orders/{id}:
    get:
      operationId: getOrder
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Order'}}}}
        "404": {description: not found, content: {application/problem+json: {schema: {type: object}}}}
components:
  securitySchemes:
    bearerAuth: {type: http, scheme: bearer}
  schemas:
    CreateOrder: {type: object, required: [sku], properties: {sku: {type: string}}}
    Order: {type: object, properties: {id: {type: string}, sku: {type: string}}}
EOF
variant() { cp "$o/draft.yaml" "$o/$1.yaml"; }
yaml_run pass "openapi lint: a valid draft passes" "$o" sh "$CI/check-openapi.sh" lint draft.yaml
variant noidem; sedi '/Idempotency-Key/d' "$o/noidem.yaml"
yaml_run fail "openapi lint: a POST without Idempotency-Key fails" "$o" sh "$CI/check-openapi.sh" lint noidem.yaml
variant badpath; sedi 's|/api/v1/orders:|/orders:|' "$o/badpath.yaml"
yaml_run fail "openapi lint: a path outside /api/v1 fails" "$o" sh "$CI/check-openapi.sh" lint badpath.yaml
variant mixed; sedi 's|description: not found, content: {application/problem+json|description: not found, content: {application/json|' "$o/mixed.yaml"
yaml_run fail "openapi lint: mixed error envelopes fail" "$o" sh "$CI/check-openapi.sh" lint mixed.yaml
variant badref; sedi "s|#/components/schemas/Order'|#/components/schemas/Nope'|" "$o/badref.yaml"
yaml_run fail "openapi lint: an unresolved \$ref fails" "$o" sh "$CI/check-openapi.sh" lint badref.yaml
variant nosec; sedi '/^security:/,/bearerAuth: \[\]/d' "$o/nosec.yaml"
yaml_run fail "openapi lint: an operation with no security fails" "$o" sh "$CI/check-openapi.sh" lint nosec.yaml
variant dupid; sedi 's/operationId: getOrder/operationId: createOrder/' "$o/dupid.yaml"
yaml_run fail "openapi lint: a duplicate operationId fails" "$o" sh "$CI/check-openapi.sh" lint dupid.yaml
variant v31; sedi 's/openapi: 3.0.3/openapi: 3.1.0/' "$o/v31.yaml"
yaml_run fail "openapi lint: OpenAPI 3.1 fails (the kit is on 3.0)" "$o" sh "$CI/check-openapi.sh" lint v31.yaml

cat > "$o/catalog-ok.yaml" <<'EOF'
openapi: 3.0.3
info: {title: Orders, version: "1"}
paths:
  /api/v1/orders/{id}:
    get:
      operationId: getOrder
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Order'}}}}
components:
  schemas:
    Order: {type: object, properties: {id: {type: string}, sku: {type: string}}}
EOF
yaml_run pass "openapi compat: a compatible draft passes" "$o" sh "$CI/check-openapi.sh" compat draft.yaml catalog-ok.yaml
cp "$o/catalog-ok.yaml" "$o/catalog-break.yaml"
sedi 's/sku: {type: string}}}/sku: {type: string}, legacy: {type: string}}}/' "$o/catalog-break.yaml"
yaml_run fail "openapi compat: a lost response property and a changed component fail" "$o" sh "$CI/check-openapi.sh" compat draft.yaml catalog-break.yaml
yaml_run pass "openapi merge: writes a new catalog from the draft" "$o" sh "$CI/check-openapi.sh" merge draft.yaml newcat/api-v1.yaml
yaml_run pass "openapi merged: the merged catalog contains the draft" "$o" sh "$CI/check-openapi.sh" merged draft.yaml newcat/api-v1.yaml
yaml_run fail "openapi merged: a catalog without the draft fails" "$o" sh "$CI/check-openapi.sh" merged draft.yaml catalog-ok.yaml

# --- ci/check-design.sh ------------------------------------------------------
d="$tmp/design"
mkdir -p "$d/docs/requirements" "$d/docs/design/orders" "$d/docs/adr"
printf '# Orders\nAC-1 place an order\nAC-2 read an order\n' > "$d/docs/requirements/orders.md"
cp "$o/draft.yaml" "$d/docs/design/orders/openapi.yaml"
cat > "$d/docs/adr/01-orders.md" <<'EOF'
# ADR 01: Orders

## Decision
Synchronous REST.

## Alternatives considered
- Kafka request/reply: more moving parts for a read-heavy flow.
- GraphQL: no consumer asked for it.
EOF
cat > "$d/docs/design/orders/design.md" <<'EOF'
# Design: orders

ADR: docs/adr/01-orders.md

## Traceability
| Requirement | Satisfied by |
|---|---|
| AC-1 | operation createOrder |
| AC-2 | operation getOrder |

## Data model
Table orders(id uuid primary key, sku text not null), index on sku, about 2M rows a year, no PII.

## Authorization
| operationId | Roles | Resource rule |
|---|---|---|
| createOrder | ROLE_CUSTOMER | caller becomes the owner |
| getOrder | ROLE_CUSTOMER | order.ownerId equals the caller |

## Failure modes
Inventory timeout after 2s: reject with 503 and a retry hint; nothing is written.

## Observability
RED metrics per operation, a log field orderId, an alert on 5xx above 1 percent.

## Rollout
Behind flag orders.enabled, default off; expand migration first; rollback by disabling the flag.
EOF
run pass "design: a complete design passes" "$d" sh "$CI/check-design.sh" orders
cp "$d/docs/design/orders/design.md" "$tmp/design.md.keep"
sedi '/| AC-2 /d' "$d/docs/design/orders/design.md"
run fail "design: an AC missing from Traceability fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/design/orders/design.md"
sedi '/| getOrder /d' "$d/docs/design/orders/design.md"
run fail "design: an operation missing from Authorization fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/design/orders/design.md"
printf '<!-- TEMPLATE: x -->\n' >> "$d/docs/design/orders/design.md"
run fail "design: a TEMPLATE: line fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/design/orders/design.md"
sedi '/^## Rollout/,$d' "$d/docs/design/orders/design.md"
run fail "design: a missing section fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/design/orders/design.md"
cp "$d/docs/adr/01-orders.md" "$tmp/adr.keep"
sedi '/GraphQL/d' "$d/docs/adr/01-orders.md"
run fail "design: an ADR with one alternative fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/adr.keep" "$d/docs/adr/01-orders.md"

run fail "design: pinning needs a design review" "$d" sh "$CI/check-design.sh" orders --pin approved
h1="$(cd "$d" && sh "$CI/check-design.sh" orders --hash)"
printf 'agent: design-reviewer\ndesign-hash: %s\n\n| # | Label | Finding | Evidence | Status |\n|---|---|---|---|---|\n| 1 | Critical | no ownership rule | design.md:20 | Open |\n' "$(printf '%s' "$h1" | cut -c1-12)" > "$d/docs/design/orders/review.md"
run fail "design: an open Critical blocks the pin" "$d" sh "$CI/check-design.sh" orders --pin approved
sedi 's/| Open |/| Resolved |/' "$d/docs/design/orders/review.md"
run pass "design: a resolved review lets the pin through" "$d" sh "$CI/check-design.sh" orders --pin approved
run pass "design: the lock matches the pinned design" "$d" sh "$CI/check-design.sh" orders --verify-lock
printf 'Also the order list is paged.\n' >> "$d/docs/design/orders/design.md"
sedi 's/^## Rollout/## Rollout\nPaged list./' "$d/docs/design/orders/design.md"
run fail "design: a change after the pin fails the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock
h2="$(cd "$d" && sh "$CI/check-design.sh" orders --hash)"
printf 'agent: design-reviewer\ndesign-hash: %s\n' "$(printf '%s' "$h2" | cut -c1-12)" > "$d/docs/design/orders/review.md"
printf '| # | Date | Change | Reason | Impacted | Approver | Decision | Hash |\n|---|---|---|---|---|---|---|---|\n| 1 | 2026-01-02 | paged list | consumer asked | AC-2 | dev | Approved | %s |\n' "$(printf '%s' "$h2" | cut -c1-12)" > "$d/docs/design/orders/amendments.md"
run pass "design: an approved amendment can be pinned" "$d" sh "$CI/check-design.sh" orders --pin "amendment 1"
run pass "design: the lock passes once the amendment is approved" "$d" sh "$CI/check-design.sh" orders --verify-lock
sedi 's/Approved/Pending/' "$d/docs/design/orders/amendments.md"
run fail "design: a pin with no Approved amendment row fails the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock

# --- ci/check-ux-spec.sh -----------------------------------------------------
u="$tmp/ux"
mkdir -p "$u/docs/design/orders/mockups"
cp "$o/draft.yaml" "$u/docs/design/orders/openapi.yaml"
cat > "$u/docs/design/orders/ux-spec.md" <<'EOF'
# UX spec

Screens: mockups/new-order.html

| Component | Screen | Mockup | Operation | Default behavior | Override |
|-----------|--------|--------|-----------|------------------|----------|
| Place order button | New order | mockups/new-order.html | createOrder | submits the form | |
| Cancel link | New order | mockups/new-order.html | — | returns to the list | |
EOF
cat > "$u/docs/design/orders/mockups/new-order.html" <<'EOF'
<html><body>
<form><input type="text" name="sku" data-component="Sku field">
<button data-component="Place order button">Place</button>
<a href="#" data-component="Cancel link">Cancel</a></form>
</body></html>
EOF
run fail "ux spec: an input with no row fails" "$u" sh "$CI/check-ux-spec.sh" orders
printf '| Sku field | New order | mockups/new-order.html | — | accepts text | |\n' >> "$u/docs/design/orders/ux-spec.md"
run pass "ux spec: rows and mockup agree" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$u/docs/design/orders/mockups/new-order.html" "$tmp/mock.keep"
sedi 's|<button data-component="Place order button">|<button>|' "$u/docs/design/orders/mockups/new-order.html"
run fail "ux spec: a control with no data-component fails" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$tmp/mock.keep" "$u/docs/design/orders/mockups/new-order.html"
cp "$u/docs/design/orders/ux-spec.md" "$tmp/spec.keep"
sedi 's/| createOrder |/| deleteOrder |/' "$u/docs/design/orders/ux-spec.md"
run fail "ux spec: an operation not in the draft fails" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$tmp/spec.keep" "$u/docs/design/orders/ux-spec.md"
printf '<script>fetch("/api/v1/orders")</script>\n' >> "$u/docs/design/orders/mockups/new-order.html"
run fail "ux spec: a mockup that calls the API fails" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$tmp/mock.keep" "$u/docs/design/orders/mockups/new-order.html"
printf '<html><body><p>spare</p></body></html>\n' > "$u/docs/design/orders/mockups/orphan.html"
run fail "ux spec: a mockup no row references fails" "$u" sh "$CI/check-ux-spec.sh" orders
rm -f "$u/docs/design/orders/mockups/orphan.html"
mkdir -p "$tmp/noui"
run pass "ux spec: a story with no UX spec passes" "$tmp/noui" sh "$CI/check-ux-spec.sh" orders

# --- ci/check-build-plan.sh --------------------------------------------------
b="$tmp/build"
mkdir -p "$b/docs/requirements" "$b/docs/build/orders" "$b/src/test/java"
printf '# Orders\nAC-1 place an order\nAC-2 read an order\n' > "$b/docs/requirements/orders.md"
printf 'class OrderServiceTest {\n  void create_valid_returnsId() {}\n  void get_unknown_returns404() {}\n}\n' > "$b/src/test/java/OrderServiceTest.java"
cat > "$b/docs/build/orders/plan.md" <<'EOF'
# Build plan

| AC | Status | Test |
|----|--------|------|
| AC-1 | done | OrderServiceTest#create_valid_returnsId |
| AC-2 | pending | |
EOF
cat > "$b/docs/build/orders/build-report.md" <<'EOF'
# Build report

commit: abcdef1234567

| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| mvn verify | 1 | 1 | OrderServiceTest#create_valid_returnsId | OrderService.java:10 |
| mvn verify | 0 | 2 | | |
EOF
run pass "build plan: a done row with an existing, red-first test passes" "$b" sh "$CI/check-build-plan.sh" orders
run fail "build plan: --complete fails while a row is pending" "$b" sh "$CI/check-build-plan.sh" orders --complete
cp "$b/docs/build/orders/plan.md" "$tmp/plan.keep"
sedi 's/| AC-2 | pending | |/| AC-2 | done | OrderServiceTest#get_unknown_returns404 |/' "$b/docs/build/orders/plan.md"
run fail "build plan: a done row with no red card fails" "$b" sh "$CI/check-build-plan.sh" orders
sedi 's/get_unknown_returns404 |/get_unknown_returns404 (no-red: configuration only) |/' "$b/docs/build/orders/plan.md"
run pass "build plan: (no-red: reason) waives the red card for one row" "$b" sh "$CI/check-build-plan.sh" orders --complete
sedi 's/get_unknown_returns404 (no-red: configuration only)/missing_method_name/' "$b/docs/build/orders/plan.md"
run fail "build plan: a test that no test file contains fails" "$b" sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/build/orders/plan.md"
sedi '/| AC-2 /d' "$b/docs/build/orders/plan.md"
run fail "build plan: a requirement with no plan row fails" "$b" sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/build/orders/plan.md"
printf '| AC-9 | pending | |\n' >> "$b/docs/build/orders/plan.md"
run fail "build plan: a row that is not a requirement fails" "$b" sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/build/orders/plan.md"
sedi 's/| AC-2 | pending | |/| AC-2 | done | OrderServiceTest#get_unknown_returns404 |/' "$b/docs/build/orders/plan.md"
run pass "build plan: REQUIRE_RED=0 turns the red-first check off" "$b" env REQUIRE_RED=0 sh "$CI/check-build-plan.sh" orders

# --- ci/check-endpoint-auth.sh -----------------------------------------------
e="$tmp/endpoints"
mkdir -p "$e/src/main/java/com/acme"
cat > "$e/src/main/java/com/acme/OrderController.java" <<'EOF'
package com.acme;

@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

  @PreAuthorize("hasRole('CUSTOMER')")
  @PostMapping
  public void create() {}

  @GetMapping("/legacy")
  public String legacy() { return ""; }
}
EOF
(cd "$e" && git init -q && git add -A && git_c commit -q -m base)
ebase="$(cd "$e" && git rev-parse HEAD)"
run pass "endpoint auth: an existing unannotated endpoint is not a new one" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
cat > "$e/src/main/java/com/acme/OrderController.java" <<'EOF'
package com.acme;

@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

  @PreAuthorize("hasRole('CUSTOMER')")
  @PostMapping
  public void create() {}

  @GetMapping("/legacy")
  public String legacy() { return ""; }

  @GetMapping("/{id}")
  public String get() { return ""; }
}
EOF
run fail "endpoint auth: a new unannotated endpoint fails" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
sedi 's|  @GetMapping("/{id}")|  @PermitAll\n  @GetMapping("/{id}")|' "$e/src/main/java/com/acme/OrderController.java"
run pass "endpoint auth: @PermitAll marks a public endpoint on purpose" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
if (cd "$e" && sh "$CI/check-endpoint-auth.sh" --list .) | grep -Fq "GET /api/v1/orders/legacy  NO-ANNOTATION"; then pass "endpoint auth: --list prints the same rows as discovery"; else fail "endpoint auth: --list prints the same rows as discovery"; fi

# --- ci/check-frontend-calls.sh ----------------------------------------------
f="$tmp/frontend"
mkdir -p "$f/ci" "$f/openapi" "$f/frontend/src/lib" "$f/frontend/src/lib/__tests__"
cp "$CI/resolve-layout.sh" "$f/ci/"
printf '{}\n' > "$f/frontend/package.json"
cp "$o/draft.yaml" "$f/openapi/api-v1.yaml"
cat > "$f/frontend/src/lib/api.ts" <<'EOF'
export const create = () => fetch('/api/v1/orders', { method: 'POST' });
export const get = (id: string) => fetch(`/api/v1/orders/${id}`);
export const getConcat = (id: string) => fetch('/api/v1/orders/' + id);
EOF
yaml_run pass "frontend calls: calls that match the catalog pass" "$f" sh "$CI/check-frontend-calls.sh"
printf "export const refund = () => fetch('/api/v1/refunds');\n" >> "$f/frontend/src/lib/api.ts"
yaml_run fail "frontend calls: a call the catalog does not list fails" "$f" sh "$CI/check-frontend-calls.sh"
yaml_run pass "frontend calls: FRONTEND_CALLS_IGNORE skips a path" "$f" env FRONTEND_CALLS_IGNORE='refunds' sh "$CI/check-frontend-calls.sh"
sedi '/refunds/d' "$f/frontend/src/lib/api.ts"
printf "fetch('/api/v1/secret');\n" > "$f/frontend/src/lib/__tests__/api.test.ts"
yaml_run pass "frontend calls: test files are not checked" "$f" sh "$CI/check-frontend-calls.sh"

if [ "$status" -ne 0 ]; then
  echo "test-design-build: FAILED" >&2
  exit 1
fi
echo "test-design-build: OK"
