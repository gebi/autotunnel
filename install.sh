#!/bin/bash
# Install autotunnel and optionally set up a tunnel instance.
#
#   install.sh                         install unit + status script only
#   install.sh [-n] NAME [PORT [DEST]] also create ~/.config/autotunnel/NAME.conf
#
#   PORT  local SOCKS port or addr:port (default: first free port from 1080 up)
#   DEST  ssh destination, host alias or user@host (default: NAME)
#   -n    enable and start the tunnel right away
#   -f    overwrite an existing NAME.conf
set -eu

usage() { sed -n '3,11s/^# \{0,1\}//p' "$0"; exit "${1:-0}"; }

now=0 force=0
while getopts nfh opt; do
    case $opt in
        n) now=1 ;;
        f) force=1 ;;
        h) usage ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))
(( $# <= 3 )) || usage 1

here=$(cd "$(dirname "$0")" && pwd)
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
confdir="$cfg/autotunnel"

# --- base install (idempotent) ---
mkdir -p "$cfg/systemd/user" "$HOME/.local/bin" "$confdir"
ln -sfn "$here/autotunnel@.service" "$cfg/systemd/user/autotunnel@.service"
ln -sfn "$here/autotunnel-status" "$HOME/.local/bin/autotunnel-status"
systemctl --user daemon-reload

if (( $# == 0 )); then
    echo "installed. set up a tunnel with:  $0 [-n] NAME [PORT [DEST]]"
    exit 0
fi

# --- tunnel instance ---
name=$1 port=${2:-} dest=${3:-$1}

if [[ ! $name =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "invalid NAME '$name' (allowed: A-Z a-z 0-9 _ . -)" >&2
    exit 1
fi
conf="$confdir/$name.conf"
if [[ -e $conf && $force -eq 0 ]]; then
    echo "$conf already exists (use -f to overwrite)" >&2
    exit 1
fi

port_used() {  # $1 = port; used by another conf or currently listening
    local f
    for f in "$confdir"/*.conf; do
        [[ -f $f && $f != "$conf" ]] || continue
        grep -qE "^[[:space:]]*LISTEN=[\"']?([^:]*:)?$1[\"']?[[:space:]]*\$" "$f" && return 0
    done
    command -v ss >/dev/null && [[ -n $(ss -Hltn "sport = :$1") ]]
}

if [[ -z $port ]]; then
    port=1080
    while port_used "$port"; do port=$((port + 1)); done
fi
[[ $port == *:* ]] && listen=$port || listen="127.0.0.1:$port"

if [[ ! ${listen##*:} =~ ^[0-9]+$ ]] || (( ${listen##*:} < 1 || ${listen##*:} > 65535 )); then
    echo "invalid PORT '$port'" >&2
    exit 1
fi
if port_used "${listen##*:}"; then
    echo "warning: port ${listen##*:} is already used by another tunnel or listener" >&2
fi

printf 'LISTEN=%s\nDEST=%s\n' "$listen" "$dest" > "$conf"
echo "created $conf: -D $listen $dest"

if (( now )); then
    systemctl --user enable --now "autotunnel@$name"
    systemctl --user restart "autotunnel@$name"   # pick up a changed conf (-f)
else
    echo "start it with:  systemctl --user enable --now autotunnel@$name"
fi
