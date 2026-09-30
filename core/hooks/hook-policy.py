#!/usr/bin/env python3
"""Shell and path guardrails for agents-v0 hooks. JSON on stdout; exit 0 unless internal error."""
from __future__ import annotations

import json
import os
import re
import shlex
import sys
from typing import List, Literal, Optional, Tuple

Action = Literal["allow", "ask", "block"]

SECRET_BASENAMES = frozenset(
    {
        ".env",
        "credentials.json",
        "secrets.yml",
        "secrets.yaml",
    }
)
SECRET_BASENAME_RE = re.compile(r"^\.env(\.(?!(example|sample|template|dist)$)[^/]+)?$")
SECRET_READERS = frozenset(
    {
        "cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg",
        "sed", "awk", "base64", "xxd", "od", "strings", "nl", "bat", "source", ".",
    }
)
SCRIPT_INTERPRETERS = frozenset({"python", "python3", "node", "perl", "ruby"})
SCRIPT_WRITE_HINT = re.compile(
    r"open\s*\([^)]*,\s*['\"][wax+]|\.write|unlink|remove|rename|rmtree|writeFile|appendFile|rmSync",
    re.I,
)

# MCP: explicit mutating verbs (word-boundary); default deny unknown mutators via ask list extension
MCP_MUTATE_VERBS = frozenset(
    {
        "create",
        "update",
        "delete",
        "write",
        "merge",
        "deploy",
        "publish",
        "execute",
        "run",
        "send",
        "transition",
        "add",
        "remove",
        "insert",
        "upsert",
        "patch",
        "put",
        "post",
    }
)
MCP_READ_SAFE = frozenset({"list", "get", "read", "search", "fetch", "describe", "show"})


def _json_out(action: Action, message: str = "") -> None:
    print(json.dumps({"action": action, "message": message}), end="")


def _strip_env_prefix(cmd: str) -> str:
    while True:
        m = re.match(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+", cmd)
        if not m:
            break
        cmd = cmd[m.end() :].lstrip()
    return cmd


def split_segments(cmd: str) -> List[str]:
    """Split compound shell commands; recurse into sh/bash -c bodies."""
    cmd = cmd.strip()
    if not cmd:
        return []
    segments: List[str] = []
    buf: List[str] = []
    in_single = in_double = False
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if c == "'" and not in_double:
            in_single = not in_single
            buf.append(c)
            i += 1
            continue
        if c == '"' and not in_single:
            in_double = not in_double
            buf.append(c)
            i += 1
            continue
        if not in_single and not in_double:
            if cmd[i : i + 2] in ("&&", "||"):
                seg = "".join(buf).strip()
                if seg:
                    segments.extend(_expand_wrapper(seg))
                buf = []
                i += 2
                continue
            if c in ";|":
                seg = "".join(buf).strip()
                if seg:
                    segments.extend(_expand_wrapper(seg))
                buf = []
                i += 1
                continue
            if c == "\n":
                seg = "".join(buf).strip()
                if seg:
                    segments.extend(_expand_wrapper(seg))
                buf = []
                i += 1
                continue
        buf.append(c)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        segments.extend(_expand_wrapper(tail))
    for body in _extract_substitutions(cmd):
        segments.extend(split_segments(body))
    return [s for s in segments if s.strip()]


def _extract_substitutions(cmd: str) -> List[str]:
    """Return bodies of $(...) and `...` command substitutions (outside single quotes)."""
    bodies: List[str] = []
    in_single = False
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if c == "'":
            in_single = not in_single
        elif not in_single and cmd[i : i + 2] == "$(":
            depth = 1
            j = i + 2
            while j < len(cmd) and depth:
                if cmd[j] == "(":
                    depth += 1
                elif cmd[j] == ")":
                    depth -= 1
                j += 1
            bodies.append(cmd[i + 2 : j - 1])
            i = j
            continue
        elif not in_single and c == "`":
            j = cmd.find("`", i + 1)
            if j == -1:
                break
            bodies.append(cmd[i + 1 : j])
            i = j + 1
            continue
        i += 1
    return [b for b in bodies if b.strip()]


def _expand_wrapper(seg: str) -> List[str]:
    seg = _strip_env_prefix(seg)
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return [seg]
    bin0 = parts[0].split("/")[-1]
    if len(parts) >= 3 and parts[1] in ("-c", "-lc") and bin0 in (
        "sh",
        "bash",
        "zsh",
        "dash",
        "ksh",
    ):
        body = " ".join(parts[2:])
        return split_segments(body)
    if bin0 == "env" and len(parts) >= 2:
        i = 1
        while i < len(parts):
            p = parts[i]
            if p in ("-i", "-u", "--unset", "-0", "--version", "--help"):
                i += 2 if p in ("-u", "--unset") else 1
                continue
            if p.startswith("-") or "=" in p:
                i += 1
                continue
            return split_segments(" ".join(parts[i:]))
        return [seg]
    if bin0 in ("sudo", "command", "nohup", "time") and len(parts) >= 2:
        return split_segments(" ".join(parts[1:]))
    if bin0 == "xargs" and len(parts) >= 2:
        for i, p in enumerate(parts[1:], 1):
            if p in ("-I", "--replace", "-i") and i + 1 < len(parts):
                return split_segments(" ".join(parts[i + 2 :]))
        return split_segments(" ".join(parts[1:]))
    if bin0 == "eval" and len(parts) >= 2:
        return split_segments(" ".join(parts[1:]))
    return [seg]


def _path_looks_secret(path: str) -> bool:
    base = os.path.basename(path.strip().strip("'\""))
    if base in SECRET_BASENAMES:
        return True
    return bool(SECRET_BASENAME_RE.match(base))


def _segment_reads_secret_file(seg: str) -> bool:
    seg = _strip_env_prefix(seg.strip())
    if not seg:
        return False
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return False
    bin0 = parts[0].split("/")[-1]
    if bin0 in SCRIPT_INTERPRETERS:
        return any(_path_looks_secret(lit) for lit in _script_literals(parts))
    args = [p for p in parts[1:] if not p.startswith("-")]
    if bin0 in SECRET_READERS:
        return any(_path_looks_secret(p) for p in args)
    if bin0 in ("cp", "mv", "scp", "rsync") and len(args) >= 2:
        return any(_path_looks_secret(p) for p in args[:-1])
    return False


def _segment_writes_protected_path(seg: str) -> Optional[str]:
    """Detect shell redirection or cp/mv/tee targeting protected paths."""
    seg = _strip_env_prefix(seg.strip())
    if not seg:
        return None
    # Redirection targets
    for m in re.finditer(r">\s*([^\s;|&]+)", seg):
        target = m.group(1).lstrip(">")
        target = target.strip().strip("'\"")
        if is_protected_path(target):
            return target
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return None
    bin0 = parts[0].split("/")[-1]
    if bin0 in ("cp", "mv", "tee", "install", "ln", "truncate", "rm", "chmod"):
        for p in parts[1:]:
            if p.startswith("-"):
                continue
            if is_protected_path(p):
                return p
    if bin0 in ("sed", "perl") and any(p.startswith("-i") for p in parts[1:]):
        for p in parts:
            if not p.startswith("-") and is_protected_path(p):
                return p
    if bin0 in SCRIPT_INTERPRETERS and SCRIPT_WRITE_HINT.search(seg):
        for lit in _script_literals(parts):
            if is_protected_path(lit):
                return lit
    return None


def _script_literals(parts: List[str]) -> List[str]:
    """String literals inside interpreter -c/-e bodies (outer shell quotes already removed)."""
    lits: List[str] = []
    for tok in parts[1:]:
        lits.extend(re.findall(r"['\"]([^'\"]+)['\"]", tok))
    return lits


def _rm_is_recursive(parts: List[str]) -> bool:
    for p in parts[1:]:
        if p == "--":
            break
        if p == "--recursive":
            return True
        if p.startswith("-") and not p.startswith("--") and re.search(r"[rR]", p[1:]):
            return True
    return False


def classify_segment(seg: str) -> Tuple[Action, str]:
    seg = _strip_env_prefix(seg.strip())
    if not seg:
        return "allow", ""
    low = seg.lower()

    if _segment_reads_secret_file(seg):
        return "block", "reading likely secret files is blocked (security-baseline.mdc)."

    wpath = _segment_writes_protected_path(seg)
    if wpath:
        return (
            "block",
            f"Protected kit/CI path cannot be modified via shell: {wpath}",
        )

    # Destructive / production patterns (heuristic)
    if re.search(r"\bkubectl\s+delete\b", low) or re.search(
        r"\bkubectl\s+.*\s+delete\b", low
    ):
        return "block", "kubectl delete is blocked (production safety)."
    if re.search(r"\bhelm\s+(delete|uninstall)\b", low):
        return "block", "helm delete/uninstall is blocked."
    if re.search(r"\bterraform\s+apply\b", low) and (
        "-auto-approve" in low or "-auto-approve=true" in low
    ):
        return "block", "terraform apply -auto-approve is blocked."
    if re.search(r"\b(psql|mysql|mariadb)\s+.*\b(drop|truncate)\b", low):
        return "block", "database DROP/TRUNCATE via CLI is blocked."
    if re.search(r"\b(aws|gcloud|az)\s+.*\b(delete|terminate|destroy|remove)\b", low):
        return "ask", "cloud resource deletion requires explicit user approval."
    if re.search(r"\b(docker|podman)\s+push\b", low) or re.search(
        r"\bnpm\s+publish\b", low
    ):
        return "ask", "registry publish requires explicit user approval."
    if re.search(r"\bmvn\s+.*\bdeploy\b", low) or re.search(
        r"\bgradle\s+.*\bpublish\b", low
    ):
        return "ask", "artifact deploy/publish requires explicit user approval."

    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return "allow", ""
    bin0 = parts[0].split("/")[-1]

    if bin0 == "rm" and _rm_is_recursive(parts):
        return "block", "recursive rm is blocked without explicit human approval."
    if bin0 == "find" and "-delete" in parts:
        return "ask", "find -delete removes files; requires explicit user approval."

    if bin0 == "gh":
        sub = parts[1] if len(parts) > 1 else ""
        if sub == "pr" and "merge" in parts[2:]:
            return "block", "gh pr merge requires explicit human authorization."
        if sub == "release" and "create" in parts[2:]:
            return "ask", "gh release create requires explicit user approval."

    if bin0 == "git":
        sub = _git_subcommand(parts)
        if sub == "push":
            for tok in parts[parts.index(sub) + 1 :] if sub in parts else []:
                if tok in ("--force", "-f", "--force-with-lease") or tok.startswith(
                    "+"
                ) or "/+" in tok:
                    return "block", "git force-push is not allowed (ai-agent-conduct.mdc)."
            return "ask", "git push requires explicit user approval."
        if sub == "commit":
            return "ask", "git commit requires explicit user approval."
        if sub == "reset" and "--hard" in parts:
            return "block", "git reset --hard is not allowed."
        if sub == "clean" and any(
            x in parts for x in ("-f", "-fd", "-ff", "-fdx", "-ffdx", "-x")
        ):
            return "block", "git clean with -f/-x is not allowed."
        if sub == "checkout" and "--" in parts:
            return "ask", "git checkout -- may discard work; requires approval."
        if sub == "restore" and "--staged" not in parts and "--" in parts:
            return "ask", "git restore may discard work; requires approval."

    return "allow", ""


def _git_subcommand(parts: List[str]) -> str:
    i = 1
    while i < len(parts):
        p = parts[i]
        if p in ("-C", "--git-dir", "--work-tree") and i + 1 < len(parts):
            i += 2
            continue
        if p == "-c" and i + 1 < len(parts):
            i += 2
            continue
        if p.startswith("-") and p not in ("-C", "--git-dir", "--work-tree"):
            i += 1
            continue
        return p
    return ""


def classify_command(cmd: str) -> Tuple[Action, str]:
    segments = split_segments(cmd)
    if not segments:
        return "allow", ""
    worst: Action = "allow"
    msg = ""
    for seg in segments:
        action, message = classify_segment(seg)
        if action == "block":
            return "block", message
        if action == "ask" and worst != "block":
            worst = "ask"
            msg = message or msg
    if worst == "ask":
        return "ask", msg
    return "allow", ""


def _segment_may_print_secrets(seg: str) -> bool:
    seg = _strip_env_prefix(seg.strip())
    if not seg:
        return False
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return False
    bin0 = parts[0].split("/")[-1]
    if bin0 == "printenv":
        return True
    if bin0 == "env":
        for p in parts[1:]:
            if p.startswith("-") and p not in ("-u", "--unset"):
                continue
            if p in ("-u", "--unset"):
                continue
            if "=" in p:
                continue
            return False
        return True
    if bin0 == "set" and len(parts) == 1:
        return True
    if bin0 == "export" and (len(parts) == 1 or "-p" in parts[1:]):
        return True
    if re.search(r"(?:^|[\s;|&])(?:printenv)\b", seg):
        return True
    if re.search(r"(?:^|[\s;|&])env\s*(?:\||$)", seg):
        return True
    if bin0 in ("awk", "gawk", "mawk") and re.search(r"\bENVIRON\b", seg):
        return True
    if len(parts) >= 3 and parts[1] == "-c" and bin0 in ("sh", "bash", "zsh", "dash", "ksh"):
        body = " ".join(parts[2:])
        if re.search(r"(?:printenv|env)\b|export\s+-p\b", body):
            return True
        return _segment_may_print_secrets(body)
    if bin0 in ("python", "python3") and "-c" in parts[1:]:
        body = " ".join(parts[parts.index("-c") + 1 :])
        if re.search(r"\bos\.environ\b|\benviron\[", body):
            return True
    if bin0 == "node" and ("-e" in parts[1:] or "--eval" in parts[1:]):
        if re.search(r"process\.env\b", seg):
            return True
    return False


def may_print_secrets(cmd: str) -> bool:
    for seg in split_segments(cmd):
        if _segment_may_print_secrets(seg):
            return True
    return False


PROTECTED_PATH_PATTERNS = [
    re.compile(r"(^|/)\.cursor/hooks\.json$"),
    re.compile(r"(^|/)\.cursor/hooks/"),
    re.compile(r"(^|/)\.cursor/rules/"),
    re.compile(r"(^|/)\.cursor/agents/"),
    re.compile(r"(^|/)\.claude/settings\.json$"),
    re.compile(r"(^|/)\.claude/hooks/"),
    re.compile(r"(^|/)\.claude/agents/"),
    re.compile(r"(^|/)\.claude/rules/"),
    re.compile(r"(^|/)\.kilo/kilo\.json$"),
    re.compile(r"(^|/)\.kilo/agent/"),
    re.compile(r"(^|/)\.kilo/rules/"),
    re.compile(
        r"(^|/)ci/check-(approvals|evidence|milestone|delivery-linkage|known-failures|approver-github|approver-gitlab|coverage-ratchet)\.sh$"
    ),
    re.compile(r"(^|/)\.github/workflows/"),
    re.compile(r"(^|/)\.gitlab-ci\.yml$"),
    re.compile(r"(^|/)\.gitlab/"),
    re.compile(r"(^|/)CODEOWNERS$"),
    re.compile(r"(^|/)core/hooks/"),
    re.compile(r"(^|/)AGENTS\.md$"),
    re.compile(r"(^|/)CLAUDE\.md$"),
]


def is_protected_path(path: str) -> bool:
    if not path:
        return False
    norm = path.replace("\\", "/")
    for pat in PROTECTED_PATH_PATTERNS:
        if pat.search(norm):
            return True
    return False


def classify_path(path: str) -> Tuple[Action, str]:
    if is_protected_path(path):
        return (
            "block",
            f"Protected kit/CI path cannot be modified by agents: {path}",
        )
    norm = path.replace("\\", "/")
    if re.search(r"(^|/)docs/requirements/.+\.md$", norm):
        return (
            "ask",
            "Delivery artifact edit — do not change Delivery approvals without explicit human gate approval.",
        )
    if re.search(r"(^|/)docs/milestones/.+\.md$", norm):
        return (
            "ask",
            "Milestone manifest edit — confirm with release owner before changing go/no-go rows.",
        )
    return "allow", ""


def _mcp_split(tool: str, server: str) -> Tuple[str, str]:
    """Claude names MCP tools mcp__<server>__<tool>; Cursor passes server separately."""
    m = re.match(r"^mcp__([^_]+(?:_[^_]+)*?)__(.+)$", tool)
    if m and not server:
        return m.group(1), m.group(2)
    return server, tool


def _load_mcp_policy() -> Optional[dict]:
    path = os.environ.get("HOOK_MCP_POLICY") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "mcp-policy.json"
    )
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _mcp_policy_decision(policy: dict, server: str, tool: str) -> Optional[Tuple[Action, str]]:
    import fnmatch

    servers = policy.get("servers") or {}
    entry = servers.get(server) if server else None
    if entry is None:
        default = policy.get("default", "heuristic")
        if default in ("allow", "ask", "block"):
            return default, f"MCP default policy ({default}) for unlisted server {server or '?'}: {tool}"
        return None
    t = tool.lower()
    for key, action in (("block", "block"), ("allow", "allow"), ("ask", "ask")):
        for pat in entry.get(key, []):
            if fnmatch.fnmatch(t, pat.lower()):
                return action, f"MCP policy {server}/{pat} → {action}: {tool}"
    fallback = entry.get("default", "ask")
    return fallback, f"MCP policy {server} default → {fallback}: {tool}"


def classify_mcp(tool: str, server: str = "") -> Tuple[Action, str]:
    server, tool = _mcp_split(tool, server)
    policy = _load_mcp_policy()
    if policy is not None:
        decision = _mcp_policy_decision(policy, server, tool)
        if decision is not None:
            return decision
    return classify_mcp_tool(tool)


def classify_mcp_tool(tool: str) -> Tuple[Action, str]:
    t = tool.lower()
    if not t:
        return "allow", ""
    if re.search(r"\b(production|prod-env|prod_cluster)\b", t):
        return "block", f"MCP tool blocked for production safety: {tool}"
    tokens = re.split(r"[_\-.]+", t)
    if "delete" in tokens and "undelete" not in tokens:
        return "block", f"MCP destructive tool blocked: {tool}"
    for tok in tokens:
        if tok in MCP_MUTATE_VERBS:
            return "ask", f"MCP tool may mutate external state: {tool}"
    if any(tok in MCP_READ_SAFE for tok in tokens):
        return "allow", ""
    if re.search(r"(create|update|write|merge|deploy|publish|execute|send)", t):
        return "ask", f"MCP tool may mutate external state: {tool}"
    return "allow", ""


def main() -> int:
    if len(sys.argv) < 2:
        _json_out("block", "hook-policy: missing mode")
        return 0
    mode = sys.argv[1]
    if mode == "shell":
        cmd = os.environ.get("HOOK_CMD", "")
        if not cmd and len(sys.argv) > 2:
            cmd = sys.argv[2]
        action, message = classify_command(cmd)
        if action == "allow" and may_print_secrets(cmd):
            action, message = "block", (
                "Refusing commands that may print secrets or environment variables."
            )
        _json_out(action, message)
        return 0
    if mode == "mcp":
        tool = os.environ.get("HOOK_MCP_TOOL", "")
        server = os.environ.get("HOOK_MCP_SERVER", "")
        action, message = classify_mcp(tool, server)
        _json_out(action, message)
        return 0
    if mode == "path":
        path = os.environ.get("HOOK_PATH", "")
        if not path and len(sys.argv) > 2:
            path = sys.argv[2]
        action, message = classify_path(path)
        _json_out(action, message)
        return 0
    _json_out("block", f"hook-policy: unknown mode {mode}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # fail closed
        _json_out("block", f"hook-policy error: {exc}")
        raise SystemExit(0)
