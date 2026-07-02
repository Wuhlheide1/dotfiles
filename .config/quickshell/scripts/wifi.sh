#!/usr/bin/env bash
# Thin iwctl wrapper for the ControlCenter Wi-Fi UI. All output is
# machine-friendly; iwctl's ANSI/table dressing is stripped here so the QML
# never has to parse it.
#
#   wifi.sh status            nobackend | nodev | off <dev> | on <dev> | connected <dev> <ssid>
#   wifi.sh list              TSV: connected(0/1) <tab> ssid <tab> security <tab> bars(0-4)
#   wifi.sh known             one known ssid per line
#   wifi.sh scan              trigger a scan (harmless if one is running)
#   wifi.sh power on|off
#   wifi.sh connect <ssid> [passphrase]
#   wifi.sh disconnect
#   wifi.sh forget <ssid>
set -uo pipefail

wdev() {
    local d
    for d in /sys/class/net/*; do
        [ -d "$d/wireless" ] && { basename "$d"; return 0; }
    done
    return 1
}

strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }

DEV="$(wdev || true)"

# every subcommand except status needs iwctl; degrade to a silent no-op
if [ "${1:-status}" != "status" ] && ! command -v iwctl >/dev/null; then
    exit 0
fi

case "${1:-status}" in
status)
    command -v iwctl >/dev/null || { echo nobackend; exit 0; }
    systemctl is-active --quiet iwd || { echo nobackend; exit 0; }
    [ -n "$DEV" ] || { echo nodev; exit 0; }
    show="$(iwctl device "$DEV" show 2>/dev/null | strip_ansi)"
    if ! grep -qE '^\s*Powered\s+on' <<<"$show"; then
        echo "off $DEV"; exit 0
    fi
    ssid="$(iwctl station "$DEV" show 2>/dev/null | strip_ansi \
            | awk '/Connected network/ { $1=""; $2=""; sub(/^ +/,""); print; exit }')"
    if [ -n "$ssid" ]; then echo "connected $DEV $ssid"; else echo "on $DEV"; fi
    ;;
list)
    [ -n "$DEV" ] || exit 0
    iwctl station "$DEV" get-networks 2>/dev/null | strip_ansi | awk '
        {
            line = $0
            conn = (line ~ /^ *> /) ? 1 : 0
            sub(/^ *>? */, "", line)
            # ssid may contain spaces; anchor on the known security keywords
            if (match(line, / (psk|sae|open|8021x|wep) +[*_]+ *$/)) {
                tail = substr(line, RSTART + 1)
                name = substr(line, 1, RSTART - 1); gsub(/ +$/, "", name)
                split(tail, a, / +/)
                bars = gsub(/\*/, "*", a[2])
                if (name != "") print conn "\t" name "\t" a[1] "\t" bars
            }
        }'
    ;;
known)
    iwctl known-networks list 2>/dev/null | strip_ansi | awk '
        {
            line = $0
            sub(/^ */, "", line)
            if (match(line, / (psk|sae|open|8021x|wep) /)) {
                name = substr(line, 1, RSTART - 1); gsub(/ +$/, "", name)
                if (name != "" && name != "Name") print name
            }
        }'
    ;;
scan)       [ -n "$DEV" ] && iwctl station "$DEV" scan >/dev/null 2>&1 || true ;;
power)      [ -n "$DEV" ] && iwctl device "$DEV" set-property Powered "${2:?on|off}" ;;
connect)
    ssid="${2:?ssid}"
    if [ -n "${3:-}" ]; then
        iwctl --passphrase "$3" station "$DEV" connect "$ssid"
    else
        iwctl station "$DEV" connect "$ssid"
    fi
    ;;
disconnect) [ -n "$DEV" ] && iwctl station "$DEV" disconnect ;;
forget)     iwctl known-networks "${2:?ssid}" forget ;;
*)          echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
