#!/usr/bin/env bash
# wallpaper.sh — single source of truth for applying wallpapers.
#   set <path>   one wallpaper on ALL outputs + accent re-theme
#   random       a DIFFERENT random image per output; theme follows DP-2
#
# Callers: WallpaperPicker.qml, the SUPER+SHIFT+W bind, autostart.lua (login
# shuffle, passes `auto`) and the wallpaper-shuffle systemd user timer.
# State: the image driving the theme is recorded in $STATE (read back by the
# picker's "current" badge and the no-repeat logic here).
set -euo pipefail

WALL_DIR="$HOME/images/wallpapers"
STATE_DIR="$HOME/.local/state/quickshell"
STATE="$STATE_DIR/wallpaper"

# right after login the awww daemon may still be coming up — wait for it
wait_daemon() {
    for _ in $(seq 1 25); do
        awww query >/dev/null 2>&1 && return 0
        sleep 0.2
    done
}

# regenerate accents from $1 and record it as the theme image.
# scheme-content keeps the wallpaper's REAL color as the accent (the old
# tonal-spot default pastel-shifted it); index 0 = most dominant color,
# which also skips the interactive selection prompt.
theme() {
    matugen image "$1" -t scheme-content --source-color-index 0
    hyprctl reload   # apply the regenerated colors.lua (border accents)
    # reload restores the un-gamed config — re-apply game mode if the Control
    # Center tile is on (keep this eval identical to ControlCenter.qml)
    if [ -f "$STATE_DIR/gamemode" ]; then
        hyprctl eval "hl.config({ general = { gaps_in = 0, gaps_out = 0 }, decoration = { rounding = 0, blur = { enabled = false } }, animations = { enabled = false } })" >/dev/null || true
    fi
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" > "$STATE"
}

case "${1:-}" in
    set)
        wait_daemon
        awww img "$2" --transition-type grow --transition-fps 60
        theme "$2"
        ;;
    random)
        # `random auto` (login shuffle, timer): debounce so automated callers
        # racing each other — or any reload loop — can't churn the wallpaper.
        # A plain `random` (Shuffle button, keybind) always acts.
        if [ "${2:-}" = "auto" ] && [ -f "$STATE" ] \
                && [ $(( $(date +%s) - $(stat -c %Y "$STATE") )) -lt 60 ]; then
            exit 0
        fi
        # the timer also stays quiet while anything is fullscreen (game, video)
        # or game mode is on — a mid-game re-theme + hyprctl reload is exactly
        # the interruption the shuffle exists to avoid. Next tick catches up.
        if [ "${2:-}" = "auto" ]; then
            if [ -f "$STATE_DIR/gamemode" ] || hyprctl clients -j 2>/dev/null \
                    | grep -q '"fullscreen": [^0]'; then
                exit 0
            fi
        fi
        current="$(cat "$STATE" 2>/dev/null || true)"
        mapfile -t all < <(find "$WALL_DIR" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
               -o -iname '*.webp' -o -iname '*.bmp' \) | sort)
        [ "${#all[@]}" -gt 0 ] || { echo "no wallpapers in $WALL_DIR" >&2; exit 1; }

        wait_daemon
        # one image per output ("` : DP-2: 2560x1440, ...`" query lines);
        # fall back to a single all-outputs image if the daemon is silent
        mapfile -t outs < <(awww query 2>/dev/null | awk -F': ' '{print $2}' | grep . || true)

        theme_img=""
        used=" $current "
        pick_one() {   # distinct from $used when the pool allows it
            local p
            if [ "${#all[@]}" -le $(( ${#outs[@]} + 1 )) ]; then
                p="${all[RANDOM % ${#all[@]}]}"
            else
                while :; do
                    p="${all[RANDOM % ${#all[@]}]}"
                    case "$used" in *" $p "*) continue ;; esac
                    break
                done
            fi
            used="$used$p "
            printf '%s' "$p"
        }

        if [ "${#outs[@]}" -eq 0 ]; then
            pick="$(pick_one)"
            awww img "$pick" --transition-type grow --transition-fps 60
            theme_img="$pick"
        else
            for out in "${outs[@]}"; do
                pick="$(pick_one)"
                awww img "$pick" -o "$out" --transition-type grow --transition-fps 60
                # DP-2 (primary) drives the theme; else first output wins
                if [ "$out" = "DP-2" ] || [ -z "$theme_img" ]; then
                    theme_img="$pick"
                fi
            done
        fi
        theme "$theme_img"
        ;;
    *)
        echo "usage: wallpaper.sh set <path> | random [auto]" >&2
        exit 2
        ;;
esac
