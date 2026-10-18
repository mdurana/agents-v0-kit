#!/bin/sh
# test-design-build.sh — behavior tests for the Design and Build checks (no network).
# Covers: ci/check-openapi.sh, ci/check-design.sh (checks, pin, lock, amendments),
# ci/check-ux-spec.sh, ci/check-build-plan.sh, ci/check-endpoint-auth.sh, ci/check-frontend-calls.sh.
# Run by validate-kit.sh. Needs git, python3, and PyYAML (python3 -m pip install pyyaml).
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
CI="$KIT/templates/.agents-v0/ci"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0
HAVE_YAML=0
python3 -c 'import yaml' >/dev/null 2>&1 && HAVE_YAML=1

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
# run <expect pass|fail> <description> <dir> <command...>
run() {
  want="$1"; desc="$2"; dir="$3"; shift 3
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (wanted $want, got $got: $(tail -n 2 "$tmp/out.txt" | tr '\n' ' '))"; fi
  if [ -n "${TEST_VERBOSE:-}" ] && [ "$want" = fail ]; then grep '^FAIL' "$tmp/out.txt" | sed 's/^/    | /'; fi
}
yaml_run() {
  if [ "$HAVE_YAML" = 1 ]; then
    run "$@"
  else
    fail "$2 (PyYAML is required: python3 -m pip install pyyaml, apk add py3-yaml, or on Intel macOS sh templates/.agents-v0/scripts/host-tools-macports.sh)"
  fi
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

cat > "$o/async-ok.yaml" <<'EOF'
asyncapi: 2.6.0
info: {title: Orders events, version: "1.0.0"}
channels:
  orders.created:
    publish:
      message:
        x-event-type: ORDER_CREATED
        payload:
          type: object
          properties:
            eventType: {type: string}
            eventVersion: {type: string}
EOF
yaml_run pass "asyncapi lint: a valid draft passes" "$o" sh "$CI/check-asyncapi.sh" lint async-ok.yaml
cp "$o/async-ok.yaml" "$o/async-no-event.yaml"
sedi '/x-event-type/d' "$o/async-no-event.yaml"
sedi '/eventType/d' "$o/async-no-event.yaml"
yaml_run fail "asyncapi lint: a message without event type fails" "$o" sh "$CI/check-asyncapi.sh" lint async-no-event.yaml

cat > "$o/async3-ok.yaml" <<'EOF'
asyncapi: 3.0.0
info: {title: Orders events, version: "1.0.0"}
channels:
  orders.created:
    address: orders.created
    messages:
      orderCreated:
        x-event-type: ORDER_CREATED
        payload:
          type: object
          properties:
            eventType: {type: string}
operations:
  publishOrderCreated:
    action: send
    channel:
      $ref: '#/channels/orders.created'
    messages:
      - $ref: '#/channels/orders.created/messages/orderCreated'
EOF
yaml_run pass "asyncapi lint: a valid 3.x draft passes" "$o" sh "$CI/check-asyncapi.sh" lint async3-ok.yaml
cp "$o/async3-ok.yaml" "$o/async3-no-op.yaml"
sedi '/^operations:/,$d' "$o/async3-no-op.yaml"
yaml_run fail "asyncapi lint: 3.x without an operation fails" "$o" sh "$CI/check-asyncapi.sh" lint async3-no-op.yaml

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
mkdir -p "$d/docs/agents-v0/requirements" "$d/docs/agents-v0/design/orders" "$d/docs/agents-v0/adr"
printf '# Orders\nAC-1 place an order\nAC-2 read an order\n' > "$d/docs/agents-v0/requirements/orders.md"
cp "$o/draft.yaml" "$d/docs/agents-v0/design/orders/openapi.yaml"
cat > "$d/docs/agents-v0/adr/01-orders.md" <<'EOF'
# ADR 01: Orders

- **Status:** Accepted

## Decision
Synchronous REST.

## Alternatives considered
- Kafka request/reply: more moving parts for a read-heavy flow.
- GraphQL: no consumer asked for it.
EOF
cat > "$d/docs/agents-v0/design/orders/design.md" <<'EOF'
# Design: orders

ADR: docs/agents-v0/adr/01-orders.md

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

## Events
N/A: no event contract

## Failure modes
Inventory timeout after 2s: reject with 503 and a retry hint; nothing is written.

## Observability
RED metrics per operation, a log field orderId, an alert on 5xx above 1 percent.

## Rollout
Behind flag orders.enabled, default off; expand migration first; rollback by disabling the flag.
EOF
run pass "design: a complete design passes" "$d" sh "$CI/check-design.sh" orders
cp "$d/docs/agents-v0/design/orders/design.md" "$tmp/design.events"
sedi '/N\/A: no event contract/d' "$d/docs/agents-v0/design/orders/design.md"
run fail "design: no event contract without the N/A phrase fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.events" "$d/docs/agents-v0/design/orders/design.md"
cp "$o/async-ok.yaml" "$d/docs/agents-v0/design/orders/asyncapi.yaml"
run fail "design: the N/A phrase fails while asyncapi.yaml exists" "$d" sh "$CI/check-design.sh" orders
rm -f "$d/docs/agents-v0/design/orders/asyncapi.yaml"
mkdir -p "$d/docs/agents-v0/design/orders/events"
printf '{}\n' > "$d/docs/agents-v0/design/orders/events/order-created.json"
run fail "design: the N/A phrase fails while events/ has a file" "$d" sh "$CI/check-design.sh" orders
rm -rf "$d/docs/agents-v0/design/orders/events"
cp "$tmp/design.events" "$d/docs/agents-v0/design/orders/design.md"
cp "$d/docs/agents-v0/requirements/orders.md" "$tmp/req.keep"
cp "$d/docs/agents-v0/design/orders/design.md" "$tmp/design-neg.keep"
cat >> "$d/docs/agents-v0/requirements/orders.md" <<'EOF'

### AC-3 — unknown order
Kind: negative
Given no order for fixture ORD-404
When the caller reads it
Then HTTP 404 and the orders table is unchanged
EOF
sedi '/| AC-2 | operation getOrder |/a\
| AC-3 | operation getOrder |' "$d/docs/agents-v0/design/orders/design.md"
run fail "design: a negative AC missing from Failure modes fails" "$d" sh "$CI/check-design.sh" orders
sedi '/^## Failure modes/a\
AC-3 unknown id returns HTTP 404 and the row is unchanged.' "$d/docs/agents-v0/design/orders/design.md"
run pass "design: naming the negative AC in Failure modes passes" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/req.keep" "$d/docs/agents-v0/requirements/orders.md"
cp "$tmp/design-neg.keep" "$d/docs/agents-v0/design/orders/design.md"
cp "$d/docs/agents-v0/design/orders/design.md" "$tmp/design.md.keep"
sedi '/| AC-2 /d' "$d/docs/agents-v0/design/orders/design.md"
run fail "design: an AC missing from Traceability fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/agents-v0/design/orders/design.md"
sedi '/| getOrder /d' "$d/docs/agents-v0/design/orders/design.md"
run fail "design: an operation missing from Authorization fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/agents-v0/design/orders/design.md"
printf '<!-- TEMPLATE: x -->\n' >> "$d/docs/agents-v0/design/orders/design.md"
run fail "design: a TEMPLATE: line fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/agents-v0/design/orders/design.md"
sedi '/^## Rollout/,$d' "$d/docs/agents-v0/design/orders/design.md"
run fail "design: a missing section fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/design.md.keep" "$d/docs/agents-v0/design/orders/design.md"
cp "$d/docs/agents-v0/adr/01-orders.md" "$tmp/adr.keep"
sedi '/GraphQL/d' "$d/docs/agents-v0/adr/01-orders.md"
run fail "design: an ADR with one alternative fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/adr.keep" "$d/docs/agents-v0/adr/01-orders.md"
sedi '/Status:/d' "$d/docs/agents-v0/adr/01-orders.md"
run fail "design: an ADR without a status fails" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/adr.keep" "$d/docs/agents-v0/adr/01-orders.md"
sedi 's/Accepted/Superseded by ADR 02/' "$d/docs/agents-v0/adr/01-orders.md"
run fail "design: a superseded ADR cannot be cited" "$d" sh "$CI/check-design.sh" orders
cp "$tmp/adr.keep" "$d/docs/agents-v0/adr/01-orders.md"

run fail "design: pinning needs a design review" "$d" sh "$CI/check-design.sh" orders --pin approved
mkdir -p "$d/docs/agents-v0/requirements" "$d/docs/agents-v0/design/skel"
printf '# Skel\nAC-1 the build passes\n' > "$d/docs/agents-v0/requirements/skel.md"
cat > "$d/docs/agents-v0/design/skel/design.md" <<'EOF'
# Design: skeleton

ADR: N/A: no product decision

N/A: no /api/v1 operation

## Traceability
| Requirement | Satisfied by |
|---|---|
| AC-1 | the module verify command |

## Data model
N/A: no persistence in the skeleton.

## Authorization
N/A: no /api/v1 operation

## Events
N/A: no event contract

## Failure modes
The verify command fails closed and prints the module that failed.

## Observability
The build log is the signal for this story.

## Rollout
The skeleton merges to the default branch before feature stories branch.
EOF
run pass "design: a non-API design pins without a review" "$d" sh "$CI/check-design.sh" skel --pin approved
rm -f "$d/docs/agents-v0/design/skel/design.lock"
cp "$o/async-ok.yaml" "$d/docs/agents-v0/design/skel/asyncapi.yaml"
run fail "design: an asyncapi contract needs a review before pinning" "$d" sh "$CI/check-design.sh" skel --pin approved
rm -f "$d/docs/agents-v0/design/skel/asyncapi.yaml"
printf 'GET /health uses @PreAuthorize("permitAll()").\n' >> "$d/docs/agents-v0/design/skel/design.md"
run pass "design: a health permitAll still pins without a review" "$d" sh "$CI/check-design.sh" skel --pin approved
rm -f "$d/docs/agents-v0/design/skel/design.lock"
printf 'POST /api/v1/admin uses permitAll.\n' >> "$d/docs/agents-v0/design/skel/design.md"
run fail "design: a public route still needs a review" "$d" sh "$CI/check-design.sh" skel --pin approved
mkdir -p "$d/docs/agents-v0/design/anon"
printf '# Skel\nAC-1 the build passes\n' > "$d/docs/agents-v0/requirements/anon.md"
cat > "$d/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | dotnet |
EOF
cat > "$d/docs/agents-v0/design/anon/design.md" <<'EOF'
# Design: skeleton

ADR: N/A: no product decision

N/A: no /api/v1 operation

## Traceability
| Requirement | Satisfied by |
|---|---|
| AC-1 | the module verify command |

## Data model
N/A: no persistence in the skeleton.

## Authorization
N/A: no /api/v1 operation

## Events
N/A: no event contract

## Failure modes
The verify command fails closed and prints the module that failed.

## Observability
The build log is the signal for this story.

## Rollout
The skeleton merges to the default branch before feature stories branch.

GET /health uses [AllowAnonymous].
EOF
run pass "design: a health AllowAnonymous pins without a review" "$d" sh "$CI/check-design.sh" anon --pin approved
rm -f "$d/docs/agents-v0/design/anon/design.lock"
printf 'POST /admin uses [AllowAnonymous].\n' >> "$d/docs/agents-v0/design/anon/design.md"
run fail "design: AllowAnonymous on a non-health route needs a review" "$d" sh "$CI/check-design.sh" anon --pin approved
rm -f "$d/docs/agents-v0/project-profile.md"
h1="$(cd "$d" && sh "$CI/check-design.sh" orders --hash)"
printf 'agent: design-reviewer\ndesign-hash: %s\n\n| # | Label | Finding | Evidence | Status |\n|---|---|---|---|---|\n| 1 | Critical | no ownership rule | design.md:20 | Open |\n' "$(printf '%s' "$h1" | cut -c1-12)" > "$d/docs/agents-v0/design/orders/review.md"
run fail "design: an open Critical blocks the pin" "$d" sh "$CI/check-design.sh" orders --pin approved
sedi 's/| Open |/| Resolved |/' "$d/docs/agents-v0/design/orders/review.md"
sedi 's/Accepted/Proposed/' "$d/docs/agents-v0/adr/01-orders.md"
hp="$(cd "$d" && sh "$CI/check-design.sh" orders --hash)"
printf 'agent: design-reviewer\ndesign-hash: %s\n\n| # | Label | Finding | Evidence | Status |\n|---|---|---|---|---|\n| 1 | Critical | no ownership rule | design.md:20 | Resolved |\n' "$(printf '%s' "$hp" | cut -c1-12)" > "$d/docs/agents-v0/design/orders/review.md"
run pass "design: a Proposed ADR still passes the structure check" "$d" sh "$CI/check-design.sh" orders
run fail "design: a Proposed ADR cannot be pinned" "$d" sh "$CI/check-design.sh" orders --pin approved
sedi 's/Proposed/Accepted/' "$d/docs/agents-v0/adr/01-orders.md"
cp "$o/async-ok.yaml" "$d/docs/agents-v0/design/orders/asyncapi.yaml"
sedi 's/N\/A: no event contract/Channel orders.order-created in asyncapi.yaml./' "$d/docs/agents-v0/design/orders/design.md"
ha="$(cd "$d" && sh "$CI/check-design.sh" orders --hash)"
printf 'agent: design-reviewer\ndesign-hash: %s\n\n| # | Label | Finding | Evidence | Status |\n|---|---|---|---|---|\n| 1 | Critical | no ownership rule | design.md:20 | Resolved |\n' "$(printf '%s' "$ha" | cut -c1-12)" > "$d/docs/agents-v0/design/orders/review.md"
run pass "design: a resolved review lets the pin through" "$d" sh "$CI/check-design.sh" orders --pin approved
run pass "design: the lock matches the pinned design" "$d" sh "$CI/check-design.sh" orders --verify-lock
sedi 's/ORDER_CREATED/ORDER_PLACED/' "$d/docs/agents-v0/design/orders/asyncapi.yaml"
run fail "design: modifying asyncapi.yaml after the pin fails the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock
cp "$o/async-ok.yaml" "$d/docs/agents-v0/design/orders/asyncapi.yaml"
run pass "design: restoring asyncapi.yaml matches the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock
cp "$d/docs/agents-v0/adr/01-orders.md" "$tmp/adr.pinned"
sedi 's/Synchronous REST./Synchronous REST plus a queue./' "$d/docs/agents-v0/adr/01-orders.md"
run fail "design: rewriting an accepted ADR fails the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock
cp "$tmp/adr.pinned" "$d/docs/agents-v0/adr/01-orders.md"
run pass "design: restoring the accepted ADR matches the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock
printf 'Also the order list is paged.\n' >> "$d/docs/agents-v0/design/orders/design.md"
sedi 's/^## Rollout/## Rollout\nPaged list./' "$d/docs/agents-v0/design/orders/design.md"
run fail "design: a change after the pin fails the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock
if grep -Fq 'run design-reviewer' "$tmp/out.txt"; then pass "design: a drifted lock says to review before the pin"; else fail "design: a drifted lock says to review before the pin"; fi
h2="$(cd "$d" && sh "$CI/check-design.sh" orders --hash)"
printf 'agent: design-reviewer\ndesign-hash: %s\n' "$(printf '%s' "$h2" | cut -c1-12)" > "$d/docs/agents-v0/design/orders/review.md"
printf '| # | Date | Change | Reason | Impacted | Approver | Decision | Hash |\n|---|---|---|---|---|---|---|---|\n| 1 | 2026-01-02 | paged list | consumer asked | AC-2 | dev | Approved | %s |\n' "$(printf '%s' "$h2" | cut -c1-12)" > "$d/docs/agents-v0/design/orders/amendments.md"
run pass "design: an approved amendment can be pinned" "$d" sh "$CI/check-design.sh" orders --pin "amendment 1"
run pass "design: the lock passes once the amendment is approved" "$d" sh "$CI/check-design.sh" orders --verify-lock
sedi 's/Approved/Pending/' "$d/docs/agents-v0/design/orders/amendments.md"
run fail "design: a pin with no Approved amendment row fails the lock" "$d" sh "$CI/check-design.sh" orders --verify-lock

# --- ci/check-adr.sh ---------------------------------------------------------
adr="$tmp/adr-records"
mkdir -p "$adr/docs/agents-v0/adr"
cat > "$adr/docs/agents-v0/adr/01-store.md" <<'EOF'
# ADR 01: Store

- **Status:** Accepted

## Decision
PostgreSQL.

## Alternatives considered
- MySQL: the team has no operator for it.
- SQLite: it is not shared across instances.
EOF
(cd "$adr" && git init -q && git add -A && git_c commit -q -m accepted)
run pass "adr: a committed accepted ADR passes" "$adr" sh "$CI/check-adr.sh"
cp "$KIT/templates/docs/agents-v0/adr/_template.md" "$adr/docs/agents-v0/adr/_template.md"
run pass "adr: ADR check ignores _template.md" "$adr" sh "$CI/check-adr.sh"
rm -f "$adr/docs/agents-v0/adr/_template.md"
sedi 's/PostgreSQL./MongoDB./' "$adr/docs/agents-v0/adr/01-store.md"
run fail "adr: rewriting a committed accepted ADR fails" "$adr" sh "$CI/check-adr.sh"
(cd "$adr" && git checkout -q -- docs/agents-v0/adr/01-store.md)
sedi 's/Accepted/Superseded by ADR 02/' "$adr/docs/agents-v0/adr/01-store.md"
run fail "adr: supersession without a successor fails" "$adr" sh "$CI/check-adr.sh"
cat > "$adr/docs/agents-v0/adr/02-store.md" <<'EOF'
# ADR 02: Store

- **Status:** Accepted

## Decision
MongoDB.

## Alternatives considered
- PostgreSQL: the new workload is document-shaped.
- SQLite: it is not shared across instances.
EOF
run pass "adr: superseding with an accepted successor passes" "$adr" sh "$CI/check-adr.sh"
sedi 's/Accepted/Proposed/' "$adr/docs/agents-v0/adr/02-store.md"
run fail "adr: a successor that is still Proposed fails" "$adr" sh "$CI/check-adr.sh"
sedi 's/Proposed/Accepted/' "$adr/docs/agents-v0/adr/02-store.md"
sedi 's/Accepted/Superseded by ADR 03/' "$adr/docs/agents-v0/adr/02-store.md"
run fail "adr: a superseded successor without its own successor fails" "$adr" sh "$CI/check-adr.sh"
cat > "$adr/docs/agents-v0/adr/03-store.md" <<'EOF'
# ADR 03: Store

- **Status:** Accepted

## Decision
Document store.

## Alternatives considered
- PostgreSQL: the workload outgrew rows.
- MongoDB: the operator moved off it.
EOF
run pass "adr: a supersession chain that ends Accepted passes" "$adr" sh "$CI/check-adr.sh"
hist="$tmp/adr-history"
mkdir -p "$hist/docs/agents-v0/adr"
cat > "$hist/docs/agents-v0/adr/01-store.md" <<'EOF'
# ADR 01: Store

- **Status:** Accepted

## Decision
PostgreSQL.

## Alternatives considered
- MySQL: the team has no operator for it.
- SQLite: it is not shared across instances.
EOF
(cd "$hist" && git init -q && git add -A && git_c commit -q -m accepted)
sedi 's/PostgreSQL./MongoDB./' "$hist/docs/agents-v0/adr/01-store.md"
(cd "$hist" && git add -A && git_c commit -q -m rewrite)
run fail "adr: a commit that rewrites an accepted ADR fails" "$hist" sh "$CI/check-adr.sh"
inh="$tmp/adr-inherited"
mkdir -p "$inh/docs/agents-v0/adr"
cat > "$inh/docs/agents-v0/adr/0000-inherited-decisions.md" <<'EOF'
# Inherited decisions

- Framework: Spring. Status: Accepted (inherited)
EOF
(cd "$inh" && git init -q && git add -A && git_c commit -q -m inherited)
run pass "adr: an inherited record passes" "$inh" sh "$CI/check-adr.sh"
sedi 's/Spring/Quarkus/' "$inh/docs/agents-v0/adr/0000-inherited-decisions.md"
run fail "adr: rewriting an inherited decision fails" "$inh" sh "$CI/check-adr.sh"

# --- ci/check-ux-spec.sh -----------------------------------------------------
u="$tmp/ux"
mkdir -p "$u/docs/agents-v0/design/orders/mockups"
cp "$o/draft.yaml" "$u/docs/agents-v0/design/orders/openapi.yaml"
cat > "$u/docs/agents-v0/design/orders/ux-spec.md" <<'EOF'
# UX spec

Screens: mockups/new-order.html

| Component | Screen | Mockup | Operation | Default behavior | Override |
|-----------|--------|--------|-----------|------------------|----------|
| Place order button | New order | mockups/new-order.html | createOrder | submits the form | |
| Cancel link | New order | mockups/new-order.html | — | returns to the list | |
EOF
cat > "$u/docs/agents-v0/design/orders/mockups/new-order.html" <<'EOF'
<html><body>
<form><input type="text" name="sku" data-component="Sku field">
<button data-component="Place order button">Place</button>
<a href="#" data-component="Cancel link">Cancel</a></form>
</body></html>
EOF
run fail "ux spec: an input with no row fails" "$u" sh "$CI/check-ux-spec.sh" orders
printf '| Sku field | New order | mockups/new-order.html | — | accepts text | |\n' >> "$u/docs/agents-v0/design/orders/ux-spec.md"
run pass "ux spec: rows and mockup agree" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$u/docs/agents-v0/design/orders/mockups/new-order.html" "$tmp/mock.keep"
sedi 's|<button data-component="Place order button">|<button>|' "$u/docs/agents-v0/design/orders/mockups/new-order.html"
run fail "ux spec: a control with no data-component fails" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$tmp/mock.keep" "$u/docs/agents-v0/design/orders/mockups/new-order.html"
cp "$u/docs/agents-v0/design/orders/ux-spec.md" "$tmp/spec.keep"
sedi 's/| createOrder |/| deleteOrder |/' "$u/docs/agents-v0/design/orders/ux-spec.md"
run fail "ux spec: an operation not in the draft fails" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$tmp/spec.keep" "$u/docs/agents-v0/design/orders/ux-spec.md"
printf '<script>fetch("/api/v1/orders")</script>\n' >> "$u/docs/agents-v0/design/orders/mockups/new-order.html"
run fail "ux spec: a mockup that calls the API fails" "$u" sh "$CI/check-ux-spec.sh" orders
cp "$tmp/mock.keep" "$u/docs/agents-v0/design/orders/mockups/new-order.html"
printf '<html><body><p>spare</p></body></html>\n' > "$u/docs/agents-v0/design/orders/mockups/orphan.html"
run fail "ux spec: a mockup no row references fails" "$u" sh "$CI/check-ux-spec.sh" orders
rm -f "$u/docs/agents-v0/design/orders/mockups/orphan.html"
mkdir -p "$tmp/noui"
run pass "ux spec: a story with no UX spec passes" "$tmp/noui" sh "$CI/check-ux-spec.sh" orders

# --- ci/check-build-plan.sh --------------------------------------------------
b="$tmp/build"
mkdir -p "$b/docs/agents-v0/requirements" "$b/docs/agents-v0/build/orders" "$b/src/test/java"
printf '# Orders\nAC-1 place an order\nAC-2 read an order\n' > "$b/docs/agents-v0/requirements/orders.md"
printf 'class OrderServiceTest {\n  void create_valid_returnsId() {}\n  void get_unknown_returns404() {}\n}\n' > "$b/src/test/java/OrderServiceTest.java"
cat > "$b/docs/agents-v0/build/orders/plan.md" <<'EOF'
# Build plan

| AC | Status | Test |
|----|--------|------|
| AC-1 | done | OrderServiceTest#create_valid_returnsId |
| AC-2 | pending | |
EOF
cat > "$b/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build report

commit: abcdef1234567

| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| mvn verify | 1 | 1 | OrderServiceTest#create_valid_returnsId | OrderService.java:10 |
| mvn verify | 0 | 2 | | |
EOF
run pass "build plan: a done row with an existing, red-first test passes" "$b" sh "$CI/check-build-plan.sh" orders
run fail "build plan: --complete fails while a row is pending" "$b" sh "$CI/check-build-plan.sh" orders --complete
cp "$b/docs/agents-v0/build/orders/plan.md" "$tmp/plan.keep"
sedi 's/| AC-2 | pending | |/| AC-2 | done | OrderServiceTest#get_unknown_returns404 |/' "$b/docs/agents-v0/build/orders/plan.md"
run fail "build plan: a done row with no red card fails" "$b" sh "$CI/check-build-plan.sh" orders
sedi 's/get_unknown_returns404 |/get_unknown_returns404 (no-red: configuration only) |/' "$b/docs/agents-v0/build/orders/plan.md"
run pass "build plan: (no-red: reason) waives the red card for one row" "$b" sh "$CI/check-build-plan.sh" orders --complete
sedi 's/get_unknown_returns404 (no-red: configuration only)/missing_method_name/' "$b/docs/agents-v0/build/orders/plan.md"
run fail "build plan: a test that no test file contains fails" "$b" sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/agents-v0/build/orders/plan.md"
sedi '/| AC-2 /d' "$b/docs/agents-v0/build/orders/plan.md"
run fail "build plan: a requirement with no plan row fails" "$b" sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/agents-v0/build/orders/plan.md"
printf '| AC-9 | pending | |\n' >> "$b/docs/agents-v0/build/orders/plan.md"
run fail "build plan: a row that is not a requirement fails" "$b" sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/agents-v0/build/orders/plan.md"
sedi 's/| AC-2 | pending | |/| AC-2 | done | OrderServiceTest#get_unknown_returns404 |/' "$b/docs/agents-v0/build/orders/plan.md"
run pass "build plan: REQUIRE_RED=0 turns the red-first check off" "$b" env REQUIRE_RED=0 sh "$CI/check-build-plan.sh" orders
cp "$tmp/plan.keep" "$b/docs/agents-v0/build/orders/plan.md"
run fail "build plan: REQUIRE_RED_REPORT=1 fails when only a markdown card exists without a machine report" "$b" env REQUIRE_RED_REPORT=1 sh "$CI/check-build-plan.sh" orders
mkdir -p "$b/target/surefire-reports"
cat > "$b/target/surefire-reports/TEST-OrderServiceTest.xml" <<'EOF'
<testsuite tests="1" failures="1">
  <testcase classname="com.acme.OrderServiceTest" name="create_valid_returnsId">
    <failure message="expected 201"/>
  </testcase>
</testsuite>
EOF
run pass "build plan: --record-red snapshots failing test IDs from JUnit XML into red-tests.json" "$b" sh "$CI/check-build-plan.sh" orders --record-red
cat > "$b/target/surefire-reports/TEST-OrderServiceTest.xml" <<'EOF'
<testsuite tests="1" failures="0">
  <testcase classname="com.acme.OrderServiceTest" name="create_valid_returnsId"/>
</testsuite>
EOF
run pass "build plan: REQUIRE_RED_REPORT=1 passes after --record-red even when green overwrote the XML" "$b" env REQUIRE_RED_REPORT=1 sh "$CI/check-build-plan.sh" orders
sedi 's/| AC-2 | pending | |/| AC-2 | done | OrderServiceTest#get_unknown_returns404 |/' "$b/docs/agents-v0/build/orders/plan.md"
printf '| mvn verify | 1 | 2 | OrderServiceTest#get_unknown_returns404 | OrderService.java:20 |\n' >> "$b/docs/agents-v0/build/orders/build-report.md"
run fail "build plan: a markdown red card not backed by red-tests.json fails when red-tests.json is present" "$b" sh "$CI/check-build-plan.sh" orders
rm -f "$b/docs/agents-v0/build/orders/red-tests.json"
cp "$tmp/plan.keep" "$b/docs/agents-v0/build/orders/plan.md"
sedi 's|OrderService.java:10|target/surefire-reports/TEST-OrderServiceTest.xml|' "$b/docs/agents-v0/build/orders/build-report.md"
run fail "build plan: a card Location naming a green XML report fails machine verification" "$b" sh "$CI/check-build-plan.sh" orders
cat > "$b/target/surefire-reports/TEST-OrderServiceTest.xml" <<'EOF'
<testsuite tests="1" failures="1">
  <testcase classname="com.acme.OrderServiceTest" name="create_valid_returnsId">
    <failure message="expected 201"/>
  </testcase>
</testsuite>
EOF
run pass "build plan: a card Location naming a failing XML report passes machine verification" "$b" sh "$CI/check-build-plan.sh" orders

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
mkdir -p "$e/docs/agents-v0"
cat > "$e/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | java |
EOF
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
mkdir -p "$e/docs/agents-v0" "$e/api"
cat > "$e/docs/agents-v0/project-profile.md" <<'EOF'
## Endpoint authorization

| Stack | Suffix | Marker | Mapping | Security |
|-------|--------|--------|---------|----------|
| fastapi | .py | APIRouter | @(?:router)\.(get|post)\(\s*["']([^"']+) | require_role|Depends\( |
EOF
cat > "$e/api/routes.py" <<'EOF'
from fastapi import APIRouter
router = APIRouter()

@router.get("/health")
def health():
    return {}
EOF
(cd "$e" && git add docs/agents-v0/project-profile.md api/routes.py)
run fail "endpoint auth: a profile stack flags a new unannotated route" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
cat > "$e/api/routes.py" <<'EOF'
from fastapi import APIRouter
router = APIRouter()

@router.get("/health")
def health():
    return require_role()
EOF
run pass "endpoint auth: a profile stack accepts a secured route" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"

# Pack-native endpoint scanners: dotnet Minimal API, python custom router, go Chi router
cat > "$e/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | dotnet |
EOF
cat > "$e/Program.cs" <<'EOF'
app.MapPost("/api/v1/orders", () => Results.Ok());
EOF
(cd "$e" && git add docs/agents-v0/project-profile.md Program.cs)
run fail "endpoint auth: dotnet pack flags an unannotated Minimal API MapPost" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
cat > "$e/Program.cs" <<'EOF'
app.MapPost("/api/v1/orders", () => Results.Ok()).RequireAuthorization();
EOF
run pass "endpoint auth: dotnet pack accepts a Minimal API MapPost with RequireAuthorization" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
rm -f "$e/Program.cs"

cat > "$e/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | python |
EOF
cat > "$e/api/routes.py" <<'EOF'
from fastapi import APIRouter
orders_router = APIRouter()

@orders_router.post("/api/v1/orders")
def create_order():
    return {}
EOF
run fail "endpoint auth: python pack flags an unannotated @orders_router.post route" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
cat > "$e/api/routes.py" <<'EOF'
from fastapi import APIRouter, Depends
orders_router = APIRouter()

@orders_router.post("/api/v1/orders")
def create_order(user=Depends(auth)):
    return {}
EOF
run pass "endpoint auth: python pack accepts @orders_router.post with Depends" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"

cat > "$e/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | go |
EOF
cat > "$e/routes.go" <<'EOF'
package main
import "github.com/go-chi/chi/v5"
func routes() {
	r := chi.NewRouter()
	r.Post("/api/v1/orders", createOrder)
}
EOF
(cd "$e" && git add routes.go)
run fail "endpoint auth: go pack flags an unannotated Chi r.Post route" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
cat > "$e/routes.go" <<'EOF'
package main
import "github.com/go-chi/chi/v5"
func routes() {
	r := chi.NewRouter()
	r.With(AuthMiddleware).Post("/api/v1/orders", createOrder)
}
EOF
run pass "endpoint auth: go pack accepts a Chi r.Post route with AuthMiddleware" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
rm -f "$e/routes.go"

cat > "$e/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | node |
EOF
cat > "$e/orders.routes.ts" <<'EOF'
import { Router } from 'express';
const ordersRouter = Router();
ordersRouter.post('/api/v1/orders', (req, res) => res.json({}));
EOF
(cd "$e" && git add docs/agents-v0/project-profile.md orders.routes.ts)
run fail "endpoint auth: node pack flags an unannotated Express ordersRouter.post route" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"
cat > "$e/orders.routes.ts" <<'EOF'
import { Router } from 'express';
const ordersRouter = Router();
ordersRouter.post('/api/v1/orders', requireAuth, (req, res) => res.json({}));
EOF
run pass "endpoint auth: node pack accepts Express ordersRouter.post with requireAuth" "$e" sh "$CI/check-endpoint-auth.sh" "$ebase"

# --- ci/check-frontend-calls.sh ----------------------------------------------
f="$tmp/frontend"
mkdir -p "$f/.agents-v0/ci" "$f/openapi" "$f/frontend/src/lib" "$f/frontend/src/lib/__tests__"
cp "$CI/resolve-layout.sh" "$f/.agents-v0/ci/"
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

fnode="$tmp/frontend-node-service"
mkdir -p "$fnode/.agents-v0/ci" "$fnode/src"
cp "$CI/resolve-layout.sh" "$CI/packlib.py" "$fnode/.agents-v0/ci/"
printf '{"name":"orders-api","dependencies":{"express":"4.19.0"}}\n' > "$fnode/package.json"
printf "app.get('/api/v1/unlisted', (req, res) => res.json({}));\n" > "$fnode/src/routes.ts"
run pass "frontend calls: a root-level backend Node package.json is not scanned as a frontend root" "$fnode" sh "$CI/check-frontend-calls.sh"

if [ "$status" -ne 0 ]; then
  echo "test-design-build: FAILED" >&2
  exit 1
fi
echo "test-design-build: OK"
