#!/usr/bin/env bash
# Brings the Caelestia shell back when it dies, and locks again.
#
# The shell also draws the lock screen. When it dies while the session is
# locked, Hyprland is left locked with no lock screen and shows its "go to a
# TTY" screen. With misc:allow_session_lock_restore (misc.lua) a new lock
# client may take over, so after a death this restarts the shell and locks:
# you come back to the password prompt with every window still open.
#
# Both deaths seen so far came from the monitors re-plugging on DPMS wake:
#   2026-10-24  SIGSEGV in Qt's window cleanup (systemd-coredump logs it)
#   2026-11-02  Hyprland cut the shell off for a protocol error ("error in
#               client communication (pid N)"); Qt then exits without a core
# Only those count; a shell stopped or restarted on purpose is left alone.
# At most 3 restarts in 10 minutes, so a shell that dies on start can't loop
# forever. One guard per Hyprland session, and it only watches the shell on
# its own display (a second login must not steal the guard).
# Started from autostart.lua.
set -u

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/caelestia-shell-guard-$WAYLAND_DISPLAY.lock"
flock -n 9 || exit 0    # one guard per session

shell_pid() {
    local p
    for p in $(pgrep -x -f 'qs -c caelestia -n -d'); do
        grep -qxzF "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" "/proc/$p/environ" 2>/dev/null &&
            { echo "$p"; return; }
    done
}
died() {
    journalctl -q -o cat --since=-60s -t systemd-coredump -g "^Process $1 \(qs\)" 2>/dev/null |
        grep -q 'terminated abnormally' ||
    journalctl -q -o cat --since=-60s -g "error in client communication \(pid $1\)" 2>/dev/null |
        grep -q .
}
restarts=()

while :; do
    pid=$(shell_pid)
    if [ -z "$pid" ]; then
        sleep 2
        continue
    fi
    tail --pid="$pid" -f /dev/null 9>&-    # wait for it to exit

    sleep 5
    [ -n "$(shell_pid)" ] && continue    # restarted on purpose (caelestia shell -r/-d)
    died "$pid" || continue

    now=$(date +%s)
    recent=()
    for t in "${restarts[@]}"; do
        (( now - t < 600 )) && recent+=("$t")
    done
    restarts=("${recent[@]}" "$now")
    if (( ${#restarts[@]} > 3 )); then
        notify-send -u critical "Caelestia shell" "Died 4 times in 10 minutes; not restarting it again. Run: caelestia shell -d"
        exit 1
    fi

    caelestia shell -d 9>&-
    for _ in $(seq 40); do
        new=$(shell_pid)
        [ -n "$new" ] && qs ipc --pid "$new" call lock isLocked >/dev/null 2>&1 && break
        sleep 0.5
    done
    [ -n "$new" ] && qs ipc --pid "$new" call lock lock
done
