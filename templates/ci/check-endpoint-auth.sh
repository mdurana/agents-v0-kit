#!/bin/sh
# check-endpoint-auth.sh — a new Spring endpoint is explicitly authorized or explicitly public.
#
# Usage:
#   sh ci/check-endpoint-auth.sh <base> [<head>]   fail on a mapping the change adds without a security annotation
#   sh ci/check-endpoint-auth.sh --list [<root>...]  print every mapping: file:line  VERB /path  annotated|NO-ANNOTATION
#
# A mapping counts as annotated when its own annotations, or its controller class, carry
# @PreAuthorize, @PostAuthorize, @Secured, @RolesAllowed, @PermitAll, or @DenyAll. A deliberately
# public endpoint says so with @PermitAll. Authorization enforced only in configuration
# (SecurityFilterChain matchers) is not seen here: add the annotation, or keep the rule in code
# review. The same scan feeds scripts/discover-codebase.sh (keep the two in step).
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


if args[0] == "--list":
    roots = args[1:] or ["."]
    for root in roots:
        for dirpath, dirs, names in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in SKIP)
            for name in sorted(names):
                if name.endswith(".java"):
                    path = os.path.normpath(os.path.join(dirpath, name))
                    for line_no, verb, full, ok in endpoints(read_lines(path)):
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
for path in [p for p in out.splitlines() if p.endswith(".java")]:
    if head:
        _c, text = git("show", f"{head}:{path}")
    else:
        text = "\n".join(read_lines(path))
    c2, old = git("show", f"{base}:{path}")
    before = {(v, p) for _n, v, p, _ok in endpoints(old.splitlines())} if c2 == 0 else set()
    for line_no, verb, full, ok in endpoints(text.splitlines()):
        checked += 1
        if not ok and (verb, full) not in before:
            failures.append(f"{path}:{line_no}  {verb} {full} has no security annotation "
                            f"(@PreAuthorize/@Secured/@RolesAllowed, or @PermitAll when it is public on purpose)")
if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: no new unannotated endpoint ({checked} mapping(s) in changed controllers)")
PY
