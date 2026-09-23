# Manual Arch install on a T2 MacBook (dual-boot, keep macOS)

Companion to **[touchbar-mac.md](touchbar-mac.md)**. This is the hand install
to fall back on when `t2archinstall` fails. Source of truth for anything not
here: <https://wiki.t2linux.org/distributions/arch/installation/> and its FAQ.

Disk assumed: `/dev/nvme0n1` (T2 Macs present the internal SSD as NVMe once the
T2 kernel is up). **Check the real name with `lsblk` first** — never paste a
device path blind.

---

## 0. Before you boot anything

These are one-time macOS-side settings. If `t2archinstall` already booted, they
are already done — skip.

1. **Startup Security Utility** (⌘-R at power-on → Utilities → Startup Security
   Utility, authenticate):
   - Secure Boot → **No Security**
   - Allowed Boot Media → **Allow booting from external or removable media**
2. **FileVault off** (System Settings → Privacy & Security) if it was ever on —
   otherwise the macOS container is encrypted and resizing/reading it is a pain.
3. Use the **T2 ISO**, not vanilla Arch: grab the latest release from
   <https://github.com/t2linux/archiso-t2/releases> (named after the kernel
   version). The vanilla Arch ISO has no working internal keyboard/trackpad/Wi-Fi
   on a T2 — the T2 ISO ships the patched kernel + `apple-bce`.
4. Flash it (from macOS: `sudo dd if=archiso-t2-*.iso of=/dev/rdiskX bs=1m`, or
   balenaEtcher which you already have).
5. Boot it: power on holding **⌥ (Option)**, pick the **orange "EFI Boot"** entry.

---

## 1. Live environment: get online + look at the disk FIRST

```sh
# keyboard layout if not US:
loadkeys de          # or whatever

# --- Wi-Fi (T2 firmware is on the ISO) ---
iwctl
    device list
    station wlan0 scan
    station wlan0 get-networks
    station wlan0 connect "SSID"
    exit
ping -c2 archlinux.org
```

Wi-Fi in the T2 installer is sometimes flaky. **Reliable fallback:** USB-C
Ethernet, or plug in a phone and USB-tether (shows up as a wired device).

**Now inspect what's actually on the disk before touching it:**

```sh
lsblk -f                       # names, filesystems, sizes, mountpoints
fdisk -l /dev/nvme0n1          # partition table
parted /dev/nvme0n1 print      # sizes + flags
```

You are reconciling this against what you did earlier:
- 1 TB split in macOS into ~400 GB (macOS) + ~600 GB (Arch)
- the failed install script tried to carve a 1 GB boot partition out of the Arch side

### What a healthy layout looks like

| Partition | Size | FS | What it is | Touch it? |
|---|---|---|---|---|
| `nvme0n1p1` | ~200–300 MB | vfat | **macOS EFI (ESP)** | ❌ leave alone |
| `nvme0n1p2` | ~400 GB | apfs | **macOS** | ❌ leave alone |
| `nvme0n1p3` | ~1 GB | vfat/empty | **Linux ESP** (the script's "boot") | ✅ format vfat |
| `nvme0n1p4` | ~599 GB | empty | **Linux root** | ✅ format ext4 |

(There may also be a small Apple recovery partition — leave it alone too.)

### Three cases

- **Both p3 (1 GB) and p4 (~599 GB) already exist** → the script's work carried
  over. Skip to §2, just reformat them.
- **Only a single ~600 GB empty region exists** → the 1 GB split did NOT survive.
  Create the two partitions inside that free space (see below).
- **You see macOS's 200 MB ESP and want to reuse it instead of a 1 GB one** →
  possible, but the macOS ESP is small and the T2 `linux-t2` initramfs is large
  (kernel + initramfs live on the ESP here). A dedicated ~1 GB ESP is why the
  script made one. Recommended: keep the separate 1 GB ESP.

### Creating the two Linux partitions (only if they're missing)

⚠️ **Do not delete, resize, or reformat p1 (EFI) or the ~400 GB APFS/macOS
partition. That destroys macOS.** You are only working inside the free 600 GB.

```sh
gdisk /dev/nvme0n1
    p                # print — confirm the free region and that macOS parts are intact
    n                # new partition -> the 1 GB ESP
        <enter>      # default first sector (start of free space)
        +1G
        ef00         # type: EFI System
    n                # new partition -> root
        <enter>
        <enter>      # use the rest
        8300         # type: Linux filesystem
    p                # sanity check
    w                # write (asks to confirm)
```

---

## 2. Format + mount

Substitute the real partition numbers you confirmed above.

```sh
mkfs.fat -F32 /dev/nvme0n1p3            # Linux ESP  (the ~1 GB one)
mkfs.ext4     /dev/nvme0n1p4            # Linux root (~599 GB)

mount /dev/nvme0n1p4 /mnt
mount --mkdir /dev/nvme0n1p3 /mnt/boot # kernel+initramfs live on the ESP here
```

**Never run mkfs on p1 or the APFS partition.**

(ext4 is the boring, reliable choice. btrfs works too if you want snapshots —
its own guide, not covered here.)

---

## 3. Install the base system (this is the T2-specific part)

The T2 ISO already has the `arch-mact2` (t2linux) pacman repo enabled, so
`pacstrap` can pull the patched kernel directly:

```sh
pacstrap /mnt \
  base base-devel linux-t2 linux-t2-headers linux-firmware \
  arch-mact2-mirrorlist arch-mact2-rankmirrors \
  apple-t2-audio-config apple-bcm-firmware \
  intel-ucode grub efibootmgr iwd t2fanrd \
  sudo vim git networkmanager
```

- `linux-t2` — the patched kernel (apple-bce for keyboard/trackpad/audio/Touch
  Bar/Wi-Fi). **Do not** also install stock `linux`.
- `apple-bcm-firmware` — Wi-Fi/Bluetooth firmware (no more extracting from
  macOS like the old guides).
- `apple-t2-audio-config` — internal speaker/mic ALSA UCM profile.
- `t2fanrd` — fan control daemon (the T2 doesn't manage fans for Linux).
- `iwd` — matches the rice's ControlCenter Wi-Fi page. `networkmanager` is
  included as an easy first-boot fallback; pick one to enable in §4.

Generate fstab:

```sh
genfstab -U /mnt >> /mnt/etc/fstab
```

---

## 4. Configure inside chroot

```sh
arch-chroot /mnt

# --- persist the t2 repo so you can update the kernel later ---
# append to /etc/pacman.conf:
cat >> /etc/pacman.conf <<'EOF'

[arch-mact2]
Include = /etc/pacman.d/arch-mact2-mirrorlist
SigLevel = Never
EOF

# --- time / locale / hostname ---
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc
sed -i 's/^#\(en_US.UTF-8\)/\1/; s/^#\(de_DE.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'macbook' > /etc/hostname
printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\tmacbook\n' > /etc/hosts

# --- root password + your user ---
passwd
useradd -mG wheel wuhlheide
passwd wuhlheide
EDITOR=vim visudo          # uncomment: %wheel ALL=(ALL:ALL) ALL

# --- services ---
systemctl enable t2fanrd
systemctl enable iwd.service          # OR: systemctl enable NetworkManager
systemctl enable bluetooth.service
```

### Bootloader (GRUB, EFI, removable so the Mac picker finds it)

```sh
# add the T2 kernel params
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="intel_iommu=on iommu=pt pm_async=off"|' /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg
```

`intel_iommu=on iommu=pt pm_async=off` are **required** on T2 — without them the
Wi-Fi/USB bridge misbehaves and boot can hang.

```sh
exit                 # leave chroot
umount -R /mnt
reboot
```

Pull the USB. At the boot chime hold **⌥**, pick **EFI Boot** (GRUB). macOS is
still the plain "Macintosh HD" entry — so you keep dual boot. (To make GRUB the
default without holding Option, set it later with `bless` from macOS or just
keep holding ⌥ — most people leave it.)

---

## 5. First boot sanity checks

```sh
uname -r                       # should say ...-t2
sudo dmesg | grep -i apple_bce # driver loaded?
ip link                        # wlanX present?
iwctl                          # reconnect Wi-Fi on the installed system
```

If **suspend** misbehaves (common on T2), see the wiki FAQ — usually a
`mem_sleep_default` / `hid_apple` tweak. If **audio** is silent, confirm
`apple-t2-audio-config` is installed and unmute in `alsamixer`.

Touch Bar: install `tiny-dfr` (AUR) once online and enable its service — gives
you a function-key + brightness/volume strip. See touchbar-mac.md §2.

---

## 6. Transfer the rice

Base desktop first, T2 quirks second. Two ways to get the dotfiles over:

### A. Git bare repo (preferred — it's already on GitHub)

```sh
# after §1–5, logged in as your user, online:
sudo pacman -S --needed git
git clone --bare https://github.com/Wuhlheide1/dotfiles.git $HOME/.dotfiles
alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
dot checkout                   # if it complains about existing files, back them up / rm them
dot config status.showUntrackedFiles no
bash ~/.config/rice/install.sh
```

### B. Tarball fallback (offline)

On this desktop: `bash ~/.config/rice/export.sh` → copy `rice-*.tar.gz` to the
Mac → `tar xzf rice-*.tar.gz -C ~` → `bash ~/.config/rice/install.sh`.

`install.sh` installs repo + AUR packages, bootstraps paru, enables the
quickshell/wallpaper services, masks dunst. It does **not** touch the kernel, so
it's safe over the T2 base.

### Then adjust for laptop hardware (see README.md "HARDWARE NOTES")

- `~/.config/hypr/monitors.lua` — replace `DP-2`/`HDMI-A-1` with the single
  internal panel (`eDP-1`). `wlr-randr` / `hyprctl monitors` shows the name.
- `~/.config/hypr/windowsAndWorkspaces.lua` — drop the DP-2/HDMI workspace split;
  put all workspaces on the one output.
- **Brightness**: desktop fakes it via hyprsunset gamma. The MacBook has a real
  backlight — rebind brightness keys to `brightnessctl`. hyprsunset is a gamma
  backend ONLY (temperature pinned neutral at 6500K in autostart.lua).
  (Annotate the new binds in keybinds.lua — SUPER+K parses it.)
- **Fan/temp tile** in ControlCenter reads desktop hwmon names (`k10temp`,
  `amdgpu`); on the Mac these are different (`applesmc`, `coretemp`) — adjust or
  hide.
- Skip `coolercontrol-bin` (already marked desktop-only in packages-aur.txt).
- GPU: 15"/16" T2 have an AMD dGPU (`amdgpu`, great on Wayland); Air/13" are
  Intel-only. Either works with Hyprland — no extra config normally needed.

Drop a few images in `~/images/wallpapers`, start Hyprland; login shuffles a
wallpaper and matugen themes the accents. No manual theming step.
