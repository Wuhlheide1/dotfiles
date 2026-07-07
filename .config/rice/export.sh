#!/usr/bin/env bash
# export.sh — bundle the rice into a tarball you can carry to another machine.
#
#   bash ~/.config/rice/export.sh                    configs only
#   bash ~/.config/rice/export.sh --with-wallpapers  configs + ~/images/wallpapers
#
# The tarball is rooted at $HOME, so on the new machine you just:
#   tar xzf rice-*.tar.gz -C ~   &&   bash ~/.config/rice/install.sh
set -euo pipefail

out="$HOME/rice-$(hostnamectl hostname 2>/dev/null || hostname)-$(date +%F).tar.gz"
cd "$HOME"

paths=(
    .config/quickshell
    .config/hypr
    .config/matugen
    .config/kitty
    .config/rice
    .config/wireplumber/wireplumber.conf.d/50-bluetooth-fixes.conf
    .config/systemd/user/quickshell.service
    .config/systemd/user/wallpaper-shuffle.service
    .config/systemd/user/wallpaper-shuffle.timer
)
[ "${1:-}" = "--with-wallpapers" ] && paths+=( images/wallpapers )

# skip anything that doesn't exist rather than aborting the whole export
have=()
for p in "${paths[@]}"; do [ -e "$p" ] && have+=("$p") || echo "skip (missing): $p" >&2; done

tar czf "$out" "${have[@]}"
echo "wrote $out ($(du -h "$out" | cut -f1))"
