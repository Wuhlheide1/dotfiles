---------------
---- INPUT ----
---------------

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
kb_options = "custom:zeha",
kb_rules   = "",

follow_mouse = 1,

sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

touchpad = {
natural_scroll = false,
        },
    },
})

-- Warp the mouse cursor onto a workspace's monitor when switching to it,
-- so the pointer follows your focus across monitors.
hl.config({
    cursor = {
        warp_on_change_workspace = true,
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

