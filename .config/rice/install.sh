#!/usr/bin/env bash
# install.sh — set up the rice on a fresh Arch machine.
#
# Expected order on the new machine:
#   1. install Arch, create your user, get online
#   2. tar xzf rice-*.tar.gz -C ~        (puts the configs AND this script in place)
#   3. bash ~/.config/rice/install.sh    (packages, services, dirs)
#   4. drop some images into ~/images/wallpapers, reboot into Hyprland
#
# Idempotent: --needed everywhere, nothing overwrites the extracted configs.
# Read HARDWARE NOTES in README.md before first boot on a laptop.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

strip() { grep -vE '^\s*(#|$)' "$1"; }

echo "==> repo packages (sudo pacman)"
strip "$here/packages-repo.txt" | sudo pacman -S --needed --noconfirm -

if ! command -v paru >/dev/null; then
    echo "==> bootstrapping paru from the AUR"
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    ( cd "$tmp/paru-bin" && makepkg -si --noconfirm )
    rm -rf "$tmp"
fi

echo "==> AUR packages (paru)"
strip "$here/packages-aur.txt" | paru -S --needed --noconfirm -

echo "==> user services"
systemctl --user daemon-reload
systemctl --user enable wallpaper-shuffle.timer
# quickshell is THE notification daemon — dunst must never win the D-Bus name
systemctl --user mask dunst.service 2>/dev/null || true

echo "==> system services (sudo)"
sudo systemctl enable --now bluetooth.service
# Wi-Fi via iwd (the ControlCenter Wi-Fi page drives iwctl). Skip if this
# machine uses ethernet only.
sudo systemctl enable --now iwd.service || true

echo "==> directories"
mkdir -p ~/images/wallpapers ~/.local/state/quickshell ~/.cache/quickshell

cat <<'EOF'

Done. Before the first Hyprland start:
  * put a few images in ~/images/wallpapers (login picks one + themes accents)
  * on NEW HARDWARE edit:  ~/.config/hypr/monitors.lua  (outputs/resolutions)
    and ~/.config/hypr/windowsAndWorkspaces.lua (workspace<->monitor split is
    for the desktop's DP-2 + HDMI-A-1)
  * laptop: see HARDWARE NOTES in ~/.config/rice/README.md
EOF
