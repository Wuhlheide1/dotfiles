---------------
---- INPUT ----
---------------

-- Scheme colours, for the desktop background shown before the shell paints
-- its wallpaper (and behind any gap the wallpaper doesn't cover).
local ok, c = pcall(require, "scheme.current")
if not ok or type(c) ~= "table" then
    c = { background = "0c0e12" }
end

hl.config({
    input = {
-- Native JIS layout. Plain 英数(Caps)=Eisu_toggle (Mozc direct-input);
-- real Caps Lock is Shift+Caps. jp106 model documents the JIS keycode set.
kb_layout  = "jp",
kb_variant = "",
kb_model   = "jp106",
-- custom:zeha gives the <ZEHA> keycode (evdev 85 = what Wootility's "Lang 5"
-- sends) the Zenkaku_Hankaku keysym, so the E/J key left of 1 can reach fcitx5.
-- Defined in ~/.config/xkb/{rules/evdev,symbols/custom}; stock xkb leaves that
-- keycode with no usable keysym and inet(evdev) squats on it with F24.
-- custom:umlaut maps F13-F17 to ae/oe/ue/sz/euro, so the Wooting's Fn layer can
-- bind a/o/u/s/e to those keycodes and type German without leaving the JIS
-- layout. Defined in ~/.config/xkb/symbols/custom alongside zeha.
kb_options = "custom:zeha,custom:umlaut",
kb_rules   = "",

follow_mouse = 1,

sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

-- Faster than the stock 600ms/25Hz. On a 80HE this is the difference between
-- held arrow keys feeling sluggish and feeling instant; it matches what
-- Caelestia's own config ships.
repeat_delay = 250,
repeat_rate  = 35,

-- When a window closes, focus the one under the cursor rather than whatever
-- the layout decides. Stops focus jumping to the far side of the screen.
focus_on_close = 1,

touchpad = {
natural_scroll = false,
        },
    },

    binds = {
        -- No artificial delay between scroll-driven bind repeats, so
        -- SUPER+scroll through workspaces tracks the wheel 1:1.
        scroll_event_delay = 0,
    },
})

-- Warp the mouse cursor onto a workspace's monitor when switching to it,
-- so the pointer follows your focus across monitors.
hl.config({
    cursor = {
        warp_on_change_workspace = true,
    },
})

--------------
---- MISC ----
--------------

hl.config({
    misc = {
        -- Nothing should render before the shell does.
        disable_hyprland_logo     = true,
        disable_splash_rendering  = true,
        -- The void behind the wallpaper matches the scheme instead of flashing
        -- Hyprland's default blue-grey during a reload or monitor re-plug.
        background_color          = "rgb(" .. c.background .. ")",

        -- Let an app that asks for attention actually take focus (dialogs,
        -- "open in existing window" from the browser) instead of just marking
        -- the workspace urgent.
        focus_on_activate         = true,

        -- Animate manual resizes and mouse drags; without these, dragging a
        -- window is the one interaction on the desktop that snaps instead of
        -- easing, and it reads as a glitch next to everything else.
        animate_manual_resizes           = true,
        animate_mouse_windowdragging     = true,

        -- No window swallowing, deliberately: its exception list can only
        -- match the terminal's title, and Claude Code sets that to the session
        -- name, so anything Claude launched would hide the Claude terminal.
    },

    cursor = {
        -- The pointer disappears while you type and comes back on the next
        -- mouse move, so it never sits on top of the text you're writing.
        hide_on_key_press = true,
    },

    ecosystem = {
        -- No "what's new" / donation windows popping up after an update.
        no_update_news  = true,
        no_donation_nag = true,
    },

    xwayland = {
        -- All monitors are scale 1, so this costs nothing today, but it stops
        -- XWayland apps rendering blurry the moment a scaled display is added.
        force_zero_scaling = true,
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})
