#!/usr/bin/env bash
# screenshot.sh — grim/slurp capture for the Quickshell/Hyprland setup.
#   region  : drag-select an area (slurp), Esc to cancel
#   full    : the currently focused monitor only
#   window  : the active window's geometry (from hyprctl)
#   edit    : drag-select, then annotate in satty (its toolbar copies/saves)
#   ocr     : drag-select, OCR the region (tesseract) and copy the TEXT
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
  edit)
    geom="$(slurp)" || exit 0
    if ! command -v satty >/dev/null; then
      # graceful fallback: plain region shot + a hint to install satty
      grim -g "$geom" "$file"
      wl-copy --type image/png < "$file"
      notify-send -a "Screenshot" -i "$file" "satty not installed" \
        "Plain region captured. For annotation: sudo pacman -S satty"
      exit 0
    fi
    # satty owns copy/save from here (its toolbar); --early-exit closes it
    # after either action. Only notify if the user actually saved.
    grim -g "$geom" - | satty --filename - --output-filename "$file" \
      --early-exit --copy-command wl-copy
    [ -f "$file" ] && notify-send -a "Screenshot" -i "$file" \
      "Screenshot saved" "${file/#$HOME/~}"
    exit 0
    ;;
  ocr)
    geom="$(slurp)" || exit 0
    if ! command -v tesseract >/dev/null; then
      notify-send -a "Screenshot" "tesseract not installed" \
        "For OCR: sudo pacman -S tesseract tesseract-data-eng"
      exit 0
    fi
    txt="$(grim -g "$geom" - | tesseract stdin stdout 2>/dev/null)" || txt=""
    if [ -z "${txt//[[:space:]]/}" ]; then
      notify-send -a "Screenshot" "No text found" "OCR came back empty"
      exit 0
    fi
    printf '%s' "$txt" | wl-copy
    notify-send -a "Screenshot" "Text copied" "$(printf '%.120s' "$txt")"
    exit 0
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
    echo "usage: $(basename "$0") region|full|window|edit|ocr" >&2
    exit 1
    ;;
esac

wl-copy --type image/png < "$file"

notify-send -a "Screenshot" -i "$file" \
  "Screenshot saved" "${file/#$HOME/~} · copied to clipboard"
