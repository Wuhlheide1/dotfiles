-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function ()
   -- Hand the Wayland session env to systemd --user FIRST, then (re)start the
   -- units that need it. A bare `systemctl --user start` here used to race the
   -- env import and the polkit agent died with status=255 before the dialog
   -- code ever had a display. quickshell runs as a unit for Restart=on-failure.
   hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user restart hyprpolkitagent quickshell.service'")
   hl.exec_cmd("awww-daemon")
   -- fresh random wallpaper (+ matugen accent re-theme) each session; the
   -- script waits for awww-daemon, and `auto` debounces against the shuffle
   -- timer so a login can't double-fire it
   hl.exec_cmd("bash /home/wuhlheide/.config/quickshell/scripts/wallpaper.sh random auto")
   -- software (GPU-gamma) brightness/temperature; safe, never touches the monitor.
   -- Gamma resumes at the last level Brightness.qml persisted (100 on first run);
   -- temperature resumes the ControlCenter night-light state (6500 = off).
   -- nightlight file may hold "0" = "manually off tonight" — treat as 6500
   hl.exec_cmd("sh -c 'g=$(cat ~/.local/state/quickshell/brightness 2>/dev/null); t=$(cat ~/.local/state/quickshell/nightlight 2>/dev/null); [ \"$t\" -gt 0 ] 2>/dev/null || t=6500; hyprsunset --gamma \"${g:-100}\" --temperature \"$t\"'")
   -- clipboard history: watch selections and store them for the SUPER+V picker
   hl.exec_cmd("wl-paste --type text --watch cliphist store")
   hl.exec_cmd("wl-paste --type image --watch cliphist store")
   -- idle management (dim/lock/dpms); config in ~/.config/hypr/hypridle.conf
   hl.exec_cmd("hypridle")
   -- phone integration (KDE Connect protocol) running headless in the background.
   -- NOTE: kdeconnect(d) must NOT run at the same time — both want port 1716.
   hl.exec_cmd("valent --gapplication-service")
   -- polkit auth agent + quickshell start from the sequenced command above,
   -- after the session env import.
 end)

