# dotfiles

Arch Linux · Hyprland · Quickshell — a hand-built desktop shell (not a fork of
an existing rice), themed entirely from the wallpaper via matugen.
See **[FEATURES.md](FEATURES.md)** for the full tour of what's actually in here.

This repo *is* `$HOME` — a bare repo, no separate checkout dir, no symlink
farm. Files sit exactly where every tool already expects them
(`~/.config/quickshell/`, `~/.config/hypr/`, …).

## How this works (bare repo, no stow/symlinks)

Normally `git init` creates a `.git/` folder inside your project and you
`cd` into that project to work on it. Here there's no project folder — the
project *is* your home directory, and a folder that large can't have a
`.git/` living inside it (every unrelated file in `$HOME` would show up as
untracked noise).

The fix: the git *directory* (the object database, refs, etc.) lives
somewhere else — `~/.dotfiles` — while the *work tree* (where git looks for
the actual files) is set to `$HOME`. Every git command needs to be told both
locations, which is exactly what this alias does (already in `.bashrc` and
`fish/config.fish`):

```sh
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

From then on, `dotfiles <anything>` is a normal git command that happens to
operate on `$HOME` instead of the current directory:

```sh
dotfiles status
dotfiles add .config/quickshell/Timers.qml
dotfiles commit -m "..."
dotfiles push
```

`status.showUntrackedFiles` is set to `no` in this repo's config, so
`dotfiles status` only ever shows files that are *already tracked* and
modified — not the thousand other things living in your home directory. To
track a new file for the first time, `add` it explicitly by path.

## Setting up a new machine

```sh
# 1. Arch install, base packages, get online, create your user — do this first
# 2. Clone the bare repo directly into place
git clone --bare https://github.com/Wuhlheide1/dotfiles.git $HOME/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
# 3. Populate $HOME from it (fails loudly if something in $HOME already
#    conflicts with a tracked file — move those aside first)
dotfiles checkout
dotfiles config status.showUntrackedFiles no
# 4. Install every package the rice depends on
bash ~/.config/rice/install.sh
# 5. Drop wallpapers into ~/images/wallpapers, then reboot into Hyprland.
```

If step 3 refuses because of pre-existing dotfiles (a stock `.bashrc`, etc.):

```sh
mkdir -p ~/.dotfiles-backup
dotfiles checkout 2>&1 | grep -E '^\s+\.' | xargs -I{} mv {} ~/.dotfiles-backup/{} --parents
dotfiles checkout
```

**Read the HARDWARE NOTES in `.config/rice/README.md` before first boot** —
monitor layout, brightness method, fan/temp readout, and night-light lat/lon
are all tuned for *this* desktop and need adjusting on different hardware
(the laptop, most likely).

## Daily workflow

```sh
dotfiles status              # what changed since last commit
dotfiles diff                # see the actual diff
dotfiles add <path>           # stage a specific file (never `add -A` — see below)
dotfiles commit -m "..."
dotfiles push
```

On the *other* machine, when you want this machine's latest changes:

```sh
dotfiles pull
```

**Never `dotfiles add -A` or `add .`** — this is your whole home directory;
a broad add can pick up something you didn't mean to track (credentials,
caches, one-off scratch files). Add paths explicitly. `git status` after
staging is cheap insurance.

### What's deliberately NOT tracked

`~/.gitignore` excludes matugen's *generated* output —
`.config/hypr/colors.lua` and `.config/hypr/hyprlock-colors.conf` — because
they're rewritten on every wallpaper change and would dirty the tree
constantly. `~/.config/hypr/lookAndFeel.lua` guards the `require("colors")`
with `pcall`, so a fresh clone (before the first wallpaper is ever set)
doesn't crash on the missing file.

Also never tracked, and never should be: `~/.local/state/quickshell/*`
(per-machine runtime state — night-light level, game-mode flag, current
wallpaper — regenerates on its own), `~/.config/restic/password` (chmod 600,
keep it off GitHub entirely, copy it out-of-band), and anything under
`~/.cache`.

## Related docs

- [FEATURES.md](FEATURES.md) — everything the shell actually does, organized by area
- `.config/rice/README.md` — package manifests, install/export scripts, per-machine hardware notes
- `.config/quickshell/TUTORIAL.md` — quickshell-specific developer notes (QML patterns, gotchas)
