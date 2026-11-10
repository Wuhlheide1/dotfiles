"""Helper for ~/.local/bin/vault (run with python3 -I).

  nautilus-in-vault MNT       exit 0 if a Nautilus window/tab shows a folder in MNT
  show MNT                    open MNT in Nautilus
  scrub MNT [PATH...]         drop thumbnails + recent-file entries under MNT (and PATHs)
  forget-old MNT PATH...      after PATH moved into the vault: cut its old plain copies
                              out of home snapshots and restic, then scrub them
  watch MNT VAULT             the event watcher (vault-watch.service), no polling:
                                logind PrepareForSleep  -> lock (holds a delay inhibitor)
                                Hyprland closewindow    -> `vault check` (lock if unused)
                                Nautilus OpenLocations  -> prompt when you enter the locked
                                                           vault; check when you leave it
                                mount table change      -> scrub after gocryptfs' idle unmount
"""

import os
import re
import socket
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

HOME = Path.home()
NAUTILUS = "org.gnome.Nautilus"
FM_PATH = "/org/freedesktop/FileManager1"
FM_IFACE = "org.freedesktop.FileManager1"


def uri(path: str | Path) -> str:
    """The URI GLib apps write for a path (same escaping as thumbnails/recent files)."""
    return Gio.File.new_for_path(str(path)).get_uri()


def under(u: str, prefixes: list[str]) -> bool:
    return any(u == p or u.startswith(p.rstrip("/") + "/") for p in prefixes)


# --- Nautilus -------------------------------------------------------------------

def nautilus_locations(bus) -> list[str]:
    """OpenLocations of a running Nautilus; never starts one."""
    owner = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                          "NameHasOwner", GLib.Variant("(s)", (NAUTILUS,)), None, 0, 1000, None)
    if not owner.unpack()[0]:
        return []
    try:
        v = bus.call_sync(NAUTILUS, FM_PATH, "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", (FM_IFACE, "OpenLocations")), None, 0, 1000, None)
        return list(v.unpack()[0])
    except GLib.Error:
        return []


def cmd_nautilus_in_vault(mnt: str) -> int:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    return 0 if any(under(u, [uri(mnt)]) for u in nautilus_locations(bus)) else 1


def cmd_show(mnt: str) -> int:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    bus.call_sync(NAUTILUS, FM_PATH, FM_IFACE, "ShowFolders",
                  GLib.Variant("(ass)", ([uri(mnt)], "")), None, 0, 5000, None)
    return 0


# --- scrub: thumbnails + recently-used.xbel ---------------------------------------

def thumb_uri(head: bytes) -> bytes | None:
    """Thumb::URI from a PNG's tEXt chunks (walks the chunks; no PIL needed)."""
    if not head.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    pos = 8
    while pos + 8 <= len(head):
        length = int.from_bytes(head[pos:pos + 4], "big")
        kind = head[pos + 4:pos + 8]
        data = head[pos + 8:pos + 8 + length]
        if kind == b"tEXt" and data.startswith(b"Thumb::URI\x00"):
            return data[11:]
        if kind == b"IDAT":
            return None
        pos += 12 + length
    return None


def scrub(prefixes: list[str]) -> tuple[int, int]:
    """Delete freedesktop thumbnails and GTK recent-file entries for URIs under prefixes."""
    keys = [p.encode() for p in prefixes]
    thumbs = 0
    root = HOME / ".cache/thumbnails"
    if root.is_dir():
        for png in root.rglob("*.png"):
            try:
                with open(png, "rb") as f:
                    head = f.read(8192)
            except OSError:
                continue
            u = thumb_uri(head)
            if u and any(u == k or u.startswith(k.rstrip(b"/") + b"/") for k in keys):
                png.unlink(missing_ok=True)
                thumbs += 1
    recent = 0
    xbel = HOME / ".local/share/recently-used.xbel"
    if xbel.is_file():
        text = xbel.read_text(errors="surrogateescape")
        pat = re.compile(r'[ \t]*<bookmark href="([^"]*)".*?</bookmark>\n?', re.S)

        def keep(m):
            nonlocal recent
            if under(m.group(1), prefixes):
                recent += 1
                return ""
            return m.group(0)

        new = pat.sub(keep, text)
        if recent:
            tmp = xbel.with_name(".recently-used.xbel.vault-tmp")
            tmp.write_text(new, errors="surrogateescape")
            os.replace(tmp, xbel)
    return thumbs, recent


def cmd_scrub(mnt: str, *paths: str) -> int:
    t, r = scrub([uri(mnt), *(uri(p) for p in paths)])
    print(f"removed {t} thumbnails, {r} recent-file entries")
    return 0


# --- forget-old ---------------------------------------------------------------------

SNAPSHOT_CUT = r"""
set -u
n=0
for s in /home/.snapshots/*/snapshot; do
    hit=()
    for rel in "$@"; do [ -e "$s/$rel" ] || [ -L "$s/$rel" ] && hit+=("$s/$rel"); done
    [ ${#hit[@]} -eq 0 ] && continue
    btrfs property set -ts "$s" ro false || continue
    rm -rf -- "${hit[@]}"
    btrfs property set -ts "$s" ro true
    n=$((n + 1))
done
echo "   home snapshots cleaned: $n"
"""


def cmd_forget_old(mnt: str, *paths: str) -> int:
    if not paths:
        print("usage: vault forget-old PATH...   (paths you moved into ~/.vault)")
        return 2
    absps = []
    for p in paths:
        a = Path(os.path.abspath(os.path.expanduser(p)))
        if not str(a).startswith(str(HOME) + "/"):
            print(f"{a}: not in your home folder")
            return 2
        if a.exists() or a.is_symlink():
            print(f"{a} still exists: move it into {mnt} first")
            return 2
        absps.append(a)
    print("Cutting the old plain copies out of history:")
    for a in absps:
        print(f"   {a}")
    rels = [str(a.relative_to("/home")) for a in absps]
    print("1. home snapshots (needs sudo)")
    subprocess.run(["sudo", "bash", "-c", SNAPSHOT_CUT, "snapshot-cut", *rels])

    print("2. restic backups")
    if os.path.ismount("/mnt/shared"):
        env = {**os.environ, "RESTIC_REPOSITORY": "/mnt/shared/backups/restic",
               "RESTIC_PASSWORD_FILE": str(HOME / ".config/restic/password")}
        ex = [arg for a in absps for arg in ("--exclude", str(a))]
        r = subprocess.run(["restic", "rewrite", "--forget", *ex], env=env)
        if r.returncode == 0:
            subprocess.run(["restic", "prune"], env=env)
    else:
        print("   /mnt/shared is not mounted: run this again when it is")

    print("3. thumbnails and recent files")
    t, r = scrub([uri(a) for a in absps])
    print(f"   removed {t} thumbnails, {r} recent-file entries")
    if any(a.is_relative_to(HOME / "Pictures") for a in absps):
        # Caelestia keeps resized copies of every wallpaper it has shown, named by hash.
        for c in (HOME / ".cache/caelestia/imagecache", HOME / ".cache/caelestia/wallpapers"):
            subprocess.run(["rm", "-rf", "--", str(c)])
        print("   cleared Caelestia's wallpaper caches (they refill on their own)")
    return 0


# --- watch ----------------------------------------------------------------------------

def cmd_watch(mnt: str, vault: str) -> int:
    loop = GLib.MainLoop()
    session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    vault_uri = uri(mnt)
    state = {"mounted": os.path.ismount(mnt), "in_vault": False, "prompting": False, "inhibit": None}

    def run(*args: str) -> None:
        subprocess.Popen([vault, *args], stdin=subprocess.DEVNULL, start_new_session=True)

    def check_later(ms: int) -> None:
        GLib.timeout_add(ms, lambda: (run("check"), False)[1])

    # logind: lock before sleep. A delay inhibitor makes logind wait for us.
    def take_inhibitor() -> None:
        try:
            res, fds = system.call_with_unix_fd_list_sync(
                "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager",
                "Inhibit", GLib.Variant("(ssss)", ("sleep", "vault", "Lock the vault before sleeping", "delay")),
                GLib.VariantType("(h)"), 0, -1, None, None)
            # steal: the list must not keep its own copy open, or logind waits the full delay
            state["inhibit"] = fds.steal_fds()[res.unpack()[0]]
        except GLib.Error as e:
            print(f"no sleep inhibitor: {e.message}", file=sys.stderr)

    def on_sleep(_c, _s, _p, _i, _m, params) -> None:
        if params.unpack()[0]:
            if os.path.ismount(mnt):
                subprocess.run([vault, "lock", "--quiet"], stdin=subprocess.DEVNULL, timeout=20)
            if state["inhibit"] is not None:
                os.close(state["inhibit"])
                state["inhibit"] = None
        else:
            take_inhibitor()

    take_inhibitor()
    system.signal_subscribe("org.freedesktop.login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                            "/org/freedesktop/login1", None, Gio.DBusSignalFlags.NONE, on_sleep)

    # Nautilus: prompt when a window enters the locked vault; check when it leaves.
    def prompt_done(_pid, _status) -> None:
        state["prompting"] = False

    def on_locations(_c, _s, _p, _i, _m, params) -> None:
        iface, changed, _inv = params.unpack()
        if iface != FM_IFACE or "OpenLocations" not in changed:
            return
        inside = any(under(u, [vault_uri]) for u in changed["OpenLocations"])
        entering = inside and not state["in_vault"]
        state["in_vault"] = inside
        if inside and os.path.ismount(mnt):
            run("seen")
        elif entering and not state["prompting"]:
            state["prompting"] = True
            p = subprocess.Popen([vault, "open", "--gui", "--show"], stdin=subprocess.DEVNULL,
                                 start_new_session=True)
            GLib.child_watch_add(GLib.PRIORITY_DEFAULT, p.pid, prompt_done)
        if not inside:
            run("check")

    session.signal_subscribe(None, "org.freedesktop.DBus.Properties", "PropertiesChanged", FM_PATH,
                             None, Gio.DBusSignalFlags.NONE, on_locations)

    # Hyprland: a closed window may have been the last user (a terminal's shell
    # exits a moment after its window), so check now-ish and once more after.
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    rt = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if sig:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(f"{rt}/hypr/{sig}/.socket2.sock")
            buf = b""

            def on_hypr(_fd, cond) -> bool:
                nonlocal buf
                if cond & (GLib.IO_HUP | GLib.IO_ERR):
                    loop.quit()        # Hyprland is gone; systemd restarts us with the session
                    return False
                data = sock.recv(65536)
                if not data:
                    loop.quit()
                    return False
                buf += data
                *lines, buf = buf.split(b"\n")
                if os.path.ismount(mnt) and any(l.startswith(b"closewindow>>") for l in lines):
                    check_later(800)
                    check_later(3000)
                return True

            GLib.io_add_watch(sock.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_hypr)
        except OSError as e:
            print(f"no Hyprland events: {e}", file=sys.stderr)

    # Mount table: notice gocryptfs' own idle unmount and clean up after it.
    try:
        gi.require_version("GioUnix", "2.0")
        from gi.repository import GioUnix
        monitor = GioUnix.MountMonitor.get()
    except (ImportError, ValueError, AttributeError):
        monitor = Gio.UnixMountMonitor.get()

    def on_mounts(_m) -> None:
        now = os.path.ismount(mnt)
        if state["mounted"] and not now:
            subprocess.run([sys.executable, "-I", __file__, "scrub", mnt], stdout=subprocess.DEVNULL)
            Path(rt, "vault/seen").unlink(missing_ok=True)
        state["mounted"] = now

    monitor.connect("mounts-changed", on_mounts)
    loop.run()
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cmd, mnt, *rest = sys.argv[1:]
    return {
        "nautilus-in-vault": cmd_nautilus_in_vault,
        "show": cmd_show,
        "scrub": cmd_scrub,
        "forget-old": cmd_forget_old,
        "watch": cmd_watch,
    }[cmd](mnt, *rest)


if __name__ == "__main__":
    sys.exit(main())
