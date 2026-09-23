#!/usr/bin/env bash
# install.sh — one-shot privileged setup for the WireGuard VPN stack.
# Idempotent: safe to re-run after adding new tunnels.
#
#   sudo bash ~/.config/rice/vpn/install.sh
#
# Installs: wireguard-tools + systemd-resolvconf, the vpnctl root helper, and a
# single narrow sudoers rule so the Quickshell toggle never prompts.
set -euo pipefail

USER_NAME="${SUDO_USER:-wuhlheide}"
SRC="$(dirname "$(realpath "$0")")"

[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo bash $0" >&2; exit 1; }

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# --- 1. packages ----------------------------------------------------------
# systemd-resolvconf matters: wg-quick shells out to `resolvconf` for the
# conf's DNS= line, and with systemd-resolved running that is the package that
# provides it. Without it, `wg-quick up` fails outright.
say "Packages"
need=()
pacman -Q wireguard-tools    >/dev/null 2>&1 || need+=(wireguard-tools)
pacman -Q systemd-resolvconf >/dev/null 2>&1 || need+=(systemd-resolvconf)
if [ "${#need[@]}" -gt 0 ]; then
    echo "installing: ${need[*]}"
    pacman -S --needed --noconfirm "${need[@]}"
else
    echo "already present: wireguard-tools systemd-resolvconf"
fi

# --- 2. the root helper ---------------------------------------------------
say "Root helper"
install -o root -g root -m 0755 "$SRC/vpnctl" /usr/local/bin/vpnctl
install -d -o root -g root -m 0700 /var/lib/vpnctl
echo "installed /usr/local/bin/vpnctl"

# --- 3. sudoers ------------------------------------------------------------
# Deliberately one binary, not a blanket rule over wg-quick/nft/systemctl:
# everything privileged is funnelled through vpnctl so this stays auditable.
say "Sudo rule"
tmp="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/vpnctl\n' "$USER_NAME" > "$tmp"
if visudo -cf "$tmp" >/dev/null; then
    install -o root -g root -m 0440 "$tmp" /etc/sudoers.d/10-vpnctl
    echo "installed /etc/sudoers.d/10-vpnctl for $USER_NAME"
else
    echo "REFUSED: generated sudoers rule failed validation" >&2
    rm -f "$tmp"; exit 1
fi
rm -f "$tmp"

# --- 4. config directory ---------------------------------------------------
say "Tunnel directory"
install -d -o root -g root -m 0700 /etc/wireguard
n=$(find /etc/wireguard -maxdepth 1 -name '*.conf' 2>/dev/null | wc -l)
chmod 0600 /etc/wireguard/*.conf 2>/dev/null || true
echo "/etc/wireguard ready — $n tunnel(s) present"

# --- 5. verify -------------------------------------------------------------
say "Verify"
ok=1
command -v wg >/dev/null      && echo "  ok   wg"            || { echo "  FAIL wg";      ok=0; }
command -v wg-quick >/dev/null && echo "  ok   wg-quick"     || { echo "  FAIL wg-quick"; ok=0; }
command -v resolvconf >/dev/null && echo "  ok   resolvconf" || { echo "  FAIL resolvconf"; ok=0; }
modprobe wireguard 2>/dev/null && echo "  ok   wireguard kernel module" || echo "  note wireguard module loads on demand"
sudo -u "$USER_NAME" sudo -n /usr/local/bin/vpnctl status >/dev/null 2>&1 \
    && echo "  ok   $USER_NAME can call vpnctl without a password" \
    || { echo "  FAIL passwordless vpnctl"; ok=0; }

if [ "$n" = 0 ]; then
    cat <<'MSG'

No tunnels yet. Get them from Surfshark:
  1. my.surfshark.com -> VPN -> Manual setup -> WireGuard
  2. Generate a key pair, then download the .conf for each location you want
  3. sudo bash ~/.config/rice/vpn/import.sh ~/Downloads/*.conf

MSG
fi

[ "$ok" = 1 ] && say "Done — open the ControlCenter, the VPN tile is live." \
              || { say "Finished with problems (see FAIL above)"; exit 1; }
