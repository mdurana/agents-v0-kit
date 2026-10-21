# agents-v0 Agentic Workflow Audit

Scope: rules, commands, agents, hooks, state and budget scripts, install/validate, CI template, at `0d3d64b`.
Every **High** finding below was **reproduced** in a temp repo (commands in [Appendix A](#appendix-a--reproductions)). The patches in §3 were run against a 33-case state-machine smoke test plus the existing 213-case `test-hook-policy.py`.

> [!IMPORTANT]
> Several files in the request scope no longer exist: `templates/.agents-v0/ci/gate.sh`, `gates.json`, `check-delivery-gate-local.sh`, `hooks/pre-commit`, `hooks/after-edit.sh`, and any `design.lock`. `validate-kit.sh:222-224` *requires* them to be absent, and `install.sh:171,186` deletes them on update. The "automated GitLab CI gate and evidence verification" in the stated workflow goal **no longer exists**. That changes how severe findings H1–H3 are. Every gate is now enforced only by prompts and an optional local `pre-push`.

---

## 1. Critical Bottlenecks & Failure Modes

### High

| # | Finding | Evidence |
|---|---------|----------|
| **H1** | **Any agent can self-approve. Approval is a prompt convention, not a control.** `--approve`, `--verify-passed true`, and `--clear-active` are allowed without a prompt. The orchestrator, all engineers, and the reviewers all have `shell`. There are two more ways to approve: (a) edit the `Delivery approvals` table. `pre-edit.sh` returns `ask`, but the file itself says Cursor does not enforce `ask` on preToolUse. The next plain sync then turns a positive row into an approval. (b) Commit a state file plus `requirements/*.md` with **no prompt** through the evidence-commit allowlist. | `hook-policy.py` has no rule for `sync-feature-state.sh` (probe → `allow`); `pre-edit.sh:50-53`; `hook-policy.py:670-676, 486-524`; `sync-feature-state.sh:149-152, 212-217` |
| **H2** | **The state machine checks no transitions.** `--approve release` on a brand-new feature marks `intake…release` approved *and* sets `verifyPassed: true`, because `--approve` fills in every earlier phase and verifyPassed is inferred from `lastApprovedPhase`. `--active-phase build --status in_progress` succeeds without Design. Each prerequisite check lives in prose that an LLM re-reads (`v0-build.md:14`, `v0-verify.md:11`, `v0-design.md:12`). | `sync-feature-state.sh:231-235, 278-292, 529-530`. Repro A1 → `['intake','design','build','verify','release'] True` |
| **H3** | **No server-side gate. The only enforcement point fails open.** The CI runs the native build only. It never checks state or evidence. When the profile has no verify command and there is no `pom.xml` (for example a fresh **dotnet** profile), the backend job runs nothing and passes. `pre-push` reads the *working tree* state, not the pushed commit. It passes when the branch name matches no state file, and `verifyPassed` alone (agent-settable) satisfies it. | `.gitlab-ci.yml:64-84`; `hooks/pre-push:21-28, 44` |
| **H4** | **Shell injection, and a crash on ordinary test names, in `check-failure-brief.sh`.** Test names from an agent-written Markdown table go into `eval` unquoted. An xUnit/Jest display name like `returns 404 when missing` exits 127 (`404: command not found`). A name containing `; cmd` runs arbitrary code, and `pre-shell.sh` only ever saw `sh check-failure-brief.sh`. | `check-failure-brief.sh:37, 68-69`. Repro A3 |
| **H5** | **Stale or unbound Verify reaches Release.** (a) `--reopen build` without `--verify-passed false` leaves `verifyPassed: true`. (b) No commit is recorded at Verify, so Release cannot prove that the code it merges is the code that was verified. `/v0-status` only *advises* a re-verify. (c) `/v0-local-release` step 5 runs `--approve release` **before** the commit and merge. A merge conflict leaves the item "released", and `session-start.sh:30` then hides it. | `sync-feature-state.sh:241-250, 524-532`; `v0-local-release.md:25-28`; `v0-status.md:26` |

### Medium

| # | Finding | Evidence |
|---|---------|----------|
| **M1** | **Exhausting the reopen budget is never saved, so work re-enters a loop.** On the 4th `--reopen`, the script exits 2 *before writing*. The state stays at `verify/in_progress`, so `/v0-status` → `/v0-verify` → the same Critical → the reopen fails again. Each pass reruns the full suite and two `xhigh` reviewers. There is no terminal "escalated" state. | `sync-feature-state.sh:252-254` |
| **M2** | **Helper-loop detection gives false positives and contradicts the docs.** It hashes the *first* `ask:`/`outputs:`/`return:` line, which is usually `outputs:`, even though the rule says it records the `ask:` digest. Every brief on disk is rescanned on **every** call, so any second sync before the brief is deleted (for example `--active-phase … in_progress` on resume) exits 2. That also blocks recording approvals. | `sync-feature-state.sh:440-457`. Repro A2 → `exit=2` |
| **M3** | **The artifact → state mapping silently routes to the wrong file.** Passing `design/f1/design.md` writes `requirements/design.state.json`. `build-report.md` would create `build-report.state.json`. The rule text only says `<artifact>`. | `sync-feature-state.sh:88-100`. Repro A4 |
| **M4** | **Dead-end routing on `blocked`.** `/v0-status` and `/v0-deliver` map `blocked` → rerun `activePhase`. With "Design not approved", `/v0-build` blocks again, forever. The `design-reviewer` "max 3 cycles" has no counter and no defined exit. The Build attempt budget counts cards in agent-authored Markdown, never resets on reopen, and uses exit 1 for both "usage error" and "budget spent". | `v0-status.md:19`; `v0-deliver.md:12`; `v0-design.md:28`; `check-attempt-budget.sh:17, 41-57` |
| **M5** | **Contradictory and dangling instructions dilute adherence.** `orchestrator.md:19` says the Release approval "records the phases" for P0-A and that the Build approval records Design. `v0-build.md:37`, `v0-verify.md:34` and `v0-design.md:27` have the agent run `--approve` immediately. Dangling references: "`workflow-orchestration.mdc` Batch approval" (`orchestrator.md:28`), "…Architecture" skip list (`:18`, `program-architecture/SKILL.md:8`), "Helper agents" (`schema-author.md:13`, real heading: *Helper Subagents*), `reopenedPhases` (`orchestrator.md:24`, `_state.template.json:6`; the script never writes it). Triage allows "patch/minor" (`v0-triage.md:10`) while the rule says "patch" (`workflow-orchestration.mdc:65`). | as cited |
| **M6** | **Tool feedback is not structured.** `pre-shell.sh` blocks with stderr and exit 2 but emits no `{"permission":"deny","agent_message":…}`, so the agent may never see why. `pre-edit.sh` does emit it. When `pre-edit.sh` cannot extract a path, it exits 0 with no JSON (`:26`). Under `failClosed` that is a silent block. With unrecognised payload keys (`target_file`, multi-file edits) it fails open. State scripts print free-text `FAIL:` lines on overloaded exit codes (1 = usage, data and validation). | `pre-shell.sh:11-15`; `pre-edit.sh:26` |
| **M7** | **The shell guard can be bypassed.** A heredoc interpreter (`python3 - <<EOF open('…state.json','w')…`) is allowed. Paths are not normalised: `.cursor/./rules/x.mdc` → `allow`. `activate-stack-pack.sh --force` (which rewrites the protected rules and skills tree) → `allow`. | probes in Appendix A5 |
| **M8** | **Tier downgrade skips security review.** `tier:` is read from the agent-editable artifact. `tier: trivial` triggers the abbreviated Verify, which skips `security-reviewer` and `code-reviewer`. The script never checks the `Tier confirmed by` row that the user is supposed to confirm. | `sync-feature-state.sh:157-158`; `v0-verify.md:24-25`; `v0-triage.md:18` |
| **M9** | **Role tool scopes are wider than their contracts.** `security-reviewer`, `code-reviewer` and `design-reviewer` have `write` + `shell`, limited only by "use write access only for this report". Hooks cannot see agent identity, so there is no path scope per role. The **cheapest** model (Orchestrator = Build tier) interprets "did the user approve?". | agent frontmatter; `model-config.json:10` |

### Low

| # | Finding | Evidence |
|---|---------|----------|
| L1 | `*.state.json.lock` files are not gitignored. `stop.sh`'s doc filter does not exclude `.lock`, so you get spurious "uncommitted code" reminders. | `.gitignore`; `stop.sh:33` |
| L2 | `stop.sh`'s "evidence" grep misses `dotnet test`, `go test` and `pnpm`, so a dotnet repo always gets the reminder. | `stop.sh:29` |
| L3 | `session-start.sh` lists every open state file without a cap and without the next command or blocked reason. | `session-start.sh:16-32` |
| L4 | Each shell call starts about 5 Python interpreters (policy, 2× JSON parse, audit log). That adds latency to every command. | `pre-shell.sh:21-27,43` |
| L5 | Observability: `audit.jsonl` has no session, feature or phase id. State is overwritten in place with no history, so a failed run cannot be traced or replayed. `phase-result.md` is free text. | `lib.sh:66-94`; `sync-feature-state.sh:555-562` |
| L6 | `eval "$(resolve-layout.sh)"` is in the agent-facing command text. Values are single-quoted without escaping, so a `'` in a profile cell breaks out. | `v0-verify.md:19`; `resolve-layout.sh:74-78` |

---

## 2. Context & Prompt Optimization

**Baseline:** always-on context is `AGENTS.md` (5.8 KB) plus three `alwaysApply` rules (18.4 KB), about **6k tokens per turn per agent**. Every one of the 19 subagent launches pays it again. Roughly 60% of it duplicates command files or is domain guidance that only applies to code edits.

### 2.1 `workflow-orchestration.mdc` (9.4 KB → ~3.5 KB)

- **Delete lines 82-93 ("Phase Gates Summary").** They repeat every `v0-*.md` command, and two lines in them disagree with the commands (M5). Replace them with one line: `Each phase's prerequisites, outputs and gate live in its command file; the state script enforces order.`
- **Move the field table (lines 36-47)** to `agents-v0-kit.md`. Agents never need field semantics in every turn because the script now validates them.
- **Replace lines 49-51 and 77-80** with the invariant block below. It moves budgets and prerequisites into code and tells the agent how to react to exit codes instead of how to count:

```markdown
## State contract (enforced by `.agents-v0/scripts/sync-feature-state.sh`)
- Always pass the **primary artifact** (`requirements/<feature>.md`, `maintain/<id>/note.md`, `onboarding/*.md`, `roadmap/*.md`, `architecture.md`, `milestones/*.md`).
- Exit `0` → continue. Exit `3` → illegal transition: read `next_command` from the stderr JSON and stop. Exit `2` → budget/loop exhausted, state is already `blocked`: report and stop. Exit `64` → fix the invocation.
- `--approve <phase> --approved-by <name>` prompts the human in the IDE. Run it only right after the user approved in chat. If the prompt is declined, stop.
- Gate skips are not judgment calls: use `--auto-approve design --rule contract-none` or `--auto-approve build|verify --rule p0-a`; the script checks the predicate.
- Never edit `Delivery approvals` rows or `tier:`; humans do.
```

- **Fix headings and references** so cross-file pointers resolve: rename *Helper Subagents (Hub-and-Spoke)* → *Helper agents*, or update the four callers. Either add a *Batch approval* section or delete `orchestrator.md:28`.

### 2.2 `project-delivery-core.mdc` (6.2 KB, always on)

Split it. Keep **Stack (active pack)** and **Directory profiles** always on (~2.4 KB). Move *Cross-cutting*, *API envelopes*, *Design defaults*, *Documentation*, *BFF and frontends*, and *OMS* into a new glob-scoped rule:

```yaml
---
description: Service-code defaults (observability, envelopes, resilience, BFF, OMS)
globs: "**/*.cs,**/*.java,**/*.go,**/*.py,**/*.ts,**/*.tsx,openapi/**,docs/agents-v0/design/**"
alwaysApply: false
---
```

This saves about 1k tokens on every Intake, Roadmap, Status, Release and Triage turn, where none of it applies.

### 2.3 `ai-agent-conduct.mdc`

- Delete **Prompt efficiency** (lines 49-57). It tells the *human* how to write prompts and is noise in agent context.
- Delete **Rule precedence** (lines 59-61), which is a third copy. Keep it once, in `AGENTS.md`.
- Merge **Git and PRs** into one line: `Commits, merges, pushes, tags, MR changes: the IDE prompt is the authorization; if declined, stop.`

### 2.4 `AGENTS.md`

The 15-row lifecycle table duplicates the rule's mermaid and phase list. Cursor loads both. Reduce `AGENTS.md` to Mission, Non-negotiables and Reference (~1.5 KB), and point to `/v0-status` for routing.

### 2.5 Agents and commands

- `test-engineer.md` description: replace "JUnit5+Mockito+AssertJ, Vitest" with "the bound pack's test stack (`pack.json`)". Under the **dotnet** pack the stack-specific text misleads tool choice.
- `orchestrator.md:19`: delete the P0-A and Contract-None prose and replace it with: `P0-A and Contract: None gates are recorded by --auto-approve (script-checked). Stop at every gate whose sync call did not exit 0.`
- `v0-status.md:19`: route by `blockedCode`, not by `activePhase`:

```markdown
- `blocked`: route by `blockedCode` —
  `prereq:<phase>` / `E_PREREQ` → `/v0-<phase>`; `E_REOPEN_BUDGET` → stop, human decides (`--unblock`);
  `E_ATTEMPT_BUDGET` → stop, present `build-report.md`; anything else → `/v0-<activePhase>` once, then ask.
```

- Reviewers (`security-reviewer`, `code-reviewer`, `design-reviewer`): drop `shell` where possible. They only need `git diff` output, which the launcher can pass as `git diff --stat <base>...HEAD` plus a per-file `git diff -U3` list rather than whole files. Keep `write` for the report only.
- `release-manager` and local-release: reorder to **verify → merge → `--approve release`** (approve last), so a failed merge leaves `release/awaiting_approval`.

---

## 3. Refactored Implementation

Full patches (scratch, tested):
- [sync-feature-state.diff](file:///Users/marlondurana/.gemini/antigravity/brain/3eac9f38-6bcc-4750-9d67-815fe2f78910/scratch/sync-feature-state.diff) → patched [sync-feature-state.v2.sh](file:///Users/marlondurana/.gemini/antigravity/brain/3eac9f38-6bcc-4750-9d67-815fe2f78910/scratch/sync-feature-state.v2.sh), smoke test [test-v2.sh](file:///Users/marlondurana/.gemini/antigravity/brain/3eac9f38-6bcc-4750-9d67-815fe2f78910/scratch/test-v2.sh) (**33/33 pass**)
- [hook-policy.diff](file:///Users/marlondurana/.gemini/antigravity/brain/3eac9f38-6bcc-4750-9d67-815fe2f78910/scratch/hook-policy.diff): existing suite 211/213. The 2 failures are the **intended** change: committing `requirements/<feature>.md` now prompts. Update those two expectations in `scripts/test-hook-policy.py` to `ask`.
- [check-failure-brief.diff](file:///Users/marlondurana/.gemini/antigravity/brain/3eac9f38-6bcc-4750-9d67-815fe2f78910/scratch/check-failure-brief.diff)

### 3.1 Make approval a human act (H1, M7): `hook-policy.py`

The key point: Cursor **does** enforce `ask` on `beforeShellExecution`. Routing the privileged state flags through it turns the IDE permission dialog into the approval record, with no new infrastructure.

```diff
+# Kit scripts that are privileged writers of gate state. The shell "ask" is enforced by Cursor
+# (unlike preToolUse "ask"), so the native permission prompt becomes the human approval act.
+_STATE_SCRIPT = re.compile(r"(^|/)sync-feature-state\.sh$")
+_PACK_SCRIPT = re.compile(r"(^|/)activate-stack-pack\.sh$")
+
+def _privileged_kit_script(parts: List[str]) -> Optional[Tuple[Action, str]]:
+    args = parts[1:] if parts[0].split("/")[-1] in ("sh", "bash", "dash", "zsh") else parts
+    if not args:
+        return None
+    script, flags = args[0], args[1:]
+    if _STATE_SCRIPT.search(script):
+        if "--approve" in flags or "--unblock" in flags:
+            return "ask", "recording a gate approval/unblock is a human act; approve only if you just approved this phase in chat."
+        if "--clear-active" in flags:
+            return "ask", "clearing the active phase ends a gate; requires explicit user approval."
+    if _PACK_SCRIPT.search(script) and "--force" in flags:
+        return "ask", "replacing the bound stack pack rewrites rules and skills; requires explicit user approval."
+    return None
+
+# Interpreter fed by a heredoc / stdin: the body is not visible as argv, so scan the whole command.
+_HEREDOC_INTERP = re.compile(r"\b(?:python3?|node|perl|ruby)\b[^\n|;&]*(?:\s-\s*)?<<-?\s*['\"]?\w+")
+
+def _heredoc_writes_protected(cmd: str) -> Optional[str]:
+    if not _HEREDOC_INTERP.search(cmd) or not SCRIPT_WRITE_HINT.search(cmd):
+        return None
+    for lit in re.findall(r"['\"]([^'\"\n]+)['\"]", cmd):
+        if is_protected_path(lit):
+            return lit
+    return None
@@ classify_segment (after bin0 is computed)
+    priv = _privileged_kit_script(parts)
+    if priv:
+        return priv
@@ _commit_paths_are_evidence
-        elif (
-            (norm.startswith("docs/agents-v0/requirements/") and norm.endswith(".md"))
-            or (norm.startswith("docs/agents-v0/maintain/") and norm.endswith("/note.md"))
-        ):
-            continue
         else:
+            # requirements/<feature>.md and maintain/<id>/note.md carry the Delivery approvals table:
+            # committing them grants approvals, so they always go through the ask prompt.
             return False
@@ classify_command
+    hp = _heredoc_writes_protected(cmd)
+    if hp:
+        return "block", f"Protected kit/state path cannot be written by an inline interpreter: {hp}"
@@ PROTECTED_PATH_PATTERNS
+    re.compile(r"(^|/)docs/agents-v0/.+\.history\.jsonl$"),
@@ is_protected_path
-    norm = path.replace("\\", "/")
-    for pat in PROTECTED_PATH_PATTERNS:
-        if pat.search(norm):
-            return True
+    raw = path.replace("\\", "/").strip().strip("'\"")
+    norm = posixpath.normpath(raw) if raw else raw     # ".cursor/./rules/x" → ".cursor/rules/x"
+    for candidate in {raw, norm}:
+        for pat in PROTECTED_PATH_PATTERNS:
+            if pat.search(candidate):
+                return True
     return False
```

### 3.2 A deterministic state machine (H2, H5, M1–M3, M8): `sync-feature-state.sh`

Summary of the patch (full diff linked above):

| Change | Effect |
|---|---|
| Strict primary-artifact `case`, repo-relative normalisation | M3: `design.md` → `E_ARTIFACT` (exit 64) |
| `PREREQ` transition table (P0-A chain = `build→verify→release`) applied to `--approve`, `--auto-approve`, and non-blocked `--active-phase` | H2: no skip-ahead, no transitive fill |
| `--approve` requires `--approved-by`, `activePhase==<phase>/awaiting_approval`, and `verifyPassed` for verify/release | H1 + H2 |
| `--auto-approve <phase> --rule contract-none\|p0-a` with **file-based predicates** | Takes LLM judgment out of gate skips |
| Delivery-approval rows **grant only from `git show HEAD:<artifact>`**. Working-tree rows can only withdraw | H1 (a) |
| `--reopen` forces `verifyPassed=false` and clears `verifiedCommit` | H5 (a) |
| `--verify-passed true` needs `activePhase==verify` and `quality-gate.md`, and records `verifiedCommit=HEAD` | H5 (b) |
| `--approve release` fails `E_STALE_VERIFY` if non-doc files changed since `verifiedCommit` | H5 (b) |
| Reopen overflow **writes** `blocked`/`blockedCode:E_REOPEN_BUDGET` and then exits 2. Later agent calls get `E_ESCALATED` until a human `--unblock` (which prompts) | M1: terminal state |
| Helper dedup only with `--register-brief <path>`, hashing `helper`+normalised `ask` | M2 |
| `tier: trivial` honoured only with a `Tier confirmed by:` line | M8 |
| JSON stdout and stderr (`{"ok":false,"code":"E_PREREQ","next_command":"/v0-design"}`), exit codes `0/2/3/64/65` | M6 |
| `schemaVersion`, `approvals[]` (who, when, head, via), `blockedCode`, `verifiedCommit` | Auditable state |
| Append-only `<state>.history.jsonl` (argv, head, session, field diff), written under the same `flock` | L5: trace and replay |

Core of the new logic:

```python
chain = ["build", "verify", "release"] if p0a and not (onboarding or maintain_note or program_doc) else phases
PREREQ = {p: chain[i - 1] for i, p in enumerate(chain) if i}

def require_prereq(phase, action):
    if phase not in chain:
        fail("E_PHASE", f"{action}: phase '{phase}' is not in this work item's chain {chain}", 3)
    pre = PREREQ.get(phase)
    if pre and pre not in approved_list:
        fail("E_PREREQ", f"{action} {phase}: '{pre}' must be approved first", 3,
             phase=phase, missing=pre, next_command=f"/v0-{pre}")

if cli_approve:
    require_prereq(cli_approve, "--approve")
    if (prev.get("activePhase"), prev.get("activeStatus")) != (cli_approve, "awaiting_approval"):
        fail("E_NOT_AWAITING", f"--approve {cli_approve}: phase is not awaiting_approval "
             f"(active={prev.get('activePhase') or '-'}/{prev.get('activeStatus') or '-'})", 3)
    if cli_approve in ("verify", "release") and not prev.get("verifyPassed"):
        fail("E_VERIFY", f"--approve {cli_approve}: verifyPassed is not true", 3, next_command="/v0-verify")
    if cli_approve == "release" and prev.get("verifiedCommit") and head_now:
        changed = subprocess.run(["git", "diff", "--name-only", prev["verifiedCommit"], "HEAD"],
                                 capture_output=True, text=True, check=False).stdout.split()
        code_changes = [p for p in changed if not (p.startswith("docs/") or p in ("CHANGELOG.md", "README.md"))]
        if code_changes:
            fail("E_STALE_VERIFY", "code changed after Verify; re-run /v0-verify", 3, files=code_changes[:20])
    ...
    approvals.append({"phase": cli_approve, "by": os.environ.get("HOOK_APPROVED_BY", ""),
                      "at": now_iso, "head": head_now, "via": "cli"})

# reopen overflow is persisted, not thrown away
escalate = reopen_count > MAX_REOPEN
...
if escalate:
    active_phase, active_status = cli_reopen, "blocked"
    blocked_reason = f"reopen budget exhausted ({reopen_count} > {MAX_REOPEN}); human decision required"
    blocked_code = "E_REOPEN_BUDGET"
```

**Command-file updates this patch requires** (find and replace):

| File | Old | New |
|---|---|---|
| all `v0-*.md` approval steps | `--approve <phase> <artifact>` | `--approve <phase> --approved-by "<user>" <artifact>` |
| `v0-design.md:27` | `--approve design` (Contract: None) | `--auto-approve design --rule contract-none` |
| `v0-build.md:37`, `v0-verify.md:34` | `--approve build` / `--verify-passed true --approve verify` | `--auto-approve build --rule p0-a` / `--verify-passed true --auto-approve verify --rule p0-a` |
| `workflow-orchestration.mdc:74`, `v0-maintain.md:25` | `sync-feature-state.sh <artifact>` (dedup) | `sync-feature-state.sh --register-brief <brief> <artifact>` |
| `v0-local-release.md:25-28` | approve → commit → merge | commit → merge → `--approve release` |
| `_state.template.json` | `reopenedPhases` | remove; add `schemaVersion`, `approvals`, `blockedCode`, `verifiedCommit` |

### 3.3 Eval injection (H4): `check-failure-brief.sh`

```diff
-import os, re, sys
+import os, re, shlex, sys
 ...
-print("NEED_TESTS=%s" % ",".join(need))
+print("NEED_TESTS=%s" % shlex.quote(",".join(need)))
```

Verified: a test name `returns 404 when missing; touch PWNED` now produces a correct `FAIL … exit 1` and no `PWNED` file.

### 3.4 Structured block feedback (M6): `pre-shell.sh` and `pre-edit.sh`

```sh
# pre-shell.sh — replace block()
block() {
  hook_audit_log "shell" "$cmd" "block" "$1"
  printf 'BLOCK: %s\n' "$1" >&2
  HOOK_DENY_MSG="$1" python3 -c 'import json,os; m=os.environ["HOOK_DENY_MSG"]; print(json.dumps({"permission":"deny","user_message":m,"agent_message":"BLOCKED by kit policy: "+m+" Do not retry a variant of this command; report to the user."}))' 2>/dev/null || true
  exit 2
}
```

```sh
# pre-edit.sh:26 — no silent outcome when the payload shape is unknown
[ -n "$path" ] || { hook_audit_log "path" "" "deny-unparsed" "no file path in payload";
  printf '{"permission":"deny","agent_message":"pre-edit: could not determine target path; use a single-file Edit/Write."}\n'; exit 2; }
```

Also add `target_file` and `paths[0]` to the key list in `hook_json_string_field` / `pre-edit.sh:16,21`.

### 3.5 Read state from the pushed commit (H3): `hooks/pre-push`

```sh
  state_file="docs/agents-v0/requirements/${feature}.state.json"
  git cat-file -e "$local_sha:$state_file" 2>/dev/null || state_file="docs/agents-v0/maintain/${feature}/state.json"
  if ! git cat-file -e "$local_sha:$state_file" 2>/dev/null; then
    # Branch touches application code but has no state → refuse (fail closed for feature branches).
    if git diff --name-only "${remote_sha:-$local_sha~1}" "$local_sha" 2>/dev/null | grep -qv '^docs/'; then
      case "$branch" in feature/*|fix/*) echo "pre-push: $branch changes code but has no state file" >&2; exit 1;; esac
    fi
    continue
  fi
  git show "$local_sha:$state_file" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ok = d.get("verifyPassed") is True and "verify" in (d.get("approvedPhases") or []) and d.get("verifiedCommit")
sys.exit(0 if ok else 1)' || { echo "pre-push: $state_file at $local_sha has not passed and been approved at Verify" >&2; exit 1; }
```

### 3.6 Bring back a minimal CI evidence gate (H3)

Add one job to `templates/.gitlab-ci.yml`. It is the only check an agent cannot bypass locally:

```yaml
delivery-gate:
  stage: test
  image: ${CI_IMAGE_PREFIX}python:3.12-slim
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - |
      python3 - <<'PY'
      import json, os, subprocess, sys
      base = os.environ["CI_MERGE_REQUEST_DIFF_BASE_SHA"]
      changed = subprocess.run(["git","diff","--name-only",base,"HEAD"],capture_output=True,text=True).stdout.split()
      states = [p for p in changed if p.endswith(".state.json")]
      code = [p for p in changed if not p.startswith("docs/")]
      if code and not states: sys.exit("delivery-gate: code changed but no state file in this MR")
      for p in states:
          d = json.load(open(p))
          if d.get("schemaVersion", 1) < 2: sys.exit(f"{p}: schemaVersion < 2")
          if not (d.get("verifyPassed") and "verify" in d.get("approvedPhases", [])): sys.exit(f"{p}: Verify not passed+approved")
          vc = d.get("verifiedCommit", "")
          drift = subprocess.run(["git","diff","--name-only",vc,"HEAD"],capture_output=True,text=True).stdout.split()
          drift = [f for f in drift if not f.startswith("docs/") and f not in ("CHANGELOG.md","README.md")]
          if drift: sys.exit(f"{p}: code changed after Verify ({vc[:8]}): {drift[:5]}")
          if not any(a.get("phase")=="verify" and a.get("via")=="cli" and a.get("by") for a in d.get("approvals",[])):
              sys.exit(f"{p}: no human Verify approval recorded")
      print("delivery-gate: OK")
      PY
```

Also make the backend job **fail** when it resolves no verify command. Add before line 85:

```sh
      else
        echo "backend: no verify command resolved for pack '${pack_id:-?}' (set 'Backend verify' in project-profile.md)" >&2
        exit 1
      fi
```

### 3.7 JSON Schema for state (for CI, `validate-kit --target`, and `/v0-status`)

`templates/docs/agents-v0/state.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["schemaVersion","feature","tier","lastApprovedPhase","approvedPhases","activePhase","activeStatus","verifyPassed","reopenCount","artifact","baseCommit","updatedAt"],
  "properties": {
    "schemaVersion": {"const": 2},
    "feature": {"type": "string", "pattern": "^[a-z0-9][a-z0-9._-]*$"},
    "tier": {"enum": ["standard","trivial","major","emergency"]},
    "lastApprovedPhase": {"enum": ["","onboard","roadmap","architecture","plan","intake","design","build","maintain","verify","release"]},
    "approvedPhases": {"type": "array", "uniqueItems": true, "items": {"$ref": "#/properties/lastApprovedPhase"}},
    "approvals": {"type": "array", "items": {"type": "object", "required": ["phase","by","at","via"],
      "properties": {"via": {"enum": ["cli","delivery-approvals-row","rule:contract-none","rule:p0-a"]}}}},
    "activePhase": {"$ref": "#/properties/lastApprovedPhase"},
    "activeStatus": {"enum": ["","in_progress","awaiting_approval","blocked"]},
    "blockedCode": {"type": "string", "pattern": "^$|^(E_[A-Z_]+|prereq:[a-z]+)$"},
    "verifyPassed": {"type": "boolean"},
    "verifiedCommit": {"type": "string", "pattern": "^$|^[0-9a-f]{40}$"},
    "reopenCount": {"type": "integer", "minimum": 0, "maximum": 4},
    "baseCommit": {"type": "string", "pattern": "^$|^[0-9a-f]{7,40}$"}
  },
  "allOf": [
    {"if": {"properties": {"activeStatus": {"const": "blocked"}}}, "then": {"required": ["blockedReason","blockedCode"]}},
    {"if": {"properties": {"lastApprovedPhase": {"enum": ["verify","release"]}}}, "then": {"properties": {"verifyPassed": {"const": true}}}}
  ]
}
```

### 3.8 Catch cross-reference drift (M5): `validate-kit.sh`

```sh
# 10. Section references "`<rule>.mdc` <Heading>" must resolve to a heading in that rule.
python3 - <<'PY' || fail=1
import re, pathlib, sys
rules = {p.name: {re.sub(r"\s*\(.*\)$", "", h).strip().lower() for h in re.findall(r"^#+\s+(.+)$", p.read_text(), re.M)}
         for p in pathlib.Path("core").rglob("*.mdc")}
bad = []
for f in list(pathlib.Path("core").rglob("*.md")) + list(pathlib.Path("core").rglob("*.mdc")):
    for rule, sect in re.findall(r"`([a-z-]+\.mdc)`\s+([A-Z][A-Za-z &-]+?)(?=[).,;:]|\s+(?:section|for|and)\b)", f.read_text()):
        if rule in rules and sect.strip().lower() not in rules[rule]:
            bad.append(f"{f}: `{rule}` {sect.strip()}")
for b in bad: print("FAIL: dangling rule reference:", b, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
grep -rq 'reopenedPhases' core templates && err "reopenedPhases is not written by sync-feature-state.sh"
```

### 3.9 Smaller fixes

```gitignore
# templates/.gitignore
docs/agents-v0/**/*.lock
```

```sh
# stop.sh:29 — recognise all pack verify commands
grep -Eqi 'mvn|gradle|npm|pnpm|yarn|vitest|jest|pytest|dotnet (test|build)|go test|run-backend-verify|coverage|docs/agents-v0/(build|verify)/'
```

```sh
# lib.sh hook_audit_log — correlate hook events with runs (fields Cursor passes in hook payloads)
"session": os.environ.get("HOOK_CONVERSATION_ID",""), "generation": os.environ.get("HOOK_GENERATION_ID",""),
# set in pre-shell.sh / pre-edit.sh:
# HOOK_CONVERSATION_ID="$(printf '%s' "$payload" | hook_json_string_field conversation_id)"
```

---

## 4. Observability & Testability: recommendations without code

1. **Trace a failed run.** Join `<state>.history.jsonl` (state transitions, argv, head) with `.cursor/hooks/audit.jsonl` (every shell and edit decision) on `session`. That gives a full timeline for a feature without reading transcripts.
2. **Replay a step deterministically.** Every transition records `head` and `argv`. `git worktree add /tmp/r <head>`, copy the prior state line, and rerun the same argv. The script is now a pure function of (prev state, artifact at HEAD, argv, files on disk).
3. **Per-phase prompt capture.** Have each phase write `phase-result.md` with YAML front matter (`phase`, `status`, `criticals: [{source, id, file, line}]`, `commands: [{cmd, exit}]`). Verify→Build routing then parses a list instead of re-reading three reports.
4. **Tests.** Promote `scratch/test-v2.sh` into `scripts/test-state-machine.sh` and wire it into `validate-kit.sh`. Add the A5 probes to `test-hook-policy.py`.

---

## Appendix A: Reproductions

```text
A1  sync --approve release requirements/f1.md       → approvedPhases=[intake..release], verifyPassed=True
A2  write f1.helper-brief.md; sync f1.md; sync --active-phase build --status in_progress f1.md
                                                     → FAIL: Duplicate helper brief ask detected … exit=2
A3  build-report rows "returns 404 when missing" ×2; check-failure-brief.sh f1
                                                     → line 72: 404: command not found  exit=127
A4  sync --approve intake design/f1/design.md        → wrote requirements/design.state.json
A5  hook-policy shell "sh …/sync-feature-state.sh --approve release …"   → allow
    hook-policy shell "python3 - <<EOF\nopen('…/f1.state.json','w')…"     → allow
    hook-policy path  ".cursor/./rules/x.mdc"                              → allow
    hook-policy shell "sh …/activate-stack-pack.sh node --force"           → allow
After patches: A1 → E_PREREQ/E_APPROVER; A2 → ok; A3 → FAIL exit 1 (no exec); A4 → E_ARTIFACT;
A5 → ask / block / block / ask.
```
