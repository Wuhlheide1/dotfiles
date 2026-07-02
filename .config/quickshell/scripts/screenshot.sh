#!/usr/bin/env bash
# screenshot.sh — grim/slurp capture for the Quickshell/Hyprland setup.
#   region  : drag-select an area (slurp), Esc to cancel
#   full    : the currently focused monitor only
#   window  : the active window's geometry (from hyprctl)
# In every mode the PNG is saved to ~/images/screenshots, copied to the
# clipboard, and announced with notify-send — which our Quickshell
# NotificationServer picks up and shows in the notification center.
set -euo pipefail

mode="${1:-region}"
dir="$HOME/images/screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

case "$mode" in
  region)
    # slurp exits non-zero when the user presses Esc -> bail out quietly.
    geom="$(slurp)" || exit 0
    grim -g "$geom" "$file"
    ;;
  full)
    mon="$(hyprctl monitors | awk '/^Monitor /{n=$2} /focused: yes/{print n; exit}')"
    grim ${mon:+-o "$mon"} "$file"
    ;;
  window)
    at="$(hyprctl activewindow   | awk -F': ' '/^[[:space:]]*at:/{print $2; exit}')"
    size="$(hyprctl activewindow | awk -F': ' '/^[[:space:]]*size:/{print $2; exit}')"
    if [ -z "$at" ] || [ -z "$size" ]; then
      grim "$file"                      # nothing focused -> whole output
    else
      grim -g "$at ${size/,/x}" "$file"  # grim wants "X,Y WxH"
    fi
    ;;
  *)
    echo "usage: $(basename "$0") region|full|window" >&2
    exit 1
    ;;
esac

wl-copy --type image/png < "$file"

notify-send -a "Screenshot" -i "$file" \
  "Screenshot saved" "${file/#$HOME/~} · copied to clipboard"
