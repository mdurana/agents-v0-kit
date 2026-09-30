#!/usr/bin/env python3
"""Unit tests for hook-policy.py (run from kit root: python3 scripts/test-hook-policy.py)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLICY = os.path.join(ROOT, "core", "hooks", "hook-policy.py")


def _run(mode: str, env_extra: dict) -> str:
    env = {**os.environ, **env_extra}
    out = subprocess.check_output([sys.executable, POLICY, mode], env=env, text=True)
    return json.loads(out)["action"]


def shell(cmd: str) -> str:
    return _run("shell", {"HOOK_CMD": cmd})


def path(p: str) -> str:
    return _run("path", {"HOOK_PATH": p})


def mcp(tool: str, server: str = "", policy: str = "") -> str:
    env = {"HOOK_MCP_TOOL": tool, "HOOK_MCP_SERVER": server}
    env["HOOK_MCP_POLICY"] = policy or os.path.join(ROOT, "core", "hooks", "mcp-policy.json")
    return _run("mcp", env)


SHELL_CASES = [
    # Force-push and history rewrites
    ("git push origin main --force", "block"),
    ("git push -f", "block"),
    ("git push origin +main", "block"),
    ("git -c foo=bar push --force", "block"),
    ("git -C repo push --force-with-lease", "block"),
    ("sudo git push --force", "block"),
    ("env git push --force", "block"),
    ("command git push --force", "block"),
    ("nohup git push --force", "block"),
    ("eval git push --force", "block"),
    ("echo $(git push --force)", "block"),
    ("echo `git push --force`", "block"),
    ("bash -c 'git push --force'", "block"),
    ("cd x && git push --force", "block"),
    ("git status; git reset --hard", "block"),
    ("git clean -fdx", "block"),
    ("git push", "ask"),
    ("git commit -m x", "ask"),
    ("git checkout -- src", "ask"),
    ("git status", "allow"),
    ("git rm --cached file.txt", "allow"),
    # Destructive deletes
    ("rm -r dir", "block"),
    ("rm -rf dir", "block"),
    ("rm -fr dir", "block"),
    ("rm -R dir", "block"),
    ("rm -r -f dir", "block"),
    ("rm --recursive dir", "block"),
    ("rm -f build.log", "allow"),
    ("rm build.log", "allow"),
    ("docker rm -f my-container", "allow"),
    ("npm run build -- --dry-run", "allow"),
    ("find . -name '*.tmp' -delete", "ask"),
    ("kubectl delete ns prod", "block"),
    ("helm uninstall app", "block"),
    ("terraform apply -auto-approve", "block"),
    # Secrets
    ("cat .env", "block"),
    ("grep KEY .env", "block"),
    ("sed -n p .env.local", "block"),
    ("base64 .env", "block"),
    ("cp .env /tmp/x", "block"),
    ("python3 -c \"print(open('.env').read())\"", "block"),
    ("printenv", "block"),
    ("env | grep TOKEN", "block"),
    ("cat .env.example", "allow"),
    ("cp .env.example .env", "allow"),
    ("git add .env.example", "allow"),
    ("touch .env", "allow"),
    # Protected paths via shell
    ("echo x > .cursor/hooks.json", "block"),
    ("sed -i s/a/b/ .cursor/hooks/pre-shell.sh", "block"),
    ("cp evil.sh .claude/hooks/pre-shell.sh", "block"),
    ("rm .cursor/hooks.json", "block"),
    ("python3 -c \"open('.cursor/hooks.json','w').write('{}')\"", "block"),
    ("node -e \"require('fs').writeFileSync('.github/workflows/x.yml','')\"", "block"),
    ("cat .cursor/hooks.json", "allow"),
    # Publish / deploy
    ("npm publish", "ask"),
    ("docker push img", "ask"),
    ("gh pr merge 12 --squash", "block"),
    ("gh release create v1", "ask"),
    # Benign
    ("ls -la", "allow"),
    ("mvn -B clean verify", "allow"),
    ("npm test", "allow"),
]

PATH_CASES = [
    (".cursor/hooks.json", "block"),
    (".cursor/agents/foo.md", "block"),
    (".cursor/rules/org/x.mdc", "block"),
    (".github/workflows/ci.yml", "block"),
    ("AGENTS.md", "block"),
    ("docs/requirements/foo.md", "ask"),
    ("docs/milestones/p0.md", "ask"),
    ("src/Main.java", "allow"),
]


def main() -> int:
    fail = 0

    def check(got: str, want: str, label: str) -> None:
        nonlocal fail
        if got != want:
            print(f"FAIL: {label}: want {want}, got {got}", file=sys.stderr)
            fail = 1

    for cmd, want in SHELL_CASES:
        check(shell(cmd), want, f"shell `{cmd}`")
    for p, want in PATH_CASES:
        check(path(p), want, f"path {p}")

    # MCP: bundled policy (github/gitlab allowlists). Unlisted servers use default "ask".
    check(mcp("list_issues", "github"), "allow", "mcp github list")
    check(mcp("create_pull_request", "github"), "ask", "mcp github create")
    check(mcp("merge_pull_request", "github"), "block", "mcp github merge")
    check(mcp("mcp__github__get_file_contents"), "allow", "mcp claude-style github get")
    check(mcp("execute_sql", "postgres"), "ask", "mcp unlisted execute asks")
    check(mcp("list_tables", "postgres"), "ask", "mcp unlisted list asks")
    check(mcp("prod_delete_cluster", "infra"), "ask", "mcp unlisted delete asks")
    check(mcp("api_get_project", "gitlab"), "allow", "mcp gitlab api_get")
    check(mcp("api_create_issue", "gitlab"), "ask", "mcp gitlab api_create asks")
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"default": "ask", "servers": {}}, f)
        strict = f.name
    try:
        check(mcp("list_things", "unknown", strict), "ask", "mcp strict default")
    finally:
        os.unlink(strict)

    total = len(SHELL_CASES) + len(PATH_CASES) + 10
    if fail:
        print("test-hook-policy: FAILED", file=sys.stderr)
        return 1
    print(f"test-hook-policy: OK ({total} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
