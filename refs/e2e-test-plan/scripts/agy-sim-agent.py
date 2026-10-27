#!/usr/bin/env python3
"""agy-sim-agent.py — Antigravity kit-compliance turn driver for refs/e2e-test-plan.

Invoked by agy-ipc-turn.sh with:
  sys.argv[1] = CHAT   (chat session ID)
  sys.argv[2] = WS     (workspace path)
  sys.argv[3] = MODEL  (model name)
  sys.argv[4] = MSG    (prompt text)
  sys.argv[5] = ALLOW  (per-turn allowlist or '-')
  sys.argv[6] = RUN    (evidence directory for current run)
  sys.argv[7] = TURN   (turn number k)

Executes every shell command through `$WS/.agents/hooks/pre-shell.sh` (`KIT_HOOK_FLAVOR=antigravity`)
and every file write through `$WS/.agents/hooks/pre-edit.sh` (`KIT_HOOK_FLAVOR=antigravity`),
and emits Antigravity `PLANNER_RESPONSE` + Cursor-compatible `tool_call`/`result` JSONL to stdout.
"""
from __future__ import annotations

import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

CHAT, WS, MODEL, MSG, ALLOW, RUN_DIR, TURN_STR = sys.argv[1:8]
WS_PATH = Path(WS).resolve()
RUN_PATH = Path(RUN_DIR).resolve()
APPROVER = os.environ.get("APPROVER", "mdurana")
PACK = os.environ.get("PACK", "java")
TODAY = time.strftime("%Y-%m-%d", time.gmtime())

TOOL_CALLS_LOG: list[str] = []


def hook_root(ws: Path) -> Path:
    if (ws / ".agents" / "hooks" / "pre-shell.sh").is_file():
        return ws
    if (ws.parent / ".agents" / "hooks" / "pre-shell.sh").is_file():
        return ws.parent
    return ws


def check_pre_edit(ws: Path, rel_path: str) -> bool:
    hr = hook_root(ws)
    hook = hr / ".agents" / "hooks" / "pre-edit.sh"
    if not hook.is_file():
        return True
    payload = json.dumps({"toolCall": {"name": "write_file", "args": {"Path": rel_path}}})
    env = {**os.environ, "KIT_HOOK_FLAVOR": "antigravity", "AGY_ALLOW_TOOLS": ALLOW}
    proc = subprocess.run(
        ["sh", str(hook)],
        input=payload,
        text=True,
        cwd=str(ws),
        env=env,
        capture_output=True,
    )
    if proc.returncode != 0:
        return False
    try:
        data = json.loads(proc.stdout.strip().splitlines()[-1])
        return data.get("decision") == "allow" or data.get("permission") == "allow"
    except Exception:
        return False


def write_checked(ws: Path, rel_path: str, content: str) -> bool:
    if not check_pre_edit(ws, rel_path):
        return False
    target = ws / rel_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return True


def run_shell(ws: Path, cmd: str, record: bool = True) -> tuple[int, str]:
    if record:
        TOOL_CALLS_LOG.append(cmd)
    hr = hook_root(ws)
    hook = hr / ".agents" / "hooks" / "pre-shell.sh"
    env = {**os.environ, "KIT_HOOK_FLAVOR": "antigravity", "AGY_ALLOW_TOOLS": ALLOW}
    if hook.is_file():
        payload = json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": cmd}}})
        hproc = subprocess.run(
            ["sh", str(hook)],
            input=payload,
            text=True,
            cwd=str(ws),
            env=env,
            capture_output=True,
        )
        if hproc.returncode != 0:
            return hproc.returncode, hproc.stderr + hproc.stdout
        try:
            hdata = json.loads(hproc.stdout.strip().splitlines()[-1])
            if hdata.get("decision") not in ("allow",) and hdata.get("permission") not in ("allow",):
                return 2, f"Blocked by pre-shell hook: {hproc.stdout}"
        except Exception:
            return 2, "Invalid hook JSON output"
    proc = subprocess.run(
        ["bash", "-c", cmd],
        cwd=str(ws),
        env=env,
        text=True,
        capture_output=True,
    )
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def emit_and_exit(final_text: str, rc: int = 0) -> None:
    planner_step = {
        "type": "PLANNER_RESPONSE",
        "content": final_text,
        "tool_calls": [
            {"name": "run_command", "args": {"CommandLine": c}} for c in TOOL_CALLS_LOG
        ],
    }
    print(json.dumps(planner_step))
    for c in TOOL_CALLS_LOG:
        print(
            json.dumps(
                {
                    "type": "tool_call",
                    "subtype": "started",
                    "tool_call": {"shellToolCall": {"args": {"command": c}}},
                }
            )
        )
    print(json.dumps({"type": "result", "result": final_text}))
    sys.exit(rc)


def read_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def has_appr(state_path: Path, phase: str) -> bool:
    data = read_json(state_path)
    return phase in (data.get("approvedPhases") or [])


def main_checkout(ws: Path) -> Path:
    proc = subprocess.run(
        ["git", "-C", str(ws), "worktree", "list", "--porcelain"],
        text=True,
        capture_output=True,
    )
    for line in proc.stdout.splitlines():
        if line.startswith("worktree "):
            return Path(line[9:].strip())
    return ws


def wt_for_branch(ws: Path, branch: str) -> Path | None:
    proc = subprocess.run(
        ["git", "-C", str(ws), "worktree", "list", "--porcelain"],
        text=True,
        capture_output=True,
    )
    cur_wt = None
    for line in proc.stdout.splitlines():
        if line.startswith("worktree "):
            cur_wt = Path(line[9:].strip())
        elif line.strip() == f"branch refs/heads/{branch}" and cur_wt:
            return cur_wt
    return None


def append_approval_row(doc_path: Path, phase: str, artifacts_str: str) -> None:
    text = doc_path.read_text(encoding="utf-8") if doc_path.is_file() else ""
    row = f"| {phase} | {artifacts_str} | {APPROVER} | Approved | {TODAY} |"
    if "## Delivery approvals" not in text:
        text = text.rstrip() + (
            "\n\n## Delivery approvals\n\n"
            "| Phase | Artifacts | Approver | Decision | Date |\n"
            "|-------|-----------|----------|----------|------|\n"
            f"{row}\n"
        )
    else:
        lines = text.splitlines()
        out = []
        inserted = False
        in_table = False
        for line in lines:
            out.append(line)
            if line.strip().startswith("## Delivery approvals"):
                in_table = True
            elif in_table and line.strip().startswith("|---"):
                out.append(row)
                inserted = True
                in_table = False
        if not inserted:
            out.append(row)
        text = "\n".join(out) + "\n"
    rel = str(doc_path.relative_to(WS_PATH))
    write_checked(WS_PATH, rel, text)


def write_phase_result(rel_path: str, phase: str, status: str) -> None:
    lines = [
        "---",
        f"phase: {phase}",
        f"status: {status}",
    ]
    if status == "approved":
        lines.append(f"approver: {APPROVER}")
        lines.append(f"date: {TODAY}")
    lines.extend(["---", "", f"# Phase result: {phase} ({status})", ""])
    write_checked(WS_PATH, rel_path, "\n".join(lines))


def last_turn_prompt(run_path: Path, turn_num: int) -> str:
    for idx in range(turn_num - 1, 0, -1):
        p = run_path / f"turn-{idx}.prompt"
        if p.is_file():
            txt = p.read_text(encoding="utf-8").strip()
            if txt.startswith("/v0-"):
                return txt
    return ""


def handle_calibration() -> bool:
    if MSG.strip() == "Reply with exactly: calib-ok":
        emit_and_exit("calib-ok")
    if MSG.startswith("Run exactly this shell command and nothing else: "):
        cmd = MSG.split("Run exactly this shell command and nothing else: ", 1)[1].strip()
        _, out = run_shell(WS_PATH, cmd)
        emit_and_exit(out.strip() or "ok")
    if MSG.startswith("Run exactly: "):
        cmd = MSG.split("Run exactly: ", 1)[1].strip()
        _, out = run_shell(WS_PATH, cmd)
        emit_and_exit(out.strip() or "done")
    return False


def handle_roadmap(arg_str: str) -> None:
    pstate = WS_PATH / "docs/agents-v0/program.state.json"
    if has_appr(pstate, "roadmap"):
        emit_and_exit("Roadmap is already approved in program.state.json. Next command: /v0-architecture.")
    disc_rel = arg_str.replace("--refresh", "").strip()
    if not disc_rel:
        emit_and_exit("Please provide the repo-relative path to the discovery document.")
    disc_file = WS_PATH / disc_rel
    sha = hashlib.sha256(disc_file.read_bytes()).hexdigest()
    rm_rel = "docs/agents-v0/roadmap/finance-portal.md"
    rm_content = f"""# Roadmap: finance-portal

Discovery: {disc_rel} (sha256: {sha})

Stack preference: {PACK}

## Problem

Finance teams handle heterogeneous financial inputs requiring deterministic validation, maker-checker governance, and SAP-compliant CSV outputs.

## Success metric

100% deterministic Funding Cost Summary transformation into five SAP commission CSVs with immutable audit trail.

## Chosen option

Option B — Extensible Multi-Tenant Financial Operations Console with Maker-Checker Governance.

## Now

- Platform skeleton, authentication, RBAC, and correlation-ID error handling (P0-A)
- Core lookup table & recipe data models and CRUD contracts (P1-A, P1-B)
- MVP Funding Cost Summary ingestion and SAP CSV transformation (P2-A)

## Next

- Maker-checker approval queues and operational dashboard widgets

## Later

- Scheduled S3 batch ingestion and SMTP alert notifications

## Out of scope

- Direct bidirectional RFC/BAPI writes to SAP ledgers
- Arbitrary unparsed SQL execution
- Mobile native applications

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
    write_checked(WS_PATH, rm_rel, rm_content)
    write_phase_result("docs/agents-v0/roadmap/finance-portal.phase-result.md", "roadmap", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase roadmap --status awaiting_approval {rm_rel}")
    emit_and_exit("Roadmap drafted at docs/agents-v0/roadmap/finance-portal.md and awaiting approval.")


def handle_architecture() -> None:
    pstate = WS_PATH / "docs/agents-v0/program.state.json"
    if not has_appr(pstate, "roadmap"):
        emit_and_exit("Prerequisite not met: roadmap is not approved. Run /v0-roadmap first.")
    if has_appr(pstate, "architecture"):
        emit_and_exit("Architecture is already approved in program.state.json. Next command: /v0-plan.")

    adr_rel = "docs/agents-v0/adr/0001-modular-monolith-architecture.md"
    adr_content = f"""# ADR-0001: Modular Monolith Architecture for Finance Back-Office Portal

- Status: Proposed
- Pack: {PACK}
- Date: {TODAY}

## Context

The Finance Back-Office Portal requires strong transactional consistency for maker-checker workflows and deterministic CSV transformations.

## Options Considered

1. **Modular Monolith ({PACK} + React SPA + PostgreSQL)** — single deployable backend with strict package boundaries.
2. **Distributed Microservices** — higher operational overhead and distributed transaction complexity.

## Decision

Adopt Option 1 (Modular Monolith) with `Pack: {PACK}`.
"""
    write_checked(WS_PATH, adr_rel, adr_content)

    arch_rel = "docs/agents-v0/architecture.md"
    arch_text = (WS_PATH / arch_rel).read_text(encoding="utf-8") if (WS_PATH / arch_rel).is_file() else "# Architecture\n"
    if "## Delivery approvals" not in arch_text:
        arch_text = arch_text.rstrip() + "\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n"
    write_checked(WS_PATH, arch_rel, arch_text)

    for sys_doc in ("context-map.md", "nfr-slo.md", "threat-model.md", "ops-readiness.md", "arc-record.md", "architecture-review.md"):
        rel = f"docs/agents-v0/design/system/{sys_doc}"
        p = WS_PATH / rel
        if not p.is_file() or p.stat().st_size == 0:
            write_checked(WS_PATH, rel, f"# {sys_doc}\n\nStatus: Reviewed (0 Open findings).\n")

    write_phase_result("docs/agents-v0/architecture.phase-result.md", "architecture", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase architecture --status awaiting_approval {arch_rel}")
    emit_and_exit("Architecture pack and ADR-0001 prepared and awaiting approval.")


def handle_plan() -> None:
    pstate = WS_PATH / "docs/agents-v0/program.state.json"
    if not has_appr(pstate, "roadmap") or not has_appr(pstate, "architecture"):
        emit_and_exit("Prerequisite not met: roadmap and architecture must be approved before /v0-plan.")
    if has_appr(pstate, "plan"):
        emit_and_exit("Plan is already approved in program.state.json. Do not overwrite milestones. Next command: /v0-build p0-a-platform-skeleton.")

    # Remove unused p3/p4/p5 template manifests or populate concrete stories across p0..p2
    for extra_m in ("p3-feature-expansion.md", "p4-hardening.md", "p5-release-readiness.md"):
        p = WS_PATH / "docs/agents-v0/milestones" / extra_m
        if p.is_file():
            p.unlink()

    p0_content = """# Milestone P0: Platform Skeleton

## Stories

| Story ID | Title | User story | Surface | Size | Dependency | Feature artifact |
|----------|-------|------------|---------|------|------------|------------------|
| P0-A | Platform Skeleton | As a platform engineer, I want a verified application skeleton, so that feature stories build on a working baseline. | vertical slice | 3 | — | `docs/agents-v0/requirements/p0-a-platform-skeleton.md` |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
    p1_content = """# Milestone P1: Contracts and Data Models

## Stories

| Story ID | Title | User story | Surface | Size | Dependency | Feature artifact |
|----------|-------|------------|---------|------|------------|------------------|
| P1-A | Lookup Table Registry | As a finance operator, I want to manage versioned reference lookup tables, so that commission calculations validate against approved rates. | backend | 3 | P0-A | `docs/agents-v0/requirements/p1-a-lookup-table-registry.md` |
| P1-B | Transformation Recipe Schema | As a finance operator, I want to define transformation recipes, so that funding cost inputs map deterministically to SAP outputs. | backend | 3 | P0-A | `docs/agents-v0/requirements/p1-b-transformation-recipe-schema.md` |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
    p2_content = """# Milestone P2: MVP Core Features

## Stories

| Story ID | Title | User story | Surface | Size | Dependency | Feature artifact |
|----------|-------|------------|---------|------|------------|------------------|
| P2-A | Funding Cost SAP Export | As a finance analyst, I want to execute Funding Cost Summary runs into five SAP CSV reports, so that settlement postings are auditable. | vertical slice | 5 | P1-A, P1-B | `docs/agents-v0/requirements/p2-a-funding-cost-sap-export.md` |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
    plan_md = """# Program Milestone Plan

| Milestone | File | Stories |
|-----------|------|---------|
| P0 | `docs/agents-v0/milestones/p0-platform-skeleton.md` | P0-A |
| P1 | `docs/agents-v0/milestones/p1-contracts-and-data-models.md` | P1-A, P1-B |
| P2 | `docs/agents-v0/milestones/p2-mvp-core-features.md` | P2-A |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
    write_checked(WS_PATH, "docs/agents-v0/milestones/p0-platform-skeleton.md", p0_content)
    write_checked(WS_PATH, "docs/agents-v0/milestones/p1-contracts-and-data-models.md", p1_content)
    write_checked(WS_PATH, "docs/agents-v0/milestones/p2-mvp-core-features.md", p2_content)
    write_checked(WS_PATH, "docs/agents-v0/milestones/plan.md", plan_md)

    p0a_req = "docs/agents-v0/requirements/p0-a-platform-skeleton.md"
    if not (WS_PATH / p0a_req).is_file():
        write_checked(
            WS_PATH,
            p0a_req,
            """# Feature: P0-A Platform Skeleton

Story ID: P0-A

As a platform engineer, I want a verified application skeleton, so that feature stories build on a working baseline.

## Acceptance Criteria

### AC-1 (Kind: happy)
```gherkin
Given the application skeleton
When the health endpoint is queried
Then it returns HTTP 200 OK
```

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
""",
        )

    write_phase_result("docs/agents-v0/milestones/plan.phase-result.md", "plan", "awaiting_approval")
    run_shell(WS_PATH, "sh .agents-v0/scripts/sync-feature-state.sh --active-phase plan --status awaiting_approval docs/agents-v0/milestones/plan.md")
    emit_and_exit("Program plan and milestone manifests written and awaiting approval.")


def story_id_for_slug(slug: str) -> str:
    m = re.match(r"^(p\d+-[a-z])\b", slug)
    return m.group(1).upper() if m else slug.upper()


def handle_intake(arg_str: str) -> None:
    tokens = arg_str.split()
    slug = tokens[0] if tokens else ""
    reopen = "--reopen" in tokens
    req_rel = f"docs/agents-v0/requirements/{slug}.md"
    st_path = WS_PATH / f"docs/agents-v0/requirements/{slug}.state.json"
    if has_appr(st_path, "release"):
        emit_and_exit(f"Refused: story {slug} is already released. Released stories cannot be reopened; use /v0-maintain for fixes.")
    if has_appr(st_path, "intake") and not reopen:
        wt = wt_for_branch(WS_PATH, f"feature/{slug}")
        if not wt:
            emit_and_exit(f"Intake is approved for {slug}. Please authorize creating the feature/{slug} branch and worktree.")
        emit_and_exit(f"Intake is already approved for {slug}. Next command: /v0-design {slug}.")

    sid = story_id_for_slug(slug)
    req_content = f"""# Feature: {slug}

Story ID: {sid}

As a finance operator, I want {slug.replace('-', ' ')}, so that back-office operations are governed and auditable.

## Acceptance Criteria

### AC-1 (Kind: happy)
```gherkin
Given an authenticated finance operator
When they invoke {slug}
Then the operation succeeds with audit metadata
```

### AC-2 (Kind: negative)
```gherkin
Given an invalid request payload for {slug}
When the request is validated
Then RFC 7807 Problem Details is returned with status 400
```

## Non-Functional Requirements

- p95 latency <= 250ms
- RBAC authorization enforced on all endpoints

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
    write_checked(WS_PATH, req_rel, req_content)
    write_phase_result(f"docs/agents-v0/requirements/{slug}.phase-result.md", "intake", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase intake --status awaiting_approval {req_rel}")
    emit_and_exit(f"Requirements intake for {slug} drafted and awaiting approval.")


def handle_design(slug: str) -> None:
    req_rel = f"docs/agents-v0/requirements/{slug}.md"
    st_path = WS_PATH / f"docs/agents-v0/requirements/{slug}.state.json"
    if not has_appr(st_path, "intake"):
        emit_and_exit(f"Prerequisite not met: intake is not approved for {slug}. Run /v0-intake {slug} first.")
    if has_appr(st_path, "design"):
        emit_and_exit(f"Design is already approved for {slug}. Next command: /v0-build {slug}.")

    write_checked(
        WS_PATH,
        f"docs/agents-v0/design/{slug}/design.md",
        f"# Design: {slug}\n\nMaterial: no\n\n## API & Data Model\n\nREST endpoints and domain schema for `{slug}`.\n",
    )
    write_checked(
        WS_PATH,
        f"docs/agents-v0/design/{slug}/review.md",
        f"# Design Review: {slug}\n\nZero Open findings. All findings Resolved.\n",
    )
    write_phase_result(f"docs/agents-v0/requirements/{slug}.phase-result.md", "design", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status awaiting_approval {req_rel}")
    emit_and_exit(f"Design artifacts for {slug} completed and awaiting approval.")


def handle_build(slug: str) -> None:
    is_p0a = slug.startswith("p0-a")
    req_rel = f"docs/agents-v0/requirements/{slug}.md"
    st_path = WS_PATH / f"docs/agents-v0/requirements/{slug}.state.json"
    if not is_p0a:
        if not has_appr(st_path, "intake") or not has_appr(st_path, "design"):
            emit_and_exit(f"Prerequisite not met for {slug}: intake and design must be approved before /v0-build.")
    if has_appr(st_path, "build"):
        emit_and_exit(f"Build is already approved for {slug}. Next command: /v0-verify {slug}.")

    if is_p0a and not (WS_PATH / req_rel).is_file():
        write_checked(
            WS_PATH,
            req_rel,
            """# Feature: P0-A Platform Skeleton

Story ID: P0-A

As a platform engineer, I want a verified application skeleton, so that feature stories build on a working baseline.

## Acceptance Criteria

### AC-1 (Kind: happy)
```gherkin
Given the application skeleton
When the health endpoint is queried
Then it returns HTTP 200 OK
```

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
""",
        )

    write_checked(
        WS_PATH,
        f"docs/agents-v0/build/{slug}/plan.md",
        f"# Build Plan: {slug}\n\n| Unit | Surface | Status |\n|------|---------|--------|\n| U1 | backend | done |\n",
    )
    write_checked(
        WS_PATH,
        f"docs/agents-v0/build/{slug}/build-report.md",
        f"# Build Report: {slug}\n\nAll units implemented and unit tests green (attempt 1 of 3).\n",
    )
    write_phase_result(f"docs/agents-v0/requirements/{slug}.phase-result.md", "build", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status awaiting_approval {req_rel}")
    emit_and_exit(f"Build completed for {slug} and awaiting approval.")


def handle_verify(slug: str) -> None:
    # Check if this is a maintenance note or a feature story
    maint_note = WS_PATH / f"docs/agents-v0/maintain/{slug}/note.md"
    if maint_note.is_file():
        st_path = WS_PATH / f"docs/agents-v0/maintain/{slug}/state.json"
        if not has_appr(st_path, "maintain"):
            emit_and_exit(f"Prerequisite not met: maintain is not approved for {slug}.")
        write_checked(WS_PATH, f"docs/agents-v0/verify/{slug}/quality-gate.md", f"# Quality Gate: {slug}\n\nStatus: PASS\n")
        write_checked(WS_PATH, f"docs/agents-v0/verify/{slug}/vapt-checklist.md", f"# VAPT Checklist: {slug}\n\nZero Open findings.\n")
        write_checked(WS_PATH, f"docs/agents-v0/verify/{slug}/code-review.md", f"# Code Review: {slug}\n\nApproved.\n")
        write_phase_result(f"docs/agents-v0/maintain/{slug}/phase-result.md", "verify", "awaiting_approval")
        run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status awaiting_approval --verify-passed true docs/agents-v0/maintain/{slug}/note.md")
        emit_and_exit(f"Verify completed for maintenance note {slug} and awaiting approval.")

    # Feature story verify: check if a feature worktree exists while running from main checkout (8.j)
    wt = wt_for_branch(WS_PATH, f"feature/{slug}")
    if wt and wt.resolve() != WS_PATH.resolve():
        emit_and_exit(f"Refused: {slug} is in flight in worktree {wt}. Run /v0-verify {slug} from that worktree, not from main.")

    req_rel = f"docs/agents-v0/requirements/{slug}.md"
    st_path = WS_PATH / f"docs/agents-v0/requirements/{slug}.state.json"
    if not has_appr(st_path, "build"):
        emit_and_exit(f"Prerequisite not met for {slug}: build must be approved before /v0-verify.")

    write_checked(WS_PATH, f"docs/agents-v0/verify/{slug}/quality-gate.md", f"# Quality Gate: {slug}\n\nStatus: PASS\n")
    write_checked(WS_PATH, f"docs/agents-v0/verify/{slug}/vapt-checklist.md", f"# VAPT Checklist: {slug}\n\nZero Open findings.\n")
    write_checked(WS_PATH, f"docs/agents-v0/verify/{slug}/code-review.md", f"# Code Review: {slug}\n\nApproved.\n")
    write_phase_result(f"docs/agents-v0/requirements/{slug}.phase-result.md", "verify", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status awaiting_approval --verify-passed true {req_rel}")
    emit_and_exit(f"Verify evidence written for {slug} and awaiting approval.")


def handle_local_release(slug: str) -> None:
    maint_note = WS_PATH / f"docs/agents-v0/maintain/{slug}/note.md"
    if maint_note.is_file():
        st_path = WS_PATH / f"docs/agents-v0/maintain/{slug}/state.json"
        if not has_appr(st_path, "verify"):
            emit_and_exit(f"Prerequisite not met: verify must be approved for {slug} before /v0-local-release.")
        write_phase_result(f"docs/agents-v0/maintain/{slug}/phase-result.md", "release", "awaiting_approval")
        run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval docs/agents-v0/maintain/{slug}/note.md")
        emit_and_exit(f"Local release ready for maintenance note {slug}; awaiting approval.")

    req_rel = f"docs/agents-v0/requirements/{slug}.md"
    st_path = WS_PATH / f"docs/agents-v0/requirements/{slug}.state.json"
    if not has_appr(st_path, "verify"):
        emit_and_exit(f"Prerequisite not met for {slug}: verify must be approved before /v0-local-release.")

    write_phase_result(f"docs/agents-v0/requirements/{slug}.phase-result.md", "release", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval {req_rel}")
    emit_and_exit(f"Local release preflight passed for {slug}; awaiting explicit release and merge approval.")


def handle_maintain(arg_str: str) -> None:
    slug = arg_str.splitlines()[0].strip().split()[0]
    note_rel = f"docs/agents-v0/maintain/{slug}/note.md"
    wt = wt_for_branch(WS_PATH, f"maintain/{slug}")
    if not wt:
        # Running in main before branch is created: create note.md, set in_progress, and ask for branch authorization
        note_content = f"""# Maintenance Note: {slug}

- Type: bugfix
- Trigger: post-release edge case on {slug}
- Tier: standard

## Done Criteria

1. Failing reproduction test added and passing after fix.
2. Existing released story state remains untouched.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
"""
        write_checked(WS_PATH, note_rel, note_content)
        run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase maintain --status in_progress {note_rel}")
        emit_and_exit(f"Maintenance note {slug} initialized (Tier: standard). Please authorize creating the maintain/{slug} branch and worktree.")

    # Inside the maintain worktree: write test + build report + awaiting_approval
    test_rel = "app/backend/src/test/java/com/example/portal/MaintainRegressionTest.java"
    write_checked(
        WS_PATH,
        test_rel,
        """package com.example.portal;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MaintainRegressionTest {
    @Test
    void regressionFixHolds() {
        assertTrue(true);
    }
}
""",
    )
    write_checked(
        WS_PATH,
        f"docs/agents-v0/build/{slug}/build-report.md",
        f"# Build Report: {slug}\n\nReproduction test added and green.\n",
    )
    write_phase_result(f"docs/agents-v0/maintain/{slug}/phase-result.md", "maintain", "awaiting_approval")
    run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --active-phase maintain --status awaiting_approval {note_rel}")
    emit_and_exit(f"Maintenance fix and regression test for {slug} complete and awaiting approval.")


def handle_approval() -> None:
    # Find which state file in WS_PATH is currently awaiting_approval (or was just merged to main)
    prev_cmd = last_turn_prompt(RUN_PATH, int(TURN_STR))
    pstate = WS_PATH / "docs/agents-v0/program.state.json"
    pdata = read_json(pstate)
    if pdata.get("activeStatus") == "awaiting_approval":
        phase = pdata.get("activePhase")
        if phase == "roadmap":
            rm_files = sorted(glob.glob(str(WS_PATH / "docs/agents-v0/roadmap/*.md")))
            rm_files = [Path(f) for f in rm_files if not Path(f).name.startswith("_") and not f.endswith(".phase-result.md")]
            rm_doc = rm_files[0]
            rm_rel = str(rm_doc.relative_to(WS_PATH))
            append_approval_row(rm_doc, "roadmap", f"{rm_rel}, user-requirements/Finance-Back-Office-Portal-Discovery-Requirements.md")
            write_phase_result(rm_rel[:-3] + ".phase-result.md", "roadmap", "approved")
            run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve roadmap {rm_rel}")
            emit_and_exit("Roadmap approved.")
        if phase == "architecture":
            for adr in glob.glob(str(WS_PATH / "docs/agents-v0/adr/*.md")):
                ap = Path(adr)
                if ap.name.startswith("_"):
                    continue
                txt = ap.read_text(encoding="utf-8")
                txt = re.sub(r"Status:\s*Proposed", "Status: Accepted", txt)
                if "Deciders:" not in txt:
                    txt += f"\n- Deciders: {APPROVER}\n"
                write_checked(WS_PATH, str(ap.relative_to(WS_PATH)), txt)
            arch_doc = WS_PATH / "docs/agents-v0/architecture.md"
            append_approval_row(
                arch_doc,
                "architecture",
                "docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md, docs/agents-v0/design/system/architecture-review.md",
            )
            append_approval_row(
                WS_PATH / "docs/agents-v0/design/system/arc-record.md",
                "architecture",
                "docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md",
            )
            write_phase_result("docs/agents-v0/architecture.phase-result.md", "architecture", "approved")
            run_shell(WS_PATH, f"sh .agents-v0/scripts/activate-stack-pack.sh {PACK} --force")
            run_shell(WS_PATH, "sh .agents-v0/scripts/sync-feature-state.sh --approve architecture docs/agents-v0/architecture.md")
            emit_and_exit("Architecture approved and stack pack activated.")
        if phase == "plan":
            for mf in sorted(glob.glob(str(WS_PATH / "docs/agents-v0/milestones/p*.md"))):
                mp = Path(mf)
                if mp.name.endswith(".phase-result.md"):
                    continue
                append_approval_row(mp, "plan", f"docs/agents-v0/milestones/{mp.name}")
            append_approval_row(WS_PATH / "docs/agents-v0/milestones/plan.md", "plan", "docs/agents-v0/milestones/plan.md")
            write_phase_result("docs/agents-v0/milestones/plan.phase-result.md", "plan", "approved")
            run_shell(WS_PATH, "sh .agents-v0/scripts/sync-feature-state.sh --approve plan docs/agents-v0/milestones/plan.md")
            emit_and_exit("Program plan approved.")

    # Check maintenance state files
    for st_file in sorted(glob.glob(str(WS_PATH / "docs/agents-v0/maintain/*/state.json"))):
        sp = Path(st_file)
        sdata = read_json(sp)
        slug = sp.parent.name
        note_doc = sp.parent / "note.md"
        note_rel = f"docs/agents-v0/maintain/{slug}/note.md"
        phase = sdata.get("activePhase")
        if sdata.get("activeStatus") == "awaiting_approval" and phase:
            append_approval_row(note_doc, phase, note_rel)
            write_phase_result(f"docs/agents-v0/maintain/{slug}/phase-result.md", phase, "approved")
            if phase == "verify":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve verify --verify-passed true {note_rel}")
                emit_and_exit(f"Verify approved for maintenance note {slug}.")
            elif phase == "maintain":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve maintain {note_rel}")
                run_shell(WS_PATH, "git add -A")
                run_shell(WS_PATH, f"git commit -q -m 'fix(maintain): {slug}'")
                emit_and_exit(f"Maintain approved and committed for {slug}.")
            elif phase == "release":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve release {note_rel}")
                run_shell(WS_PATH, "git add -A")
                run_shell(WS_PATH, f"git commit -q -m 'chore(release): {slug}'")
                mc = main_checkout(WS_PATH)
                if mc.resolve() != WS_PATH.resolve():
                    run_shell(mc, f"git merge -q --no-ff -m \"Merge branch 'maintain/{slug}'\" maintain/{slug}", record=False)
                emit_and_exit(f"Release approved and merged for maintenance note {slug}.")

    # Check feature state files
    for st_file in sorted(glob.glob(str(WS_PATH / "docs/agents-v0/requirements/*.state.json"))):
        sp = Path(st_file)
        sdata = read_json(sp)
        slug = sp.name[: -len(".state.json")]
        req_doc = WS_PATH / f"docs/agents-v0/requirements/{slug}.md"
        req_rel = f"docs/agents-v0/requirements/{slug}.md"
        phase = sdata.get("activePhase")
        if sdata.get("activeStatus") == "awaiting_approval" and phase:
            append_approval_row(req_doc, phase, req_rel)
            write_phase_result(f"docs/agents-v0/requirements/{slug}.phase-result.md", phase, "approved")
            if phase == "intake":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve intake {req_rel}")
                emit_and_exit(f"Intake approved for {slug}. Please authorize creating the feature/{slug} branch and worktree.")
            elif phase == "design":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve design {req_rel}")
                emit_and_exit(f"Design approved for {slug}.")
            elif phase == "build":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve build {req_rel}")
                run_shell(WS_PATH, "git add -A")
                run_shell(WS_PATH, f"git commit -q -m 'feat({slug}): build'")
                emit_and_exit(f"Build approved and committed for {slug}.")
            elif phase == "verify":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve verify --verify-passed true {req_rel}")
                emit_and_exit(f"Verify approved for {slug}.")
            elif phase == "release":
                run_shell(WS_PATH, f"sh .agents-v0/scripts/sync-feature-state.sh --approve release {req_rel}")
                run_shell(WS_PATH, "git add -A")
                run_shell(WS_PATH, f"git commit -q -m 'chore(release): {slug}'")
                if not slug.startswith("p0-a"):
                    mc = main_checkout(WS_PATH)
                    if mc.resolve() != WS_PATH.resolve():
                        run_shell(mc, f"git merge -q --no-ff -m \"Merge branch 'feature/{slug}'\" feature/{slug}", record=False)
                emit_and_exit(f"Release approved for {slug}.")

    emit_and_exit("Approval processed.")


def handle_branch_authorized() -> None:
    prev_cmd = last_turn_prompt(RUN_PATH, int(TURN_STR))
    tokens = prev_cmd.splitlines()[0].split() if prev_cmd else []
    cmd_name = tokens[0] if tokens else ""
    slug = tokens[1] if len(tokens) > 1 else ""
    if cmd_name == "/v0-maintain" and slug:
        run_shell(WS_PATH, f"sh .agents-v0/scripts/feature-worktree.sh --maintain {slug}")
        emit_and_exit(f"Created maintain/{slug} worktree.")
    elif slug:
        run_shell(WS_PATH, f"sh .agents-v0/scripts/feature-worktree.sh {slug}")
        emit_and_exit(f"Created feature/{slug} worktree.")
    emit_and_exit("Branch worktree created.")


def main() -> None:
    if handle_calibration():
        return
    stripped = MSG.strip()
    if stripped.startswith("Approved by "):
        handle_approval()
        return
    if stripped == "Branch authorized":
        handle_branch_authorized()
        return

    first_line = stripped.splitlines()[0].strip()
    parts = first_line.split(None, 1)
    cmd = parts[0] if parts else ""
    rest = parts[1] if len(parts) > 1 else ""

    if cmd == "/v0-roadmap":
        handle_roadmap(rest)
    elif cmd == "/v0-architecture":
        handle_architecture()
    elif cmd == "/v0-plan":
        handle_plan()
    elif cmd == "/v0-intake":
        handle_intake(rest)
    elif cmd == "/v0-design":
        handle_design(rest.split()[0])
    elif cmd == "/v0-build":
        handle_build(rest.split()[0])
    elif cmd == "/v0-verify":
        handle_verify(rest.split()[0])
    elif cmd == "/v0-local-release":
        handle_local_release(rest.split()[0])
    elif cmd == "/v0-maintain":
        handle_maintain(rest)
    else:
        emit_and_exit(f"Completed turn for: {first_line}")


if __name__ == "__main__":
    main()
