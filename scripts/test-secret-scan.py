#!/usr/bin/env python3
"""Behavior tests for templates/.agents-v0/scripts/secret_scan.py and guard-common.sh (onboard redo, Design: D1).

Carried from 6e833b5c/e7892312 (workflow-fixes-onboard), Design: D1. Adapted: the check-lessons section is dropped
(check-lessons.sh keeps its own rules in the redo, not D1); new D1 sections cover secret_scan.py --commits,
guard-common.sh (scan-staged, scan-push, branch-check, paths) and the pre-push hook on a real `git push`.

Run from anywhere: python3 scripts/test-secret-scan.py. Every case builds its own scratch git repository in one
temp folder (under $TMPDIR), which this run removes at the end unless KEEP_TEST_TMP=1 (it removes nothing else).
No network, no agent, no model call.

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
GUARD = os.path.join(ROOT, "templates", ".agents-v0", "scripts", "guard-common.sh")
PRE_PUSH = os.path.join(ROOT, "templates", ".agents-v0", "hooks", "pre-push")
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
    """lineSha256: sha256 of the matched line's UTF-8 bytes with only its line ending (LF, CRLF) removed."""
    return hashlib.sha256(line.rstrip("\r\n").encode("utf-8")).hexdigest()


def scan3(repo: str, *args: str):
    """(exit code, stdout, stderr); the never-print-a-secret check runs on both streams."""
    r = subprocess.run([sys.executable, SCANNER, *(args or ("--staged",))], cwd=repo, env=dict(GIT_ENV),
                       capture_output=True, text=True)
    for s in SECRETS:
        check(s not in r.stdout + r.stderr, f"output never contains the secret value ({s[:4]}...)", r.stdout + r.stderr)
    return r.returncode, r.stdout, r.stderr


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
        run_d1_cases(tmp)
    finally:
        if os.environ.get("KEEP_TEST_TMP") == "1":
            print(f"test-secret-scan: kept {tmp}")
        else:
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
    # (rev 6 point 4) a malformed allow-list at HEAD is reported and all its entries are ignored: no crash, and
    #   the hits stay hits (fail closed); see the reader cases below.
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

    # --- allow-list reader (rev 6 point 4 / point 11): HEAD only, rule + path + fingerprint, ALLOWED <id> -------
    tok = f"API_TOKEN={API_TOKEN_VAL}"
    awsl = f"aws = {AWS}"
    ok_e = entry(id="AL-ok", ruleId="content.assignment", path="app/config.txt", lineSha256=line_sha(tok))

    def staged_repo(name, head_files, staged):
        rr = new_repo(tmp, name, head_files)
        for rel, body in staged.items():
            write(rr, rel, body)
            git(rr, "add", "--", rel)
        return rr

    # R1 a valid entry clears exactly its hit; a second, different hit in the same file stays
    r = staged_repo("rd-valid", {"README.md": "x\n", al: allowlist(ok_e)}, {"app/config.txt": tok + "\n"})
    rc, so, se = scan3(r)
    check(rc == 0 and "ALLOWED AL-ok app/config.txt:1 content.assignment" in so and "HIT" not in so,
          "R1 a valid entry clears its hit, prints ALLOWED <id> with rule and path, exits 0", so + se)
    r = staged_repo("rd-second", {"README.md": "x\n", al: allowlist(ok_e)}, {"app/config.txt": tok + "\n" + awsl + "\n"})
    rc, so, se = scan3(r)
    check(rc == 1 and "ALLOWED AL-ok app/config.txt:1 content.assignment" in so
          and "HIT app/config.txt:2 content.aws-key-id" in so and "hits=1" in so,
          "R1 one entry does not clear a second, different hit in the same file", so + se)

    # R2 wrong rule, wrong path, wrong fingerprint: the hit stays
    for label, e in [("wrong rule", dict(ok_e, id="AL-rule", ruleId="content.sk-key")),
                     ("wrong path", dict(ok_e, id="AL-path", path="app/Config.txt")),
                     ("wrong fingerprint", dict(ok_e, id="AL-fp", lineSha256=line_sha(tok + " ")))]:
        r = staged_repo("rd-" + label.replace(" ", "-"), {"README.md": "x\n", al: allowlist(e)},
                        {"app/config.txt": tok + "\n"})
        rc, so, se = scan3(r)
        check(rc == 1 and "ALLOWED" not in so and "HIT app/config.txt:1 content.assignment" in so,
              f"R2 {label}: the hit is not cleared", so + se)

    # R3 an entry only in the index or the working tree (not in HEAD) does not clear the hit
    r = staged_repo("rd-idx", {"README.md": "x\n", al: allowlist()}, {"app/config.txt": tok + "\n", al: allowlist(ok_e)})
    rc, so, se = scan3(r)
    check(rc == 1 and "ALLOWED" not in so, "R3 an entry staged over an empty HEAD allow-list does not count", so + se)
    write(r, al, allowlist(ok_e))
    git(r, "reset", "-q", "--", al)
    rc, so, se = scan3(r)
    check(rc == 1 and "ALLOWED" not in so, "R3 an entry only in the working tree does not count", so + se)
    r = staged_repo("rd-unborn", None, {"app/config.txt": tok + "\n", al: allowlist(ok_e)})
    rc, so, se = scan3(r)
    check(rc == 1 and "ALLOWED" not in so, "R3 no HEAD (unborn branch): no entries, the hit stays", so + se)

    # R4 bad entries are ignored and reported on stderr (id or index plus the reason); the hit stays
    def drop(e, key):
        return {k: v for k, v in e.items() if k != key}

    def drop_src(e, key):
        return dict(e, approvalSource={k: v for k, v in e["approvalSource"].items() if k != key})

    bad = [(f"missing {f}", drop(dict(ok_e, id=f"AL-m-{f}"), f), f"AL-m-{f}" if f != "id" else "#1", f)
           for f in ("id", "ruleId", "path", "reason", "approvedBy", "approvedAt", "approvalSource")]
    bad += [(f"missing approvalSource.{k}", drop_src(dict(ok_e, id=f"AL-s-{k}"), k), f"AL-s-{k}", "approvalSource")
            for k in ("channel", "messageTime", "quote")]
    bad += [
        ("no fingerprint", drop(dict(ok_e, id="AL-none"), "lineSha256"), "AL-none", "exactly one"),
        ("two fingerprints", dict(ok_e, id="AL-two", fileSha256="1" * 64), "AL-two", "exactly one"),
        ("bad approvedAt", dict(ok_e, id="AL-at", approvedAt="yesterday"), "AL-at", "approvedAt"),
        ("approvedAt without offset", dict(ok_e, id="AL-off", approvedAt="2026-11-02T09:00:00"), "AL-off", "approvedAt"),
        ("expired expiresAt", dict(ok_e, id="AL-exp", expiresAt="2026-01-01T00:00:00+08:00"), "AL-exp", "expired"),
        ("glob *", dict(ok_e, id="AL-g1", path="app/*.txt"), "AL-g1", "glob"),
        ("glob ?", dict(ok_e, id="AL-g2", path="app/config.tx?"), "AL-g2", "glob"),
        ("glob [", dict(ok_e, id="AL-g3", path="app/[c]onfig.txt"), "AL-g3", "glob"),
    ]
    for label, e, lab, why in bad:
        r = staged_repo("rd-bad-" + label.replace(" ", "-").replace("*", "s").replace("?", "q").replace("[", "b"),
                        {"README.md": "x\n", al: allowlist(e)}, {"app/config.txt": tok + "\n"})
        rc, so, se = scan3(r)
        check(rc == 1 and "ALLOWED" not in so and "HIT app/config.txt:1" in so,
              f"R4 {label}: the entry is ignored and the hit stays", so + se)
        rep = [ln for ln in se.splitlines() if ln.startswith(f"INVALID-ENTRY {lab}:")]
        check(len(rep) == 1 and why in rep[0], f"R4 {label}: reported on stderr as INVALID-ENTRY {lab} ({why})", so + se)
    # a valid future expiresAt still works
    r = staged_repo("rd-future", {"README.md": "x\n", al: allowlist(dict(ok_e, expiresAt="2099-01-01T00:00:00+08:00"))},
                    {"app/config.txt": tok + "\n"})
    rc, so, se = scan3(r)
    check(rc == 0 and "ALLOWED AL-ok" in so, "R4 an entry with a future expiresAt clears its hit", so + se)

    # R5 a malformed allow-list at HEAD is reported, every entry is ignored, the hit stays a hit (no crash)
    for label, body in [("not JSON", "{ not json, " + json.dumps(ok_e) + "\n"), ("wrong shape", "[1, 2]\n"),
                        ("wrong version", json.dumps({"version": 2, "entries": [ok_e]}) + "\n")]:
        r = staged_repo("rd-mal-" + label.replace(" ", "-"), {"README.md": "x\n", al: body},
                        {"app/config.txt": tok + "\n"})
        rc, so, se = scan3(r)
        check(rc == 1 and "HIT app/config.txt:1 content.assignment" in so and "ALLOWED" not in so
              and "INVALID-ALLOWLIST" in se and "Traceback" not in se,
              f"R5 malformed allow-list ({label}): reported on stderr, hit stays, exit 1", so + se)
    r = staged_repo("rd-mal-clean", {"README.md": "x\n", al: "{ not json\n"}, {"a.txt": "fine\n"})
    rc, so, se = scan3(r)
    check(rc == 0 and "INVALID-ALLOWLIST" in se, "R5 malformed allow-list with no hit: reported, exits 0", so + se)

    # R6 fileSha256 on a file-name rule
    pem = "harmless test fixture, not a key\n"
    pem_e = drop(dict(ok_e, id="AL-pem", ruleId="name.suffix", path="deploy/server.pem",
                      fileSha256=hashlib.sha256(pem.encode()).hexdigest()), "lineSha256")
    r = staged_repo("rd-pem", {"README.md": "x\n", al: allowlist(pem_e)}, {"deploy/server.pem": pem})
    rc, so, se = scan3(r)
    check(rc == 0 and "ALLOWED AL-pem deploy/server.pem:- name.suffix" in so,
          "R6 a fileSha256 entry clears a file-name rule hit", so + se)
    r = staged_repo("rd-pem2", {"README.md": "x\n", al: allowlist(pem_e)}, {"deploy/server.pem": pem + "y\n"})
    rc, so, se = scan3(r)
    check(rc == 1 and "ALLOWED" not in so, "R6 a changed file no longer matches its fileSha256", so + se)

    # R7 lineSha256 = sha256 of the line with only its line ending removed (trailing spaces count, CR does not)
    r = staged_repo("rd-trail", {"README.md": "x\n", al: allowlist(dict(ok_e, lineSha256=line_sha(tok + "  ")))},
                    {"app/config.txt": tok + "  \n"})
    rc, so, se = scan3(r)
    check(rc == 0 and "ALLOWED AL-ok" in so, "R7 trailing spaces are part of lineSha256", so + se)
    r = staged_repo("rd-trail2", {"README.md": "x\n", al: allowlist(ok_e)}, {"app/config.txt": tok + "  \n"})
    rc, so, se = scan3(r)
    check(rc == 1 and "lineSha256=" + line_sha(tok + "  ") in so,
          "R7 a line with trailing spaces does not match the stripped line's fingerprint", so + se)
    r = staged_repo("rd-crlf", {"README.md": "x\n", al: allowlist(ok_e)}, {"app/config.txt": (tok + "\r\n").encode()})
    rc, so, se = scan3(r)
    check(rc == 0 and "ALLOWED AL-ok" in so, "R7 a CRLF line ending is not part of lineSha256", so + se)

    # R8 no secret value in any output (also checked on every run by scan()/scan3())
    r = staged_repo("rd-nosecret", {"README.md": "x\n", al: allowlist(dict(ok_e, id="AL-x", path="other.txt"))},
                    {"app/config.txt": awsl + "\n" + tok + "\n"})
    rc, so, se = scan3(r)
    check(rc == 1 and AWS not in so + se and API_TOKEN_VAL not in so + se, "R8 no secret value is printed", so + se)

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


    # --- install: seeded, hashed, empty allow-list never overwritten; a clean install has zero hits (E25) --------
    proj = new_repo(tmp, "proj", {"README.md": "x\n"})
    env = dict(GIT_ENV)
    env["KIT_VALIDATING"] = "1"
    res = subprocess.run(["sh", INSTALL, proj], cwd=ROOT, env=env, capture_output=True, text=True)
    check(res.returncode == 0, "install: first install succeeds", res.stdout[-2000:] + res.stderr[-2000:])
    check(os.path.isfile(os.path.join(proj, ".agents-v0/scripts/secret_scan.py")), "install seeds secret_scan.py")
    check(os.path.isfile(os.path.join(proj, ".agents-v0/scripts/guard-common.sh")), "install seeds guard-common.sh")
    alp = os.path.join(proj, al)
    ok = os.path.isfile(alp)
    check(ok, "install creates .agents-v0/secret-allowlist.json")
    if ok:
        data = json.load(open(alp))
        check(data.get("entries") == [], "install: the allow-list starts empty", json.dumps(data))
    res = subprocess.run(["sh", CHECK_INSTALLED, proj], cwd=ROOT, env=GIT_ENV, capture_output=True, text=True)
    check(res.returncode == 0 and "HASH-OK" in res.stdout, "check-installed-kit: HASH-OK with secret_scan.py and guard-common.sh",
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


# ======================================= Design: D1 (new): push scan, guard =======================================

def guard(repo: str, *args: str, stdin: str = None, script: str = None):
    r = subprocess.run(["sh", script or GUARD, *args], cwd=repo, env=dict(GIT_ENV), input=stdin,
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    for s in SECRETS:
        check(s not in out, f"guard output never contains the secret value ({s[:4]}...)", out)
    return r.returncode, out


def push(repo: str, *args: str):
    r = subprocess.run(["git", "push", *args], cwd=repo, env=dict(GIT_ENV), capture_output=True, text=True)
    out = r.stdout + r.stderr
    for s in SECRETS:
        check(s not in out, f"push output never contains the secret value ({s[:4]}...)", out)
    return r.returncode, out


def commit_all(repo: str, msg: str) -> str:
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", msg)
    return git(repo, "rev-parse", "HEAD").strip()


def run_d1_cases(tmp: str) -> None:
    al = ".agents-v0/secret-allowlist.json"
    zero = "0" * 40

    # --- secret_scan.py --commits ---------------------------------------------------------------------------
    r = new_repo(tmp, "commits", {"README.md": "x\n"})
    c0 = git(r, "rev-parse", "HEAD").strip()
    write(r, "app/settings.txt", f"aws = {AWS}\n")
    c1 = commit_all(r, "add settings")
    write(r, "app/settings.txt", "aws = none\n")
    c2 = commit_all(r, "remove the key again")
    res = subprocess.run([sys.executable, SCANNER, "--commits", "-"], cwd=r, env=dict(GIT_ENV), input=f"{c2}\n",
                         capture_output=True, text=True)
    check(res.returncode == 0, "commits: a clean commit exits 0", res.stdout + res.stderr)
    res = subprocess.run([sys.executable, SCANNER, "--commits", "-"], cwd=r, env=dict(GIT_ENV),
                         input=f"{c1}\n{c2}\n", capture_output=True, text=True)
    o = res.stdout + res.stderr
    check(res.returncode == 1 and "content.aws-key-id" in o and c1[:7] in o,
          "commits: a commit that added a key exits 1 and names the commit", o)
    check(AWS not in o, "commits: the key is never printed", o)
    lst = os.path.join(tmp, "commit-list.txt")
    write(tmp, "commit-list.txt", f"{c0}\n{c1}\n")
    res = subprocess.run([sys.executable, SCANNER, "--commits", lst], cwd=r, env=dict(GIT_ENV), capture_output=True,
                         text=True)
    check(res.returncode == 1, "commits: the list may come from a file", res.stdout + res.stderr)
    # the commit message is scanned too
    write(r, "b.txt", "b\n")
    git(r, "add", "b.txt")
    git(r, "commit", "-qm", f"wire it up with {GHP}")
    c3 = git(r, "rev-parse", "HEAD").strip()
    res = subprocess.run([sys.executable, SCANNER, "--commits", "-"], cwd=r, env=dict(GIT_ENV), input=c3 + "\n",
                         capture_output=True, text=True)
    check(res.returncode == 1 and "content.github-token" in res.stdout + res.stderr and GHP not in res.stdout + res.stderr,
          "commits: a secret in the commit message exits 1", res.stdout + res.stderr)
    # the allow-list is read from the commit's parent, not from the commit that adds the entry (N16 for pushes)
    r2 = new_repo(tmp, "commits-al", {"README.md": "x\n"})
    tok = f"API_TOKEN={API_TOKEN_VAL}"
    write(r2, al, allowlist(entry(id="AL-1", path="app/config.txt", lineSha256=line_sha(tok))))
    write(r2, "app/config.txt", tok + "\n")
    cs = commit_all(r2, "self-approved secret")
    res = subprocess.run([sys.executable, SCANNER, "--commits", "-"], cwd=r2, env=dict(GIT_ENV), input=cs + "\n",
                         capture_output=True, text=True)
    check(res.returncode == 1, "commits: an allow-list entry added in the same commit does not clear it",
          res.stdout + res.stderr)
    write(r2, "app/config.txt", "x\n")
    commit_all(r2, "drop")
    write(r2, "app/config.txt", tok + "\n")
    ca = commit_all(r2, "re-add, the entry is now in the parent")
    res = subprocess.run([sys.executable, SCANNER, "--commits", "-"], cwd=r2, env=dict(GIT_ENV), input=ca + "\n",
                         capture_output=True, text=True)
    check(res.returncode == 0 and "ALLOWED" in res.stdout + res.stderr,
          "commits: an entry committed in the parent clears the line (ALLOWED)", res.stdout + res.stderr)
    # misuse: bad input exits 2 (fail closed)
    for label, args, inp in [("a non-hex id", ["--commits", "-"], "HEAD\n"),
                             ("an unknown commit", ["--commits", "-"], "deadbeefdeadbeef\n"),
                             ("--commits with --staged", ["--commits", "-", "--staged"], c2 + "\n"),
                             ("a missing list file", ["--commits", os.path.join(tmp, "no-such-file")], "")]:
        res = subprocess.run([sys.executable, SCANNER, *args], cwd=r, env=dict(GIT_ENV), input=inp,
                             capture_output=True, text=True)
        check(res.returncode == 2, f"commits misuse: {label} exits 2", res.stdout + res.stderr)

    # --- guard-common.sh: base helpers ---------------------------------------------------------------------------
    gk = new_repo(tmp, "guard-kit", {"README.md": "x\n"})
    os.makedirs(os.path.join(gk, ".agents-v0", "scripts"))
    for src in (GUARD, SCANNER):
        shutil.copy(src, os.path.join(gk, ".agents-v0", "scripts", os.path.basename(src)))
    write(gk, al, allowlist())
    commit_all(gk, "kit")
    g = os.path.join(gk, ".agents-v0", "scripts", "guard-common.sh")
    rc, out = guard(gk, "paths", script=g)
    check(rc == 0 and f"root={os.path.realpath(gk)}" in out and "onboarding_state=docs/agents-v0/onboarding/state.json" in out,
          "guard paths: root and onboarding state path", out)
    rc, out = guard(gk, "branch-check", "main", script=g)
    check(rc == 0 and "OK branch-check: on branch main" in out, "guard branch-check: on the expected branch", out)
    rc, out = guard(gk, "branch-check", "feature/x", script=g)
    check(rc == 1 and "REFUSED branch-check" in out, "guard branch-check: another branch is refused", out)
    git(gk, "checkout", "-q", "--detach")
    rc, out = guard(gk, "branch-check", script=g)
    check(rc == 1 and "detached" in out, "guard branch-check: a detached HEAD is refused", out)
    git(gk, "checkout", "-q", "main")
    rc, out = guard(gk, "no-such-step", script=g)
    check(rc == 2, "guard misuse: an unknown step exits 2", out)
    rc, out = guard(gk, script=g)
    check(rc == 2, "guard misuse: no step exits 2", out)
    lib = subprocess.run(["sh", "-c", f'GC_HERE="{os.path.dirname(g)}" GUARD_COMMON_LIB=1 . "{g}"; '
                          'gc_state_file feature orders; gc_state_file maintain m1; gc_state_file program'],
                         cwd=gk, env=dict(GIT_ENV), capture_output=True, text=True)
    check(lib.returncode == 0 and lib.stdout.split() == ["docs/agents-v0/requirements/orders.state.json",
                                                         "docs/agents-v0/maintain/m1/state.json",
                                                         "docs/agents-v0/program.state.json"],
          "guard as a library: state file paths, no step runs", lib.stdout + lib.stderr)

    # --- D1 check 1: a staged file with a fake key is refused at commit -----------------------------------------
    head0 = git(gk, "rev-parse", "HEAD").strip()
    rc, out = guard(gk, "scan-staged", script=g)
    check(rc == 1 and "nothing is staged" in out, "guard scan-staged: nothing staged is refused", out)
    write(gk, "app/settings.txt", f"aws = {AWS}\n")
    git(gk, "add", "app/settings.txt")
    res = subprocess.run(["sh", "-c", f'sh "{g}" scan-staged && git -c commit.gpgsign=false commit -qm "add settings"'],
                         cwd=gk, env=dict(GIT_ENV), capture_output=True, text=True)
    o = res.stdout + res.stderr
    check(res.returncode != 0 and "REFUSED scan-staged" in o and "content.aws-key-id" in o,
          "D1-1 a staged fake key is refused at commit (scan-staged && git commit)", o)
    check(git(gk, "rev-parse", "HEAD").strip() == head0, "D1-1 the refused commit was not made", "")
    check(AWS not in o, "D1-1 the key is never printed", o)
    git(gk, "reset", "-q", "app/settings.txt")
    os.replace(os.path.join(gk, "app", "settings.txt"), os.path.join(tmp, "settings-moved-aside.txt"))
    write(gk, "notes.md", "plain\n")
    git(gk, "add", "notes.md")
    msgf = os.path.join(tmp, "commit-msg.txt")
    write(tmp, "commit-msg.txt", f"notes with {GLPAT}\n")
    rc, out = guard(gk, "scan-staged", "--message-file", msgf, script=g)
    check(rc == 1 and "content.gitlab-token" in out, "guard scan-staged: a secret in the commit message is refused", out)
    write(tmp, "commit-msg.txt", "notes\n")
    rc, out = guard(gk, "scan-staged", "--message-file", msgf, script=g)
    check(rc == 0 and "OK scan-staged" in out, "guard scan-staged: a clean commit passes", out)
    # misuse: the scanner is missing -> refused (fail closed); outside a work tree -> refused
    gm = new_repo(tmp, "guard-noscanner", {"README.md": "x\n"})
    os.makedirs(os.path.join(gm, ".agents-v0", "scripts"))
    shutil.copy(GUARD, os.path.join(gm, ".agents-v0", "scripts", "guard-common.sh"))
    write(gm, "a.txt", "a\n")
    git(gm, "add", "a.txt")
    rc, out = guard(gm, "scan-staged", script=os.path.join(gm, ".agents-v0", "scripts", "guard-common.sh"))
    check(rc == 1 and "secret_scan.py is missing" in out, "guard misuse: a missing secret_scan.py refuses (fail closed)", out)
    rc, out = guard(gm, "scan-push", stdin=f"refs/heads/main {zero} refs/heads/main {zero}\n",
                    script=os.path.join(gm, ".agents-v0", "scripts", "guard-common.sh"))
    check(rc == 1 and "secret_scan.py is missing" in out, "guard misuse: scan-push without the scanner refuses", out)
    outside = os.path.join(tmp, "not-a-repo")
    os.makedirs(outside)
    rc, out = guard(outside, "scan-staged", script=g)
    check(rc == 1 and "not inside a git work tree" in out, "guard misuse: outside a work tree is refused", out)

    # --- D1 check 2: the same key is refused at git push (installed kit, real pre-push hook) ---------------------
    proj = new_repo(tmp, "push-proj", {"README.md": "x\n"})
    env = dict(GIT_ENV)
    env["KIT_VALIDATING"] = "1"
    res = subprocess.run(["sh", INSTALL, "--git-hooks", proj], cwd=ROOT, env=env, capture_output=True, text=True)
    check(res.returncode == 0, "push: install --git-hooks succeeds", res.stdout[-2000:] + res.stderr[-2000:])
    check(git(proj, "config", "core.hooksPath").strip() == ".agents-v0/hooks", "push: core.hooksPath is set", "")
    commit_all(proj, "install the kit")
    bare = os.path.join(tmp, "push-remote.git")
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", bare], env=GIT_ENV, check=True, capture_output=True)
    git(proj, "remote", "add", "origin", bare)
    rc, out = push(proj, "-q", "origin", "main")
    check(rc == 0, "push: a clean first push passes the pre-push scan", out[-3000:])
    remote_tip = lambda ref="main": subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/heads/{ref}"],
                                                   cwd=bare, env=GIT_ENV, capture_output=True, text=True).stdout.strip()
    clean_tip = git(proj, "rev-parse", "HEAD").strip()
    check(remote_tip() == clean_tip, "push: the remote has the clean tip", "")
    write(proj, "app/settings.txt", f"aws = {AWS}\n")
    git(proj, "add", "app/settings.txt")
    git(proj, "commit", "-qm", "add settings")  # a plain commit outside the guard (no pre-commit hook in D1)
    rc, out = push(proj, "origin", "main")
    check(rc != 0 and "content.aws-key-id" in out and "REFUSED scan-push" in out,
          "D1-2 the same fake key is refused at git push (pre-push scan)", out[-3000:])
    check(remote_tip() == clean_tip, "D1-2 the remote did not receive the commit", "")
    # removing the key in a later commit does not clear the push: the key is still in the history being sent
    write(proj, "app/settings.txt", "aws = none\n")
    commit_all(proj, "remove the key")
    rc, out = push(proj, "origin", "main")
    check(rc != 0 and "content.aws-key-id" in out, "push: a later fix does not clear a key still in the pushed range",
          out[-3000:])
    # a new branch is scanned too (no remote tip: every commit not on a remote-tracking branch)
    rc, out = push(proj, "origin", "main:refs/heads/topic")
    check(rc != 0 and "content.aws-key-id" in out and remote_tip("topic") == "",
          "push: a new branch carrying the key is refused", out[-3000:])
    # back to the clean tip, then a clean commit pushes
    git(proj, "reset", "-q", "--hard", clean_tip)
    write(proj, "notes.md", "plain\n")
    commit_all(proj, "notes")
    rc, out = push(proj, "-q", "origin", "main")
    check(rc == 0 and remote_tip() == git(proj, "rev-parse", "HEAD").strip(), "push: a clean follow-up push passes",
          out[-3000:])
    # the existing verifyPassed state check is kept
    git(proj, "checkout", "-q", "-b", "feature/orders")
    sf = "docs/agents-v0/requirements/orders.state.json"
    write(proj, sf, json.dumps({"lastApprovedPhase": "plan", "verifyPassed": False}) + "\n")
    commit_all(proj, "orders state")
    rc, out = push(proj, "origin", "feature/orders")
    check(rc != 0 and "has not passed /v0-verify" in out, "push: the verifyPassed check still refuses an unverified story",
          out[-3000:])
    write(proj, sf, json.dumps({"lastApprovedPhase": "verify", "verifyPassed": True}) + "\n")
    commit_all(proj, "orders verified")
    rc, out = push(proj, "-q", "origin", "feature/orders")
    check(rc == 0, "push: a verified story with clean commits pushes", out[-3000:])
    git(proj, "checkout", "-q", "main")
    # misuse: guard-common.sh removed from the project -> the push is refused (fail closed)
    gpath = os.path.join(proj, ".agents-v0", "scripts", "guard-common.sh")
    had = os.path.isfile(gpath)
    check(had, "push: install put guard-common.sh in the project")
    if had:
        os.replace(gpath, os.path.join(tmp, "guard-common-moved-aside.sh"))
    write(proj, "more.md", "more\n")
    commit_all(proj, "more")
    rc, out = push(proj, "origin", "main")
    check(rc != 0 and "guard-common.sh is missing" in out, "push misuse: a missing guard-common.sh refuses the push", out)
    if had:
        os.replace(os.path.join(tmp, "guard-common-moved-aside.sh"), gpath)
    # misuse: a branch delete is not scanned and not blocked by the scan
    rc, out = guard(proj, "scan-push", "origin", stdin=f"(delete) {zero} refs/heads/topic2 {'1' * 40}\n",
                    script=gpath)
    check(rc == 0 and "no new commits" in out, "guard scan-push: a delete line sends nothing and passes", out)


if __name__ == "__main__":
    sys.exit(main())
