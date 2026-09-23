# VPN (kernel WireGuard)

Replaces the official Surfshark client, which **cannot work on this machine**.

## Why the Surfshark app failed

`surfshark-client` is a NetworkManager front-end. Its daemon talks to
`org.freedesktop.NetworkManager` over D-Bus, and its own bundled diagnostics
script collects `nmcli`, NM polkit actions and `/etc/NetworkManager/`.

This box runs **iwd + systemd-networkd + systemd-resolved**, and NetworkManager
has never started on it — `journalctl -u NetworkManager` is empty across every
boot, even though the package got pulled in as a Surfshark dependency. So
`surfsharkd` dies at startup with:

```
Gio.DBusError: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown:
The name is not activatable
```

Enabling NetworkManager would mean moving `enp37s0` off systemd-networkd and
letting NM drive iwd, which puts it in direct conflict with the ControlCenter's
Wi-Fi page. Kernel WireGuard needs none of that, and is faster besides.

## Install (once)

```bash
sudo bash ~/.config/rice/vpn/install.sh
```

Installs `wireguard-tools` + `systemd-resolvconf`, the `vpnctl` root helper, and
a single sudoers line so the desktop toggle never prompts for a password.

`systemd-resolvconf` is not optional: `wg-quick` shells out to `resolvconf` for
the `DNS =` line in a config, and without it `wg-quick up` fails outright.

## Add tunnels

1. <https://my.surfshark.com> → VPN → Manual setup → WireGuard
2. Generate a key pair, download a `.conf` per location you want
3. `sudo bash ~/.config/rice/vpn/import.sh ~/Downloads/*.conf`

`import.sh` trims `de-fra.prod.surfshark.com.conf` down to the tunnel `de-fra`
and annotates it with `# label: Frankfurt` / `# country: DE`, which is what the
ControlCenter renders. Edit those two comments to rename anything.

## Use

| Where | What |
|---|---|
| ControlCenter → VPN tile | toggle; opens the locations page |
| VPN page | locations sorted by measured latency, kill switch, connect-at-boot |
| `SUPER + SHIFT + P` | toggle the last-used tunnel |
| `SUPER + SHIFT + N` | network doctor — reports the first broken hop |
| `qs ipc call control page vpn` | jump straight to the page |
| `vpn.sh status\|list\|up\|down\|toggle` | the same thing from a shell |

## Design notes

- **Everything privileged goes through `vpnctl`**, one root binary behind one
  sudoers line, rather than a blanket grant over `wg-quick`/`nft`/`systemctl`.
  `wg show` needs root too, which is why even status reads route through it.
- **Kill switch** is an nftables table (`inet vpnkill`) with a drop policy on
  output, pinholed for loopback, the LAN, DHCP and the single UDP endpoint. It
  is applied *before* `wg-quick up` — otherwise the handshake is the thing that
  gets dropped — and torn down again if the tunnel fails to come up, so a bad
  config cannot strand the machine offline.
- **DNS** is forced onto the tunnel with `resolvectl domain <if> "~."` so
  queries cannot leak back to the LAN resolver via split-horizon.
- **A stalled tunnel is not shown as "on".** WireGuard is silent when idle, but
  no handshake for >180 s means it is up in name only; the tile and the doctor
  both report that as a fault.
