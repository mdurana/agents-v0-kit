#!/usr/bin/env bash
# triage.sh --test-root <dir>
# First, script-made classification of the failure that stopped a run (fix-and-resume.md §3). Reads only; writes
# results/triage.tsv and results/triage.md. Classes:
#   ENV          box/tools/account problem: preflight or prerequisites failed, usage limit, sign-in, network, stall
#   HARNESS      the test scripts or fixtures are wrong: runner crash, restore/snapshot error, unknown gate in the fixtures
#   KIT          a kit script fails on valid input, or the same check failed again after an agent retry (confirmed)
#   KIT-OR-AGENT a behaviour check failed once; confirm with one agent retry (--reason agent-retry) before fixing the kit
#   EXPECTED     the failure is a known kit gap listed in test-plan.md §9; record it, do not fix it in this run
# The operator confirms the class with the evidence named in each row (rule table in fix-and-resume.md §3).
set -u
TR=""; while [ $# -gt 0 ]; do case "$1" in --test-root) TR="$2"; shift 2;; *) echo "unknown argument $1" >&2; exit 2;; esac; done
R="$TR/results"; E="$TR/evidence"; S="$TR/status"; [ -f "$R/results.tsv" ] || { echo "triage: $R/results.tsv not found" >&2; exit 2; }
out="$R/triage.tsv"; : > "$out"
row(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$out"; }   # step scenario/check class evidence reason next-action
step="$(awk -F'\t' '$1 ~ /^step-/ && ($3=="FAIL"||$3=="HALT"){sub("step-","",$1); print $1; exit}' "$R/results.tsv")"
[ -n "$step" ] || { echo "triage: no FAIL or HALT step in results.tsv; nothing to triage"; exit 0; }
log="$(ls "$S"/*.log 2>/dev/null | head -1)"; con="$S/runner-console.log"
# 1 halts and environment
if [ -f "$TR/HALT" ]; then row "$step" HALT ENV "$TR/HALT" "$(cat "$TR/HALT")" "fix the account/limit, then --reason env-fix"; fi
case "$step" in 0|1) row "$step" "-" ENV "$R/prereqs-after.txt" "preflight or prerequisites failed" "fix the box (prereqs.sh --install or a human step), then --reason env-fix";; esac
for t in "$E"/S"$step"-*; do [ -d "$t" ] && [ -f "$t/turns.tsv" ] || continue
  last="$(tail -1 "$t/turns.tsv" | sed 's/.*class=//')"
  case "$last" in STALL|INFRA) row "$step" "${t##*/}" ENV "$t/turns.tsv" "last turn class $last (no output, network or service error)" "check network/service, then --reason env-fix";;
                  USAGE|AUTH) row "$step" "${t##*/}" ENV "$t/turn-*.stderr" "last turn class $last" "--reason env-fix after the limit resets / sign-in is fixed";; esac
done
# 2 harness
[ -n "$log" ] && grep -hE 'RESTORE-FAIL|KIT-UPDATE-FAIL' "$S"/*.log 2>/dev/null | tail -3 | while IFS= read -r l; do
  row "$step" "-" HARNESS "$S/ and $R/kit-update.log" "$l" "a restore failure is HARNESS; a KIT-UPDATE-FAIL whose kit-update.log shows install.sh/validate-kit refusing valid input is KIT"; done
[ -f "$con" ] && grep -nE 'line [0-9]+: .*(syntax error|unbound variable|command not found)|Traceback' "$con" | tail -3 | while IFS= read -r l; do
  row "$step" "-" HARNESS "$con" "$l" "fix scripts/ in the plan folder, then --reason harness-fix"; done
# 3 kit scripts failing (agent ran a kit script that errored on valid input)
for f in "$E"/S"$step"-*/final-*.md; do [ -f "$f" ] || continue
  grep -qE '\.agents-v0/scripts/[a-z-]+\.(sh|py)' "$f" && grep -qiE '(script|\.sh|\.py)[^.]*(failed|error|crash|traceback|not found|no such file|bad substitution|unbound)' "$f" &&
    row "$step" "${f%/*}" KIT "$f" "the agent reports a kit script error: $(grep -oE '\.agents-v0/scripts/[a-z-]+\.(sh|py)' "$f" | sort -u | tr '\n' ' ')" "re-run that script by hand on the evidence workspace; if the input is valid it is a kit defect -> kit-fix.sh"
done
ls "$E"/S"$step"-*.stuck >/dev/null 2>&1 && for f in "$E"/S"$step"-*.stuck; do
  row "$step" "${f##*/}" KIT-OR-AGENT "$f" "story did not progress: $(cat "$f")" "read the last final-*.md; a gate the fixtures do not know is HARNESS, a kit command that does not reach its gate is KIT-OR-AGENT"; done
grep -h 'GATE-HELD\|end=GATE-HELD' "$R/results.tsv" 2>/dev/null | awk -F'\t' -v s="$step" 'index($1,s".")==1' | while IFS=$'\t' read -r id d r t note k; do
  row "$step" "$id" HARNESS "$note" "a gate was reached that this scenario does not approve" "check approvals.tsv / the scenario's allowed gates against the kit command text"; done
# 4 failed checks
awk -F'\t' -v s="$step" '$2==s && $5=="FAIL"{print $3"\t"$4"\t"$6}' "$R/checks.tsv" | sort -u | while IFS=$'\t' read -r sc id d; do
  cls=KIT-OR-AGENT; why="check failed once"; nxt="one agent retry: run-plan.sh --resume-from $step --reason agent-retry"
  [ "$sc" = - ] || nxt="one agent retry: run-plan.sh --resume-from $step.$sc --reason agent-retry (step 7/8) or --resume-from $step"
  case "$d" in *check-release-evidence*|*check-story-dependencies*|*check-database-runtime*|*gate.sh*) cls=EXPECTED; why="names a script test-plan.md §9 lists as missing on some refs"; nxt="record; no fix in this run";; esac
  for a in "$R"/attempt-*/checks.tsv; do [ -f "$a" ] || continue
    if awk -F'\t' -v s="$step" -v i="$id" -v c="$sc" '$2==s && $3==c && $4==i && $5=="FAIL"' "$a" | grep -q . &&
       awk -F'\t' -v s="$step" '$3==s && $4=="agent-retry"' "$R/fix-attempts.tsv" 2>/dev/null | grep -q .; then
      [ "$cls" = EXPECTED ] || { cls=KIT; why="same check failed before and after an agent retry"; nxt="kit-fix.sh start --step $step"; }; fi; done
  case "$id" in X3|E4|H5|M5) [ "$cls" = KIT-OR-AGENT ] && why="$why; agent ran an approval or forbidden command (the kit enforces this by instructions only, test-plan.md §9)";; esac
  row "$step" "$sc/$id" "$cls" "$R/checks.tsv" "$d: $why" "$nxt"
done
[ -s "$out" ] || row "$step" "-" KIT-OR-AGENT "$R/summary.md" "step failed with no failed check and no other signal" "read the step's evidence; classify by hand with fix-and-resume.md §3"
{ echo "# Triage of $TR (step $step)"; echo; echo "Written $(TZ=Asia/Manila date '+%Y-%m-%d %H:%M') Asia/Manila by scripts/triage.sh. The operator confirms each class (fix-and-resume.md §3)."; echo
  echo "| Step | Item | Class | Evidence | Reason | Next action |"; echo "|---|---|---|---|---|---|"
  sed 's/|/\\|/g; s/\t/ | /g; s/^/| /; s/$/ |/' "$out"
  echo; echo "Overall: $(cut -f3 "$out" | sort | uniq -c | awk '{printf "%s %s; ",$2,$1}')"
  echo "Priority when rows disagree: ENV > HARNESS > EXPECTED > KIT > KIT-OR-AGENT (fix the outermost cause first)."; } > "$R/triage.md"
cat "$R/triage.md"
