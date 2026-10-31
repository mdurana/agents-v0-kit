#!/usr/bin/env python3
"""Shell and path guardrails for agents-v0 hooks. JSON on stdout; exit 0 unless internal error."""
from __future__ import annotations

import json
import os
import posixpath
import re
import shlex
import subprocess
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
# kitfix-20261031-guard-override: the kit scripts read AGENTS_V0_* variables (AGENTS_V0_SKIP_BRANCH_GUARD,
#   AGENTS_V0_SKIP_COMMIT_CHECK, AGENTS_V0_NOW, AGENTS_V0_TRACE_MODE, ...). They are for kit fixtures and for the
#   person's own environment, never for an agent: any agent command that sets, exports or unsets one is blocked
#   (attended and unattended): a prefix assignment, export/declare/typeset/readonly/local/unset/setenv, env NAME=,
#   ${NAME:=...}, os.environ / putenv, also inside sh -c / bash -c, after && ; | or in $(...). Reading one
#   ($AGENTS_V0_X, ${AGENTS_V0_X:-}) is allowed.
GUARD_OVERRIDE_RE = re.compile(
    r"(?:^|[^A-Za-z0-9_$])AGENTS_V0_[A-Za-z0-9_]*(?:\+?=|:=|:\?=)"
    r"|\b(?:export|declare|typeset|readonly|local|unset|setenv|unsetenv)\b[^;&|\n]*\bAGENTS_V0_"
    r"|\b(?:environ|putenv|setdefault)\b[^;&|\n]{0,60}AGENTS_V0_"
)
GUARD_OVERRIDE_MSG = (
    "setting AGENTS_V0_* variables is not allowed for an agent: they switch kit guards and checks off "
    "(branch guard, gate-commit check, clock, traceability mode). Run the kit script without them; if a guard "
    "refuses, fix the cause it names or ask the user."
)
KEEP_BRANCH_MSG = (
    "story branches (feature/*, maintain/*) are kept after release for reference and backtracking; "
    "do not delete or rename them (git worktree remove only removes the folder and keeps the branch)."
)
SUDO_RE = re.compile(
    r"(?:^|[;&|(`]|\$\()\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*(?:sudo|doas)\b"
    r"|\b(?:sh|bash|zsh|dash|ksh)\s+-l?c\s+[\"']\s*(?:sudo|doas)\b"
)
# System package installs (the kit never installs host packages; host-tools-macports.sh --install
# is the one approved path and runs as its own, asked-for script).
PKG_INSTALL_RE = re.compile(
    r"(?:^|[;&|(`]|\$\()\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*"
    r"(?:apt|apt-get|aptitude|dnf|yum|microdnf|apk|zypper|pacman|brew|port|snap|flatpak)\s+"
    r"(?:-\S+\s+)*(?:install|add|upgrade|update|-S\b|-Sy\b|-Syu\b)"
)
# An unauthenticated Docker/Podman TCP API is root on the host; do not use it to get a runtime.
DOCKER_TCP_RE = re.compile(
    r"DOCKER_HOST=['\"]?tcp://"
    r"|\b(?:127\.0\.0\.1|localhost|0\.0\.0\.0|\[::1\]):237[56]\b"
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
# kitfix-20261031-installed-no-overrides: the installed scripts carry no AGENTS_V0_* override code; only the
# kit's own test suites install copies that keep it (install.sh --test-overrides). An agent must not.
TEST_OVERRIDES_RE = re.compile(r"--test-overrides\b|\bstrip-test-overrides\.sh\b")
TEST_OVERRIDES_MSG = ("installing the kit with its test overrides (install.sh --test-overrides) is for the kit's own test "
                      "suites only; an agent never reinstalls or strips the kit scripts. Report the problem instead.")

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
    if bin0 in ("sh", "bash", "zsh", "dash", "ksh") and len(parts) >= 3:
        i = 1
        saw_c = False
        while i < len(parts) and parts[i].startswith("-"):
            flag = parts[i]
            if flag in ("-c", "-lc") or (len(flag) > 2 and "c" in flag[1:] and not flag.startswith("--")):
                saw_c = True
                i += 1
                break
            if flag in ("-o", "+o") and i + 1 < len(parts):
                i += 2
            else:
                i += 1
        if saw_c and i < len(parts):
            body = " ".join(parts[i:])
            return split_segments(body)
    if bin0 == "timeout" and len(parts) >= 3:
        i = 1
        while i < len(parts) and parts[i].startswith("-"):
            if parts[i] in ("-k", "-s", "--kill-after", "--signal") and i + 1 < len(parts):
                i += 2
            else:
                i += 1
        if i + 1 < len(parts):
            return split_segments(" ".join(parts[i + 1 :]))
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
    if bin0 in ("sudo", "command", "nohup", "time", "nice", "stdbuf", "exec", "builtin") and len(parts) >= 2:
        i = 1
        while i < len(parts) and parts[i].startswith("-"):
            if bin0 == "sudo" and parts[i] in ("-u", "-g", "-C", "-D", "-R", "-T") and i + 1 < len(parts):
                i += 2
            elif bin0 == "nice" and parts[i] == "-n" and i + 1 < len(parts):
                i += 2
            else:
                i += 1
        if i < len(parts):
            return split_segments(" ".join(parts[i:]))
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
    return _segment_writes_matching_path(seg, is_protected_path)


def _segment_writes_ask_path(seg: str) -> Optional[Tuple[str, str]]:
    """Detect shell redirection or cp/mv/tee/sed/interpreter writes targeting ask-level paths."""
    target = _segment_writes_matching_path(seg, lambda p: classify_path(p)[0] == "ask")
    if target:
        return target, classify_path(target)[1]
    return None


def _segment_writes_matching_path(seg: str, predicate) -> Optional[str]:
    seg = _strip_env_prefix(seg.strip())
    if not seg:
        return None
    # Redirection targets
    for m in re.finditer(r">+\s*([^\s;|&]+)", seg):
        target = m.group(1).strip().strip("'\"")
        if predicate(target):
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
            if predicate(p):
                return p
    if bin0 in ("sed", "perl") and any(p.startswith("-i") for p in parts[1:]):
        for p in parts:
            if not p.startswith("-") and predicate(p):
                return p
    if bin0 in SCRIPT_INTERPRETERS and SCRIPT_WRITE_HINT.search(seg):
        for lit in _script_literals(parts):
            if predicate(lit):
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


# kitfix-20261031-kit-paths (item 2 of the 10:35 review, all modes): removing, renaming, replacing or restoring
#   the kit's own guard files is blocked, not only writing one file inside them. The per-file patterns above miss
#   `mv .agents-v0/scripts /tmp/x`, `git rm .agents-v0/policy.conf`, `git mv`, a glob, a directory argument, or a
#   relative path after `cd .agents-v0`. KIT_CONTAINER_RE matches the guard folders themselves, their parents
#   (.agents-v0, .agents, .cursor) and anything inside them; the path is also resolved against the command's
#   directory (cd prefix or payload cwd), so `cd .agents-v0 && mv scripts x` is caught. H10 stays the backstop.
KIT_CONTAINER_RE = re.compile(
    r"(^|/)(?:\.agents-v0(?:/(?:scripts|hooks|ci|packs)(?:/.*)?|/policy\.conf)?"
    r"|\.agents(?:/(?:hooks|rules|agents|commands|skills)(?:/.*)?|/hooks\.json)?"
    r"|\.cursor(?:/(?:hooks|rules|agents|commands|skills)(?:/.*)?|/hooks\.json|/cli\.json)?)/*$"
)
KIT_CONTAINER_MSG = ("the kit's guard files (.agents-v0/scripts, .agents-v0/hooks, .agents-v0/policy.conf, the agent "
                     "hooks and rules) cannot be removed, renamed, replaced or restored by an agent: {}. "
                     "Report the problem instead.")
# Programs whose every path operand changes or removes it, and those where only the target changes.
_ALL_OPERANDS_CHANGE = frozenset({"mv", "rm", "rmdir", "unlink", "shred", "truncate", "chmod", "chown", "chgrp",
                                  "chattr", "setfacl"})
_TARGET_CHANGES = frozenset({"cp", "ln", "install", "rsync", "link"})


def _kit_container_text(p: str) -> bool:
    raw = p.replace("\\", "/").strip().strip("'\"")
    if not raw:
        return False
    cands = [raw, posixpath.normpath(raw)]
    g = re.search(r"[*?\[]", raw)
    if g:  # a glob: judge the folder it expands in (".agents-v0/*" -> ".agents-v0")
        prefix = raw[: g.start()]
        cands.append(prefix.rstrip("/") if prefix.endswith("/") else posixpath.dirname(prefix))
    return any(c and KIT_CONTAINER_RE.search(c) for c in cands)


def _project_root(d: str) -> str:
    try:
        r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                           timeout=5, check=False)
        if r.returncode == 0 and r.stdout.strip():
            return os.path.realpath(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    cur = os.path.realpath(d)
    while True:
        if os.path.isdir(os.path.join(cur, ".agents-v0")) or os.path.isdir(os.path.join(cur, ".agents")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.realpath(d)
        cur = parent


def _kit_container_resolved(p: str) -> bool:
    raw = os.path.expanduser(p.strip().strip("'\""))
    if not raw or re.search(r"[$`*?\[]", raw):
        return False
    full = os.path.normpath(raw if os.path.isabs(raw) else os.path.join(_base_dir(), raw))
    root = _project_root(_existing_dir_of(full) if not os.path.isdir(full) else full)
    rel = os.path.relpath(os.path.realpath(os.path.dirname(full)) + "/" + os.path.basename(full), root) \
        if os.path.basename(full) else os.path.relpath(os.path.realpath(full), root)
    if rel.startswith(".."):
        return False
    return bool(KIT_CONTAINER_RE.search("/" + rel.replace(os.sep, "/")))


def _is_kit_container(p: str) -> bool:
    return _kit_container_text(p) or _kit_container_resolved(p)


def _segment_changes_kit_container(seg: str) -> Optional[str]:
    seg = _strip_env_prefix(seg.strip())
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return None
    bin0 = parts[0].split("/")[-1]
    ops = [a for a in parts[1:] if not a.startswith("-")]
    if bin0 in _ALL_OPERANDS_CHANGE:
        if bin0 == "truncate" or bin0 in ("chmod", "chown", "chgrp", "setfacl", "chattr"):
            ops = ops[1:] if bin0 != "truncate" else ops
        for a in ops:
            if _is_kit_container(a):
                return a
    if bin0 in _TARGET_CHANGES:
        tgt = None
        for i, a in enumerate(parts[1:], 1):
            if a in ("-t", "--target-directory") and i + 1 < len(parts):
                tgt = parts[i + 1]
            elif a.startswith("--target-directory="):
                tgt = a.split("=", 1)[1]
        if tgt is None and len(ops) >= 2:
            tgt = ops[-1]
        if tgt and _is_kit_container(tgt):
            return tgt
    if bin0 == "find" and any(a in ("-delete", "-exec", "-execdir", "-ok", "-okdir") for a in parts):
        for a in parts[1:]:
            if a.startswith("-"):
                break
            if _is_kit_container(a):
                return a
    if bin0 == "git":
        sub = _git_subcommand(parts)
        sub_args = parts[parts.index(sub) + 1:] if sub in parts else []
        if sub in ("rm", "mv"):
            for a in sub_args:
                if not a.startswith("-") and _is_kit_container(a):
                    return a
        if sub in ("checkout", "restore"):  # an older version of a guard file is a replaced guard file
            staged_only = sub == "restore" and any(x in ("--staged", "-S") for x in sub_args) and not any(
                x in ("--worktree", "-W") for x in sub_args)
            if not staged_only:
                for a in sub_args:
                    if a != "--" and not a.startswith("-") and _is_kit_container(a):
                        return a
    return None


# kitfix-20261031-kit-source-exec (item 1 of the 10:35 review, unattended mode): the kit's own copies of its scripts
#   (templates/.agents-v0/scripts in a kit checkout such as /home/e2e/kit-src, another project's or another
#   worktree's .agents-v0/scripts) still hold the test-override blocks that install.sh strips, so a split-name
#   override aimed at one of them would skip the branch guard. Unattended, a command may only run the scripts of
#   the checkout it runs in (<checkout>/.agents-v0/scripts, the checkout being the payload cwd or a cd target in
#   the same repository). Running, sourcing, copying, linking or archiving any other copy is blocked, judged per
#   segment after sh -c / env / xargs / timeout / nohup are unwrapped, on the resolved path (symlinks followed).
#   Reading one (cat, grep, diff, git show ...) stays allowed unless the command also pipes into a shell or
#   redirects the output. This is a text check, so it is a speed bump too; the fence is that the agent user cannot
#   read the kit source (v3-rerun-procedure.md, harness `kit_source_locked`).
KIT_SOURCE_MSG = ("unattended mode: running, sourcing, copying or linking an agents-v0 kit script from outside this "
                  "checkout's .agents-v0/scripts is blocked ({}). Use `sh .agents-v0/scripts/<name>` in the checkout "
                  "the work is in.")
KIT_CORE_SCRIPTS = frozenset({"sync-feature-state.sh", "check-gate-commit.sh", "check-traceability.sh",
                              "feature-worktree.sh", "check-release-evidence.sh", "resolve-kit-root.sh",
                              "strip-test-overrides.sh", "packlib.py"})
_READERS = frozenset({"cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "diff", "cmp", "wc",
                      "sha256sum", "sha1sum", "md5sum", "shasum", "ls", "stat", "file", "readlink", "realpath",
                      "test", "[", "echo", "printf"})
_GIT_READERS = frozenset({"show", "log", "diff", "blame", "cat-file", "ls-files", "ls-tree", "status", "grep",
                          "rev-parse", "symbolic-ref", "merge-base", "describe"})
_SHELLS = frozenset({"sh", "bash", "dash", "zsh", "ksh", "busybox", ".", "source"})
_INTERPRETERS = _SHELLS | SCRIPT_INTERPRETERS


def unattended_mode() -> bool:
    """Same switch as lib.sh hook_shell_permission_ask: AGY_ALLOW_TOOLS or .agents/hooks/unattended-allow."""
    if os.environ.get("AGY_ALLOW_TOOLS", "").strip():
        return True
    here = os.path.dirname(os.path.abspath(__file__))
    cands = [os.path.join(here, "unattended-allow"),
             os.path.join(here, "..", "..", ".agents", "hooks", "unattended-allow"),
             os.path.join(".agents", "hooks", "unattended-allow"),
             os.path.join("..", ".agents", "hooks", "unattended-allow")]
    hc = os.environ.get("HOOK_CWD", "")
    if hc:
        cands.append(os.path.join(hc, ".agents", "hooks", "unattended-allow"))
    return any(os.path.isfile(c) for c in cands)


_COMMON_DIR_CACHE: dict = {}


def _git_common_dir(d: str) -> str:
    if d in _COMMON_DIR_CACHE:
        return _COMMON_DIR_CACHE[d]
    out = ""
    try:
        r = subprocess.run(["git", "-C", d, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=5, check=False)
        if r.returncode == 0:
            out = os.path.realpath(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    _COMMON_DIR_CACHE[d] = out
    return out


def _kit_script_names(roots: List[str]) -> set:
    names = set(KIT_CORE_SCRIPTS)
    here = os.path.dirname(os.path.abspath(__file__))
    for d in [os.path.join(r, ".agents-v0", "scripts") for r in roots] + [
            os.path.join(here, "..", "..", ".agents-v0", "scripts")]:
        try:
            names.update(n for n in os.listdir(d) if n.endswith((".sh", ".py")))
        except OSError:
            pass
    return names


def _dir_holds_kit(d: str) -> bool:
    for sub in (".agents-v0/scripts", "templates/.agents-v0/scripts", "scripts", ""):
        if os.path.isfile(os.path.join(d, sub, "sync-feature-state.sh")):
            return True
    return False


def _mentions_kit(path: str) -> bool:
    try:
        with open(path, "rb") as fh:
            return b"agents-v0" in fh.read(65536)
    except OSError:
        return True  # unreadable: judge by name (fail closed)


def _token_candidates(tok: str, is_git: bool) -> List[Tuple[str, bool]]:
    """(path, historical) pairs; historical marks a <rev>:<path> blob, which is never the installed copy."""
    t = tok.strip()
    for pre in ("<(", ">(", "<", ">"):
        if t.startswith(pre):
            t = t[len(pre):]
    t = t.rstrip(")").strip("'\"")
    if t.startswith("--") and "=" in t:
        t = t.split("=", 1)[1]
    out = [(t, False)]
    if is_git and ":" in t and not t.startswith("/"):
        out.append((t.split(":", 1)[1], True))
    if re.search(r"[\s'\"(]", tok):
        out += [(c, False) for c in re.findall(
            r"[\w./~${}@+-]*(?:\.agents-v0/|templates/)[\w./${}@+-]*|[\w./~${}@+-]+\.(?:sh|py)\b", tok)]
    return [(c, h) for c, h in out if c]


class _KitCtx:
    def __init__(self, hook_root: str):
        self.hook_root = hook_root
        self.hook_common = _git_common_dir(hook_root)
        eff = _project_root(_base_dir())
        self.roots = [hook_root]
        if eff != hook_root and self.hook_common and _git_common_dir(eff) == self.hook_common:
            self.roots.append(eff)
        self.allowed = []
        for r in self.roots:
            for sub in (".agents-v0/scripts", ".agents-v0/hooks"):
                d = os.path.join(r, sub)
                if os.path.isdir(d) and not os.path.islink(d):  # a linked folder (install --link) is the kit source
                    self.allowed.append(os.path.realpath(d))
        self.names = _kit_script_names(self.roots)

    def same_repo(self, d: str) -> bool:
        root = _project_root(d)
        return root in self.roots or bool(self.hook_common and _git_common_dir(root) == self.hook_common)


def _outside_kit_ref(cand: str, historical: bool, ctx: "_KitCtx") -> Optional[str]:
    """A reason when <cand> names a kit script, or a folder holding kit scripts, outside the allowed folders."""
    norm = cand.replace("\\", "/")
    base = posixpath.basename(norm.rstrip("/"))
    looks_kit = base in ctx.names or ".agents-v0/scripts" in norm or ".agents-v0/hooks" in norm
    if historical:
        return f"{cand} from git history (not the installed copy)" if looks_kit else None
    if re.search(r"[$`]", norm):
        return f"unresolved path {cand}" if looks_kit or ".agents-v0" in norm else None
    p = os.path.expanduser(norm)
    full = os.path.normpath(p if os.path.isabs(p) else os.path.join(_base_dir(), p))
    if not os.path.exists(full):
        if looks_kit and "/" in norm and not any(full.startswith(a + os.sep) for a in ctx.allowed):
            return f"{cand} (not this checkout's .agents-v0/scripts)"
        return None
    real = os.path.realpath(full)
    if os.path.isdir(real):
        if not _dir_holds_kit(real) or ctx.same_repo(real):
            return None
        return f"{cand} -> {real} holds another copy of the kit scripts"
    if _is_bundle_file(real):
        return f"{cand} -> {real} is a git bundle (it may hold the kit source)"
    in_kit_dir = "/.agents-v0/scripts/" in real or "/.agents-v0/hooks/" in real
    by_name = (os.path.basename(real) in ctx.names or base in ctx.names) and _mentions_kit(real)
    if not (in_kit_dir or by_name):
        return None
    if any(real.startswith(a + os.sep) for a in ctx.allowed):
        return None
    return f"{cand} -> {real}"


# kitfix-20261031-kit-git-source (11:25 review, unattended mode): a git bundle, a clone or a mirror of the kit holds the
#   unstripped kit source too, and git reaches it without naming any kit script: `git clone /tmp/kit.bundle x`,
#   `git fetch /tmp/kit.bundle main`, `git bundle unbundle`, `git -C ~/kit-src show HEAD:templates/...`. Unattended,
#   git may work on this project's own repository and its configured remotes only:
#   - clone, bundle, archive, submodule add, remote add/set-url, a remote.*.url / url.*.insteadOf config write: blocked;
#   - fetch, pull, ls-remote: allowed with no source or a configured remote whose URL is not a local bundle or kit
#     repository; any other path or URL is blocked;
#   - -C, --git-dir, --work-tree and GIT_DIR/GIT_WORK_TREE/GIT_OBJECT_DIRECTORY/GIT_ALTERNATE_OBJECT_DIRECTORIES
#     pointing at a bundle file, or at a repository outside this project whose objects hold the kit (a ref tip with
#     templates/.agents-v0/scripts/sync-feature-state.sh, or a kit root commit): blocked, readers (show, cat-file,
#     log) included.
#   Text and path checks only (a speed bump); the fence is that the agent user cannot read any kit copy (harness
#   kit_source_locked also refuses a readable *.bundle or kit repository).
KIT_ROOT_COMMITS = ("550da9df6dcfb46995d5af2adced25e21d372bd9", "fc4b642cb947cf38b5fea7cc1005e22d58e17eef")
KIT_PROBE_PATH = "templates/.agents-v0/scripts/sync-feature-state.sh"
GIT_SOURCE_MSG = ("unattended mode: {}. git works on this project's own repository and its configured remotes only; "
                  "a kit bundle, clone or mirror stays out of the agent's reach.")
_REPO_KIT_CACHE: dict = {}


def _is_bundle_file(p: str) -> bool:
    if not os.path.isfile(p):
        return False
    if p.endswith(".bundle"):
        return True
    try:
        with open(p, "rb") as fh:
            head = fh.read(16)
    except OSError:
        return False
    return head.startswith((b"# v2 git bundle", b"# v3 git bundle"))


def _repo_holds_kit(gd: str) -> bool:
    """True when the git dir <gd> holds a kit root commit or a ref (or HEAD/FETCH_HEAD) whose tree has the kit source."""
    if gd in _REPO_KIT_CACHE:
        return _REPO_KIT_CACHE[gd]
    found = False
    try:
        refs = subprocess.run(["git", "--git-dir", gd, "for-each-ref", "--count=500", "--format=%(objectname)"],
                              capture_output=True, text=True, timeout=10, check=False).stdout.split()
        lines = list(KIT_ROOT_COMMITS) + [f"{r}:{KIT_PROBE_PATH}" for r in refs + ["HEAD", "FETCH_HEAD"]]
        out = subprocess.run(["git", "--git-dir", gd, "cat-file", "--batch-check"], input="\n".join(lines) + "\n",
                             capture_output=True, text=True, timeout=10, check=False).stdout
        found = any(l and not l.endswith(" missing") and " " in l for l in out.splitlines())
    except (OSError, subprocess.SubprocessError):
        found = False
    _REPO_KIT_CACHE[gd] = found
    return found


def _kit_git_target(path: str, hook_common: str) -> Optional[str]:
    """A reason when <path> is a git bundle, or a repository outside this project that holds the kit."""
    p = os.path.expanduser(path.strip().strip("'\""))
    if not p:
        return None
    if re.search(r"[$`]", p):
        return f"{path}: an unresolved git repository path"
    full = os.path.normpath(p if os.path.isabs(p) else os.path.join(_base_dir(), p))
    real = os.path.realpath(full)
    if _is_bundle_file(real):
        return f"{path} is a git bundle"
    if not os.path.isdir(real):
        return None
    gd = _git_common_dir(real)
    if not gd and os.path.isfile(os.path.join(real, "HEAD")) and os.path.isdir(os.path.join(real, "objects")):
        gd = real
    if gd and gd != hook_common and _repo_holds_kit(gd):
        return f"{path} is a repository holding the kit source"
    if not gd and _dir_holds_kit(real):
        return f"{path} holds another copy of the kit scripts"
    return None


def _is_local_url(u: str) -> bool:
    return "://" not in u and not re.match(r"^[\w.+-]+@[\w.-]+:", u) and not re.match(r"^[\w.-]+:(?!/)", u)


GIT_ENV_RE = re.compile(r"(?:^|[\s;&|(])(?:export\s+|declare\s+-x\s+)?"
                        r"(GIT_DIR|GIT_WORK_TREE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_COMMON_DIR)="
                        r"(\"[^\"]*\"|'[^']*'|[^\s;&|)]+)")


def command_git_env_kit_source(cmd: str, hook_root: str) -> Optional[str]:
    """GIT_DIR=... and friends anywhere in the command (env prefixes are dropped when segments are split)."""
    hook_common = _git_common_dir(hook_root)
    for m in GIT_ENV_RE.finditer(cmd):
        for part in m.group(2).strip("'\"").split(":"):
            why = _kit_git_target(part, hook_common) if part else None
            if why:
                return f"{m.group(1)}: {why}"
    return None


def _segment_git_kit_source(seg: str, hook_root: str) -> Optional[str]:
    s = _strip_env_prefix(seg.strip())
    hook_common = _git_common_dir(hook_root)
    try:
        parts = shlex.split(s, posix=True)
    except ValueError:
        parts = s.split()
    if not parts or parts[0].split("/")[-1] != "git":
        return None
    i, cwd = 1, None
    while i < len(parts):
        a = parts[i]
        if a == "-C" and i + 1 < len(parts):
            cwd = parts[i + 1] if cwd is None or os.path.isabs(parts[i + 1]) else os.path.join(cwd, parts[i + 1])
            why = _kit_git_target(cwd, hook_common)
            if why:
                return f"git -C {why}"
            i += 2
            continue
        if a in ("--git-dir", "--work-tree") and i + 1 < len(parts):
            why = _kit_git_target(parts[i + 1], hook_common)
            if why:
                return f"git {a} {why}"
            i += 2
            continue
        if a.startswith(("--git-dir=", "--work-tree=")):
            why = _kit_git_target(a.split("=", 1)[1], hook_common)
            if why:
                return f"git {a.split('=', 1)[0]} {why}"
            i += 1
            continue
        if a == "-c" and i + 1 < len(parts):
            if re.match(r"(?i)^(remote\..+\.(url|pushurl)|url\..+\.insteadof)=", parts[i + 1]):
                return f"git -c {parts[i + 1].split('=', 1)[0]} changes where git fetches from"
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        break
    sub = parts[i] if i < len(parts) else ""
    args = parts[i + 1:]
    pos = [x for x in args if not x.startswith("-")]
    if sub in ("clone", "bundle", "archive"):
        return f"git {sub} is not used unattended"
    if sub == "submodule" and pos[:1] == ["add"]:
        return "git submodule add is not used unattended"
    if sub == "remote" and pos[:1] and pos[0] in ("add", "set-url"):
        return f"git remote {pos[0]} is not used unattended"
    if sub == "config" and any(re.match(r"(?i)^(remote\..+\.(url|pushurl)|url\..+\.insteadof)$", x) for x in pos) \
            and (len(pos) >= 2 or any(x in ("--add", "--replace-all") for x in args)):
        return "a git config write of a remote URL is not used unattended"
    if sub in ("fetch", "pull", "ls-remote") and pos:
        src = pos[0]
        base = os.path.join(_base_dir(), cwd) if cwd and not os.path.isabs(cwd) else (cwd or _base_dir())
        try:
            url = subprocess.run(["git", "-C", base, "config", "--get", f"remote.{src}.url"], capture_output=True,
                                 text=True, timeout=5, check=False).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            url = ""
        if not url:
            return f"git {sub} from {src}, which is not a configured remote of this project"
        if _is_local_url(url):
            u = url[len("file://"):] if url.startswith("file://") else url
            if not os.path.isabs(u):
                u = os.path.join(base, u)
            why = _kit_git_target(u, hook_common)
            if why:
                return f"git {sub} {src}: {why}"
    return None


def _segment_reads_stdin_program(seg: str) -> bool:
    try:
        parts = shlex.split(_strip_env_prefix(seg.strip()), posix=True)
    except ValueError:
        parts = seg.split()
    if not parts or parts[0].split("/")[-1] not in _INTERPRETERS:
        return False
    rest = []
    for a in parts[1:]:
        if a == "--":
            break
        if a.startswith("-") and a != "-":
            if not a.startswith("--") and "s" in a[1:]:
                return True  # sh -s: the script comes from stdin
            continue
        rest.append(a)
    return not rest or rest[0] == "-"


def _segment_uses_outside_kit(seg: str, stdin_exec: bool, hook_root: str) -> Optional[str]:
    s = _strip_env_prefix(seg.strip())
    try:
        parts = shlex.split(s, posix=True)
    except ValueError:
        parts = s.split()
    if not parts:
        return None
    bin0 = parts[0].split("/")[-1]
    out_redirect = re.search(r"(?:^|[^0-9&>])>{1,2}\s*(?!&|/dev/null\b)\S", s)
    reader = (bin0 in _READERS or (bin0 == "git" and _git_subcommand(parts) in _GIT_READERS)) \
        and not stdin_exec and not out_redirect
    if reader:
        return None
    ctx = _KitCtx(hook_root)
    for tok in parts:
        for cand, hist in _token_candidates(tok, bin0 == "git"):
            why = _outside_kit_ref(cand, hist, ctx)
            if why:
                return why
    return None

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

    kpath = _segment_changes_kit_container(seg)
    if kpath:
        return "block", KIT_CONTAINER_MSG.format(kpath)

    # MEM-13: a shell write to lessons.md / lessons-archive.md from a story checkout is blocked.
    lpath = _segment_writes_matching_path(seg, lambda p: lessons_story_block(p) is not None)
    if lpath:
        return "block", lessons_story_block(lpath) or "Lessons memory is read-only on a story branch."

    apath = _segment_writes_ask_path(seg)
    if apath:
        return "ask", apath[1]

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
        r"\b(npm|pnpm|yarn|poetry|uv|cargo)\s+publish\b", low
    ) or re.search(r"\bdotnet\s+nuget\s+push\b", low) or re.search(
        r"\btwine\s+upload\b", low
    ):
        return "ask", "registry publish requires explicit user approval."
    if re.search(r"\bmvn\s+.*\bdeploy\b", low) or re.search(
        r"\bgradle\s+.*\bpublish\b", low
    ):
        return "ask", "artifact deploy/publish requires explicit user approval."
    if re.search(r"^(?:(?:sh|bash|dash)\s+)?\S*feature-worktree\.sh\b", low):
        return "ask", "creating a feature branch and worktree requires explicit user authorization."
    if re.search(r"^(?:(?:sh|bash|dash|zsh)\s+)?\S*activate-stack-pack\.sh\b", low) and "--force" in low:
        return "ask", "replacing the bound stack pack rewrites rules and skills; requires explicit user approval."

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
        # The kit's git hooks (.agents-v0/hooks, gate.sh) are the deterministic fence against drift.
        # An agent must not switch them off; a person can still do so in their own terminal.
        sub_idx = parts.index(sub) if sub in parts else len(parts)
        if any(p.startswith("core.hooksPath") or p.startswith("core.hookspath") for p in parts[1:sub_idx]):
            return "block", "overriding core.hooksPath bypasses the delivery gate hooks; not allowed for an agent."
        if sub == "config":
            cfg_args = parts[sub_idx + 1 :]
            keys = [i for i, p in enumerate(cfg_args) if p.lower().startswith("core.hookspath")]
            if keys and (
                any(a.startswith("--unset") or a in ("--add", "--replace-all") for a in cfg_args)
                or any(i + 1 < len(cfg_args) for i in keys)
                or any("=" in cfg_args[i] for i in keys)
            ):
                return "ask", "changing core.hooksPath turns the delivery gate hooks on or off; requires explicit user approval."
        if sub in ("commit", "push", "merge", "rebase", "cherry-pick", "revert", "am"):
            sub_args = parts[sub_idx + 1 :]
            if "--no-verify" in sub_args or (sub == "commit" and any(re.fullmatch(r"-[a-zA-Z]*n[a-zA-Z]*", a) for a in sub_args)):
                return "block", "--no-verify skips the delivery gate hooks; fix the failing gate instead (ai-agent-conduct.mdc)."
        if sub == "push":
            p_args = parts[parts.index(sub) + 1 :] if sub in parts else []
            deleting = any(a in ("-d", "--delete") for a in p_args)
            if any((deleting and re.match(r"^(?:refs/heads/)?(?:feature|maintain)/", a))
                   or re.match(r"^\+?:(?:refs/heads/)?(?:feature|maintain)/", a) for a in p_args):
                return "block", KEEP_BRANCH_MSG
            for tok in parts[parts.index(sub) + 1 :] if sub in parts else []:
                if tok in ("--force", "-f", "--force-with-lease") or tok.startswith(
                    "+"
                ) or "/+" in tok:
                    return "block", "git force-push is not allowed (ai-agent-conduct.mdc)."
            return "ask", "git push requires explicit user approval."
        if sub == "commit":
            # kitfix-20261031-gate-commit: one commit per approved gate; a gate commit is never amended.
            # kitfix-20261031-no-amend: git also accepts the abbreviations --am, --ame, --amen.
            if any(a in ("--amend", "--am", "--ame", "--amen") for a in parts[sub_idx + 1 :]):
                return "ask", "git commit --amend rewrites a commit; gate commits are never amended (make a new commit)."
            if _commit_paths_are_evidence(parts):
                return "allow", ""
            return "ask", "git commit requires explicit user approval."
        # kitfix-20261031-guard-override: moving a branch rewrites committed gates (a soft/mixed reset to an
        #   earlier commit followed by a commit is an amend). Unstaging (git reset, git reset [HEAD] -- <path>) is fine.
        if sub == "reset" and "--hard" not in parts:
            r_args = parts[sub_idx + 1 :]
            pre = r_args[: r_args.index("--")] if "--" in r_args else r_args
            if any(a in ("--soft", "--mixed", "--keep", "--merge") for a in pre) or any(
                not a.startswith("-") and a != "HEAD" and (re.search(r"[~^]|@\{", a) or re.fullmatch(r"[0-9a-fA-F]{7,40}", a) or a in ("ORIG_HEAD", "FETCH_HEAD"))
                for a in pre
            ):
                return "ask", "git reset to another commit moves the branch and can rewrite committed gates; requires explicit user approval."
        if sub in ("update-ref", "filter-branch", "filter-repo", "replace"):
            return "ask", f"git {sub} rewrites refs or history; requires explicit user approval."
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
            # kitfix-20261031-guard-override: a phase tag (<phase>-v<n>) is never moved; a revision gets a new tag.
            if any(a in ("-f", "--force") or (re.fullmatch(r"-[a-zA-Z]*f[a-zA-Z]*", a) and not a.startswith("--")) for a in args):
                return "block", "git tag -f/--force moves an existing tag; phase tags are never moved (tag the revision <phase>-v<n+1>)."
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
            # kitfix-20261031-keep-branches: story branches (feature/*, maintain/*) are kept after release for
            #   reference and backtracking; the agent never deletes or renames one (a person can, in their own terminal).
            if any(f in ("-d", "-D", "--delete", "-m", "-M", "--move") or re.fullmatch(r"-[a-zA-Z]*[dDmM][a-zA-Z]*", f) for f in flags) \
                    and any(re.match(r"^(?:refs/heads/)?(?:feature|maintain)/", a) for a in positional):
                return "block", KEEP_BRANCH_MSG
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
    """A reports-only commit (build/ or verify/ docs, state.json, phase-result.md, and companion artifact) does not ask again."""
    if "--" not in parts:
        return False
    sep_idx = parts.index("--")
    for tok in parts[2:sep_idx]:
        if tok in ("-a", "--all", "-i", "--include", "--amend", "--am", "--ame", "--amen") or (
            tok.startswith("-") and not tok.startswith("--") and ("a" in tok[1:] or "i" in tok[1:])
        ):
            return False
    paths = [p for p in parts[sep_idx + 1 :] if p != "--"]
    if not paths:
        return False
    has_evidence = False
    for path in paths:
        raw = path.replace("\\", "/").strip()
        if raw.startswith("/") or raw.startswith("-"):
            return False
        norm = posixpath.normpath(raw).lstrip("./")
        if norm.startswith(".."):
            return False
        if (
            norm.startswith("docs/agents-v0/build/")
            or norm.startswith("docs/agents-v0/verify/")
            or (norm.startswith("docs/agents-v0/requirements/") and norm.endswith(".state.json"))
            or (norm.startswith("docs/agents-v0/requirements/") and norm.endswith(".phase-result.md"))
            or (norm.startswith("docs/agents-v0/maintain/") and norm.endswith("state.json"))
            or (norm.startswith("docs/agents-v0/maintain/") and norm.endswith("phase-result.md"))
            or norm in ("docs/agents-v0/onboarding/state.json", "docs/agents-v0/program.state.json")
        ):
            has_evidence = True
        elif (
            (norm.startswith("docs/agents-v0/requirements/") and norm.endswith(".md"))
            or (norm.startswith("docs/agents-v0/maintain/") and norm.endswith("/note.md"))
            or norm in ("docs/agents-v0/lessons.md", "docs/agents-v0/lessons-archive.md")
        ):
            continue
        else:
            return False
    return has_evidence


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


def _heredoc_writes_protected(cmd: str) -> Optional[str]:
    if not re.search(r"\b(?:python3?|node|perl|ruby)\b[^\n|;&]*(?:\s-\s*)?<<-?\s*['\"]?\w+", cmd):
        return None
    if not SCRIPT_WRITE_HINT.search(cmd):
        return None
    for lit in re.findall(r"['\"]([^'\"\n]+)['\"]", cmd):
        if is_protected_path(lit):
            return lit
    return None


def _heredoc_writes_ask_path(cmd: str) -> Optional[Tuple[str, str]]:
    if not re.search(r"\b(?:python3?|node|perl|ruby)\b[^\n|;&]*(?:\s-\s*)?<<-?\s*['\"]?\w+", cmd):
        return None
    if not SCRIPT_WRITE_HINT.search(cmd):
        return None
    for lit in re.findall(r"['\"]([^'\"\n]+)['\"]", cmd):
        act, msg = classify_path(lit)
        if act == "ask" or (act == "block" and LESSONS_PATH_RE.search(lit.replace("\\", "/"))):
            return lit, msg
    return None


def _cd_target(seg: str) -> Optional[str]:
    m = re.fullmatch(r"\s*cd\s+(?:--\s+)?(['\"]?)([^'\"\s;&|]+)\1\s*", seg)
    return m.group(2) if m else None


def classify_command(cmd: str) -> Tuple[Action, str]:
    global _BASE_DIR
    _BASE_DIR = None
    if GUARD_OVERRIDE_RE.search(cmd):
        return "block", GUARD_OVERRIDE_MSG
    if TEST_OVERRIDES_RE.search(cmd):
        return "block", TEST_OVERRIDES_MSG
    hp = _heredoc_writes_protected(cmd)
    if hp:
        return "block", f"Protected kit/CI path cannot be modified via shell: {hp}"
    segments = split_segments(cmd)
    # MEM-13: "cd <dir> && ..." moves the base for relative paths, so the lessons branch check reads
    # the worktree the command really writes in.
    lead = _cd_target(segments[0]) if segments else None
    if lead:
        _BASE_DIR = os.path.normpath(os.path.join(_base_dir(), os.path.expanduser(lead)))
    ha = _heredoc_writes_ask_path(cmd)
    if ha and LESSONS_PATH_RE.search(ha[0].replace("\\", "/")) and lessons_story_block(ha[0]):
        return "block", ha[1]
    _BASE_DIR = None
    if not segments:
        return ("ask", ha[1]) if ha else ("allow", "")
    worst: Action = "ask" if ha else "allow"
    msg = ha[1] if ha else ""
    unattended = unattended_mode()
    stdin_exec = unattended and any(_segment_reads_stdin_program(sg) for sg in segments)
    hook_root = _project_root(_base_dir()) if unattended else ""
    if unattended:
        why = command_git_env_kit_source(cmd, hook_root)
        if why:
            return "block", GIT_SOURCE_MSG.format(why)
    for seg in segments:
        cd_to = _cd_target(seg)
        if cd_to:
            _BASE_DIR = os.path.normpath(os.path.join(_base_dir(), os.path.expanduser(cd_to)))
            continue
        if unattended:
            why = _segment_uses_outside_kit(seg, stdin_exec, hook_root)
            if why:
                return "block", KIT_SOURCE_MSG.format(why)
            why = _segment_git_kit_source(seg, hook_root)
            if why:
                return "block", GIT_SOURCE_MSG.format(why)
        action, message = classify_segment(seg)
        if action == "block":
            return "block", message
        if action == "ask" and worst != "block":
            worst = "ask"
            msg = message or msg
    # sudo is unwrapped when segments are split, and a pipe splits a download from its interpreter,
    # so both are judged on the whole command. A block above still wins.
    if SUDO_RE.search(cmd):
        return "block", (
            "sudo/doas is not used by the kit. Do not escalate privileges or install host packages; "
            "report the missing tool and stop (for a database, run .agents-v0/scripts/check-database-runtime.sh)."
        )
    if PKG_INSTALL_RE.search(cmd):
        return "block", (
            "system package installs are not allowed. Report the missing tool and stop "
            "(for a database, run .agents-v0/scripts/check-database-runtime.sh)."
        )
    if DOCKER_TCP_RE.search(cmd):
        return "block", (
            "a Docker/Podman TCP API (DOCKER_HOST=tcp://, :2375/:2376) is root-equivalent and is not used. "
            "Run .agents-v0/scripts/check-database-runtime.sh and follow its result."
        )
    if PIPE_TO_INTERPRETER_RE.search(cmd):
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
    re.compile(r"(^|/)\.cursor/cli\.json$"),
    re.compile(r"(^|/)\.cursor/hooks/"),
    re.compile(r"(^|/)\.cursor/rules/"),
    re.compile(r"(^|/)\.cursor/agents/"),
    re.compile(r"(^|/)\.cursor/(commands|skills)/"),
    re.compile(r"(^|/)\.agents/hooks\.json$"),
    re.compile(r"(^|/)\.agents/hooks/"),
    re.compile(r"(^|/)\.agents/rules/"),
    re.compile(r"(^|/)\.agents/agents/"),
    re.compile(r"(^|/)\.agents/(commands|skills)/"),
    re.compile(r"(^|/)\.agents-v0/ci/[^/]+\.(sh|py|json)$"),
    re.compile(r"(^|/)\.agents-v0/scripts/[^/]+\.(sh|py)$"),
    re.compile(r"(^|/)\.agents-v0/packs/.+\.(json|sh|py)$"),
    re.compile(r"(^|/)\.agents-v0/hooks/[^/]+$"),
    re.compile(r"(^|/)\.agents-v0/policy\.conf$"),  # kitfix-20261031-installed-no-overrides: trace mode
    re.compile(r"(^|/)\.git/hooks/"),
    re.compile(r"(^|/)\.gitlab-ci\.yml$"),
    re.compile(r"(^|/)\.gitlab/"),
    re.compile(r"(^|/)CODEOWNERS$"),
    re.compile(r"(^|/)core/(common|[a-z]+)/hooks/"),
    re.compile(r"(^|/)AGENTS\.md$"),
    re.compile(r"(^|/)docs/agents-v0/requirements/[^/]+\.state\.json$"),
    re.compile(r"(^|/)docs/agents-v0/maintain/[^/]+/state\.json$"),
    re.compile(r"(^|/)docs/agents-v0/onboarding/state\.json$"),
    re.compile(r"(^|/)docs/agents-v0/program\.state\.json$"),
]


def is_protected_path(path: str) -> bool:
    if not path:
        return False
    raw = path.replace("\\", "/").strip().strip("'\"")
    norm = posixpath.normpath(raw) if raw else raw
    for candidate in (raw, norm):
        for pat in PROTECTED_PATH_PATTERNS:
            if pat.search(candidate):
                return True
    return False


# MEM-13: a story checkout (branch feature/* or maintain/*) must never write the cross-story lessons
# memory. The branch is read from the edited file's own worktree (git -C <dir of file>), so an agent
# working in ../<repo>-<feature> is caught even when the hook runs from the main checkout.
LESSONS_PATH_RE = re.compile(r"(^|/)docs/agents-v0/lessons(-archive)?\.md$")
STORY_BRANCH_RE = re.compile(r"^(feature|maintain)/")
_BASE_DIR: Optional[str] = None  # directory relative paths start from (cd prefix or payload cwd)


def _base_dir() -> str:
    for cand in (_BASE_DIR, os.environ.get("HOOK_CWD", "")):
        if cand and os.path.isdir(cand):
            return cand
    return os.getcwd()


def _existing_dir_of(path: str) -> str:
    p = os.path.expanduser(path.strip().strip("'\""))
    if not os.path.isabs(p):
        p = os.path.join(_base_dir(), p)
    d = os.path.dirname(os.path.normpath(p))
    while d and not os.path.isdir(d):
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return d or _base_dir()


def _branch_of(path: str) -> str:
    """Current branch of the worktree that holds <path> ('' when unknown, detached, or not git)."""
    try:
        r = subprocess.run(["git", "-C", _existing_dir_of(path), "symbolic-ref", "--short", "-q", "HEAD"],
                           capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def lessons_story_block(path: str) -> Optional[str]:
    """Block message when <path> is lessons.md / lessons-archive.md inside a story checkout."""
    norm = path.replace("\\", "/").strip().strip("'\"")
    if not LESSONS_PATH_RE.search(norm):
        return None
    branch = _branch_of(norm)
    if not STORY_BRANCH_RE.match(branch):
        return None
    return (
        f"Lessons memory is read-only on story branch {branch}: {os.path.basename(norm)} changes only in the "
        "integration checkout, where the release-manager appends the lessons the user accepted. Write "
        "candidates in the phase-result '## Lessons' section instead."
    )


def classify_path(path: str) -> Tuple[Action, str]:
    if is_protected_path(path):
        return (
            "block",
            f"Protected kit/CI path cannot be modified by agents: {path}",
        )
    norm = path.replace("\\", "/")
    if re.search(r"(^|/)docs/agents-v0/requirements/.+\.md$", norm):
        if norm.endswith(".phase-result.md"):
            return "allow", ""
        return (
            "ask",
            "Delivery artifact edit — do not change Delivery approvals without explicit human gate approval.",
        )
    # MEM-08: the cross-story lessons memory changes only at the local-release gate, in the
    # integration checkout, with lessons the user accepted. Any other edit (for example a phase
    # agent on a story branch writing straight into lessons.md) asks the human first.
    # MEM-13: on a story branch the edit is blocked; in the integration checkout it stays "ask", which
    # pre-edit.sh records as allow-flagged (the release-manager's file-edit append works unattended) and
    # which a shell write still asks for.
    if LESSONS_PATH_RE.search(norm):
        blocked = lessons_story_block(norm)
        if blocked:
            return "block", blocked
        return (
            "ask",
            "Lessons memory edit: only the release-manager appends user-accepted lessons in the "
            "integration checkout after the local-release merge. Story phases write candidates in "
            "the phase-result '## Lessons' section instead.",
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
