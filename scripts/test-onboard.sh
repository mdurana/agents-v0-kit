#!/bin/sh
# test-onboard.sh — behavior tests for the /v0-onboard scripts on a fixture repo (no network).
# Covers: discover-codebase.sh, generate-repo-map.sh, collect-dependency-graphs.sh,
# check-onboarding-docs.sh, sync-feature-state.sh (onboarding), and the guard's normal path start -> ready ->
# approve -> commit (onboard redo, Design: D6). Run by validate-kit.sh. Needs python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
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
mkdir -p "$r/.agents-v0/scripts" "$r/docs/agents-v0"
cp "$KIT"/templates/.agents-v0/scripts/resolve-layout.sh \
   "$KIT"/templates/.agents-v0/scripts/endpoint_scan.py \
   "$KIT"/templates/.agents-v0/scripts/packlib.py \
   "$KIT"/templates/.agents-v0/scripts/discover-codebase.sh \
   "$KIT"/templates/.agents-v0/scripts/generate-repo-map.sh \
   "$KIT"/templates/.agents-v0/scripts/collect-dependency-graphs.sh \
   "$KIT"/templates/.agents-v0/scripts/check-onboarding-docs.sh \
   "$KIT"/templates/.agents-v0/scripts/sync-feature-state.sh \
   "$KIT"/templates/.agents-v0/scripts/audit-brownfield-baseline.sh "$r/.agents-v0/scripts/"
mkdir -p "$r/.agents-v0/ui/react"
cp "$KIT/core/ui/react/pack.json" "$r/.agents-v0/ui/react/pack.json"
for id in java dotnet node python go; do
  mkdir -p "$r/.agents-v0/packs/$id"
  cp "$KIT/core/$id/pack.json" "$r/.agents-v0/packs/$id/pack.json"
done
cat > "$r/docs/agents-v0/project-profile.md" <<'EOF'
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
expect_pass "discover-codebase runs on the fixture" "$r" sh .agents-v0/scripts/discover-codebase.sh
d="$r/docs/agents-v0/discovery"
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

(cd "$r" && DISCOVER_MAX=1 sh .agents-v0/scripts/discover-codebase.sh >/dev/null 2>&1)
has "a capped list says it was cut" "$d/endpoints.txt" "TRUNCATED: showing 1 of 5"

# baseline numbers from target/ reports
mkdir -p "$o/target/surefire-reports" "$o/target/site/jacoco"
printf '<testsuite tests="4" failures="1" errors="0" skipped="0"/>\n' > "$o/target/surefire-reports/TEST-a.xml"
cat > "$o/target/site/jacoco/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="x"><counter type="LINE" missed="1" covered="1"/></report>
EOF
(cd "$r" && sh .agents-v0/scripts/discover-codebase.sh >/dev/null 2>&1)
has "baseline: coverage read from jacoco.xml" "$d/baseline.md" "50.0%"
has "baseline: proposed coverage ratchet row" "$d/baseline.md" "| services/order | 50% |"
has "baseline: proposed known_failures row" "$d/baseline.md" "| 1 | services/order |"

# --- generate-repo-map.sh ----------------------------------------------------
expect_pass "generate-repo-map runs on the fixture" "$r" sh .agents-v0/scripts/generate-repo-map.sh
has "repo map: resolved service roots" "$r/docs/agents-v0/repo-map.md" '`services/inventory`'
has "repo map: Maven build file under a service root" "$r/docs/agents-v0/repo-map.md" 'services/order/pom.xml'
has "repo map: controller found" "$r/docs/agents-v0/repo-map.md" "OrderController.java"
has "repo map: commit stamped" "$r/docs/agents-v0/repo-map.md" "commit:"

# --- collect-dependency-graphs.sh --------------------------------------------
g="$tmp/graphs"
mkdir -p "$g/.agents-v0/scripts" "$g/docs/agents-v0" "$g/services/order" "$g/services/inventory"
cp "$KIT"/templates/.agents-v0/scripts/resolve-layout.sh \
   "$KIT"/templates/.agents-v0/scripts/collect-dependency-graphs.sh "$g/.agents-v0/scripts/"
: > "$g/services/order/pom.xml"
: > "$g/services/inventory/pom.xml"
cat > "$g/services/order/mvnw" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in -DoutputFile=*) out="${a#-DoutputFile=}" ;; esac; done
printf 'com.acme:order:jar:1\n' >> "$out"
EOF
printf '#!/bin/sh\nexit 1\n' > "$g/services/inventory/mvnw"
chmod +x "$g/services/order/mvnw" "$g/services/inventory/mvnw"
expect_fail "dependency graphs: a failing root makes the script exit non-zero" "$g" sh .agents-v0/scripts/collect-dependency-graphs.sh
has "dependency graphs: a working root writes its own graph" "$g/docs/agents-v0/discovery/dependency-graph.services-order.txt" "com.acme:order"
if (cd "$g" && sh .agents-v0/scripts/collect-dependency-graphs.sh 2>&1) | grep -Fq "dependency:tree failed under services/inventory"; then
  pass "dependency graphs: the failing root is named"
else
  fail "dependency graphs: the failing root is named"
fi

pack_graph() {
  name="$1"
  dir="$tmp/graph-$name"
  mkdir -p "$dir/.agents-v0/scripts" "$dir/docs/agents-v0" "$dir/bin"
  cp "$KIT"/templates/.agents-v0/scripts/resolve-layout.sh \
     "$KIT"/templates/.agents-v0/scripts/collect-dependency-graphs.sh "$dir/.agents-v0/scripts/"
  printf '%s' "$dir"
}
d="$(pack_graph dotnet)"
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$d/App.csproj"
cat > "$d/bin/dotnet" <<'EOF'
#!/bin/sh
printf '   > Newtonsoft.Json                 13.0.3\n'
EOF
chmod +x "$d/bin/dotnet"
expect_pass "dependency graphs: dotnet list package writes a graph" "$d" env PATH="$d/bin:$PATH" sh .agents-v0/scripts/collect-dependency-graphs.sh
has "dependency graphs: dotnet graph names the package" "$d/docs/agents-v0/discovery/dotnet-graph.txt" "Newtonsoft.Json"

d="$(pack_graph go)"
printf 'module example.com/app\n\ngo 1.26\n' > "$d/go.mod"
cat > "$d/bin/go" <<'EOF'
#!/bin/sh
printf 'example.com/app\nexample.com/dep v1.2.3\n'
EOF
chmod +x "$d/bin/go"
expect_pass "dependency graphs: go list writes a graph" "$d" env PATH="$d/bin:$PATH" sh .agents-v0/scripts/collect-dependency-graphs.sh
has "dependency graphs: go graph names the module" "$d/docs/agents-v0/discovery/go-graph.txt" "example.com/dep"

d="$(pack_graph python)"
printf '[project]\nname = "app"\n' > "$d/pyproject.toml"
cat > "$d/bin/python3" <<'EOF'
#!/bin/sh
printf 'fastapi==0.115.0\n'
EOF
chmod +x "$d/bin/python3"
expect_pass "dependency graphs: pip freeze writes a graph" "$d" env PATH="$d/bin:$PATH" sh .agents-v0/scripts/collect-dependency-graphs.sh
has "dependency graphs: python graph names the package" "$d/docs/agents-v0/discovery/python-graph.txt" "fastapi==0.115.0"

# --- check-onboarding-docs.sh ------------------------------------------------
mkdir -p "$r/docs/agents-v0/onboarding/modules"
cite='`services/order/src/main/java/com/acme/order/OrderController.java:7`'
cat > "$r/docs/agents-v0/onboarding/report.md" <<EOF
# Onboarding report

commit: abcdef1234567

The controller is at $cite. The database is reached at db.internal:5432 and \`example.com:8080\`.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
expect_pass "onboarding docs: a real citation passes and hostnames are not citations" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
printf 'Also see `services/order/src/Missing.java:3`.\n' >> "$r/docs/agents-v0/onboarding/report.md"
expect_fail "onboarding docs: a citation to a missing file fails" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/agents-v0/onboarding/report.md" && rm -f "$r/docs/agents-v0/onboarding/report.md.bak"
printf 'Out of range: `services/order/src/main/java/com/acme/order/OrderController.java:999`.\n' >> "$r/docs/agents-v0/onboarding/report.md"
expect_fail "onboarding docs: a line past the end of the file fails" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/agents-v0/onboarding/report.md" && rm -f "$r/docs/agents-v0/onboarding/report.md.bak"
printf '<!-- TEMPLATE: replace -->\n' >> "$r/docs/agents-v0/onboarding/report.md"
expect_fail "onboarding docs: a TEMPLATE: marker fails" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/agents-v0/onboarding/report.md" && rm -f "$r/docs/agents-v0/onboarding/report.md.bak"
printf '> Instruction: cite code as `path/File.java:42` and delete each `TEMPLATE:` line when you replace it.\n' >> "$r/docs/agents-v0/onboarding/report.md"
expect_pass "onboarding docs: blockquote instruction lines with TEMPLATE: and example path/File.java:42 pass" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/agents-v0/onboarding/report.md" && rm -f "$r/docs/agents-v0/onboarding/report.md.bak"
printf 'Owner: UNVERIFIED\n\n## Open questions and UNVERIFIED items\n\n| # | Item | Source | Owner |\n|---|------|--------|-------|\n| 1 | Order retry policy | %s | UNVERIFIED |\n' "$cite" >> "$r/docs/agents-v0/onboarding/report.md"
expect_pass "onboarding docs: UNVERIFIED in headings and Owner column does not count against MAX_UNVERIFIED=0" "$r" env MAX_UNVERIFIED=0 sh .agents-v0/scripts/check-onboarding-docs.sh
sed -i.bak '/^Owner: UNVERIFIED/,$d' "$r/docs/agents-v0/onboarding/report.md" && rm -f "$r/docs/agents-v0/onboarding/report.md.bak"
printf 'Retention is UNVERIFIED.\n' >> "$r/docs/agents-v0/onboarding/report.md"
expect_pass "onboarding docs: UNVERIFIED is counted, not failed, by default" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
expect_fail "onboarding docs: MAX_UNVERIFIED=0 fails on an unknown" "$r" env MAX_UNVERIFIED=0 sh .agents-v0/scripts/check-onboarding-docs.sh
sed -i.bak '$d' "$r/docs/agents-v0/onboarding/report.md" && rm -f "$r/docs/agents-v0/onboarding/report.md.bak"
printf '# Module: order\n\nNo commit line here.\n' > "$r/docs/agents-v0/onboarding/modules/order.md"
expect_fail "onboarding docs: a module document needs a commit line" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
cat > "$r/docs/agents-v0/onboarding/modules/order.md" <<'EOF'
# Module: order

commit: abcdef1234567

- Retry policy: UNVERIFIED — not in config.
EOF
expect_fail "onboarding docs: module UNVERIFIED without an open question row in report.md fails" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
cat >> "$r/docs/agents-v0/onboarding/report.md" <<EOF

## Open questions and UNVERIFIED items

| # | Question or unverified item | Where seen | Suggested owner |
|---|-----------------------------|------------|-----------------|
| 1 | Order retry policy | $cite | UNVERIFIED |
EOF
expect_pass "onboarding docs: module UNVERIFIED listed in report.md Open questions passes" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
rm -f "$r/docs/agents-v0/onboarding/modules/order.md"
mv "$r/docs/agents-v0/onboarding/report.md" "$r/docs/agents-v0/onboarding/report.keep"
expect_fail "onboarding docs: the default run needs the report" "$r" sh .agents-v0/scripts/check-onboarding-docs.sh
mv "$r/docs/agents-v0/onboarding/report.keep" "$r/docs/agents-v0/onboarding/report.md"

# --- onboarding state and approval -------------------------------------------
expect_pass "state: onboarding in progress" "$r" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md --active-phase onboard --status in_progress
has "state: written beside the report" "$r/docs/agents-v0/onboarding/state.json" '"activePhase": "onboard"'
has "state: feature is onboarding" "$r/docs/agents-v0/onboarding/state.json" '"feature": "onboarding"'
has "state: baseCommit pinned from report commit header" "$r/docs/agents-v0/onboarding/state.json" '"baseCommit": "abcdef1234567"'
expect_pass "state: approval clears the active phase" "$r" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md --approve onboard --clear-active
has "state: last approved phase is onboard" "$r/docs/agents-v0/onboarding/state.json" '"lastApprovedPhase": "onboard"'
has "state: baseCommit preserved across approval sync" "$r/docs/agents-v0/onboarding/state.json" '"baseCommit": "abcdef1234567"'
has "state: artifacts map records primary report path" "$r/docs/agents-v0/onboarding/state.json" '"primary": "docs/agents-v0/onboarding/report.md"'
expect_fail "state: an intake phase is not valid for onboarding" "$r" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md --active-phase intake --status in_progress

# --- C# controller route resolution, placeholder secrets, and dotnet baseline -
disc="$r/docs/agents-v0/discovery"
cs="$r/services/inventory"
cat > "$cs/InventoryController.cs" <<'EOF'
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Acme.Inventory;

[ApiController]
[Route("api/[controller]")]
public class InventoryController : ControllerBase
{
    [HttpGet]
    public IActionResult ListAll() => Ok();

    [Authorize]
    [HttpPost("{id}/[action]")]
    public IActionResult Reserve(int id) => Ok();
}
EOF
cat > "$cs/appsettings.json" <<'EOF'
{
  "Emailer": {
    "senderPassword": "CHANGEME"
  }
}
EOF
expect_pass "discover-codebase runs with C# controller and placeholder config" "$r" sh .agents-v0/scripts/discover-codebase.sh
has "endpoints: C# [controller] token resolved on class route" "$disc/endpoints.txt" "GET /api/inventory  NO-ANNOTATION"
has "endpoints: C# [controller] and [action] tokens resolved with [Authorize]" "$disc/endpoints.txt" "POST /api/inventory/{id}/reserve  annotated"
lacks "endpoints: raw [controller] template token is not stored" "$disc/endpoints.txt" "[controller]"
has "config: CHANGEME placeholder classified as (placeholder)" "$disc/config.txt" "Emailer.senderPassword  (placeholder)"
lacks "security baseline: CHANGEME placeholder not flagged as LITERAL-IN-FILE" "$disc/security-baseline.md" "Emailer.senderPassword"

b="$tmp/dotnet-baseline"
mkdir -p "$b/.agents-v0/scripts" "$b/bin"
cp "$KIT"/templates/.agents-v0/scripts/audit-brownfield-baseline.sh "$b/.agents-v0/scripts/"
printf 'Microsoft Visual Studio Solution File, Format Version 12.00\n' > "$b/App.sln"
cat > "$b/bin/dotnet" <<'EOF'
#!/bin/sh
case "$1" in
  build) printf 'Build succeeded.\n' ;;
  test) printf 'Test run for App.dll (.NETCoreApp,Version=v8.0)\nNo test is available in App.dll.\n' ;;
  list) printf 'The given project has no vulnerable packages given the current sources.\n' ;;
esac
EOF
chmod +x "$b/bin/dotnet"
expect_fail "audit-brownfield-baseline: fails when dotnet test executes 0 tests" "$b" env PATH="$b/bin:$PATH" sh .agents-v0/scripts/audit-brownfield-baseline.sh
cat > "$b/bin/dotnet" <<'EOF'
#!/bin/sh
case "$1" in
  build) printf 'Build succeeded.\n' ;;
  test) printf 'Passed!  - Failed:     0, Passed:     2, Skipped:     0, Total:     2\n' ;;
  list) printf 'The given project has no vulnerable packages given the current sources.\n' ;;
esac
EOF
chmod +x "$b/bin/dotnet"
expect_pass "audit-brownfield-baseline: passes when dotnet test runs real tests" "$b" env PATH="$b/bin:$PATH" sh .agents-v0/scripts/audit-brownfield-baseline.sh

# --- normal path through the guard: start -> ready -> approve -> commit (onboard redo, Design: D6) ---------------
# Same helpers as test-guard-commit.sh: a kit test copy (install.sh --test-overrides) so AGENTS_V0_APPROVALS_DIR sends
# the user's approval record to a temp folder, and his approve words typed on a pseudo-terminal. Normal path only.
onboard_normal_path() (
  for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  export AGENTS_V0_APPROVALS_DIR="$tmp/np-approvals"
  p="$tmp/np"; G="$p/.agents-v0/scripts"
  mkdir -p "$p" && git -C "$p" init -q -b main && printf 'x\n' > "$p/README.md" && git -C "$p" add README.md && git -C "$p" commit -q -m init \
    || { echo "setup: fixture repo"; exit 1; }
  KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" --test-overrides "$p" >"$tmp/np-install.log" 2>&1 || { echo "setup: install --test-overrides"; tail -20 "$tmp/np-install.log"; exit 1; }
  # Design: DA: a fresh install ships .cursor/cli.json with an empty allow, so supervised cursor-agent asks before every command.
  python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["permissions"]["allow"] == [] else 1)' "$p/.cursor/cli.json" \
    || { echo "fresh install: .cursor/cli.json allow list is not empty (supervised runs would not ask)"; exit 1; }
  git -C "$p" add -A && git -C "$p" commit -q -m "install agents-v0" || { echo "setup: commit the install"; exit 1; }
  (cd "$p" && sh "$G/guard-onboard.sh" start) || { echo "start failed"; exit 1; }
  head="$(git -C "$p" rev-parse HEAD)"
  printf '# Onboarding report\n\ncommit: %s\n\nThe app entry point is `README.md:1`.\n' "$head" > "$p/docs/agents-v0/onboarding/report.md"
  for d in architecture.md network.md; do
    [ ! -f "$p/docs/agents-v0/$d" ] || printf '# %s\n\nOne module, no network calls (`README.md:1`).\n' "$d" > "$p/docs/agents-v0/$d"
  done
  (cd "$p" && sh "$G/guard-onboard.sh" ready) || { echo "ready failed"; exit 1; }
  python3 - "$p" "$G/guard-common.sh" "Approved, the onboarding docs are right" <<'PY2' || { echo "approve failed"; exit 1; }
import os, pty, sys, time
proj, script, words = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.execvp("sh", ["sh", script, "approve", "onboard"])
buf, sent, end = b"", False, time.time() + 60
while time.time() < end:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    if not sent and b"Type your approval words" in buf:
        os.write(fd, words.encode() + b"\r")
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PY2
  (cd "$p" && sh "$G/guard-onboard.sh" commit) || { echo "commit failed"; exit 1; }
  [ "$(git -C "$p" rev-parse HEAD~1)" = "$head" ] || { echo "not exactly one new commit"; exit 1; }
  [ "$(git -C "$p" rev-parse onboard-v1^{commit})" = "$(git -C "$p" rev-parse HEAD)" ] && [ "$(git -C "$p" cat-file -t onboard-v1)" = tag ] \
    || { echo "no annotated onboard-v1 tag on the commit"; exit 1; }
  [ -z "$(git -C "$p" status --porcelain --untracked-files=all | grep -v '\.lock$')" ] || { echo "tree not clean after commit"; git -C "$p" status --porcelain; exit 1; }
)
if np_out="$(onboard_normal_path 2>&1)"; then
  pass "onboard normal path: fresh install has an empty cli.json allow; start, ready, approve, commit make one commit tagged onboard-v1, tree clean"
else
  fail "onboard normal path: start, ready, approve, commit"; printf '%s\n' "$np_out" | tail -20 | sed 's/^/    /' >&2
fi

if [ "$status" -ne 0 ]; then
  echo "test-onboard: FAILED" >&2
  exit 1
fi
echo "test-onboard: OK"
