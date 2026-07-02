---------------------
---- KEYBINDINGS ----
---------------------
--
-- Lines matter to more than Hyprland here: scripts/keybinds-list.sh (Quickshell
-- cheatsheet, SUPER+K) parses this file.
--   `-- @ Name`              starts a cheatsheet category
--   trailing `-- text`       becomes the bind's description
--   `-- @bind KEYS | text`   adds an entry the parser can't derive (loops etc.)
-- Binds without a trailing comment stay functional but won't show in the sheet.

local myPrograms = require("myPrograms")
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- @ Apps
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(myPrograms.terminal))        -- terminal
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(myPrograms.fileManager))     -- file manager
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(myPrograms.browser))         -- browser
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("qs ipc call launcher toggle")) -- app launcher

-- @ Windows
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close()) -- close window
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())                  -- fullscreen
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())                      -- pseudo-tile
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))                -- toggle split direction
-- SUPER+V opens the clipboard-history picker; floating toggle moved to SUPER+SHIFT+V.
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" })) -- toggle floating

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))    -- focus left
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))   -- focus right
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))      -- focus up
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))    -- focus down

-- Move the active window with mainMod + SHIFT + arrow keys
-- @bind SUPER + SHIFT + ← → ↑ ↓ | move window
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true }) -- drag window
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }) -- resize window

-- @ Workspaces
-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
-- silent = true sends the window without following it, so your focus stays put.
-- @bind SUPER + 1…0 | switch to workspace 1–10
-- @bind SUPER + SHIFT + 1…0 | send window to workspace (focus stays)
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i, silent = true}))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic")) -- toggle scratchpad
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" })) -- send to scratchpad

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" })) -- next workspace
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" })) -- previous workspace

-- @ Tools
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("qs ipc call cheatsheet toggle")) -- this cheatsheet
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle")) -- clipboard history
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("qs ipc call wallpaper toggle")) -- wallpaper picker
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))                 -- lock screen

-- Screenshots via Quickshell IPC -> grim/slurp (scripts/screenshot.sh)
hl.bind("Print",                hl.dsp.exec_cmd("qs ipc call screenshot region"))  -- screenshot: select region
hl.bind("SHIFT + Print",        hl.dsp.exec_cmd("qs ipc call screenshot full"))    -- screenshot: whole monitor
hl.bind(mainMod .. " + Print",  hl.dsp.exec_cmd("qs ipc call screenshot win"))     -- screenshot: active window

-- Pick a colour anywhere on screen (hyprpicker) and copy the hex to the clipboard.
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a -f hex")) -- colour picker
-- Toggle screen recording (wf-recorder) via scripts/record.sh; bar shows a red dot while active.
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("~/.config/quickshell/scripts/record.sh toggle")) -- record screen

-- @ Media & hardware keys
-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true }) -- volume up
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true }) -- volume down
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true }) -- mute
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true }) -- mute microphone
-- Brightness via Quickshell -> hyprsunset (software gamma; this desktop has no backlight device)
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("qs ipc call brightness up"),   { locked = true, repeating = true }) -- brightness up
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("qs ipc call brightness down"), { locked = true, repeating = true }) -- brightness down

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true }) -- next track
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- play / pause
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- play / pause
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true }) -- previous track
