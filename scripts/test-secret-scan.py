#!/usr/bin/env python3
"""Behavior tests for templates/.agents-v0/scripts/secret_scan.py (onboard fix JO-8 / SOC-9, Sasuke).

Run from anywhere: python3 scripts/test-secret-scan.py. Every case builds its own scratch git repository in one
temp folder, which this run removes at the end (it removes nothing else). No network, no agent, no model call.

Test ids (jiraiya-onboard-test-cases-20261101.md): N6 staged secret refused, N16 an agent's own allow-list entry
is ignored (HEAD-only read), N43 rename and binary, N44 errors exit 2, N45 bad allow-list entries ignored,
N47 commit message, E4 false alarm cleared by the allow-list, E25 content rules and a clean install with zero hits.
Fake secrets are built at run time, so this file itself holds none.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True  # importing the scanner and the hook must leave no __pycache__ in the kit

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCANNER = os.path.join(ROOT, "templates", ".agents-v0", "scripts", "secret_scan.py")
CHECK_LESSONS = os.path.join(ROOT, "templates", ".agents-v0", "scripts", "check-lessons.sh")
HOOK_POLICY = os.path.join(ROOT, "core", "common", "hooks", "hook-policy.py")
INSTALL = os.path.join(ROOT, "scripts", "install.sh")
CHECK_INSTALLED = os.path.join(ROOT, "scripts", "check-installed-kit.sh")

# Fake secrets, assembled so the source file never contains one literally.
AWS = "AKIA" + "QZ7X3B5N8M2K4J6H"
GHP = "ghp_" + "Zq8Lw2Xv5Nb7Mc9Rt4Ys6Ud1Fh3Gk0Jp2Ae5"
GLPAT = "glpat-" + "Xy7Zq2Wv9Lm4Np8Rs3Tu6"
API_TOKEN_VAL = "abcd1234" + "efgh"
BEARER = "eyQ8sLw2Xv5Nb7Mc9Rt4Ys6U"
PEM_HEAD = "-----BEGIN " + "RSA PRIVATE KEY-----"
SECRETS = [AWS, GHP, GLPAT, API_TOKEN_VAL, BEARER, "MIIEowIBAAKCAQEA7fake"]

passed = failed = 0
GIT_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
GIT_ENV.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
                "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"})


def check(cond: bool, label: str, detail: str = "") -> None:
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print(f"FAIL: {label}" + (f"\n    {detail}" if detail else ""), file=sys.stderr)


def git(repo: str, *args: str) -> str:
    return subprocess.run(["git", "-c", "commit.gpgsign=false", *args], cwd=repo, env=GIT_ENV, check=True,
                          capture_output=True, text=True).stdout


def new_repo(base: str, name: str, commit_files: dict = None) -> str:
    repo = os.path.join(base, name)
    os.makedirs(repo)
    git(repo, "init", "-q", "-b", "main")
    if commit_files is not None:
        for rel, body in commit_files.items():
            write(repo, rel, body)
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "base", "--allow-empty")
    return repo


def write(repo: str, rel: str, body) -> None:
    p = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(p) or repo, exist_ok=True)
    mode = "wb" if isinstance(body, bytes) else "w"
    with open(p, mode) as fh:
        fh.write(body)


def scan(repo: str, *args: str, env: dict = None):
    e = dict(GIT_ENV)
    e.update(env or {})
    r = subprocess.run([sys.executable, SCANNER, *(args or ("--staged",))], cwd=repo, env=e,
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    for s in SECRETS:  # the scanner never prints a secret value (all runs)
        check(s not in out, f"output never contains the secret value ({s[:4]}...)", out)
    return r.returncode, out


def line_sha(line: str) -> str:
    return hashlib.sha256(line.rstrip().encode("utf-8")).hexdigest()


def entry(**over) -> dict:
    e = {"id": "SA-1", "ruleId": "content.assignment", "path": "app/config.txt", "lineSha256": "0" * 64,
         "reason": "test fixture value, not a real key", "approvedBy": "Sensei",
         "approvedAt": "2026-11-02T09:00:00+08:00",
         "approvalSource": {"channel": "team chat", "messageTime": "2026-11-02T09:00:00+08:00",
                            "quote": "OK, allow-list it"}}
    e.update(over)
    return e


def allowlist(*entries) -> str:
    return json.dumps({"version": 1, "entries": list(entries)}, indent=2) + "\n"


def main() -> int:
    if not os.path.isfile(SCANNER):
        print(f"FAIL: scanner missing: {SCANNER}", file=sys.stderr)
        return 1
    tmp = tempfile.mkdtemp(prefix="test-secret-scan-")
    try:
        run_cases(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)  # only the folder this run created
    print(f"test-secret-scan: {passed} passed, {failed} failed")
    return 1 if failed else 0


def run_cases(tmp: str) -> None:
    al = ".agents-v0/secret-allowlist.json"

    # --- N6 / staged vs unstaged -------------------------------------------------------------------------------
    r = new_repo(tmp, "staged", {"README.md": "hello\n"})
    rc, out = scan(r)
    check(rc == 0, "N6 clean index exits 0", out)
    write(r, "app/settings.txt", f"aws = {AWS}\n")  # unstaged, untracked
    rc, out = scan(r)
    check(rc == 0, "N6 an unstaged secret is not scanned (index only)", out)
    git(r, "add", "app/settings.txt")
    rc, out = scan(r)
    check(rc == 1, "N6 a staged secret exits 1", out)
    check("app/settings.txt:1" in out and "content.aws-key-id" in out, "N6 prints path:line and rule id", out)
    check("lineSha256=" + line_sha(f"aws = {AWS}") in out, "N6 prints the line fingerprint", out)
    write(r, "app/settings.txt", "aws = none\n")  # working tree cleaned, index still holds the secret
    rc, out = scan(r)
    check(rc == 1, "N6 the index is scanned, not the working tree", out)
    # A modified file: only the added lines count; a committed line is not re-reported.
    r = new_repo(tmp, "modified", {"a.txt": "one\ntwo\n"})
    write(r, "a.txt", f"one\ntwo\ntoken = {GHP}\n")
    git(r, "add", "a.txt")
    rc, out = scan(r)
    check(rc == 1 and "a.txt:3" in out and "content.github-token" in out, "N6 modified file: added line 3", out)
    # Unborn branch (greenfield bootstrap, first commit)
    r = new_repo(tmp, "unborn")
    write(r, "x.txt", "plain\n")
    git(r, "add", "x.txt")
    rc, out = scan(r)
    check(rc == 0, "unborn HEAD: a clean first commit exits 0", out)
    write(r, "y.txt", f"k={GLPAT}\n")
    git(r, "add", "y.txt")
    rc, out = scan(r)
    check(rc == 1 and "content.gitlab-token" in out, "unborn HEAD: a staged secret exits 1", out)

    # --- file-name rules (the hook's list) -----------------------------------------------------------------------
    for rel, want in [("config/.env", 1), (".env.local", 1), (".env.example", 0), ("deploy/server.pem", 1),
                      ("keys/id_rsa", 1), ("keys/id_rsa.pub", 0), ("credentials.json", 1), (".npmrc", 1),
                      (".docker/config.json", 1), ("certs/app.p12", 1), ("docs/notes.md", 0)]:
        r = new_repo(tmp, "name-" + rel.replace("/", "_"), {"README.md": "x\n"})
        write(r, rel, "nothing secret here\n")
        git(r, "add", "-f", rel)
        rc, out = scan(r)
        check(rc == want, f"file-name rule: {rel} -> exit {want}", out)
        if want:
            check("name." in out and "fileSha256=" in out, f"file-name rule: {rel} prints name.* and fileSha256", out)

    # --- E25 content rules -----------------------------------------------------------------------------------
    cases = [
        (f"API_TOKEN={API_TOKEN_VAL}", 1, "content.assignment"),
        (f"Authorization: Bearer {BEARER}", 1, "content.bearer"),
        (PEM_HEAD, 1, "content.private-key"),
        (f"export GH={GHP}", 1, "content.github-token"),
        (f"db: postgres://app:{API_TOKEN_VAL}@db/app", 1, "content.url-credential"),
        ("AccountKey=" + "Qm9ndXNLZXlGb3JUZXN0aW5nT25seTEyMw==", 1, "content.azure-key"),
        ("  tokens: varchar_255", 0, ""),
        ("            token = match.group(1)", 0, ""),
        ('SECRET = re.compile(r"(^|/)(\\.env)$")', 0, ""),
        ("password: <your-password>", 0, ""),
        ("token: ${CI_JOB_TOKEN}", 0, ""),
        ("curl -H 'Authorization: Bearer $TOKEN' https://x", 0, ""),
    ]
    for i, (line, want, rule) in enumerate(cases):
        r = new_repo(tmp, f"content-{i}", {"README.md": "x\n"})
        write(r, "notes/a.txt", "intro\n" + line + "\n")
        git(r, "add", "notes/a.txt")
        rc, out = scan(r)
        check(rc == want, f"E25 content rule {rule or 'none'}: exit {want} for case {i}", out)
        if want:
            check(rule in out and "notes/a.txt:2" in out, f"E25 {rule} reported at line 2", out)

    # --- N43 rename and binary -------------------------------------------------------------------------------
    r = new_repo(tmp, "rename", {"docs/old.txt": f"k = {AWS}\n"})
    git(r, "mv", "docs/old.txt", "docs/new.txt")
    rc, out = scan(r)
    check(rc == 1 and "docs/new.txt:1" in out, "N43 a renamed file is scanned as new content (--no-renames)", out)
    r = new_repo(tmp, "binary", {"README.md": "x\n"})
    blob = b"\x89PNG\r\n\x1a\n\x00\x00fake"
    write(r, "img/logo.png", blob)
    git(r, "add", "img/logo.png")
    rc, out = scan(r)
    check(rc == 1 and "file.binary" in out, "N43 a staged binary is refused", out)
    fsha = hashlib.sha256(blob).hexdigest()
    write(r, al, allowlist(entry(id="SA-bin", ruleId="file.binary", path="img/logo.png", lineSha256=None,
                                 fileSha256=fsha)))
    # strip the None key
    data = json.loads(open(os.path.join(r, al)).read())
    data["entries"][0].pop("lineSha256")
    write(r, al, json.dumps(data))
    git(r, "reset", "-q")
    git(r, "add", al)
    git(r, "commit", "-qm", "allow-list")
    git(r, "add", "img/logo.png")
    rc, out = scan(r)
    check(rc == 0 and "ALLOWED SA-bin" in out, "N43 a binary passes with its fileSha256 allow-listed", out)

    # --- E4 allow-list: exact path + fingerprint, read from HEAD only ------------------------------------------
    line = f"API_TOKEN={API_TOKEN_VAL}"
    good = entry(id="SA-1", ruleId="content.assignment", path="app/config.txt", lineSha256=line_sha(line))
    r = new_repo(tmp, "allow", {"README.md": "x\n", al: allowlist(good)})
    write(r, "app/config.txt", line + "\n")
    git(r, "add", "app/config.txt")
    rc, out = scan(r)
    check(rc == 0 and "ALLOWED SA-1" in out, "E4 a false alarm on the exact path and fingerprint is allowed", out)
    write(r, "other/config.txt", line + "\n")
    git(r, "add", "other/config.txt")
    rc, out = scan(r)
    check(rc == 1 and "other/config.txt:1" in out, "E4 the same line on another path is still refused", out)
    # Another line in the same file is not covered.
    r = new_repo(tmp, "allow2", {"README.md": "x\n", al: allowlist(good)})
    write(r, "app/config.txt", line + "\n" + f"API_TOKEN={API_TOKEN_VAL}9\n")
    git(r, "add", "app/config.txt")
    rc, out = scan(r)
    check(rc == 1 and "app/config.txt:2" in out and "ALLOWED SA-1" in out, "E4 a different line is not covered", out)

    # N16 / N45: an entry in the working tree or only in the index (the commit that adds it) is ignored.
    r = new_repo(tmp, "wt-only", {"README.md": "x\n"})
    write(r, "app/config.txt", line + "\n")
    git(r, "add", "app/config.txt")
    write(r, al, allowlist(good))
    rc, out = scan(r)
    check(rc == 1 and "ALLOWED" not in out, "N16 an allow-list edited only in the working tree is ignored", out)
    git(r, "add", al)
    rc, out = scan(r)
    check(rc == 1 and "ALLOWED" not in out, "N45 an entry cannot approve the commit that adds it", out)

    # N45 bad entries are ignored and reported; the hit stays.
    bad_entries = [
        ("glob path", entry(id="SA-g", path="app/*.txt", lineSha256=line_sha(line))),
        ("missing field", {k: v for k, v in entry(id="SA-m", lineSha256=line_sha(line)).items() if k != "approvedBy"}),
        ("expired", entry(id="SA-e", lineSha256=line_sha(line), expiresAt="2020-01-01T00:00:00+08:00")),
        ("time without offset", entry(id="SA-t", lineSha256=line_sha(line), approvedAt="2026-11-02T09:00:00")),
        ("stale fingerprint", entry(id="SA-s", lineSha256=line_sha(line + "x"))),
        ("both fingerprints", entry(id="SA-b", lineSha256=line_sha(line), fileSha256="1" * 64)),
        ("lineSha256 on a name rule", entry(id="SA-n", ruleId="name.suffix", path="app/config.txt",
                                            lineSha256=line_sha(line))),
    ]
    for label, e in bad_entries:
        r = new_repo(tmp, "bad-" + label.replace(" ", "-"), {"README.md": "x\n", al: allowlist(e)})
        write(r, "app/config.txt", line + "\n")
        git(r, "add", "app/config.txt")
        rc, out = scan(r)
        check(rc == 1 and "ALLOWED" not in out, f"N45 {label}: the entry is ignored and the hit stays", out)
        if label != "stale fingerprint":
            check("INVALID-ENTRY" in out, f"N45 {label}: the entry is reported as invalid", out)

    # N44 errors exit 2 (fail closed)
    r = new_repo(tmp, "malformed", {"README.md": "x\n", al: "{ not json\n"})
    write(r, "a.txt", "fine\n")
    git(r, "add", "a.txt")
    rc, out = scan(r)
    check(rc == 2, "N44 a malformed allow-list at HEAD exits 2", out)
    r = new_repo(tmp, "wrongshape", {"README.md": "x\n", al: "[1, 2]\n"})
    rc, out = scan(r)
    check(rc == 2, "N44 an allow-list that is not an object with entries exits 2", out)
    rc, out = scan(tmp)  # not a repository
    check(rc == 2, "N44 outside a git repository exits 2", out)
    r = new_repo(tmp, "idx", {"README.md": "x\n"})
    rc, out = scan(r, env={"GIT_INDEX_FILE": os.path.join(r, "other-index")})
    check(rc == 2, "N44 GIT_INDEX_FILE set (another index) exits 2", out)
    with open(os.path.join(r, ".git", "index"), "wb") as fh:
        fh.write(b"garbage index")
    rc, out = scan(r)
    check(rc == 2, "N44 an unreadable index exits 2", out)
    rc, out = scan(new_repo(tmp, "usage", {"README.md": "x\n"}), "--bogus")
    check(rc == 2, "N44 an unknown option exits 2", out)

    # N47 commit message
    r = new_repo(tmp, "msg", {"README.md": "x\n"})
    write(r, "msg.txt", f"onboard: approved\n\nkey {AWS}\n")
    rc, out = scan(r, "--staged", "--message-file", "msg.txt")
    check(rc == 1 and "commit-message:3" in out, "N47 a secret in the commit message is refused", out)
    write(r, "msg2.txt", "onboard: approved\n")
    rc, out = scan(r, "--staged", "--message-file", "msg2.txt")
    check(rc == 0, "N47 a clean commit message passes", out)

    # --- one rule set: the scanner's file-name list is the hook's list --------------------------------------------
    def load(path, name):
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    ss = load(SCANNER, "secret_scan_under_test")
    hp = load(HOOK_POLICY, "hook_policy_under_test")
    for attr in ("SECRET_BASENAMES", "SECRET_SUFFIXES"):
        check(getattr(ss, attr) == getattr(hp, attr), f"file-name list parity: {attr} equals hook-policy.py")
    for attr in ("SECRET_PATH_RE", "SECRET_BASENAME_RE"):
        check(getattr(ss, attr).pattern == getattr(hp, attr).pattern, f"file-name list parity: {attr} equals hook-policy.py")

    # check-lessons (and through it the opt-in pre-push hook) uses the scanner's content rules.
    r = new_repo(tmp, "lessons", {"README.md": "x\n"})
    write(r, "docs/agents-v0/lessons.md", "# Lessons\n\n## Active lessons\n\n_No entries yet._\n")
    write(r, "docs/agents-v0/lessons-archive.md", "# Lessons archive\n")
    res = subprocess.run(["sh", CHECK_LESSONS], cwd=r, env=GIT_ENV, capture_output=True, text=True)
    check(res.returncode == 0, "check-lessons: empty lessons pass", res.stdout + res.stderr)
    with open(os.path.join(r, "docs/agents-v0/lessons-archive.md"), "a") as fh:
        fh.write(f"\nAPI_TOKEN={API_TOKEN_VAL}\n")
    res = subprocess.run(["sh", CHECK_LESSONS], cwd=r, env=GIT_ENV, capture_output=True, text=True)
    check(res.returncode != 0 and "looks like a secret" in res.stdout + res.stderr,
          "check-lessons uses the shared rules (API_TOKEN= is caught)", res.stdout + res.stderr)

    # --- install: seeded, hashed, empty allow-list never overwritten; a clean install has zero hits (E25) --------
    proj = new_repo(tmp, "proj", {"README.md": "x\n"})
    env = dict(GIT_ENV)
    env["KIT_VALIDATING"] = "1"
    res = subprocess.run(["sh", INSTALL, proj], cwd=ROOT, env=env, capture_output=True, text=True)
    check(res.returncode == 0, "install: first install succeeds", res.stdout[-2000:] + res.stderr[-2000:])
    check(os.path.isfile(os.path.join(proj, ".agents-v0/scripts/secret_scan.py")), "install seeds secret_scan.py")
    alp = os.path.join(proj, al)
    ok = os.path.isfile(alp)
    check(ok, "install creates .agents-v0/secret-allowlist.json")
    if ok:
        data = json.load(open(alp))
        check(data.get("entries") == [], "install: the allow-list starts empty", json.dumps(data))
    res = subprocess.run(["sh", CHECK_INSTALLED, proj], cwd=ROOT, env=GIT_ENV, capture_output=True, text=True)
    check(res.returncode == 0 and "HASH-OK" in res.stdout, "check-installed-kit: HASH-OK with secret_scan.py",
          res.stdout + res.stderr)
    git(proj, "add", "-A")
    rc, out = scan(proj)
    check(rc == 0, "E25 a clean install, fully staged, has zero hits", out[-3000:])
    if ok:
        write(proj, al, allowlist(good))
        res = subprocess.run(["sh", INSTALL, "--update", "--quick", "--allow-in-flight", proj], cwd=ROOT, env=env,
                             capture_output=True, text=True)
        check(res.returncode == 0, "install --update succeeds", res.stdout[-2000:] + res.stderr[-2000:])
        check("SA-1" in open(alp).read(), "install --update never overwrites the allow-list")


if __name__ == "__main__":
    sys.exit(main())
