--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

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

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Bind workspaces to monitors so SUPER + [0-9] is predictable.
-- See https://wiki.hypr.land/Configuring/Workspace-Rules/
--   HDMI-A-1 (second) -> workspace 6 only (SUPER + 6)
--   DP-2     (main)   -> all the rest     (SUPER + 1..5, 7..9, 0)
-- Without these rules a workspace opens on whichever monitor the cursor
-- is on, which is why switching felt random.
for ws = 1, 6 do
    hl.workspace_rule({
        workspace  = tostring(ws),
        monitor    = (ws == 6) and "HDMI-A-1" or "DP-2",
        -- Keep each monitor's home workspace alive even when empty,
        -- so every screen always owns a workspace.
        persistent = (ws == 1 or ws == 6),
    })
end
