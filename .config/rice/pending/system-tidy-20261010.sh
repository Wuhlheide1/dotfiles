#!/usr/bin/env bash
# One-shot system tidy, 2026-10-10. Run as your user: it calls sudo itself.
# Every step was dry-run first; pacman/paru still show you what they'll do.
set -euo pipefail
step() { printf '\n\e[1;36m── %s\e[0m\n' "$*"; }

step "1/5  Rebuild Qt plugins stuck on Qt 6.11 (this is the missing-icon fix)"
# qt6-base went 6.11 -> 6.12 on 2026-10-09. qtengine is a QPA theme plugin built
# on Qt's private API, so the 6.11 build loads but returns no icon theme:
# every tray/notification icon falls back to image-missing. Rebuilding fixes it.
paru -S --rebuild=yes qtengine caelestia-shell qt6-m3shapes-git

step "2/5  Full update (security fixes: gstreamer 1.28.8, python 3.14.8, browsers...)"
paru -Syu

step "3/5  Remove unused / duplicate packages + orphans"
sudo pacman -Rns \
  firefox waterfox-bin \
  overskride-bin bzmenu-bin gnome-bluetooth-3.0 \
  octopi arch-store htop vim pavucontrol-gtk3 wl-color-picker \
  kindle-for-arch suwayomi-server-bin \
  nvidia-utils lib32-nvidia-utils \
  wl-gammarelay-rs dunst polkit-kde-agent paru-debug
orphans=$(pacman -Qdtq || true)
[ -n "$orphans" ] && sudo pacman -Rns $orphans

step "4/5  Trim package cache (keep only the installed version)"
sudo paccache -rk1
sudo paccache -ruk0

step "5/5  Hardening"
# LLMNR answers name lookups from anyone on the LAN -- a classic spoofing
# vector. mDNS stays on: KDE Connect and printers use it.
printf '[Resolve]\nLLMNR=no\n' | sudo install -Dm644 /dev/stdin /etc/systemd/resolved.conf.d/10-no-llmnr.conf
# Hide kernel pointers from unprivileged users (was 0).
echo 'kernel.kptr_restrict = 2' | sudo install -Dm644 /dev/stdin /etc/sysctl.d/90-hardening.conf
sudo systemctl restart systemd-resolved
sudo sysctl --system >/dev/null
# CVE scanner for installed packages.
sudo pacman -S --needed arch-audit

step "Done. Restart the shell to load the rebuilt plugin:  caelestia shell -r"
