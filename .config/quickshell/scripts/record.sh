#!/usr/bin/env bash
# record.sh — toggle a screen recording with wf-recorder.
#   toggle [mode]  : stop the running recording, or start one (focused monitor -> ~/videos)
#   start  [mode]  : same as toggle but only ever starts
#   mode: none (default) | desktop | mic | both
# "both" mixes the default sink monitor + default source into a temporary
# null sink (recmix) and records its monitor; the modules are torn down on stop.
# The bar's Recorder.qml shows a red REC dot while active and offers the mode
# chooser on SUPER+SHIFT+R.
set -euo pipefail

dir="$HOME/videos"
mkdir -p "$dir"
state="${XDG_RUNTIME_DIR:-/tmp}/record-audio-modules"

stop() {
  # SIGINT so wf-recorder finalises the file
  pkill -INT -x wf-recorder || true
  if [ -f "$state" ]; then
    while read -r id; do pactl unload-module "$id" 2>/dev/null || true; done < "$state"
    rm -f "$state"
  fi
  notify-send -a "Recorder" "Recording stopped" "Saved to ~/videos"
}

if pgrep -x wf-recorder >/dev/null; then
  [ "${1:-toggle}" = "start" ] && exit 0   # already recording; nothing to start
  stop
  exit 0
fi

mode="${2:-none}"
file="$dir/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
mon="$(hyprctl monitors | awk '/^Monitor /{n=$2} /focused: yes/{print n; exit}')"

audio=()
case "$mode" in
  desktop) audio=(--audio="$(pactl get-default-sink).monitor") ;;
  mic)     audio=(--audio="$(pactl get-default-source)") ;;
  both)
    m1=$(pactl load-module module-null-sink sink_name=recmix sink_properties=device.description=RecordingMix)
    m2=$(pactl load-module module-loopback source="$(pactl get-default-sink).monitor" sink=recmix latency_msec=20)
    m3=$(pactl load-module module-loopback source="$(pactl get-default-source)" sink=recmix latency_msec=20)
    printf '%s\n' "$m1" "$m2" "$m3" > "$state"
    audio=(--audio=recmix.monitor)
    ;;
  none|*)  audio=() ;;
esac

label="$mode audio"; [ "$mode" = none ] && label="no audio"
notify-send -a "Recorder" "Recording started" "${mon:-screen} · $label · SUPER+SHIFT+R to stop"

# wf-recorder blocks until it gets SIGINT; detach so the caller returns.
wf-recorder ${mon:+-o "$mon"} "${audio[@]}" -f "$file" >/dev/null 2>&1 &
