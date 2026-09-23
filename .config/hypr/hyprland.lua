---------------------
---- REQUIREMENTS ----
----------------------

require("monitors")
require("autostart")
require("environmentVariables")
require("lookAndFeel")
require("misc")
require("keybinds")
require("windowsAndWorkspaces")

-- The desktop shell is Caelestia (caelestia-shell, from the AUR). It is
-- installed system-wide at /etc/xdg/quickshell/caelestia and is NOT part of
-- this config: only autostart.lua (`caelestia shell -d`) and keybinds.lua
-- (`hl.dsp.global("caelestia:…")`) reach into it.
--   * shell settings   -> ~/.config/caelestia/shell.json
--   * generated colours -> ~/.config/hypr/scheme/current.lua (do not edit)
--   * list its shortcuts -> `caelestia shell -s`, `hyprctl globalshortcuts`
--   * restart it        -> `caelestia shell -r`
--
-- NOTE: Japanese IME + JIS layout config lives in the modules above, using the
-- Lua API Hyprland actually reads (bare `env`/`exec_once`/`input` globals here
-- are silently ignored):
--   * IME env vars      -> environmentVariables.lua  (hl.env)
--                          AND ~/.config/environment.d/im-modules.conf, which
--                          is the one that actually reaches child processes
--   * fcitx5 autostart  -> autostart.lua             (hl.exec_cmd)
--   * kb_layout = jp    -> misc.lua                  (hl.config)

-- HyprMod managed settings
require("hyprland-gui")
