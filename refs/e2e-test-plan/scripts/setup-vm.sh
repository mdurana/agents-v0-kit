#!/usr/bin/env bash
# setup-vm.sh — prepare a fresh Ubuntu 24.04 VM (Linode shared 16 GB, sg-sin-2) to run this e2e plan (test-plan.md §12).
# HARNESS-FIX 2026-10-29 (SV-01). Native tools only: no Docker, no Podman, no Testcontainers, no Redis (Marlon's
# decision); PostgreSQL 17 is the portable zonky build that prereqs.sh installs under $TOOLS_DIR, and P0-A AC-4
# (container run) stays DEGRADED, exactly as on Marlon's box.
#
# Usage (as root on the VM; every mode is safe to run again):
#   bash setup-vm.sh --kit-url <bundle file | local repo | https URL> --kit-ref <branch|commit> [options]   full setup
#   bash setup-vm.sh --pre-image [--defer-odc]     clean caches/logs/history, refuse if disk used > 5.4 GB
#   bash setup-vm.sh --after-image                 after the image is captured: install deferred OWASP data
#   add --dry-run to any mode: print every action, change nothing (needs no root)
# Options: --user <name> (default e2e)  --odc-src <dir with odc.mv.db>  --defer-odc  --skip-cli-update  --log-dir <dir>
# Private kit repo: either a git bundle made where you can read the repo (`git bundle create kit.bundle <branch>`),
# or an https URL plus GITHUB_TOKEN_E2E_VM in the environment (read-only, fine-grained). The token is only ever
# passed to git through environment variables for the one clone/fetch; it is never written to a file, a log or argv.
#
# This script performs NO sign-in (agy Google sign-in, Cursor CURSOR_API_KEY, GitHub): those come after the image
# is captured, so the image holds no credential. It contains no secrets.
set -eu

# ---------- settings ----------
MODE=setup; DRY=0; RUN_USER=e2e; KIT_SRC="${KIT_URL:-}"; KIT_REF_IN="${KIT_REF:-}"; ODC_SRC_IN=""; DEFER_ODC=0
SKIP_CLI_UPDATE=0; LOG_DIR=""; USER_PHASE=0
LIMIT_BYTES=5400000000      # 5.4 GB (decimal): the Linode image limit is 6 GB by default; keep a margin
APT_PACKAGES="git jq python3 python3-yaml python3-docx curl xz-utils tmux rsync unzip"
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) DRY=1; shift;;
  --pre-image) MODE=pre-image; shift;;
  --after-image) MODE=after-image; shift;;
  --user-phase) USER_PHASE=1; shift;;                 # internal: the part that runs as the run user
  --user) RUN_USER="$2"; shift 2;;
  --kit-url) KIT_SRC="$2"; shift 2;;
  --kit-ref) KIT_REF_IN="$2"; shift 2;;
  --odc-src) ODC_SRC_IN="$2"; shift 2;;
  --defer-odc) DEFER_ODC=1; shift;;
  --skip-cli-update) SKIP_CLI_UPDATE=1; shift;;
  --log-dir) LOG_DIR="$2"; shift 2;;
  -h|--help) sed -n '2,20p' "$0"; exit 0;;
  *) echo "setup-vm.sh: unknown argument: $1" >&2; exit 64;;
esac; done
U_HOME="/home/$RUN_USER"; [ "$USER_PHASE" = 0 ] || U_HOME="$HOME"
KIT_DIR="$U_HOME/kit-src"; PLAN="$KIT_DIR/refs/e2e-test-plan"
TOOLS_DIR_U="$U_HOME/.local/agents-v0-tools"; ODC_DST_U="$U_HOME/.m2/repository/org/owasp/dependency-check-data/9.0"
: "${LOG_DIR:=$U_HOME/setup-vm}"
SELF_COPY=/usr/local/lib/agents-v0-setup-vm.sh

# ---------- helpers ----------
ts(){ TZ=Asia/Manila date '+%F %T'; }
say(){ printf '%s Asia/Manila setup-vm: %s\n' "$(ts)" "$*"; }
die(){ printf '%s Asia/Manila setup-vm: ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }
# run <cmd...>: print the command, then run it unless --dry-run
run(){ printf '+ '; printf '%q ' "$@"; printf '\n'; [ "$DRY" = 1 ] || "$@"; }
# run_sh <shell text>: same, for a pipeline (e.g. an official installer `curl ... | bash`)
run_sh(){ printf '+ %s\n' "$1"; [ "$DRY" = 1 ] || bash -c "$1"; }
need_root(){ [ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || die "run this mode as root (or add --dry-run)"; }
as_user(){ # <args...>: run this script's user phase as the run user, with a clean environment (no secrets passed)
  local a=(--user-phase --user "$RUN_USER"); [ "$DRY" = 0 ] || a+=(--dry-run)
  if [ "$DRY" = 1 ]; then say "(dry run) the user phase below runs as $RUN_USER via runuser"; HOME="$U_HOME" bash "$0" "${a[@]}" "$@"; return; fi
  install -m 0755 "$0" "$SELF_COPY"
  runuser -u "$RUN_USER" -- env -i HOME="$U_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" LANG=C.UTF-8 TZ=Asia/Manila \
    PATH="$U_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" bash "$SELF_COPY" "${a[@]}" "$@"; }
used_bytes(){ df -B1 --output=used / | tail -1 | tr -d ' '; }
gb(){ awk -v b="$1" 'BEGIN{printf "%.2f GB", b/1e9}'; }

# =====================================================================================================
# USER PHASE (runs as the run user): CLIs, toolchain, agy trust setting, versions log
# =====================================================================================================
user_phase(){
  [ "$DRY" = 1 ] || mkdir -p "$LOG_DIR"
  export PATH="$U_HOME/.local/bin:$PATH"
  if [ "$MODE" = after-image ]; then
    # Deferred OWASP data: plain prereqs.sh --install (without ODC_DEFER) installs only what is still missing.
    say "installing deferred OWASP data (ODC_SRC=${ODC_SRC_U:-none})"
    run env ODC_SRC="${ODC_SRC_U:-}" TOOLS_DIR="$TOOLS_DIR_U" bash "$PLAN/scripts/prereqs.sh" --install
    run rm -f "$U_HOME/.odc-deferred"
    write_versions; return 0; fi

  # 1. Agent CLIs: latest release of each, official installers, into ~/.local/bin. No sign-in here.
  if [ "$SKIP_CLI_UPDATE" = 1 ] && [ -x "$U_HOME/.local/bin/agy" ]; then say "agy present, --skip-cli-update"
  else run_sh 'curl -fsSL https://antigravity.google/cli/install.sh | bash'; fi
  if [ "$SKIP_CLI_UPDATE" = 1 ] && [ -x "$U_HOME/.local/bin/agent" ]; then say "Cursor CLI present, --skip-cli-update"
  else run_sh 'curl -fsS https://cursor.com/install | bash'; fi

  # 2. agy settings: trust the folders the run uses. Marlon's box trusts /workspace; a fresh VM trusts nothing, and
  #    whether `agy -p` would stop to ask is unverified, so we set it. Existing keys are kept (merge, not overwrite).
  say "agy settings: trustedWorkspaces += $U_HOME, $U_HOME/agents-v0-e2e"
  run mkdir -p "$U_HOME/.gemini/antigravity-cli"
  run python3 -c 'import json,os,sys
p=sys.argv[1]; d={}
if os.path.exists(p):
    try: d=json.load(open(p))
    except Exception: d={}
t=d.setdefault("trustedWorkspaces",[])
for w in sys.argv[2:]:
    if w not in t: t.append(w)
json.dump(d,open(p,"w"),indent=2)' "$U_HOME/.gemini/antigravity-cli/settings.json" "$U_HOME" "$U_HOME/agents-v0-e2e"

  # 3. Toolchain into $TOOLS_DIR (no root): Temurin JDK 21, Node 22, portable PostgreSQL 17 (zonky), OWASP data.
  #    prereqs.sh --install is the same code step 1 of the run uses; it writes $TOOLS_DIR/tools.env.
  local odc_env=(ODC_SRC="${ODC_SRC_U:-}")
  if [ "$DEFER_ODC" = 1 ]; then odc_env+=(ODC_DEFER=1); run touch "$U_HOME/.odc-deferred"; fi
  run env "${odc_env[@]}" TOOLS_DIR="$TOOLS_DIR_U" AGENT_DRIVER=antigravity bash "$PLAN/scripts/prereqs.sh" --install
  say "prerequisite check (agent sign-in is expected to be missing until after the image):"
  if [ "$DRY" = 1 ]; then run env "${odc_env[@]}" TOOLS_DIR="$TOOLS_DIR_U" AGENT_DRIVER=antigravity bash "$PLAN/scripts/prereqs.sh" --check
  else env "${odc_env[@]}" TOOLS_DIR="$TOOLS_DIR_U" AGENT_DRIVER=antigravity bash "$PLAN/scripts/prereqs.sh" --check | tee "$LOG_DIR/prereqs-check.txt" || true
    ! grep -qE '^PREREQ +(git|jq|python3|curl|tar|xz|sha256|pyyaml|python-docx|jdk21|node22|postgres17|agy-bin|network|disk) +(MISSING|HUMAN|FAILED)' "$LOG_DIR/prereqs-check.txt" ||
      die "a prerequisite is missing, see $LOG_DIR/prereqs-check.txt"; fi

  # 4. Login shells (SSH, tmux) get ~/.local/bin and the toolchain. Marked block, added once.
  if ! grep -q 'agents-v0 e2e (setup-vm.sh)' "$U_HOME/.profile" 2>/dev/null; then
    say "adding the toolchain block to $U_HOME/.profile"
    [ "$DRY" = 1 ] || cat >> "$U_HOME/.profile" <<'PROF'
# >>> agents-v0 e2e (setup-vm.sh) >>>
export PATH="$HOME/.local/bin:$PATH"
if [ -f "$HOME/.local/agents-v0-tools/tools.env" ]; then . "$HOME/.local/agents-v0-tools/tools.env"; export PATH="$TOOLS_PATH:$PATH"; fi
# <<< agents-v0 e2e (setup-vm.sh) <<<
PROF
  fi

  # 5. launch.env example (no secrets) for scripts/start-tmux.sh
  if [ ! -f "$U_HOME/launch.env" ]; then say "writing $U_HOME/launch.env (example, no secrets)"
    [ "$DRY" = 1 ] || cat > "$U_HOME/launch.env" <<LENV
# launch.env for scripts/start-tmux.sh — no secrets in this file (test-plan.md §12)
export AGENT_DRIVER=antigravity AGENT_MODEL=gemini-4-argon-medium AGY_MODEL=gemini-4-argon-medium
export KIT_URL=\$HOME/kit-src KIT_REF=$(git -C "$KIT_DIR" rev-parse HEAD 2>/dev/null || echo "<commit>")
export TARGET_SURFACE=frontend STOP_AFTER_STEP=4
export LANG=C.UTF-8   # OWASP data: already in ~/.m2 (or setup-vm.sh --after-image), so no ODC_SRC
LENV
  fi
  write_versions
  cat <<NEXT

Setup done for $RUN_USER. Next, in this order (test-plan.md §12):
  1. as root:  bash $SELF_COPY --pre-image [--defer-odc]     (must report used <= 5.4 GB)
  2. power off and capture the Linode image (no sign-in has happened yet)
  3. boot; as $RUN_USER: run 'agy' once over SSH and complete the Google sign-in; check: agy -p 'Reply with exactly: ok'
  4. if the OWASP data was deferred: bash $SELF_COPY --after-image   (as root)
  5. as $RUN_USER: cd ~/kit-src/refs/e2e-test-plan && bash scripts/start-tmux.sh ~/launch.env
Versions: $LOG_DIR/versions.txt
NEXT
}
write_versions(){ # every installed tool's version, for the results (CL-01)
  local f="$LOG_DIR/versions.txt"; say "writing $f"; [ "$DRY" = 0 ] || return 0
  # shellcheck source=/dev/null
  if [ -f "$TOOLS_DIR_U/tools.env" ]; then . "$TOOLS_DIR_U/tools.env"; export PATH="${TOOLS_PATH:-}:$PATH"; fi
  { echo "# setup-vm.sh versions, $(ts) Asia/Manila"
    # shellcheck source=/dev/null
    echo "os: $(. /etc/os-release && echo "$PRETTY_NAME") kernel $(uname -r) $(uname -m)"
    echo "kit: $(git -C "$KIT_DIR" rev-parse HEAD 2>/dev/null) ($(git -C "$KIT_DIR" log -1 --format=%s 2>/dev/null))"
    echo "agy: $(agy --version 2>&1 | head -1)"
    echo "agent (Cursor CLI): $(agent --version 2>&1 | head -1)"
    echo "java: $(java -version 2>&1 | head -1)"
    echo "node: $(node -v 2>&1) npm $(npm -v 2>&1)"
    echo "postgres: $("${PG_HOME:-/nonexistent}/bin/postgres" --version 2>&1)"
    echo "odc: $(ls -l "$ODC_DST_U/odc.mv.db" 2>/dev/null || echo 'not installed (deferred or missing)')"
    echo "git: $(git --version)  python3: $(python3 --version 2>&1)  jq: $(jq --version)  tmux: $(tmux -V)"
  } > "$f"; cat "$f"; }

# =====================================================================================================
# ROOT: full setup
# =====================================================================================================
fetch_kit(){ # clone or update $KIT_DIR from a bundle, a local repo or https (+ GITHUB_TOKEN_E2E_VM), as root
  [ -n "$KIT_SRC" ] || { [ -d "$KIT_DIR/.git" ] && { say "kit already at $KIT_DIR ($(git -c safe.directory="$KIT_DIR" -C "$KIT_DIR" rev-parse --short HEAD 2>/dev/null)), no --kit-url given"; return 0; }; die "--kit-url is required (git bundle file, local repo or https URL)"; }
  [ -n "$KIT_REF_IN" ] || die "--kit-ref is required (branch or commit to run, e.g. the one Marlon approved)"
  local g=(git -c safe.directory="$KIT_DIR") auth=0
  case "$KIT_SRC" in
    https://*)
      if [ -n "${GITHUB_TOKEN_E2E_VM:-}" ]; then auth=1
        # The token goes to git only as an HTTP header through GIT_CONFIG_* environment variables of this one
        # process tree: not in argv (ps), not in .git/config, not in the remote URL, not in this log.
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
        GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN_E2E_VM" | base64 -w0)"; export GIT_CONFIG_VALUE_0
        say "GitHub auth: GITHUB_TOKEN_E2E_VM via environment (value not shown)"
      else say "no GITHUB_TOKEN_E2E_VM: cloning $KIT_SRC anonymously (fails for a private repo)"; fi;;
    *) [ "$DRY" = 1 ] || [ -e "$KIT_SRC" ] || die "kit source $KIT_SRC not found";;
  esac
  if [ -d "$KIT_DIR/.git" ]; then
    run "${g[@]}" -C "$KIT_DIR" fetch -q "$KIT_SRC" '+refs/heads/*:refs/remotes/origin/*'
  else
    run "${g[@]}" clone -q --no-checkout "$KIT_SRC" "$KIT_DIR"
  fi
  [ "$auth" = 0 ] || unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  # check out the requested ref: a commit, or a branch (local or origin/<branch>)
  if [ "$DRY" = 1 ]; then run "${g[@]}" -C "$KIT_DIR" checkout -q --detach "$KIT_REF_IN"
  else local c; c="$("${g[@]}" -C "$KIT_DIR" rev-parse -q --verify "$KIT_REF_IN^{commit}" 2>/dev/null || "${g[@]}" -C "$KIT_DIR" rev-parse -q --verify "origin/$KIT_REF_IN^{commit}")" ||
      die "kit ref $KIT_REF_IN not found in $KIT_SRC"
    run "${g[@]}" -C "$KIT_DIR" checkout -q --detach "$c"; fi
  case "$KIT_SRC" in https://*) run "${g[@]}" -C "$KIT_DIR" remote set-url origin "$KIT_SRC";; esac   # never a token in the URL
  run chown -R "$RUN_USER:$RUN_USER" "$KIT_DIR"; }
setup_root(){
  need_root
  # check the kit arguments before changing anything (a re-run with the kit already in place may omit them)
  [ -n "$KIT_SRC" ] || [ -d "$KIT_DIR/.git" ] || die "--kit-url is required (git bundle file, local repo or https URL)"
  [ -n "$KIT_REF_IN" ] || [ -z "$KIT_SRC" ] || die "--kit-ref is required (branch or commit to run)"
  # shellcheck source=/dev/null
  [ "$DRY" = 1 ] || { . /etc/os-release; [ "${ID:-}" = ubuntu ] || say "warning: not Ubuntu (${PRETTY_NAME:-?}); tested target is Ubuntu 24.04"; }
  say "1/6 packages (native tools only; no Docker/Podman/Redis): $APT_PACKAGES"
  run env DEBIAN_FRONTEND=noninteractive apt-get update -q
  # shellcheck disable=SC2086
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $APT_PACKAGES ca-certificates
  say "2/6 timezone Asia/Manila"
  if [ "$DRY" = 1 ]; then run timedatectl set-timezone Asia/Manila
  elif command -v timedatectl >/dev/null && run timedatectl set-timezone Asia/Manila 2>/dev/null; then :
  else run ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime; run_sh 'echo Asia/Manila > /etc/timezone'; fi   # no systemd (container)
  say "3/6 run user $RUN_USER (non-root; runs everything else)"
  if [ "$DRY" = 1 ] || ! id "$RUN_USER" >/dev/null 2>&1; then run adduser --disabled-password --gecos "agents-v0 e2e" "$RUN_USER"; fi
  if [ -s /root/.ssh/authorized_keys ] && [ ! -s "$U_HOME/.ssh/authorized_keys" ]; then
    run install -d -m 700 -o "$RUN_USER" -g "$RUN_USER" "$U_HOME/.ssh"
    run install -m 600 -o "$RUN_USER" -g "$RUN_USER" /root/.ssh/authorized_keys "$U_HOME/.ssh/authorized_keys"; fi
  run install -d -o "$RUN_USER" -g "$RUN_USER" "$LOG_DIR"
  say "4/6 kit source -> $KIT_DIR"
  fetch_kit
  say "5/6 OWASP data source"
  if [ -n "$ODC_SRC_IN" ]; then
    [ "$DRY" = 1 ] || [ -s "$ODC_SRC_IN/odc.mv.db" ] || die "--odc-src $ODC_SRC_IN has no odc.mv.db"
    run rsync -a --chown="$RUN_USER:$RUN_USER" "$ODC_SRC_IN"/ "$U_HOME/odc-data"/
  fi
  ODC_SRC_U=""
  if [ -s "$U_HOME/odc-data/odc.mv.db" ] || { [ "$DRY" = 1 ] && [ -n "$ODC_SRC_IN" ]; }; then ODC_SRC_U="$U_HOME/odc-data"; fi
  [ -n "$ODC_SRC_U" ] || say "no prebuilt OWASP data: prereqs.sh builds it from the NVD mirror (30-60 min) unless --defer-odc"
  say "6/6 user phase as $RUN_USER: agy + Cursor CLI, JDK 21, Node 22, PostgreSQL 17, OWASP data, tools.env, agy trust"
  local ua=(); [ "$DEFER_ODC" = 0 ] || ua+=(--defer-odc); [ "$SKIP_CLI_UPDATE" = 0 ] || ua+=(--skip-cli-update)
  [ -z "$ODC_SRC_U" ] || ua+=(--odc-src "$ODC_SRC_U")
  as_user "${ua[@]}" --log-dir "$LOG_DIR"; }

# =====================================================================================================
# ROOT: --pre-image (clean, check for credentials, measure, refuse when too big)
# =====================================================================================================
pre_image(){
  need_root
  say "pre-image: cleaning caches, logs and shell history"
  run apt-get clean
  run_sh 'rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin'
  if command -v journalctl >/dev/null || [ "$DRY" = 1 ]; then run journalctl --vacuum-size=10M; fi
  run_sh 'find /var/log -type f \( -name "*.gz" -o -name "*.[0-9]" -o -name "*.old" \) -delete; find /var/log -type f -exec truncate -s 0 {} +'
  run_sh "rm -rf /tmp/* /var/tmp/* /root/.cache /root/.bash_history '$U_HOME/.bash_history' '$U_HOME/.cache/pip' '$U_HOME/.npm/_cacache' '$U_HOME/.npm/_logs' '$TOOLS_DIR_U/dl'"
  # Maven: keep only the OWASP data inside ~/.m2 (it lives there); the rest is a download cache that ./mvnw refills.
  run_sh "if [ -d '$U_HOME/.m2/repository' ]; then find '$U_HOME/.m2/repository' -mindepth 1 -maxdepth 1 ! -name org -exec rm -rf {} +; find '$U_HOME/.m2/repository/org' -mindepth 1 -maxdepth 1 ! -name owasp -exec rm -rf {} + 2>/dev/null; find '$U_HOME/.m2/repository/org/owasp' -mindepth 1 -maxdepth 1 ! -name dependency-check-data -exec rm -rf {} + 2>/dev/null; fi; rm -rf '$TOOLS_DIR_U/odc-m2'"
  # Cursor CLI keeps every version it ever installed; keep only the newest one (the 'agent' symlink target).
  run_sh "d='$U_HOME/.local/share/cursor-agent/versions'; if [ -d \"\$d\" ]; then keep=\"\$(basename \"\$(dirname \"\$(readlink -f '$U_HOME/.local/bin/agent')\")\")\"; for v in \"\$d\"/*; do [ \"\$(basename \"\$v\")\" = \"\$keep\" ] || rm -rf \"\$v\"; done; fi"
  run_sh "rm -rf '$U_HOME/.gemini/antigravity-cli/log' '$U_HOME/.gemini/antigravity-cli/crashes' '$U_HOME/.gemini/antigravity-cli/cache'"
  # The prebuilt OWASP copy in ~/odc-data was only the source for prereqs.sh, which copied it into ~/.m2; keeping it
  # would put the same ~250 MB into the image twice.
  run rm -rf "$U_HOME/odc-data"
  if [ "$DEFER_ODC" = 1 ]; then
    say "--defer-odc: removing the OWASP data from the disk. After capture: rsync a prebuilt copy to $U_HOME/odc-data (else it is rebuilt from the NVD mirror, 30-60 min), then --after-image"
    run rm -rf "$ODC_DST_U"; run touch "$U_HOME/.odc-deferred"; run chown "$RUN_USER:$RUN_USER" "$U_HOME/.odc-deferred"; fi
  # No credential may be in the image (sign-ins come after capture).
  say "checking that no sign-in or token file exists"
  if [ "$DRY" = 0 ]; then local found
    # known sign-in files: agy (~/.gemini/antigravity-cli/antigravity-oauth-token), Cursor stored login
    # (~/.config/cursor/auth.json), git credentials; plus key/token text in the shell and launch files
    found="$(find "$U_HOME" /root -xdev \( -name 'antigravity-oauth-token' -o -name '.git-credentials' -o -name 'auth.json' \) \
             -not -path '*/node_modules/*' -not -path "$U_HOME/.local/share/cursor-agent/*" -not -path "$TOOLS_DIR_U/*" -not -path "$KIT_DIR/*" 2>/dev/null || true)
$(grep -lsE 'CURSOR_API_KEY=|GITHUB_TOKEN|GEMINI_API_KEY=|refresh_token|accessToken' "$U_HOME/.profile" "$U_HOME/.bashrc" "$U_HOME/launch.env" \
             "$U_HOME/.gemini/antigravity-cli/settings.json" /root/.bashrc /root/.profile 2>/dev/null || true)"
    found="$(printf '%s\n' "$found" | sed '/^$/d')"
    [ -z "$found" ] || die "credential-like files found; remove them (sign out) before capturing the image:
$found"; fi
  run sync
  if [ "$DRY" = 1 ]; then run df -h /; say "(dry run) would refuse when used > $(gb $LIMIT_BYTES)"; return 0; fi
  local used; used="$(used_bytes)"; df -h / | tee -a "$LOG_DIR/pre-image.txt"
  say "disk used on /: $(gb "$used") (limit for the image: $(gb $LIMIT_BYTES))" | tee -a "$LOG_DIR/pre-image.txt"
  if [ "$used" -gt "$LIMIT_BYTES" ]; then
    echo "=================================================================================" >&2
    echo " IMAGE TOO BIG: $(gb "$used") used on / > $(gb $LIMIT_BYTES). Do NOT capture the image." >&2
    [ "$DEFER_ODC" = 1 ] || echo " Try: bash $0 --pre-image --defer-odc   (moves the OWASP data, ~250 MB, to after capture)" >&2
    echo " Otherwise tell Marlon the size before deleting anything else." >&2
    echo "=================================================================================" >&2
    exit 3; fi
  say "OK: under the limit. Power off and capture the image now (before any sign-in)."; }

# =====================================================================================================
if [ "$USER_PHASE" = 1 ]; then
  ODC_SRC_U="$ODC_SRC_IN"; user_phase; exit 0; fi
case "$MODE" in
  setup) setup_root;;
  pre-image) pre_image;;
  after-image) need_root; ODC_SRC_U=""; [ -s "$U_HOME/odc-data/odc.mv.db" ] && ODC_SRC_U="$U_HOME/odc-data"
               a=(); [ -z "$ODC_SRC_U" ] || a=(--odc-src "$ODC_SRC_U"); MODE_ARG=--after-image
               if [ "$DRY" = 1 ]; then HOME="$U_HOME" bash "$0" --user-phase --after-image --dry-run --user "$RUN_USER" "${a[@]}"
               else install -m 0755 "$0" "$SELF_COPY"; runuser -u "$RUN_USER" -- env -i HOME="$U_HOME" USER="$RUN_USER" LANG=C.UTF-8 TZ=Asia/Manila \
                      PATH="$U_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" bash "$SELF_COPY" --user-phase "$MODE_ARG" --user "$RUN_USER" "${a[@]}"; fi;;
esac
