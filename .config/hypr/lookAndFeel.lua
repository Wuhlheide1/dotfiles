-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Colours come from Caelestia now. `caelestia scheme set …`, and every wallpaper
-- change, regenerate ~/.config/hypr/scheme/current.lua and reload Hyprland, so
-- the window borders follow the shell's palette automatically. (This replaces
-- the old matugen -> colors.lua pipeline, which is gone.)
--
-- The fallback keeps the config loadable before the first scheme is generated.
local ok, c = pcall(require, "scheme.current")
if not ok or type(c) ~= "table" then
    c = { primary = "9ccbfb", onSurfaceVariant = "c8c5d1", shadow = "000000" }
end

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        -- Caelestia's own proportions, so tiled windows sit on the same rhythm
        -- as the shell's cards and the bar's floating pill (its width is
        -- reserved separately via the layer's exclusive zone, so gaps_out is
        -- not doing double duty on the left edge).
        gaps_in  = 5,
        gaps_out = 10,

        border_size = 2,

        col = {
            -- Follows the wallpaper: `caelestia scheme` rewrites
            -- scheme/current.lua and reloads Hyprland on every change.
            active_border   = "rgba(" .. c.primary .. "e6)",
            inactive_border = "rgba(" .. c.onSurfaceVariant .. "22)",
        },

        resize_on_border = true,
        allow_tearing    = true, -- opt-in per window; see the gaming rule in windowsAndWorkspaces.lua

        layout = "dwindle",
    },

    decoration = {
        -- CONCENTRIC WITH CAELESTIA'S FRAME. The shell draws a rounded frame
        -- around the desktop and reserves space for it with the
        -- caelestia-border-exclusion layers, so windows nest inside a rounded
        -- hole. For the curves to be parallel rather than merely both-round,
        -- every corner has to share one arc centre:
        --
        --   border.thickness = 10   frame inner edge, from the screen edge
        --   border.rounding  = 25   frame corner radius
        --   => arc centre sits 10+25 = 35 from the screen corner
        --
        --   window content edge = thickness + gaps_out + border_size
        --                       = 10 + 10 + 2 = 22 from the screen corner
        --   => rounding = 35 - 22 = 13
        --
        -- Re-derive if you change gaps_out, border_size, or border.thickness /
        -- border.rounding in shell.json:
        --     rounding = (thickness + border.rounding) - (thickness + gaps_out + border_size)
        --              =  border.rounding - gaps_out - border_size
        rounding       = 13,
        -- 2.0 = a true circular arc. Caelestia's frame is an SDF rect with a
        -- plain radius (its `smoothing` is the blob-merge blend between open
        -- drawers, NOT corner smoothing), so anything above 2 would squircle
        -- the windows against round frame corners.
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 15,
            render_power = 3,
            color        = "rgba(" .. c.shadow .. "40)",
            color_inactive = "rgba(" .. c.shadow .. "20)",
        },

        blur = {
            enabled           = true,
            size              = 8,
            passes            = 2,
            vibrancy          = 0.1696,
            new_optimizations = true,

            -- Blur the surfaces that are NOT the shell: context menus, tooltips
            -- and - the one that actually matters here - the fcitx5 candidate
            -- window, so Japanese input matches everything else instead of
            -- floating on a flat grey slab.
            popups        = true,
            input_methods = true,
            special       = true,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })
-- Snappy near-critical spring for window open + tile-reflow: ~250ms settle with
-- a touch of life, vs "easy"'s soft ~500ms wobble that made open/close feel slow.
hl.curve("snappy",         { type = "spring", mass = 1, stiffness = 350, dampening = 32 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "snappy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "snappy",       style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})
