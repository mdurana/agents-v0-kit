"""Path rewriting for skills installed into target projects."""

from __future__ import annotations

import re

NWOB_REFERENCES_DIR = "nwob-references"

# Rewrite links from source repo layout to project layout (.cursor/skills + nwob-references/).
REWRITES: list[tuple[str, str]] = [
  # Template paths in skills → .nwob/templates in project
    (
        r"\[meeting-summary-template\.md\]\(\.\./\.\./\.\./templates/observer/meeting-summary-template\.md\)",
        "[meeting-summary-template.md](../../../.nwob/templates/meeting-summary-template.md)",
    ),
    (
        r"\[tickets-export-params\.template\.md\]\(\.\./\.\./\.\./templates/po/tickets-export-params\.template\.md\)",
        "[tickets-export-params.template.md](../../../.nwob/templates/tickets-export-params.template.md)",
    ),
    (r"\.\./\.\./\.\./templates/", "../../../.nwob/templates/"),
    (r"\.\./\.\./\.\./references/", f"../../../{NWOB_REFERENCES_DIR}/"),
    (r"\]\(references/", f"]({NWOB_REFERENCES_DIR}/"),
    # Agent skill links in agent files → .cursor/skills
    (
        r"\]\(\.\./skills/([a-z0-9-]+)/([a-z0-9-]+)/SKILL\.md\)",
        r"](.cursor/skills/\2/SKILL.md)",
    ),
    (
        r"\]\(skills/([a-z0-9-]+)/([a-z0-9-]+)/SKILL\.md\)",
        r"](.cursor/skills/\2/SKILL.md)",
    ),
]


def rewrite_project_paths(content: str) -> str:
    """Rewrite references/ paths to nwob-references/ in installed project artifacts."""
    content = content.replace("../../references/", f"../../{NWOB_REFERENCES_DIR}/")
    content = content.replace("@references/", f"@{NWOB_REFERENCES_DIR}/")
    content = content.replace("](references/", f"]({NWOB_REFERENCES_DIR}/")
    content = content.replace("`references/", f"`{NWOB_REFERENCES_DIR}/")
    return content


def rewrite_skill_content(content: str) -> str:
    for pattern, replacement in REWRITES:
        content = re.sub(pattern, replacement, content)
    return content


def rewrite_agent_content(content: str) -> str:
    content = re.sub(
        r"\]\(\.\./skills/([a-z0-9-]+)/([a-z0-9-]+)/SKILL\.md\)",
        r"](.cursor/skills/\2/SKILL.md)",
        content,
    )
    content = re.sub(
        r"skills/([a-z0-9-]+)/",
        r".cursor/skills/",
        content,
    )
    return content
