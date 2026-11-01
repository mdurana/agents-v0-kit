#!/bin/sh
# test-state-json-guard.sh — onboard fix (Iruka scope, Sasuke): docs/agents-v0/onboarding/state.json (and the other
# workflow state files) is never an agent's write, on Cursor and on agy, in every mode. Each tool is driven through
# its real hook entry point in a scratch project: Cursor Edit/Write/Delete (pre-edit.sh, tool_input.file_path) and
# beforeShellExecution (pre-shell.sh), agy write_file and edit_file (pre-edit.sh) and run_command (pre-shell.sh,
# through the exact command line in core/common/adapters/antigravity/hooks.json). Shell spellings: redirects
# (> >> >|), tee, cp, mv, a destination folder, -t, a relative path after cd, an inline python write; the rest of the
# spellings (install, ln, rsync, dd, sed -i, truncate, git checkout/restore, ...) are in scripts/test-hook-policy.py. The kit's own scripts stay allowed:
# sync-feature-state.sh runs (it writes a temp file and renames it, which no hook sees), reads stay allowed.
# Known gap (recorded in the handoff): a hook that matches command text cannot stop a script the agent wrote first.
# No agent, no model call: the commands are judged, never run. The scratch folder is this run's own.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0; n=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
command -v python3 >/dev/null 2>&1 || { err "python3 not found"; exit 1; }

scratch="$(mktemp -d)"
trap 'rc=$?; rm -rf "$scratch"; exit $rc' EXIT INT TERM

hooks_cmd() {  # <adapter> <matcher>
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
if "agents-v0-delivery" in d:
    for m in d["agents-v0-delivery"]["PreToolUse"]:
        if m["matcher"] == sys.argv[2]:
            print(m["hooks"][0]["command"]); break
else:
    for ev, items in d["hooks"].items():
        for m in items:
            if sys.argv[2] in m["command"]:
                print(m["command"]); break
' "$KIT/core/common/adapters/$1/hooks.json" "$2" | head -n 1
}
AGY_SHELL="$(hooks_cmd antigravity run_command)"
AGY_EDIT="$(hooks_cmd antigravity 'edit_file|write_file')"
CUR_SHELL="$(hooks_cmd cursor pre-shell.sh)"
CUR_EDIT="$(hooks_cmd cursor pre-edit.sh)"
for v in "$AGY_SHELL" "$AGY_EDIT" "$CUR_SHELL" "$CUR_EDIT"; do
  case "$v" in *KIT_HOOK_FLAVOR=*pre-*.sh*) ;; *) err "hook entry not found in an adapter hooks.json ($v)"; exit 1 ;; esac
done

P="$scratch/proj"
mkdir -p "$P/.agents" "$P/.cursor" "$P/.agents-v0/scripts" "$P/docs/agents-v0/onboarding"
cp -R "$KIT/core/common/hooks" "$P/.agents/hooks"
cp -R "$KIT/core/common/hooks" "$P/.cursor/hooks"
cp "$KIT/templates/.agents-v0/scripts/sync-feature-state.sh" "$P/.agents-v0/scripts/"
printf '{}\n' > "$P/docs/agents-v0/onboarding/state.json"
git init -q -b main "$P"
S=docs/agents-v0/onboarding/state.json

# judge <tool> <want block|allow|ask> <label> <arg> [VAR=value ...]
judge() {
  tool="$1"; want="$2"; label="$3"; arg="$4"; shift 4
  n=$((n + 1))
  case "$tool" in
    cursor-shell) cmdline="$CUR_SHELL"; payload="$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1],"cwd":sys.argv[2]}))' "$arg" "$P")" ;;
    cursor-edit|cursor-write|cursor-delete)
      cmdline="$CUR_EDIT"; payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[2],"tool_input":{"file_path":sys.argv[1]}}))' "$arg" "${tool#cursor-}")" ;;
    agy-shell) cmdline="$AGY_SHELL"; payload="$(python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":"run_command","args":{"CommandLine":sys.argv[1],"Cwd":sys.argv[2]}}}))' "$arg" "$P")" ;;
    agy-write_file|agy-edit_file)
      cmdline="$AGY_EDIT"; payload="$(python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":sys.argv[2],"args":{"Path":sys.argv[1]}}}))' "$arg" "${tool#agy-}")" ;;
  esac
  set +e
  out="$(cd "$P" && printf '%s' "$payload" | env "$@" /bin/sh -c "$cmdline" 2>&1)"
  rc=$?
  set -e
  case "$want" in
    block) [ "$rc" = 2 ] || err "$tool $label: expected a refusal (rc=2), got rc=$rc: $arg ($out)" ;;
    allow) { [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -Eq 'BLOCK:|"(deny|ask)"'; } \
             || err "$tool $label: expected allow (rc=0), got rc=$rc: $arg ($out)" ;;
    ask) { [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '"ask"'; } \
             || err "$tool $label: expected ask (rc=0), got rc=$rc: $arg ($out)" ;;
  esac
}

UA='AGY_ALLOW_TOOLS=Shell(*),Shell(sh:*),Shell(cp:*),Shell(echo:*)'
# One or two cases per tool and spelling here; the full list of spellings (about 65, every state file, both modes)
# is in scripts/test-hook-policy.py, which judges the same policy without a process per case.
# Edit tools: each tool refuses (agy also unattended, where an ask would become an allow).
for t in cursor-edit cursor-write cursor-delete agy-write_file agy-edit_file; do
  judge "$t" block "edit tool" "$S"
done
judge cursor-edit block "edit tool, absolute path" "$P/$S"
judge agy-write_file block "edit tool, unattended" "$S" "$UA"
judge agy-edit_file block "edit tool, unattended, ./ path" "./$S" "$UA"
# Shell writes: Cursor and agy attended, agy unattended.
while IFS= read -r c; do
  [ -n "$c" ] || continue
  judge cursor-shell block "shell write" "$c"
  judge agy-shell block "shell write" "$c"
  judge agy-shell block "shell write, unattended" "$c" "$UA"
done <<EOC
echo {} > $S
echo {} >> $S
cat /tmp/x >| $S
echo {} | tee $S
cp /tmp/x $S
cp -t docs/agents-v0/onboarding /tmp/state.json
mv /tmp/x $S
mv /tmp/state.json docs/agents-v0/onboarding/
cd docs/agents-v0/onboarding && echo {} > state.json
python3 -c "open('$S','w').write('{}')"
EOC
# Cursor only (agy is out of the onboard fix per Sensei): a few spellings through the Cursor entry point, so the
#   in-process lists in test-hook-policy.py are known to be what the hook does. Jiraiya C and Iruka note 2 (a folder
#   checkout, a run-time target, pushd, a writer tool, git stash apply and git am; a run-time target away from
#   the state folders asks; round 3: a forced checkout/switch and git stash pop), then Jiraiya A and B (gh token, git-push, a $var command name).
while IFS= read -r c; do
  [ -n "$c" ] || continue
  judge cursor-shell block "shell write (Jiraiya C / Iruka 2)" "$c"
done <<EOC
git checkout HEAD~1 -- docs/agents-v0/onboarding
f=$S; echo {} > \$f
pushd docs/agents-v0/onboarding && echo {} > state.json
git apply x.diff
git stash apply
git am x.patch
git checkout -f main
git switch --discard-changes main
git stash pop
EOC
judge cursor-shell ask "run-time write target (Jiraiya round 2)" 'echo {} > "$OUT"'
while IFS= read -r c; do
  [ -n "$c" ] || continue
  judge cursor-shell block "remote write or token (Jiraiya A / B)" "$c"
done <<EOC
gh auth token
git-push origin main
g=gh; \$g pr create --fill
EOC
judge cursor-shell allow "gh read (Jiraiya B)" "gh auth status"
judge cursor-shell allow "plain branch checkout" "git checkout main"
judge cursor-shell allow "plain branch switch (Jiraiya round 3)" "git switch main"
# The kit's own scripts and plain reads stay allowed.
while IFS= read -r c; do
  [ -n "$c" ] || continue
  for t in cursor-shell agy-shell; do
    judge "$t" allow "kit script or read" "$c"
  done
done <<EOC
sh .agents-v0/scripts/sync-feature-state.sh --active-phase onboard --status in_progress docs/agents-v0/onboarding/onboarding.md
cat $S
EOC
judge agy-write_file allow "edit tool, the onboarding record next to it" docs/agents-v0/onboarding/notes.md
# sync-feature-state.sh writes state through a temp file and os.replace, never by a command a hook judges.
grep -q 'os.replace(tmp_path, out)' "$KIT/templates/.agents-v0/scripts/sync-feature-state.sh" \
  || err "sync-feature-state.sh no longer writes state via tempfile + os.replace; re-check the state guard"
n=$((n + 1))

# JO-8 (Sasuke): with onboarding in progress (activePhase onboard) the only commit is the onboard chain step
#   `gate-checks.sh commit_msg_ok && git commit -F <onboard message>` (still an ask), and the onboard message and scan
#   record are never an agent's write. Through the Cursor entry; the full list is in scripts/test-hook-policy.py.
printf '{"activePhase":"onboard","activeStatus":"awaiting_approval","approvedPhases":[]}\n' > "$P/$S"
G='sh .agents-v0/scripts/gate-checks.sh commit_msg_ok'
M=.git/agents-v0-onboard-commit-msg.txt
judge cursor-shell block "JO-8 commit outside the chain" "git commit -m x"
judge cursor-shell block "JO-8 commit after ; not &&" "$G ; git commit -F $M"
judge cursor-shell block "JO-8 commit with another message file" "$G && git commit -F other.txt"
judge cursor-shell block "JO-8 write to the scan record" "printf x > .git/agents-v0-onboard-commit-msg.scan"
judge cursor-shell ask "JO-8 the chain's commit step (git commit asks)" "$G && git commit -F $M"
judge cursor-shell allow "JO-8 read the onboard message" "cat $M"
judge cursor-edit block "JO-8 edit tool on the onboard message" "$M"

# Jiraiya 8670b7e4 review (Sasuke): commands inside ( ) and { } groups are judged like the same command bare, the
#   protected paths match in any case (macOS file systems), and commit aliases / commit-tree are denied during
#   onboarding. Through the Cursor entry; the full list is in scripts/test-hook-policy.py (jr3_cases).
judge cursor-shell block "group: subshell push" "(git push origin main)"
judge cursor-shell block "group: brace push" "{ git push; }"
judge cursor-shell block "group: subshell restore over the state" "(git restore .)"
judge cursor-shell block "group: subshell commit during onboarding" "(git commit -m x)"
judge cursor-shell block "group: grouped commit after the check" "$G && (git commit -F $M)"
judge cursor-shell block "group: subshell state write" "( printf x > $S ) 2>&1"
judge cursor-shell allow "group: plain subshell" "(ls)"
judge cursor-shell allow "group: plain brace group" "{ echo hi; }"
judge cursor-shell block "case: upper-case .GIT scan record" "printf x > .GIT/agents-v0-onboard-commit-msg.scan"
judge cursor-edit block "case: upper-case state path" "DOCS/AGENTS-V0/ONBOARDING/STATE.JSON"
judge cursor-shell block "onboarding: commit alias" "git -c alias.ci=commit ci -m x"
judge cursor-shell block "onboarding: commit-tree" "git commit-tree HEAD^{tree} -m x"

# Jiraiya 36a0dce1 review (Sasuke): commands inside if/for/while/until/case/select, !, coproc and function bodies are
#   judged like the same command bare; a compound form whose reserved words do not pair up fails closed. The full
#   list is in scripts/test-hook-policy.py (jr4_cases).
judge cursor-shell block "compound: push in if" "if true; then git push; fi"
judge cursor-shell block "compound: push in for" "for i in 1; do git push; done"
judge cursor-shell block "compound: push in while" "while true; do git push; break; done"
judge cursor-shell block "compound: ! push" "! git push"
judge cursor-shell block "compound: coproc push" "coproc git push"
judge cursor-shell block "compound: gh in until" "until false; do gh pr create --fill; done"
judge cursor-shell block "compound: state write in a case arm" "case x in x) printf x > $S;; esac"
judge cursor-shell block "compound: onboard commit chain in if" "if true; then $G && git commit -F $M; fi"
judge cursor-shell block "compound: unbalanced, names git push" "if true; then echo git push"
judge cursor-shell ask "compound: unbalanced, nothing denied" "if true; then ls"
judge cursor-shell allow "compound: plain if" "if true; then ls; fi"
judge cursor-shell allow "compound: plain for" 'for f in *.md; do echo $f; done'
judge cursor-shell allow "compound: ! grep" "! grep -q x file"

# N3A (Sasuke; Sai's request with ec944f63, Kakashi's assignment): the gate ledger and the reopen grant are written only
#   by gate-checks.sh (the grant only by the person). The full list is in scripts/test-hook-policy.py (n3a_cases).
mkdir -p "$P/.git/agents-v0"
printf 'FAIL onboard x\n' > "$P/.git/agents-v0/gate-ledger"
L=.git/agents-v0/gate-ledger
judge cursor-shell block "N3A: append to the gate ledger" "printf x >> $L"
judge cursor-shell block "N3A: cut the gate ledger" "sed -i '\$d' $L"
judge cursor-shell block "N3A: write the reopen grant" "printf x > .git/agents-v0/reopen-grant"
# Iruka and Jiraiya (on 2e1f6629): appending is the main attack, so every append form, for both files, and inside
#   $( ), ( ), { } and if bodies.
G=.git/agents-v0/reopen-grant
for f in "$L" "$G"; do
  b=${f##*/}
  judge cursor-shell block "N3A append: printf >> $b" "printf x >> $f"
  judge cursor-shell block "N3A append: echo >> $b" "echo x >> $f"
  judge cursor-shell block "N3A append: cat x >> $b" "cat /tmp/x >> $f"
  judge cursor-shell block "N3A append: cat >> $b (stdin)" "cat >> $f"
  judge cursor-shell block "N3A append: fd 1>> $b" "printf x 1>>$f"
  judge cursor-shell block "N3A append: tee -a $b" "printf x | tee -a $f"
  judge cursor-shell block "N3A append: tee --append $b" "printf x | tee --append $f"
  judge cursor-shell block "N3A append: in \$( ) $b" "y=\$(printf x >> $f)"
  judge cursor-shell block "N3A append: in ( ) $b" "( echo x >> $f )"
  judge cursor-shell block "N3A append: in { } $b" "{ cat /tmp/x >> $f; }"
  judge cursor-shell block "N3A append: in if $b" "if true; then printf x | tee -a $f; fi"
  judge agy-shell block "N3A append: unattended >> $b" "printf x >> $f" "$UA"
done
judge cursor-shell block "N3A append: case variant" "printf x >> .GIT/Agents-V0/Reopen-Grant"
judge cursor-shell block "N3A append: worktrees form" "echo x >> .git/worktrees/wt1/agents-v0/gate-ledger"
judge cursor-shell block "N3A: move the agents-v0 folder" "mv .git/agents-v0 /tmp/x"
judge cursor-shell block "N3A: case variant" "printf x > .GIT/AGENTS-V0/GATE-LEDGER"
judge cursor-shell block "N3A: run-time target" 'printf x >> "$(git rev-parse --git-path agents-v0/gate-ledger)"'
judge cursor-shell block "N3A: inside if" "if true; then : > $L; fi"
judge agy-shell block "N3A: unattended rm" "rm $L" "$UA"
judge cursor-edit block "N3A: edit tool on the ledger" "$L"
judge cursor-shell allow "N3A: read the ledger" "cat $L"
judge cursor-shell allow "N3A: copy the ledger out" "cp $L /tmp/ledger-copy"
judge cursor-shell block "N3A: folder swap, mv onto it" "mv /tmp/d .git/agents-v0"
judge cursor-shell block "N3A: folder swap, ln -s onto it" "ln -sfn /tmp/d .git/agents-v0"
judge cursor-shell block "N3A: folder swap, cp -r onto it" "cp -r /tmp/d .git/agents-v0"
judge cursor-shell block "N3A: folder swap, worktrees form" "mv /tmp/d .git/worktrees/wt1/agents-v0"
# N3B (Kakashi, Jiraiya 2026-11-02): find that deletes, a hard link then an append, git init --separate-git-dir.
judge cursor-shell block "N3B: find -exec rm on the ledger folder" "find .git/agents-v0 -exec rm {} +"
judge cursor-shell block "N3B: hard link, then append" "cp -l $L ./l && echo forged >> ./l"
judge cursor-shell block "N3B: git init --separate-git-dir" "git init --separate-git-dir=/tmp/g"

if [ "$fail" = 0 ]; then printf 'test-state-json-guard: OK (%s cases)\n' "$n"; exit 0; fi
printf 'test-state-json-guard: FAILED\n' >&2
exit 1
