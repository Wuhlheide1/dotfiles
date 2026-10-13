--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})


--------------------
---- WINDOW RULES --
--------------------
-- Small utility windows are floated and centred rather than shoved into the
-- tiling layout, where a 300x400 dialog would halve whatever you were reading.
hl.window_rule({
    name  = "float-utility-windows",
    match = { class = "^(pwvucontrol|pavucontrol|blueman-manager|nm-connection-editor|org\\.gnome\\.FileRoller|file-roller|Galculator|xdg-desktop-portal-gtk)$" },

    float  = true,
    center = true,
})

-- GTK/Qt file pickers, which report no useful class of their own.
-- The noun is required on purpose: a bare "^Open " would also float a browser
-- window titled "Open Source Project - Brave".
hl.window_rule({
    name  = "float-dialogs",
    match = { title = "^(Open|Save|Select|Choose|Export|Import)( a| an)? (File|Files|Folder|Directory|Image|Document|As)\\b.*" },

    float  = true,
    center = true,
})

-- Browser picture-in-picture: float it, pin it above everything and keep it
-- out of the tiling layout, so a video survives a workspace switch.
hl.window_rule({
    name  = "pip-float-pin",
    match = { title = "[Pp]icture[- ]in[- ][Pp]icture" },

    float  = true,
    pin    = true,
    size   = "640 360",
    no_shadow = true,
})

-- Tearing for fullscreen games only. general.allow_tearing is the master
-- switch; `immediate` is what actually opts a window in, so nothing else on
-- the desktop can tear. Worth having on a 280Hz panel where the latency
-- saving is real and the artifacts are not visible at that frame rate.
hl.window_rule({
    name  = "tearing-for-games",
    match = { class = "^(steam_app_\\d+|gamescope|Minecraft.*|com\\.mojang.*)$" },

    immediate = true,
})

--------------------
---- LAYER RULES ---
--------------------
-- Caelestia's surfaces are named caelestia-<name>. The shell blurs its own
-- backgrounds internally (it samples the wallpaper), so there is deliberately
-- NO blur rule here - adding one would blur it a second time. These rules match
-- what the upstream Caelestia Hyprland config ships.
hl.layer_rule({
    name  = "caelestia-no-anim",
    match = { namespace = "caelestia-(border-exclusion|area-picker|circle)" },
    no_anim = true,
})
hl.layer_rule({
    name  = "caelestia-fade",
    match = { namespace = "caelestia-(drawers|background)" },
    animation = "fade",
})

-- fuzzel, which Caelestia uses for the clipboard (SUPER+V) and emoji (SUPER+.)
-- pickers. This is the one surface the shell does not draw itself.
hl.layer_rule({
    name  = "fuzzel-popin",
    match = { namespace = "launcher" },
    animation = "popin 80%",
    blur      = true,
})

-- Fade these out instead of snapping them away
hl.layer_rule({ name = "hyprpicker-fade", match = { namespace = "hyprpicker" }, animation = "fade" })
hl.layer_rule({ name = "slurp-fade",      match = { namespace = "selection" },  animation = "fade" })

------------------------
---- WORKSPACE RULES ---
------------------------
-- Bind workspaces to monitors so SUPER + [1-6] is predictable.
-- See https://wiki.hypr.land/Configuring/Workspace-Rules/
--   Acer XF270H B (second) -> workspace 6 only (SUPER + 6)
--   MAG 272Q X28  (main)   -> workspaces 1..5
-- Matched by description, not by port, for the same reason as monitors.lua:
-- the MAG moved DP-2 -> DP-1 and every "DP-2" rule here silently went dead,
-- leaving the main screen with no workspaces of its own (it landed on 7).
-- Only workspaces 1-6 exist; 7-10 are unbound on purpose (keybinds.lua).
-- Without these rules a workspace opens on whichever monitor the cursor
-- is on, which is why switching felt random.
local mainMonitor   = "desc:Microstep MAG 272Q X28"
local secondMonitor = "desc:Acer Technologies Acer XF270H B"
for ws = 1, 6 do
    hl.workspace_rule({
        workspace  = tostring(ws),
        monitor    = (ws == 6) and secondMonitor or mainMonitor,
        -- Keep each monitor's home workspace alive even when empty,
        -- so every screen always owns a workspace.
        persistent = (ws == 1 or ws == 6),
    })
end
