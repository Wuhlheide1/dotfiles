#!/usr/bin/env bash
# Audit fixes, 2026-11-10: everything you said yes to in the Claude session
# that needs root. Run it in kitty as yourself (NOT with sudo in front):
#
#     bash ~/.config/rice/pending/audit-fixes-20261110.sh
#
# pacman and paru still show every transaction and wait for your yes.
# Running it again is harmless: finished steps say so and move on.
# Reboot at the end (fstab, zram and /boot apply at boot).
set -uo pipefail

say()  { printf '\n\033[1;36m── %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!\033[0m %s\n' "$*"; }
ask()  { local a; read -r -p "   $1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }
wait_closed() {  # $1 = process name, $2 = what to tell you
    while pgrep -x "$1" >/dev/null; do
        warn "$2 is running. Close it, then press Enter."
        read -r
    done
}

[ "$EUID" -eq 0 ] && { echo "Run this as yourself, not with sudo in front."; exit 1; }
me=$(id -un)
sudo -v || exit 1
# Keep sudo alive while paru builds, so you type the password once.
( while sleep 50; do kill -0 $$ 2>/dev/null || exit; sudo -n -v 2>/dev/null || exit; done ) &
keepalive=$!
trap 'kill $keepalive 2>/dev/null' EXIT


say "1/11  Login screen: close the passwordless-root hole"
# `sudo astra-airlock --sync` ran python3 as root with your HOME, so it loaded
# your own Python files as root. The theme hook now writes the login screen's
# colours and wallpaper itself (no sudo). The two Brave rules go too: nothing
# has used them since finish-setup step 1. The vpnctl rule stays (it is safe).
sudo bash -s <<'ROOT'
set -uo pipefail
found=0
for f in /etc/sudoers /etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    grep -qE 'astra-airlock|/etc/brave/policies' "$f" || continue
    found=1
    tmp=$(mktemp)
    grep -vE 'astra-airlock|/etc/brave/policies' "$f" > "$tmp"
    if ! visudo -cqf "$tmp"; then
        echo "   ! $f: the edited copy fails visudo, left it alone (tell Claude)"
        rm -f "$tmp"; continue
    fi
    bak="/root/sudoers-$(basename "$f").pre-20261110"
    cp -a "$f" "$bak"
    install -m 0440 -o root -g root "$tmp" "$f"
    rm -f "$tmp"
    if visudo -cq >/dev/null; then
        echo "   ✓ removed the airlock/Brave rules from $f (old copy: $bak)"
    else
        cp -a "$bak" "$f"
        echo "   ! full sudoers check failed after editing $f, restored it (tell Claude)"
    fi
done
[ "$found" = 1 ] || echo "   ✓ no airlock/Brave rules left"
ROOT
# A Python cache root wrote into your config through that hole.
if [ -d ~/.config/caelestia/cli-overlay/__pycache__ ]; then
    sudo rm -rf ~/.config/caelestia/cli-overlay/__pycache__ && ok "removed the root-owned __pycache__"
fi
# The login screen's cache entries become yours, so the hook can write them.
c=/var/cache/astra-airlock
sudo install -d -m 0755 "$c" "$c/schemes" "$c/schemes/dynamic" "$c/wallpapers"
sudo install -d -o "$me" -g "$me" -m 0755 "$c/schemes/dynamic/$me"
sudo find "$c/schemes/dynamic/$me" -maxdepth 1 -type f -exec chown "$me:$me" {} +
[ -e "$c/wallpapers/$me" ] || sudo install -m 0644 /dev/null "$c/wallpapers/$me"
sudo chown -h "$me:$me" "$c/wallpapers/$me"
ok "login screen cache now writable by you ($c)"


say "2/11  Hardening (all four you picked)"
sudo install -Dm644 /dev/stdin /etc/sysctl.d/90-hardening.conf <<'EOF'
# 2026-11-10, see ~/.config/rice/pending/audit-fixes-20261110.sh
# Programs that aren't root no longer see kernel memory addresses (Ubuntu's default).
kernel.kptr_restrict = 1
# Nothing here uses kexec; stops anything swapping the running kernel (EAC wants this too).
kernel.kexec_load_disabled = 1
# A desktop is not a router.
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF
# LLMNR answers "who has this name?" from anyone on the network. mDNS stays.
sudo install -Dm644 /dev/stdin /etc/systemd/resolved.conf.d/10-no-llmnr.conf <<'EOF'
[Resolve]
LLMNR=no
EOF
sudo systemctl reload-or-restart systemd-resolved
ok "sysctl hardening + LLMNR off"


say "3/11  Memory and logs: zram half of RAM, journal capped at 500 MB"
sudo cp -n /etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf.pre-20261110 2>/dev/null
sudo install -Dm644 /dev/stdin /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
# Arch wiki values for swap on zram.
sudo install -Dm644 /dev/stdin /etc/sysctl.d/99-zram.conf <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
sudo sysctl --system >/dev/null
sudo install -Dm644 /dev/stdin /etc/systemd/journald.conf.d/10-size.conf <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-size=500M 2>&1 | tail -1
ok "zram grows to 8 GB after the reboot"


say "4/11  Services: printing on demand, grub-btrfsd off"
# disabling cups.service also unlinks cups.socket (Also=), so enable the socket again
sudo systemctl disable --now cups.service 2>/dev/null
sudo systemctl enable --now cups.socket
if systemctl list-unit-files grub-btrfsd.service >/dev/null 2>&1; then
    sudo systemctl disable --now grub-btrfsd.service 2>/dev/null
fi
ok "cups starts only when something prints; grub-btrfsd stopped"


say "5/11  Firewall: KDE Connect from your home network only"
for p in tcp udp; do
    if sudo ufw status | grep -qE "^1714:1764/$p +ALLOW( IN)? +Anywhere"; then
        sudo ufw delete allow "1714:1764/$p" >/dev/null
    fi
    sudo ufw allow from 192.168.1.0/24 to any port 1714:1764 proto "$p" comment 'KDE Connect, home LAN' >/dev/null
    sudo ufw allow from fe80::/10 to any port 1714:1764 proto "$p" comment 'KDE Connect, link-local IPv6' >/dev/null
done
sudo ufw status | grep 1714 | sed 's/^/   /'


say "6/11  Packages"
# CoolerControl: the -bin packages were deleted from the AUR; Arch's repo has 5.1.1.
# Download first, so the fans are only uncontrolled for a few seconds.
if pacman -Q coolercontrold-bin &>/dev/null; then
    if sudo pacman -Sw --needed coolercontrol coolercontrold; then
        sudo systemctl stop coolercontrold
        old=()
        for p in coolercontrol-bin coolercontrold-bin; do pacman -Q "$p" &>/dev/null && old+=("$p"); done
        sudo pacman -Rdd --noconfirm "${old[@]}"
        sudo pacman -S --noconfirm coolercontrol coolercontrold
        sudo systemctl daemon-reload
        sudo systemctl enable --now coolercontrold
        systemctl is-active --quiet coolercontrold && ok "CoolerControl now from the repo (profiles kept)" \
            || warn "coolercontrold did not start: run  systemctl status coolercontrold"
    fi
else
    ok "CoolerControl already from the repo"
fi
# Wanted on purpose: vet needs cargo, the headless test rigs need Xvfb.
sudo pacman -D --asexplicit rust xorg-server-xvfb >/dev/null 2>&1
gone=()
for p in samsung_magician-consumer-ssd linux-headers dotnet-sdk; do
    pacman -Q "$p" &>/dev/null && gone+=("$p")
done
mapfile -t orphans < <(pacman -Qdtq 2>/dev/null)
gone+=("${orphans[@]}")
if [ ${#gone[@]} -gt 0 ]; then
    echo "   Removing: ${gone[*]}"
    sudo pacman -Rns "${gone[@]}"
else
    ok "nothing left to remove"
fi
# For the vault (gocryptfs) and its Nautilus menu (nautilus-python).
sudo pacman -S --needed gocryptfs nautilus-python
# Weekly cache trim: keep 3 versions, drop packages that are no longer installed.
sudo install -Dm644 /dev/stdin /etc/systemd/system/paccache.service.d/uninstalled.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/paccache -r $PACCACHE_ARGS
ExecStart=/usr/bin/paccache -ruk0
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now paccache.timer
ok "weekly paccache timer on"
# Leftovers: old crash dumps (~380 MB) and lightdm's config folder (lightdm is gone).
sudo find /var/lib/systemd/coredump -maxdepth 1 -type f -name 'core.*' -delete
pacman -Q lightdm &>/dev/null || sudo rm -rf /etc/lightdm
ok "old crash dumps and /etc/lightdm removed"


say "7/11  Warning when Qt changes its minor version"
sudo install -Dm755 /dev/stdin /usr/local/bin/qt-bump-check <<'EOF'
#!/bin/sh
# pacman hook (zz-qt-bump.hook). Quiet on patch updates (6.12.1 -> 6.12.2); on a
# minor bump (6.12 -> 6.13) qtengine and caelestia-shell-git use Qt private API
# and must be rebuilt before the next login, or the shell and Qt theming break.
stamp=/var/lib/qt-bump-check/last
now=$(pacman -Q qt6-base | awk '{print $2}' | cut -d. -f1,2)
old=$(cat "$stamp" 2>/dev/null)
mkdir -p "${stamp%/*}" && echo "$now" > "$stamp"
[ -n "$old" ] && [ "$old" != "$now" ] || exit 0
printf '\n\033[1;31m  Qt %s -> %s: rebuild BEFORE you log out or reboot:\033[0m\n' "$old" "$now"
printf '\033[1;31m    paru -S --rebuild=yes qtengine\n    caelestia-update --rebuild\033[0m\n\n'
EOF
sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/zz-qt-bump.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = qt6-base

[Action]
Description = Checking whether Qt changed its minor version...
When = PostTransaction
Exec = /usr/local/bin/qt-bump-check
EOF
sudo /usr/local/bin/qt-bump-check   # records today's version, prints nothing
ok "Qt bump warning installed (Qt $(pacman -Q qt6-base | awk '{print $2}' | cut -d. -f1,2) recorded)"


say "8/11  Spotify 1.3.4 -> 1.3.8, then your theme back on"
cur=$(pacman -Q spotify 2>/dev/null | awk '{print $2}')
if [ -n "$cur" ] && [ "$(vercmp "$cur" 1:1.3.8)" -lt 0 ]; then
    wait_closed spotify "Spotify"
    if paru -S spotify; then
        spicetify -n restore backup apply && ok "Spotify updated, theme re-applied" \
            || warn "spicetify failed: run  spicetify -n restore backup apply"
    fi
else
    ok "Spotify is already current"
fi


say "9/11  Snapshots"
for cfg in root home; do
    if snapper -c "$cfg" list 2>/dev/null | grep -qE '^ *1 +│.*snapper repaired'; then
        sudo snapper -c "$cfg" delete 1 && ok "deleted $cfg snapshot #1 (2 Jul, no cleanup rule)"
    fi
done
echo "   The paru builds and the wallpaper cache deleted today still sit inside the"
echo "   older home snapshots, so the disk only gets that space back as they expire"
echo "   (up to 3 months). This cuts just those two cache folders out of every home"
echo "   snapshot; everything else in the snapshots stays."
if ask "Cut them out now?"; then
    sudo bash -s "$me" <<'ROOT'
me=$1
n=0
for s in /home/.snapshots/*/snapshot; do
    hit=()
    for d in "$s/$me/.cache/paru/clone" "$s/$me/.cache/caelestia/imagecache"; do
        [ -e "$d" ] && hit+=("$d")
    done
    [ ${#hit[@]} -eq 0 ] && continue
    btrfs property set -ts "$s" ro false || continue
    rm -rf "${hit[@]}"
    btrfs property set -ts "$s" ro true
    n=$((n + 1))
done
echo "   ✓ cleaned $n home snapshots (the space frees over the next minute)"
ROOT
fi


say "10/11  Krita AI (29 GB) -> NVMe"
src=~/.local/share/krita/ai_diffusion/server
dst=/mnt/nvme/@krita/server
if [ -L "$src" ]; then
    ok "already on the NVMe"
elif ! mountpoint -q /mnt/nvme; then
    warn "/mnt/nvme is not mounted, skipped"
elif [ -d "$src" ]; then
    wait_closed krita "Krita"
    while pgrep -f "ai_diffusion/server" >/dev/null; do
        warn "Krita's AI server is still running. Close it, then press Enter."
        read -r
    done
    [ -d /mnt/nvme/@krita ] || sudo btrfs subvolume create /mnt/nvme/@krita >/dev/null
    sudo chown "$me:$me" /mnt/nvme/@krita
    echo "   copying (a few minutes)..."
    rm -rf "$dst"
    if cp -a "$src" "$dst" && diff -rq --no-dereference "$src" "$dst" >/dev/null; then
        # The old copy is its own subvolume: deleting it is instant.
        if sudo btrfs subvolume delete "$src" >/dev/null 2>&1 || rm -rf "$src"; then
            ln -s "$dst" "$src"
            ok "moved and verified byte for byte; Krita still finds it at the old path"
        fi
    else
        warn "copy or verify failed; the original is untouched (tell Claude)"
        rm -rf "$dst"
    fi
fi


say "11/11  fstab: checksums + compression, /boot readable by root only"
# Applies at the reboot. Existing files keep their no-checksum flag until
# they are rewritten: Claude prepares a recopy script for the folders you pick.
new=$(mktemp)
sed -E -e '/^UUID=28f56239-c1cc-48cb-b9a8-d53f873be23c\s/ s/nodatasum,nodatacow,/compress=zstd:1,/' \
       -e '/^UUID=15A7-3073\s/ s/fmask=0022,dmask=0022/fmask=0077,dmask=0077/' /etc/fstab > "$new"
if cmp -s /etc/fstab "$new"; then
    ok "fstab already done"
else
    diff -u /etc/fstab "$new" | sed 's/^/   /'
    n=$(grep -c '^UUID=28f56239.*compress=zstd:1' "$new")
    if [ "$n" != 4 ] || ! grep -q '^UUID=15A7-3073.*fmask=0077,dmask=0077' "$new"; then
        warn "expected 4 btrfs lines + the /boot line, got something else: fstab left alone (tell Claude)"
    elif ! findmnt --verify --tab-file "$new" >/dev/null 2>&1; then
        findmnt --verify --tab-file "$new" | sed 's/^/   /'
        warn "findmnt found problems in the new fstab: left alone (tell Claude)"
    else
        sudo cp -a /etc/fstab /etc/fstab.pre-20261110
        sudo install -m644 "$new" /etc/fstab
        sudo systemctl daemon-reload
        ok "fstab updated (old one: /etc/fstab.pre-20261110)"
    fi
fi
rm -f "$new"

mv ~/.config/rice/pending/security-cleanup-20261029.sh ~/.config/rice/pending/security-cleanup-20261029.sh.superseded 2>/dev/null
mv ~/.config/rice/pending/system-tidy-20261010.sh ~/.config/rice/pending/system-tidy-20261010.sh.superseded 2>/dev/null

say "Done. Reboot when it suits you (not mid-game)."
echo "   Then tell Claude, and it checks everything and continues with the vault."
