#!/bin/sh
# check-traceability.sh — cheap, deterministic gate-to-gate consistency checks (kitfix-20261031-traceability).
# Each check parses ids from the artifacts the earlier gates approved and says which phase it blames.
#
# Usage: sh .agents-v0/scripts/check-traceability.sh <design|build|verify> docs/agents-v0/requirements/<feature>.md
#   design  T1 every `### AC-<n>` of the requirements appears in design.md (Traceability)   blames design
#           T2 the AC count matches the milestone plan's Size cell (unless `## Proposed split` or a
#              `Plan deviation:` line is recorded)                                         blames intake
#           T3 design.md names no AC id the requirements do not have                       blames design
#   build   T4 every operationId / path of docs/agents-v0/design/<feature>/openapi.yaml has code under
#              app/ (operationId, path literal, or the path's static segments in one source file)  blames build
#           T5 ... and at least one test file that names the operationId or calls the path     blames build
#   verify  T6 every AC has a passing row in docs/agents-v0/verify/<feature>/quality-gate.md (a line naming
#              AC-<n> with PASS / passed / ok / ✅ and no FAIL). When it has none, the blame is the earliest
#              phase where the AC is lost: design (not in design.md), build (no test names it), else verify.
# Every failure prints one line:
#   TRACE <WARN|FAIL> <check> gate=<gate> earliest_bad_phase=<phase> artifact=<file>: <detail>
# and the result is written to docs/agents-v0/requirements/<feature>.trace.json (committed with the gate),
# which the e2e harness reads to choose its rollback gate.
# AGENTS_V0_TRACE_NO_WRITE=1 prints only (the e2e harness re-runs a failed phase's checks this way).
# Mode: AGENTS_V0_TRACE_MODE=warn (default, D8: warn first; exit 0) or fail (exit 1 on any failure).
# P0-A: design checks are skipped (no design gate); build/verify checks run when their inputs exist.
set -eu
gate="${1:-}"; art="${2:-}"
case "$gate" in design|build|verify) ;; *) printf 'usage: %s <design|build|verify> <requirements artifact>\n' "$0" >&2; exit 2 ;; esac
[ -n "$art" ] && [ -f "$art" ] || { printf 'usage: %s <design|build|verify> <requirements artifact>\n' "$0" >&2; exit 2; }

TR_GATE="$gate" TR_ART="$art" python3 - <<'PYTR'
import json, os, re, sys
gate, art = os.environ["TR_GATE"], os.environ["TR_ART"].replace("\\", "/")
mode = os.environ.get("AGENTS_V0_TRACE_MODE", "warn").lower()
slug = os.path.basename(art)[:-3]
m = re.match(r"(.*?)docs/agents-v0/requirements/", art)
root = m.group(1) if m else ""
P = lambda *a: os.path.join(root, *a)
def read(p):
    try: return re.sub(r"<!--.*?-->", "", open(p, encoding="utf-8").read(), flags=re.S)
    except OSError: return None
req = read(art) or ""
p0a = slug.startswith("p0-a") or bool(re.search(r"^\s*(\*\*)?Story(\*\*)?:\s*(\*\*)?P0-A([^A-Za-z0-9]|$)", req, re.M | re.I))
acs = sorted(set(int(n) for n in re.findall(r"^###\s+AC-(\d+)\b", req, re.M)))
acid = lambda n: f"AC-{n}"
design_p = f"docs/agents-v0/design/{slug}/design.md"; design = read(P(design_p))
fails = []
def fail(check, bad, artifact, detail):
    fails.append({"check": check, "gate": gate, "earliest_bad_phase": bad, "artifact": artifact, "detail": detail})
def mentions(text, n):
    return bool(re.search(rf"\bAC-{n}(?!\d)", text or ""))

def planned_size():
    mdir = P("docs/agents-v0/milestones")
    if not os.path.isdir(mdir): return None, None
    for f in sorted(os.listdir(mdir)):
        if not f.endswith(".md") or f.startswith("_") or f == "plan.md": continue
        hdr = None
        for line in open(os.path.join(mdir, f), encoding="utf-8"):
            s = line.strip()
            if not s.startswith("|"): hdr = None; continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            low = [c.lower() for c in cells]
            if "story id" in low and "size" in low: hdr = low; continue
            if hdr and f"requirements/{slug}.md" in s:
                size = dict(zip(hdr, cells)).get("size", "")
                return (int(size) if size.isdigit() else None), f"docs/agents-v0/milestones/{f}"
    return None, None

if gate == "design" and not p0a:
    if design is None:
        fail("T1-design-covers-acs", "design", design_p, "design.md is missing")
    else:
        miss = [acid(n) for n in acs if not mentions(design, n)]
        if miss: fail("T1-design-covers-acs", "design", design_p, "not traced in design.md: " + ", ".join(miss))
        extra = sorted(set(int(n) for n in re.findall(r"\bAC-(\d+)(?!\d)", design)) - set(acs))
        if extra: fail("T3-design-no-unknown-acs", "design", design_p, "AC ids not in the requirements: " + ", ".join(acid(n) for n in extra))
    size, manifest = planned_size()
    if size is not None and size != len(acs) and not re.search(r"^## Proposed split|Plan deviation:", req, re.M):
        fail("T2-ac-count-vs-plan", "intake", art, f"{len(acs)} ACs written, {manifest} Size says {size}")

SRC_SKIP = {"node_modules", "target", "dist", "build", ".git", "coverage"}
def sources():
    out = []
    base = P("app")
    for d, dirs, files in os.walk(base):
        dirs[:] = [x for x in dirs if x not in SRC_SKIP]
        for f in files:
            if f.endswith((".java", ".kt", ".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".cs")):
                p = os.path.join(d, f)
                is_test = bool(re.search(r"(/src/test/|/__tests__/|/tests?/|\.test\.|\.spec\.|Tests?\.\w+$|IT\.\w+$)", p.replace("\\", "/")))
                try: out.append((p, is_test, open(p, encoding="utf-8", errors="replace").read()))
                except OSError: pass
    return out

if gate == "build":
    spec_p = f"docs/agents-v0/design/{slug}/openapi.yaml"; spec = read(P(spec_p))
    if spec:
        ops, path, in_paths = [], None, False
        for line in spec.splitlines():
            if re.match(r"^paths:\s*$", line): in_paths = True; continue
            if in_paths and re.match(r"^\S", line): in_paths = False
            mp = re.match(r"^  (/[^:\s]*):\s*$", line) if in_paths else None
            if mp: path = mp.group(1); continue
            mo = re.match(r"^\s+operationId:\s*['\"]?([A-Za-z0-9_]+)", line)
            if mo and path: ops.append((mo.group(1), path))
        src = sources()
        for op, path in ops:
            pre = re.sub(r"^/api/v\d+", "", path)
            rx = re.compile("".join("[^/\"'`\\s?]+" if seg.startswith("{") else re.escape(seg) for seg in re.split(r"(\{[^}]*\})", path)))
            statics = [s for s in path.split("/") if s and not s.startswith("{") and not re.fullmatch(r"api|v\d+", s)]
            def code_hit(text):
                return (re.search(rf"\b{re.escape(op)}\b", text) or path in text or (pre and pre != path and pre in text)
                        or (statics and all(f'"/{s}' in text or f"/{s}\"" in text or f"/{s}/" in text for s in statics)
                            and ("{" not in path or re.search(r'"[^"\n]*\{[^}"\n]+\}[^"\n]*"', text))))
            if not any(code_hit(t) for p, is_test, t in src if not is_test):
                fail("T4-endpoint-has-code", "build", spec_p, f"{op} ({path}) has no code under app/")
            elif not any(re.search(rf"\b{re.escape(op)}\b", t) or rx.search(t) for p, is_test, t in src if is_test):
                fail("T5-endpoint-has-test", "build", spec_p, f"{op} ({path}) has no test that names it or calls the path")

if gate == "verify":
    qg_p = f"docs/agents-v0/verify/{slug}/quality-gate.md"; qg = read(P(qg_p))
    tests = None
    for n in acs:
        lines = [l for l in (qg or "").splitlines() if mentions(l, n)]
        ok = any(re.search(r"\b(PASS(ED)?|ok)\b|✅", l, re.I) and not re.search(r"\bFAIL(ED)?\b|❌", l, re.I) for l in lines)
        if ok: continue
        if not p0a and design is not None and not mentions(design, n):
            bad = "design"
        else:
            if tests is None: tests = [t for p, is_test, t in sources() if is_test]
            bad = "build" if not any(mentions(t, n) for t in tests) else "verify"
        fail("T6-ac-has-passing-test", bad, qg_p, f"{acid(n)} has no passing row in quality-gate.md")

level = "FAIL" if mode == "fail" else "WARN"
for f in fails:
    print(f"TRACE {level} {f['check']} gate={gate} earliest_bad_phase={f['earliest_bad_phase']} artifact={f['artifact']}: {f['detail']}")
order = ["intake", "design", "build", "verify", "release"]
earliest = min((f["earliest_bad_phase"] for f in fails), key=order.index) if fails else None
tp = re.sub(r"\.md$", ".trace.json", art)
try: data = json.load(open(tp, encoding="utf-8"))
except (OSError, ValueError): data = {}
data[gate] = {"result": ("fail" if mode == "fail" else "warn") if fails else "ok", "mode": mode,
              "earliestBadPhase": earliest, "failures": fails, "acCount": len(acs)}
if os.environ.get("AGENTS_V0_TRACE_NO_WRITE", "0") != "1":
    with open(tp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2); fh.write("\n")
if not fails:
    print(f"TRACE OK gate={gate} {slug}: {len(acs)} ACs")
elif mode == "fail":
    print(f"TRACE: {len(fails)} check(s) failed; earliest bad phase: {earliest}. Fix that phase's artifact, or reopen it.", file=sys.stderr)
    sys.exit(1)
else:
    print(f"TRACE: {len(fails)} warning(s); earliest bad phase: {earliest} (AGENTS_V0_TRACE_MODE=warn; report them at the gate)")
PYTR
