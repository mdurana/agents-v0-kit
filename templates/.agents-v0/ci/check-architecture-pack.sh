#!/bin/sh
# check-architecture-pack.sh — the program architecture pack is complete and consistent
# (program-architecture, workflow-orchestration.mdc Architecture).
#
# Usage: sh check-architecture-pack.sh [--approved] [--without-review] [<architecture.md>]
#   <architecture.md>  default docs/agents-v0/architecture.md. The other pack files are read
#                      from the same docs/agents-v0/ tree.
#   --approved         the pattern ADR must already be Accepted (CI, after the architecture row).
#   --without-review   skip architecture-review.md check (for pre-review check by architect or reviewer).
#
# Fails when:
#   - C4 Context or C4 Container is empty or has no Mermaid block, or names a product technology;
#   - Data flow, Data models (Conceptual, Logical, Physical), State machine, Failure domains and
#     degradation, or MVP and future state is empty, still a placeholder, or lacks its diagram.
#     "N/A: <reason>" is accepted wherever the template allows it;
#   - the Data flow diagram uses different nodes than the C4 Container diagram;
#   - network.md has no Target topology diagram (or N/A with a reason);
#   - arc-record.md does not name an existing pattern ADR, or has no structural fitness function row;
#   - nfr-slo.md, threat-model.md, ops-readiness.md, or context-map.md has no filled row;
#   - a context-map row has no existing component plan and no "N/A: <reason>";
#   - architecture-review.md is missing, was not written by design-reviewer, or has an open Critical
#     (unless --without-review is set).

set -eu

approved=0
without_review=0
arch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --approved) approved=1; shift ;;
    --without-review) without_review=1; shift ;;
    -*) printf 'usage: %s [--approved] [--without-review] [<architecture.md>]\n' "$0" >&2; exit 1 ;;
    *) arch="$1"; shift ;;
  esac
done
[ -n "$arch" ] || arch="docs/agents-v0/architecture.md"
[ -f "$arch" ] || { printf 'FAIL: architecture file not found: %s\n' "$arch" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$arch" APPROVED="$approved" WITHOUT_REVIEW="$without_review" PACKLIB_DIR="$DIR" python3 - <<'PY'
import os
import re
import sys

sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib

arch = os.environ["ARCH"]
approved = os.environ["APPROVED"] == "1"
without_review = os.environ["WITHOUT_REVIEW"] == "1"
base = os.path.dirname(arch) or "."
system = os.path.join(base, "design", "system")
failures = []


def fail(message):
    failures.append(message)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def split_sections(text, level):
    """Map normalized heading text to its body, for headings of exactly this level."""
    out, name, buf, fenced = {}, None, [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
        m = None if fenced else re.match(r"^(#+)\s+(.*?)\s*$", line)
        if m and len(m.group(1)) <= level:
            if name is not None and name not in out:
                out[name] = "\n".join(buf)
            name = m.group(2).lower() if len(m.group(1)) == level else None
            buf = []
            continue
        if name is not None:
            buf.append(line)
    if name is not None and name not in out:
        out[name] = "\n".join(buf)
    return out


COMMENT = re.compile(r"<!--.*?-->", re.S)


def strip_comments(body):
    return COMMENT.sub("", body)


def table_rows(body):
    """Return (header, rows): the first table in body, header cells and data rows as cell lists."""
    lines = [l.strip() for l in strip_comments(body).splitlines()]
    for i, line in enumerate(lines):
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|?$", lines[i + 1]):
            header = [c.strip() for c in line.strip("|").split("|")]
            rows = []
            for row in lines[i + 2:]:
                if not row.startswith("|"):
                    break
                rows.append([c.strip() for c in row.strip("|").split("|")])
            return header, rows
    return None, []


def filled_rows(rows, minimum=2):
    return [r for r in rows if sum(1 for c in r if c and not c.startswith("<")) >= minimum]


def substantive(body):
    """True when the body holds more than comments, empty table rows, or a template placeholder."""
    text = strip_comments(body)
    if re.search(r"\bplaceholder\[", text) or "TEMPLATE:" in text:
        return False
    kept = []
    lines = text.splitlines()
    for i, raw in enumerate(lines):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("|"):
            if re.match(r"^\|[\s:|-]+\|?$", line):
                continue
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            if re.match(r"^\|[\s:|-]+\|?$", nxt):
                continue  # header row
            cells = [c.strip() for c in line.strip("|").split("|")]
            if sum(1 for c in cells if c) < 2:
                continue
        kept.append(line)
    return bool(kept)


def is_na(body):
    m = re.search(r"^\s*N/A:\s*(\S.*)$", strip_comments(body), re.M)
    return bool(m and len(m.group(1).strip()) >= 8)


def has_block(body, kinds):
    return any(re.search(r"```mermaid[\s\S]*?\b%s\b[\s\S]*?```" % k, body) for k in kinds)


def mermaid_blocks(body):
    return re.findall(r"```mermaid\n([\s\S]*?)```", body)


KEYWORDS = {"subgraph", "end", "flowchart", "graph", "direction", "style", "classdef", "class",
            "click", "linkstyle", "tb", "td", "lr", "rl", "bt"}


def node_ids(diagram):
    """Node IDs of a flowchart. Labels, edge text, and subgraph lines are ignored."""
    ids = set()
    for raw in diagram.splitlines():
        line = raw.split("%%", 1)[0].strip()
        if not line or line.split(None, 1)[0].lower() in KEYWORDS:
            continue
        line = re.sub(r"\|[^|]*\|", " ", line)
        line = re.sub(r"\"[^\"]*\"", " ", line)
        line = re.sub(r"--[^->|]*-->", " --> ", line)
        line = re.sub(r"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}", " ", line)
        for token in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", line):
            if token.lower() not in KEYWORDS:
                ids.add(token)
    return ids


TECH = re.compile(
    r"\b(kafka|rabbitmq|activemq|postgres(?:ql)?|mysql|mariadb|mongodb|dynamodb|redis|memcached|"
    r"elasticsearch|kubernetes|k8s|eks|aws|azure|gcp|spring(?: boot)?|svelte(?:kit)?|angular|"
    r"java|kotlin|nginx|docker|terraform|hazelcast|caffeine|yugabyte(?:db)?|flyway|liquibase|"
    r"dotnet|asp\.net|csharp|entity framework|ef core|nodejs|node\.js|nestjs|express|typescript|"
    r"python|fastapi|django|pydantic|alembic|golang|gin|chi|go)\b", re.I)
PACK_LINE = re.compile(r"^Pack:\s*(\S+)\s*$", re.M)

text = read(arch)
h2 = split_sections(text, 2)

# --- C4: present, drawn, technology-agnostic ---------------------------------
for name in ("c4 context", "c4 container"):
    body = h2.get(name)
    if body is None or not substantive(body):
        fail(f"{arch}: section '{name}' is missing or empty")
        continue
    if not mermaid_blocks(body):
        fail(f"{arch}: section '{name}' has no Mermaid diagram")
    for n, line in enumerate(strip_comments(body).splitlines()):
        m = TECH.search(line)
        if m:
            fail(f"{arch}: section '{name}' names a product technology ('{m.group(0)}'); C4 stays technology-agnostic: {line.strip()[:80]}")
            break


def required(heading, diagram=None, allow_na=True, source=None, where=None):
    where = where or arch
    src = source if source is not None else h2
    body = src.get(heading)
    if body is None:
        fail(f"{where}: section '{heading}' is missing (copy it from the architecture.md template)")
        return None
    if allow_na and is_na(body):
        return body
    if not substantive(body):
        fail(f"{where}: section '{heading}' is empty or still a placeholder (write it, or 'N/A: <reason>')")
        return None
    if diagram and not has_block(body, diagram):
        fail(f"{where}: section '{heading}' needs a Mermaid {'/'.join(diagram)} diagram (or 'N/A: <reason>')")
    return body


flow = required("data flow", diagram=["flowchart", "graph"])
container = h2.get("c4 container")
if flow and container and not is_na(flow):
    flow_blocks, c4_blocks = mermaid_blocks(flow), mermaid_blocks(container)
    if flow_blocks and c4_blocks:
        a, b = node_ids(c4_blocks[0]), node_ids(flow_blocks[0])
        if a != b:
            fail(f"{arch}: Data flow nodes differ from C4 Container (only in Data flow: {sorted(b - a)}; only in C4 Container: {sorted(a - b)}); reuse the same node IDs and relabel the edges")

models = split_sections("## Data models\n" + h2.get("data models", ""), 3) if "data models" in h2 else {}
if "data models" not in h2:
    fail(f"{arch}: section 'data models' is missing")
else:
    required("conceptual", source=models)
    required("logical", diagram=["erDiagram"], source=models)
    required("physical", diagram=["erDiagram"], source=models)

required("state machine", diagram=["stateDiagram-v2", "stateDiagram"])
failure = required("failure domains and degradation")
if failure and not is_na(failure):
    _, rows = table_rows(failure)
    if not filled_rows(rows, 4):
        fail(f"{arch}: 'failure domains and degradation' needs at least one dependency row with failure, blast radius, and degraded behaviour filled")
required("mvp and future state", allow_na=False)

# --- network: target topology ------------------------------------------------
net = read(os.path.join(base, "network.md"))
if net is None:
    fail(f"{os.path.join(base, 'network.md')} is missing")
else:
    nh2 = split_sections(net, 2)
    required("target topology", diagram=["flowchart", "graph"], source=nh2, where=os.path.join(base, "network.md"))

# --- design/system files -----------------------------------------------------
def system_file(name):
    path = os.path.join(system, name)
    body = read(path)
    if body is None:
        fail(f"{path} is missing")
    return path, body


path, body = system_file("nfr-slo.md")
if body is not None:
    _, rows = table_rows(body)
    if not filled_rows(rows, 2):
        fail(f"{path} has no filled Surface row")

path, body = system_file("threat-model.md")
if body is not None:
    if not re.search(r"^\s*-\s+\S", split_sections(body, 2).get("assets", ""), re.M):
        fail(f"{path} lists no asset")
    _, rows = table_rows(split_sections(body, 2).get("top risks (stride)", body))
    if not filled_rows(rows, 2):
        fail(f"{path} has no risk row with a mitigation")

path, body = system_file("ops-readiness.md")
if body is not None:
    sections = split_sections(body, 2)
    for heading in ("build and run ownership", "error budget policy"):
        if heading not in sections or not substantive(sections[heading]):
            fail(f"{path}: section '{heading}' is missing or empty")
    db = sections.get("database maintenance and operation")
    if db is None or not (is_na(db) or substantive(db)):
        fail(f"{path}: section 'database maintenance and operation' is empty (fill it, or 'N/A: <reason>')")
    if "production readiness checklist" not in sections:
        fail(f"{path}: section 'production readiness checklist' is missing")

path, body = system_file("arc-record.md")
if body is not None:
    options = split_sections(body, 2).get("options", "")
    adr_paths = re.findall(r"docs/agents-v0/adr/[A-Za-z0-9_./-]+\.md", options)
    adr_ok = False
    for adr in adr_paths:
        adr_text = read(adr)
        if adr_text is None:
            fail(f"{path}: Options names {adr}, which does not exist")
            continue
        adr_ok = True
        status = re.search(r"\*\*Status:\*\*\s*(.+)|^Status:\s*(.+)", adr_text, re.M)
        value = (status.group(1) or status.group(2)).strip() if status else ""
        if approved and not re.match(r"Accepted", value):
            fail(f"{adr}: Status is '{value or '?'}'; the pattern ADR must be Accepted once the architecture row is Approved")
        packs = PACK_LINE.findall(adr_text)
        if not packs:
            fail(f"{adr}: pattern ADR must record Pack: <id>")
        for pack in packs:
            data = packlib.load(pack)
            problems = [] if data is None else packlib.errors_of(data, "backend")
            if data is None:
                fail(f"{adr}: Pack '{pack}' has no manifest; write .agents-v0/packs/{pack}/pack.json before Plan")
            elif problems:
                fail(f"{adr}: Pack '{pack}' manifest is incomplete: {', '.join(problems)}")
            else:
                directory = data["dir"]
                rules = os.path.join(directory, "rules")
                if not os.path.isdir(rules) or not any(name.endswith(".mdc") for name in os.listdir(rules)):
                    fail(f"{adr}: Pack '{pack}' has no rules")
                for skill in ("implement-service", "implement-bff"):
                    if not os.path.isfile(os.path.join(directory, "skills", skill, "SKILL.md")):
                        fail(f"{adr}: Pack '{pack}' has no {skill} skill")
                ui_value = data.get("ui")
                ui = data.get("uiPack")
                if isinstance(ui_value, str):
                    if not ui:
                        fail(f"{adr}: Pack '{pack}' has no UI manifest for '{ui_value}'; write .agents-v0/ui/{ui_value}/pack.json before Plan")
                    else:
                        ui_problems = packlib.errors_of(ui, "ui")
                        if ui_problems:
                            fail(f"{adr}: Pack '{pack}' UI manifest '{ui_value}' is incomplete: {', '.join(ui_problems)}")
                elif isinstance(ui_value, dict):
                    ui_problems = packlib.errors_of(ui_value, "ui")
                    if ui_problems:
                        fail(f"{adr}: Pack '{pack}' inlined UI manifest is incomplete: {', '.join(ui_problems)}")
    if not adr_paths:
        fail(f"{path}: Options must name the pattern ADR under docs/agents-v0/adr/")
    fitness = split_sections(body, 2).get("fitness functions", "")
    header, rows = table_rows(fitness)
    names = " ".join(h.lower() for h in header or [])
    if "threshold" not in names or "check" not in names:
        fail(f"{path}: Fitness functions needs the structural table (Principle | Check | Threshold | On failure)")
    elif not filled_rows(rows, 4):
        fail(f"{path}: Fitness functions has no structural row (a check that names a real rule, or 'planned: <milestone>')")

path, body = system_file("context-map.md")
if body is not None:
    header, rows = table_rows(split_sections(body, 2).get("bounded contexts", ""))
    cols = [h.lower() for h in (header or [])]
    if "component plan" not in cols or "context" not in cols:
        fail(f"{path}: Bounded contexts table needs the Context and Component plan columns (see the context-map template)")
    else:
        ci, pi = cols.index("context"), cols.index("component plan")
        contexts = [r for r in rows if len(r) > max(ci, pi) and r[ci] and not r[ci].startswith("<")]
        if not contexts:
            fail(f"{path} has no bounded context row")
        for r in contexts:
            cell = r[pi]
            if re.match(r"N/A:\s*\S{3,}", cell):
                continue
            plan = re.search(r"docs/agents-v0/design/system/components/[A-Za-z0-9_.-]+\.md", cell)
            if not plan:
                fail(f"{path}: context '{r[ci]}' needs a component plan path under design/system/components/ or 'N/A: <reason>'")
                continue
            plan_text = read(plan.group(0))
            if plan_text is None:
                fail(f"{path}: component plan missing for '{r[ci]}': {plan.group(0)}")
            elif "TEMPLATE:" in plan_text or "<service>" in plan_text:
                fail(f"{plan.group(0)}: still carries template placeholders")
            elif "docs/agents-v0/architecture.md" not in plan_text:
                fail(f"{plan.group(0)}: must link its parent docs/agents-v0/architecture.md")
            elif approved:
                def is_sealed_component_plan(arch_path, comp_path):
                    if os.environ.get("KIT_STRICT_COMPONENT_PLAN") == "1":
                        return False
                    arch_txt = read(arch_path) or ""
                    m_rows = re.findall(r"(?im)^\s*\|\s*architecture\s*\|[^|]*\|[^|]*\|\s*([^|]+?)\s*\|", arch_txt)
                    if not m_rows or not re.match(r"^(approved|approve|yes|pass)(\b|[^a-z])", m_rows[-1].strip(), re.I):
                        return False
                    import subprocess
                    for p in (arch_path, comp_path):
                        try:
                            if subprocess.run(["git", "ls-files", "--error-unmatch", "--", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
                                return False
                            st = subprocess.run(["git", "status", "--porcelain", "--", p], capture_output=True, text=True)
                            if st.returncode != 0 or st.stdout.strip():
                                return False
                        except Exception:
                            return False
                    return True

                comp_issues = []
                if re.search(r"\(\s*Proposed\s*\)", plan_text, re.I):
                    comp_issues.append(f"{plan.group(0)}: still labels an ADR '(Proposed)' after architecture approval (update to Accepted)")
                cc_sec = split_sections(plan_text, 2).get("consistency check", "")
                if re.search(r"^\s*-\s*\[\s\]", cc_sec, re.M):
                    comp_issues.append(f"{plan.group(0)}: '## Consistency check' has unchecked items ('- [ ]') on an approved architecture pack")
                if comp_issues:
                    if is_sealed_component_plan(arch, plan.group(0)):
                        for msg in comp_issues:
                            sys.stderr.write(f"WARN: {msg} (tolerated for Approved architecture pack committed in git; editing or re-opening enforces strict check)\n")
                    else:
                        for msg in comp_issues:
                            fail(msg)

# --- independent review ------------------------------------------------------
if not without_review:
    path = os.path.join(system, "architecture-review.md")
    body = read(path)
    if body is None:
        fail(f"{path} is missing: run design-reviewer on the pack before the architecture approval")
    else:
        if not re.search(r"^agent:\s*design-reviewer\s*$", body, re.M):
            fail(f"{path}: first lines must say 'agent: design-reviewer'")
        for line in body.splitlines():
            if re.search(r"\|\s*Critical\s*\|", line, re.I) and not re.search(r"\bResolved\b", line, re.I):
                fail(f"{path} has an unresolved Critical finding: {line.strip()[:100]}")

if failures:
    for message in failures:
        sys.stderr.write(f"FAIL: {message}\n")
    sys.exit(1)
print(f"OK: architecture pack complete for {arch}")
PY
