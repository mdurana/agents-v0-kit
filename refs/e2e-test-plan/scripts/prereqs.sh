#!/usr/bin/env bash
# prereqs.sh --check | --install
#   --check   : detect only, change nothing. Prints one line per tool and exits 0 (all present),
#               10 (something is missing that --install can fetch) or 20 (something needs a human / root).
#   --install : check first, then install ONLY what is missing, into $TOOLS_DIR (no root, no sudo, no package manager).
#               Idempotent: a second run installs nothing. Writes $TOOLS_DIR/tools.env (JAVA_HOME, NODE_HOME, PG_HOME, PATH).
# Line format:  PREREQ <name> <PRESENT|MISSING|INSTALLED|HUMAN|DEGRADED|FAILED> <detail>
set -u
. "$(dirname "$0")/env.sh"
MODE="${1:---check}"; case "$MODE" in --check|--install) ;; *) echo "usage: $0 --check|--install" >&2; exit 2;; esac
[ "$MODE" = --check ] || mkdir -p "$TOOLS_DIR/dl"
ARCH="$(uname -m)"; case "$ARCH" in x86_64) A_JDK=x64; A_NODE=x64; A_PG=amd64;; aarch64|arm64) A_JDK=aarch64; A_NODE=arm64; A_PG=arm64v8;; *) A_JDK=; A_NODE=; A_PG=;; esac
OS="$(uname -s)"; case "$OS" in Linux) OS_JDK=linux; OS_NODE=linux; OS_PG=linux;; Darwin) OS_JDK=mac; OS_NODE=darwin; OS_PG=darwin;; *) OS_JDK=; OS_NODE=; OS_PG=;; esac
missing=0; human=0
say(){
  local st="$2"
  if [ "${SKIP_NET_PREREQ:-0}" = 1 ] && [ "$st" != PRESENT ] && [ "$st" != INSTALLED ]; then
    case "$1" in node22|postgres17|odc-data|network) st=DEGRADED ;; esac
  fi
  printf 'PREREQ %-14s %-9s %s\n' "$1" "$st" "$3"
  case "$st" in MISSING) missing=1;; HUMAN|FAILED) human=1;; esac
}
dl(){ [ "${SKIP_NET_PREREQ:-0}" != 1 ] && curl -fsSL --retry 3 -m 900 -o "$2" "$1"; }
sha256_check(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum -c --quiet -; else shasum -a 256 -c --status -; fi; }
sha1_of(){ if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -d' ' -f1; else shasum -a 1 "$1" | cut -d' ' -f1; fi; }
sha512_of(){ if command -v sha512sum >/dev/null 2>&1; then sha512sum "$1" | cut -d' ' -f1; else shasum -a 512 "$1" | cut -d' ' -f1; fi; }
file_size(){ stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo 0; }
file_mtime(){ { stat -c %y "$1" 2>/dev/null || stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null || echo '?'; } | cut -c1-16; }
realpath_py(){ python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
run_timeout(){
  local sec="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$sec" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$sec" "$@"
  else python3 -c 'import subprocess,sys
try:
    r = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]))
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)' "$sec" "$@"; fi
}

case "$OS" in
  Linux|Darwin) say os PRESENT "$OS ($ARCH)" ;;
  *) say os HUMAN "this runner supports Linux and Darwin (found $OS)" ;;
esac

# --- base tools (never installed by this script: they come with any dev box) ---
for t in git jq python3 curl tar xz; do
  command -v "$t" >/dev/null 2>&1 && say "$t" PRESENT "$(command -v "$t")" || say "$t" HUMAN "not on PATH; install it"; done
if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
  say sha256 PRESENT "$(command -v sha256sum 2>/dev/null || command -v shasum)"
else
  say sha256 HUMAN "neither sha256sum nor shasum found on PATH"
fi
for t in timeout setsid; do
  command -v "$t" >/dev/null 2>&1 && say "$t" PRESENT "$(command -v "$t")" || say "$t" PRESENT "python3 fallback ($OS)"; done
# kitfix-20261031-n1 (Sakura R-1 / 7e91af9 nit): under V3 (the root-owned V3-REQUIRED marker next to scripts/, or
#   E2E_NO_USER_SITE=1, which setup-vm.sh sets on the e2e VM) PyYAML never goes into the user site: pip --user fills
#   ~/.local/lib/python*/, which home-hash --record refuses and whose cached bytecode is not hashed. It is HUMAN
#   (setup-vm and the procedure stop on it). Laptops keep the pip --user fallback.
pyyaml_prereq(){
  if python3 -c 'import yaml' 2>/dev/null; then say pyyaml PRESENT "python3 -c 'import yaml' ok"; return; fi
  if [ -e "$(dirname "$0")/../V3-REQUIRED" ] || [ "${E2E_NO_USER_SITE:-0}" = 1 ]; then
    say pyyaml HUMAN "needs apt-get install python3-yaml (as root); pip --user is not used under V3 (home-hash refuses a user site with Python source)"
  elif [ "$MODE" = --install ] && python3 -m pip install --user --quiet pyyaml 2>/dev/null; then say pyyaml INSTALLED "pip --user"
  else say pyyaml MISSING "python3 -m pip install --user pyyaml (Ubuntu 24.04 refuses pip --user: install the python3-yaml package once, as root)"; fi
}
pyyaml_prereq
python3 -c 'import docx' 2>/dev/null && say python-docx PRESENT "optional (report rendering only)" || say python-docx DEGRADED "optional; only needed to rebuild test-plan.docx"

# --- JDK 21 ---
java21(){ "$1/bin/java" -version 2>&1 | grep -q 'version "21'; }
JH=""
for c in "${JAVA_HOME:-}" "$TOOLS_DIR/jdk-21" "$TOOLS_DIR/jdk-21/Contents/Home" \
  $(ls -d /usr/lib/jvm/*21* /Library/Java/JavaVirtualMachines/*21*/Contents/Home /opt/local/Library/Java/JavaVirtualMachines/*21*/Contents/Home 2>/dev/null); do
  [ -n "$c" ] && [ -x "$c/bin/java" ] && java21 "$c" && { JH="$c"; break; }
done
if [ -z "$JH" ] && command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q 'version "21'; then JH="$(dirname "$(dirname "$(realpath_py "$(command -v java)")")")"; fi
if [ -n "$JH" ]; then say jdk21 PRESENT "$JH"
elif [ "$MODE" = --install ] && [ -n "$A_JDK" ] && [ -n "$OS_JDK" ]; then
  meta="$TOOLS_DIR/dl/jdk21.json"
  if dl "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$A_JDK&image_type=jdk&os=$OS_JDK&vendor=eclipse" "$meta" &&
     url="$(jq -r '.[0].binary.package.link' "$meta")" && sum="$(jq -r '.[0].binary.package.checksum' "$meta")" &&
     dl "$url" "$TOOLS_DIR/dl/jdk21.tgz" && echo "$sum  $TOOLS_DIR/dl/jdk21.tgz" | sha256_check ; then
    rm -rf "$TOOLS_DIR/jdk-21.tmp"; mkdir -p "$TOOLS_DIR/jdk-21.tmp" && tar -xzf "$TOOLS_DIR/dl/jdk21.tgz" -C "$TOOLS_DIR/jdk-21.tmp" --strip-components=1 &&
      mv "$TOOLS_DIR/jdk-21.tmp" "$TOOLS_DIR/jdk-21" &&
      { [ -d "$TOOLS_DIR/jdk-21/Contents/Home" ] && JH="$TOOLS_DIR/jdk-21/Contents/Home" || JH="$TOOLS_DIR/jdk-21"; } &&
      say jdk21 INSTALLED "$JH ($(jq -r '.[0].version.semver' "$meta"))"
  fi
  [ -n "$JH" ] || say jdk21 FAILED "download/verify from api.adoptium.net failed"
else say jdk21 MISSING "Temurin 21 into $TOOLS_DIR/jdk-21"; fi

# --- Node 22 (Vite 7 accepts >= 20.19, the kit CI uses 22) ---
node22(){ "$1" -e 'process.exit(+process.versions.node.split(".")[0]==22?0:1)' 2>/dev/null; }
NH=""
for nc in "$TOOLS_DIR/node-22/bin/node" "$(command -v node 2>/dev/null || true)" /opt/local/bin/node /usr/local/bin/node /opt/homebrew/bin/node $(ls -d "$HOME"/.nvm/versions/node/v22*/bin/node 2>/dev/null); do
  [ -n "$nc" ] && [ -x "$nc" ] && node22 "$nc" && { NH="$(dirname "$(dirname "$(realpath_py "$nc")")")"; break; }
done
if [ -n "$NH" ]; then say node22 PRESENT "$NH ($("$NH/bin/node" -v))"
elif [ "$MODE" = --install ] && [ -n "$A_NODE" ] && [ -n "$OS_NODE" ]; then
  base=https://nodejs.org/dist/latest-v22.x
  ext="tar.xz"; [ "$OS_NODE" = darwin ] && ext="tar.gz"
  if dl "$base/SHASUMS256.txt" "$TOOLS_DIR/dl/node-SHASUMS256.txt" &&
     f="$(awk -v a="$OS_NODE-$A_NODE.$ext" '$2 ~ a"$" {print $2; exit}' "$TOOLS_DIR/dl/node-SHASUMS256.txt")" && [ -n "$f" ] &&
     dl "$base/$f" "$TOOLS_DIR/dl/$f" && (cd "$TOOLS_DIR/dl" && grep " $f\$" node-SHASUMS256.txt | sha256_check); then
    rm -rf "$TOOLS_DIR/node-22.tmp"; mkdir -p "$TOOLS_DIR/node-22.tmp" && tar -xf "$TOOLS_DIR/dl/$f" -C "$TOOLS_DIR/node-22.tmp" --strip-components=1 &&
      mv "$TOOLS_DIR/node-22.tmp" "$TOOLS_DIR/node-22" && NH="$TOOLS_DIR/node-22" && say node22 INSTALLED "$NH ($f)"
  fi
  [ -n "$NH" ] || say node22 FAILED "download/verify from nodejs.org failed"
else say node22 MISSING "Node 22 into $TOOLS_DIR/node-22 (found $(node -v 2>/dev/null || echo none))"; fi

# --- portable PostgreSQL 17 (initdb + pg_ctl, no root) ---
PGH=""
for c in "${PG_HOME:-}" "$TOOLS_DIR/postgresql-17" $(ls -d /workspace/tools/postgresql-17* "$HOME"/tools/postgresql-17* /opt/local/lib/postgresql1[567]* /opt/homebrew/opt/postgresql@1[567]* /usr/local/opt/postgresql@1[567]* 2>/dev/null); do
  [ -n "$c" ] && [ -x "$c/bin/initdb" ] && [ -x "$c/bin/pg_ctl" ] && "$c/bin/postgres" --version 2>/dev/null | grep -qE ' 1[567]\.' && { PGH="$c"; break; }; done
if [ -n "$PGH" ]; then say postgres17 PRESENT "$PGH ($("$PGH/bin/postgres" --version))"
elif [ "$MODE" = --install ] && [ -n "$A_PG" ] && [ -n "$OS_PG" ]; then
  v=17.2.0; [ "$OS_PG" = linux ] && v=17.11.0
  j="embedded-postgres-binaries-$OS_PG-$A_PG-$v.jar"; u="https://repo1.maven.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-$OS_PG-$A_PG/$v/$j"
  if dl "$u" "$TOOLS_DIR/dl/$j" && dl "$u.sha1" "$TOOLS_DIR/dl/$j.sha1" &&
     [ "$(sha1_of "$TOOLS_DIR/dl/$j")" = "$(tr -d ' \n' < "$TOOLS_DIR/dl/$j.sha1")" ]; then
    rm -rf "$TOOLS_DIR/pg.tmp"; mkdir -p "$TOOLS_DIR/pg.tmp" &&
      python3 -c 'import zipfile,sys;z=zipfile.ZipFile(sys.argv[1]);n=[x for x in z.namelist() if x.endswith(".txz")][0];open(sys.argv[2],"wb").write(z.read(n))' "$TOOLS_DIR/dl/$j" "$TOOLS_DIR/dl/pg.txz" &&
      tar -xJf "$TOOLS_DIR/dl/pg.txz" -C "$TOOLS_DIR/pg.tmp" && mv "$TOOLS_DIR/pg.tmp" "$TOOLS_DIR/postgresql-17" && PGH="$TOOLS_DIR/postgresql-17" &&
      say postgres17 INSTALLED "$PGH (zonky $v)"
  fi
  [ -n "$PGH" ] || say postgres17 FAILED "download/verify of $j from Maven Central failed"
else say postgres17 MISSING "zonky embedded-postgres-binaries into $TOOLS_DIR/postgresql-17"; fi

# --- OWASP dependency-check data (H2 DB used by ./mvnw -Pci-security) ---
odc_ok(){ [ "$(file_size "$ODC_DST/odc.mv.db")" -gt 100000000 ]; }
if odc_ok; then say odc-data PRESENT "$ODC_DST/odc.mv.db ($(du -h "$ODC_DST/odc.mv.db" | cut -f1), $(file_mtime "$ODC_DST/odc.mv.db"))"
# HARNESS-FIX 2026-10-29 (setup-vm.sh): ODC_DEFER=1 skips the OWASP data (about 250 MB) so a VM image stays under the
#   Linode image size limit; the data is installed after the image is captured (setup-vm.sh --after-image, or step 1).
elif [ "${ODC_DEFER:-0}" = 1 ]; then say odc-data DEFERRED "ODC_DEFER=1: install after image capture (setup-vm.sh --after-image or run step 1)"
elif [ "$MODE" = --install ]; then
  [ -e "$ODC_DST" ] && mv "$ODC_DST" "$ODC_DST.partial-$RUN_ID"   # never delete: keep the old dir
  mkdir -p "$ODC_DST"
  if [ -n "$ODC_SRC" ] && [ -s "$ODC_SRC/odc.mv.db" ]; then cp -a "$ODC_SRC"/. "$ODC_DST"/; fi
  if [ -n "$JH" ]; then   # refresh (or build from scratch) through the keyless NVD mirror with a user-dir Maven
    MV=3.9.9; MH="$TOOLS_DIR/apache-maven-$MV"
    if [ ! -x "$MH/bin/mvn" ]; then
      u="https://archive.apache.org/dist/maven/maven-3/$MV/binaries/apache-maven-$MV-bin.tar.gz"
      dl "$u" "$TOOLS_DIR/dl/maven.tgz" && dl "$u.sha512" "$TOOLS_DIR/dl/maven.tgz.sha512" &&
        [ "$(sha512_of "$TOOLS_DIR/dl/maven.tgz")" = "$(cut -d' ' -f1 "$TOOLS_DIR/dl/maven.tgz.sha512")" ] &&
        tar -xzf "$TOOLS_DIR/dl/maven.tgz" -C "$TOOLS_DIR"
    fi
    [ -x "$MH/bin/mvn" ] && JAVA_HOME="$JH" MAVEN_OPTS=-Xmx1536m "$MH/bin/mvn" -B -ntp -q -Dmaven.repo.local="$TOOLS_DIR/odc-m2" \
      org.owasp:dependency-check-maven:10.0.4:update-only -DnvdDatafeedUrl="$ODC_FEED" -DdataDirectory="$ODC_DST" -DossindexAnalyzerEnabled=false \
      > "$TOOLS_DIR/odc-update-$RUN_ID.log" 2>&1 || echo "odc refresh failed, see $TOOLS_DIR/odc-update-$RUN_ID.log" >&2
  fi
  odc_ok && say odc-data INSTALLED "$ODC_DST/odc.mv.db ($(du -h "$ODC_DST/odc.mv.db" | cut -f1))" || say odc-data FAILED "no usable odc.mv.db in $ODC_DST (needs JDK 21 + network, about 30-60 min from scratch)"
else say odc-data MISSING "copy ${ODC_SRC:-<none>} or build via the NVD mirror into $ODC_DST"; fi

# --- Agent driver (Antigravity / Cursor CLI): presence, auth, model ---
# HARNESS-FIX 2026-10-28: use the same resolve_driver as the run (env.sh), so step 1 checks the agent that will run.
DRV="$(resolve_driver)"
say agent-driver PRESENT "$DRV (AGENT_DRIVER=$AGENT_DRIVER)"
if [ "$DRV" = antigravity ]; then
  if [ -n "${AGENT_TURN_CMD:-}" ]; then
    say agent-cli PRESENT "antigravity custom driver ($AGENT_TURN_CMD)"
    # HARNESS-FIX 2026-10-29 (VM): the custom driver needs agy itself (run by agy-turn-loop.sh). Report its path and
    #   version; when it is missing say so here instead of failing later in the CAL-AUTH turn. Sign-in is still only
    #   proven by CAL-AUTH in step 1 (no agy command checks it without starting a model turn).
    if [ -x "${AGY_BIN:-}" ]; then say agy-bin PRESENT "$AGY_BIN $("$AGY_BIN" --version 2>/dev/null | head -1)"
    else say agy-bin HUMAN "agy not found (AGY_BIN=${AGY_BIN:-}); install: curl -fsSL https://antigravity.google/cli/install.sh | bash"; fi
    say agent-auth PRESENT "managed by Antigravity session / AGENT_TURN_CMD (proven by CAL-AUTH in step 1)"
    say agent-model PRESENT "${AGENT_MODEL:-inherit}"
  elif [ -x "${AGY_BIN:-}" ]; then
    say agent-cli PRESENT "$AGY_BIN $("$AGY_BIN" --version 2>/dev/null | head -1)"
    say agent-auth PRESENT "Antigravity IDE / agy session"
    say agent-model PRESENT "${AGENT_MODEL:-inherit}"
  elif [ -d "$HOME/.gemini/antigravity" ]; then
    say agent-cli PRESENT "Antigravity runtime ($HOME/.gemini/antigravity; set AGENT_TURN_CMD for external shell runner)"
    say agent-auth PRESENT "Antigravity runtime session"
    say agent-model PRESENT "${AGENT_MODEL:-inherit}"
  else
    say agent-cli HUMAN "neither Antigravity (agy / AGENT_TURN_CMD) nor Cursor agent CLI found"
  fi
else
  if [ ! -x "$AGENT_BIN" ] && [ "$MODE" = --install ]; then
    curl -fsS https://cursor.com/install | bash >/dev/null 2>&1 || true; AGENT_BIN="$HOME/.local/bin/agent"; fi
  if [ -x "$AGENT_BIN" ]; then
    say agent-cli PRESENT "$AGENT_BIN $("$AGENT_BIN" --version 2>/dev/null)"
    if st="$(run_timeout 60 "$AGENT_BIN" status 2>&1)" && ! printf '%s' "$st" | grep -qiE 'not (logged|authenticated)|log ?in required'; then
      say agent-auth PRESENT "$( [ -n "$CURSOR_API_KEY" ] && echo 'CURSOR_API_KEY' || echo 'stored login' ): $(printf '%s' "$st" | head -1)"
    else say agent-auth HUMAN "not signed in: export CURSOR_API_KEY=<key> (preferred, non-interactive) or run 'agent login' once"; fi
    run_timeout 120 "$AGENT_BIN" --list-models 2>/dev/null | grep -qF -- "$AGENT_MODEL" && say agent-model PRESENT "$AGENT_MODEL" ||
      say agent-model HUMAN "model '$AGENT_MODEL' not listed by 'agent --list-models' (set AGENT_MODEL)"
  else say agent-cli HUMAN "agent CLI missing and 'curl https://cursor.com/install | bash' failed"; fi
fi

# --- container runtime (needs root to install; never installed here) ---
if (command -v docker >/dev/null && docker info >/dev/null 2>&1) || (command -v podman >/dev/null && podman info >/dev/null 2>&1); then
  say container PRESENT "$(command -v docker || command -v podman)"
else say container DEGRADED "no working docker/podman; P0-A AC-4 (container run) is scored DEGRADED; installing one needs root"; fi

# --- network + disk ---
curl -sfI -m 15 https://repo.maven.apache.org/maven2/ >/dev/null && curl -sfI -m 15 https://registry.npmjs.org/ >/dev/null &&
  say network PRESENT "Maven Central + npm reachable" || say network HUMAN "Maven Central or npm not reachable"
dd="$(dirname "$TEST_ROOT")"; while [ ! -d "$dd" ]; do dd="$(dirname "$dd")"; done
free="$(df -Pk "$dd" | awk 'NR==2{print $4}')"
[ "$free" -ge 41943040 ] && say disk PRESENT "$((free/1048576)) GB free" || say disk HUMAN "need >= 40 GB free under $(dirname "$TEST_ROOT")"

if [ "$MODE" = --install ]; then
  { echo "# written by prereqs.sh $(TZ=Asia/Manila date '+%F %T') Asia/Manila"
    [ -n "$JH" ] && echo "export JAVA_HOME='$JH'"
    [ -n "$NH" ] && echo "export NODE_HOME='$NH'"
    [ -n "$PGH" ] && echo "export PG_HOME='$PGH'"
    echo "export TOOLS_PATH='${JH:+$JH/bin:}${NH:+$NH/bin:}${PGH:+$PGH/bin:}$HOME/.local/bin'"
  } > "$TOOLS_DIR/tools.env"
fi
[ "$human" = 1 ] && exit 20; [ "$missing" = 1 ] && exit 10; exit 0
