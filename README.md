# dotfiles

Arch · Hyprland · Quickshell rice. See **[FEATURES.md](FEATURES.md)** for
what it actually does.

## New machine setup

```sh
# 1. Install Arch, create your user, get online. Then:
git clone --bare https://github.com/Wuhlheide1/dotfiles.git ~/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# 2. Pull the files into place
dotfiles checkout
dotfiles config status.showUntrackedFiles no

# 3. Install everything the rice needs (packages, services)
bash ~/.config/rice/install.sh

# 4. Drop some images into ~/images/wallpapers, then reboot into Hyprland.
```

If step 2 complains about existing files (a stock `.bashrc` etc. conflicting
with a tracked one), move the conflicts out of the way first:

```sh
mkdir -p ~/.dotfiles-backup
dotfiles checkout 2>&1 | grep -E '^\s+\.' | xargs -I{} mv {} ~/.dotfiles-backup/{} --parents
dotfiles checkout
```

**Before first boot on new hardware**, open `.config/rice/README.md` and go
through the "HARDWARE NOTES" section — monitor layout, brightness method,
fan sensor names, and night-light coordinates are all tuned for the desktop
tower and need adjusting (laptop notes are already in there).

## Day to day

```sh
dotfiles status              # what changed
dotfiles add <path>          # stage a specific file — never `add -A` / `add .`
dotfiles commit -m "..."
dotfiles push
```

On the other machine, `dotfiles pull` to catch up.

## Docs

- [FEATURES.md](FEATURES.md) — full feature tour
- `.config/rice/README.md` — packages, install/export scripts, hardware notes
- `.config/quickshell/TUTORIAL.md` — QML dev notes

<details>
<summary>How the "no checkout folder" trick works, if you're curious</summary>

`dotfiles` is a git alias pointing at two flags: `--git-dir=~/.dotfiles`
(where the actual git history lives) and `--work-tree=$HOME` (where it reads
and writes files). So `dotfiles status/add/commit` are ordinary git commands
that just happen to operate directly on your home directory instead of a
project folder — nothing is symlinked, every file already lives where its
tool expects it.

`status.showUntrackedFiles no` keeps `dotfiles status` from listing every
unrelated file in `$HOME` — it only ever shows files already tracked.

Not tracked, on purpose: `.config/hypr/colors.lua` and
`.config/hypr/hyprlock-colors.conf` (matugen regenerates these on every
wallpaper change — see `~/.gitignore`), `~/.local/state/quickshell/*`
(per-machine runtime state, regenerates itself), and
`~/.config/restic/password` (keep off GitHub, copy it out-of-band).

</details>
