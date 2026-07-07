# Feature list

Everything this desktop actually does, grouped by area. Written as a
reference for future-self (and the eventual laptop) — if you're wondering
"did I already build X", check here first.

Design language throughout: matugen derives **accent colors only** from the
current wallpaper (primary/secondary/tertiary/error) — surfaces, text and
outlines are fixed neutral greys, so the chrome stays calm no matter what's
on screen. Regular apps (kitty excepted) are **not** matugen-themed. Every
popup surface is opaque — no UI transparency, readability over aesthetics.
Attention cues (timer flash, etc.) are deliberately **gentle** — no fast
blinking, ever.

## Bar

Right-side status cluster: system tray → volume (scroll/click) → clock →
notification bell (badge = unread count) → control-center chevron. Pinned to
monitor `DP-2`. Caps/Num-Lock presses flash a bottom-center ON/OFF pill OSD.
Volume/brightness changes show a matching OSD. A red pulsing dot appears
while screen recording is active.

## Launcher (`SUPER+Space`)

Raycast-style unified search box. A single query box scores and ranks, in
one flat list:

- **Apps** — desktop entries, frecency-boosted (apps you launch often rank
  higher for the *same* query — it never resurrects an unrelated app).
- **Fuzzy fallback** — typo-tolerant subsequence matching (`frfx` → Firefox)
  when nothing else matches; ranks below every exact/substring hit.
- **Open windows** — switch to a running window instead of relaunching.
- **System actions** — lock, suspend, reboot, shutdown, logout, screenshot
  modes, screen recorder toggle, color picker, wallpaper picker/shuffle.
- **Calculator** — type a math expression, Enter copies the result.
- **Unit conversion** — `10km to mi`, `72f in c` (length/mass/volume/data/
  speed/temperature).
- **Emoji picker** — `:` prefix, ~1750 entries.
- **File search** — `~` prefix, live `find` (prunes caches/build dirs).
- **Web search** — bare 3+ char query gets a catch-all "Search web" row;
  prefixes pin a specific engine: `g` Google, `yt` YouTube, `aw` Arch Wiki,
  `gh` GitHub.
- **Timer quick-add** — `10m tea`, `1h30m`, `90s pasta` starts a timer
  directly from the launcher.
- **Quicklinks** (`~/.config/quickshell/quicklinks.json`) — bookmarks/folders
  that rank alongside actions.
- **Launcher extensions** (`~/.config/quickshell/launcher-ext/`) — drop in
  any executable that prints `name\tglyph\tcmd\tkeywords` rows; it becomes
  searchable. Contract documented in that directory's own README.

## Control Center (`SUPER+A`)

Phone-style squircle tile menu with **two pages** (scroll or click the dots
to switch):

- **Stats** (top, always visible): CPU/GPU/VRAM bars; RAM bar and a
  temp/VRAM text readout auto-appear only when something's actually hot.
- **Media player** — MPRIS: art, title/artist, prev/play-pause/next.
- **Volume + brightness** sliders (brightness is software GPU-gamma via
  hyprsunset — these monitors have no hardware backlight).
- **Page 1 tiles**: Wi-Fi (→ full picker sub-page: scan, connect w/ inline
  password, saved networks, live throughput), Bluetooth (→ sub-page: nearby
  devices, pair/trust/connect), Night Light (→ strength cycle, **auto
  sunset/sunrise schedule** — see below), Phone (→ Valent actions:
  share-dialog, media window, input remote, messages).
- **Page 2 tiles**: Game Mode (strips animations/blur/gaps/rounding — the
  toggle **survives** wallpaper-triggered `hyprctl reload`s), Keep Awake
  (parks hypridle), DND (manual, or automatic during screen recording /
  fullscreen — critical-urgency notifications like timers still get through
  even in DND), Microphone mute.
- **Mixer sub-page** — master + per-app volume streams, plus an **output
  device switcher** when more than one sink exists.
- **Update indicator** — repo + AUR pending-update count (checkupdates +
  `paru -Qua`), click opens an update terminal.
- **Fan/temp readout** — CPU/GPU temps + fan RPMs from sysfs hwmon.
- Power row: lock / suspend / reboot / shutdown / logout, with a confirm step.

## Notifications (`SUPER+N`, bell icon)

Quickshell *is* the notification daemon (dunst is masked). Toasts slide in
on arrival and auto-expire (hover pauses the timer); clicking a toast or
history entry runs the sender's default action and focuses its window
(makes things like "Discord: show message" actually work). History:

- **Persists across restarts** (`~/.local/state/quickshell/notifications.json`).
- **Groups by app** once a sender has 2+ entries (collapsed w/ "N more…").
- **Search field** appears once history is long enough to need it.
- Shows the sender's app icon or a letter-avatar fallback.
- **Do Not Disturb**: manual toggle, or automatic during screen recording /
  a fullscreen window — critical-urgency alerts (timers, alarms) bypass DND
  either way.

## Timers & Alarms (`SUPER+T`)

- Freeform duration input: `90s`, `5m30s`, `1h20m`, `1:30`, or a bare number
  (minutes).
- Alarms with day/time, repeat, and a soft snooze.
- "Important" timers/alarms get a **gentle screen-edge pulse** (two slow
  breathing fades tinted toward the wallpaper accent) instead of a jarring
  strobe, plus a critical-urgency system notification that plays a sound and
  reaches you even through DND or fullscreen.
- A Focus/Break Pomodoro chain (25 min focus → 5 min break, repeating).

## Clock & Calendar (click the bar clock)

Month-grid calendar (Monday-first, today highlighted, prev/next/jump-to-
today). Below the grid: a **weather line** (open-meteo, no API key —
current temp, today's high/low, rain chance if ≥20%), fetched only while the
flyout is open and no more than every 30 minutes. Below that, an events list
ready for Google Calendar ICS sync (not yet wired — needs the private iCal
URL).

## Clipboard history (`SUPER+V`)

`cliphist`-backed picker, themed like the launcher. Search, arrow/Enter
navigation. Image entries get real decoded thumbnails (not just "\[\[binary
data]]" text). Selecting an entry copies it **and auto-pastes** into whatever
window regains focus (`Ctrl+V`, or `Ctrl+Shift+V` in kitty).

## Wallpaper & theming

`scripts/wallpaper.sh` is the single source of truth — every caller (login,
the 3-hour shuffle timer, the picker, `SUPER+SHIFT+W`) goes through it:

- `set <path>` — one wallpaper on every monitor + re-theme.
- `random` — a **different** random image per monitor; the primary
  monitor's pick drives the accent theme.
- The 3-hour auto-shuffle **skips** while anything is fullscreen or Game
  Mode is on — it won't interrupt a game or movie; the next tick catches up.
- Re-theming **animates**: matugen writes accent values to a small JSON
  file, and `Colors.qml` watches it and glides every accent color over
  ~1 second in step with the wallpaper's own crossfade transition — nothing
  in the shell hard-reloads on a wallpaper change anymore.
- Wallpaper picker (`SUPER+W`) shows a "current" badge on whichever image is
  driving the theme, plus a Shuffle button.

**Night light**: strength cycles Off → Soft → Medium → Strong from the
control-center tile, but it also runs on an **automatic sunset/sunrise
schedule** (astronomically computed, no fixed clock times) — eases to Soft
at sunset, off at sunrise. A manual tile press overrides the schedule until
the next sunrise/sunset boundary.

## Screenshots & recording

- `Print` region, `Shift+Print` full monitor, `SUPER+Print` active window —
  all via grim+slurp, auto-copied to clipboard, saved to
  `~/images/screenshots/`.
- `SUPER+SHIFT+Print` — same capture piped into **satty** for annotation
  (arrows, text, blur, crop) before saving.
- Launcher action for **OCR**: capture a region, extract its text via
  tesseract, copy to clipboard.
- `SUPER+SHIFT+R` toggles screen recording (wf-recorder), with a choice of
  desktop audio / mic / both / none; red REC dot in the bar while active.

## Phone integration (Valent / KDE Connect protocol)

Runs headless in the background. Control-center Phone page for
share-dialog/media/input-remote/messages. **Drag a file onto the bar** to
send it straight to the phone. (Notification mirroring from the phone needs
a one-time toggle on the Android side — see `.config/rice/README.md`.)

## Keybind cheatsheet (`SUPER+K`)

Self-updating — it's parsed live from `~/.config/hypr/keybinds.lua`'s
comments, so it can never go stale. (Any new bind that should show up here
needs its trailing `-- description` comment added in the same edit.)

## System reliability (not Quickshell, but part of the rice)

- **Snapshots**: snapper (root + home, timeline retention) + snap-pac (auto
  snapshot around pacman transactions) + grub-btrfs (boot into any snapshot
  from the GRUB menu).
- **Backups**: restic to an external NTFS drive, daily via a systemd user
  timer, wrapped in `~/.local/bin/backup` (run/list/files/restore/check —
  restores always land in `~/restored/`, never in place).
- **Watchdog**: a daily `health-check` user timer checks snapper/restic/
  failed systemd units and notifies if anything silently broke.
- **Firewall**: ufw, enabled.

## Transfer kit (`~/.config/rice/`)

`export.sh` bundles the configs (optionally + wallpapers) into a tarball;
`install.sh` installs every package the rice needs (repo + AUR manifests,
validated to match what's actually installed here), bootstraps `paru` if
missing, enables the right systemd units, and masks dunst. `README.md`
documents per-machine hardware knobs (monitor layout, brightness method, fan
sensor names, night-light coordinates) for the planned laptop migration.
This git repo is the *other* transfer method — clone it directly into
`$HOME` on a new machine (see the root `README.md`).
