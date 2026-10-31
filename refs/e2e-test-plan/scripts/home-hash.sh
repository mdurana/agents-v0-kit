#!/usr/bin/env bash
# home-hash.sh — hash the agent user's startup files, so a change between segments is caught before any relaunch
#   (kitfix-20261031-launch-env, review by Sakura 2026-10-31, approved by Marlon 13:25 Asia/Manila).
#   The agent runs as that user and can write these files; a login shell (`su - e2e`), bash, git, tmux and the harness
#   (tools.env) read them, so they could change PATH, PLAN_DIR, REQUIRE_FAIL_MODES or the lock variables.
# Usage:
#   bash home-hash.sh <home>                    print "<sha256|absent>  <relpath>" for every file in the list
#   bash home-hash.sh --record <file> <home>    as root at lock time (V3 procedure §4 step 9): write the list to <file>
#   bash home-hash.sh --check <file> <home>     compare with <file>: prints HOME-HASH-OK <n> files (exit 0), or one
#                                               HOME-CHANGED/HOME-ADDED/HOME-REMOVED line per difference (exit 1)
#   kitfix-20261031-n1: also .local/lib (the user site-packages: usercustomize.py, *.pth). Only files under a
#   __pycache__/ folder are left out of folder hashes (a cache refresh is not a change; Python never imports a
#   sourceless .pyc from there). Any other .pyc is hashed: a sourceless usercustomize.pyc runs (Sakura B-1).
#   N-1 follow-up (Sakura R-1): skipping __pycache__/ is safe only while the user site holds no .py a bare python3
#   imports (a tampered cached .pyc of a real module runs and is not hashed). So --record refuses (exit 2) when
#   .local/lib holds any *.py or *.pth outside __pycache__/: the V3 user site must be empty of Python source
#   (PyYAML from apt's python3-yaml, not pip --user). After that, any .py or .pth that appears is a HOME change.
#   N-1 final round: only .local/lib/python*/ is ever on sys.path, so only *.py/*.pth there refuse the record (a
#   node-gyp gyp_main.py under .local/lib/node_modules does not); all of .local/lib is still hashed.
set -u
FILES=".profile .bash_profile .bash_login .bashrc .bash_logout .bash_aliases .zshenv .zprofile .zshrc .inputrc
.tmux.conf .config/tmux/tmux.conf .gitconfig .config/git/config .config/git/attributes .ssh/rc .ssh/environment
.pam_environment .config/environment.d .config/e2e-secrets.env .local/agents-v0-tools/tools.env .local/lib"
list(){ local h="$1" f
  for f in $FILES; do
    if [ -d "$h/$f" ]; then printf '%s  %s/\n' "$(cd "$h/$f" && find . -type f ! -path '*/__pycache__/*' | LC_ALL=C sort | xargs -r sha256sum | sha256sum | cut -c1-64)" "$f"
    elif [ -e "$h/$f" ] || [ -L "$h/$f" ]; then printf '%s  %s\n' "$(sha256sum < "$h/$f" | cut -c1-64)" "$f"
    else printf 'absent  %s\n' "$f"; fi
  done; }
case "${1:-}" in
  --record) [ $# = 3 ] || { echo "usage: $0 --record <file> <home>" >&2; exit 2; }
            src=""; [ ! -d "$3/.local/lib" ] || src="$(find "$3/.local/lib" -mindepth 1 -maxdepth 1 -name 'python*' \
                -exec find {} -type f \( -name '*.py' -o -name '*.pth' \) ! -path '*/__pycache__/*' \; 2>/dev/null | LC_ALL=C sort)"
            [ -z "$src" ] || { printf 'HOME-HASH REFUSED: %s/.local/lib/python* holds %s Python source or .pth file(s), first %s. Their cached bytecode under __pycache__/ is not hashed, so it could be swapped unseen. Remove the user-site packages (PyYAML comes from apt python3-yaml) and record again.\n' \
                "$3" "$(printf '%s\n' "$src" | wc -l | tr -d ' ')" "$(printf '%s\n' "$src" | head -n 1)"; exit 2; }
            (umask 022; list "$3" > "$2") || exit 2; echo "HOME-HASH recorded $(grep -vc '^absent' "$2") files of $3 in $2";;
  --check)  [ $# = 3 ] || { echo "usage: $0 --check <file> <home>" >&2; exit 2; }
            [ -s "$2" ] || { echo "HOME-HASH record missing: $2"; exit 1; }
            d="$(diff <(LC_ALL=C sort -k2 "$2") <(list "$3" | LC_ALL=C sort -k2) | awk '
                 /^[<>]/{s=$1; h=$2; f=$3; if(s=="<") old[f]=h; else new[f]=h}
                 END{for(f in old){ if(!(f in new)) continue
                       if(old[f]=="absent") print "HOME-ADDED " f; else if(new[f]=="absent") print "HOME-REMOVED " f; else print "HOME-CHANGED " f }
                     for(f in new) if(!(f in old)) print "HOME-NEW-NAME " f }' | LC_ALL=C sort)"
            if [ -z "$d" ]; then echo "HOME-HASH-OK $(grep -vc '^absent' "$2") files of $3 unchanged"; else printf '%s\n' "$d"; exit 1; fi;;
  -*)       echo "usage: $0 [--record|--check <file>] <home>" >&2; exit 2;;
  *)        [ -n "${1:-}" ] || { echo "usage: $0 <home>" >&2; exit 2; }; list "$1";;
esac
