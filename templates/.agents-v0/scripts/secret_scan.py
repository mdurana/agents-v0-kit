#!/usr/bin/env python3
"""secret_scan.py: refuse a commit whose staged content holds a secret (onboard fix JO-8 / SOC-9).

The kit's one secret rule set. The file-name rules are the agent hook's list (core/common/hooks/hook-policy.py,
kept equal by scripts/test-secret-scan.py); the content rules are the ones check-lessons.sh (and through it the
opt-in pre-push hook) uses, imported from this file.

Usage:
  python3 .agents-v0/scripts/secret_scan.py [--staged] [--root DIR] [--message-file FILE]...
  python3 .agents-v0/scripts/secret_scan.py --list-rules | --help

What it scans (--staged is the only mode and the default):
  - the STAGED index content only (never the working tree), against HEAD (or the empty tree on an unborn branch),
    with --no-renames, so a renamed or copied file is scanned as new content;
  - a new file whole; a modified file by its added lines; deleted files and submodules are skipped;
  - each staged path against the file-name rules (.env, private keys, credential files);
  - each --message-file (the commit message) line by line, reported as commit-message:<line>.

Allow-list: .agents-v0/secret-allowlist.json, read from HEAD only (git show HEAD:...). An entry staged in this
  commit or edited in the working tree never counts, so an entry cannot approve the commit that adds it. Format:
    {"version": 1, "entries": [{"id", "ruleId", "path" (exact repository path, no globs), exactly one of
     "lineSha256" (content.* rules: sha256 of the line, trailing whitespace stripped) or "fileSha256" (name.* and
     file.* rules: sha256 of the staged file), "reason", "approvedBy", "approvedAt" (ISO time with offset),
     "approvalSource": {"channel", "messageTime", "quote"}, optional "expiresAt"}]}
  A hit is cleared only by an entry with the same ruleId, the same path and the same fingerprint; each use prints
  ALLOWED <id>. An invalid or expired entry is ignored and printed as INVALID-ENTRY. The fingerprint to approve is
  printed with each hit.

Output (stdout). The secret value itself is never printed:
  HIT <path>:<line|-> <ruleId> lineSha256=<hex>|fileSha256=<hex>
  ALLOWED <id> <path>:<line|-> <ruleId>
  INVALID-ENTRY <id|#n>: <reason>
  SECRET-SCAN clean files=<n>  |  SECRET-SCAN REFUSED hits=<n>  |  error: <why>  (stderr)

Exit codes: 0 no unallowed hit; 1 one or more hits (commit refused); 2 error, the scan could not run and the
  commit is refused (fail closed): not a git repository, GIT_INDEX_FILE set (another index), an unmerged or
  unreadable index, a git command failed, a malformed allow-list at HEAD, an unreadable message file, bad usage.
"""
from __future__ import annotations

import datetime as _dt
import hashlib
import json
import os
import posixpath
import re
import subprocess
import sys
from typing import Dict, List, Optional, Tuple

ALLOWLIST_PATH = ".agents-v0/secret-allowlist.json"
MAX_BLOB = 5 * 1024 * 1024
BINARY_SNIFF = 8000

# --- file-name rules: the same lists as core/common/hooks/hook-policy.py (parity test: scripts/test-secret-scan.py)
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
SECRET_SUFFIXES = (".pem", ".key", ".p12", ".pfx", ".jks", ".keystore")
SECRET_PATH_RE = re.compile(
    r"(^|/)\.(ssh|gnupg)(/|$)"
    r"|(^|/)\.aws/(credentials|config)$"
    r"|(^|/)\.kube/config$"
    r"|(^|/)\.config/gcloud(/|$)"
    r"|(^|/)\.docker/config\.json$"
    r"|(^|/)proc/[^/]+/environ$"
)
SECRET_BASENAME_RE = re.compile(r"^\.env(\.(?!(example|sample|template|dist)$)[^/]+)?$")

# --- content rules: (ruleId, label, regex). check-lessons.sh imports CONTENT_RULES and keeps the labels.
_PLACEHOLDER = r"(?![<$*{\[(]|x{3,}|\.\.\.|redacted|changeme|example|none|null|placeholder)"
# A value that is code, not a secret: a function or method call (token = match.group(1), SECRET = re.compile(...)).
_CODE_VALUE = r"(?![A-Za-z_][\w.]*\()"
CONTENT_RULES = [
    ("content.private-key", "private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("content.aws-key-id", "AWS access key id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("content.github-token", "GitHub token",
     re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{30,}\b")),
    ("content.gitlab-token", "GitLab token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    ("content.slack-token", "Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b")),
    ("content.sk-key", "API secret key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("content.google-api-key", "Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("content.jwt", "JSON Web Token",
     re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    ("content.url-credential", "credential in URL",
     re.compile(r"\b[a-z][a-z0-9+.-]*://[^/\s:@]+:" + _PLACEHOLDER + r"[^/\s@]{3,}@", re.I)),
    # SOC-9: also prefixed names (API_TOKEN=, DB_PASSWORD=, aws_secret_access_key =); "tokens: varchar_255" is not.
    ("content.assignment", "password/secret/token assignment",
     re.compile(r"(?<![A-Za-z0-9_])(?:[A-Za-z0-9]+[_.-])*(?:password|passwd|pwd|secret|client[_-]?secret|"
                r"api[_-]?key|access[_-]?key|access[_-]?token|auth[_-]?token|token)\b\s*[:=]\s*[\"']?"
                + _PLACEHOLDER + _CODE_VALUE + r"[^\s\"'`]{8,}", re.I)),
    ("content.bearer", "authorization header credential",
     re.compile(r"\bauthorization\s*[:=]\s*[\"']?(?:bearer|basic|token)\s+(?![<$*{\[(]|x{3,}|\.\.\.)"
                r"[A-Za-z0-9._~+/=-]{16,}", re.I)),
    ("content.azure-key", "Azure storage or service bus key",
     re.compile(r"\b(?:AccountKey|SharedAccessKey)\s*=\s*[A-Za-z0-9+/]{20,}={0,2}", re.I)),
]
NAME_RULES = {
    "name.env": ".env file",
    "name.basename": "credential file name",
    "name.suffix": "private key or keystore file",
    "name.path": "credential location",
}
FILE_RULES = {
    "file.binary": "binary file (cannot be scanned)",
    "file.too-large": f"file over {MAX_BLOB} bytes (cannot be scanned)",
    "file.undecodable": "not UTF-8 text (cannot be scanned)",
}
RULE_IDS = {r[0] for r in CONTENT_RULES} | set(NAME_RULES) | set(FILE_RULES)
_HEX64 = re.compile(r"^[0-9a-f]{64}$")


class ScanError(Exception):
    pass


def name_rule(path: str) -> Optional[str]:
    """The file-name rule a repository path matches (the hook's _path_looks_secret, with a rule id)."""
    base = posixpath.basename(path)
    if base.endswith(".pub"):
        return None  # a public key is not a secret
    if SECRET_BASENAME_RE.match(base):
        return "name.env"
    if base in SECRET_BASENAMES:
        return "name.basename"
    if base.endswith(SECRET_SUFFIXES):
        return "name.suffix"
    if SECRET_PATH_RE.search(path):
        return "name.path"
    return None


def content_rule(line: str) -> Optional[Tuple[str, str]]:
    for rid, label, rx in CONTENT_RULES:
        if rx.search(line):
            return rid, label
    return None


def line_sha256(line: str) -> str:
    return hashlib.sha256(line.rstrip().encode("utf-8", "surrogateescape")).hexdigest()


def show(path: str) -> str:
    """A path safe to print: control characters escaped."""
    return "".join(c if 0x20 <= ord(c) != 0x7F else f"\\x{ord(c):02x}" for c in path)


def git(*args: str, data: Optional[bytes] = None) -> bytes:
    try:
        r = subprocess.run(["git", "-c", "core.quotepath=off", *args], input=data, capture_output=True)
    except OSError as exc:
        raise ScanError(f"cannot run git: {exc}")
    if r.returncode != 0:
        msg = r.stderr.decode("utf-8", "replace").strip().splitlines()
        raise ScanError(f"git {args[0]} failed: {msg[0] if msg else 'exit ' + str(r.returncode)}")
    return r.stdout


def _iso(value) -> Optional[_dt.datetime]:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        t = _dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo is not None else None


def _text(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_entry(e) -> Optional[str]:
    """None when the entry is usable, else why it is ignored."""
    if not isinstance(e, dict):
        return "not an object"
    for f in ("id", "ruleId", "path", "reason", "approvedBy"):
        if not _text(e.get(f)):
            return f"missing or empty {f}"
    if e["ruleId"] not in RULE_IDS:
        return f"unknown ruleId {e['ruleId']!r}"
    p = e["path"]
    if any(c in p for c in "*?[") or "\\" in p:
        return "path must be one exact repository path (no globs)"
    if p.startswith("/") or posixpath.normpath(p) != p or p.split("/")[0] == "..":
        return "path must be a normalized path relative to the repository root"
    has_line, has_file = "lineSha256" in e, "fileSha256" in e
    if has_line == has_file:
        return "needs exactly one of lineSha256 or fileSha256"
    want = "lineSha256" if e["ruleId"].startswith("content.") else "fileSha256"
    if not has_line and want == "lineSha256" or not has_file and want == "fileSha256":
        return f"{e['ruleId']} needs {want}"
    if not isinstance(e[want], str) or not _HEX64.match(e[want]):
        return f"{want} must be 64 lowercase hex characters"
    if _iso(e.get("approvedAt")) is None:
        return "approvedAt must be an ISO time with an offset"
    src = e.get("approvalSource")
    if not isinstance(src, dict) or not all(_text(src.get(k)) for k in ("channel", "messageTime", "quote")):
        return "approvalSource needs channel, messageTime and quote"
    if _iso(src.get("messageTime")) is None:
        return "approvalSource.messageTime must be an ISO time with an offset"
    if "expiresAt" in e:
        exp = _iso(e.get("expiresAt"))
        if exp is None:
            return "expiresAt must be an ISO time with an offset"
        if exp <= _dt.datetime.now(_dt.timezone.utc):
            return "expired"
    return None


def load_allowlist(head: Optional[str], out: List[str]) -> Dict[Tuple[str, str, str], str]:
    """{(ruleId, path, fingerprint): id} from the allow-list at HEAD. Raises ScanError when it is malformed."""
    if head is None:
        return {}
    listing = git("ls-tree", "-z", head, "--", ALLOWLIST_PATH)
    if not listing:
        return {}
    meta = listing.split(b"\t", 1)[0].split()
    if len(meta) != 3 or meta[1] != b"blob" or meta[0] not in (b"100644", b"100755"):
        raise ScanError(f"{ALLOWLIST_PATH} at HEAD is not a regular file")
    raw = git("cat-file", "blob", meta[2].decode())
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ScanError(f"{ALLOWLIST_PATH} at HEAD is not valid JSON ({type(exc).__name__}); fix it in a commit "
                        f"Sensei approves")
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("entries"), list):
        raise ScanError(f'{ALLOWLIST_PATH} at HEAD must be {{"version": 1, "entries": [...]}}')
    allowed: Dict[Tuple[str, str, str], str] = {}
    seen = set()
    for n, e in enumerate(data["entries"], 1):
        why = validate_entry(e)
        label = show(e["id"]) if isinstance(e, dict) and _text(e.get("id")) else f"#{n}"
        if why is None and e["id"] in seen:
            why = "duplicate id"
        if why:
            out.append(f"INVALID-ENTRY {label}: {why}")
            continue
        seen.add(e["id"])
        fp = e.get("lineSha256") or e.get("fileSha256")
        allowed[(e["ruleId"], e["path"], fp)] = e["id"]
    return allowed


def _blob_hits(path: str, blob: bytes) -> Tuple[Optional[str], Optional[str]]:
    """(file rule, decoded text): a file-level rule when the blob cannot be scanned as text."""
    if len(blob) > MAX_BLOB:
        return "file.too-large", None
    if b"\0" in blob[:BINARY_SNIFF]:
        return "file.binary", None
    try:
        return None, blob.decode("utf-8")
    except UnicodeDecodeError:
        return "file.undecodable", None


_HUNK_RE = re.compile(rb"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def added_lines(base: str, path: str) -> List[Tuple[int, bytes]]:
    diff = git("diff", "--cached", "--no-renames", "--no-ext-diff", "--no-textconv", "--no-color", "--text",
               "--no-relative", "-U0", base, "--", path)
    lines: List[Tuple[int, bytes]] = []
    no = 0
    in_hunk = False
    for raw in diff.split(b"\n"):
        m = _HUNK_RE.match(raw)
        if m:
            no = int(m.group(1))
            in_hunk = True
            continue
        if not in_hunk:
            continue
        if raw.startswith(b"+"):
            lines.append((no, raw[1:]))
            no += 1
        elif raw.startswith(b"diff --git"):
            in_hunk = False
    return lines


def scan(message_files: List[str]) -> int:
    if os.environ.get("GIT_INDEX_FILE"):
        raise ScanError("GIT_INDEX_FILE is set: refusing to scan another index than the repository's own")
    messages = []
    for mf in message_files:
        try:
            with open(mf, "rb") as fh:
                messages.append(fh.read())
        except OSError as exc:
            raise ScanError(f"cannot read message file {show(mf)}: {exc.strerror}")
    try:
        top = git("rev-parse", "--show-toplevel").decode().strip()
    except ScanError:
        raise ScanError("not inside a git repository work tree")
    os.chdir(top)
    if git("ls-files", "-u", "-z"):
        raise ScanError("the index has unmerged paths; resolve the merge first")
    try:
        head: Optional[str] = git("rev-parse", "--verify", "-q", "HEAD^{commit}").decode().strip()
    except ScanError:
        head = None
    base = head or git("hash-object", "-t", "tree", "--stdin", data=b"").decode().strip()

    out: List[str] = []
    allowed = load_allowlist(head, out)
    stage = {}
    for rec in git("ls-files", "-s", "-z").split(b"\0"):
        if rec:
            meta, _, p = rec.partition(b"\t")
            mode, sha, _st = meta.split()
            stage[p.decode("utf-8", "surrogateescape")] = (mode.decode(), sha.decode())
    status = git("diff", "--cached", "--no-renames", "--no-ext-diff", "--no-relative", "--name-status", "-z", base)
    fields = status.split(b"\0")
    changes: List[Tuple[str, str]] = []
    i = 0
    while i + 1 < len(fields):
        st, p = fields[i].decode(), fields[i + 1].decode("utf-8", "surrogateescape")
        changes.append((st[:1], p))
        i += 2

    hits = 0
    scanned = 0

    def report(path: str, line: Optional[int], rid: str, kind: str, fp: str) -> None:
        nonlocal hits
        where = f"{show(path)}:{line if line is not None else '-'}"
        aid = allowed.get((rid, path, fp))
        if aid:
            out.append(f"ALLOWED {show(aid)} {where} {rid}")
            return
        hits += 1
        out.append(f"HIT {where} {rid} {kind}={fp}")

    for st, path in changes:
        if st == "D" or path not in stage:
            continue
        mode, sha = stage[path]
        if mode == "160000":
            continue  # a submodule pointer has no content here
        scanned += 1
        blob = git("cat-file", "blob", sha)
        fsha = hashlib.sha256(blob).hexdigest()
        nr = name_rule(path)
        if nr:
            report(path, None, nr, "fileSha256", fsha)
        frule, text = _blob_hits(path, blob)
        if frule:
            report(path, None, frule, "fileSha256", fsha)
            continue
        if st == "A":
            numbered = list(enumerate(text.split("\n"), 1))
        else:
            numbered = []
            for no, raw in added_lines(base, path):
                try:
                    numbered.append((no, raw.decode("utf-8")))
                except UnicodeDecodeError:
                    report(path, None, "file.undecodable", "fileSha256", fsha)
                    numbered = []
                    break
        for no, line in numbered:
            line = line.rstrip("\r")
            hit = content_rule(line)
            if hit:
                report(path, no, hit[0], "lineSha256", line_sha256(line))
    for raw in messages:
        text = raw.decode("utf-8", "surrogateescape")
        for no, line in enumerate(text.split("\n"), 1):
            hit = content_rule(line.rstrip("\r"))
            if hit:
                report("commit-message", no, hit[0], "lineSha256", line_sha256(line))

    for line in out:
        print(line)
    if hits:
        print(f"SECRET-SCAN REFUSED hits={hits} (remove the secret from the staged content; a false alarm needs an "
              f"allow-list entry Sensei approves, committed before this commit: {ALLOWLIST_PATH})")
        return 1
    print(f"SECRET-SCAN clean files={scanned}")
    return 0


def main(argv: List[str]) -> int:
    message_files: List[str] = []
    root = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(__doc__)
            return 0
        if a == "--list-rules":
            for rid, label, _rx in CONTENT_RULES:
                print(f"{rid}\t{label}")
            for rid, label in list(NAME_RULES.items()) + list(FILE_RULES.items()):
                print(f"{rid}\t{label}")
            return 0
        if a == "--staged":
            i += 1
            continue
        if a in ("--message-file", "--root") and i + 1 < len(argv):
            if a == "--root":
                root = argv[i + 1]
            else:
                message_files.append(os.path.abspath(argv[i + 1]))
            i += 2
            continue
        print(f"error: unknown or incomplete option: {show(a)} (see --help)", file=sys.stderr)
        return 2
    try:
        if root is not None:
            try:
                os.chdir(root)
            except OSError as exc:
                raise ScanError(f"--root {show(root)}: {exc.strerror}")
        return scan(message_files)
    except ScanError as exc:
        print(f"error: {exc} (commit refused: the secret scan could not run)", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
