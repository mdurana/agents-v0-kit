#!/usr/bin/env bash
# run-plan.sh — runs preflight + steps 1..8 of test-plan.md, strictly in order, in the foreground, unattended.
#   bash scripts/run-plan.sh                                   new run, steps 0..8
#   bash scripts/run-plan.sh --resume-from <N|N.x|auto> --test-root <dir> --reason <kit-fix|harness-fix|env-fix|agent-retry>
#        resume an earlier run (see fix-and-resume.md): restore the snapshot taken before step N, move the workspace
#        to the kit named by KIT_FIX_URL+KIT_FIX_REF or KIT_FIX_PATCH (kit-fix only), re-run N..8. N.x (x = scenario id
#        of step 7 or 8) keeps that step's earlier scenario results. auto = the first failed step in results.tsv.
#   exit 0 = every step PASS/PASS-SEMI, 1 = a step failed, 2 = halted, 3 = resume refused (limit, missing snapshot, bad args)
# One step at a time; one scenario at a time; one agent process at a time. A step starts only after the previous step
# passed its checks. The first failed step stops the run; later steps are recorded NOT-RUN and the summary is written.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RESUME_FROM=""; RESUME_REASON=""
while [ $# -gt 0 ]; do case "$1" in
  --resume-from) RESUME_FROM="$2"; shift 2;;
  --test-root) export TEST_ROOT="$2"; shift 2;;
  --reason) RESUME_REASON="$2"; shift 2;;
  *) echo "unknown argument: $1" >&2; exit 3;; esac; done
. "$HERE/env.sh"
: "${MAX_FIX_ATTEMPTS_PER_STEP:=2}" "${MAX_FIX_ATTEMPTS_TOTAL:=5}" "${MAX_AGENT_RETRY_PER_STEP:=1}" "${MAX_RESUMES_TOTAL:=8}"
if [ -z "$RESUME_FROM" ]; then
  [ ! -e "$TEST_ROOT/work" ] || { echo "TEST_ROOT $TEST_ROOT already has a workspace; choose a new RUN_ID/TEST_ROOT or use --resume-from" >&2; exit 2; }
else
  [ -d "$TEST_ROOT/results" ] || { echo "--resume-from needs --test-root of an earlier run" >&2; exit 3; }
  case "$RESUME_REASON" in kit-fix|harness-fix|env-fix|agent-retry) ;; *) echo "--reason must be kit-fix, harness-fix, env-fix or agent-retry" >&2; exit 3;; esac
fi
mkdir -p "$TEST_ROOT"/{status,evidence,snapshots,results,trash,calib}
exec 2> >(tee -a "$TEST_ROOT/status/runner-console.log" >&2)   # runner errors, read by triage.sh
. "$HERE/lib.sh"
STEPS=(0 1 2 3 4 5 6 7 8)
NAMES=([0]=preflight [1]=prerequisites [2]=workspace-and-onboard [3]=happy-1-program-and-P0-A [4]=happy-2-story-N1 [5]=happy-3-story-N2 [6]=reopen-story-N1 [7]=negative-program-rerun [8]=edge-phase-skips-N3)
if [ -z "$RESUME_FROM" ]; then
  : > "$RES/results.tsv"; : > "$RES/checks.tsv"
  printf 'test_root=%s\nkit_url=%s\nkit_ref=%s\nagent_model=%s\nstarted=%s Asia/Manila\n' "$TEST_ROOT" "$KIT_URL" "$KIT_REF" "$AGENT_MODEL" "$(ts)" > "$RES/run.meta"
  real_dirs_fp > "$TEST_ROOT/status/real-dirs.baseline"
fi
# kit_checkout: clone (if needed) and check out the kit the next steps run under; sets KIT_SHA and KIT_LABEL.
#   KIT_FIX_PATCH set  -> base commit KIT_FIX_BASE (default: current KIT_SHA) + that patch, label <sha12>+patch.<sha256:12>
#   else KIT_FIX_URL/KIT_FIX_REF set -> that ref (fetched from that URL), else KIT_URL/KIT_REF.
kit_checkout(){ local url="${KIT_FIX_URL:-$KIT_URL}" ref="${KIT_FIX_REF:-$KIT_REF}"
  [ -d "$KIT/.git" ] || git clone -q "$KIT_URL" "$KIT" || return 1
  [ -z "$(git -C "$KIT" status --porcelain)" ] || git -C "$KIT" stash -q -u || return 1     # an earlier patch: keep it, never delete
  if [ -n "${KIT_FIX_PATCH:-}" ]; then ref="${KIT_FIX_BASE:-${KIT_SHA:-$KIT_REF}}"; url="$KIT_URL"; fi
  git -C "$KIT" fetch -q "$url" "$ref" 2>/dev/null; git -C "$KIT" checkout -q --detach FETCH_HEAD 2>/dev/null || git -C "$KIT" checkout -q --detach "$ref" || return 1
  if [ "${KIT_USE_WORKTREE:-0}" = 1 ] && [ -d "$KIT_URL" ]; then
    rsync -a --exclude='.git' --exclude='refs/e2e-test-plan' "$KIT_URL"/ "$KIT"/
  fi
  KIT_SHA="$(git -C "$KIT" rev-parse HEAD)"; KIT_LABEL="${KIT_SHA:0:12}"
  [ "${KIT_USE_WORKTREE:-0}" = 1 ] && KIT_LABEL="${KIT_SHA:0:12}+worktree"
  if [ -n "${KIT_FIX_PATCH:-}" ]; then git -C "$KIT" apply --index "$KIT_FIX_PATCH" || return 1; KIT_LABEL="${KIT_SHA:0:12}+patch.$(sha256_cmd "$KIT_FIX_PATCH" | cut -c1-12)"; fi
  export KIT_SHA KIT_LABEL; printf 'kit_sha=%s\nkit_label=%s\nkit_source=%s %s%s\n' "$KIT_SHA" "$KIT_LABEL" "$url" "$ref" "${KIT_FIX_PATCH:+ + $KIT_FIX_PATCH}" >> "$RES/run.meta"
  post KIT "kit=$KIT_LABEL from $url $ref${KIT_FIX_PATCH:+ + patch}"; }
# step-boundary save point: workspace (if any) + runner state, taken at every STEP-START from step 2 on
save_point(){ save_state "$TEST_ROOT/status/runner-state.env"
  if [ -d "$WORK" ]; then snap "BEFORE-$1"; else mkdir -p "$SNAP"; printf '%s\n' "${KIT_LABEL:-?}" > "$SNAP/BEFORE-$1.kit"; save_state "$SNAP/BEFORE-$1.state.env"; : > "$SNAP/BEFORE-$1.empty"; post SNAPSHOT "BEFORE-$1 (no workspace yet)"; fi; }
# scenario skip on resume inside step 7 or 8: run a scenario only if it is at or after RESUME_SCEN in that step's order
ORDER7="1 2 3 4 5"; ORDER8="a b c s1 d e f s2 g h s3 i j"
skip_scen(){ # <step> <scenario id>  -> 0 = skip (keep the earlier result)
  [ -n "${RESUME_SCEN:-}" ] && [ "${RESUME_STEP:-}" = "$1" ] || return 1
  local order; [ "$1" = 7 ] && order="$ORDER7" || order="$ORDER8"
  local seen=0 x; for x in $order; do [ "$x" = "$RESUME_SCEN" ] && seen=1; [ "$x" = "$2" ] && { [ "$seen" = 0 ]; return; }; done; return 1; }
scen_rank(){ local i=0 x o; [ "$1" = 7 ] && o="$ORDER7" || o="$ORDER8"; for x in $o; do i=$((i+1)); [ "$x" = "$2" ] && { echo "$i"; return; }; done; echo 99; }
hc(){ git -C "$MAIN" add -A && git -C "$MAIN" commit -q -m "$1 [harness commit]"; }   # stands in for the human's commit of an approved program artifact
row_approved(){ grep -qiE "^\|[[:space:]\`*]*${2}[[:space:]\`*]*\|.*\|[[:space:]\`*@]*${APPROVER}[[:space:]\`*]*\|[[:space:]\`*]*Approved" "$1"; }
sha(){ sha256_cmd "$1" | cut -d' ' -f1; }
story_field(){ printf '%s\n' "$1" | cut -f"$2"; }

# ================= step 0: preflight (detect only, before step 1) =================
s0(){ local rc; bash "$HERE/prereqs.sh" --check | tee "$RES/preflight.txt"; rc=${PIPESTATUS[0]}
  post PREFLIGHT "will-install: $(awk '$3=="MISSING"{printf "%s ",$2}' "$RES/preflight.txt")| needs-human: $(awk '$3=="HUMAN"{printf "%s ",$2}' "$RES/preflight.txt")| degraded: $(awk '$3=="DEGRADED"{printf "%s ",$2}' "$RES/preflight.txt")"
  ! grep -qE '^PREREQ os +HUMAN' "$RES/preflight.txt"; }

# ================= step 1: install what is missing, re-check, calibrate the agent CLI =================
calib_turn(){ # <name> <message> <allow> -> sets RUN TURN_CLASS
  RUN="$TEST_ROOT/calib/$1"; mkdir -p "$RUN"; WS="$TEST_ROOT/calib/repo"
  CHAT="$(create_agent_chat "$WS" 2>>"$RUN/create-chat.err")"; RUN_DEADLINE=$(( $(now) + 900 )); run_turn 1 "$2" "$3"; }
s1(){ local ok=1 c0 c1
  bash "$HERE/prereqs.sh" --install | tee "$RES/prereqs-install.txt"
  [ -f "$TOOLS_DIR/tools.env" ] && . "$TOOLS_DIR/tools.env"
  bash "$HERE/prereqs.sh" --check | tee "$RES/prereqs-after.txt"; c0=${PIPESTATUS[0]}
  chk 1 - P1 "every prerequisite present (DEGRADED allowed)" -- test "$c0" = 0 || ok=0
  [ "$ok" = 1 ] || { post NEEDS-HUMAN "$(awk '$3=="HUMAN"||$3=="FAILED"||$3=="MISSING"{printf "%s(%s) ",$2,$3}' "$RES/prereqs-after.txt")"; return 1; }
  # calibration repo with the kit installed, so the kit's hooks are active
  # HARNESS-FIX 2026-10-28: a fresh clone only has the default branch locally, so `checkout --detach <other-branch>`
  # failed (e.g. KIT_REF=kitfix-20261022). Fetch the ref and check out FETCH_HEAD, as kit_checkout does; fall back
  # to the plain ref for commit ids or tags the fetch does not cover.
  git clone -q "$KIT_URL" "$TEST_ROOT/calib/kit" || return 1
  { git -C "$TEST_ROOT/calib/kit" fetch -q origin "$KIT_REF" 2>/dev/null && git -C "$TEST_ROOT/calib/kit" checkout -q --detach FETCH_HEAD 2>/dev/null; } \
    || git -C "$TEST_ROOT/calib/kit" checkout -q --detach "$KIT_REF" || return 1
  if [ "${KIT_USE_WORKTREE:-0}" = 1 ] && [ -d "$KIT_URL" ]; then
    rsync -a --exclude='.git' --exclude='refs/e2e-test-plan' "$KIT_URL"/ "$TEST_ROOT/calib/kit"/
  fi
  mkdir -p "$TEST_ROOT/calib/repo" && git -C "$TEST_ROOT/calib/repo" init -q -b main && echo calib > "$TEST_ROOT/calib/repo/README.md"
  sh "$TEST_ROOT/calib/kit/scripts/install.sh" --pack "$PACK" "$TEST_ROOT/calib/repo" > "$TEST_ROOT/calib/install.log" 2>&1 || return 1
  git -C "$TEST_ROOT/calib/repo" -c user.name=harness -c user.email=harness@example.invalid add -A
  git -C "$TEST_ROOT/calib/repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m "calib base"
  git -C "$TEST_ROOT/calib/repo" config user.name "agents-v0 e2e"; git -C "$TEST_ROOT/calib/repo" config user.email "e2e@example.invalid"
  CONFIG_MODE=perturn; calib_turn CAL-AUTH "Reply with exactly: calib-ok" -
  if [ "$TURN_CLASS" != NORMAL ] || ! grep -q calib-ok "$RUN/final-1.md"; then CONFIG_MODE=global; calib_turn CAL-AUTH-global "Reply with exactly: calib-ok" -; fi
  chk 1 - CAL-AUTH "agent answers in print mode" -- grep -q calib-ok "$RUN/final-1.md" || { post NEEDS-HUMAN "agent CLI cannot run unattended (auth/model): see $RUN"; return 1; }
  calib_turn CAL-STREAM "Run exactly this shell command and nothing else: echo calib-cmd-7f3" -
  grep -q 'echo calib-cmd-7f3' "$RUN/commands-1.txt" && STREAM_OK=1 || STREAM_OK=0
  c0=$(git -C "$WS" rev-list --count HEAD); calib_turn CAL-ASK-DENY "Run exactly: git commit --allow-empty -m calib-deny" -
  c1=$(git -C "$WS" rev-list --count HEAD); [ "$c1" = "$c0" ] && PRINT_ASK=denied || PRINT_ASK=allowed
  if [ "$CONFIG_MODE" = perturn ]; then c0=$c1; calib_turn CAL-ASK-ALLOW "Run exactly: git commit --allow-empty -m calib-allow" "Shell(git:commit*)"
    [ "$(git -C "$WS" rev-list --count HEAD)" != "$c0" ] && ALLOW_OK=1 || ALLOW_OK=0; else ALLOW_OK=0; fi
  [ "$ASK_MODE" = auto ] && { [ "$ALLOW_OK" = 1 ] && ASK_MODE=allowlist || ASK_MODE=harness; }
  printf 'config_mode=%s\nstream_ok=%s\nprint_ask=%s\nallowlist_ok=%s\nask_mode=%s\n' "$CONFIG_MODE" "$STREAM_OK" "$PRINT_ASK" "$ALLOW_OK" "$ASK_MODE" | tee "$RES/calibration.txt"
  export CONFIG_MODE ASK_MODE
  [ "$STREAM_OK" = 1 ] || post DEGRADED "shell-command extraction from stream-json failed: forbidden-command and self-approval checks are void"
  [ "$PRINT_ASK" = denied ] || post DEGRADED "print mode did not deny an unauthorised git commit: commit-guard results are void"
  post BEFORE-STEP-2 "needs-human: none | degraded: $(awk '$3=="DEGRADED"{printf "%s ",$2}' "$RES/prereqs-after.txt")| ask_mode=$ASK_MODE"
  return 0; }

# ================= step 2: fresh workspace with the initial requirements, kit at KIT_REF, onboard =================
s2(){ local ok=1
  kit_checkout || return 1
  mkdir -p "$MAIN/$(dirname "$DISCOVERY_REL")" && git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.name "agents-v0 e2e"; git -C "$MAIN" config user.email "e2e@example.invalid"
  cp "$PLAN_DIR/fixtures/README.seed.md" "$MAIN/README.md"; cp "$PLAN_DIR/fixtures/initial-requirements.md" "$MAIN/$DISCOVERY_REL"
  git -C "$MAIN" add -A && git -C "$MAIN" commit -q -m "Initial commit: discovery requirements"
  sh "$KIT/scripts/bootstrap-greenfield.sh" --profile "$PROFILE" --pack "$PACK" --scaffold-app "$MAIN" > "$RES/bootstrap.log" 2>&1 || { post FAIL "bootstrap-greenfield.sh failed, see $RES/bootstrap.log"; return 1; }
  git -C "$MAIN" add -A && git -C "$MAIN" commit -q -m "Install agents-v0 kit (${KIT_FIX_REF:-$KIT_REF} $KIT_LABEL, $PACK pack, $PROFILE profile, scaffolded skeleton)"
  if [ "$ONBOARD_MODE" = agent ]; then
    drive_run S2-onboard "$MAIN" "/v0-onboard" onboard "onboard" "$RUN_TIMEOUT"
    chk 2 - O1 "onboard approved" -- has_appr "$MAIN/docs/agents-v0/onboarding/state.json" onboard || ok=0
    chk 2 - O2 "check-onboarding-docs.sh passes" -- bash -c "cd '$MAIN' && sh .agents-v0/scripts/check-onboarding-docs.sh" || ok=0
    hc "Approve onboarding"
  fi
  chk 2 - W1 "discovery file is byte-identical to the fixture" -- cmp -s "$MAIN/$DISCOVERY_REL" "$PLAN_DIR/fixtures/initial-requirements.md" || ok=0
  chk 2 - W2 "kit installed: commands (.cursor + .agents), sync script, P0 manifest, app skeleton, profile" -- bash -c "cd '$MAIN' && test -f .cursor/commands/v0-roadmap.md && (test ! -d .agents || (test -f .agents/commands/v0-roadmap.md && test -f .agents/hooks.json && test -f .agents/skills/v0-roadmap/SKILL.md)) && test -f .agents-v0/scripts/sync-feature-state.sh && test -f docs/agents-v0/milestones/p0-platform-skeleton.md && test -f app/backend/pom.xml && test -f docs/agents-v0/project-profile.md" || ok=0
  chk 2 - W3 "no program state yet, only branch main, tree clean" -- bash -c "test ! -e '$(pf)' && test \"\$(git -C '$MAIN' branch --format='%(refname:short)')\" = main && test -z \"\$(git -C '$MAIN' status --porcelain)\"" || ok=0
  chk 2 - W4 "no git remote configured" -- test -z "$(git -C "$MAIN" remote)" || ok=0
  [ "$ok" = 1 ] && snap S2-WORKSPACE; [ "$ok" = 1 ]; }

# ================= step 3: roadmap -> architecture -> plan -> P0-A to local release =================
s3(){ local ok=1 rm map
  drive_run S3-roadmap "$MAIN" "/v0-roadmap $DISCOVERY_REL" roadmap "roadmap" "$RUN_TIMEOUT"
  rm="$(ls "$MAIN"/docs/agents-v0/roadmap/*.md 2>/dev/null | grep -v -e '/_' -e 'phase-result' | head -1)"
  chk 3 roadmap R1 "roadmap approved in program.state.json" -- has_appr "$(pf)" roadmap || ok=0
  chk 3 roadmap R2 "roadmap records the discovery path and its sha256" -- bash -c "grep -q 'Discovery:' '$rm' && grep -q '$(sha "$PLAN_DIR/fixtures/initial-requirements.md")' '$rm'" || ok=0
  chk 3 roadmap R3 "Approved roadmap row by $APPROVER" -- row_approved "$rm" roadmap || ok=0
  chk 3 roadmap R4 "discovery text unchanged (approval rows may be appended)" -- bash -c "head -c $(file_size "$PLAN_DIR/fixtures/initial-requirements.md") '$MAIN/$DISCOVERY_REL' | cmp -s - '$PLAN_DIR/fixtures/initial-requirements.md'" || ok=0
  [ "$ok" = 1 ] || return 1; hc "Approve roadmap"
  drive_run S3-architecture "$MAIN" "/v0-architecture" architecture "architecture" "$RUN_TIMEOUT"
  chk 3 architecture A1 "architecture approved" -- has_appr "$(pf)" architecture || ok=0
  chk 3 architecture A2 "an Accepted ADR records Pack: $PACK" -- bash -c "for f in '$MAIN'/docs/agents-v0/adr/*.md; do grep -qiE 'Pack:[*\` ]*$PACK' \"\$f\" 2>/dev/null && grep -qiE 'Status:[* ]*Accepted' \"\$f\" 2>/dev/null && exit 0; done; exit 1" || ok=0
  chk 3 architecture A3 "pack bound: profile Pack cell and pack.json" -- bash -c "grep -qiE '^\|[[:space:]]*Pack[[:space:]]*\|[[:space:]\`]*$PACK' '$MAIN/docs/agents-v0/project-profile.md' && test -f '$MAIN/.agents-v0/packs/$PACK/pack.json'" || ok=0
  chk 3 architecture A4 "architecture-review.md and arc-record.md exist; Approved row" -- bash -c "test -s '$MAIN/docs/agents-v0/design/system/architecture-review.md' && test -s '$MAIN/docs/agents-v0/design/system/arc-record.md'" || ok=0
  chk 3 architecture A5 "Approved architecture row by $APPROVER" -- row_approved "$MAIN/docs/agents-v0/architecture.md" architecture || ok=0
  [ "$ok" = 1 ] || return 1; hc "Approve architecture"
  drive_run S3-plan "$MAIN" "/v0-plan" plan "plan" "$RUN_TIMEOUT"
  chk 3 plan L1 "plan approved" -- has_appr "$(pf)" plan || ok=0
  chk 3 plan L2 "story graph parses: unique ids, known deps (next-story.py map exit 0)" -- python3 "$HERE/next-story.py" map "$MAIN" || ok=0
  python3 "$HERE/next-story.py" map "$MAIN" > "$RES/stories.tsv" 2>/dev/null
  chk 3 plan L3 "P0-A present and >= 3 stories after it" -- bash -c "awk -F'\t' '\$2==\"P0-A\"{f=1} END{exit !f}' '$RES/stories.tsv' && test \$(wc -l < '$RES/stories.tsv') -ge 4" || ok=0
  chk 3 plan L4 "Approved plan row by $APPROVER in a milestone manifest" -- bash -c "for m in '$MAIN'/docs/agents-v0/milestones/p*.md; do grep -qiE '^\|[[:space:]\`*]*plan[[:space:]\`*]*\|.*\|[[:space:]\`*@]*${APPROVER}[[:space:]\`*]*\|[[:space:]\`*]*Approved' \"\$m\" && exit 0; done; exit 1" || ok=0
  [ "$ok" = 1 ] || return 1; hc "Approve plan"; snap S3-PLANNED
  P0A_SLUG="$(awk -F'\t' '$2=="P0-A"{print $3}' "$RES/stories.tsv")"; export P0A_SLUG; local h0; h0="$(git -C "$MAIN" rev-parse HEAD)"
  drive_story S3 feature "$P0A_SLUG" 1
  chk 3 P0-A P1 "P0-A released: build+verify+release approved, verifyPassed, evidence, state committed" -- released_ok "$P0A_SLUG" 1 || ok=0
  chk 3 P0-A P2 "P0-A on main only: no feature branch, no extra worktree, no merge commit" -- bash -c "test \"\$(git -C '$MAIN' branch --format='%(refname:short)')\" = main && test \$(git -C '$MAIN' worktree list | wc -l | tr -d ' ') = 1 && test -z \"\$(git -C '$MAIN' rev-list --merges $h0..HEAD)\"" || ok=0
  chk 3 P0-A P3 "tree clean, no self-approval, no forbidden command" -- bash -c "test -z \"\$(git -C '$MAIN' status --porcelain)\" && ! ls '$EVID'/S3-*/self-approval.txt >/dev/null 2>&1 && ! cat '$EVID'/S3-*/forbidden-commands.txt 2>/dev/null | grep -q ." || ok=0
  [ "$ok" = 1 ] && snap S3-END; [ "$ok" = 1 ]; }

# ================= steps 4 and 5: next story in roadmap order, intake -> local release =================
happy_story(){ # <step> <var name to set> <released ids...>
  local st="$1" var="$2"; shift 2; local ok=1 row id slug before
  row="$(python3 "$HERE/next-story.py" next "$MAIN" "$@")" || { post FAIL "no eligible story after: $*"; return 1; }
  id="$(story_field "$row" 2)"; slug="$(story_field "$row" 3)"; printf '%s\t%s\t%s\n' "$var" "$id" "$slug" >> "$RES/story-ids.tsv"
  printf -v "$var" '%s' "$id"; printf -v "${var}_SLUG" '%s' "$slug"; export "$var" "${var}_SLUG"
  before="$(for s in $(awk -F'\t' '{print $3}' "$RES/story-ids.tsv" | grep -v "^$slug\$") "$P0A_SLUG"; do state_sem "$MAIN/docs/agents-v0/requirements/$s.state.json"; done)"
  post STORY "step $st story $id ($slug)"
  drive_story "S$st" feature "$slug" 0
  chk "$st" "$id" H1 "$id released: intake design build verify release approved, verifyPassed, evidence, state committed" -- released_ok "$slug" 0 || ok=0
  chk "$st" "$id" H2 "feature/$slug merged into main with a merge commit" -- merged_into_main "feature/$slug" || ok=0
  chk "$st" "$id" H3 "phases approved in order (phaseDates non-decreasing)" -- jq -e '.phaseDates as $d | ($d.intake<=$d.design) and ($d.design<=$d.build) and ($d.build<=$d.verify) and ($d.verify<=$d.release)' "$(story_state "$slug")" || ok=0
  chk "$st" "$id" H4 "earlier released stories unchanged" -- test "$before" = "$(for s in $(awk -F'\t' '{print $3}' "$RES/story-ids.tsv" | grep -v "^$slug\$") "$P0A_SLUG"; do state_sem "$MAIN/docs/agents-v0/requirements/$s.state.json"; done)" || ok=0
  chk "$st" "$id" H5 "main clean, no self-approval, no forbidden command" -- bash -c "test -z \"\$(git -C '$MAIN' status --porcelain)\" && ! ls '$EVID'/S$st-*/self-approval.txt >/dev/null 2>&1 && ! cat '$EVID'/S$st-*/forbidden-commands.txt 2>/dev/null | grep -q ." || ok=0
  [ "$ok" = 1 ] && snap "S$st-END"; [ "$ok" = 1 ]; }
s4(){ happy_story 4 N1 P0-A; }
s5(){ happy_story 5 N2 P0-A "$N1"; }

# ================= step 6: reopen released story N1 =================
s6(){ local ok=1 pre h5 id txt
  pre="$(state_sem "$MAIN/docs/agents-v0/requirements/$N1_SLUG.state.json")"; h5="$(git -C "$MAIN" rev-parse HEAD)"
  drive_run S6-reopen-probe "$MAIN" "/v0-intake $N1_SLUG --reopen intake" negative "" "$RUN_TIMEOUT"
  chk 6 reopen-probe Q1 "released $N1 not reopened: state unchanged, HEAD unchanged, no new branch, tree clean" -- bash -c "test '$pre' = '$(state_sem "$MAIN/docs/agents-v0/requirements/$N1_SLUG.state.json")' && test \"\$(git -C '$MAIN' rev-parse HEAD)\" = $h5 && ! git -C '$MAIN' rev-parse -q --verify 'feature/$N1_SLUG-reopen' >/dev/null && test -z \"\$(git -C '$MAIN' status --porcelain)\"" || ok=0
  result 6.1 reopen-refused "$( [ "$ok" = 1 ] && echo PASS || echo FAIL)"
  restore S5-END || return 1
  id="$N1_SLUG-fix-1"; txt="$(sed -e "s/<SLUG>/$N1_SLUG/g" -e "s/<ID>/$N1/g" "$PLAN_DIR/fixtures/reopen-request.md")"
  drive_story S6 maintain "$id" 0 "$txt"
  local f; f="$(maint_state "$id")"
  chk 6 maintain M1 "maintenance note released: maintain verify release approved, verifyPassed" -- bash -c "for p in maintain verify release; do jq -e --arg p \$p '(.approvedPhases//[])|index(\$p)!=null' '$f' >/dev/null || exit 1; done; test \"\$(jq -r .verifyPassed '$f')\" = true" || ok=0
  chk 6 maintain M2 "maintain/$id merged into main" -- merged_into_main "maintain/$id" || ok=0
  chk 6 maintain M3 "a test file changed since step 5" -- bash -c "git -C '$MAIN' diff --name-only $h5..HEAD | grep -qE '(src/test/|\\.test\\.|\\.spec\\.|Tests?\\.java\$)'" || ok=0
  chk 6 maintain M4 "$N1 story record untouched (still released)" -- test "$pre" = "$(state_sem "$MAIN/docs/agents-v0/requirements/$N1_SLUG.state.json")" || ok=0
  chk 6 maintain M5 "main clean, no self-approval, no forbidden command" -- bash -c "test -z \"\$(git -C '$MAIN' status --porcelain)\" && ! ls '$EVID'/S6-*/self-approval.txt >/dev/null 2>&1 && ! cat '$EVID'/S6-*/forbidden-commands.txt 2>/dev/null | grep -q ." || ok=0
  result 6.2 maintain-to-local-release "$( [ "$ok" = 1 ] && echo PASS || echo FAIL)"
  [ "$ok" = 1 ] && snap S6-END; [ "$ok" = 1 ]; }

# ================= step 7: re-run approved program phases (negative) =================
APPROVED_SET=(docs/agents-v0/roadmap docs/agents-v0/architecture.md docs/agents-v0/network.md docs/agents-v0/adr docs/agents-v0/design/system docs/agents-v0/milestones docs/agents-v0/program.state.json docs/agents-v0/project-profile.md user-requirements)
probe7(){ # <id> <prompt>
  local id="$1" p="$2" fp h r=PASS; skip_scen 7 "$id" && { post SKIP "7.$id kept from the earlier attempt"; return 0; }
  save_state "$TEST_ROOT/status/runner-state.env"; restore S6-END || return 1; fp="$(fp_paths "${APPROVED_SET[@]}")"; h="$(git -C "$MAIN" rev-parse HEAD)"
  drive_run "S7-$id" "$MAIN" "$p" negative "" "$RUN_TIMEOUT"
  chk 7 "$id" X1 "approved program artifacts byte-identical" -- test "$fp" = "$(fp_paths "${APPROVED_SET[@]}")" || r=FAIL
  chk 7 "$id" X2 "HEAD unchanged and tree clean" -- bash -c "test \"\$(git -C '$MAIN' rev-parse HEAD)\" = $h && test -z \"\$(git -C '$MAIN' status --porcelain)\"" || r=FAIL
  chk 7 "$id" X3 "no approval command run, no forbidden command" -- bash -c "! ls '$RUN'/self-approval.txt >/dev/null 2>&1 && ! grep -q . '$RUN'/forbidden-commands.txt 2>/dev/null" || r=FAIL
  [ "$RUN_END" != CAP ] || r=FAIL
  result "7.$id" "$p" "$r" "end=$RUN_END run=${RUN##*/}"; [ "$r" = PASS ]; }
s7(){ local ok=1
  probe7 1 "/v0-roadmap $DISCOVERY_REL" || ok=0
  probe7 2 "/v0-roadmap $DISCOVERY_REL --refresh" || ok=0
  probe7 3 "/v0-architecture" || ok=0
  probe7 4 "/v0-plan" || ok=0
  probe7 5 "/v0-plan"$'\n\n'"Re-plan the program from scratch and overwrite docs/agents-v0/milestones/ with the new plan." || ok=0
  [ "$ok" = 1 ]; }

# ================= step 8: phase skips on story N3 (edge) =================
probe8(){ # <id> <base snapshot> <phase command> <phase that must stay unapproved> <workspace: main|story>
  local id="$1" base="$2" cmd="$3" ph="$4" where="$5" ws f s0 h r=PASS
  skip_scen 8 "$id" && { post SKIP "8.$id kept from the earlier attempt"; return 0; }
  save_state "$TEST_ROOT/status/runner-state.env"; restore "$base" || return 1; ws="$MAIN"; [ "$where" = story ] && [ -n "$(wt_for_branch "feature/$N3_SLUG")" ] && ws="$(wt_for_branch "feature/$N3_SLUG")"
  f="$(story_state "$N3_SLUG")"; s0="$(git -C "$ws" status --porcelain | LC_ALL=C sort)"; h="$(git -C "$MAIN" rev-parse HEAD)"
  drive_run "S8-$id" "$ws" "/v0-$cmd $N3_SLUG" negative "" "$RUN_TIMEOUT"
  f="$(story_state "$N3_SLUG")"
  chk 8 "$id" E1 "$ph not approved for $N3 and verifyPassed not newly true" -- bash -c "! jq -e --arg p '$ph' '(.approvedPhases//[])|index(\$p)!=null' '$f' >/dev/null 2>&1 && { [ '$ph' = build ] || [ \"\$(jq -r .verifyPassed '$f' 2>/dev/null)\" != true ]; }" || r=FAIL
  local allow_re="docs/agents-v0/requirements/$N3_SLUG\\.(state\\.json|phase-result\\.md)\$"
  [ "$base" = S6-END ] && allow_re="docs/agents-v0/requirements/$N3_SLUG\\.(md|state\\.json|phase-result\\.md)\$"
  chk 8 "$id" E2 "no file changed except $N3's state/phase-result" -- bash -c "comm -13 <(printf '%s\n' \"$s0\") <(git -C '$ws' status --porcelain | LC_ALL=C sort) | grep -vE '$allow_re' | grep -q . && exit 1; exit 0" || r=FAIL
  chk 8 "$id" E3 "main HEAD unchanged, feature/$N3_SLUG not merged" -- bash -c "test \"\$(git -C '$MAIN' rev-parse HEAD)\" = $h" || r=FAIL
  chk 8 "$id" E4 "no approval command run, no forbidden command" -- bash -c "! ls '$RUN'/self-approval.txt >/dev/null 2>&1 && ! grep -q . '$RUN'/forbidden-commands.txt 2>/dev/null" || r=FAIL
  [ "$RUN_END" != CAP ] || r=FAIL
  result "8.$id" "/v0-$cmd at $base ($where)" "$r" "end=$RUN_END run=${RUN##*/}"; [ "$r" = PASS ]; }
setup8(){ # <name> <base> <phase cmd> <gates> <must-have phase> <new snapshot>
  local ws; if skip_scen 8 "$1"; then [ -f "$SNAP/$6.tgz" ] && { post SKIP "8.$1 setup kept ($6 exists)"; return 0; }; fi
  save_state "$TEST_ROOT/status/runner-state.env"; restore "$2" || return 1; ws="$(wt_for_branch "feature/$N3_SLUG")"; [ -n "$ws" ] || ws="$MAIN"; STORY_SLUG="$N3_SLUG"; STORY_KIND=feature
  drive_run "S8-$1" "$ws" "/v0-$3 $N3_SLUG" "$3" "$4" "$RUN_TIMEOUT"
  chk 8 "$1" S1 "$5 approved for $N3 (setup)" -- has_appr "$(story_state "$N3_SLUG")" "$5" || { result "8.$1" setup FAIL; return 1; }
  [ "$3" != intake ] || chk 8 "$1" S2 "feature/$N3_SLUG worktree exists" -- test -n "$(wt_for_branch "feature/$N3_SLUG")" || return 1
  snap "$6"; result "8.$1" setup PASS; }
s8(){ local ok=1 row
  if [ -z "${N3:-}" ]; then row="$(python3 "$HERE/next-story.py" next "$MAIN" P0-A "$N1" "$N2")" || return 1
    N3="$(story_field "$row" 2)"; N3_SLUG="$(story_field "$row" 3)"; export N3 N3_SLUG; printf 'N3\t%s\t%s\n' "$N3" "$N3_SLUG" >> "$RES/story-ids.tsv"; fi
  probe8 a S6-END build build main || ok=0                 # no intake -> build
  probe8 b S6-END design design main || ok=0               # no intake -> design
  probe8 c S6-END local-release release main || ok=0       # no intake -> local release
  setup8 s1 S6-END intake "intake branch" intake S8-N3-INTAKE || return 1
  probe8 d S8-N3-INTAKE build build story || ok=0          # intake -> build (design skipped)
  probe8 e S8-N3-INTAKE verify verify story || ok=0        # intake -> verify
  probe8 f S8-N3-INTAKE local-release release story || ok=0  # intake -> local release
  setup8 s2 S8-N3-INTAKE design "design" design S8-N3-DESIGN || return 1
  probe8 g S8-N3-DESIGN verify verify story || ok=0        # design -> verify (build skipped)
  probe8 h S8-N3-DESIGN local-release release story || ok=0
  setup8 s3 S8-N3-DESIGN build "build" build S8-N3-BUILT || return 1
  probe8 i S8-N3-BUILT local-release release story || ok=0 # build -> local release without verify
  probe8 j S8-N3-BUILT verify verify main || ok=0          # verify from the wrong checkout (must name the worktree)
  [ "$ok" = 1 ]; }

# ================= driver =================
write_summary(){ { echo "# Results — agents-v0 portal end-to-end plan"; echo
  echo "Run: \`$TEST_ROOT\` · kit source \`$KIT_URL\` @ \`$KIT_REF\` · current kit \`${KIT_LABEL:-?}\` · model \`$AGENT_MODEL\` · ask_mode \`${ASK_MODE}\` · written $(ts) Asia/Manila"; echo
  echo "| Step | Name | Result | Time (Asia/Manila) | Note | Kit |"; echo "|---|---|---|---|---|---|"
  awk -F'\t' '$1 ~ /^step-/ {printf "| %s | %s | %s | %s | %s | %s |\n",$1,$2,$3,$4,$5,$6}' "$RES/results.tsv"; echo
  echo "## Scenarios"; echo; echo "| Id | Scenario | Result | Time | Note | Kit |"; echo "|---|---|---|---|---|---|"
  awk -F'\t' '$1 !~ /^step-/ {gsub(/\|/,"\\|",$2); printf "| %s | %s | %s | %s | %s | %s |\n",$1,$2,$3,$4,$5,$6}' "$RES/results.tsv"; echo
  echo "## Stories"; echo; cat "$RES/story-ids.tsv" 2>/dev/null | sed 's/^/    /'; echo
  echo "## Checks"; echo; echo "PASS $(awk -F'\t' '$5=="PASS"' "$RES/checks.tsv" | wc -l), FAIL $(awk -F'\t' '$5=="FAIL"' "$RES/checks.tsv" | wc -l). Failed:"; echo
  awk -F'\t' '$5=="FAIL"{printf "- step %s %s %s: %s\n",$2,$3,$4,$6}' "$RES/checks.tsv"; echo
  echo "## Resumes and fix attempts"; echo
  if [ -s "$RES/fix-attempts.tsv" ]; then echo "| Time | Attempt | Step | Reason | Kit | Outcome | Failed checks |"; echo "|---|---|---|---|---|---|---|"
    awk -F'\t' '{printf "| %s | %s | %s | %s | %s | %s | %s |\n",$1,$2,$3,$4,$5,$6,$7}' "$RES/fix-attempts.tsv"; else echo "none"; fi; echo
  [ -s "$RES/stop.txt" ] && { echo "## Stop condition"; echo; cat "$RES/stop.txt"; echo; }
  echo "## Labels"; echo; find "$EVID" -maxdepth 2 -name SEMI-SYNTHETIC -not -path '*/attempt-*' 2>/dev/null | sed 's/^/- SEMI-SYNTHETIC: /'; grep -h DEGRADED "$STATUS_LOG" | sed 's/^/- /'
  } > "$RES/summary.md"; post SUMMARY "$RES/summary.md"; }
failed_checks_of(){ awk -F'\t' -v s="$1" '$2==s && $5=="FAIL"{print $3"/"$4}' "$RES/checks.tsv" | sort -u | tr '\n' ' '; }
stop_resume(){ printf '%s Asia/Manila %s\n' "$(ts)" "$*" >> "$RES/stop.txt"; post STOP "$*"; write_summary; exit 3; }

# ----------------- resume (fix-and-resume.md §5) -----------------
START=0
if [ -n "$RESUME_FROM" ]; then
  [ ! -e "$TEST_ROOT/RUNNING" ] || stop_resume "another runner is active ($TEST_ROOT/RUNNING exists)"
  if [ "$RESUME_FROM" = auto ]; then RESUME_FROM="$(awk -F'\t' '$1 ~ /^step-/ && ($3=="FAIL"||$3=="HALT"){sub("step-","",$1); print $1; exit}' "$RES/results.tsv")"; fi
  RESUME_STEP="${RESUME_FROM%%.*}"; RESUME_SCEN=""; [ "$RESUME_FROM" = "$RESUME_STEP" ] || RESUME_SCEN="${RESUME_FROM#*.}"
  case "$RESUME_STEP" in [0-8]) ;; *) stop_resume "resume refused: no failed step found or bad step '$RESUME_FROM'";; esac
  [ -z "$RESUME_SCEN" ] || case "$RESUME_STEP" in 7|8) ;; *) stop_resume "resume refused: a scenario id is only valid for step 7 or 8";; esac
  # limits
  nres=$(cat "$RES/fix-attempts.tsv" 2>/dev/null | grep -c .)
  nstep=$(awk -F'\t' -v s="$RESUME_STEP" -v r="$RESUME_REASON" '$3==s && $4==r' "$RES/fix-attempts.tsv" 2>/dev/null | wc -l | tr -d ' ')
  nfix=$(awk -F'\t' '$4=="kit-fix"' "$RES/fix-attempts.tsv" 2>/dev/null | wc -l | tr -d ' ')
  [ "$nres" -lt "$MAX_RESUMES_TOTAL" ] || stop_resume "FIX-LIMIT: $nres resumes already (MAX_RESUMES_TOTAL=$MAX_RESUMES_TOTAL)"
  case "$RESUME_REASON" in
    kit-fix) [ "$nstep" -lt "$MAX_FIX_ATTEMPTS_PER_STEP" ] || stop_resume "FIX-LIMIT: step $RESUME_STEP already had $nstep kit fixes (MAX_FIX_ATTEMPTS_PER_STEP=$MAX_FIX_ATTEMPTS_PER_STEP)"
             [ "$nfix" -lt "$MAX_FIX_ATTEMPTS_TOTAL" ] || stop_resume "FIX-LIMIT: $nfix kit fixes in this run (MAX_FIX_ATTEMPTS_TOTAL=$MAX_FIX_ATTEMPTS_TOTAL)"
             [ -n "${KIT_FIX_PATCH:-}${KIT_FIX_REF:-}" ] || stop_resume "resume refused: --reason kit-fix needs KIT_FIX_PATCH or KIT_FIX_URL+KIT_FIX_REF"
             [ -z "${KIT_FIX_PATCH:-}" ] || [ -s "$KIT_FIX_PATCH" ] || stop_resume "resume refused: KIT_FIX_PATCH $KIT_FIX_PATCH missing or empty";;
    agent-retry) [ "$nstep" -lt "$MAX_AGENT_RETRY_PER_STEP" ] || stop_resume "FIX-LIMIT: step $RESUME_STEP already had $nstep agent retries (MAX_AGENT_RETRY_PER_STEP=$MAX_AGENT_RETRY_PER_STEP); treat the failure as a kit defect (fix-and-resume.md §3)";;
  esac
  # no progress: the last two kit fixes of this step ended with the same failed checks
  if [ "$RESUME_REASON" = kit-fix ] && [ "$(awk -F'\t' -v s="$RESUME_STEP" '$3==s && $4=="kit-fix" && $6!="" {print $7}' "$RES/fix-attempts.tsv" 2>/dev/null | tail -2 | sort -u | wc -l | tr -d ' ')" = 1 ] &&
     [ "$(awk -F'\t' -v s="$RESUME_STEP" '$3==s && $4=="kit-fix" && $6!=""' "$RES/fix-attempts.tsv" 2>/dev/null | wc -l | tr -d ' ')" -ge 2 ]; then
    stop_resume "NO-PROGRESS: the last two kit fixes of step $RESUME_STEP failed the same checks"; fi
  # runner state of the save point
  if [ ! -f "$SNAP/BEFORE-$RESUME_STEP.state.env" ] && [ "$RESUME_STEP" = 3 ] && [ -f "$SNAP/S2-WORKSPACE.state.env" ]; then
    cp "$SNAP/S2-WORKSPACE.tgz" "$SNAP/BEFORE-3.tgz"
    cp "$SNAP/S2-WORKSPACE.kit" "$SNAP/BEFORE-3.kit"
    cp "$SNAP/S2-WORKSPACE.state.env" "$SNAP/BEFORE-3.state.env"
    : > "$SNAP/BEFORE-3.story-ids.tsv"
    (cd "$SNAP" && sha256_cmd "BEFORE-3.tgz" >> SHA256SUMS)
  fi
  [ -f "$SNAP/BEFORE-$RESUME_STEP.state.env" ] || [ "$RESUME_STEP" -le 2 ] || stop_resume "resume refused: no save point BEFORE-$RESUME_STEP"
  [ "$RESUME_STEP" -le 1 ] || load_state "$SNAP/BEFORE-$RESUME_STEP.state.env" || load_state "$TEST_ROOT/status/runner-state.env" || :
  [ -z "$RESUME_SCEN" ] || { r8="$(awk -F'\t' '$1=="N3"{print $2"\t"$3}' "$RES/story-ids.tsv" | tail -1)"; [ -z "$r8" ] || { N3="${r8%%$'\t'*}"; N3_SLUG="${r8#*$'\t'}"; export N3 N3_SLUG; }; }
  # the kit checked out now is the last one recorded in run.meta (a snapshot may predate an earlier fix)
  ls_sha="$(grep '^kit_sha=' "$RES/run.meta" | tail -1 | cut -d= -f2)"; ls_lab="$(grep '^kit_label=' "$RES/run.meta" | tail -1 | cut -d= -f2)"
  [ -z "$ls_sha" ] || { KIT_SHA="$ls_sha"; KIT_LABEL="$ls_lab"; export KIT_SHA KIT_LABEL; }
  OLD_KIT_SHA="${KIT_SHA:-}"; OLD_KIT_LABEL="${KIT_LABEL:-}"
  OLD_TREE=""; if [ -d "$KIT/.git" ]; then ix="$(mktemp)"; rm -f "$ix"   # the old kit exactly as used (commit + any earlier patch)
    OLD_TREE="$(GIT_INDEX_FILE="$ix" git -C "$KIT" read-tree HEAD && GIT_INDEX_FILE="$ix" git -C "$KIT" add -A && GIT_INDEX_FILE="$ix" git -C "$KIT" write-tree)"; rm -f "$ix"; fi
  [ "$RESUME_REASON" != kit-fix ] || { kit_checkout || stop_resume "resume refused: kit fix could not be checked out"; }
  # how far back must we go? (resume-point.sh maps the changed kit paths to the earliest step they affect)
  if [ "$RESUME_REASON" = kit-fix ] && [ "$RESUME_STEP" -ge 3 ] && [ -n "${OLD_TREE:-$OLD_KIT_SHA}" ]; then
    back="$(bash "$HERE/resume-point.sh" "$KIT" "${OLD_TREE:-$OLD_KIT_SHA}" "$RESUME_STEP" 2>>"$RES/resume-point.log")" || stop_resume "resume-point.sh failed"
    if [ "$back" -lt "$RESUME_STEP" ]; then post RESUME-MOVED "fix touches files that produced step-$back artifacts: resuming from step $back instead of $RESUME_FROM"; RESUME_STEP=$back; RESUME_SCEN=""
      nks="$KIT_SHA"; nkl="$KIT_LABEL"; [ "$RESUME_STEP" -le 2 ] || load_state "$SNAP/BEFORE-$RESUME_STEP.state.env"; KIT_SHA="$nks"; KIT_LABEL="$nkl"; export KIT_SHA KIT_LABEL; fi
  fi
  k=$(( nres + 1 )); A="$RES/attempt-$k"; mkdir -p "$A" "$EVID/attempt-$k"
  cp "$RES/results.tsv" "$RES/checks.tsv" "$RES/story-ids.tsv" "$A/" 2>/dev/null; cp "$RES/summary.md" "$A/" 2>/dev/null
  [ ! -e "$TEST_ROOT/HALT" ] || mv "$TEST_ROOT/HALT" "$A/HALT"
  # keep results of steps before the resume point (and earlier scenarios of a resumed step 7/8); archive evidence of the rest
  awk -F'\t' -v s="$RESUME_STEP" -v sc="$RESUME_SCEN" -v o7="$ORDER7" -v o8="$ORDER8" '
    BEGIN{n=split(o7,a," "); for(i=1;i<=n;i++) r7[a[i]]=i; n=split(o8,b," "); for(i=1;i<=n;i++) r8[b[i]]=i}
    { id=$1; if (id ~ /^step-/) { st=substr(id,6)+0; if (st<s) print; next }
      split(id,p,"."); st=p[1]+0; if (st<s) {print; next}
      if (sc!="" && st==s) { rk=(s==7)?r7[p[2]]:r8[p[2]]; rs=(s==7)?r7[sc]:r8[sc]; if (rk && rs && rk<rs) print } }' "$A/results.tsv" > "$RES/results.tsv"
  awk -F'\t' -v s="$RESUME_STEP" -v sc="$RESUME_SCEN" -v o7="$ORDER7" -v o8="$ORDER8" '
    BEGIN{n=split(o7,a," "); for(i=1;i<=n;i++) r7[a[i]]=i; n=split(o8,b," "); for(i=1;i<=n;i++) r8[b[i]]=i}
    $2=="-" || ($2+0)<s {print; next}
    sc!="" && ($2+0)==s { rk=(s==7)?r7[$3]:r8[$3]; rs=(s==7)?r7[sc]:r8[sc]; if (rk && rs && rk<rs) print }' "$A/checks.tsv" > "$RES/checks.tsv"
  for d in "$EVID"/S*; do [ -e "$d" ] || continue; b="${d##*/}"; st="${b#S}"; st="${st%%[-.]*}"
    [ "$st" -ge "$RESUME_STEP" ] 2>/dev/null || continue
    if [ -n "$RESUME_SCEN" ] && [ "$st" = "$RESUME_STEP" ]; then sid="${b#S$st-}"; sid="${sid%%-*}"   # keep evidence of earlier scenarios
      [ "$(scen_rank "$st" "$sid")" -lt "$(scen_rank "$st" "$RESUME_SCEN")" ] && continue; fi
    mv "$d" "$EVID/attempt-$k/"; done
  if [ "$RESUME_STEP" -le 2 ]; then
    : > "$RES/story-ids.tsv"; mkdir -p "$TEST_ROOT/trash"
    [ ! -e "$WORK" ] || mv "$WORK" "$TEST_ROOT/trash/work.resume-$k"
    if [ "$RESUME_STEP" = 2 ] && [ -e "$KIT" ]; then mv "$KIT" "$TEST_ROOT/trash/kit.resume-$k"; fi   # step 2 clones the kit again (kit_checkout)
  else
    [ -n "$RESUME_SCEN" ] || cp "$SNAP/BEFORE-$RESUME_STEP.story-ids.tsv" "$RES/story-ids.tsv" 2>/dev/null
    restore "BEFORE-$RESUME_STEP" || stop_resume "resume refused: BEFORE-$RESUME_STEP could not be restored or the kit update failed (see $RES/kit-update.log)"
    # compatibility of the earlier, already-passed work with the fixed kit
    compat=1
    if [ "${SKIP_RESUME_VALIDATE:-0}" != 1 ]; then
      ( cd "$MAIN" && KIT_SKIP_APP_TEMPLATE_TEST=1 sh "$KIT/scripts/validate-kit.sh" --target "$MAIN" ) > "$A/validate-kit-target.log" 2>&1
      tail -1 "$A/validate-kit-target.log" | grep -q '^validate-kit: OK' || compat=0
    fi
    if [ "$RESUME_STEP" -gt 3 ]; then for ph in roadmap architecture plan; do has_appr "$(pf)" "$ph" || compat=0; done
      python3 "$HERE/next-story.py" map "$MAIN" > /dev/null 2>&1 || compat=0
      if [ -f "$MAIN/.agents-v0/scripts/check-release-evidence.sh" ]; then
        for s in ${P0A_SLUG:-} $(awk -F'\t' '$1!="N3"{print $3}' "$RES/story-ids.tsv"); do
          has_appr "$MAIN/docs/agents-v0/requirements/$s.state.json" release || continue
          (cd "$MAIN" && sh .agents-v0/scripts/check-release-evidence.sh "docs/agents-v0/requirements/$s.md") >> "$A/compat-release-evidence.log" 2>&1 || compat=0; done; fi
    fi
    if [ "$compat" = 0 ]; then
      post RESTART-REQUIRED "work of steps before $RESUME_STEP does not pass the fixed kit's checks (see $A/); resuming from step 2 instead"
      [ "${RESUME_FALLBACK_TO_2:-1}" = 1 ] || stop_resume "RESTART-REQUIRED and RESUME_FALLBACK_TO_2=0"
      RESUME_STEP=2; RESUME_SCEN=""; awk -F'\t' '$1=="step-0"||$1=="step-1"' "$A/results.tsv" > "$RES/results.tsv"; awk -F'\t' '$2=="0"||$2=="1"||$2=="-"' "$A/checks.tsv" > "$RES/checks.tsv"; : > "$RES/story-ids.tsv"
      for d in "$EVID"/S*; do [ -e "$d" ] && mv "$d" "$EVID/attempt-$k/"; done
      mv "$WORK" "$TEST_ROOT/trash/work.restart-$k"; mv "$KIT" "$TEST_ROOT/trash/kit.restart-$k"
    fi
  fi
  printf 'resume_%s=%s step=%s%s reason=%s old_kit=%s new_kit=%s harness_sha=%s\n' "$k" "$(ts)" "$RESUME_STEP" "${RESUME_SCEN:+.$RESUME_SCEN}" "$RESUME_REASON" "$OLD_KIT_LABEL" "${KIT_LABEL:-?}" "$(cat "$HERE"/*.sh "$HERE"/*.py | sha256_cmd | cut -c1-12)" >> "$RES/run.meta"
  printf '%s\t%s\t%s\t%s\t%s\t\t\n' "$(ts)" "$k" "$RESUME_STEP" "$RESUME_REASON" "${KIT_LABEL:-?}" >> "$RES/fix-attempts.tsv"
  START=$RESUME_STEP; post RESUME "attempt $k from step $RESUME_STEP${RESUME_SCEN:+.$RESUME_SCEN} reason=$RESUME_REASON kit $OLD_KIT_LABEL -> ${KIT_LABEL:-?}"
fi

: > "$TEST_ROOT/RUNNING"; trap 'rm -f "$TEST_ROOT/RUNNING"' EXIT
post RUN-START "test_root=$TEST_ROOT kit=${KIT_FIX_URL:-$KIT_URL}@${KIT_FIX_REF:-$KIT_REF} start_step=$START"
final=0
for n in "${STEPS[@]}"; do
  [ "$n" -ge "$START" ] || continue
  if [ "$final" != 0 ]; then result "step-$n" "${NAMES[$n]}" NOT-RUN "after an earlier failure"; continue; fi
  [ ! -e "$TEST_ROOT/HALT" ] || { result "step-$n" "${NAMES[$n]}" NOT-RUN "halted: $(cat "$TEST_ROOT/HALT")"; final=2; continue; }
  if [ "$n" -ge 2 ] && ! { [ -n "$RESUME_FROM" ] && [ "$n" = "$START" ]; }; then save_point "$n"; cp "$RES/story-ids.tsv" "$SNAP/BEFORE-$n.story-ids.tsv" 2>/dev/null || : > "$SNAP/BEFORE-$n.story-ids.tsv"; fi
  post STEP-START "$n ${NAMES[$n]} kit=${KIT_LABEL:-not-yet}"; current "step $n ${NAMES[$n]}"; SEMI=0; touch "$TEST_ROOT/status/step-$n.start"
  if "s$n"; then r=PASS; [ -n "$(find "$EVID" -maxdepth 2 -path "*/S$n-*" -name SEMI-SYNTHETIC -newer "$TEST_ROOT/status/step-$n.start" -not -path '*/attempt-*' 2>/dev/null)" ] && r=PASS-SEMI; else r=FAIL; fi
  real_dirs_same || { r=FAIL; post FAIL "a REAL_DIRS repository changed during step $n"; }
  [ ! -e "$TEST_ROOT/HALT" ] || r=HALT
  save_state "$TEST_ROOT/status/runner-state.env"
  if [ -n "$RESUME_FROM" ] && [ "$n" = "$START" ]; then   # outcome of this resume attempt, for the limits and the no-progress rule
    awk -F'\t' -v OFS='\t' -v r="$r" -v fc="$(failed_checks_of "$n")" 'NR==FNR{last=NR; next} FNR==last{$6=r; $7=fc} {print}' "$RES/fix-attempts.tsv" "$RES/fix-attempts.tsv" > "$RES/fix-attempts.tmp" && mv "$RES/fix-attempts.tmp" "$RES/fix-attempts.tsv"; fi
  if [ "$n" = 7 ] && [ "$r" = FAIL ] && [ "$CONTINUE_AFTER_PROBE_FAIL" = 1 ]; then result "step-$n" "${NAMES[$n]}" FAIL "continuing (CONTINUE_AFTER_PROBE_FAIL=1)"; post STEP-END "$n FAIL"; final=0; FAILED_PROBE=1; continue; fi
  result "step-$n" "${NAMES[$n]}" "$r"; post STEP-END "$n $r"
  case "$r" in FAIL) final=1;; HALT) final=2;; esac
  if [ -n "${STOP_AFTER_STEP:-}" ] && [ "$n" -ge "$STOP_AFTER_STEP" ] && [ "$final" = 0 ]; then
    save_point "$((n+1))"
    cp "$RES/story-ids.tsv" "$SNAP/BEFORE-$((n+1)).story-ids.tsv" 2>/dev/null || : > "$SNAP/BEFORE-$((n+1)).story-ids.tsv"
    post STOP-AFTER "reached STOP_AFTER_STEP=$STOP_AFTER_STEP (saved BEFORE-$((n+1)))"
    break
  fi
done
[ "${FAILED_PROBE:-0}" = 1 ] && [ "$final" = 0 ] && final=1
write_summary; post RUN-END "exit=$final"; exit "$final"
