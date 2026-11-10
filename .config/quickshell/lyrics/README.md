# Game lyrics

Spotify lyrics floating in the top left corner while a game is on screen.
Click-through, follows the Caelestia scheme, and nothing is mapped unless a game
is visible, Spotify is playing and there is a line to show.

    qs -c lyrics -d                          # autostart.lua
    qs -c lyrics kill                        # edits need a kill + start, it doesn't hot-reload
    qs -c lyrics ipc call lyrics toggle      # SUPER+Y
    qs -c lyrics ipc call lyrics status      # screen, track, source, lines, position

Position and sizes are the "Tuning" block at the top of `shell.qml`.

## Where things come from

- **Lyrics:** `~/.config/spicetify/Extensions/lyrics-bridge.js` runs inside Spotify
  and POSTs its own synced lyrics to `bridge.py` (127.0.0.1:48721, Spotify's origin
  only; `~/.config/spotify-flags.conf` disables Chromium's `LocalNetworkAccessChecks`
  prompt in CEF) on every song change. Songs Spotify has none for, or a Spotify not yet
  restarted with the extension, fall back to LRCLIB. Unsynced lyrics are skipped.
- **Track:** MPRIS.
- **Position:** `playerctl position` every 2 s plus a local clock, because seeks
  aren't announced anywhere QML can see.
- **Game:** a window on a visible workspace whose class matches `gameClasses` in
  `shell.qml` or a line of `~/.config/razer/games`, the file the razer daemon uses.

To remove the extension: `spicetify config extensions lyrics-bridge.js-`, then
`spicetify -n apply`.
