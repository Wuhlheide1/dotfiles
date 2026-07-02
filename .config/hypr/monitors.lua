------------------
---- MONITORS ----
------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@144",
    position = "0x0",
    scale    = "1",
})

hl.monitor({
    output   = "DP-2",
    mode     = "2560x1440@280",
    position = "1920x0",
    scale    = "1",
})

-- Screen brightness

hl.bind("F1", hl.dsp.exec_cmd("brightnessctl s +5%"))
hl.bind("F2", hl.dsp.exec_cmd("brightnessctl s 5%-"))

