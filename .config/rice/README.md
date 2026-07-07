# Rice transfer kit

Everything needed to move this Hyprland/Quickshell desktop to another Arch
machine (or rebuild this one).

## Moving to a new machine

On this machine:

```sh
bash ~/.config/rice/export.sh                    # configs only, or
bash ~/.config/rice/export.sh --with-wallpapers  # + ~/images/wallpapers
```

On the new machine (fresh Arch, user created, online):

```sh
tar xzf rice-*.tar.gz -C ~
bash ~/.config/rice/install.sh
```

Add wallpapers to `~/images/wallpapers`, adjust the hardware files below,
start Hyprland. Login shuffles a wallpaper and matugen themes the accents
from it — no manual theming step.

## What the tarball contains

| Path | What |
|---|---|
| `.config/quickshell/` | the whole shell: bar, launcher, control center, timers, notifications, scripts |
| `.config/hypr/` | Hyprland Lua config, hypridle/hyprlock |
| `.config/matugen/` | accent templates (`colors.json` → quickshell, `colors.lua` → borders, hyprlock) |
| `.config/kitty/` | terminal |
| `.config/wireplumber/…/50-bluetooth-fixes.conf` | SBC-XQ codec pin (Buds3 Pro static fix) |
| `.config/systemd/user/…` | quickshell service, 3 h wallpaper-shuffle timer |
| `.config/rice/` | this kit |

Not included: `~/.local/state/quickshell/` (per-machine state — regenerates),
system-level config (`/etc/coolercontrol`, iwd network profiles — redo those
per machine).

## HARDWARE NOTES (laptop especially)

* `~/.config/hypr/monitors.lua` — written for DP-2 (2560x1440) + HDMI-A-1.
* `~/.config/hypr/windowsAndWorkspaces.lua` — workspaces 1–5 on DP-2, 6 on
  HDMI-A-1. On a single-screen laptop, drop the split.
* **Brightness**: the desktop fakes brightness with hyprsunset gamma because
  the monitors have no backlight device. A laptop has a real one — rebind the
  brightness keys to `brightnessctl` and leave hyprsunset for night light only.
* **Fan/temp tile** (ControlCenter) reads desktop hwmon names (`k10temp`,
  `amdgpu`, …) from sysfs; on other silicon it degrades to blanks — adjust or
  hide the readout.
* **Night light schedule**: `nightLat`/`nightLon` in ControlCenter.qml
  (currently 51.0/10.0 ≈ central Germany).
* coolercontrol is desktop-only; skip it on the laptop
  (`packages-aur.txt` marks it).

## Why not Nix?

Nix/home-manager is exactly the tool whose *promise* is this kit — declarative
packages + dotfiles, reproducible anywhere. The catch: you'd rewrite the whole
setup as Nix expressions, matugen/quickshell hot-paths fight the read-only
store (generated files like `colors.json` need escape hatches), AUR packages
need overlays, and day-to-day tinkering gains a rebuild step. For one desktop
+ one laptop that are both Arch, a tarball + package manifests gives 90 % of
the value for 2 % of the ceremony. If the fleet ever grows past two machines,
revisit.

Worth doing instead: keep `~/.config/{quickshell,hypr,matugen,rice}` in a git
repo (`git init` + a private GitHub remote) so the laptop can `git pull` rice
improvements instead of re-importing tarballs.

## Keeping the manifests honest

After installing something new the rice depends on, add it to
`packages-repo.txt` / `packages-aur.txt`. Quick diff of what's explicitly
installed vs. the manifests:

```sh
comm -13 <(pacman -Qq | sort) <(grep -hvE '^\s*(#|$)' ~/.config/rice/packages-*.txt | sort)
```

(anything printed is listed here but not installed — stale or misspelled).
