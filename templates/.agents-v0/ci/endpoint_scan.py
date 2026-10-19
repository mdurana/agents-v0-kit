"""Shared endpoint scanners for check-endpoint-auth.sh and discover-codebase.sh.

Scanners come from the active pack's pack.json. Discovery proposes profile rows
from every pack manifest it can see. Do not copy those regexes into either script.
"""

import os
import re
import subprocess
import sys

import packlib

MAPPING = re.compile(r"@(Get|Post|Put|Patch|Delete|Request)Mapping\b(.*)")
QUOTED = re.compile(r'"([^"]*)"')
SECURITY = re.compile(r"@(PreAuthorize|PostAuthorize|Secured|RolesAllowed|PermitAll|DenyAll)\b")
CLASS_DECL = re.compile(r"\b(class|interface)\s+\w+")
SKIP = {
    "node_modules", "target", ".git", "dist", "build", ".svelte-kit", ".next",
    "docs", ".cursor", ".claude", ".kilo",
}

def _spec_tuple(spec, pack_id):
    """(suffix, marker, mapping, security, name) for the generic scanner."""
    return (
        spec.get("suffix") or "",
        spec.get("marker") or "",
        spec.get("mapping") or "",
        spec.get("security") or "",
        spec.get("name") or pack_id,
    )


def pack_endpoints(pack_id):
    data = packlib.load(pack_id) if pack_id else None
    if not data:
        return []
    return [spec for spec in data.get("endpoints") or [] if isinstance(spec, dict)]


def all_endpoint_specs():
    specs = []
    for data in packlib.all_manifests():
        for spec in data.get("endpoints") or []:
            if isinstance(spec, dict) and spec.get("parser") != "spring":
                specs.append(_spec_tuple(spec, data["id"]))
    return specs


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
    """Pack row under ## Stack. A placeholder or a blank cell is empty."""
    return packlib.profile_pack(profile)


def _builtin_covers(pack, suffix, mapping):
    for spec in pack_endpoints(pack):
        if spec.get("parser") == "spring":
            continue
        if spec.get("suffix") == suffix and spec.get("mapping") == mapping:
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


def _dotnet_class_context(lines):
    """Return (decl_idx, class_route, controller_name) for a C# controller file."""
    decl = next(
        (i for i, ln in enumerate(lines)
         if CLASS_DECL.search(ln) and not ln.lstrip().startswith(("*", "//", "/*"))),
        None,
    )
    if decl is None:
        return None, "", ""
    m_cls = re.search(r"\bclass\s+(\w+)", lines[decl])
    cls_name = m_cls.group(1) if m_cls else ""
    ctrl = re.sub(r"Controller$", "", cls_name, flags=re.I) if cls_name else ""
    header = lines[max(0, decl - 12): decl + 1]
    base = ""
    for ln in header:
        m_rt = re.search(r'\[Route\(\s*"([^"]*)"\s*\)\]', ln)
        if m_rt:
            base = m_rt.group(1)
    return decl, base, ctrl


def _nest_class_base(lines):
    decl = next(
        (i for i, ln in enumerate(lines)
         if CLASS_DECL.search(ln) and not ln.lstrip().startswith(("*", "//", "/*"))),
        None,
    )
    if decl is None:
        return ""
    for ln in lines[max(0, decl - 12): decl + 1]:
        m_ct = re.search(r'@Controller\(\s*["\']([^"\']*)["\']', ln)
        if m_ct:
            return m_ct.group(1)
    return ""


def _resolve_dotnet_route(class_route, sub_route, ctrl_name, action_name):
    sub = (sub_route or "").strip()
    if sub.startswith("/") or sub.startswith("~/"):
        raw = sub.lstrip("~")
    else:
        parts = [p.strip("/") for p in (class_route, sub) if p and p.strip("/")]
        raw = "/" + "/".join(parts) if parts else "/"
    if ctrl_name:
        raw = re.sub(r"\[controller\]", ctrl_name.lower(), raw, flags=re.I)
    if action_name:
        raw = re.sub(r"\[action\]", action_name.lower(), raw, flags=re.I)
    return raw


def extra_endpoints(lines, spec):
    suffix, marker_re, mapping, security, stack = spec
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
    is_cs_mvc = suffix == ".cs" and "Http(" in mapping
    cs_decl, cs_base, cs_ctrl = _dotnet_class_context(lines) if is_cs_mvc else (None, "", "")
    nest_base = _nest_class_base(lines) if (suffix == ".ts" and stack == "nest") else ""
    if is_cs_mvc and cs_decl is not None:
        file_secured = any(security_re.search(ln) for ln in lines[max(0, cs_decl - 12): cs_decl + 1])
    else:
        file_secured = any(security_re.search(ln) for ln in lines[:40])
    verbs = {"get", "post", "put", "patch", "delete"}
    for i, ln in enumerate(lines):
        match = mapping_re.search(ln)
        if not match:
            continue
        if is_cs_mvc and cs_decl is not None:
            top = i
            while top - 1 > cs_decl and not re.search(r"[;{}]\s*$", lines[top - 1].strip()):
                top -= 1
            bottom = i
            while bottom < len(lines) - 1 and bottom - i < 8 and not re.search(r"[{};]\s*$", lines[bottom].strip()):
                bottom += 1
            window = lines[top: bottom + 1]
        else:
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
        route = route.strip(" '\"")
        if is_cs_mvc:
            sub_rt = route
            for w in window:
                m_rt = re.search(r'\[Route\(\s*"([^"]*)"\s*\)\]', w)
                if m_rt and not sub_rt:
                    sub_rt = m_rt.group(1)
            act_name = ""
            for w in lines[i: min(len(lines), i + 10)]:
                m_act = re.search(r"\b(?:public|protected|internal)\s+(?:async\s+)?(?:Task<[^>]+>|Task|IActionResult|ActionResult<[^>]+>|ActionResult|\w+)\s+(\w+)\s*\(", w)
                if m_act:
                    act_name = re.sub(r"Async$", "", m_act.group(1))
                    break
            route = _resolve_dotnet_route(cs_base, sub_rt, cs_ctrl, act_name)
        elif nest_base:
            parts = [p.strip("/") for p in (nest_base, route) if p and p.strip("/")]
            route = "/" + "/".join(parts) if parts else "/"
        yield i + 1, verb, route[:120], ok


def _scan_pack(path, lines, pack):
    for spec in pack_endpoints(pack):
        suffix = spec.get("suffix") or ""
        if not suffix or not path.endswith(suffix):
            continue
        if spec.get("parser") == "spring":
            yield from java_endpoints(lines)
        else:
            yield from extra_endpoints(lines, _spec_tuple(spec, pack))


def scan_lines(path, lines, pack=None, stacks=None):
    pack = profile_pack() if pack is None else pack
    stacks = profile_stacks() if stacks is None else stacks
    yield from _scan_pack(path, lines, pack)
    for spec in stacks:
        if path.endswith(spec[0]):
            yield from extra_endpoints(lines, spec)


def watched(path, pack=None, stacks=None):
    pack = profile_pack() if pack is None else pack
    stacks = profile_stacks() if stacks is None else stacks
    for spec in pack_endpoints(pack):
        suffix = spec.get("suffix") or ""
        if suffix and path.endswith(suffix):
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
        for suffix, marker, mapping, security, name in all_endpoint_specs():
            if name in seen or not path.endswith(suffix):
                continue
            if marker and re.search(marker, blob):
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
    if pack and not packlib.load(pack):
        print(f"FAIL: Pack {pack} has no complete manifest", file=sys.stderr)
        return 1
    if not pack and not stacks:
        print("FAIL: Pack is empty", file=sys.stderr)
        return 1
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
    if not out.strip() and not re.fullmatch(r"[0-9a-f]{7,40}", base, re.I):
        _c_b, b_sha = _git("rev-parse", "--verify", "-q", f"{base}^{{commit}}")
        _c_h, h_sha = _git("rev-parse", "--verify", "-q", f"{head or 'HEAD'}^{{commit}}")
        if b_sha.strip() and b_sha.strip() == h_sha.strip():
            eff_base = ""
            for sf in sorted(glob.glob(os.path.join("docs", "agents-v0", "requirements", "*.state.json")), key=os.path.getmtime, reverse=True):
                try:
                    st = json.load(open(sf, encoding="utf-8"))
                    slug = (st.get("feature") or "").strip()
                    rep_sha = ""
                    for rp in (
                        os.path.join("docs", "agents-v0", "build", slug, "build-report.md"),
                        os.path.join("docs", "agents-v0", "verify", slug, "test-report.md"),
                    ):
                        if slug and os.path.isfile(rp):
                            m = re.search(r"^commit:\s*([0-9a-f]{7,40})\b", open(rp, encoding="utf-8").read(), re.I | re.M)
                            if m:
                                _cr, r_full = _git("rev-parse", "--verify", "-q", f"{m.group(1)}^{{commit}}")
                                if r_full.strip():
                                    rep_sha = r_full.strip()
                                    break
                    bc = (st.get("baseCommit") or "").strip()
                    if bc:
                        _cb, bc_full = _git("rev-parse", "--verify", "-q", f"{bc}^{{commit}}")
                        bc_full = bc_full.strip()
                        if bc_full and bc_full != h_sha.strip():
                            if rep_sha:
                                _cm, mb = _git("merge-base", bc_full, rep_sha)
                                if mb.strip() == bc_full and bc_full != rep_sha:
                                    eff_base = bc_full
                                    break
                            else:
                                eff_base = bc_full
                                break
                    if rep_sha:
                        _cp, par = _git("rev-parse", "--verify", "-q", f"{rep_sha}^")
                        if par.strip():
                            eff_base = par.strip()
                            break
                except (OSError, ValueError):
                    pass
            if not eff_base:
                for rp in sorted(glob.glob(os.path.join("docs", "agents-v0", "build", "*", "build-report.md")), key=os.path.getmtime, reverse=True):
                    try:
                        m = re.search(r"^commit:\s*([0-9a-f]{7,40})\b", open(rp, encoding="utf-8").read(), re.I | re.M)
                        if m:
                            _cp, par = _git("rev-parse", "--verify", "-q", f"{m.group(1)}^")
                            if par.strip():
                                eff_base = par.strip()
                                break
                    except OSError:
                        pass
            if eff_base:
                base = eff_base
                span = [base, head or "HEAD"]
                code, out = _git("diff", "--name-only", "--diff-filter=AM", *span)
    failures, checked = [], 0
    for path in [p for p in out.splitlines() if watched(p, pack, stacks)]:
        if head:
            _code, text = _git("show", f"{head}:{path}")
        else:
            text = "\n".join(_read_lines(path))
        code_old, old = _git("show", f"{base}:{path}")
        before = {(v, p) for _n, v, p, _ok in scan_lines(path, old.splitlines(), pack, stacks)} if code_old == 0 else set()
        data = packlib.load(pack) if pack else None
        marker = (data or {}).get("publicMarker") or "the pack public marker"
        hint = f"(the {pack or 'profile'} scanner, or {marker})"
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
