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
# Design: DA (onboard redo): the approval record lives outside the repo in ~/.agents-v0-approvals/<repo id>/ and is
#   written only by `guard-common.sh approve`, which the user runs in their own terminal. An agent never touches
#   the folder (any form: ~, $HOME, ${HOME}, the expanded home path) and never runs approve.
APPROVALS_DIR_RE = re.compile(
    r"\.agents-v0-(?:approvals\b|[a-z]*[*?\[]|\$\{?[A-Za-z_])"
    r"|agents-v0-(?:approvals\b|a[a-z]*[*?\[]|\$\{?[A-Za-z_])"
)
APPROVALS_DIR_MSG = ("the approval folder (~/.agents-v0-approvals) is reserved for the user: only `guard-common.sh approve`, run by "
                     "the user in their own terminal, writes it. An agent never reads, writes or lists it. Ask the user to approve.")
APPROVE_RUN_RE = re.compile(
    r"(?:\bguard-common(?:\.sh)?\b|\.agents-v0/scripts/(?:\$\{?[A-Za-z_]\w*\}?|[^\s;&|/]*[*?\[]))[^\n;&|]*\sapprove\b"
    r"|\bgc_approve\b"
)
APPROVE_RUN_MSG = ("`guard-common.sh approve` is the user's own step, run in their own terminal outside Cursor. "
                   "An agent never runs it. Tell the user the work is ready for approval and stop.")
TEST_OVERRIDES_MSG = ("installing the kit with its test overrides (install.sh --test-overrides) is for the kit's own test "
                      "suites only; an agent never reinstalls or strips the kit scripts. Report the problem instead.")


def _deobfuscate_shell_cmd(cmd: str) -> str:
    """Expand inline shell variable assignments, collapse string concatenations, and strip mid-token quotes."""
    out = cmd
    # 1. Collapse Python/JS/shell adjacent or '+'-joined string literals: 'a'+'b', "a"+"b", 'a''b', "a""b"
    for _ in range(4):
        nxt = re.sub(r"(['\"])\s*\+\s*\1", "", out)
        nxt = re.sub(r"(['\"])([^'\"\n]*)\1(['\"])([^'\"\n]*)\3", r"\1\2\4\1", nxt)
        if nxt == out:
            break
        out = nxt
    # 2. Collect simple inline VAR=val assignments and expand $VAR / ${VAR}
    assigns: dict[str, str] = {}
    for m in re.finditer(r"(?:^|[;&|\n()]\s*|\s+)([A-Za-z_][A-Za-z0-9_]*)=('[^']*'|\"[^\"]*\"|[^\s;&|'\"]+)", out):
        k, v = m.group(1), m.group(2)
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
            v = v[1:-1]
        assigns[k] = v
    if assigns:
        for _ in range(3):
            changed = False
            for k, v in assigns.items():
                expanded = re.sub(rf"\$\{{{re.escape(k)}\}}|\${re.escape(k)}\b", lambda _m, rep=v: rep, out)
                if expanded != out:
                    out = expanded
                    changed = True
            if not changed:
                break
    # 3. Strip quotes/backslashes embedded inside path/identifier tokens (e.g. guard-"common".sh -> guard-common.sh)
    out = re.sub(r"(?<=[A-Za-z0-9_./-])(['\"])([A-Za-z0-9_./-]+)\1", r"\2", out)
    out = re.sub(r"(['\"])([A-Za-z0-9_./-]+)\1(?=[A-Za-z0-9_./-])", r"\2", out)
    out = re.sub(r"\\([A-Za-z0-9_.-])", r"\1", out)
    return out


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


# kitfix-20261031-escalation (Sonnet review 12:31, finding 3): SUDO_RE only matched a bare sudo/doas after a
#   separator, so `env sudo`, `xargs sudo`, `command sudo`, `nohup sudo`, `\sudo` and `/usr/bin/sudo` passed. Every
#   segment goes through _expand_wrapper, also the inner command of each wrapper it unwraps (env, command, nohup,
#   time, nice, stdbuf, exec, builtin, timeout, xargs, setsid, ionice, sh -c, $(...)), so the program name is recorded
#   here, as its basename with a leading backslash removed. classify_command blocks sudo/doas/run0 in every mode and
#   su/pkexec in unattended mode (the kit never needs them; the harness's own `su - e2e` runs outside the agent).
ESCALATORS_ALL_MODES = frozenset({"sudo", "doas", "run0"})
ESCALATORS_UNATTENDED = frozenset({"su", "pkexec"})
_ESCALATIONS: List[str] = []
ESCALATION_MSG = ("{} is not used by the kit. Do not escalate privileges or switch user; report the missing tool "
                  "or permission and stop (for a database, run .agents-v0/scripts/check-database-runtime.sh).")
_XARGS_OPTS_WITH_ARG = frozenset({"-n", "-P", "-L", "-l", "-d", "-E", "-e", "-s", "-a", "--max-args", "--max-procs",
                                  "--max-lines", "--delimiter", "--eof", "--max-chars", "--arg-file"})


def _expand_wrapper(seg: str) -> List[str]:
    seg = _strip_env_prefix(seg)
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return [seg]
    esc = parts[0].lstrip("\\").split("/")[-1]
    if esc in ESCALATORS_ALL_MODES or esc in ESCALATORS_UNATTENDED:
        _ESCALATIONS.append(esc)
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
    if bin0 in ("sudo", "doas", "command", "nohup", "time", "nice", "stdbuf", "exec", "builtin", "setsid", "ionice",
                "run0", "pkexec") and len(parts) >= 2:
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
        i = 1
        while i < len(parts) and parts[i].startswith("-"):
            if parts[i] in ("-I", "--replace", "-i") or parts[i] in _XARGS_OPTS_WITH_ARG:
                i += 2
            else:
                i += 1
        if i < len(parts):
            return split_segments(" ".join(parts[i:]))
        return [seg]
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
    # N-1 final round: Python start-up paths are judged by _segment_writes_py_startup (it runs first and knows that a
    #   cp/rsync source is a read); here they would ask for a backup copy out of the user site in supervised mode.
    target = _segment_writes_matching_path(
        seg, lambda p: not _is_py_startup_path(p) and classify_path(p)[0] == "ask")
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
        collapsed = tok
        for _ in range(4):
            nxt = re.sub(r"(['\"])\s*\+\s*\1", "", collapsed)
            nxt = re.sub(r"(['\"])([^'\"\n]*)\1\s*\+\s*(['\"])([^'\"\n]*)\3", r"\1\2\4\1", nxt)
            if nxt == collapsed:
                break
            collapsed = nxt
        lits.extend(re.findall(r"['\"]([^'\"]+)['\"]", collapsed))
        if collapsed != tok:
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
# Carried from 8d89d6f1/64da9195 (workflow-fixes-onboard), Design: D1.
KIT_CONTAINER_RE = re.compile(
    r"(^|/)(?:\.agents-v0(?:/(?:scripts|hooks|ci|packs)(?:/.*)?|/policy\.conf|/secret-allowlist\.json)?"
    r"|\.agents(?:/(?:hooks|rules|agents|commands|skills)(?:/.*)?|/hooks\.json)?"
    r"|\.cursor(?:/(?:hooks|rules|agents|commands|skills)(?:/.*)?|/hooks\.json|/cli\.json)?)/*$"
)
KIT_CONTAINER_MSG = ("the kit's guard files (.agents-v0/scripts, .agents-v0/hooks, .agents-v0/policy.conf, "
                     ".agents-v0/secret-allowlist.json, the agent "
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
    return _segment_changes_container(seg, _is_kit_container)


def _segment_changes_container(seg: str, _is_kit_container) -> Optional[str]:
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


# kitfix-20261031-harness-lock (Sonnet review 12:31, finding 2; unattended mode, a speed bump): the agent runs as the
#   same OS user as the harness runner, so it could edit the harness (scripts, fixtures/approvals.tsv) or the run
#   root's control files (status/pending-turn.json holds the per-turn allowlist agy-ws-exec.sh applies; results/,
#   evidence/, snapshots/, agy-driver/). Writing, removing, renaming or replacing anything there is blocked: a
#   harness-v3 folder, an agents-v0-e2e/run-*/ run root except its work/ (the agent's checkouts), refs/e2e-test-plan
#   scripts and fixtures, and $PLAN_DIR / $TEST_ROOT (minus work/) when the turn's environment names them. Setting
#   or unsetting AGY_ALLOW_TOOLS or CURSOR_CONFIG_DIR is blocked too. The fence is the procedure: the harness is
#   root-owned (/opt/harness-v3) and the preflight refuses a harness the agent user can write (harness_locked).
HARNESS_PATH_RE = re.compile(
    r"(^|/)harness-v3(?:/|$)"
    r"|(^|/)agents-v0-e2e/run-[^/]+/*$"
    r"|(^|/)agents-v0-e2e/run-[^/]+/(?!work(?:/|$))[^/]"
    r"|(^|/)agents-v0-e2e/*$"
    r"|(^|/)refs/e2e-test-plan/(?:scripts|fixtures|tests)(?:/|$)"
)
HARNESS_MSG = ("unattended mode: the e2e harness and its run-root control files ({}) are not the agent's to change; "
               "work only in your checkout under work/. Report the problem instead.")
# kitfix-20261031-ws-exec (Sasuke round 2): also AGY_TURN_WS and TEST_ROOT, which agy-ws-exec.sh trusts, and the
#   spellings `typeset +x NAME`, `declare +x NAME`, `export -n NAME` and an indirect `unset ${A}_TOOLS`.
_ALLOW_VAR_NAMES = r"(?:AGY_ALLOW_TOOLS|CURSOR_CONFIG_DIR|AGY_TURN_WS|TEST_ROOT)"
ALLOW_VAR_RE = re.compile(
    r"\b" + _ALLOW_VAR_NAMES + r"\s*\+?="
    r"|(?:\bunset|(?:^|\s)-u|--unset[=\s])\s*(?:\w+\s+)*" + _ALLOW_VAR_NAMES + r"\b"
    r"|\b(?:typeset|declare|export|readonly|local)\b[^;&|\n]*\b" + _ALLOW_VAR_NAMES + r"\b"
    r"|\bunset\b[^;&|\n]*\$"
)
ALLOW_VAR_MSG = ("unattended mode: the per-turn allowlist and turn context (AGY_ALLOW_TOOLS, CURSOR_CONFIG_DIR, AGY_TURN_WS, "
                 "TEST_ROOT) are set by the harness only; an agent command must not set, unset or un-export them "
                 "(nor unset a variable by an expanded name).")
ENV_I_MSG = ("unattended mode: `env -i` / `env --ignore-environment` drops the per-turn allowlist the hooks rely on; "
             "run the command without it.")
WS_EXEC_MSG = ("unattended mode: agy-ws-exec.sh {} (kitfix-20261031-ws-exec). Run it with this turn's TEST_ROOT and "
               "a --ws under $TEST_ROOT/work only.")


ENV_I_RE = re.compile(
    r"(?:^|[^\w./-])(?:/usr/bin/|/bin/|\\)?env\s+"
    r"(?:(?:-u|--unset|-C|--chdir)\s+\S+\s+|[A-Za-z_]\w*=\S*\s+|-[A-Za-hj-zA-Z]+\s+|--[a-z-]+=\S+\s+)*"
    r"(?:-[A-Za-z]*i[A-Za-z]*|--ignore-environment|-)(?=\s|$)"
)


def _segment_ws_exec(seg: str) -> Tuple[Optional[str], Optional[str]]:
    """agy-ws-exec.sh in a segment: (refusal reason, inner command). The inner command (its quoted argument) is
    classified like any other command; --test-root must be this turn's TEST_ROOT and --ws under $TEST_ROOT/work."""
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        return None, None
    idx = next((i for i, a in enumerate(parts) if a.split("/")[-1] == "agy-ws-exec.sh"), None)
    if idx is None:
        return None, None
    tr_env = os.environ.get("TEST_ROOT", "").strip()
    rest = parts[idx + 1:]
    tr, ws = None, None
    while rest and rest[0] in ("--test-root", "--ws"):
        if len(rest) < 2:
            return "has an option without a value", None
        if rest[0] == "--test-root":
            tr = rest[1]
        else:
            ws = rest[1]
        rest = rest[2:]
    real = lambda x: os.path.realpath(os.path.join(_base_dir(), os.path.expanduser(x)))
    if tr is not None and (not tr_env or real(tr) != os.path.realpath(tr_env)):
        return f"--test-root {tr} is not this turn's TEST_ROOT", None
    if ws is not None:
        root = tr_env or tr or ""
        work = os.path.join(os.path.realpath(root), "work") if root else ""
        if "$" in ws or not work or not (real(ws) == work or real(ws).startswith(work + "/")):
            return f"--ws {ws} is not under $TEST_ROOT/work", None
    return None, " ".join(rest)


def _harness_roots() -> List[Tuple[str, str]]:
    roots = []
    pd = os.environ.get("PLAN_DIR", "").strip()
    if pd and os.path.isdir(pd):
        roots.append((os.path.realpath(pd), ""))
    tr = os.environ.get("TEST_ROOT", "").strip()
    if tr and os.path.isdir(tr):
        roots.append((os.path.realpath(tr), os.path.join(os.path.realpath(tr), "work")))
    return roots


def _is_harness_path(p: str) -> bool:
    raw = os.path.expandvars(os.path.expanduser(p.replace("\\", "/").strip().strip("'\"")))
    if not raw:
        return False
    cands = [raw, posixpath.normpath(raw)]
    g = re.search(r"[*?\[]", raw)
    if g:
        prefix = raw[: g.start()]
        cands.append(prefix.rstrip("/") if prefix.endswith("/") else posixpath.dirname(prefix))
    if "$" not in raw:
        full = os.path.normpath(cands[-1] if os.path.isabs(cands[-1]) else os.path.join(_base_dir(), cands[-1]))
        try:
            full = os.path.join(os.path.realpath(os.path.dirname(full)), os.path.basename(full)) \
                if os.path.basename(full) else os.path.realpath(full)
        except OSError:
            pass
        cands.append(full)
        for root, carve in _harness_roots():
            if (full == root or full.startswith(root + "/")) and not (
                    carve and (full == carve or full.startswith(carve + "/"))):
                return True
    return any(c and HARNESS_PATH_RE.search(c) for c in cands)


# kitfix-20261031-n1 (Sasuke N-1, approved in design review 2026-10-31 16:36 Asia/Manila): Python start-up
#   files run inside every Python process of the user that owns them: the user site (~/.local/lib/python*/,
#   with usercustomize.py and *.pth files), a python* in ~/.local/bin (often first on PATH), and any
#   usercustomize.py / sitecustomize.py or site-packages *.pth. The hooks no longer load them (-I -S, a pinned
#   interpreter), so this is the second line: a write there is blocked unattended and asks in supervised mode.
#   This closes Python start-up injection only (kitfix-20261031-jn4 wording); the shell and session start-up files
#   follow below (JN-4).
#   Only spellings the write detection already knows are caught (dd of=, sponge, tar -x are H-5).
PY_STARTUP_RE = re.compile(
    r"(^|/)\.local/lib/python[^/]*(?:/|$)"
    r"|(^|/)\.local/bin/python[^/]*$"
    r"|(^|/)(?:usercustomize|sitecustomize)\.py$"
    r"|(^|/)(?:site|dist)-packages/[^/]+\.pth$"
)
PY_STARTUP_MSG = ("Python start-up file or user site ({}): code there runs inside every Python process of this user, "
                  "the kit hooks included. Blocked unattended; in supervised mode approve only if you asked for it.")
# JN-6 (Jiraiya's N-1 review): the Edit/Write tool cannot prompt. pre-edit.sh turns "ask" into a recorded allow
#   (Cursor does not enforce "ask" for preToolUse), so for a start-up path an edit is blocked in both modes. An agent
#   never needs the Edit tool there; a shell write still asks in supervised mode, and a developer edits in a terminal.
PY_STARTUP_EDIT_MSG = ("Python start-up file or user site ({}): code there runs inside every Python process of this "
                       "user. The edit tool cannot ask for approval, so this edit is blocked in every mode; if you "
                       "need the change, make it yourself in a terminal.")


# kitfix-20261031-jn4 (Jiraiya JN-4 with M-1, approved in design review 2026-11-01 00:04 Asia/Manila): N-1 closes Python
#   start-up injection only. The shell and session start-up files of the agent user are the same kind of file: the
#   login shell, the desktop session, systemd --user, pam or launchd read them before the IDE or agy starts, so a
#   PATH, LD_PRELOAD, LD_LIBRARY_PATH or other variable written there reaches every later process, the kit hooks
#   included (the loader acts before a hook's first line, so -I -S cannot help). They get the same rule as Python's
#   start-up files: a shell write asks in supervised mode and is blocked unattended; an edit-tool write is blocked in
#   both modes (JN-6). Only paths in the agent user's home count (a project's docker/.bashrc is not a start-up file).
#   ~/.bash* covers .bashrc, .bash_profile, .bash_login, .bash_logout, .bash_aliases; zsh reads .zshenv, .zprofile,
#   .zshrc, .zlogin and .zlogout from ~ (a ZDOTDIR elsewhere is a known limit).
SHELL_STARTUP_REL_RE = re.compile(
    r"^(?:\.profile|\.bash[^/]*|\.z(?:sh[^/]*|profile|login|logout)|\.pam_environment"
    r"|\.(?:xprofile|xsessionrc|xsession|xinitrc)|\.(?:cshrc|tcshrc|login|logout)"
    r"|\.ssh/(?:environment|rc)|\.MacOSX/environment\.plist"
    r"|\.config/(?:environment\.d|pip|fish|systemd/user|plasma-workspace/env)(?:/.*)?"
    r"|\.pip(?:/.*)?|Library/LaunchAgents(?:/.*)?)$"
)
# Folders a whole tree may land in and so plant those files without naming them (like ~ and ~/.local for the user site).
SHELL_STARTUP_PARENT_REL_RE = re.compile(r"^(?:\.config|\.config/systemd|\.ssh|\.MacOSX|Library)$")
SHELL_STARTUP_MSG = ("Shell or session start-up file ({}): the login shell, the desktop session or the IDE reads it at "
                     "start, so a PATH, LD_PRELOAD or other variable set there reaches every later process, the kit "
                     "hooks included. Blocked unattended; in supervised mode approve only if you asked for it.")
SHELL_STARTUP_EDIT_MSG = ("Shell or session start-up file ({}): a PATH, LD_PRELOAD or other variable set there reaches "
                          "every later process, the kit hooks included. The edit tool cannot ask for approval, so this "
                          "edit is blocked in every mode; if you need the change, make it yourself in a terminal.")


def _home_rel(p: str) -> Optional[str]:
    """The path relative to the agent user's home (relative paths start at the cd/payload folder), else None."""
    raw = os.path.expandvars(os.path.expanduser(p.replace("\\", "/").strip().strip("'\"")))
    if not raw:
        return None
    if not raw.startswith("/"):
        raw = posixpath.join(_BASE_DIR or _base_dir(), raw)
    cand = posixpath.normpath(raw)
    home = posixpath.normpath(os.path.expanduser("~"))
    if home in ("", "/", ".", "~"):
        return None
    for h in (home, posixpath.normpath(os.path.realpath(home))):
        if cand.startswith(h + "/"):
            return cand[len(h) + 1:]
    return None


def _is_shell_startup_path(p: str) -> bool:
    rel = _home_rel(p)
    return rel is not None and bool(SHELL_STARTUP_REL_RE.match(rel))


def _is_python_startup_path(p: str) -> bool:
    raw = os.path.expandvars(os.path.expanduser(p.replace("\\", "/").strip().strip("'\"")))
    return bool(raw) and any(PY_STARTUP_RE.search(c) for c in (raw, posixpath.normpath(raw)))


def _is_py_startup_path(p: str) -> bool:
    """A start-up file under the N-1 rule: Python's (N-1) or the shell's and session's (JN-4)."""
    return _is_python_startup_path(p) or _is_shell_startup_path(p)


def _startup_msg(p: str) -> str:
    return (PY_STARTUP_MSG if _is_python_startup_path(p) else SHELL_STARTUP_MSG).format(p)


def _startup_edit_msg(p: str) -> str:
    return (PY_STARTUP_EDIT_MSG if _is_python_startup_path(p) else SHELL_STARTUP_EDIT_MSG).format(p)


def _segment_writes_py_startup(seg: str) -> Optional[str]:
    # N-1 final round (Sakura 7e91af9 nit): a cp/rsync SOURCE under the user site is a read, not a write
    #   (cp -r ~/.local/lib/python3.13 /tmp/backup/). For those two only the redirections and where each source
    #   lands (the destination) are judged; every other program keeps the operand check.
    try:
        first = shlex.split(_strip_env_prefix(seg.strip()), posix=True)[:1]
    except ValueError:
        first = seg.split()[:1]
    if first and first[0].split("/")[-1] in ("cp", "rsync"):
        return _redirect_writes(seg, _is_py_startup_path) or \
            _segment_changes_container(seg, _is_py_startup_path) or _segment_py_startup_tree(seg)
    return _segment_writes_matching_path(seg, _is_py_startup_path) or \
        _segment_changes_container(seg, _is_py_startup_path) or _segment_py_startup_tree(seg)


# kitfix-20261031-jn4: commands that change the environment of the user's session manager without a file: every
#   process it starts later (the IDE, agy, a new terminal) inherits PATH or LD_PRELOAD from there.
SESSION_ENV_MSG = ("{} changes the environment of the user's session, so a PATH, LD_PRELOAD or other variable set "
                   "there reaches every later process, the kit hooks included. Blocked unattended; in supervised mode "
                   "approve only if you asked for it.")


def _segment_sets_session_env(seg: str) -> Optional[str]:
    try:
        parts = shlex.split(_strip_env_prefix(seg.strip()), posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return None
    bin0 = parts[0].split("/")[-1]
    rest = [a for a in parts[1:] if not a.startswith("-")]
    if bin0 == "systemctl" and rest[:1] and rest[0] in ("set-environment", "import-environment"):
        return f"systemctl {rest[0]}"
    if bin0 == "launchctl" and rest[:1] and (rest[0] in ("setenv", "putenv") or rest[:2] == ["config", "user"]):
        return f"launchctl {rest[0]}"
    if bin0 == "dbus-update-activation-environment":
        return bin0
    return None


def _redirect_writes(seg: str, predicate) -> Optional[str]:
    for m in re.finditer(r">+\s*([^\s;|&]+)", _strip_env_prefix(seg.strip())):
        target = m.group(1).strip().strip("'\"")
        if predicate(target):
            return target
    return None


# kitfix-20261031-n1 rework (Sakura B-2): a whole tree copied, moved, synced or unpacked into the user site's
#   parents (~, ~/.local, ~/.local/lib, ~/.local/bin) plants the same start-up files without naming them, and so does
#   pip install --user. A destination is judged as the path each source lands on (dest/basename, or dest itself for
#   rsync "src/", "src/." and a destination folder that does not exist yet). Copying a single file into ~ or a
#   project folder stays allowed. Setting PIP_USER (pip then installs into the user site by default) and
#   `pip config set <x>.user` count as a pip --user install. tar -x -C and dd/sponge stay with H-5.
PY_STARTUP_PARENT_RE = re.compile(r"(^|/)\.local(?:/(?:lib|bin))?/*$")
# Judged on the whole command (an env prefix or `env` wrapper is gone by the time a segment is classified).
PIP_USER_RE = re.compile(r"\bPIP_USER\s*=\s*['\"]?(?!0\b|false\b|no\b|off\b)[^\s;&|'\"]", re.I)
# N-1 follow-up (Sakura re-review): PIP_TARGET / PIP_PREFIX / PIP_ROOT pointing into the user site or its parents.
PIP_PATH_ENV_RE = re.compile(r"\bPIP_(?:TARGET|PREFIX|ROOT)\s*=\s*['\"]?([^\s;&|'\"]+)", re.I)
_PIP_PATH_OPTS = ("--target", "-t", "--prefix", "--root", "--home")


def _py_startup_expand(p: str) -> str:
    return os.path.expandvars(os.path.expanduser(p.replace("\\", "/").strip().strip("'\"")))


def _is_py_startup_parent(p: str) -> bool:
    """True for ~, ~/.local, ~/.local/lib or ~/.local/bin (any spelling): a tree landing there can hold the user site."""
    raw = _py_startup_expand(p)
    if not raw:
        return False
    cands = [raw.rstrip("/") or "/", posixpath.normpath(raw)]
    if not raw.startswith("/"):
        # the cd target counts even before it exists (cd ~/.local/lib && unzip x.zip)
        cands.append(posixpath.normpath(posixpath.join(_BASE_DIR or _base_dir(), raw)))
    home = posixpath.normpath(os.path.expanduser("~"))
    homes = {home, os.path.realpath(home)} if home not in ("", "/", "~") else set()
    if any(PY_STARTUP_PARENT_RE.search(c) or c in homes for c in cands):
        return True
    rel = _home_rel(p)  # JN-4: ~/.config, ~/.ssh, ~/Library and the like hold shell/session start-up files
    return rel is not None and bool(SHELL_STARTUP_PARENT_REL_RE.match(rel))


def _is_py_startup_tree_dest(p: str) -> bool:
    return _is_py_startup_path(p) or _is_py_startup_parent(p)


def _existing_dir(p: str) -> bool:
    raw = _py_startup_expand(p)
    if not raw or re.search(r"[$`*?\[]", raw):
        return False
    return os.path.isdir(raw if raw.startswith("/") else os.path.join(_base_dir(), raw))


def _python_module(parts: List[str]) -> Optional[Tuple[str, List[str]]]:
    """(module, its arguments) for python* -m <mod> in any spelling (-m mod, -mmod, -Im mod, -I -m mod); else None."""
    if not re.fullmatch(r"python[0-9.]*", parts[0].split("/")[-1]):
        return None
    i = 1
    while i < len(parts):
        a = parts[i]
        if a == "--" or a == "-" or not a.startswith("-"):
            return None
        if a.startswith("--"):
            i += 1
            continue
        cl = a[1:]
        for k, ch in enumerate(cl):
            if ch == "m":
                if cl[k + 1:]:
                    return cl[k + 1:], parts[i + 1:]
                return (parts[i + 1], parts[i + 2:]) if i + 1 < len(parts) else None
            if ch == "c":
                return None
            if ch in "WX":  # takes a value: the rest of the cluster or the next word
                if not cl[k + 1:]:
                    i += 1
                break
        i += 1
    return None


def _python_c_body(parts: List[str]) -> Optional[str]:
    """The program text of python* -c <body> (also -Ic, -I -S -c); None when there is no -c."""
    if not re.fullmatch(r"python[0-9.]*", parts[0].split("/")[-1]):
        return None
    for i, a in enumerate(parts[1:], 1):
        if a == "--" or not a.startswith("-") or a.startswith("--"):
            if a.startswith("--"):
                continue
            return None
        k = a.find("c", 1)
        if k > 0:
            return a[k + 1:] or (parts[i + 1] if i + 1 < len(parts) else None)
    return None


# Python calls that copy, move or unpack: name -> (index of the destination argument, does it place a whole tree).
_PY_TREE_CALLS = {"copytree": (1, True), "copy_tree": (1, True), "move": (1, True), "unpack_archive": (1, True),
                  "extractall": (0, True), "symlink": (1, True), "symlink_to": (0, True), "rename": (1, True),
                  "replace": (1, True), "copy": (1, False), "copy2": (1, False), "copyfile": (1, False)}


def _call_args(text: str, start: int) -> List[str]:
    """Top-level comma-separated arguments of the call whose '(' is at text[start]."""
    args, depth, cur, q, i = [], 0, "", None, start + 1
    while i < len(text):
        ch = text[i]
        if q:
            cur += ch
            if ch == "\\" and i + 1 < len(text):
                cur += text[i + 1]
                i += 1
            elif ch == q:
                q = None
        elif ch in "'\"":
            q = ch
            cur += ch
        elif ch in "([{":
            depth += 1
            cur += ch
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    if cur.strip():
        args.append(cur.strip())
    return args


def _py_code_tree_dest(body: str) -> Optional[str]:
    """A shutil/zipfile/os/Path call in Python source whose destination is a start-up path or (for a tree) a parent
    of the user site. String literals of the destination argument are joined with '/', so
    os.path.join(os.path.expanduser('~'), '.local', 'lib') and Path.home() / '.local' / 'lib' are seen."""
    for m in re.finditer(r"\b(" + "|".join(_PY_TREE_CALLS) + r")\s*\(", body):
        idx, tree = _PY_TREE_CALLS[m.group(1)]
        args = _call_args(body, m.end() - 1)
        kw = [a.split("=", 1)[1] for a in args if re.match(r"(?:dst|path|extract_dir|target)\s*=", a)]
        pos = [a for a in args if not re.match(r"[A-Za-z_]\w*\s*=(?!=)", a)]
        dest = kw[0] if kw else (pos[idx] if idx < len(pos) else None)
        if m.group(1) in ("symlink_to",):  # Path(dest).symlink_to(src): the destination is before the call
            pre = body[max(0, m.start() - 200):m.start()]
            lit = re.findall(r"['\"]([^'\"]+)['\"]", pre)
            dest = "'" + "/".join(lit[-3:]) + "'" if lit else None
        if not dest:
            continue
        lits = re.findall(r"['\"]([^'\"]*)['\"]", dest)
        if not lits:
            continue
        joined = "/".join(x.strip("/") if j else x.rstrip("/") for j, x in enumerate(lits) if x)
        for cand in (joined, lits[-1]):
            if _is_py_startup_path(cand) or (tree and _is_py_startup_parent(cand)):
                return cand
    return None


def _brace_expand(s: str, limit: int = 64) -> List[str]:
    m = re.search(r"\{([^{}]*,[^{}]*)\}", s)
    if not m:
        return [s]
    out: List[str] = []
    for alt in m.group(1).split(","):
        out.extend(_brace_expand(s[:m.start()] + alt + s[m.end():], limit))
        if len(out) >= limit:
            break
    return out[:limit]


def _is_home(p: str) -> bool:
    raw = _py_startup_expand(p)
    if not raw:
        return False
    full = posixpath.normpath(raw if raw.startswith("/") else posixpath.join(_BASE_DIR or _base_dir(), raw))
    home = posixpath.normpath(os.path.expanduser("~"))
    return home not in ("", "/", "~") and full in (home, os.path.realpath(home))


def _pip_install_args(parts: List[str]) -> Optional[List[str]]:
    """The arguments after `install` for pip/pip3/pip3.X, python* -m pip, or uv pip; None when it is not a pip install."""
    bin0 = parts[0].split("/")[-1]
    rest: Optional[List[str]] = None
    mod = _python_module(parts)
    if re.fullmatch(r"pip[0-9.]*", bin0):
        rest = parts[1:]
    elif mod and re.fullmatch(r"pip[0-9.]*", mod[0]):
        rest = mod[1]
    elif bin0 == "uv" and len(parts) > 1 and parts[1] == "pip":
        rest = parts[2:]
    if rest is None:
        return None
    ops = [a for a in rest if not a.startswith("-")]
    if not ops or ops[0] != "install":
        return None
    return rest[rest.index("install") + 1:]


def _segment_py_startup_tree(seg: str) -> Optional[str]:
    seg = _strip_env_prefix(seg.strip())
    try:
        parts = shlex.split(seg, posix=True)
    except ValueError:
        parts = seg.split()
    if not parts:
        return None
    bin0 = parts[0].split("/")[-1]
    if re.fullmatch(r"pip[0-9.]*", bin0) and len(parts) > 3 and parts[1:3] == ["config", "set"]:
        if re.search(r"\.user$", parts[3]):
            return "pip config set " + parts[3]
        if re.search(r"\.(?:target|prefix|root)$", parts[3]) and len(parts) > 4 and _is_py_startup_tree_dest(parts[4]):
            return parts[4]
    pip = _pip_install_args(parts)
    if pip is not None:
        if "--user" in pip:
            return "pip install --user"
        for i, a in enumerate(pip):
            for o in _PIP_PATH_OPTS:
                v = pip[i + 1] if a == o and i + 1 < len(pip) else (a.split("=", 1)[1] if a.startswith(o + "=") else None)
                if v is None and o == "-t" and a.startswith("-t") and len(a) > 2:
                    v = a[2:]  # -t<path>
                if v and _is_py_startup_tree_dest(v):
                    return v
        return None
    mod = _python_module(parts)
    if mod and mod[0] in ("zipfile", "tarfile") and any(a in ("-e", "--extract") for a in mod[1]):
        ops = [a for a in mod[1] if not a.startswith("-")]
        dest = ops[1] if len(ops) >= 2 else "."
        return dest if _is_py_startup_tree_dest(dest) else None
    body = _python_c_body(parts)
    if body:
        hit = _py_code_tree_dest(body)
        if hit:
            return hit
    if re.fullmatch(r"python[0-9.]*", bin0) and "setup.py" in parts and "install" in parts and "--user" in parts:
        return "setup.py install --user"
    if bin0 == "unzip":
        dest = "."
        for i, a in enumerate(parts[1:], 1):
            if a == "-d" and i + 1 < len(parts):
                dest = parts[i + 1]
            elif a.startswith("-d") and len(a) > 2:
                dest = a[2:]
        return dest if _is_py_startup_tree_dest(dest) else None
    if bin0 not in ("cp", "mv", "rsync", "ln", "ditto"):
        return None
    shorts = "".join(a[1:] for a in parts[1:] if a.startswith("-") and not a.startswith("--"))
    longs = [a for a in parts[1:] if a.startswith("--")]
    recursive = bin0 in ("mv", "ln", "ditto") or bool(re.search(r"[rRa]", shorts)) or \
        any(a in ("--recursive", "--archive") for a in longs)
    tgt, used = None, set()
    for i, a in enumerate(parts[1:], 1):
        if a == "--target-directory" and i + 1 < len(parts):
            tgt = parts[i + 1]
            used.add(i + 1)
        elif a.startswith("--target-directory="):
            tgt = a.split("=", 1)[1]
        elif bin0 != "rsync" and a.startswith("-") and not a.startswith("--") and "t" in a[1:]:
            rest = a[a.index("t", 1) + 1:]  # -t DIR, -tDIR, -rt DIR, -rtDIR (rsync -t is --times)
            if rest:
                tgt = rest
            elif i + 1 < len(parts):
                tgt = parts[i + 1]
                used.add(i + 1)
    ops = [a for j, a in enumerate(parts[1:], 1) if not a.startswith("-") and j not in used]
    if tgt is None:
        if len(ops) < 2:
            return None
        tgt, srcs = ops[-1], ops[:-1]
    else:
        srcs = ops
    lands = []
    tgt_dir = _existing_dir(tgt)
    # N-1 follow-up (Sakura re-review): a brace source is expanded, and a glob source counts as its contents (it
    #   lands on the destination itself). Into ~ only a glob that can match a dot name counts (.[!.]*, .l*): a plain
    #   * skips .local unless dotglob is set.
    all_srcs = [b for x in srcs for b in _brace_expand(x)]
    into = tgt_dir or len(all_srcs) > 1 or tgt.endswith("/")  # else one source onto a new name: it lands as tgt
    for src in all_srcs:
        s = src.rstrip("/")
        base = posixpath.basename(s)
        if re.search(r"[*?\[]", base):
            if base.startswith(".") or base.startswith("[.") or not _is_home(tgt):
                lands.append(tgt)
            continue
        contents = (bin0 == "rsync" and src.endswith("/")) or s.endswith("/.") or s in (".", "")
        if contents or into:
            lands.append(tgt if contents else posixpath.join(tgt, base))
    if not tgt_dir:
        lands.append(tgt)
    for land in lands:
        if _is_py_startup_path(land) or (recursive and _is_py_startup_parent(land)):
            return land
    return None


def _segment_changes_harness(seg: str) -> Optional[str]:
    w = _segment_writes_matching_path(seg, _is_harness_path)
    if w:
        return w
    return _segment_changes_container(seg, _is_harness_path)


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

# Carried from 8d89d6f1/64da9195 (workflow-fixes-onboard), Design: D1.
# N63 / N11C (onboard fix, Sasuke): gh, glab and git push change the remote: pull or merge requests, approvals,
#   repositories, releases, pipelines, CI variables, branches. An agent never runs them, in any mode, supervised
#   included: they are a block, never an ask, so no unattended allow-list (AGY_ALLOW_TOOLS, unattended-allow) can
#   turn them into an allow. Read-only calls (gh pr view, gh pr list, gh api GET, glab mr view) stay allowed.
#   Evasion forms (env prefixes, command/exec/nohup wrappers, absolute paths, quoting, sh -c, $(...), chains) are
#   unwrapped by split_segments/_expand_wrapper before this runs; git aliases are resolved below.
REMOTE_WRITE_MSG = ("{} changes the remote; an agent never runs it, in any mode, supervised included (N11C). "
                    "The user runs it in their own terminal: hand over the exact command and stop.")
# gh flags that take a value as the next token (so the value is not read as a subcommand).
_GH_VALUED_FLAGS = {"-R", "--repo", "--hostname", "-X", "--method", "-H", "--header", "-f", "-F", "--field",
                    "--raw-field", "--input", "-q", "--jq", "-t", "--template", "-p", "--preview", "--cache",
                    "-b", "--body", "-B", "--base", "--title", "-T", "-m", "--message", "-L", "--limit"}
# Jiraiya third look (item B): gh is judged against an allow-list of read-only commands; every other gh call is
#   denied. gh aliases (`gh co 1`) and extensions (`gh my-ext`) run anything, so an unknown top-level command is a
#   deny too. GH_WRITES only names the writes (for the message and the regression list); it is not the fence.
GH_READS = {
    "pr": {"list", "view", "diff", "checks", "status", "checkout"},
    "issue": {"list", "view", "status"},
    "repo": {"list", "view", "clone"},
    "release": {"list", "view", "download"},
    "run": {"list", "view", "watch", "download"},
    "workflow": {"list", "view"},
    "search": None,  # None: every subcommand reads (gh search repos|issues|prs|code|commits)
    "status": None, "browse": None, "help": None, "version": None, "completion": None,
    "auth": {"status"},  # token, login, logout, refresh, setup-git, switch: denied
    "gist": {"list", "view", "clone"},
    "label": {"list"},
    "secret": {"list"},
    "variable": {"list", "get"},
    "cache": {"list"},
    "ruleset": {"list", "view", "check"},
    "project": {"list", "view", "field-list", "item-list"},
    "codespace": {"list", "view"}, "cs": {"list", "view"},
    "extension": {"list", "search", "browse"}, "ext": {"list", "search", "browse"},
    "ssh-key": {"list"},
    "gpg-key": {"list"},
    "org": {"list"},
    "alias": {"list"},
    "config": {"get", "list"},
    "attestation": {"verify", "download"},
}
GH_WRITES = {
    "pr": {"create", "new", "merge", "review", "close", "reopen", "edit", "ready", "comment", "lock", "unlock",
           "update-branch", "revert"},
    "repo": {"create", "new", "delete", "edit", "rename", "archive", "unarchive", "fork", "sync", "set-default"},
    "release": {"create", "new", "delete", "edit", "upload", "delete-asset"},
    "issue": {"create", "new", "close", "reopen", "edit", "delete", "comment", "transfer", "pin", "unpin", "lock",
              "unlock", "develop"},
    "secret": {"set", "delete", "remove"},
    "variable": {"set", "delete", "remove"},
    "workflow": {"run", "enable", "disable"},
    "run": {"rerun", "cancel", "delete"},
    "label": {"create", "edit", "delete", "clone"},
    "gist": {"create", "new", "edit", "delete", "rename"},
    "alias": {"set", "import", "delete"},
    "cache": {"delete"},
    "ruleset": set(),
    "ssh-key": {"add", "delete"},
    "gpg-key": {"add", "delete"},
    "extension": {"install", "upgrade", "remove", "create", "exec"},
    "project": {"create", "edit", "delete", "close", "copy", "link", "unlink", "mark-template", "field-create",
                "field-delete", "item-add", "item-create", "item-edit", "item-delete", "item-archive"},
    "codespace": {"create", "delete", "edit", "ssh", "cp", "code", "jupyter", "ports", "rebuild", "stop"},
    "auth": {"login", "logout", "refresh", "setup-git", "switch"},
}
UNRESOLVED_CMD_MSG = ("`{}`: the shell fills this in at run time, so the guard cannot tell whether it pushes or "
                      "writes to GitHub; an agent spells the command out (N11C). Anything that changes the remote, "
                      "the user runs in their own terminal.")
GH_UNKNOWN_MSG = ("`gh {}` is not a known read-only gh command: it may be an alias or an extension, which can push or "
                  "merge, so an agent does not run it, in any mode (N11C). Use the read it stands for (gh pr view, "
                  "gh run view, ...); anything that changes the remote, the user runs in their own terminal.")
GH_TOKEN_MSG = ("gh auth token prints the GitHub token; an agent never reads it, in any mode (N11C). "
                "The user runs gh in their own terminal: hand over the exact command and stop.")
GLAB_WRITES = {("mr", "create"), ("mr", "new"), ("mr", "update"), ("mr", "close"), ("mr", "reopen"),
               ("mr", "delete"), ("mr", "note"), ("mr", "rebase"), ("mr", "revoke"),
               ("ci", "run"), ("ci", "trigger"), ("ci", "retry"), ("ci", "cancel"), ("ci", "delete"),
               ("release", "create"), ("release", "delete"), ("release", "upload"),
               ("variable", "set"), ("variable", "update"), ("variable", "delete"),
               ("repo", "create"), ("repo", "delete"), ("repo", "fork"), ("repo", "archive"), ("repo", "transfer"),
               ("alias", "set"), ("alias", "delete")}
_PUSH_WORD_RE = re.compile(r"(?:^|[\s!;&|(])(?:push|send-pack)\b|\bsvn\s+dcommit\b|\bsubtree\s+push\b")
# Common git subcommands: anything else may be an alias, which is looked up in the repository's git config.
_GIT_BUILTINS = {"add", "am", "apply", "archive", "bisect", "blame", "branch", "bundle", "cat-file", "check-ignore",
                 "checkout", "cherry", "cherry-pick", "clean", "clone", "commit", "config", "describe", "diff",
                 "fetch", "for-each-ref", "format-patch", "fsck", "gc", "grep", "hash-object", "help", "init", "log",
                 "ls-files", "ls-remote", "ls-tree", "merge", "merge-base", "mv", "notes", "pull", "push",
                 "range-diff", "rebase", "reflog", "remote", "reset", "restore", "rev-list", "rev-parse", "revert",
                 "rm", "shortlog", "show", "show-ref", "sparse-checkout", "stash", "status", "submodule", "switch",
                 "symbolic-ref", "tag", "update-index", "update-ref", "var", "verify-commit", "version",
                 "whatchanged", "worktree", "write-tree", "send-pack", "subtree", "svn", "p4", "lfs",
                 "send-email", "imap-send", "http-push", "request-pull", ""}
# Jiraiya third look (item A): git subcommands that send commits or patches somewhere other than this checkout.
_GIT_SEND_SUBS = {"push", "send-pack", "send-email", "imap-send", "http-push"}
_GIT_DASH_RE = re.compile(r"git-[a-z][a-z0-9-]*")  # git-push, /usr/lib/git-core/git-push: the same subcommand
_FIND_EXEC_FLAGS = {"-exec", "-execdir", "-ok", "-okdir"}


def _unresolved(tok: str) -> bool:
    """A word the shell fills in at run time ($x, ${x}, $(...), `...`): the hook cannot know what it becomes."""
    return "$" in tok or "`" in tok


def _find_exec_bodies(parts: List[str]) -> List[List[str]]:
    """The commands find runs: the words after -exec/-execdir/-ok/-okdir, up to `;` or `+`."""
    out: List[List[str]] = []
    i = 0
    while i < len(parts):
        if parts[i] in _FIND_EXEC_FLAGS:
            j = i + 1
            body: List[str] = []
            while j < len(parts) and parts[j] not in (";", "\\;", "+"):
                body.append(parts[j])
                j += 1
            if body:
                out.append(body)
            i = j
        i += 1
    return out


def _text_remote_write(text: str) -> Optional[str]:
    """The remote write in a command another command runs (find -exec, git submodule foreach), if any."""
    for seg in split_segments(text):
        seg = _strip_env_prefix(seg.strip())
        if not seg:
            continue
        try:
            parts = shlex.split(seg, posix=True)
        except ValueError:
            parts = seg.split()
        what = _parts_remote_write(parts)
        if what:
            return what
    return None


def _parts_remote_write(parts: List[str]) -> Optional[str]:
    """What remote write (or unjudgeable command name) one parsed command is, for nested commands."""
    if not parts:
        return None
    if _unresolved(parts[0]):
        return "a command name from a variable or substitution"
    b = parts[0].split("/")[-1]
    if _GIT_DASH_RE.fullmatch(b):
        parts, b = ["git", b[4:]] + parts[1:], "git"
    if b == "gh":
        return _gh_verdict(parts)
    if b == "glab":
        pairs = set(zip(parts[1:], parts[2:]))
        if ("mr", "merge") in pairs or ("mr", "approve") in pairs:
            return "glab mr merge/approve"
        return _glab_verdict(parts)
    if b == "git":
        sub = _git_subcommand(parts)
        return _git_remote_write(parts, sub, parts.index(sub) if sub in parts else len(parts))
    if b == "find":
        for body in _find_exec_bodies(parts):
            what = _text_remote_write(shlex.join(body))
            if what:
                return f"find -exec {what}"
    return None


def _api_is_write(args: List[str]) -> bool:
    """gh/glab api: a non-GET method, or any field or input, is a write (a plain GET is a read)."""
    i = 0
    while i < len(args):
        a = args[i]
        method = None
        if a in ("-X", "--method"):
            method = args[i + 1] if i + 1 < len(args) else "?"
            i += 1
        elif a.startswith("--method="):
            method = a.split("=", 1)[1]
        elif a.startswith("-X") and len(a) > 2:
            method = a[2:]
        elif a in ("-f", "-F", "--field", "--raw-field", "--input") or re.match(r"^-[fF].", a) or re.match(
                r"^--(?:field|raw-field|input)=", a):
            return True
        if method is not None and method.strip("'\"").upper() != "GET":
            return True
        i += 1
    return False


def _gh_positionals(args: List[str]) -> List[str]:
    pos: List[str] = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            pos.extend(args[i + 1:])
            break
        if a.startswith("-"):
            if a in _GH_VALUED_FLAGS:
                i += 1
            i += 1
            continue
        pos.append(a)
        i += 1
    return pos


def _gh_verdict(parts: List[str]) -> Optional[str]:
    """None for a known gh read; else what the call is (a write, a token read, or an unknown command or alias)."""
    pos = _gh_positionals(parts[1:])
    if not pos:
        return None  # gh, gh --version, gh --help
    top = pos[0]
    sub = pos[1] if len(pos) > 1 else ""
    if any("$" in t or "`" in t for t in pos[:2]):
        return f"gh {top} {sub} (a subcommand from a variable or substitution cannot be checked)".replace("  ", " ")
    if top == "api":
        return f"gh api {sub or ''} with a write method or fields".replace("  ", " ") if _api_is_write(parts[1:]) else None
    if top == "repo" and sub in ("deploy-key", "autolink"):
        third = pos[2] if len(pos) > 2 else ""
        return None if third in ("", "list", "view") else f"gh repo {sub} {third}"
    if top not in GH_READS:
        return f"gh {top} (unknown)"
    reads = GH_READS[top]
    if reads is None or sub == "" or sub in reads or sub in ("help", "--help", "-h"):
        return None
    return f"gh {top} {sub}"


def _glab_verdict(parts: List[str]) -> Optional[str]:
    pairs = set(zip(parts[1:], parts[2:]))
    if "api" in parts[1:3] and _api_is_write(parts[1:]):
        return "a state-changing glab api call"
    hit = sorted(pairs & GLAB_WRITES)
    if hit:
        return "glab " + " ".join(hit[0])
    return None


def _git_alias_value(parts: List[str], sub: str) -> str:
    """The alias a git subcommand stands for: from a -c alias.X=... on the command line, else the repo config."""
    if sub in _GIT_BUILTINS:
        return ""
    i = 1
    while i < len(parts) and parts[i] != sub:
        if parts[i] == "-c" and i + 1 < len(parts):
            k, _, v = parts[i + 1].partition("=")
            if k.lower() == f"alias.{sub}".lower():
                return v or "?"
            i += 2
            continue
        i += 1
    base = _base_dir()
    for j, p in enumerate(parts[:-1]):
        if p == "-C":
            base = os.path.join(base, os.path.expanduser(parts[j + 1]))
    try:
        r = subprocess.run(["git", "-C", base, "config", "--get", f"alias.{sub}"], capture_output=True, text=True,
                           timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _git_remote_write(parts: List[str], sub: str, sub_idx: int) -> Optional[str]:
    """git push (any remote), send-pack, subtree push, svn dcommit, and aliases that stand for them."""
    args = parts[sub_idx + 1:]
    if _unresolved(sub):
        return f"git {sub} (a subcommand from a variable or substitution cannot be checked)"
    if sub in _GIT_SEND_SUBS:
        return f"git {sub}"
    if sub == "lfs" and "push" in args:
        return "git lfs push"
    if sub == "p4" and "submit" in args:
        return "git p4 submit"
    if sub == "submodule" and "foreach" in args:
        body = [a for a in args[args.index("foreach") + 1:] if a not in ("--recursive", "-q", "--quiet")]
        inner = _text_remote_write(" ".join(body)) if body else None
        if inner:
            return f"git submodule foreach ({inner})"
    if sub == "subtree" and "push" in args:
        return "git subtree push"
    if sub == "svn" and "dcommit" in args:
        return "git svn dcommit"
    # -c alias.X=<...push...> defines a push alias for this command, whatever it then runs.
    for j in range(1, sub_idx):
        if parts[j - 1] == "-c" and parts[j].lower().startswith("alias.") and _PUSH_WORD_RE.search(
                " " + parts[j].partition("=")[2]):
            return "a git alias for push"
    if sub == "config":
        keys = [k for k, a in enumerate(args) if a.lower().startswith("alias.")]
        for k in keys:
            val = args[k].partition("=")[2] + " " + " ".join(args[k + 1:])
            if _PUSH_WORD_RE.search(" " + val):
                return "defining a git alias for push"
    alias = _git_alias_value(parts, sub)
    if alias and _PUSH_WORD_RE.search(" " + alias):
        return f"git {sub} (an alias for push)"
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

    ppath = _segment_writes_py_startup(seg)  # kitfix-20261031-n1, -jn4 (shell/session start-up files too)
    if ppath:
        return ("block" if unattended_mode() else "ask"), _startup_msg(ppath)

    senv = _segment_sets_session_env(seg)  # kitfix-20261031-jn4
    if senv:
        return ("block" if unattended_mode() else "ask"), SESSION_ENV_MSG.format(senv)

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
    # Carried from 8d89d6f1/64da9195 (workflow-fixes-onboard), Design: D1.
    # Jiraiya third look (items A and B): a command name the shell fills in at run time (`$g pr create`,
    #   `$(which gh) ...`) cannot be judged, so it is refused; git-push (or /usr/lib/git-core/git-push) is git push.
    if _unresolved(parts[0]):
        return "block", UNRESOLVED_CMD_MSG.format(" ".join(parts[:3]))
    if _GIT_DASH_RE.fullmatch(bin0):
        parts, bin0 = ["git", bin0[4:]] + parts[1:], "git"
    if bin0 == "git" and _unresolved(_git_subcommand(parts)):
        return "block", UNRESOLVED_CMD_MSG.format("git " + _git_subcommand(parts))
    if bin0 == "gh" and any(_unresolved(t) for t in _gh_positionals(parts[1:])[:2]):
        return "block", UNRESOLVED_CMD_MSG.format(" ".join(parts[:3]))
    if bin0 == "find":
        what = _parts_remote_write(parts)
        if what:
            return "block", REMOTE_WRITE_MSG.format(what)

    if bin0 == "rm" and _rm_is_recursive(parts):
        return "block", "recursive rm is blocked without explicit human approval."
    if bin0 == "find" and "-delete" in parts:
        return "ask", "find -delete removes files; requires explicit user approval."

    # Carried from 8d89d6f1/64da9195 (workflow-fixes-onboard), Design: D1.
    if bin0 == "gh":
        pos = _gh_positionals(parts[1:])
        if pos[:2] == ["auth", "token"]:
            return "block", GH_TOKEN_MSG
        if pos and pos[0] != "api" and pos[0] not in GH_READS:
            return "block", GH_UNKNOWN_MSG.format(pos[0])
        what = _gh_verdict(parts)
        if what:
            return "block", REMOTE_WRITE_MSG.format(what)

    if bin0 == "glab":
        pairs = set(zip(parts[1:], parts[2:]))
        joined = " ".join(parts[1:])
        own = " The user runs it in their own terminal."
        if ("mr", "merge") in pairs:
            return "block", "glab mr merge requires explicit human authorization." + own
        if ("mr", "approve") in pairs:
            return "block", "approving a merge request is a human act, not an agent action." + own
        if "api" in parts[1:3] and re.search(r"/(merge|approve)\b", joined):
            return "block", "merging or approving a merge request through glab api is blocked." + own
        what = _glab_verdict(parts)
        if what:  # N11C: these asked at 36b86cf; an ask can become an allow when unattended, so they block now
            return "block", REMOTE_WRITE_MSG.format(what)

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
            return "block", REMOTE_WRITE_MSG.format("git push")
        remote = _git_remote_write(parts, sub, sub_idx)
        if remote:
            return "block", REMOTE_WRITE_MSG.format(remote)
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


def _classify_command_once(cmd: str) -> Tuple[Action, str]:
    global _BASE_DIR
    _BASE_DIR = None
    del _ESCALATIONS[:]
    if GUARD_OVERRIDE_RE.search(cmd):
        return "block", GUARD_OVERRIDE_MSG
    if TEST_OVERRIDES_RE.search(cmd):
        return "block", TEST_OVERRIDES_MSG
    if APPROVALS_DIR_RE.search(cmd):  # Design: DA
        return "block", APPROVALS_DIR_MSG
    if APPROVE_RUN_RE.search(cmd):  # Design: DA
        return "block", APPROVE_RUN_MSG
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
    for esc in _ESCALATIONS:
        if esc in ESCALATORS_ALL_MODES or unattended:
            return "block", ESCALATION_MSG.format(esc)
    stdin_exec = unattended and any(_segment_reads_stdin_program(sg) for sg in segments)
    hook_root = _project_root(_base_dir()) if unattended else ""
    if unattended:
        if ALLOW_VAR_RE.search(cmd):
            return "block", ALLOW_VAR_MSG
        if ENV_I_RE.search(cmd):  # judged on the raw command: segment splitting already unwraps `env`
            return "block", ENV_I_MSG
        if re.search(r"\b(?:python3?|node|perl|ruby)\b[^\n|;&]*(?:\s-\s*)?<<-?\s*['\"]?\w+", cmd) and SCRIPT_WRITE_HINT.search(cmd):
            for lit in re.findall(r"['\"]([^'\"\n]+)['\"]", cmd):
                if _is_harness_path(lit):
                    return "block", HARNESS_MSG.format(lit)
        why = command_git_env_kit_source(cmd, hook_root)
        if why:
            return "block", GIT_SOURCE_MSG.format(why)
    for seg in segments:
        cd_to = _cd_target(seg)
        if cd_to:
            _BASE_DIR = os.path.normpath(os.path.join(_base_dir(), os.path.expanduser(cd_to)))
            continue
        if unattended:
            why, inner = _segment_ws_exec(seg)
            if why:
                return "block", WS_EXEC_MSG.format(why)
            if inner:
                saved = _BASE_DIR
                ia, im = classify_command(inner)
                _BASE_DIR = saved
                if ia == "block":
                    return "block", "agy-ws-exec.sh command: " + im
                if ia == "ask" and worst != "block":
                    worst, msg = "ask", im or msg
            hp = _segment_changes_harness(seg)
            if hp:
                return "block", HARNESS_MSG.format(hp)
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
    pip_env = "PIP_USER" if PIP_USER_RE.search(cmd) else next(
        (m.group(0) for m in PIP_PATH_ENV_RE.finditer(cmd) if _is_py_startup_tree_dest(m.group(1))), None)
    if pip_env:  # kitfix-20261031-n1 rework (Sakura B-2) and follow-up: pip then installs into the user site
        if unattended:
            return "block", PY_STARTUP_MSG.format(pip_env)
        if worst != "block":
            worst, msg = "ask", PY_STARTUP_MSG.format(pip_env)
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


def classify_command(cmd: str) -> Tuple[Action, str]:
    act, msg = _classify_command_once(cmd)
    if act == "block":
        return act, msg
    deobf = _deobfuscate_shell_cmd(cmd)
    if deobf != cmd:
        d_act, d_msg = _classify_command_once(deobf)
        if d_act == "block":
            return d_act, d_msg
        if d_act == "ask" and act == "allow":
            return d_act, d_msg
    return act, msg


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
    # Carried from 8d89d6f1/64da9195 (workflow-fixes-onboard), Design: D1.
    # onboard fix SOC-11 (Sasuke): the gate rule values and the secret-scan allow-list are guard files. The
    #   allow-list is read from HEAD only, so an agent's edit would never count; it is still never an agent's edit.
    # Design: D1 (gate-rules path fix): gate-rules lives at .agents-v0/gate-rules (D2); the old path stays covered.
    re.compile(r"(^|/)\.agents-v0/(scripts/)?gate-rules$"),
    re.compile(r"(^|/)\.agents-v0/secret-allowlist\.json$"),
    # Design: DA: the approval folder outside the repo (~/.agents-v0-approvals/<repo id>/<command>.json).
    re.compile(r"(^|/)\.agents-v0-approvals(/|$)"),
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
    if unattended_mode() and _is_harness_path(path):  # kitfix-20261031-harness-lock
        return "block", HARNESS_MSG.format(path)
    if is_protected_path(path):
        return (
            "block",
            f"Protected kit/CI path cannot be modified by agents: {path}",
        )
    if _is_py_startup_path(path):  # kitfix-20261031-n1, -jn4
        return ("block" if unattended_mode() else "ask"), _startup_msg(path)
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
        if action == "ask" and _is_py_startup_path(path):  # JN-6 (and JN-4: shell/session start-up files)
            action, message = "block", _startup_edit_msg(path)
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
