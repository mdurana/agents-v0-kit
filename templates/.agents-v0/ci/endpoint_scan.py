"""Shared endpoint scanners for check-endpoint-auth.sh and discover-codebase.sh.

One table defines every non-Java pack. Discovery proposes profile rows from this
table, and the auth check scans with the same marker, mapping, and security
regexes. Do not copy the table into either script.
"""

import os
import re
import subprocess
import sys

MAPPING = re.compile(r"@(Get|Post|Put|Patch|Delete|Request)Mapping\b(.*)")
QUOTED = re.compile(r'"([^"]*)"')
SECURITY = re.compile(r"@(PreAuthorize|PostAuthorize|Secured|RolesAllowed|PermitAll|DenyAll)\b")
CLASS_DECL = re.compile(r"\b(class|interface)\s+\w+")
PACKS = {"java", "dotnet", "node", "python", "go"}
SKIP = {
    "node_modules", "target", ".git", "dist", "build", ".svelte-kit", ".next",
    "docs", ".cursor", ".claude", ".kilo",
}

# suffix, marker, mapping, security, name.
# Mapping group 1 is the verb and group 2 the path, unless the regex has a single group (the path).
BUILTINS = {
    "dotnet": [
        (".cs", r"\[Http(Get|Post|Put|Patch|Delete)",
         r"\[Http(Get|Post|Put|Patch|Delete)(?:\(\s*\"([^\"]*)\"\))?",
         r"\[Authorize|\[AllowAnonymous\]", "dotnet"),
    ],
    "node": [
        (".ts", r"@(Get|Post|Put|Patch|Delete)\(",
         r"@(Get|Post|Put|Patch|Delete)\(\s*[\"']?([^\"')]*)",
         r"@UseGuards|@Public", "nest"),
        (".ts", r"express\(|Router\(",
         r"\b(?:app|router)\.(get|post|put|patch|delete)\(\s*[\"']([^\"']+)",
         r"requireAuth|authenticate|authorize|publicRoute", "express"),
        (".js", r"express\(|Router\(",
         r"\b(?:app|router)\.(get|post|put|patch|delete)\(\s*[\"']([^\"']+)",
         r"requireAuth|authenticate|authorize|publicRoute", "express"),
    ],
    "python": [
        (".py", r"APIRouter|FastAPI\(",
         r"@(?:router)\.(get|post|put|patch|delete)\(\s*[\"']([^\"']+)",
         r"Depends\(|require_role", "fastapi"),
        (".py", r"urlpatterns",
         r"\bpath\(\s*[\"']([^\"']+)",
         r"login_required|permission_classes|IsAuthenticated", "django"),
    ],
    "go": [
        (".go", r"gin\.|chi\.NewRouter",
         r"\.(GET|POST|PUT|PATCH|DELETE)\(\s*\"([^\"]+)\"",
         r"Auth|middleware", "go"),
        (".go", r"http\.HandleFunc",
         r"http\.HandleFunc\(\s*\"([^\"]+)\"",
         r"Auth|middleware", "go-stdlib"),
    ],
}


def java_endpoints(lines):
    """Yield (line_number, verb, path, annotated) for each Spring mapping in one file."""
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
        match = MAPPING.search(ln)
        if match and match.group(1) == "Request":
            quoted = QUOTED.search(match.group(2))
            base = quoted.group(1) if quoted else ""
    for i in range(decl + 1, len(lines)):
        match = MAPPING.search(lines[i])
        if not match:
            continue
        quoted = QUOTED.search(match.group(2))
        sub = quoted.group(1) if quoted else ""
        full = "/" + "/".join(p.strip("/") for p in (base, sub) if p.strip("/"))
        top = i
        while top - 1 > decl and not re.search(r"[;{}]\s*$", lines[top - 1].strip()):
            top -= 1
        bottom = i
        while bottom < len(lines) - 1 and bottom - i < 8 and not re.search(r"[{};]\s*$", lines[bottom].strip()):
            bottom += 1
        secured = class_secured or any(SECURITY.search(ln) for ln in lines[top: bottom + 1])
        verb = "ANY" if match.group(1) == "Request" else match.group(1).upper()
        yield i + 1, verb, full, secured


def profile_pack(profile="docs/agents-v0/project-profile.md"):
    """Pack row under ## Stack. Missing or blank stays java so existing repos keep that scanner."""
    if not os.path.isfile(profile):
        return "java"
    text = open(profile, encoding="utf-8", errors="replace").read()
    if "## Stack" not in text:
        return "java"
    body = text.split("## Stack", 1)[1].split("\n## ", 1)[0]
    for line in body.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells and cells[0] == "Pack" and len(cells) > 1 and cells[1] in PACKS:
            return cells[1]
    return "java"


def _builtin_covers(pack, suffix, mapping):
    for spec in BUILTINS.get(pack, []):
        if spec[0] == suffix and spec[2] == mapping:
            return True
    return False


def profile_stacks(profile="docs/agents-v0/project-profile.md"):
    """Extra stacks from the profile. Rows the active pack already scans are skipped."""
    if not os.path.isfile(profile):
        return []
    text = open(profile, encoding="utf-8", errors="replace").read()
    heading = "## Endpoint authorization"
    if heading not in text:
        return []
    section = text.split(heading, 1)[1].split("\n## ", 1)[0]
    pack = profile_pack(profile)
    stacks = []
    for line in section.splitlines():
        if not line.startswith("|"):
            continue
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
        if _builtin_covers(pack, suffix, mapping):
            continue
        if marker_re in ("", "—", "-", "(any)"):
            marker_re = ""
        stacks.append((suffix, marker_re, mapping, security, stack))
    return stacks


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
    verbs = {"get", "post", "put", "patch", "delete"}
    for i, ln in enumerate(lines):
        match = mapping_re.search(ln)
        if not match:
            continue
        window = lines[max(0, i - 12): i + 9]
        ok = file_secured or any(security_re.search(w) for w in window)
        if match.lastindex and match.lastindex >= 2 and match.group(1):
            verb = match.group(1).upper()
            route = match.group(2) or ""
        elif match.lastindex == 1 and match.group(1):
            token = match.group(1)
            if token.lower() in verbs:
                verb, route = token.upper(), ""
            else:
                verb, route = "ANY", token
        else:
            verb, route = "ANY", match.group(0)
        yield i + 1, verb, route.strip(" '\"")[:120], ok


def scan_lines(path, lines, pack=None, stacks=None):
    pack = profile_pack() if pack is None else pack
    stacks = profile_stacks() if stacks is None else stacks
    if pack == "java" and path.endswith(".java"):
        yield from java_endpoints(lines)
    for spec in BUILTINS.get(pack, []):
        if path.endswith(spec[0]):
            yield from extra_endpoints(lines, spec)
    for spec in stacks:
        if path.endswith(spec[0]):
            yield from extra_endpoints(lines, spec)


def watched(path, pack=None, stacks=None):
    pack = profile_pack() if pack is None else pack
    stacks = profile_stacks() if stacks is None else stacks
    if pack == "java" and path.endswith(".java"):
        return True
    if any(path.endswith(spec[0]) for spec in BUILTINS.get(pack, [])):
        return True
    return any(path.endswith(spec[0]) for spec in stacks)


def proposal_hits(files, read_text):
    """First file that matches each builtin scanner. Same regexes the auth check uses."""
    seen = {}
    for path in files:
        try:
            blob = read_text(path)[:8000]
        except OSError:
            continue
        for specs in BUILTINS.values():
            for suffix, marker, mapping, security, name in specs:
                if name in seen or not path.endswith(suffix):
                    continue
                if re.search(marker, blob):
                    seen[name] = (suffix, marker, mapping, security, path.replace(os.sep, "/"))
    return seen


def _read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read().splitlines()
    except OSError:
        return []


def _git(*args):
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    return proc.returncode, proc.stdout


def main(args):
    if not args:
        print("usage: check-endpoint-auth.sh <base> [<head>] | --list [<root>...]", flush=True)
        return 1
    pack = profile_pack()
    stacks = profile_stacks()
    if args[0] == "--list":
        roots = args[1:] or ["."]
        for root in roots:
            for dirpath, dirs, names in os.walk(root):
                dirs[:] = sorted(d for d in dirs if d not in SKIP)
                for name in sorted(names):
                    path = os.path.normpath(os.path.join(dirpath, name))
                    if not watched(path, pack, stacks):
                        continue
                    for line_no, verb, full, ok in scan_lines(path, _read_lines(path), pack, stacks):
                        print(f"{path}:{line_no}  {verb} {full}  {'annotated' if ok else 'NO-ANNOTATION'}")
        return 0

    base = args[0]
    head = args[1] if len(args) > 1 else ""
    span = [base, head] if head else [base]
    code, out = _git("diff", "--name-only", "--diff-filter=AM", *span)
    if code != 0:
        print(f"FAIL: git diff {' '.join(span)} failed", file=sys.stderr)
        return 1
    failures, checked = [], 0
    for path in [p for p in out.splitlines() if watched(p, pack, stacks)]:
        if head:
            _code, text = _git("show", f"{head}:{path}")
        else:
            text = "\n".join(_read_lines(path))
        code_old, old = _git("show", f"{base}:{path}")
        before = {(v, p) for _n, v, p, _ok in scan_lines(path, old.splitlines(), pack, stacks)} if code_old == 0 else set()
        if path.endswith(".java"):
            hint = "(@PreAuthorize/@Secured/@RolesAllowed, or @PermitAll when it is public on purpose)"
        else:
            hint = "(the active pack scanner, or an Endpoint authorization row)"
        for line_no, verb, full, ok in scan_lines(path, text.splitlines(), pack, stacks):
            checked += 1
            if not ok and (verb, full) not in before:
                failures.append(f"{path}:{line_no}  {verb} {full} has no security annotation {hint}")
    if failures:
        for item in failures:
            print(f"FAIL: {item}", file=sys.stderr)
        return 1
    print(f"OK: no new unannotated endpoint ({checked} mapping(s) in changed controllers)")
    return 0
