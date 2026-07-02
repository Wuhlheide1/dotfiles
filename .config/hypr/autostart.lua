-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function ()
   hl.exec_cmd("awww-daemon")
   hl.exec_cmd("xrdb -merge ~/.Xresources")
   hl.exec_cmd("quickshell")
   -- software (GPU-gamma) brightness/temperature; safe, never touches the monitor
   hl.exec_cmd("hyprsunset --gamma 100 --temperature 6500")
   -- clipboard history: watch selections and store them for the SUPER+V picker
   hl.exec_cmd("wl-paste --type text --watch cliphist store")
   hl.exec_cmd("wl-paste --type image --watch cliphist store")
   -- idle management (dim/lock/dpms); config in ~/.config/hypr/hypridle.conf
   hl.exec_cmd("hypridle")
 end)

