#!/usr/bin/env bash
# phone.sh — thin gdbus wrapper for Valent (KDE Connect protocol), used by the
# ControlCenter phone page. Machine-friendly output, no GVariant parsing in QML.
#
#   status               one line per paired device:
#                        id <TAB> state <TAB> battery% <TAB> charging(0/1) <TAB> name
#                        (state is the Valent flag field: bit0 connected, bit1 paired)
#   action <id> <name>   activate a parameterless device action, e.g.
#                        findmyphone.ring, clipboard.push, clipboard.pull,
#                        sftp.browse, sms.sync, photo.request
#   share-text <id>      share one line of text/URL from stdin with the device
#   share-uris [id]      share files with the device; one URI per stdin line
#                        (id defaults to the first paired device)
set -uo pipefail

DEST=ca.andyholmes.Valent
ROOT=/ca/andyholmes/Valent

command -v gdbus >/dev/null || exit 0

case "${1:-status}" in
status)
    gdbus introspect --session --dest $DEST --object-path $ROOT/Device 2>/dev/null \
    | awk 'match($0, /^ *node ([0-9a-f]+) \{/, m) { print m[1] }' \
    | while read -r id; do
        [ -n "$id" ] || continue
        props="$(gdbus call --session --dest $DEST --object-path "$ROOT/Device/$id" \
                 --method org.freedesktop.DBus.Properties.GetAll ca.andyholmes.Valent.Device 2>/dev/null)"
        name="$(sed -n "s/.*'Name': <'\([^']*\)'>.*/\1/p" <<<"$props")"
        state="$(sed -n "s/.*'State': <uint32 \([0-9]*\)>.*/\1/p" <<<"$props")"
        batt="$(gdbus call --session --dest $DEST --object-path "$ROOT/Device/$id" \
                --method org.gtk.Actions.Describe battery.state 2>/dev/null)"
        pct="$(sed -n "s/.*'percentage': <\([0-9.]*\)>.*/\1/p" <<<"$batt")"
        chg=0; grep -q "'charging': <true>" <<<"$batt" && chg=1
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "${state:-0}" "${pct%.*}" "$chg" "${name:-Phone}"
      done
    ;;
action)
    gdbus call --session --dest $DEST --object-path "$ROOT/Device/${2:?id}" \
        --method org.gtk.Actions.Activate "${3:?action}" '[]' '{}' >/dev/null
    ;;
share-text)
    IFS= read -r txt || true
    [ -n "${txt:-}" ] || exit 0
    # minimal GVariant string escaping
    txt=${txt//\\/\\\\}; txt=${txt//\'/\\\'}
    gdbus call --session --dest $DEST --object-path "$ROOT/Device/${2:?id}" \
        --method org.gtk.Actions.Activate share.text "[<'$txt'>]" '{}' >/dev/null
    ;;
share-uris)
    id="${2:-}"
    if [ -z "$id" ]; then
        id="$(gdbus introspect --session --dest $DEST --object-path $ROOT/Device 2>/dev/null \
              | awk 'match($0, /^ *node ([0-9a-f]+) \{/, m) { print m[1]; exit }')"
    fi
    [ -n "$id" ] || exit 0
    uris=""; n=0
    while IFS= read -r u; do
        [ -n "$u" ] || continue
        u=${u//\\/\\\\}; u=${u//\'/\\\'}
        uris="$uris,'$u'"
        n=$((n+1))
    done
    [ "$n" -gt 0 ] || exit 0
    gdbus call --session --dest $DEST --object-path "$ROOT/Device/$id" \
        --method org.gtk.Actions.Activate share.uris "[<[${uris#,}]>]" '{}' >/dev/null \
      && notify-send -a "Phone" "Sending to phone" "$n file(s)"
    ;;
*)  echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
