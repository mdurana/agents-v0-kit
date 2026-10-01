#!/bin/sh
# check-endpoint-auth.sh — a new endpoint is explicitly authorized or explicitly public.
#
# Usage:
#   sh ci/check-endpoint-auth.sh <base> [<head>]   fail on a mapping the change adds without a security annotation
#   sh ci/check-endpoint-auth.sh --list [<root>...]  print every mapping: file:line  VERB /path  annotated|NO-ANNOTATION
#
# Spring (*.java) is built in: a mapping counts as annotated when its own annotations, or its
# controller class, carry @PreAuthorize, @PostAuthorize, @Secured, @RolesAllowed, @PermitAll, or
# @DenyAll. A deliberately public endpoint says so with @PermitAll. Authorization enforced only in
# configuration (SecurityFilterChain matchers) is not seen here.
# Other stacks: add a row under "## Endpoint authorization" in docs/project-profile.md
# (Stack, Suffix, Marker, Mapping, Security). Spring stays the built-in scanner; those rows add
# file types. The Spring scan feeds scripts/discover-codebase.sh (keep the two in step).
# <head> omitted compares <base> with the working tree.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }
[ $# -ge 1 ] || { printf 'usage: %s <base> [<head>] | --list [<root>...]\n' "$0" >&2; exit 1; }

ARGS="$(printf '%s\n' "$@")" python3 - <<'PY'
import os
import re
import subprocess
import sys

args = os.environ["ARGS"].splitlines()
MAPPING = re.compile(r"@(Get|Post|Put|Patch|Delete|Request)Mapping\b(.*)")
QUOTED = re.compile(r'"([^"]*)"')
SECURITY = re.compile(r"@(PreAuthorize|PostAuthorize|Secured|RolesAllowed|PermitAll|DenyAll)\b")
CLASS_DECL = re.compile(r"\b(class|interface)\s+\w+")
SKIP = {"node_modules", "target", ".git", "dist", "build", ".svelte-kit", ".next", "docs", ".cursor", ".claude", ".kilo"}


def endpoints(lines):
    """Yield (line_number, verb, path, annotated) for each mapping in one controller file."""
    if not any(re.search(r"@(RestController|Controller)\b", ln) for ln in lines):
        return
    decl = next((i for i, ln in enumerate(lines)
                 if CLASS_DECL.search(ln) and not ln.lstrip().startswith(("*", "//", "/*"))), None)
    if decl is None:
        return
    header = lines[max(0, decl - 12): decl + 1]
    class_secured = any(SECURITY.search(ln) for ln in header)
    base = ""
    for ln in header:
        m = MAPPING.search(ln)
        if m and m.group(1) == "Request":
            q = QUOTED.search(m.group(2))
            base = q.group(1) if q else ""
    for i in range(decl + 1, len(lines)):
        m = MAPPING.search(lines[i])
        if not m:
            continue
        q = QUOTED.search(m.group(2))
        sub = q.group(1) if q else ""
        full = "/" + "/".join(p.strip("/") for p in (base, sub) if p.strip("/"))
        top = i
        while top - 1 > decl and not re.search(r"[;{}]\s*$", lines[top - 1].strip()):
            top -= 1
        bottom = i
        while bottom < len(lines) - 1 and bottom - i < 8 and not re.search(r"[{};]\s*$", lines[bottom].strip()):
            bottom += 1
        secured = class_secured or any(SECURITY.search(ln) for ln in lines[top: bottom + 1])
        verb = "ANY" if m.group(1) == "Request" else m.group(1).upper()
        yield i + 1, verb, full, secured


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read().splitlines()
    except OSError:
        return []


def git(*a):
    proc = subprocess.run(["git", *a], capture_output=True, text=True)
    return proc.returncode, proc.stdout


def profile_stacks():
    """Extra stacks from docs/project-profile.md. Spring stays built in."""
    path = "docs/project-profile.md"
    if not os.path.isfile(path):
        return []
    text = open(path, encoding="utf-8", errors="replace").read()
    heading = "## Endpoint authorization"
    if heading not in text:
        return []
    section = text.split(heading, 1)[1].split("\n## ", 1)[0]
    stacks = []
    for line in section.splitlines():
        if not line.startswith("|"):
            continue
        # Split on " | " so a regex may contain "|" (for example get|post).
        cells = [c.strip().strip("`") for c in line.strip().strip("|").split(" | ")]
        if len(cells) < 5:
            continue
        stack, suffix, marker_re, mapping, security = cells[:5]
        low = stack.lower()
        if low in ("stack", "") or set(stack) <= set("-: "):
            continue
        if low == "spring" or mapping in ("", "(built-in)"):
            continue
        if not suffix.startswith("."):
            continue
        if marker_re in ("", "—", "-", "(any)"):
            marker_re = ""
        stacks.append((suffix, marker_re, mapping, security, stack))
    return stacks


STACKS = profile_stacks()


def extra_endpoints(lines, spec):
    _suffix, marker_re, mapping, security, _stack = spec
    blob = "\n".join(lines)
    if marker_re:
        try:
            if not re.search(marker_re, blob):
                return
        except re.error:
            return
    try:
        mapping_re = re.compile(mapping)
        security_re = re.compile(security)
    except re.error:
        return
    file_secured = any(security_re.search(ln) for ln in lines[:40])
    for i, ln in enumerate(lines):
        match = mapping_re.search(ln)
        if not match:
            continue
        window = lines[max(0, i - 12): i + 9]
        ok = file_secured or any(security_re.search(w) for w in window)
        verb = match.group(1).upper() if match.lastindex and match.group(1) else "ANY"
        route = match.group(2) if match.lastindex and match.lastindex >= 2 and match.group(2) else match.group(0)
        yield i + 1, verb, route.strip(" '\"")[:120], ok


def scan_file(path, lines):
    if path.endswith(".java"):
        yield from endpoints(lines)
    for spec in STACKS:
        if path.endswith(spec[0]):
            yield from extra_endpoints(lines, spec)


def watched(path):
    if path.endswith(".java"):
        return True
    return any(path.endswith(spec[0]) for spec in STACKS)


if args[0] == "--list":
    roots = args[1:] or ["."]
    for root in roots:
        for dirpath, dirs, names in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in SKIP)
            for name in sorted(names):
                path = os.path.normpath(os.path.join(dirpath, name))
                if not watched(path):
                    continue
                for line_no, verb, full, ok in scan_file(path, read_lines(path)):
                    print(f"{path}:{line_no}  {verb} {full}  {'annotated' if ok else 'NO-ANNOTATION'}")
    raise SystemExit(0)

base = args[0]
head = args[1] if len(args) > 1 else ""
span = [base, head] if head else [base]
code, out = git("diff", "--name-only", "--diff-filter=AM", *span)
if code != 0:
    print(f"FAIL: git diff {' '.join(span)} failed", file=sys.stderr)
    raise SystemExit(1)
failures, checked = [], 0
for path in [p for p in out.splitlines() if watched(p)]:
    if head:
        _c, text = git("show", f"{head}:{path}")
    else:
        text = "\n".join(read_lines(path))
    c2, old = git("show", f"{base}:{path}")
    before = {(v, p) for _n, v, p, _ok in scan_file(path, old.splitlines())} if c2 == 0 else set()
    hint = ("(@PreAuthorize/@Secured/@RolesAllowed, or @PermitAll when it is public on purpose)"
            if path.endswith(".java") else "(docs/project-profile.md Endpoint authorization)")
    for line_no, verb, full, ok in scan_file(path, text.splitlines()):
        checked += 1
        if not ok and (verb, full) not in before:
            failures.append(f"{path}:{line_no}  {verb} {full} has no security annotation {hint}")
if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: no new unannotated endpoint ({checked} mapping(s) in changed controllers)")
PY
