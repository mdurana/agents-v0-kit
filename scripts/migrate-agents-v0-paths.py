#!/usr/bin/env python3
"""Path migration for target layout: .agents-v0/ and docs/agents-v0/."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "target", "agent-transcripts"}

REPLACEMENTS = [
    ("!docs/build/", "!docs/agents-v0/build/"),
    ("!docs/verify/", "!docs/agents-v0/verify/"),
    ("FETCH_HEAD:ci/", "FETCH_HEAD:.agents-v0/ci/"),
    ("git archive FETCH_HEAD ci ", "git archive FETCH_HEAD .agents-v0/ci "),
    ("templates/.agents-v0/.agents-v0/", "templates/.agents-v0/"),
    ("templates/docs/agents-v0/agents-v0/", "templates/docs/agents-v0/"),
    ("docs/agents-v0/agents-v0/", "docs/agents-v0/"),
    ("templates/docs/agents-v0/", "templates/docs/agents-v0/"),  # noop anchor
    ("templates/ci/", "templates/.agents-v0/ci/"),
    ("templates/scripts/", "templates/.agents-v0/scripts/"),
    ("templates/hooks/", "templates/.agents-v0/hooks/"),
    ("templates/CODEOWNERS", "templates/.gitlab/CODEOWNERS"),
    ("docs/requirements/", "docs/agents-v0/requirements/"),
    ("docs/onboarding/", "docs/agents-v0/onboarding/"),
    ("docs/discovery/", "docs/agents-v0/discovery/"),
    ("docs/design/", "docs/agents-v0/design/"),
    ("docs/build/", "docs/agents-v0/build/"),
    ("docs/verify/", "docs/agents-v0/verify/"),
    ("docs/maintain/", "docs/agents-v0/maintain/"),
    ("docs/milestones/", "docs/agents-v0/milestones/"),
    ("docs/agents-v0/benchmark/reference-project.md", ".agents-v0/scripts/delivery-metrics.sh"),
    ("docs/benchmark/reference-project.md", ".agents-v0/scripts/delivery-metrics.sh"),
    ("docs/diagrams/", "docs/agents-v0/diagrams/"),
    ("docs/release/", "docs/agents-v0/release/"),
    ("docs/agents-v0/security/vapt-pr-checklist.md", "vapt-pr-review.mdc"),
    ("docs/agents-v0/security/vapt-prevention-guardrails.md", "vapt-pr-review.mdc"),
    ("docs/security/vapt-pr-checklist.md", "vapt-pr-review.mdc"),
    ("docs/security/vapt-prevention-guardrails.md", "vapt-pr-review.mdc"),
    ("docs/security-standards.md", "security-baseline.mdc"),
    ("docs/adr/", "docs/agents-v0/adr/"),
    ("docs/project-profile.md", "docs/agents-v0/project-profile.md"),
    ("docs/architecture.md", "docs/agents-v0/architecture.md"),
    ("docs/network.md", "docs/agents-v0/network.md"),
    ("docs/repo-map.md", "docs/agents-v0/repo-map.md"),
    ("docs/compliance-matrix.md", "docs/agents-v0/agents-v0-kit.md"),
    ("docs/model-routing-matrix.md", "docs/agents-v0/model-routing-matrix.md"),
    ("docs/user-guide.md", "docs/agents-v0/user-guide.md"),
    ("docs/agents-v0-kit.md", "docs/agents-v0/agents-v0-kit.md"),
    ("docs/greenfield-onboarding.md", "docs/agents-v0/greenfield-onboarding.md"),
    ("docs/brownfield-onboarding.md", "docs/agents-v0/brownfield-onboarding.md"),
    ("docs/gold-standards.md", "docs/agents-v0/gold-standards.md"),
    ("docs/quality-quick-reference.md", "docs/agents-v0/quality-gates.md"),
    ("docs/quality-gates", "docs/agents-v0/quality-gates"),
    ("docs/workspace.manifest.json", "docs/agents-v0/workspace.manifest.json"),
    ("':(exclude)ci/**'", "':(exclude).agents-v0/**'"),
    ("sh scripts/", "sh .agents-v0/scripts/"),
    ("sh ci/", "sh .agents-v0/ci/"),
    (" hooks/pre-push", " .agents-v0/hooks/pre-push"),
    ("hooks/pre-push", ".agents-v0/hooks/pre-push"),
    ("$t/ci/", "$t/.agents-v0/ci/"),
    ("$t/scripts/", "$t/.agents-v0/scripts/"),
    ('[ -f "$t/ci/', '[ -f "$t/.agents-v0/ci/'),
    ('[ -x "$t/ci/', '[ -x "$t/.agents-v0/ci/'),
    ("wire ci/", "wire .agents-v0/ci/"),
    ("/ci/check-", "/.agents-v0/ci/check-"),
    ("/scripts/check-", "/.agents-v0/scripts/check-"),
    ("$TARGET_ABS/CODEOWNERS", "$TARGET_ABS/.gitlab/CODEOWNERS"),
]

EXTS = {
    ".md", ".mdc", ".sh", ".py", ".json", ".yml", ".yaml", ".tsv", ".xml",
    ".example", ".gitignore", ".cursorignore",
}


def should_process(path: Path) -> bool:
    if path.name == "migrate-agents-v0-paths.py":
        return False
    if any(part in SKIP_DIRS for part in path.parts):
        return False
    if path.suffix in EXTS or path.name in ("AGENTS.md", "CODEOWNERS"):
        return True
    return False


def migrate_hook_policy(text: str) -> str:
    text = text.replace(
        're.compile(r"(^|/)ci/[^/]+\\.sh$")',
        're.compile(r"(^|/)\\.agents-v0/ci/[^/]+\\.sh$")',
    )
    text = text.replace(
        'r"(^|/)scripts/(check-attempt-budget',
        'r"(^|/)\\.agents-v0/scripts/(check-attempt-budget',
    )
    text = text.replace(
        're.compile(r"(^|/)hooks/pre-push$")',
        're.compile(r"(^|/)\\.agents-v0/hooks/pre-push$")',
    )
    text = text.replace(
        'r"(^|/)docs/requirements/.+\\.md$"',
        'r"(^|/)docs/agents-v0/requirements/.+\\.md$"',
    )
    text = text.replace(
        'r"(^|/)docs/milestones/.+\\.md$"',
        'r"(^|/)docs/agents-v0/milestones/.+\\.md$"',
    )
    return text


def main() -> None:
    changed = 0
    for path in ROOT.rglob("*"):
        if not path.is_file() or not should_process(path):
            continue
        original = path.read_text(encoding="utf-8", errors="replace")
        updated = original
        for old, new in REPLACEMENTS:
            if old == new:
                continue
            updated = updated.replace(old, new)
        if path.name == "hook-policy.py":
            updated = migrate_hook_policy(updated)
        updated = updated.replace(".agents-v0/.agents-v0/", ".agents-v0/")
        updated = updated.replace("docs/agents-v0/agents-v0/", "docs/agents-v0/")
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed += 1
    print(f"Updated {changed} files")


if __name__ == "__main__":
    main()
