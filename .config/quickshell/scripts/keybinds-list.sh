#!/usr/bin/env bash
# Emits the keybind cheatsheet as TSV: CATEGORY <tab> KEYS <tab> DESCRIPTION.
# Source of truth is keybinds.lua itself — see the parsing notes at its top.
set -euo pipefail

awk '
function pretty(k) {
    gsub(/mouse:272/,  "LMB drag", k)
    gsub(/mouse:273/,  "RMB drag", k)
    gsub(/mouse_down/, "scroll ↓", k)
    gsub(/mouse_up/,   "scroll ↑", k)
    # arrow words only ever end a combo; anchored so "Brightness" survives
    sub(/ left$/,  " ←", k); sub(/ right$/, " →", k)
    sub(/ up$/,    " ↑", k); sub(/ down$/,  " ↓", k)
    gsub(/space/, "Space", k)
    gsub(/XF86MonBrightnessUp/,   "Brightness ↑", k)
    gsub(/XF86MonBrightnessDown/, "Brightness ↓", k)
    gsub(/XF86AudioRaiseVolume/,  "Vol ↑", k)
    gsub(/XF86AudioLowerVolume/,  "Vol ↓", k)
    gsub(/XF86AudioMicMute/,      "Mic mute", k)
    gsub(/XF86AudioMute/,         "Mute", k)
    gsub(/XF86AudioNext/,         "Next", k)
    gsub(/XF86AudioPrev/,         "Prev", k)
    gsub(/XF86AudioPause/,        "Play", k)
    gsub(/XF86AudioPlay/,         "Play", k)
    return k
}

/^-- @ /     { cat = substr($0, 6); next }

/^-- @bind / {
    line = substr($0, 10)
    n = index(line, " | ")
    if (n > 0) emit(cat, substr(line, 1, n - 1), substr(line, n + 3))
    next
}

/hl\.bind\(/ {
    # description = trailing comment after the bind
    if (!match($0, /\) *-- /)) next
    desc = substr($0, RSTART); sub(/^\) *-- /, "", desc)

    # keys: mainMod .. " + X"  ->  SUPER + X ; plain "X" stays as-is
    if (match($0, /mainMod \.\. " \+ [^"]+"/)) {
        keys = substr($0, RSTART + 15, RLENGTH - 16)
        keys = "SUPER + " keys
    } else if (match($0, /hl\.bind\("[^"]+"/)) {
        keys = substr($0, RSTART + 9, RLENGTH - 10)
    } else next

    emit(cat, pretty(keys), desc)
}

function emit(c, k, d) {
    if (seen[c "\t" k "\t" d]++) return   # XF86AudioPause/Play both map to Play
    print c "\t" k "\t" d
}
' "$HOME/.config/hypr/keybinds.lua"
