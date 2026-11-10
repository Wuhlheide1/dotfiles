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

-- IDLE POWER (2026-10-17): the RX 7800 XT can only switch its VRAM clock
-- inside a vertical blank. The MAG's stock 280Hz mode has a 0.38 ms blank and
-- the Acer's 144Hz mode 0.11 ms, both too short: VRAM sat at 1218 MHz and the
-- card idled at ~50 W. The MAG's own 240Hz EDID mode has a 0.97 ms blank and
-- the Acer gets a custom long-blank mode. Measured idle: 50 -> 35 W with both
-- monitors; the MAG alone at 240 drops to 10 W (45 W at 280).
-- Do NOT give the MAG a custom 280Hz modeline: trimming its hblank to fit a
-- longer vblank under the 1270 MHz dotclock limit shredded the picture into
-- shifted horizontal bands. The Acer at stock 144 keeps VRAM pinned even
-- with the MAG at 240.
-- To go back: mode = "2560x1440@280" / "1920x1080@144".
-- Check: grep '\*' /sys/class/drm/card1/device/pp_dpm_mclk (1218Mhz = stuck).
-- HyprMod: hyprland-gui.lua loads LAST; a monitor rule saved from HyprMod
-- overrides this file (it did for the Acer until 2026-10-17).

-- LAYOUT (2026-10-21): the MAG owns 0x0 and the Acer sits LEFT of it at a
-- negative x. With the Acer at 0x0 and the MAG at 1920x0, unplugging the Acer
-- left nothing at the origin. Wayland Chromium reports every window at 0,0 and
-- Brave refuses windows.create unless half the window is on a screen, so
-- Migaku's extension window (OPEN) silently failed whenever the Acer was off.
-- 0x0 is also what Wine/Proton treats as the primary screen.
-- Caveat: X11 (XWayland) menus on the Acer may misplace at negative x.
hl.monitor({
    output   = "desc:Acer Technologies Acer XF270H B", -- second, 1080p 144Hz
    -- stock timings, vtotal 1098 -> 1240 (0.90 ms vblank), 178.6 kHz of 180
    mode     = "modeline 367.11 1920 1944 1976 2056 1080 1083 1088 1240 +hsync +vsync",
    position = "-1920x0",
    scale    = "1",
})

-- MAG black at 240 Hz but fine at 60/120 = the DP link through the KVM, not
-- this file: 240 is the only mode that needs DSC at full link speed. Fixed
-- 2026-10-21 by reseating the DP cables at the KVM and the PC. Stopgap while
-- it's broken: mode "2560x1440@120" (VRAM pins, ~50 W idle).
--
-- HDR (2026-10-23): the MAG is a QD-OLED with HDR10 in its EDID (PQ, BT.2020,
-- ~465 nits). ON/OFF: SUPER + CTRL + H, works blind - press it if the screen
-- goes black. Saved to ~/.local/state/hdr ("on"/"off"; missing = SDR), so it
-- survives reloads and logins. From a TTY/SSH:
--   echo off > ~/.local/state/hdr && hyprctl eval 'hdr_set(false)'
-- HDR = 10-bit + PQ: more DP bandwidth through the same marginal KVM link.
-- SDR content (the whole desktop) is mapped into HDR; sdrbrightness /
-- sdrsaturation below tune how bright/saturated it looks there.
local HDR_STATE = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/hdr"

local function hdrSaved()
    local f = io.open(HDR_STATE)
    if not f then return false end
    local s = f:read("a")
    f:close()
    return s:match("^on") ~= nil
end

local function mag(hdr)
    hl.monitor({
        output        = "desc:Microstep MAG 272Q X28", -- main, 1440p 240Hz (EDID mode)
        mode          = "2560x1440@240",
        position      = "0x0",
        scale         = "1",
        bitdepth      = hdr and 10 or 8,
        cm            = hdr and "hdr" or "srgb",
        -- Tuned by eye 2026-10-23 on ~/Pictures/Calibration/hdr-check.png: 1.0 too dim,
        -- 2.5 good, 3.2 picked. Above ~2.6 SDR white runs into the panel's ~465-nit
        -- peak and the top near-white steps merge; the user prefers the brightness.
        -- cm_sdr_eotf = "srgb" made no visible difference to the near-blacks.
        sdrbrightness = 3.2,
        sdrsaturation = 1.15,
    })
    -- The hardware cursor plane skips HDR colour conversion (0.57.0): every
    -- cursor came out washed-out white, blacks lifted to grey. Software-drawn
    -- in HDR it goes through the same conversion as everything else
    -- (2026-11-01). 2 = auto, the default, for SDR.
    hl.config({ cursor = { no_hardware_cursors = hdr and 1 or 2 } })
end

function hdr_set(on)
    local f = io.open(HDR_STATE, "w")
    if f then
        f:write(on and "on\n" or "off\n")
        f:close()
    end
    mag(on)
    hl.notification.create({ text = "HDR " .. (on and "on" or "off"), timeout = 1500 })
end

mag(hdrSaved())
hl.bind("SUPER + CTRL + H", function() hdr_set(not hdrSaved()) end)

-- Brightness is real DDC/CI backlight control through Caelestia (ddcutil),
-- bound to SUPER+F1/F2 and the XF86 keys in keybinds.lua. The old hyprsunset
-- gamma workaround is gone.
