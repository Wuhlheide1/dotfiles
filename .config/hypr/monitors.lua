------------------
---- MONITORS ----
------------------

-- Matched by DESCRIPTION, not by port. The MAG used to sit on DP-2 and moved to
-- DP-1 (a replug is enough), which silently dropped its rule -> it fell back to
-- 2560x1440@60 with no workspaces bound. This file still said "DP-2" until the
-- Caelestia migration, so the main panel was running at 60Hz instead of 280Hz.
-- desc: follows the panel across ports; don't put port names back here.
-- Descriptions come from `hyprctl monitors` (the trailing serial is optional).
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.monitor({
    output   = "desc:Acer Technologies Acer XF270H B", -- second, 1080p 144Hz
    mode     = "1920x1080@144",
    position = "0x0",
    scale    = "1",
})

hl.monitor({
    output   = "desc:Microstep MAG 272Q X28", -- main, 1440p 280Hz
    mode     = "2560x1440@280",
    position = "1920x0",
    scale    = "1",
})

-- Brightness is real DDC/CI backlight control through Caelestia (ddcutil),
-- bound to SUPER+F1/F2 and the XF86 keys in keybinds.lua. The old hyprsunset
-- gamma workaround is gone.
