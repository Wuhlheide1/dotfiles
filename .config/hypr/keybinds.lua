---------------------
---- KEYBINDINGS ----
---------------------
--
-- Layout is unchanged from the pre-Caelestia rice wherever a key was already
-- taken; Caelestia's own defaults only fill keys that were free. Where the two
-- collided, this file wins (e.g. SUPER+Q is the terminal here, not close).
--
-- Two ways to reach the shell:
--   hl.dsp.global("caelestia:<name>")  -- instant, via the global-shortcut
--                                         protocol. `caelestia shell -s` or
--                                         `hyprctl globalshortcuts` lists them.
--   exec_cmd("caelestia <subcommand>") -- the CLI, for things with no shortcut.

local myPrograms = require("myPrograms")
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Shorthand for the shell's global shortcuts.
local function shell(name)
    return hl.dsp.global("caelestia:" .. name)
end

---------------
---- APPS ----
---------------
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(myPrograms.terminal))    -- terminal
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(myPrograms.fileManager)) -- file manager
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(myPrograms.browser))     -- browser
hl.bind(mainMod .. " + space", shell("launcher"))                   -- app launcher

-----------------
---- WINDOWS ----
-----------------
hl.bind(mainMod .. " + C", hl.dsp.window.close())                             -- close window
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())                        -- fullscreen
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())                            -- pseudo-tile
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))                      -- toggle split direction
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" })) -- toggle floating

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Move the active window with mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Resize the focused window by 10% a step (Caelestia default keys; these were free)
hl.bind(mainMod .. " + Minus",         hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true }) -- narrower
hl.bind(mainMod .. " + Equal",         hl.dsp.window.resize({ x = 100,  y = 0, relative = true }), { repeating = true }) -- wider
hl.bind(mainMod .. " + SHIFT + Minus", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true }) -- shorter
hl.bind(mainMod .. " + SHIFT + Equal", hl.dsp.window.resize({ x = 0, y = 100,  relative = true }), { repeating = true }) -- taller

hl.bind(mainMod .. " + ALT + P", hl.dsp.window.pin())       -- pin above everything (SUPER+P is pseudo-tile here)
hl.bind("CTRL + " .. mainMod .. " + Backslash", hl.dsp.window.center()) -- centre a floating window

-- Picture-in-picture: float the window, shrink it to a corner and pin it.
-- Caelestia's own dots do this with a helper from their hypr config, which is
-- not installed here (shell-only install), so it is spelled out.
hl.bind(mainMod .. " + ALT + Backslash", function()
    local win = hl.get_active_window()
    local mon = hl.get_active_monitor()
    if not (win and mon) then return end

    local w = math.floor(mon.width / mon.scale * 0.25)
    local h = math.floor(w * 9 / 16)
    local pad = 20

    local x = math.floor(mon.x + mon.width / mon.scale - w - pad)
    local y = math.floor(mon.y + mon.height / mon.scale - h - pad)

    if not win.floating then hl.dispatch(hl.dsp.window.float()) end
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false }))
    -- The Lua dispatcher table has no absolute-position move (only directional
    -- and by-workspace), so the corner placement goes through hyprctl.
    hl.dispatch(hl.dsp.exec_cmd(
        "hyprctl dispatch movewindowpixel exact " .. x .. " " .. y .. ",activewindow"
    ))
    hl.dispatch(hl.dsp.window.pin({ action = "on" }))
end)

-- Window groups (tabbed stacks) - all of these keys were free
hl.bind("ALT + TAB",         hl.dsp.window.cycle_next(),                { repeating = true }) -- next window in group
hl.bind("SHIFT + ALT + TAB", hl.dsp.window.cycle_next({ next = false }), { repeating = true }) -- previous window in group
hl.bind(mainMod .. " + Comma",         hl.dsp.group.toggle())      -- group / ungroup
hl.bind(mainMod .. " + SHIFT + Comma", hl.dsp.group.lock_active()) -- lock the group (stop it swallowing windows)
hl.bind(mainMod .. " + U", hl.dsp.window.move({ out_of_group = true })) -- pull window out of its group

--------------------
---- WORKSPACES ----
--------------------
-- Only workspaces 1-6 exist: the MAG (main) owns 1-5, the Acer owns 6.
-- Rules in windowsAndWorkspaces.lua. 7-10 stay unbound on purpose.
-- silent = true sends the window without following it, so focus stays put.
for i = 1, 6 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i, silent = true }))
end

-- Scratchpad. Named "special" rather than "magic" so Caelestia's bar shows it
-- with its star icon instead of a generic dot.
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("special"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:special" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

---------------
---- SHELL ----
---------------
-- Same keys as the old Quickshell rice, pointed at Caelestia's panels.
hl.bind(mainMod .. " + A", shell("utilities")) -- quick toggles / control centre
hl.bind(mainMod .. " + D", shell("dashboard")) -- dashboard
hl.bind(mainMod .. " + N", shell("sidebar"))   -- notifications & sidebar
hl.bind(mainMod .. " + K", shell("showall"))   -- show every panel at once
hl.bind(mainMod .. " + L", shell("lock"))      -- lock screen

-- Caelestia extras on keys that were free before
hl.bind("CTRL + ALT + Delete", shell("session"))    -- session menu (log out / reboot / …)
hl.bind("CTRL + ALT + C",      shell("clearNotifs"), { locked = true }) -- clear all notifications
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("systemctl suspend"), { locked = true }) -- sleep

-- Wallpaper: the launcher's `>wall` mode is the picker; this is the shuffle
-- that the old wallpaper-shuffle.timer used to do. Changing the wallpaper
-- re-themes the whole shell (Caelestia generates the scheme from the image).
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("caelestia wallpaper -r -N")) -- random wallpaper

-- Timers. Caelestia has no timer of its own, so these use systemd transient
-- timers for the timekeeping (accurate, survive a shell restart, listable with
-- `systemctl --user list-timers`) and fire a normal notification, so the alert
-- lands in the notification centre like anything else. Prompt accepts
-- "10m tea", "1h30m", "90s", or a bare number meaning minutes.
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("bash ~/.config/caelestia/scripts/timer.sh"))                 -- set a timer
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("bash ~/.config/caelestia/scripts/timer.sh cancel"))  -- cancel a timer

-- Clipboard history and emoji picker (fuzzel; pkill closes it if already open)
hl.bind(mainMod .. " + V",       hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
hl.bind(mainMod .. " + ALT + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d")) -- delete an entry
hl.bind(mainMod .. " + Period",  hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))     -- emoji / glyph picker

-------------------
---- UTILITIES ----
-------------------
-- Screenshots. The shell's picker replaces grim/slurp/satty; edits open in swappy.
hl.bind("Print",                       shell("screenshot"))                         -- select a region
hl.bind("SHIFT + Print",               hl.dsp.exec_cmd("caelestia screenshot"))     -- whole screen, straight to file
hl.bind(mainMod .. " + Print",         shell("screenshotFreeze"))                   -- freeze the screen, then select
hl.bind(mainMod .. " + SHIFT + Print", shell("screenshotClip"))                     -- select a region, to clipboard only

-- Screen recording (toggles: a second press stops)
hl.bind(mainMod .. " + SHIFT + R",       hl.dsp.exec_cmd("caelestia record"))       -- record screen
hl.bind(mainMod .. " + ALT + R",         hl.dsp.exec_cmd("caelestia record -s"))    -- record screen with sound
hl.bind(mainMod .. " + SHIFT + ALT + R", hl.dsp.exec_cmd("caelestia record -r"))    -- record a region

hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a")) -- colour picker

-----------------------------
---- MEDIA & HARDWARE KEYS --
-----------------------------
-- Volume. The shell draws the OSD; it watches PipeWire, so plain wpctl is enough.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")) -- mute (no dedicated key on this board)

-- Brightness. This is real backlight control over DDC/CI now (ddcutil), not the
-- old hyprsunset gamma trick, so it dims the panels themselves. SUPER+F1/F2 are
-- kept because desktop keyboards rarely carry XF86 brightness keys.
hl.bind("XF86MonBrightnessUp",   shell("brightnessUp"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", shell("brightnessDown"), { locked = true, repeating = true })
hl.bind(mainMod .. " + F2", shell("brightnessUp"),   { repeating = true })
hl.bind(mainMod .. " + F1", shell("brightnessDown"), { repeating = true })

-- Media keys, routed through the shell so its OSD and dashboard stay in sync
hl.bind("XF86AudioPlay",  shell("mediaToggle"), { locked = true })
hl.bind("XF86AudioPause", shell("mediaToggle"), { locked = true })
hl.bind("XF86AudioNext",  shell("mediaNext"),   { locked = true })
hl.bind("XF86AudioPrev",  shell("mediaPrev"),   { locked = true })
hl.bind("XF86AudioStop",  shell("mediaStop"),   { locked = true })
hl.bind("CTRL + " .. mainMod .. " + space", shell("mediaToggle")) -- play/pause without media keys
