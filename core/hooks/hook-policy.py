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
        "id_rsa",
        "id_dsa",
        "id_ecdsa",
        "id_ed25519",
        ".netrc",
        ".npmrc",
        ".pypirc",
        ".pgpass",
        ".git-credentials",
    }
)
# Same family as the .gitignore and .cursorignore secret lists.
SECRET_SUFFIXES = (".pem", ".key", ".p12", ".pfx", ".jks", ".keystore")
# Credential locations by directory: SSH and GPG keys, cloud and cluster credentials, the process environment.
SECRET_PATH_RE = re.compile(
    r"(^|/)\.(ssh|gnupg)(/|$)"
    r"|(^|/)\.aws/(credentials|config)$"
    r"|(^|/)\.kube/config$"
    r"|(^|/)\.config/gcloud(/|$)"
    r"|(^|/)\.docker/config\.json$"
    r"|(^|/)proc/[^/]+/environ$"
)
SECRET_BASENAME_RE = re.compile(r"^\.env(\.(?!(example|sample|template|dist)$)[^/]+)?$")
# curl/wget piped into an interpreter, or an interpreter reading process substitution of a download.
PIPE_TO_INTERPRETER_RE = re.compile(
    r"\b(?:curl|wget)\b[^|;&\n]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh|dash|ksh|python3?|perl|ruby|node)\b"
    r"|\b(?:sh|bash|zsh|dash|ksh)\s+<\(\s*(?:curl|wget)\b"
)
# sudo/doas in command position, directly or as the body of sh -c.
SUDO_RE = re.compile(
    r"(?:^|[;&|(`]|\$\()\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*(?:sudo|doas)\b"
    r"|\b(?:sh|bash|zsh|dash|ksh)\s+-l?c\s+[\"']\s*(?:sudo|doas)\b"
)
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
    cleaned = path.strip().strip("'\"")
    norm = cleaned.replace("\\", "/")
    base = os.path.basename(norm)
    if base.endswith(".pub"):
        return False  # a public key is not a secret
    if base in SECRET_BASENAMES:
        return True
    # A negated glob such as '!*.key' excludes files from a search; it does not read them.
    if base.endswith(SECRET_SUFFIXES) and not cleaned.startswith("!"):
        return True
    if SECRET_PATH_RE.search(norm):
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
    if re.search(r"^(?:(?:sh|bash|dash)\s+)?\S*feature-worktree\.sh\b", low):
        return "ask", "creating a feature branch and worktree requires explicit user authorization."

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

    if bin0 == "glab":
        pairs = set(zip(parts[1:], parts[2:]))
        joined = " ".join(parts[1:])
        if ("mr", "merge") in pairs:
            return "block", "glab mr merge requires explicit human authorization."
        if ("mr", "approve") in pairs:
            return "block", "approving a merge request is a human act, not an agent action."
        if "api" in parts[1:3]:
            if re.search(r"/(merge|approve)\b", joined):
                return "block", "merging or approving a merge request through glab api is blocked."
            mutating = any(x in parts for x in ("-f", "-F", "--field", "--raw-field", "--input"))
            for i, tok in enumerate(parts[:-1]):
                if tok in ("-X", "--method") and parts[i + 1].upper() != "GET":
                    mutating = True
            if mutating:
                return "ask", "a state-changing glab api call requires explicit user approval."
        if pairs & {("mr", "create"), ("mr", "update"), ("mr", "close"), ("mr", "reopen"), ("mr", "delete"),
                    ("ci", "run"), ("ci", "trigger"), ("ci", "retry"), ("release", "create"), ("release", "delete"),
                    ("variable", "set"), ("variable", "update"), ("variable", "delete")}:
            return "ask", "this glab command changes the merge request, pipeline, release, or CI variables; it requires explicit user approval."

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
            if _commit_paths_are_evidence(parts):
                return "allow", ""
            return "ask", "git commit requires explicit user approval."
        if sub == "reset" and "--hard" in parts:
            return "block", "git reset --hard is not allowed."
        if sub == "clean" and any(
            x in parts for x in ("-f", "-fd", "-ff", "-fdx", "-ffdx", "-x")
        ):
            return "block", "git clean with -f/-x is not allowed."
        if sub == "checkout" and "--" in parts:
            return "ask", "git checkout -- may discard work; requires approval."
        if sub == "tag":
            args = parts[parts.index("tag") + 1:] if "tag" in parts else []
            listing = not [a for a in args if not a.startswith("-")] or any(a in ("-l", "--list") for a in args)
            if not listing:
                return "ask", "creating, moving, or deleting a git tag requires explicit user approval."
        if sub == "restore":
            staged_only = any(a in ("--staged", "-S") for a in parts) and not any(
                a in ("--worktree", "-W") for a in parts
            )
            if not staged_only:
                return "ask", "git restore may discard work; requires approval."
        branch_msg = "creating a branch or worktree requires explicit user authorization."
        if sub == "branch":
            args = parts[parts.index("branch") + 1 :] if "branch" in parts else []
            flags = [a for a in args if a.startswith("-")]
            positional = [a for a in args if not a.startswith("-")]
            if any(f in ("-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy") for f in flags):
                return "ask", "deleting, renaming, or copying a branch requires explicit user approval."
            tracking = any(
                f.startswith("--set-upstream-to") or f in ("-u", "--unset-upstream", "--edit-description")
                for f in flags
            )
            listing = any(
                f in ("--list", "--all", "--remotes", "--verbose", "--show-current", "--contains",
                      "--no-contains", "--merged", "--no-merged")
                or re.fullmatch(r"-[avrl]+", f)
                for f in flags
            )
            if positional and not listing and not tracking:
                return "ask", branch_msg
        if sub == "worktree" and "add" in parts[1:]:
            return "ask", branch_msg
        if sub == "checkout" and any(x in parts for x in ("-b", "-B")):
            return "ask", branch_msg
        if sub == "switch" and any(x in parts for x in ("-c", "-C", "--create")):
            return "ask", branch_msg
        if sub in ("rebase", "merge", "cherry-pick", "revert"):
            return "ask", f"git {sub} rewrites or combines history; requires explicit user approval."
        if sub == "stash":
            args = parts[parts.index("stash") + 1 :] if "stash" in parts else []
            op = next((a for a in args if not a.startswith("-")), "")
            if op in ("pop", "drop", "clear"):
                return "ask", "git stash pop, drop, or clear can discard work; requires explicit user approval."

    return "allow", ""


def _commit_paths_are_evidence(parts: List[str]) -> bool:
    """A reports-only commit (build/ or verify/ docs) does not ask again."""
    if "--" not in parts:
        return False
    paths = [p for p in parts[parts.index("--") + 1 :] if p != "--"]
    if not paths:
        return False
    for path in paths:
        norm = path.replace("\\", "/").lstrip("./")
        if not (
            norm.startswith("docs/agents-v0/build/")
            or norm.startswith("docs/agents-v0/verify/")
        ):
            return False
    return True


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
    # sudo is unwrapped when segments are split, and a pipe splits a download from its interpreter,
    # so both are judged on the whole command. A block above still wins.
    if SUDO_RE.search(cmd):
        worst, msg = "ask", msg or "sudo or doas runs a command as root; requires explicit user approval."
    elif PIPE_TO_INTERPRETER_RE.search(cmd):
        worst, msg = "ask", msg or "piping a download into an interpreter requires explicit user approval."
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
    if bin0 in ("declare", "typeset") and any(
        a.startswith("-") and re.search(r"[xp]", a[1:]) for a in parts[1:]
    ):
        return True
    if bin0 == "compgen" and any(a in ("-e", "-v") for a in parts[1:]):
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
    re.compile(r"(^|/)\.cursor/(commands|skills)/"),
    # Every CI gate script: a new check is protected without editing this list.
    re.compile(r"(^|/)\.agents-v0/ci/[^/]+\.sh$"),
    # Every kit script: they write the state, the evidence, and the merge-request body that approvers
    # rely on, and one of them runs sudo. A new script is protected without editing this list.
    re.compile(r"(^|/)\.agents-v0/scripts/[^/]+\.sh$"),
    re.compile(r"(^|/)\.agents-v0/hooks/pre-push$"),
    re.compile(r"(^|/)\.git/hooks/"),
    re.compile(r"(^|/)\.gitlab-ci\.yml$"),
    re.compile(r"(^|/)\.gitlab/"),
    re.compile(r"(^|/)CODEOWNERS$"),
    re.compile(r"(^|/)core/hooks/"),
    re.compile(r"(^|/)AGENTS\.md$"),
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
    if re.search(r"(^|/)docs/agents-v0/requirements/.+\.md$", norm):
        return (
            "ask",
            "Delivery artifact edit — do not change Delivery approvals without explicit human gate approval.",
        )
    if re.search(r"(^|/)docs/agents-v0/milestones/.+\.md$", norm):
        return (
            "ask",
            "Milestone manifest edit — confirm with release owner before changing go/no-go rows.",
        )
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
