-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    -- Hand the Wayland session env to systemd --user FIRST, then (re)start the
    -- units that need it. A bare `systemctl --user start` here used to race the
    -- env import and the polkit agent died with status=255 before the dialog
    -- code ever had a display.
    -- GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS are included too: without them,
    -- anything systemd/dbus-activation spawns never gets fcitx routing, even
    -- though hl.env() sets it for Hyprland's own children fine - those two
    -- environments don't sync automatically.
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE GTK_IM_MODULE QT_IM_MODULE XMODIFIERS; systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE GTK_IM_MODULE QT_IM_MODULE XMODIFIERS; systemctl --user restart hyprpolkitagent'")

    -- The shell. Draws the bar, wallpaper, notifications, OSD, launcher, lock
    -- screen and idle handling - hypridle/hyprlock/awww/matugen are all gone,
    -- Caelestia does the lot. Restart it by hand with `caelestia shell -r`.
    hl.exec_cmd("caelestia shell -d")

    -- Clipboard history: watch selections and store them for SUPER+V, which
    -- hands the same cliphist database to Caelestia's fuzzel picker.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Fcitx5 Japanese IME daemon. Needed for the JIS keys (英数/Henkan/Muhenkan/
    -- かな/半角全角) to do anything - they emit IME keysyms with no OS meaning
    -- unless an input method is listening. Input methods configured in
    -- ~/.config/fcitx5/profile (keyboard-jp + mozc). --replace is idempotent.
    hl.exec_cmd("fcitx5 -d --replace")

    -- Phone integration (KDE Connect protocol) running headless in the background.
    -- NOTE: kdeconnect(d) must NOT run at the same time - both want port 1716.
    hl.exec_cmd("valent --gapplication-service")

    -- Forward the play/pause/skip buttons on Bluetooth headphones to MPRIS, so
    -- the XM5's controls drive whatever is playing.
    hl.exec_cmd("mpris-proxy")
end)
