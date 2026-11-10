#!/usr/bin/env bash
# SUPER+ALT+L, a locked bind (works on the lock screen too).
#
# For the rare case that the lock screen died and shell-guard.sh did not bring
# it back: Hyprland then shows its "go to a TTY" screen. This starts the shell
# if none runs on this display and locks again, so you get the password prompt
# back with every window still open (misc:allow_session_lock_restore). With a
# healthy shell it simply locks. `qs -n` refuses a second shell, so pressing it
# while shell-guard restarts the shell does no harm.
set -u

shell_pid() {
    local p
    for p in $(pgrep -x -f 'qs -c caelestia -n -d'); do
        grep -qxzF "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" "/proc/$p/environ" 2>/dev/null &&
            { echo "$p"; return; }
    done
}

pid=$(shell_pid)
if [ -z "$pid" ]; then
    caelestia shell -d >/dev/null 2>&1
    for _ in $(seq 40); do
        pid=$(shell_pid)
        [ -n "$pid" ] && qs ipc --pid "$pid" call lock isLocked >/dev/null 2>&1 && break
        sleep 0.5
    done
fi
[ -n "$pid" ] && qs ipc --pid "$pid" call lock lock
