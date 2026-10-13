#!/usr/bin/env bash
# One-off finishing steps from 2026-10-13 - everything that needs sudo or
# needs Brave closed. Run it in a kitty window (NOT with sudo in front):
#     bash ~/.config/rice/pending/finish-setup.sh
# Each step explains itself and asks first; re-running is harmless.
set -uo pipefail

ask() { read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

wait_for_brave_closed() {
    if pgrep -f '/opt/brave' >/dev/null; then
        say "Close Brave completely (all windows), then press Enter."
        read -r
        while pgrep -f '/opt/brave' >/dev/null; do sleep 1; done
    fi
}

sudo -v || exit 1   # ask for the password once, up front

# 1 ---------------------------------------------------------------------------
say "1. Brave toolbar: theme extension instead of the admin policy"
cat <<'EOF'
   Caelestia currently themes Brave through /etc/brave/policies/managed/
   caelestia.json. That needs sudo on every wallpaper change, so it only
   updates when sudo happens to be cached, and it paints the active vertical
   tab tile backwards. The theme extension needs no sudo and gets the tabs
   right; a new palette shows after Brave restarts.
EOF
if ask "   Switch to the theme extension?"; then
    wait_for_brave_closed
    sudo rm -f /etc/brave/policies/managed/caelestia.json
    python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".config/caelestia/cli.json"
d = json.loads(p.read_text())
d.setdefault("theme", {})["enableChromium"] = False
p.write_text(json.dumps(d, indent=4) + "\n")
PY
    flag="--load-extension=$HOME/.local/share/caelestia-brave-theme"
    grep -qxF -- "$flag" ~/.config/brave-flags.conf 2>/dev/null || {
        printf '\n# Caelestia theme (manifest re-rendered on every scheme change;\n# Brave reads it at startup).\n%s\n' "$flag" >> ~/.config/brave-flags.conf
    }
    echo "   done."
fi

# 2 ---------------------------------------------------------------------------
say "2. Brave new tab page shows the current wallpaper"
cat <<'EOF'
   If you already uploaded a picture under Customize > Background image, that
   slot is kept and simply gets replaced by each new wallpaper.
EOF
if ask "   Turn it on?"; then
    wait_for_brave_closed
    python3 - <<'PY'
import json, pathlib
prefs = pathlib.Path.home() / ".config/BraveSoftware/Brave-Browser/Default/Preferences"
d = json.loads(prefs.read_text())
ntp = d.setdefault("brave", {}).setdefault("new_tab_page", {})
bg = ntp.get("background", {})
if bg.get("type") == "custom_image" and bg.get("selected_value"):
    print("   keeping your uploaded slot:", bg["selected_value"])
else:
    ntp["background"] = {"type": "custom_image", "selected_value": "caelestia.png", "random": False}
    lst = ntp.setdefault("custom_background_image_list", [])
    if "caelestia.png" not in lst:
        lst.append("caelestia.png")
ntp["show_background_image"] = True
prefs.write_text(json.dumps(d, separators=(",", ":")))
PY
    S=~/.local/state/caelestia/scheme.json
    SCHEME_COLOURS="$(jq -c .colours "$S")" SCHEME_MODE="$(jq -r .mode "$S")" \
        python3 ~/.config/caelestia/hooks/theme-post.py --background
    echo "   done."
fi

# 3 ---------------------------------------------------------------------------
say "3. Hide the Windows partitions from Nautilus / file pickers"
cat <<'EOF'
   The Windows C: drive shows as "1.5 TB Volume" in every file-manager
   sidebar; one click mounts it, which is risky while Windows is hibernated
   (Fast Startup). Hides the Windows system, recovery and EFI partitions on
   the NVMe from udisks. /mnt/shared and /mnt/nvme are unaffected.
EOF
if ask "   Hide them?"; then
    sudo tee /etc/udev/rules.d/99-hide-windows-partitions.rules >/dev/null <<'EOF'
# Keep the Windows install out of file-manager sidebars (udisks2).
# NVMe only, matched by partition type: Microsoft basic data (C:), Windows
# recovery, EFI system. The Linux half (nvme0n1p4, btrfs) is not matched.
SUBSYSTEM=="block", KERNEL=="nvme0n1p[0-9]*", ENV{ID_PART_ENTRY_TYPE}=="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7", ENV{UDISKS_IGNORE}="1"
SUBSYSTEM=="block", KERNEL=="nvme0n1p[0-9]*", ENV{ID_PART_ENTRY_TYPE}=="de94bba4-06d1-4d40-a16a-bfd50179d6ac", ENV{UDISKS_IGNORE}="1"
SUBSYSTEM=="block", KERNEL=="nvme0n1p[0-9]*", ENV{ID_PART_ENTRY_TYPE}=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b", ENV{UDISKS_IGNORE}="1"
EOF
    sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=block
    echo "   done."
fi

# 4 ---------------------------------------------------------------------------
say "4. WireGuard: re-import the Surfshark tunnels"
cat <<'EOF'
   Five of the eight tunnels (at-vie, jp-tok, uk-edi, uk-lon, us-nyc) were
   installed while their config still had Surfshark's "<insert key>"
   placeholder, so they can't connect. The fixed files are in ~/Downloads.
   Re-importing replaces each tunnel; afterwards the ~/Downloads copies (they
   contain your private key) are deleted - /etc/wireguard keeps root-only ones.
EOF
confs=(~/Downloads/{at-vie,de-ber,de-fra,jp-tok,lu-ste,uk-edi,uk-lon,us-nyc}.conf)
if ls "${confs[@]}" >/dev/null 2>&1 && ask "   Re-import all 8?"; then
    if grep -l 'insert' "${confs[@]}"; then
        echo "   ^ these still have a placeholder key - skipping the import."
    else
        sudo bash ~/.config/rice/vpn/import.sh "${confs[@]}" && {
            shred -u "${confs[@]}" 2>/dev/null || rm -f "${confs[@]}"
            echo "   done. Test one: sudo -n vpnctl up de-fra && sudo -n vpnctl status"
        }
    fi
fi

# 5 ---------------------------------------------------------------------------
say "5. Boot splash"
cat <<'EOF'
   Plymouth is installed and in the initramfs, but your kernel command line
   (/etc/kernel/cmdline, baked into the UKI) never had "splash", so it never
   showed. This installs a theme that continues the rEFInd look (the Arch
   triangle on near-black, a slim blue spinner), uses the same triangle for
   the boot-stub splash before it, adds "quiet splash loglevel=3", makes
   greetd wait for the splash to finish, and rebuilds the UKI.
   Undo: restore the two .pre-splash-bak files and run sudo mkinitcpio -P.
   The fallback UKI and GRUB stay untouched if anything goes wrong.
EOF
if ask "   Install it?"; then
    src=~/.config/rice/plymouth/caelestia-boot
    sudo install -d /usr/share/plymouth/themes/caelestia-boot /usr/local/share/caelestia-boot
    sudo install -m644 "$src"/*.png "$src"/caelestia-boot.plymouth /usr/share/plymouth/themes/caelestia-boot/
    sudo install -m644 "$src"/stub-splash.bmp /usr/local/share/caelestia-boot/
    sudo plymouth-set-default-theme caelestia-boot

    sudo cp -n /etc/kernel/cmdline /etc/kernel/cmdline.pre-splash-bak
    grep -qw splash /etc/kernel/cmdline || sudo sed -i '1s/$/ quiet splash loglevel=3/' /etc/kernel/cmdline
    echo "   cmdline: $(cat /etc/kernel/cmdline)"

    preset=/etc/mkinitcpio.d/linux-zen.preset
    sudo cp -n "$preset" "$preset.pre-splash-bak"
    sudo sed -i 's|--splash /usr/share/systemd/bootctl/splash-arch.bmp|--splash /usr/local/share/caelestia-boot/stub-splash.bmp|' "$preset"

    sudo install -Dm644 /dev/stdin /etc/systemd/system/greetd.service.d/plymouth.conf <<'EOF'
# Start the greeter only after the boot splash has handed the screen back,
# so tuigreet never draws underneath or on top of plymouth.
[Unit]
After=plymouth-quit-wait.service
EOF
    sudo systemctl daemon-reload
    sudo mkinitcpio -P && echo "   done - you'll see it on the next boot."
fi

# 6 ---------------------------------------------------------------------------
say "6. nvim: language servers + tree-sitter (optional)"
cat <<'EOF'
   lua-language-server  - completion/diagnostics for your Hyprland Lua config
   bash-language-server - for the scripts in ~/.local/bin
   tree-sitter-cli      - lets nvim build parsers for fish, toml, json, css,
                          qml, python... (highlighting beyond c/lua/markdown)
EOF
if ask "   Install them?"; then
    sudo pacman -S --needed lua-language-server bash-language-server tree-sitter-cli
fi

say "All done. You can delete this script: rm ~/.config/rice/pending/finish-setup.sh"
