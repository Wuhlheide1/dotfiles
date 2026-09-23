#!/usr/bin/env bash
# import.sh — install downloaded WireGuard .conf files as named tunnels.
#
#   sudo bash ~/.config/rice/vpn/import.sh ~/Downloads/*.conf
#
# Surfshark names its downloads `de-fra.prod.surfshark.com.conf`, which makes a
# terrible interface name and a worse UI label. This trims that to `de-fra`,
# annotates the file with `# label:` / `# country:` comments that vpnctl reads,
# and installs it root-only. Re-running replaces an existing tunnel of the same
# name, so refreshing a rotated key is just another import.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo bash $0 <files...>" >&2; exit 1; }
[ "$#" -gt 0 ] || { echo "usage: sudo bash $0 <downloaded .conf files>" >&2; exit 2; }

DEST=/etc/wireguard
install -d -o root -g root -m 0700 "$DEST"

country_name() {
    case "$1" in
        de) echo DE ;; ch) echo CH ;; uk|gb) echo UK ;; nl) echo NL ;; fr) echo FR ;;
        us) echo US ;; at) echo AT ;; it) echo IT ;; es) echo ES ;; se) echo SE ;;
        no) echo NO ;; dk) echo DK ;; fi) echo FI ;; pl) echo PL ;; cz) echo CZ ;;
        be) echo BE ;; ie) echo IE ;; pt) echo PT ;; jp) echo JP ;; sg) echo SG ;;
        ca) echo CA ;; au) echo AU ;; *)  echo "${1^^}" ;;
    esac
}

city_name() {
    case "$1" in
        fra) echo Frankfurt ;;   ber) echo Berlin ;;      muc) echo Munich ;;
        dus) echo "Dusseldorf" ;; zur) echo Zurich ;;     lon) echo London ;;
        man) echo Manchester ;;  gla) echo Glasgow ;;     ams) echo Amsterdam ;;
        par) echo Paris ;;       mrs) echo Marseille ;;   vie) echo Vienna ;;
        mil) echo Milan ;;       rom) echo Rome ;;        mad) echo Madrid ;;
        bcn) echo Barcelona ;;   sto) echo Stockholm ;;   osl) echo Oslo ;;
        cph) echo Copenhagen ;;  hel) echo Helsinki ;;    waw) echo Warsaw ;;
        prg) echo Prague ;;      bru) echo Brussels ;;    dub) echo Dublin ;;
        lis) echo Lisbon ;;      tky|tok) echo Tokyo ;;   sgp) echo Singapore ;;
        tor) echo Toronto ;;     syd) echo Sydney ;;      nyc) echo "New York" ;;
        lax) echo "Los Angeles" ;; chi) echo Chicago ;;   dal) echo Dallas ;;
        mia) echo Miami ;;       sea) echo Seattle ;;     atl) echo Atlanta ;;
        buh) echo Bucharest ;;   bud) echo Budapest ;;    sof) echo Sofia ;;
        ath) echo Athens ;;      ist) echo Istanbul ;;    hkg) echo "Hong Kong" ;;
        sel) echo Seoul ;;       *) echo "${1^^}" ;;
    esac
}

n=0
for f in "$@"; do
    [ -f "$f" ] || { echo "skip (not a file): $f" >&2; continue; }

    # only accept something that is actually a WireGuard config
    if ! grep -q '^\[Interface\]' "$f" || ! grep -q '^\[Peer\]' "$f"; then
        echo "skip (not a WireGuard config): $f" >&2; continue
    fi

    base="$(basename "$f" .conf)"
    name="${base%%.*}"                       # de-fra.prod.surfshark.com -> de-fra
    name="$(tr '[:upper:]' '[:lower:]' <<<"$name" | tr -c 'a-z0-9_-' '-')"
    name="${name%%-}"
    # wg-quick interface names are capped at 15 characters
    name="${name:0:15}"
    [ -n "$name" ] || { echo "skip (cannot derive a name): $f" >&2; continue; }

    cc="${name%%-*}"; city="${name#*-}"
    label="$(city_name "$city")"
    country="$(country_name "$cc")"

    dst="$DEST/$name.conf"
    {
        printf '# label: %s\n# country: %s\n' "$label" "$country"
        # drop any annotations from a previous import so re-running is clean
        grep -v -E '^#[[:space:]]*(label|country):' "$f"
    } > "$dst"

    chown root:root "$dst"; chmod 0600 "$dst"
    echo "installed $name  ($label · $country)"
    n=$((n+1))
done

echo
echo "$n tunnel(s) installed in $DEST"
[ "$n" -gt 0 ] && echo "Open the ControlCenter -> VPN; they are listed by latency."
