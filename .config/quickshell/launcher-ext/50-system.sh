#!/usr/bin/env bash
# Example launcher extension: a few rice-maintenance rows.
# Format: name<TAB>glyph<TAB>command<TAB>keywords   (see README.md)
printf '%s\t%s\t%s\t%s\n' \
    "Restart Quickshell" $'' "systemctl --user restart quickshell" "shell bar reload fix wedge" \
    "Edit Quickshell Config" $'' "codium /home/wuhlheide/.config/quickshell" "rice qml shell bar" \
    "Edit Hyprland Config" $'' "codium /home/wuhlheide/.config/hypr" "rice keybinds lua"
