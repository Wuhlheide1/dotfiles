#!/usr/bin/env bash
# Timers for Caelestia, using systemd transient timers for the timekeeping and
# the shell's own notification daemon for the alert. No extra daemon runs: the
# timer exists only while it is pending, and `systemctl --user list-timers`
# shows them all.
#
#   timer.sh            -> prompt via fuzzel ("10m tea", "1h30m", "90s")
#   timer.sh 10m tea    -> set directly
#   timer.sh list       -> show pending timers
#   timer.sh cancel     -> pick one to cancel (fuzzel), or cancel all with -a
set -uo pipefail

UNIT_PREFIX="caelestia-timer"

# "1h30m" / "10m" / "90s" / "45" (bare = minutes) -> seconds
parse_duration() {
    local s=${1,,} total=0 num unit
    [[ $s =~ ^[0-9]+$ ]] && { echo $(( s * 60 )); return; }
    while [[ $s =~ ^([0-9]+)([hms])(.*)$ ]]; do
        num=${BASH_REMATCH[1]}; unit=${BASH_REMATCH[2]}; s=${BASH_REMATCH[3]}
        case $unit in
            h) total=$(( total + num * 3600 ));;
            m) total=$(( total + num * 60 ));;
            s) total=$(( total + num ));;
        esac
    done
    [[ -n $s ]] && return 1
    (( total > 0 )) && echo "$total"
}

human() {
    local t=$1
    (( t >= 3600 )) && { printf '%dh%02dm' $(( t / 3600 )) $(( (t % 3600) / 60 )); return; }
    (( t >= 60 )) && { printf '%dm' $(( t / 60 )); return; }
    printf '%ds' "$t"
}


case "${1:-}" in
  list)
      systemctl --user list-timers --all --no-pager "${UNIT_PREFIX}-*.timer" 2>/dev/null
      exit 0 ;;
  cancel)
      if [ "${2:-}" = "-a" ]; then
          mapfile -t units < <(systemctl --user list-units --no-legend --plain "${UNIT_PREFIX}-*.timer" 2>/dev/null | awk '{print $1}')
          [ ${#units[@]} -eq 0 ] && { notify-send -a Timers "No timers running" ; exit 0; }
          systemctl --user stop "${units[@]}" 2>/dev/null
          notify-send -a Timers "Cancelled ${#units[@]} timer(s)"
          exit 0
      fi
      mapfile -t units < <(systemctl --user list-units --no-legend --plain "${UNIT_PREFIX}-*.timer" 2>/dev/null | awk '{print $1}')
      [ ${#units[@]} -eq 0 ] && { notify-send -a Timers "No timers running"; exit 0; }
      pick=$(printf '%s\n' "${units[@]}" | sed "s/^${UNIT_PREFIX}-//;s/\.timer$//" | fuzzel --dmenu --prompt "cancel> ") || exit 0
      [ -n "$pick" ] && systemctl --user stop "${UNIT_PREFIX}-${pick}.timer" && notify-send -a Timers "Cancelled $pick"
      exit 0 ;;
esac

if [ $# -eq 0 ]; then
    input=$(: | fuzzel --dmenu --prompt "timer> " --lines 0) || exit 0
else
    input="$*"
fi
[ -n "${input// }" ] || exit 0

dur=${input%% *}
label=${input#* }
[ "$label" = "$input" ] && label="Timer"

secs=$(parse_duration "$dur") || { notify-send -u critical -a Timers "Bad duration" "Could not read '$dur'. Try 10m, 1h30m, 90s."; exit 1; }
[ -n "$secs" ] || { notify-send -u critical -a Timers "Bad duration" "Could not read '$dur'. Try 10m, 1h30m, 90s."; exit 1; }

slug=$(echo "$label" | tr -c '[:alnum:]' '-' | sed 's/-\+/-/g;s/^-//;s/-$//' | cut -c1-24)
[ -n "$slug" ] || slug="timer"
unit="${UNIT_PREFIX}-${slug}-$(date +%s)"

systemd-run --user --quiet \
    --unit="$unit" \
    --on-active="$secs" \
    --timer-property=AccuracySec=1s \
    --description="Caelestia timer: $label" \
    notify-send -u critical -a Timers -i alarm "$label" "$(human "$secs") elapsed" \
    || { notify-send -u critical -a Timers "Could not start timer"; exit 1; }

notify-send -a Timers -i timer "Timer set" "$label in $(human "$secs")"
