#!/usr/bin/env bash
# record.sh — toggle a screen recording with wf-recorder.
#   toggle : stop the running recording, or start one (focused monitor -> ~/videos)
# The recording is announced with notify-send, which our Quickshell
# NotificationServer shows in the notification center. The bar's Recorder.qml
# widget polls `pgrep wf-recorder` and shows a red REC dot while active.
set -euo pipefail

dir="$HOME/videos"
mkdir -p "$dir"

# Already recording? Send SIGINT so wf-recorder finalises the file, then bail.
if pgrep -x wf-recorder >/dev/null; then
  pkill -INT -x wf-recorder
  notify-send -a "Recorder" "Recording stopped" "Saved to ~/videos"
  exit 0
fi

file="$dir/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
mon="$(hyprctl monitors | awk '/^Monitor /{n=$2} /focused: yes/{print n; exit}')"

notify-send -a "Recorder" "Recording started" "${mon:-screen} · SUPER+SHIFT+R to stop"

# wf-recorder blocks until it gets SIGINT; detach so the keybind returns.
wf-recorder ${mon:+-o "$mon"} -f "$file" >/dev/null 2>&1 &
