#!/usr/bin/env bash
# escalation-check.sh — the agent user has no way to become root or reach a Docker daemon
#   (kitfix-20261031-escalation-none, review by Sai 2026-10-31, approved by Marlon 13:25 Asia/Manila).
# Usage:
#   bash escalation-check.sh [--record <file>] <user>   full check, as root (V3 procedure §4 step 9); with --record the
#                                                       output is also written to <file> (mode 644), which the
#                                                       launch preflight verifies (lib.sh escalation_none_ok)
#   bash escalation-check.sh --live <user>              the part any user can check (groups, sockets, listeners), run
#                                                       by the preflight at every launch
# Checks (each prints `ESC <name> ok …` or `ESC <name> HIT …`):
#   sudo     `sudo -l -U <user>` lists no rule (sudo absent is ok; anything unclear is a HIT)      [full only]
#   groups   `id -nG <user>` has none of sudo wheel admin docker lxd
#   doas     no line of /etc/doas.conf (if present) names the user or one of its groups          [full only]
#   polkit   no polkit rule (rules.d, localauthority) names the user or one of its groups       [full only]
#   sockets  no /var/run/docker.sock, /run/docker.sock or /run/user/<uid>/docker.sock
#   ports    nothing listens on TCP 2375 or 2376 (/proc/net/tcp and tcp6)
# Last line: `ESCALATION-NONE user=<u> uid=<n> mode=<full|live> at=<time> Asia/Manila host=<h>` (exit 0), or
#   `ESCALATION-FOUND user=<u> hits=<n> mode=…` (exit 1). Usage errors and a full check as non-root exit 2.
# ESC_ROOT=<dir> prefixes every file path (tests only; it also allows a full check as non-root). Never set it on the VM.
set -u
mode=full rec=""
while [ $# -gt 0 ]; do case "$1" in
  --live) mode=live; shift;; --record) rec="${2:-}"; shift 2;; -*) echo "usage: $0 [--live|--record <file>] <user>" >&2; exit 2;;
  *) break;; esac; done
u="${1:-}"; [ -n "$u" ] || { echo "usage: $0 [--live|--record <file>] <user>" >&2; exit 2; }
R="${ESC_ROOT:-}"
if [ "$mode" = full ] && [ -z "$R" ] && [ "$(id -u)" != 0 ]; then echo "ESC full check needs root (sudo -l -U, doas.conf, polkit rules)" >&2; exit 2; fi
uid="$(id -u "$u" 2>/dev/null)" || { echo "ESCALATION-FOUND user=$u hits=1 mode=$mode (no such user)"; exit 1; }
groups=" $(id -nG "$u" 2>/dev/null) "
hits=0 out=""
say(){ out="$out$1
"; case "$1" in *" HIT "*) hits=$((hits+1));; esac; }
if [ "$mode" = full ]; then
  if ! command -v sudo >/dev/null 2>&1; then say "ESC sudo ok (sudo not installed)"
  else s="$(LC_ALL=C sudo -n -l -U "$u" 2>&1)"
    case "$s" in
      *"may run the following commands"*) say "ESC sudo HIT sudo -l -U $u lists rules: $(printf '%s' "$s" | tr '\n' ' ' | cut -c1-200)";;
      *"is not allowed to run sudo"*) say "ESC sudo ok ($u is not allowed to run sudo)";;
      *) say "ESC sudo HIT unclear sudo -l -U $u output: $(printf '%s' "$s" | tr '\n' ' ' | cut -c1-200)";;
    esac; fi
fi
g=""; for x in sudo wheel admin docker lxd; do case "$groups" in *" $x "*) g="$g $x";; esac; done
[ -z "$g" ] && say "ESC groups ok (id -nG $u:${groups% })" || say "ESC groups HIT $u is in:$g"
# the user and its groups as words a rule can name: e2e, :e2e (doas), unix-user:e2e / unix-group:<g> (polkit)
pat="(^|[^A-Za-z0-9_.-])$u([^A-Za-z0-9_.-]|\$)"
for x in $groups; do pat="$pat|:$x([^A-Za-z0-9_.-]|\$)|unix-group:$x([^A-Za-z0-9_.-]|\$)|\"$x\""; done
if [ "$mode" = full ]; then
  if [ -e "$R/etc/doas.conf" ]; then
    h="$(grep -v '^[[:space:]]*#' "$R/etc/doas.conf" | grep -E -- "$pat" | head -3)"
    [ -z "$h" ] && say "ESC doas ok (/etc/doas.conf names neither $u nor its groups)" || say "ESC doas HIT /etc/doas.conf: $(printf '%s' "$h" | tr '\n' ' ')"
  else say "ESC doas ok (no /etc/doas.conf)"; fi
  h="$(for d in "$R/etc/polkit-1/rules.d" "$R/usr/share/polkit-1/rules.d" "$R/etc/polkit-1/localauthority" "$R/var/lib/polkit-1/localauthority"; do
         [ -d "$d" ] && grep -rlE -- "$pat" "$d" 2>/dev/null; done | head -3)"
  [ -z "$h" ] && say "ESC polkit ok (no rule names $u or its groups)" || say "ESC polkit HIT rules naming $u or its groups: $(printf '%s' "$h" | tr '\n' ' ')"
fi
h=""; for s in /var/run/docker.sock /run/docker.sock "/run/user/$uid/docker.sock"; do [ ! -e "$R$s" ] && [ ! -L "$R$s" ] || h="$h $s"; done
[ -z "$h" ] && say "ESC sockets ok (no docker.sock)" || say "ESC sockets HIT docker socket present:$h"
h="$(cat "$R/proc/net/tcp" "$R/proc/net/tcp6" 2>/dev/null | awk '$4=="0A"{n=split($2,a,":"); p=toupper(a[n]); if(p=="0947") print "2375"; if(p=="0948") print "2376"}' | sort -u | tr '\n' ' ')"
[ -z "$h" ] && say "ESC ports ok (nothing listens on 2375/2376)" || say "ESC ports HIT listening on: $h"
if [ "$hits" = 0 ]; then out="${out}ESCALATION-NONE user=$u uid=$uid mode=$mode at=$(TZ=Asia/Manila date '+%F %T') Asia/Manila host=$(hostname 2>/dev/null)"
else out="${out}ESCALATION-FOUND user=$u hits=$hits mode=$mode"; fi
printf '%s\n' "$out"
if [ -n "$rec" ]; then (umask 022; printf '%s\n' "$out" > "$rec") || { echo "cannot write $rec" >&2; exit 2; }; fi
[ "$hits" = 0 ]
