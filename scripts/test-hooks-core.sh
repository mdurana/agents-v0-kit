#!/bin/sh
# test-hooks-core.sh: the tier 1 hook cases (Sensei 2026-11-02 08:44 Manila, option C: "Tier 1 limit C stands:
# keep 600s, keep the hook-policy, state guard and agy hook cases in tier 1, move the rest of test-hooks.sh to
# tier 2"). The rest of test-hooks.sh runs in tier 2 (scripts/tier2.sh); test-hook-policy.py and
# test-state-json-guard.sh stay in tier 1 as they were (validate-kit.sh).
# Every case runs through a real installed hook entry point, never hook-policy.py directly: install.sh into a
# temp git repo (--with-antigravity, so both .cursor/ and .agents/ are installed), then the exact command line from that install's .cursor/hooks.json (beforeShellExecution) or
# .agents/hooks.json (run_command, edit_file|write_file), started in the project folder. Group A runs each case
# twice, with sh and with dash in place of /bin/sh (as test-hooks.sh ran them); group B runs the installed line
# exactly as written (/bin/sh), once per case. Group A: the agy hook cases (moved from test-hooks.sh, same payloads and
# verdicts). Group B: a smoke set for the gate ledger and the reopen grant through pre-shell.sh, both flavors.
# TODO(untrusted-root): add the .git/agents-v0/untrusted-root marker smoke case here when Sasuke's
# .git/agents-v0/ hook commit lands; today the hook allows mv/rm of that marker, so a case would fail.
# Offline, no agent; the commands are judged, never run. Temp folder: this run's own (tier1-harness.sh).
set -eu
export PYTHONDONTWRITEBYTECODE=1
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-harness.sh"
command -v python3 >/dev/null 2>&1 || { fail "python3 not found"; t1_done test-hooks-core; }
SH1="$(command -v sh)"; SH2="$(command -v dash 2>/dev/null || command -v sh)"

P="$(t1_repo proj)"
if t1_install "$P" --with-antigravity; then pass "install.sh --with-antigravity into an empty temp repo"; else fail "install.sh --with-antigravity into an empty temp repo"; t1_done test-hooks-core; fi
# An onboarded project (commit plus an onboard-v tag), so the agy cases get the verdicts test-hooks.sh gave them;
# with onboarding in progress the hook refuses every commit but the onboard gate commit (hook-policy.py, onboard-v).
G "$P" add -A && G "$P" commit -qm onboarded && G "$P" tag onboard-v1 || fail "onboard the temp project"
mkdir -p "$P/.git/agents-v0"; : > "$P/.git/agents-v0/gate-ledger"
# entry <installed hooks.json> <matcher or script>: the installed command line for that hook
entry() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
if "agents-v0-delivery" in d:
    for m in d["agents-v0-delivery"]["PreToolUse"]:
        if m["matcher"] == sys.argv[2]:
            print(m["hooks"][0]["command"]); break
else:
    for m in d["hooks"]["beforeShellExecution" if sys.argv[2] == "pre-shell.sh" else "preToolUse"]:
        if sys.argv[2] in m["command"]:
            print(m["command"]); break
' "$1" "$2"
}
CUR_SHELL="$(entry "$P/.cursor/hooks.json" pre-shell.sh)"
AGY_SHELL="$(entry "$P/.agents/hooks.json" run_command)"
AGY_EDIT="$(entry "$P/.agents/hooks.json" 'edit_file|write_file')"
case "$CUR_SHELL" in *KIT_HOOK_FLAVOR=cursor*" .cursor/hooks/pre-shell.sh") pass "installed Cursor entry runs .cursor/hooks/pre-shell.sh" ;; *) fail "installed Cursor shell entry not found ($CUR_SHELL)" ;; esac
case "$AGY_SHELL" in *KIT_HOOK_FLAVOR=antigravity*.agents/hooks/pre-shell.sh*) pass "installed agy entry runs .agents/hooks/pre-shell.sh" ;; *) fail "installed agy shell entry not found ($AGY_SHELL)" ;; esac
case "$AGY_EDIT" in *KIT_HOOK_FLAVOR=antigravity*.agents/hooks/pre-edit.sh*) pass "installed agy edit entry runs .agents/hooks/pre-edit.sh" ;; *) fail "installed agy edit entry not found ($AGY_EDIT)" ;; esac
for h in .cursor/hooks/pre-shell.sh .agents/hooks/pre-shell.sh .agents/hooks/pre-edit.sh; do
  cmp -s "$KIT/core/common/hooks/${h##*/}" "$P/$h" && pass "installed $h is the kit's wrapper" || fail "installed $h is the kit's wrapper"
done
[ -d "$P/docs/agents-v0" ] && pass "the install has docs/agents-v0 (the ledger rules apply)" || fail "the install has docs/agents-v0"

# judge <id> <entry> <payload> <want block|ask|allow|allow-json:<text>> <label> [VAR=value ...]
# Runs the entry once per shell in $J_SHELLS, with that shell in place of /bin/sh.
judge() {
  j_id="$1"; j_cmd="$2"; j_pay="$3"; j_want="$4"; j_lbl="$5"; shift 5
  for j_sh in $J_SHELLS; do
    j_line="$(printf '%s' "$j_cmd" | sed "s#/bin/sh#$j_sh#g")"
    set +e
    j_out="$(cd "$P" && printf '%s' "$j_pay" | env "$@" "$j_sh" -c "$j_line" 2>&1)"; j_rc=$?
    set -e
    j_tag="$j_id ${j_sh##*/}: $j_lbl"
    case "$j_want" in
      block) [ "$j_rc" = 2 ] && pass "$j_tag" || fail "$j_tag: expected block (rc=2), got rc=$j_rc ($j_out)" ;;
      ask) { [ "$j_rc" = 0 ] && printf '%s' "$j_out" | grep -Eq '"(permission|permissionDecision|decision)": "ask"'; } \
             && pass "$j_tag" || fail "$j_tag: expected ask, got rc=$j_rc ($j_out)" ;;
      allow) { [ "$j_rc" = 0 ] && ! printf '%s' "$j_out" | grep -Eq 'BLOCK:|"ask"|"deny"'; } \
             && pass "$j_tag" || fail "$j_tag: expected allow, got rc=$j_rc ($j_out)" ;;
      allow-json:*) { [ "$j_rc" = 0 ] && printf '%s' "$j_out" | grep -Fq "${j_want#allow-json:}"; } \
             && pass "$j_tag" || fail "$j_tag: expected rc=0 with ${j_want#allow-json:}, got rc=$j_rc ($j_out)" ;;
    esac
  done
}
js() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
agy_cmd() { printf '{"toolCall":{"name":"run_command","args":{"CommandLine":%s}}}' "$(js "$1")"; }
agy_cmd_cwd() { printf '{"toolCall":{"name":"run_command","args":{"CommandLine":%s,"Cwd":%s}}}' "$(js "$1")" "$(js "$P")"; }
cur_cmd() { printf '{"command":%s,"cwd":%s}' "$(js "$1")" "$(js "$P")"; }

J_SHELLS="$SH1 $SH2"
# ---- Group A: the agy hook cases (were test-hooks.sh:66-69, 71-82, 88-90, and the agy half of 92-99) ----
judge A1 "$AGY_SHELL" "$(agy_cmd 'git push origin main --force')" block "agy git push --force"
judge A2 "$AGY_SHELL" "$(agy_cmd 'git commit -m x')" ask "agy git commit"
judge A3 "$AGY_SHELL" "$(agy_cmd 'echo x > .agents/hooks.json')" block "agy write .agents/hooks.json"
judge A4 "$AGY_SHELL" "$(agy_cmd 'ls')" allow "agy ls"
judge A5 "$AGY_SHELL" "$(agy_cmd 'git commit -m x')" block "agy unattended AGY_ALLOW_TOOLS=- denies git commit" AGY_ALLOW_TOOLS=-
judge A6 "$AGY_SHELL" "$(agy_cmd 'git commit -m x')" 'allow-json:"decision": "allow"' "agy unattended Shell(git:commit*) allows git commit" 'AGY_ALLOW_TOOLS=Shell(git:commit*)'
judge A7 "$AGY_EDIT" '{"toolCall":{"name":"edit_file","args":{"Path":".agents/hooks.json"}}}' block "agy edit .agents/hooks.json"
judge A8 "$AGY_EDIT" '{"toolCall":{"name":"write_file","args":{"Path":".agents/skills/v0-build/SKILL.md"}}}' block "agy write .agents/skills"
judge A9 "$AGY_EDIT" '{"toolCall":{"name":"edit_file","args":{"Path":"src/Main.java"}}}' allow "agy edit src"
judge A10 "$AGY_EDIT" '{"toolCall":{"name":"edit_file","args":{"Path":"src/Main.java"}}}' 'allow-json:"decision": "allow"' "agy pre-edit prints explicit allow JSON"

# ---- Group B: gate ledger and reopen grant smoke, through pre-shell.sh (Cursor and agy entries) ----
J_SHELLS=/bin/sh
L=.git/agents-v0/gate-ledger; R=.git/agents-v0/reopen-grant
judge B1 "$CUR_SHELL" "$(cur_cmd "printf x >> $L")" block "cursor append to the gate ledger"
judge B2 "$AGY_SHELL" "$(agy_cmd_cwd "printf x >> $L")" block "agy append to the gate ledger"
judge B3 "$CUR_SHELL" "$(cur_cmd "rm -f $L")" block "cursor remove the gate ledger"
judge B4 "$AGY_SHELL" "$(agy_cmd_cwd 'printf x >> "$(git rev-parse --git-path agents-v0/gate-ledger)"')" block "agy unattended append through git rev-parse" 'AGY_ALLOW_TOOLS=Shell(*),Shell(printf:*)'
judge B5 "$CUR_SHELL" "$(cur_cmd "printf x > $R")" block "cursor write the reopen grant"
judge B6 "$AGY_SHELL" "$(agy_cmd_cwd "printf x > $R")" block "agy write the reopen grant"
judge B7 "$CUR_SHELL" "$(cur_cmd "mv $R /tmp/x")" block "cursor move the reopen grant"
judge B8 "$CUR_SHELL" "$(cur_cmd 'mv .git/agents-v0 /tmp/x')" block "cursor move the folder that holds them"
judge B9 "$CUR_SHELL" "$(cur_cmd "cat $L")" allow "control: cursor read the gate ledger"
judge B10 "$AGY_SHELL" "$(agy_cmd_cwd 'printf x > notes/gate-ledger.md')" allow "control: agy write a look-alike name"
# TODO(untrusted-root): B11 cursor `mv .git/agents-v0/untrusted-root /tmp/x` block, when Sasuke's commit lands.

t1_done test-hooks-core
